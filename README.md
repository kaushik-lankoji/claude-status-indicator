# Claude Island

A small dock in your menu bar that shows what Claude Code and Codex are doing. On a MacBook it sits just right of the camera notch; on an external monitor it sits in the centre of the menu bar.

- **Working**: the agent's mascot animates with a timer. Clawd scuttles for Claude Code; a little cloud with its `>_` prompt floats for Codex. With several sessions, one dot per session.
- **Needs you**: the dock opens, glows in that agent's colour, and the mascot hops. For a permission prompt it shows what's being asked (a command, an edit) with **Deny** and **Allow** buttons, so you can answer without going back to the terminal or the Codex app.
- **Done**: a happy hop, a check, and the first line of the agent's reply.

When both agents are running they share the pill, one on each side of a hairline: Claude's mascot and status on the left, Codex's on the right, each with its own mood. Hover to see every session stacked, labelled by agent. Click one to jump to its terminal or the Codex app. Right-click to turn sounds on or off, or to quit.

Questions and plan reviews can't be answered from the dock yet; they show an **Open terminal** (or **Open Codex**) button instead.

If you're already looking at the terminal or the Codex app when a prompt appears, the dock steps aside and the agent's own prompt appears as usual.

## Install

```sh
./scripts/install.sh
```

This builds the app into `~/Applications/Claude Island.app` and adds its hooks to `~/.claude/settings.json` and, if Codex is installed, `~/.codex/hooks.json`. Your existing settings and hooks are left alone, and a backup is saved next to each file. You need Xcode or the Command Line Tools (for `swift`).

Codex only runs hooks you've trusted, so the installer trusts ours through Codex's own app-server, the same way its Trust button does (`scripts/codex-trust.py`). If that ever fails, open `/hooks` in Codex and trust them there.

The island launches itself whenever a Claude Code or Codex session starts, so there's nothing to keep open.

## Uninstall

```sh
./scripts/uninstall.sh
```

## How it works

Claude Code and Codex both run `island-hook` on their lifecycle events (prompt submitted, tool use, permission prompt, stop). Their hooks speak nearly the same language, so one binary serves both; Codex's hook passes `codex` as an argument. The hook writes a small JSON file per session to `~/.claude-island/sessions/`, and the app watches that folder.

For permission prompts the hook waits for your click on the dock and passes the answer back to Claude Code. If you switch to the terminal, quit the app, or ten minutes pass, it hands the prompt back to the terminal.

Some edges are handled without hooks. Claude Code fires no hook when you press Esc, so the app watches the session transcript for the interrupt; Codex reports interrupts itself. Codex has no hook for a turn that dies on an error, so a Codex session that has been silent for ten minutes is released. If a terminal closes without a clean exit, the session is dropped once its `claude` process is gone. A finished session clears when you return to its terminal.

## Development

```sh
swift build
.build/debug/ClaudeIsland
```

Requires macOS 14 or later.
