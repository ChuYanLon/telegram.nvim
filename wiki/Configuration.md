## Setup Options

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",
  -- proxy = "socks5://127.0.0.1:7890",

  -- data_dir = vim.fn.stdpath("data") .. "/telegram",  -- default
  -- http_port = 8080,
  -- ws_port = 8081,
})

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tdlib_path` | `string?` | auto-detect | Path to `libtdjson.so`/`.dylib`/`.dll` |
| `proxy` | `string?` | `nil` | Proxy URL (e.g. `socks5://127.0.0.1:7890`) |
| `data_dir` | `string?` | stdpath data | Directory for TDLib database and files |
| `http_port` | `number?` | `8080` | Backend HTTP server port |
| `ws_port` | `number?` | `8081` | Backend WebSocket server port |

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

## Database

TDLib stores data in `data_dir/tdlib_db/` (SQLite + binlog) and files in `data_dir/tdlib_files/`.  
Delete these directories to force re-authentication.  
`:TgLogout` does this automatically.
