# Claude Island

A small dock in your menu bar that shows what Claude Code is doing. On a MacBook it sits just right of the camera notch; on an external monitor it sits in the centre of the menu bar.

- **Working**: Clawd scuttles along with a timer. With several sessions, one dot per session.
- **Needs you**: the dock opens, glows, and Clawd hops. For a permission prompt it shows what's being asked (`npm install`, an edit) with **Deny** and **Allow** buttons, so you can answer without going back to the terminal.
- **Done**: a happy hop, a check, and the first line of Claude's reply.

Hover over the dock to see every session stacked. Click one to jump to its terminal. Right-click to turn sounds on or off, or to quit.

Questions and plan reviews can't be answered from the dock yet; they show an **Open terminal** button instead.

If you're already looking at the terminal when a prompt appears, the dock steps aside and Claude Code's own prompt appears as usual.

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

For permission prompts the hook waits for your click on the dock and passes the answer back to Claude Code. If you switch to the terminal, quit the app, or ten minutes pass, it hands the prompt back to the terminal.

Some edges are handled without hooks. Pressing Esc doesn't fire a hook, so the app watches the session transcript for the interrupt instead. If a terminal closes without a clean exit, the session is dropped once its `claude` process is gone. A finished session clears when you return to its terminal.

## Development

```sh
swift build
.build/debug/ClaudeIsland
```

Requires macOS 14 or later.
