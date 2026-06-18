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
| `debug` | `boolean?` | `false` | Write HTTP request/response logs to `stdpath("data")/tg-debug.log` |

## Keymaps

All keymaps are configurable via `setup({ keys = { ... } })`. Set a key to `nil` or `false` to disable it.

| Key name | Default | Action |
|----------|---------|--------|
| `tool_picker` | `@` | Open tool picker |
| `input_editor` | `i` | Open message input editor |
| `reply` | `<CR>` | Reply to / jump to message |
| `edit` | `e` | Edit own message |
| `delete` | `d` | Delete / revoke message |
| `forward` | `f` | Forward message |
| `pin` | `p` | Pin / unpin message |
| `reaction` | `r` | React to message (opens emoji picker) |
| `save` | `s` | Save message to Favorites (with confirmation) |
| `copy` | `yy` | Copy message text to clipboard |
| `refresh` | `G` | Refresh messages, jump to bottom |
| `ban` | `B` | Ban message sender |
| `open_dm` | `c` | Open DM with message sender |
| `help` | `?` | Toggle help popup |
| `editor_submit` | `<CR>` | Submit message in editor |
| `editor_cancel` | `<Esc>` | Cancel editing |
| `help_close` | `<Esc>` | Close help popup |
| `help_close_q` | `q` | Close help popup (alt) |
| `perms_down` | `j` | Permission editor: move down |
| `perms_up` | `k` | Permission editor: move up |
| `perms_toggle` | `<Tab>` | Permission editor: toggle item |
| `perms_up_alt` | `<S-Tab>` | Permission editor: move up (alt) |
| `perms_save` | `<CR>` | Permission editor: save |
| `perms_discard` | `<Esc>` | Permission editor: discard |

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
