## Setup Options

```lua
require("telegram").setup({
  -- tdlib_path = "/path/to/libtdjson.so",
  -- proxy = "socks5://127.0.0.1:7890",
})
```

## Environment Variables

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` |
| `TG_PROXY` | `proxy` |

## Proxy

In regions where Telegram is blocked (e.g. China), set a proxy:

```lua
require("telegram").setup({ proxy = "socks5://127.0.0.1:7890" })
```

Supported formats: `socks5://host:port`, `socks5://user:pass@host:port`, `http://host:port`.
