#!/bin/bash
# Builds Claude Island, installs it to ~/Applications, and wires it into Claude Code's hooks.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Claude Island.app"
SETTINGS="$HOME/.claude/settings.json"
HOOK="$APP/Contents/MacOS/island-hook"
# Event -> hook timeout in seconds. PermissionRequest waits on you, so it gets a long one.
EVENTS='{"SessionStart":5,"SessionEnd":5,"UserPromptSubmit":5,"PreToolUse":5,"PostToolUse":5,"PostToolUseFailure":5,"Notification":5,"Stop":5,"StopFailure":5,"PermissionRequest":620}'

echo "Building…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "Installing to $APP"
pkill -x ClaudeIsland 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/ClaudeIsland" "$BIN/island-hook" "$APP/Contents/MacOS/"
codesign --force --sign - "$APP/Contents/MacOS/island-hook"
codesign --force --sign - "$APP"

echo "Adding hooks to $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" || { echo "$SETTINGS isn't valid JSON; fix it and run again." >&2; exit 1; }
[ -f "$SETTINGS.before-claude-island" ] || cp "$SETTINGS" "$SETTINGS.before-claude-island"
TMP="$(mktemp)"
jq --arg cmd "\"$HOOK\"" --argjson events "$EVENTS" '
  .hooks = (.hooks // {})
  | reduce ($events | to_entries[]) as $e (.;
      .hooks[$e.key] = (
        ((.hooks[$e.key] // []) | map(select(((.hooks // []) | any(.command // "" | contains("island-hook"))) | not)))
        + [{hooks: [{type: "command", command: $cmd, timeout: $e.value}]}]
      ))
' "$SETTINGS" > "$TMP"
cat "$TMP" > "$SETTINGS" && rm "$TMP"

open -g "$APP"
echo
echo "Done. Restart any Claude Code sessions that are already open so they pick up the hooks."
