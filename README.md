# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

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

## Progress

| Category | Done | Total | Progress |
|----------|------|-------|----------|
| Messaging | 7 | 14 | ████████░░░░░ 50% |
| UI & Interaction | 16 | 21 | ████████████░░ 76% |
| Infrastructure | 6 | 10 | ████████░░░░ 60% |
| **Total** | **29** | **45** | █████████░░ 64% |

### Messaging

| | Feature | Status |
|--|---------|--------|
| ✓ | **Send text messages** — plain text to any group | ✅ Done |
| ✓ | **Edit messages** — edit own message text | ✅ Done |
| ✓ | **Delete / recall** — delete for self or revoke for everyone | ✅ Done |
| ✓ | **Forward messages** — forward to another group | ✅ Done |
| ✓ | **Reply to messages** — reply with quoted context | ✅ Done |
| ✓ | **Search messages** — `/` to search within a chat | ✅ Done |
| ✓ | **Bidirectional auto-load** — scroll older/newer from current position | ✅ Done |
| ☐ | **Rich text rendering** — bold/italic/code/links/markdown | 📝 Planned |
| ☐ | **Media files** — download and view images/documents/voice | 📝 Planned |
| ☐ | **Message reactions** — add/remove emoji reactions | 📝 Planned |
| ☐ | **Pinned messages** — view, pin, unpin | 📝 Planned |
| ☐ | **Polls** — create and vote | 📝 Planned |
| ☐ | **Multi-select mode** — batch delete / batch forward | 📝 Planned |
| ☐ | **Message details** — edit history, message info | 📝 Planned |

### UI & Interaction

| | Feature | Status |
|--|---------|--------|
| ✓ | **Group list** — all supergroups and basic groups | ✅ Done |
| ✓ | **Real-time push** — WebSocket instant message arrival | ✅ Done |
| ✓ | **Online member count** — `N online` in menu bar | ✅ Done |
| ✓ | **Typing indicators** — see when others are typing | ✅ Done |
| ✓ | **Own typing broadcast** — auto-send typing indicator | ✅ Done |
| ✓ | **Multi-line input editor** — NuiPopup with placeholder/mode indicators | ✅ Done |
| ✓ | **Context window** — reply/search result with surrounding messages | ✅ Done |
| ✓ | **Target highlighting** — reply/edit/delete/forward indicator | ✅ Done |
| ✓ | **Cursor persistence** — save/restore position across sessions | ✅ Done |
| ✓ | **Unread indicator** — `[N]` on title bar | ✅ Done |
| ✓ | **Virtual-scrolled groups** — efficient for hundreds of groups | ✅ Done |
| ✓ | **Read-only message window** — buffer not modifiable | ✅ Done |
| ✓ | **Async UI** — non-blocking operations | ✅ Done |
| ✓ | **Operation feedback** — success notifications | ✅ Done |
| ✓ | **Startup feedback** — immediate status | ✅ Done |
| ✓ | **Help popup** — `?` shows keymap reference | ✅ Done |
| ☐ | **Direct messages / user search** — private chats | 📝 Planned |
| ☐ | **Chat filters** — unread only, specific types | 📝 Planned |
| ☐ | **Cross-chat global search** — search all chats | 📝 Planned |
| ☐ | **Session persistence** — restore state across Neovim restart | 📝 Planned |
| ☐ | **Message translation** — via external API | 📝 Planned |

### Infrastructure

| | Feature | Status |
|--|---------|--------|
| ✓ | **Auth flow** — phone → code → 2FA, async | ✅ Done |
| ✓ | **Proxy support** — SOCKS5/HTTP for TDLib | ✅ Done |
| ✓ | **Auto-detect libtdjson** — Linux/macOS/Windows | ✅ Done |
| ✓ | **Port conflict handling** — auto-increment on conflict | ✅ Done |
| ✓ | **Server lifecycle** — auto-start/stop with Neovim | ✅ Done |
| ✓ | **`vim.notify` with title** — `[tg]` as title, not text | ✅ Done |
| ☐ | **WebSocket auto-reconnect** — reconnect on disconnect | 📝 Planned |
| ☐ | **Chat cache persistence** — avoid re-fetch on restart | 📝 Planned |
| ☐ | **Batch sender resolve** — optimize bulk message loading | 📝 Planned |
| ☐ | **HTTP error retry** — retry with backoff on failure | 📝 Planned |

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
