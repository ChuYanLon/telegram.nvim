## Chat Window

| Key | Action |
|-----|--------|
| `?` | Show help popup |
| `i` | Focus input editor |
| `<CR>` | Reply to message / jump to original message |
| `e` | Edit own message (highlighted in blue) |
| `d` | Delete / revoke message (highlighted in red) |
| `f` | Forward message to another chat |
| `G` | Refresh messages, jump to bottom |
| `@` | Open tool picker |

## Tools (`@` key)

| Tool | Description |
|------|-------------|
| **groups** | Switch to another chat (Snacks picker, falls back to `vim.ui.select`) |
| **refresh** | Refresh current chat messages |
| **send** | Send a message to current chat |
| **search** | Search messages in current chat |
| **refreshmedia** | Refresh media for current messages |
| **openlink** | Open URL or media file under cursor |

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
| `:TgSend <chatId> <text>` | Send a message programmatically |
| `:TgTool` | Open tool picker (equivalent to `@`) |
| `:TgIssue` | Browse GitHub issues, create branch, close, open in browser |
| `:TgPr` | Create GitHub PR with branch picker (squash/merge option) |

## Mouse

Scrolling near the top/bottom of the buffer automatically loads older/newer messages.
