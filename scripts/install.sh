#!/bin/bash
# Builds Claude Island, installs it to ~/Applications, and wires it into Claude Code's hooks.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Claude Island.app"
SETTINGS="$HOME/.claude/settings.json"
HOOK="$APP/Contents/MacOS/island-hook"
EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","Notification","Stop","StopFailure"]'

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
  | reduce $events[] as $e (.;
      .hooks[$e] = (
        ((.hooks[$e] // []) | map(select(((.hooks // []) | any(.command // "" | contains("island-hook"))) | not)))
        + [{hooks: [{type: "command", command: $cmd, timeout: 5}]}]
      ))
' "$SETTINGS" > "$TMP"
cat "$TMP" > "$SETTINGS" && rm "$TMP"

open -g "$APP"
echo
echo "Done. Restart any Claude Code sessions that are already open so they pick up the hooks."
