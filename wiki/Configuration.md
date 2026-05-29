## Setup Options

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",
  -- proxy = "socks5://127.0.0.1:7890",
  -- api_id = 12345,
  -- api_hash = "abcdef1234567890",
  -- data_dir = vim.fn.stdpath("data") .. "/telegram",  -- default
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tdlib_path` | `string?` | auto-detect | Path to `libtdjson.so`/`.dylib`/`.dll` |
| `proxy` | `string?` | `nil` | Proxy URL (e.g. `socks5://127.0.0.1:7890`) |
| `api_id` | `number?` | `1025907` | Telegram API ID |
| `api_hash` | `string?` | built-in | Telegram API hash |
| `data_dir` | `string?` | stdpath data | Directory for TDLib database and files |

## Environment Variables

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` in setup |
| `TG_PROXY` | `proxy` in setup |
| `TG_API_ID` | `api_id` in setup |
| `TG_API_HASH` | `api_hash` in setup |
| `TG_PORT` | Backend HTTP port (default `8080`) |
| `TG_WS_PORT` | WebSocket port (default `8081`) |
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
