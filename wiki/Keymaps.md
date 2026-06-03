All keymaps are configurable via `setup({ keys = { ... } })`.  
See [Configuration](Configuration.md#keymaps) for details and the full list of key names.

## Chat Window

| Key | Action |
|-----|--------|
| `?` | Show help popup |
| `i` | Focus input editor |
| `<CR>` | Reply to message / jump to original message |
| `e` | Edit own message (highlighted in blue) |
| `d` | Delete / revoke message (highlighted in red) |
| `f` | Forward message to another chat |
| `p` | Pin / unpin message at cursor |
| `r` | React to message (opens emoji picker) |
| `c` | Open DM with message sender |
| `B` | Ban message sender |
| `G` | Refresh messages, jump to bottom |
| `@` | Open tool picker |

## Tools (`@` key)

| Tool | Description |
|------|-------------|
| **chats** | Switch to another chat (Snacks picker, falls back to `vim.ui.select`) |
| **refresh** | Refresh current chat messages |
| **send** | Send a message to current chat |
| **search** | Search messages in current chat |
| **refreshmedia** | Refresh media for current messages |
| **openlink** | Open URL or media file under cursor |
| **newchat** | Start a new private chat by @username |
| **members** | View and manage chat members |
| **invitelinks** | Manage invite links |
| **groupsettings** | Group / channel settings (title, description, granular default permissions editor, add member, leave/unsubscribe) |

## Input Editor

| Key | Action |
|-----|--------|
| `<CR>` | Send message / confirm edit |
| `Esc` | Cancel reply/edit/forward mode |

## Commands

| Command | Description |
|---------|-------------|
| `:Tg` | Toggle Telegram panel (start backend + auth if first run) |
| `:TgLogout` | Log out, delete local TDLib database, stop server |
| `:TgSend <text>` | Send to current chat |
| `:TgSend <chatId> <text>` | Send to specific chat by ID |
| `:TgTool` | Open tool picker (equivalent to `@`) |
| `:TgIssue` | Browse GitHub issues, create branch, close, open in browser |
| `:TgPr` | Create GitHub PR with branch picker (squash/merge option) |

## Mouse

Scrolling near the top/bottom of the buffer automatically loads older/newer messages.
