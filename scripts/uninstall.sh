#!/bin/bash
# Removes Claude Island and its hooks. Leaves every other hook alone.
set -euo pipefail

APP="$HOME/Applications/Claude Island.app"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_HOOKS="${CODEX_HOME:-$HOME/.codex}/hooks.json"

# remove_hooks <file>: drops our hook entries, and the hooks key too if nothing else is left in it.
remove_hooks() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp)"
  jq '
    if .hooks then
      .hooks |= (
        with_entries(.value |= map(select(((.hooks // []) | any(.command // "" | contains("island-hook"))) | not)))
        | with_entries(select(.value | length > 0))
      )
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$file" > "$tmp"
  cat "$tmp" > "$file" && rm "$tmp"
  echo "Removed hooks from $file"
}

remove_hooks "$CLAUDE_SETTINGS"
remove_hooks "$CODEX_HOOKS"
# A hooks.json we created and nothing else uses is just noise.
[ -f "$CODEX_HOOKS" ] && [ "$(jq -c . "$CODEX_HOOKS")" = "{}" ] && rm "$CODEX_HOOKS"

pkill -x ClaudeIsland 2>/dev/null || true
rm -rf "$APP" "$HOME/.claude-island"
echo "Removed Claude Island."
