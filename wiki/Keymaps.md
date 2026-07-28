All keymaps are configurable via `setup({ keys = { ... } })`.  
See [Configuration](Configuration.md#keymaps) for details and the full list of key names.

## Chat Window

<!-- KEYMAPS_TABLE_START -->
| Key name | Default | Action |
|----------|---------|--------|
| `translate_zh` | `tt` | translate message to Chinese |
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

<!-- KEYMAPS_TABLE_END -->

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

### `@` Tools

Available tools via the tool picker (`@` or `:TgTool`):

<!-- TOOLS_TABLE_START -->
| Tool | Description |
|------|-------------|
| `@archive` | Archive/unarchive current chat |
| `@blocked` | List and manage blocked users |
| `@channels` | Switch to a channel (filtered) |
| `@chats` | Switch to another chat |
| `@createpoll` | Create a poll in current chat |
| `@dm` | Switch to a private chat (filtered) |
| `@draft` | Save draft to server / clear draft |
| `@folders` | Switch chat folder |
| `@groups` | Switch to a group (filtered) |
| `@groupsettings` | Group / channel settings (title, description, permissions, etc.) |
| `@invitelinks` | Manage invite links |
| `@jump_to_date` | Jump to messages on a specific date |
| `@markunread` | Mark current chat as unread / read |
| `@members` | View and manage chat members |
| `@mentions` | Search @mentions in current chat |
| `@messagelink` | Copy shareable link of message under cursor |
| `@mute` | Mute / unmute current chat |
| `@newchat` | Start a new private chat by @username |
| `@openlink` | Open URL or media file under cursor |
| `@openshared` | Open shared chat or user DM |
| `@pinchat` | Pin / unpin current chat |
| `@reaction` | React to message |
| `@refresh` | Refresh messages |
| `@refreshmedia` | Download and update image for message under cursor |
| `@saved` | Open Saved Messages |
| `@search` | Search message history |
| `@send` | Send a message to current chat |
| `@showarchived` | Toggle archived chats in picker |
| `@stoppoll` | Stop a poll |
| `@toggleheader` | Toggle floating title bar visibility |
| `@translate` | Translate message under cursor |
| `@translate_zh` | Translate message under cursor to Chinese |
| `@userinfo` | View profile of message sender |
| `@vote` | Vote on the poll message under cursor |
| `@voters` | List who voted on each poll option |

<!-- TOOLS_TABLE_END -->

