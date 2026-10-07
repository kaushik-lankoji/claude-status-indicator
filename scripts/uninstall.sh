#!/bin/bash
# Removes Claude Island and its hooks. Leaves every other hook alone.
set -euo pipefail

APP="$HOME/Applications/Claude Island.app"
SETTINGS="$HOME/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
  TMP="$(mktemp)"
  jq '
    if .hooks then
      .hooks |= (
        with_entries(.value |= map(select(((.hooks // []) | any(.command // "" | contains("island-hook"))) | not)))
        | with_entries(select(.value | length > 0))
      )
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$TMP"
  cat "$TMP" > "$SETTINGS" && rm "$TMP"
  echo "Removed hooks from $SETTINGS"
fi

pkill -x ClaudeIsland 2>/dev/null || true
rm -rf "$APP" "$HOME/.claude-island"
echo "Removed Claude Island."
