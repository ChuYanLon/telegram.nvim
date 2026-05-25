# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

A Telegram chat tool for neovim, similar to telegra.el

Backend powered by TDLib + Node.js, frontend in pure Lua with HTTP + WebSocket communication.

> 💬 Join the discussion on Telegram: search **telegram.nvim** in Telegram.

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
- **nui.nvim** — used for popups, layout, and input editor (automatically installed by lazy.nvim)
- **gh** (GitHub CLI) — optional, required for `:TgPr` and `:TgIssue` commands

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
  dependencies = { "MunifTanjim/nui.nvim" },
  keys = {
    { "<leader>tt", "<cmd>Tg<Cr>", desc = "Toggle Telegram" },
    { "<leader>tL", "<cmd>TgLogout<Cr>", desc = "Logout Telegram" },
    { "<leader>tp", "<cmd>TgPr<Cr>", desc = "Create PR" },
    { "<leader>ti", "<cmd>TgIssue<Cr>", desc = "Manage Issues" },
  },
  cmd = {
    "Tg",
    "TgLogout",
    "TgPr",
    "TgIssue",
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
| `:TgPr`       | Create a PR — select source/target branch, auto-fill title, optionally merge directly (admin bypass for `main`)                   |
| `:TgIssue`    | Manage issues — list, create branch, close, assign, open in browser                                                              |

> The server runs on a fixed port (8080). Opening `:Tg` in another Neovim instance will connect to the same server — only the instance that started it will stop it on exit.

## Neovim Keymaps

```lua
-- Configure inside lazy.nvim `keys`, or map manually:
vim.keymap.set("n", "<leader>tt", "<cmd>Tg<Cr>", { desc = "Toggle Telegram" })
vim.keymap.set("n", "<leader>tL", "<cmd>TgLogout<Cr>", { desc = "Logout Telegram" })
vim.keymap.set("n", "<leader>tp", "<cmd>TgPr<Cr>", { desc = "Create PR" })
vim.keymap.set("n", "<leader>ti", "<cmd>TgIssue<Cr>", { desc = "Manage Issues" })
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

## Feature Status

- [x] **Auth**: Phone number, verification code, 2FA password input
- [x] **Auth**: Session persistence across restarts
- [x] **Auth**: Error retry on invalid input
- [x] **Auth**: Async non-blocking input prompts
- [x] **Chat**: Group list with virtual scrolling and unread badges
- [x] **Chat**: Open/close chat
- [x] **Chat**: Bi-directional infinite scroll (older + newer messages)
- [x] **Chat**: Typing indicators (receive + send own typing)
- [x] **Chat**: Online member count in title bar
- [x] **Chat**: Real-time new message push via WebSocket
- [x] **Chat**: Cursor position persistence per chat
- [x] **Chat**: Mark messages as read on open
- [x] **Message**: Send plain text messages (with reply-to support)
- [x] **Message**: Edit own messages
- [x] **Message**: Delete messages (for me / revoke for everyone)
- [x] **Message**: Forward messages across groups
- [x] **Message**: Reply to messages with quote context
- [x] **Message**: Search messages with result picker + jump to context
- [x] **Message**: URL link detection and rendering
- [x] **Message**: Code block detection and rendering (backtick)
- [x] **Message**: Media display labels (photo, video, audio, document, voice, animation)
- [x] **Message**: Fallback rendering for stickers, polls, contacts, locations, dice, games, calls
- [x] **UI**: Three-panel layout: groups / messages / input
- [x] **UI**: Panel navigation via `<C-h/j/k/l>`
- [x] **UI**: Floating NUI popups with rounded borders
- [x] **UI**: Help popup showing all keymaps
- [x] **UI**: Input editor with placeholder text
- [x] **UI**: Action target color highlighting (reply / edit / delete / forward)
- [x] **UI**: Visual clipboard yank (`y`/`Y`)
- [x] **UI**: 12 custom highlight groups
- [x] **GitHub**: `:TgPr` — Create PR with branch selection, auto-fill, optional admin merge
- [x] **GitHub**: `:TgIssue` — List issues, create branch, close, assign, open in browser
- [x] **Backend**: 16 HTTP API endpoints (health, auth, groups, messages, chat actions, CRUD)
- [x] **Backend**: WebSocket broadcast for real-time updates
- [x] **Backend**: Auto-detection of libtdjson on Linux / macOS / Windows
- [x] **Backend**: Proxy support (SOCKS5 / HTTP)
- [x] **Backend**: Auto port allocation (fallback if port is occupied)
- [x] **Backend**: Server process lifecycle managed by Neovim
- [x] **Config**: `tdlib_path`, `proxy`, `data_dir`, `api_id`, `api_hash` options
- [x] **Config**: Environment variable overrides (`TG_TDLIB_PATH`, `TG_PROXY`, etc.)
- [x] **Config**: Dependency checking on startup (node, curl, scripts)
- [x] **Testing**: Vitest unit tests for message formatting, sender resolution, reply formatting
- [x] **Testing**: Vitest integration tests for Express server endpoints
- [x] **Testing**: FakeTdClient mock for testing

- [ ] **Message**: Message formatting (bold, italic, underline, strikethrough, monospace, spoiler) — send/edit only supports plain text
- [ ] **Message**: Media upload (send photos, videos, files, audio) — only text messages can be sent
- [ ] **Message**: Media download / preview in Neovim — media is shown as labels only
- [ ] **Message**: Sticker / GIF sending — can only receive and display labels
- [ ] **Message**: Poll creation and voting — read-only fallback rendering
- [ ] **Message**: Message pinning — no UI or API
- [ ] **Message**: Message reactions — no UI or API
- [ ] **Message**: Inline bots / bot commands
- [ ] **Message**: Scheduled messages
- [ ] **Message**: Emoji picker — no emoji support in input
- [ ] **Chat**: Channel support — filtered out; supergroups only
- [ ] **Chat**: Private chat (direct messages)
- [ ] **Chat**: Chat folders
- [ ] **Chat**: Pinned chats section
- [ ] **Chat**: Group management (add/remove members, change title/photo)
- [ ] **Chat**: Voice message recording / sending
- [ ] **Chat**: Message selection (multi-select for batch operations) — single message operations only
- [ ] **UI**: Message thread / topic view
- [ ] **UI**: Image / file preview in floating window — only text labels
- [ ] **UI**: Customizable keymaps — hardcoded, no user override API
- [ ] **UI**: Configurable UI layout (panel sizes, position) — fixed layout
- [ ] **UI**: Message search within chat (inline filtering) — uses `vim.ui.select` external picker
- [ ] **UI**: Dark/light theme adaptation — colors are fixed
- [ ] **Code**: `render/reply.lua` is dead code — defined but never called

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
