## Setup Options

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",  -- only if auto-detection fails
  -- proxy = "socks5://127.0.0.1:7890",     -- proxy for TDLib connections
})
```

## Environment Variables

| Env var | Overrides | Default |
|---------|-----------|---------|
| `TG_TDLIB_PATH` | `tdlib_path` | auto-detected |
| `TG_PROXY` | `proxy` | — |
| `TG_PORT` | HTTP server port | `8080` |
| `TG_WS_PORT` | WebSocket server port | `8081` |
| `TG_DATA_DIR` | Data directory for `tdlib_db/` and `tdlib_files/` | `./` |

## Proxy

In regions where Telegram is blocked (e.g. China), set a proxy:

```lua
require("telegram").setup({ proxy = "socks5://127.0.0.1:7890" })
```

Supported formats: `socks5://host:port`, `socks5://user:pass@host:port`, `http://host:port`.
