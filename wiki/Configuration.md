## Setup Options

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",
  -- proxy = "socks5://127.0.0.1:7890",

  -- data_dir = "/path/to/data",  -- default: plugin root directory
  -- http_port = 8080,
  -- ws_port = 8081,
  -- notify_chat_types = { "private", "mention" },  -- types: "private", "group", "channel"; add "mention" for @mentions

  -- Custom keymaps (nil/false to disable a key)
  -- keys = {
  --   tool_picker = "@",
  --   input_editor = "i",
  --   reply = "<CR>",
  --   edit = "e",
  -- },
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tdlib_path` | `string?` | auto-detect | Path to `libtdjson.so`/`.dylib`/`.dll` |
| `proxy` | `string?` | `nil` | Proxy URL (e.g. `socks5://127.0.0.1:7890`) |
| `data_dir` | `string?` | plugin root | Directory for TDLib database and files |
| `http_port` | `number?` | `8080` | Backend HTTP server port |
| `ws_port` | `number?` | `8081` | Backend WebSocket server port |
| `keys` | `table?` | all defaults | Custom keymaps — see [Keymaps](#keymaps) below |
| `notify_chat_types` | `table?` | `{"private", "mention"}` | Chat types that trigger `vim.notify` on new messages (`"private"`, `"group"`, `"channel"`). Include `"mention"` for @mentions |
| `hide_title` | `boolean?` | `false` | Start with floating title bar hidden |

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

## Environment Variables

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` in setup |
| `TG_PROXY` | `proxy` in setup |
| `TG_PORT` | Backend HTTP port (default `8080`, overrides `http_port`) |
| `TG_WS_PORT` | WebSocket port (default `8081`, overrides `ws_port`) |
| `TG_DATA_DIR` | Database/files directory |

## Proxy

In regions where Telegram is blocked, set a proxy:

```lua
require("telegram").setup({ proxy = "socks5://127.0.0.1:7890" })
```

Supported formats:
- `socks5://host:port`
- `socks5://user:pass@host:port`
- `http://host:port`

The proxy is applied via TDLib's `addProxy` at startup.

## Lua API

`require("telegram").status` is a pre-built lualine component. Drop it into any lualine section:

```lua
lualine_x = {
  require("telegram").lualine,
}
```

For other statuslines:
```lua
require("telegram").status()       -- "disconnected" | "connecting" | "connected" | "error"
require("telegram").status_color() -- { fg = "#..." }
require("telegram").total_unread() -- total, mentions
```

Displays `  ` with:
- 🟢 green — connected, no unread
- 🟡 yellow — connecting
- ⚫ gray — disconnected
- 🔴 red — error or has @mentions
- Shows unread count after icon when there are new messages, e.g. `  5`
- Appends `!` when there are @mentions, e.g. `  3!`

## Database

TDLib stores data in `data_dir/tdlib_db/` (SQLite + binlog) and files in `data_dir/tdlib_files/`.  
Delete these directories to force re-authentication.  
`:TgLogout` does this automatically.
