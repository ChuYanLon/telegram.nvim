# telegram.nvim

A Telegram chat tool for neovim, similar to telegra.el

Backend powered by TDLib + Node.js, frontend in pure Lua with HTTP + WebSocket communication.

## Screenshots

| Feature | |
|---------|-|
| **Group details** | <img width="400" src="https://github.com/user-attachments/assets/a93336ce-f847-4331-973c-02e4a096eeb5" /> |
| **Edit message** | <img width="400" src="https://github.com/user-attachments/assets/f0fdf32e-6e8b-4d77-9082-c5b07f9e365d" /> |
| **Reply / restore message** | <img width="400" src="https://github.com/user-attachments/assets/06bed954-5865-4642-97ae-744bb485089d" /> |
| **Recall / delete message** | <img width="400" src="https://github.com/user-attachments/assets/5c4f623e-295b-451c-a186-d51622a6feae" /> |
| **Forward message** | <img width="400" src="https://github.com/user-attachments/assets/eb902e79-344a-42a0-a55e-3deee305068a" /> |
| **New message indicator** | <img width="400" src="https://github.com/user-attachments/assets/eb363ec8-d908-4c24-9d79-8358656f3bc4" /> |
| **Search messages** | <img width="400" src="https://github.com/user-attachments/assets/8e01b8a6-f056-410b-b13f-523c529b8f3c" /> <img width="400" src="https://github.com/user-attachments/assets/d1117f1e-a4e8-44d4-94d9-9a0eb4202d0b" /> |

## Requirements

- **Node.js** (>= 18)
- **curl**
- **libtdjson** — TDLib shared library (minimum version **1.8.64**) — `libtdjson.so` (Linux), `libtdjson.dylib` (macOS), `tdjson.dll` (Windows)

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
    -- tdlib_path = "/path/to/libtdjson.so",         -- optional: .so (Linux) / .dylib (macOS) / .dll (Windows)
    -- proxy = "socks5://127.0.0.1:7890",             -- optional: for regions where Telegram is blocked
  },
}
```

`build = "npm i"` installs Node.js dependencies automatically on first install.

## Commands

| Command       | Description                                                                                                                       |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `:Tg`         | Toggle groups. First run: server + auth. Then: if chat open → refresh; if previously opened → reopen; otherwise opens the first chat |
| `:TgLogout`   | Log out, clear auth data, next `:Tg` starts fresh                                                                                 |
| `:TgSend`     | Send a message programmatically: `:TgSend <chatId> <text>`                                                                        |

## Neovim Keymaps

```lua
-- Configure inside lazy.nvim `keys`, or map manually:
vim.keymap.set("n", "<leader>tt", "<cmd>Tg<Cr>")
vim.keymap.set("n", "<leader>tL", "<cmd>TgLogout<Cr>")
```

### Keymaps

Inside a chat window:

| Key | Action |
|-----|--------|
| `?` | Show help popup |
| `<C-h>` | Focus groups panel |
| `<C-l>` | Focus message panel |
| `<C-j>` | Focus input editor |
| `<C-k>` | Focus message panel |
| `i` | Focus input editor |
| `/` | Search messages |
| `<CR>` | Reply to message / jump to original with context |
| `e` | Edit own message at cursor |
| `d` | Delete message — prompts Revoke (for everyone) / Delete (for me) |
| `f` | Forward message to another group |
| `r` | Refresh and scroll to latest messages |
| `Esc Esc` | Close chat (preserves cursor position) |
| `q` | Quit (stop server, full exit) |

In the input editor:

| Key | Action |
|-----|--------|
| `<CR>` | Send message / confirm edit |
| `Esc` | Cancel reply/edit mode |
| `<C-h/j/k/l>` | Navigate panels |

In the groups panel:

| Key | Action |
|-----|--------|
| `j/k` | Move cursor |
| `<CR>` | Open selected chat |
| `<C-h/j/k/l>` | Navigate panels |

## Features

- **Online member count** — shows `N online` in the menu bar when a group is open
- **Typing indicators** — displays when another user is typing/recording/etc.
- **Own typing broadcast** — sends `typing...` indicator while composing, cancels on close
- **Cursor position persistence** — Esc saves cursor position, reopening restores it
- **Multi-line input editor** — NuiPopup-based editor with placeholder, reply/edit mode indicators
- **Context window** — `Enter` on a reply reference or picking a search result navigates to the message with surrounding context (~15 messages before and after), not a jump to raw message
- **Search messages** — `/` to search, pick a result to jump to it with full context
- **Bidirectional auto-load** — scroll past the top to load older messages, scroll past the bottom to load newer messages; both paginate from your current position, not from the chat's absolute newest
- **Operation feedback** — success notifications for send/reply/edit/delete/recall/forward
- **Async UI** — message operations, search, and scroll loading don't block the UI or cause scroll jumps
- **Startup feedback** — immediate "Starting server..." notification before blocking operations
- **Reply/Edit/Delete/Forward target highlight** — target message is highlighted with "● Replying" / "● Editing" / "● Deleting" / "● Forwarding" indicator
- **Virtual-scrolled groups panel** — only renders visible groups; `j/k` automatically pages when reaching the boundary; handles hundreds of groups efficiently
- **Read-only message window** — main chat buffer is not modifiable

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
  -- tdlib_path = "/path/to/libtdjson.so",  -- only if auto-detection fails
  -- proxy = "socks5://127.0.0.1:7890",     -- proxy for TDLib connections
})
```

Environment variable overrides:

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` |
| `TG_PROXY` | `proxy` |


The server auto-detects `libtdjson` on startup via:
- **Linux**: `ldconfig -p`, common paths (`/usr/lib`, `/usr/local/lib`, `~/.local/lib`, `/usr/lib64`, `/opt/lib`), `LD_LIBRARY_PATH`, and `find`
- **macOS**: `mdfind` and common paths (`/opt/homebrew/lib`, `/usr/local/lib`)
- **Windows**: `where tdjson.dll` and common paths (`%LOCALAPPDATA%`, `%PROGRAMFILES%`)

Override with `setup({ tdlib_path = "..." })` or the `TG_TDLIB_PATH` env var.

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

**Q: "libtdjson.so not found" / "Cannot find libtdjson"**
A: The server auto-detects the library on startup. If auto-detection fails, install TDLib (see "Installing libtdjson" above) or set a custom path via `setup({ tdlib_path = "..." })` or the `TG_TDLIB_PATH` env var.

**Q: Do I need to re-authenticate every time Neovim restarts?**
A: No. TDLib caches session state in `tdlib_db/`. Auth persists across restarts.

**Q: How do I switch accounts?**
A: Run `:TgLogout`, or manually delete the `tdlib_db/` and `tdlib_files/` directories.

**Q: Port conflict?**
A: Default ports are 8080/8081. The plugin kills any leftover tg server process on the port before starting. If still occupied, it auto-increments until a free port is found. Server process is terminated on Neovim exit.

## Contributing

All contributions are welcome! Just open a pull request.

## License

MIT
