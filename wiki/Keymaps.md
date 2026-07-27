All keymaps are configurable via `setup({ keys = { ... } })`.  
See [Configuration](Configuration.md#keymaps) for details and the full list of key names.

## Chat Window

<!-- KEYMAPS_TABLE_START -->
| Key name | Default | Action |
|----------|---------|--------|
| `tool_picker` | `@` | open tool picker |
| `input_editor` | `i` | open input editor |
| `reply` | `<CR>` | reply / jump to original |
| `edit` | `e` | edit own message |
| `delete` | `d` | delete / revoke |
| `forward` | `f` | forward message |
| `forward_with_reply` | `F` | forward with reply context |
| `pin` | `p` | pin / unpin message |
| `save` | `s` | save to Favorites |
| `copy` | `yy` | copy message text |
| `refresh` | `G` | refresh + jump to bottom |
| `ban` | `B` | ban message sender |
| `open_dm` | `c` | open DM with message sender |
| `help` | `?` | toggle this help |
| `editor_submit` | `<CR>` | submit message in editor |
| `editor_cancel` | `<Esc>` | cancel editing |
| `help_close` | `<Esc>` | close this help |
| `help_close_q` | `q` | close this help (alt) |
| `goto_last` | `<C-o>` | switch to previous chat |
| `reaction` | `r` | react to message |
| `archive` | `a` | archive/unarchive chat |
| `mark_unread` | `u` | mark unread / mark as read |
| `message_link` | `L` | copy message link |
| `user_profile` | `U` | view user profile |
| `mute` | `m` | mute / unmute chat |
| `perms_down` | `j` | permission editor: move down |
| `perms_up` | `k` | permission editor: move up |
| `perms_toggle` | `<Tab>` | permission editor: toggle item |
| `perms_up_alt` | `<S-Tab>` | permission editor: move up (alt) |
| `perms_save` | `<CR>` | permission editor: save |
| `perms_discard` | `<Esc>` | permission editor: discard |
| `vote` | `V` | vote on poll |

<!-- KEYMAPS_TABLE_END -->

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
| **toggleheader** | Toggle floating title bar visibility |

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
