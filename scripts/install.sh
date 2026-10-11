#!/bin/bash
# Builds Claude Island, installs it to ~/Applications, and wires it into the hooks of
# Claude Code and, if it's installed, Codex.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Claude Island.app"
HOOK="$APP/Contents/MacOS/island-hook"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_HOOKS="$CODEX_HOME/hooks.json"

# Event -> hook timeout in seconds. PermissionRequest waits on you, so it gets a long one.
CLAUDE_EVENTS='{"SessionStart":5,"SessionEnd":5,"UserPromptSubmit":5,"PreToolUse":5,"PostToolUse":5,"PostToolUseFailure":5,"Notification":5,"Stop":5,"StopFailure":5,"PermissionRequest":620}'
# Codex clamps SessionEnd and Interrupt to 3 seconds.
CODEX_EVENTS='{"SessionStart":5,"SessionEnd":3,"UserPromptSubmit":5,"PreToolUse":5,"PostToolUse":5,"Stop":5,"Interrupt":3,"PermissionRequest":620}'

# add_hooks <file> <command> <events-json>: adds our hook to each event, replacing any earlier copy of it
# and leaving everyone else's hooks alone.
add_hooks() {
  local file="$1" command="$2" events="$3" tmp
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    jq empty "$file" || { echo "$file isn't valid JSON; fix it and run again." >&2; exit 1; }
    # Back up only a file we haven't touched yet, so the backup is always the original.
    grep -q island-hook "$file" || [ -f "$file.before-claude-island" ] || cp "$file" "$file.before-claude-island"
  else
    echo '{}' > "$file"
  fi
  tmp="$(mktemp)"
  jq --arg cmd "$command" --argjson events "$events" '
    .hooks = (.hooks // {})
    | reduce ($events | to_entries[]) as $e (.;
        .hooks[$e.key] = (
          ((.hooks[$e.key] // []) | map(select(((.hooks // []) | any(.command // "" | contains("island-hook"))) | not)))
          + [{hooks: [{type: "command", command: $cmd, timeout: $e.value}]}]
        ))
  ' "$file" > "$tmp"
  cat "$tmp" > "$file" && rm "$tmp"
}

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

echo "Adding Claude Code hooks to $CLAUDE_SETTINGS"
add_hooks "$CLAUDE_SETTINGS" "\"$HOOK\"" "$CLAUDE_EVENTS"

CODEX=0
if [ -d "$CODEX_HOME" ] || command -v codex >/dev/null 2>&1; then
  CODEX=1
  echo "Adding Codex hooks to $CODEX_HOOKS"
  add_hooks "$CODEX_HOOKS" "\"$HOOK\" codex" "$CODEX_EVENTS"
  # Codex only runs hooks you've trusted. This trusts ours, the same way Codex's own Trust button does.
  python3 scripts/codex-trust.py island-hook \
    || echo "Couldn't trust the Codex hooks automatically. Open /hooks in Codex and trust them." >&2
else
  echo "Codex not found; skipping its hooks. Run this again after installing it."
fi

open -g "$APP"
echo
echo "Done. Restart any Claude Code sessions that are already open so they pick up the hooks."
[ "$CODEX" = 1 ] && echo "Codex picks the hooks up on its next session."
exit 0
