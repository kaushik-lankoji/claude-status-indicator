# Claude Island

A small island at the top of your screen that shows what Claude Code is doing.

- **Working**: Clawd scuttles along and a timer counts the turn.
- **Needs you**: the island opens, glows, and Clawd hops and waves. It shows exactly what's being asked ("Run this command? `npm install`").
- **Done**: a happy hop, a check, and the first line of Claude's reply.

Hover over the island to see every session. Click to jump to its terminal. Right-click to turn sounds on or off, or to quit.

## Install

```sh
./scripts/install.sh
```

This builds the app into `~/Applications/Claude Island.app` and adds its hooks to `~/.claude/settings.json`. Your existing settings and hooks are left alone, and a backup is saved next to the file. You need Xcode or the Command Line Tools (for `swift`).

The island launches itself whenever a Claude Code session starts, so there's nothing to keep open.

## Uninstall

```sh
./scripts/uninstall.sh
```

## How it works

Claude Code runs `island-hook` on its lifecycle events (prompt submitted, tool use, permission prompt, stop). The hook writes a small JSON file per session to `~/.claude-island/sessions/`, and the app watches that folder.

Some edges are handled without hooks. Pressing Esc doesn't fire a hook, so the app watches the session transcript for the interrupt instead. If a terminal closes without a clean exit, the session is dropped once its `claude` process is gone. A finished session clears when you return to its terminal.

## Development

```sh
swift build
.build/debug/ClaudeIsland
```

Requires macOS 14 or later.
