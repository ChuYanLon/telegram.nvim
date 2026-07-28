<!-- CONFIG_REFERENCE_START -->
## Configuration

Pass options via `setup()`:

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",  -- only if auto-detection fails
  -- proxy = "socks5://127.0.0.1:7890",     -- proxy for TDLib connections
  -- data_dir = "/path/to/data",            -- default: plugin root
  -- http_port = 8080,                      -- HTTP server port
  -- ws_port = 8081,                        -- WebSocket server port
  -- notify_chat_types = { "private", "mention" },  -- types: "private", "group", "channel"; add "mention" for @mentions
  -- hide_title = false,  -- start with floating title bar hidden
  -- panel_position = "right",  -- "right" | "left" | "bottom" | "top"
})
```

Environment variable overrides:

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` |
| `TG_PROXY` | `proxy` |
| `TG_PORT` | HTTP server port (default: `8080`) |
| `TG_WS_PORT` | WebSocket server port (default: `8081`) |
| `TG_DATA_DIR` | Data directory for `tdlib_db/` and `tdlib_files/` (default: plugin root) |

The server auto-detects `libtdjson` on startup via:
- **Linux**: `ldconfig -p`, common paths (`/usr/lib`, `/usr/local/lib`, `~/.local/lib`, `/usr/lib64`, `/opt/lib`), `LD_LIBRARY_PATH`, and `find`
- **macOS**: `mdfind` and common paths (`/opt/homebrew/lib`, `/usr/local/lib`)
- **Windows**: `where tdjson.dll` and common paths (`%LOCALAPPDATA%`, `%PROGRAMFILES%`)

Override with `setup({ tdlib_path = "..." })` or the `TG_TDLIB_PATH` env var.

> **Note on `proxy`:** In regions where Telegram is blocked (e.g. China), TDLib cannot connect to Telegram's servers directly. Set a SOCKS5 or HTTP proxy here. Supported formats:
> - `socks5://127.0.0.1:7890`
> - `socks5://user:pass@127.0.0.1:7890`
> - `http://127.0.0.1:8080`
<!-- CONFIG_REFERENCE_END -->

## Keymaps

All keymaps are configurable via `setup({ keys = { ... } })`. Set a key to `nil` or `false` to disable it.

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

```lua
-- Example: rebind keys
require("telegram").setup({
  keys = {
    input_editor = "I",
    refresh = "<F5>",
    help = "<F1>",
    ban = nil,  -- disable ban key
  },
})
```

<!-- LUA_API_START -->
## Lua API

### Statusline

`require("telegram").lualine` is a pre-built lualine component:

```lua
require("lualine").setup({
  sections = {
    lualine_x = { require("telegram").lualine },
  },
})
```

For other statuslines (heirline, feline, etc.):

```lua
require("telegram").status()       -- "disconnected" | "connecting" | "connected" | "error"
require("telegram").status_color() -- { fg = "#..." }   -- color matching current status
require("telegram").total_unread() -- total, mentions   -- unread counts across all chats
```

Displays `  ` with:
- 🟢 green — connected, no unread
- 🟡 yellow — connecting
- ⚫ gray — disconnected
- 🔴 red — error or has @mentions
- Shows unread count after icon when there are new messages, e.g. `  5`
- Appends `!` when there are @mentions, e.g. `  3!`
<!-- LUA_API_END -->

<!-- DATABASE_START -->
## Database

TDLib stores data in `data_dir/tdlib_db/` (SQLite + binlog) and files in `data_dir/tdlib_files/`.  
Delete these directories to force re-authentication.  
`:TgLogout` does this automatically.
<!-- DATABASE_END -->

### `@` Tools

Available tools via the tool picker (`@` or `:TgTool`):

<!-- TOOLS_TABLE_START -->
| Tool | Description |
|------|-------------|
| `@archive` | Archive/unarchive current chat |
| `@blocked` | List and manage blocked users |
| `@channels` | Switch to a channel (filtered) |
| `@chats` | Switch to another chat |
| `@contacts` | Browse your contacts list |
| `@createpoll` | Create a poll in current chat |
| `@dm` | Switch to a private chat (filtered) |
| `@draft` | Save draft to server / clear draft |
| `@eventlog` | View recent admin events (member changes, edits, etc.) |
| `@folders` | Switch chat folder |
| `@groups` | Switch to a group (filtered) |
| `@groupsettings` | Group / channel settings (title, description, permissions, etc.) |
| `@invitelinks` | Manage invite links |
| `@joinrequests` | View and manage pending join requests |
| `@jump_to_date` | Jump to messages on a specific date |
| `@markunread` | Mark current chat as unread / read |
| `@members` | View and manage chat members |
| `@mentions` | Search @mentions in current chat |
| `@messagelink` | Copy shareable link of message under cursor |
| `@mute` | Mute / unmute current chat |
| `@myprofile` | View and edit your profile name and bio |
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

