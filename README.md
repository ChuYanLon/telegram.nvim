# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

A Telegram chat tool for neovim, similar to telegra.el

Backend powered by TDLib + Node.js (TypeScript), frontend in pure Lua with HTTP + WebSocket communication.

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
| **Service messages** | <img width="400" src="https://github.com/user-attachments/assets/eb87e415-e3d7-417e-9d96-84f9ca9568a2" /> |

## Feature Status

### What works

- [x] Login with phone number, verification code, and 2FA password
- [x] Session persists across restarts (no re-login)
- [x] `:TgLogout` to clear auth and start fresh
- [x] Group list with unread badges, virtual scrolling
- [x] Open/close chats, switch between groups
- [x] Scroll infinitely in both directions (older and newer messages)
- [x] Receive new messages in real-time via WebSocket
- [x] Typing indicators and online member count
- [x] Cursor position is remembered per chat
- [x] Messages are marked as read when opening a chat
- [x] Send plain text messages (with reply context)
- [x] Edit your own messages
- [x] Delete your own messages (Delete for me / Revoke for everyone)
- [x] Forward messages to another group
- [x] Reply to a message with quote context
- [x] Search messages and jump to the result position
- [x] URLs are highlighted and clickable
- [x] Code blocks (backtick) are detected and formatted
- [x] Three-panel layout: group list / messages / input
- [x] `<C-h/j/k/l>` to navigate between panels
- [x] `?` opens a help popup with all keybindings
- [x] Different highlight colors for reply / edit / delete / forward targets
- [x] Visual `y`/`Y` yanks to system clipboard
- [x] `:TgPr` — create GitHub PR with branch picker, auto-fill, optional merge
- [x] `:TgIssue` — list, create branch, close, assign, open in browser
- [x] Proxy support (SOCKS5 / HTTP) for restricted regions
- [x] Service messages shown as readable text with prefix symbols

### What doesn't work yet

- [ ] **Send messages with formatting** (bold, italic, underline, etc.) — plain text only
- [ ] **Send media** (photos, videos, files, audio) — can't upload anything yet
- [ ] **Send stickers / GIFs**
- [ ] **Create polls**
- [ ] **Scheduled messages**
- [ ] **Emoji picker**
- [ ] **Inline preview** of photos, videos, files in Neovim — only shows a label, no real preview
- [ ] **Sticker, poll, contact, location, dice, game, call display** — fallback exists but doesn't render properly
- [ ] **React to messages** (like, heart, etc.)
- [ ] **Pin messages**
- [ ] **Multi-select messages** for batch operations
- [ ] **Channel support** — currently filtered out, supergroups only
- [ ] **Private chats** (direct 1-on-1 messages)
- [ ] **Chat folders**
- [ ] **Pinned chats** section
- [ ] **Leave group**
- [ ] **Change group name / description**
- [ ] **Add / kick / ban members**
- [ ] **Promote / demote admins**
- [ ] **View member list**
- [ ] **Pin / unpin messages**
- [ ] **Generate invite link**
- [ ] **Change group photo**
- [ ] **Voice message** recording and sending
- [ ] **Inline bots** / bot commands
- [ ] **Message threads** / topic view
- [ ] **Customizable keymaps** — all hardcoded for now
- [ ] **Adjustable layout** — panel sizes and position are fixed
- [ ] **Dark/light theme adaptation** — colors are hardcoded

### Service messages

System messages (members added, group renamed, etc.) are rendered as readable text with a prefix symbol. The text color follows the `Comment` highlight group.

| Prefix | Display | Example |
|--------|---------|---------|
| `+` | Member joined | `+ Kitty joined this group at 19:49:58 on May 09, 2026` |
| `+` | Member added | `+ Kitty added Bob at 19:49:58 on May 09, 2026` |
| `-` | Member left | `- Kitty left the group at ...` |
| `~` | Group changed | `~ Kitty changed the group name to 'New Name' at ...` |
| `*` | Message pinned | `* Kitty pinned a message at ...` |
| `>` | Group/topic created | `> Kitty created this group at ...` |

### Media labels

Media messages that cannot be rendered natively are shown as tags:

| Tag | Meaning |
|-----|---------|
| `[Photo]` | Photo sent |
| `[Video]` | Video sent |
| `[Animation]` | GIF sent |
| `[Document]` | File sent |
| `[Audio]` | Music sent |
| `[Voice]` | Voice message |
| `[Video Note]` | Video message |
| `[Sticker]` | Sticker sent |
| `[Poll]` | Poll created |
| `[Contact]` | Contact shared |
| `[Location]` | Location shared |
| `[Dice]` | Dice rolled |
| `[Game]` | Game played |
| `[Call]` | Voice/video call |

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
| `:TgPr`       | Propose changes from a feature branch to main — choose squash or full merge, branch auto-deletes on completion |
| `:TgIssue`    | Browse, create, close, and assign issues — create branches directly from an issue |

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

**Q: Why does the server use TypeScript?**
A: The backend was migrated from JavaScript to TypeScript (v0.3.0) for better type safety and maintainability in a multi-contributor project. The server runs via `tsx`, which is installed automatically by `npm install` — no extra setup needed.

**Q: How do I switch accounts?**
A: Run `:TgLogout`, or manually delete the `tdlib_db/` and `tdlib_files/` directories.

**Q: Port conflict?**
A: Default ports are 8080/8081. The plugin kills any leftover tg server process on the port before starting. If still occupied, it auto-increments until a free port is found. Server process is terminated on Neovim exit.

## Development Workflow

- **`main`** — stable branch, protected, no direct pushes
- **`feat/*` / `fix/*` / `chore/*`** — feature/fix branches, created from `main`
- PRs target `main` — use `:TgPr` to create and optionally merge
- Merge options: **squash** or **commit**
- After merge, GitHub auto-deletes the source branch (set in repo settings)
- CI runs on every push and PR (test + typecheck)

## Contributing

All contributions are welcome! Just open a pull request targeting `main`. See the [full guide](CONTRIBUTING.md) for details.

## License

MIT
