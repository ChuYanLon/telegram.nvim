# telegram.nvim

A Telegram chat tool for neovim, similar to telegra.el

Backend powered by TDLib + Node.js, frontend in pure Lua with HTTP + WebSocket communication.

## Requirements

- **Node.js** (>= 18)
- **curl**
- **libtdjson** — TDLib shared library (minimum version **1.8.64**)

### Installing libtdjson

**Arch Linux:**

```bash
sudo pacman -S tdlib
```

**macOS:**

```bash
brew install tdlib
```

**Other Linux:** Build from source:

```bash
git clone https://github.com/tdlib/td.git
cd td
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=~/.local \
    -DCMAKE_CXX_FLAGS="-O2 -g0" \
    ..
cmake --build . --target install -j$(nproc)
ldconfig 2>/dev/null || true
```

Or rely on `prebuilt-tdlib` (listed as a dependency — the `.so` still needs to be on your system).

The plugin auto-detects `libtdjson.so` at these paths:

- `/usr/lib/libtdjson.so`
- `/usr/lib/x86_64-linux-gnu/libtdjson.so`
- `/usr/local/lib/libtdjson.so`
- `~/.local/lib/libtdjson.so`

## Installation

### lazy.nvim

```lua
{
  "ChuYanLon/telegram.nvim",
  build = "npm i",
  event = "VeryLazy",
  keys = {
    { "<leader>tt", "<cmd>Tg<Cr>" },
    { "<leader>tL", "<cmd>TgLogout<Cr>" },
  },
  cmd = {
    "Tg",
    "TgLogout",
  },
  opts = {
    proxy = "socks5://127.0.0.1:7890",  -- optional, for regions where Telegram is blocked
  },
}
```

`build = "npm i"` installs Node.js dependencies automatically on first install.

## Commands

| Command     | Description                                                                                                                       |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `:Tg`       | Toggle groups. First run: server + auth. Then: if chat open → refresh; if previously opened → reopen; otherwise show group picker |
| `:TgLogout` | Log out, clear auth data, next `:Tg` starts fresh                                                                                 |

## Keymaps

```lua
-- Configure inside lazy.nvim `keys`, or map manually:
vim.keymap.set("n", "<leader>tt", "<cmd>Tg<Cr>")
vim.keymap.set("n", "<leader>tL", "<cmd>TgLogout<Cr>")
```

## Auth Flow

First run of `:Tg`:

1. Backend starts on port 8080
2. TDLib enters authentication flow
3. Neovim shows an input prompt — **async and non-blocking**, you can keep editing
4. Enter: **phone number** → **verification code** → (optional) **2FA password**
5. On success, the group list opens automatically

Cancelling the input prompt (ESC / close dialog) aborts auth and cleans cached state. The next `:Tg` starts from scratch.

## Configuration

Pass options via `setup()`:

```lua
require("telegram").setup({
  proxy = "socks5://127.0.0.1:7890",  -- proxy for TDLib connections
})
```

> **Note on `proxy`:** In regions where Telegram is blocked (e.g. China), TDLib cannot connect to Telegram's servers directly. Set a SOCKS5 or HTTP proxy here. Supported formats:
> - `socks5://127.0.0.1:7890`
> - `socks5://user:pass@127.0.0.1:7890`
> - `http://127.0.0.1:8080`

## FAQ

**Q: Verification code never arrives (SMS not received)**
A: If you're in a region where Telegram is blocked (e.g. China), TDLib needs a proxy to connect. Set `proxy` in your config:

```lua
require("telegram").setup({
  proxy = "socks5://127.0.0.1:7890",
})
```

Your proxy needs to support SOCKS5 (e.g. ClashX, V2Ray, Shadowsocks). On Windows, a system-level VPN/proxy may already cover TDLib's traffic; on macOS, TDLib ignores system proxy settings and must be configured explicitly.

**Q: "libtdjson.so not found"**
A: Install TDLib (see "Installing libtdjson" above), or set a custom path via `setup({ tdlib_path = "..." })`.

**Q: Do I need to re-authenticate every time Neovim restarts?**
A: No. TDLib caches session state in `tdlib_db/`. Auth persists across restarts.

**Q: How do I switch accounts?**
A: Run `:TgLogout`, or manually delete the `tdlib_db/` and `tdlib_files/` directories.

**Q: Port conflict?**
A: Default ports are 8080/8081. If occupied, the plugin auto-increments until it finds a free port.

## License

MIT
