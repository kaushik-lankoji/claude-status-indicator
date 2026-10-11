#!/usr/bin/env python3
"""Trust Codex hooks whose command contains a given string.

Codex won't run a hook until its hash is trusted. This does what the Trust button
in Codex does: it asks the Codex app-server for each hook's key and hash, then saves
them with the same config write the app uses (hooks.state in ~/.codex/config.toml).
Only hooks matching the given string are touched.

Usage: codex-trust.py <command-substring>
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import queue

APP_CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex"


def find_codex():
    if os.access(APP_CODEX, os.X_OK):
        return APP_CODEX
    return shutil.which("codex")


class Client:
    def __init__(self, binary):
        self.proc = subprocess.Popen([binary, "app-server"], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.next_id = 0

    def _read(self):
        for line in self.proc.stdout:
            try:
                self.lines.put(json.loads(line))
            except ValueError:
                pass

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def call(self, method, params, timeout=20):
        self.next_id += 1
        self.send({"id": self.next_id, "method": method, "params": params})
        while True:
            try:
                reply = self.lines.get(timeout=timeout)
            except queue.Empty:
                raise SystemExit(f"codex-trust: timed out waiting for {method}")
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise SystemExit(f"codex-trust: {method} failed: {reply['error']}")
                return reply["result"]

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


def matching_hooks(client, needle):
    result = client.call("hooks/list", {"cwds": [os.path.expanduser("~")]})
    hooks = [h for entry in result["data"] for h in entry["hooks"]]
    return [h for h in hooks if needle in (h.get("command") or "")]


def main():
    if len(sys.argv) != 2 or not sys.argv[1]:
        raise SystemExit(__doc__)
    needle = sys.argv[1]
    binary = find_codex()
    if not binary:
        raise SystemExit("codex-trust: Codex not found")

    client = Client(binary)
    try:
        client.call("initialize", {"clientInfo": {"name": "claude-island", "version": "1"}})
        client.send({"method": "initialized"})

        hooks = matching_hooks(client, needle)
        if not hooks:
            raise SystemExit(f"codex-trust: no Codex hooks match {needle!r}")

        state = {h["key"]: {"trusted_hash": h["currentHash"]}
                 for h in hooks if h.get("trustStatus") != "trusted"}
        if state:
            client.call("config/batchWrite", {
                "edits": [{"keyPath": "hooks.state", "value": state, "mergeStrategy": "upsert"}],
                "filePath": None, "expectedVersion": None, "reloadUserConfig": True,
            })

        untrusted = [h["key"] for h in matching_hooks(client, needle) if h.get("trustStatus") != "trusted"]
        if untrusted:
            raise SystemExit(f"codex-trust: still untrusted: {untrusted}")
        print(f"Trusted {len(hooks)} Codex hook(s).")
    finally:
        client.close()


main()
