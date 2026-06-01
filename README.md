# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

A Telegram chat tool for neovim, similar to telegra.el

Backend powered by TDLib + Node.js (TypeScript), frontend in pure Lua with HTTP + WebSocket communication.

> 💬 Join the discussion on Telegram: [t.me/+h4aEOaABJJ1mMzhl](https://t.me/+h4aEOaABJJ1mMzhl)

## Screenshots

### Image Preview

| Feature | |
|---------|-|
| **Photo inline preview** | <img width="400" src="https://github.com/user-attachments/assets/3a1dc317-4a5d-40ab-b518-41d2014f87e3" /> |
| **Photo inline preview 2** | <img width="400" src="https://github.com/user-attachments/assets/2f24ddb3-ad50-4410-84be-0999dc5aad44" /> |

### Chat & Messages

| Feature | |
|---------|-|
| **Group chat** | <img width="400" src="https://github.com/user-attachments/assets/a36cc7c0-58ff-4ea8-9a57-36176ca0a9c8" /> |
| **Send message** | <img width="400" src="https://github.com/user-attachments/assets/cb891a1f-3b89-41eb-9c3e-c50662822722" /> |
| **Reply to message** | <img width="400" src="https://github.com/user-attachments/assets/6db5af48-2de1-45a2-b11f-45b933fd045f" /> |
| **Edit own message** | <img width="400" src="https://github.com/user-attachments/assets/677fca2b-ebb0-480f-8731-36c942f180c4" /> |
| **Delete / revoke message** | <img width="400" src="https://github.com/user-attachments/assets/b0d6ef43-f704-48e1-b238-858cf447ce71" /> |

### Private Chat

| Feature | |
|---------|-|
| **Private chat (DM)** | <img width="400" src="https://github.com/user-attachments/assets/7f162d15-d9bd-454c-9c16-24a69c6e7e84" /> |
| **Confirm before opening DM** | <img width="400" src="https://github.com/user-attachments/assets/d97585cb-4dd1-4619-ab6b-5cbdb476d2a2" /> |

### Navigation & Search

| Feature | |
|---------|-|
| **Chat list (picker)** | <img width="400" src="https://github.com/user-attachments/assets/3c95df1b-272c-41ce-ab2c-2578727300d3" /> |
| **Search messages** | <img width="400" src="https://github.com/user-attachments/assets/79d0aad8-25fa-4ac8-956b-f4c13190e763" /> |
| **Jump to search result** | <img width="400" src="https://github.com/user-attachments/assets/47866c45-84cd-48b3-920d-0d2f19ccf104" /> |

### UI Elements

| Feature | |
|---------|-|
| **Help popup** | <img width="400" src="https://github.com/user-attachments/assets/4a5b7376-e30e-4bd9-bb09-77808a823ef6" /> |
| **Tool picker (@)** | <img width="400" src="https://github.com/user-attachments/assets/fd62c5b5-1029-4afc-b918-2b8738cac24f" /> |

## Feature Status

### What works

- [x] Login with phone number, verification code, and 2FA password
- [x] Session persists across restarts (no re-login)
- [x] `:TgLogout` to clear auth and start fresh
- [x] Group list with unread badges, inline fuzzy search (Snacks picker with `vim.ui.select` fallback)
- [x] Open/close chats, switch between groups
- [x] Scroll infinitely in both directions (older and newer messages)
- [x] Receive new messages in real-time via WebSocket
- [x] Typing indicators and online member count
- [x] Cursor position is remembered per chat
- [x] Messages are marked as read when opening a chat
- [x] Send plain text messages (with reply context)
- [x] Send messages with formatting — type markdown syntax (`**bold**`, `### heading`) in input; Telegram clients (Android, iOS, Desktop) parse markdown natively, Neovim buffer renders via markdown treesitter
- [x] Edit your own messages
- [x] Delete your own messages (Delete for me / Revoke for everyone)
- [x] Forward messages to another chat
- [x] Reply to a message with quote context
- [x] Search messages and jump to the result position
- [x] URLs are highlighted and clickable
- [x] Code blocks (backtick) are detected and formatted
- [x] Single-panel chat layout with floating input popup
- [x] Adjustable panel position — respects `splitright`; width via `g:telegram_width`
- [x] `?` opens a help popup with all keybindings
- [x] Different highlight colors for reply / edit / delete / forward targets
- [x] `:TgPr` — create GitHub PR with branch picker, auto-fill, optional merge
- [x] `:TgIssue` — list, create branch, close, assign, open in browser
- [x] Proxy support (SOCKS5 / HTTP) for restricted regions
- [x] Service messages shown as readable text with prefix symbols
- [x] Download HD media — `@refreshmedia` downloads highest-quality version of photos/videos under cursor (async, non-blocking)
- [x] Context-aware tool picker — `@` only shows applicable tools (e.g. `refreshmedia` only on media messages)
- [x] Wake-up safe — messages received after sleep are batched and rendered at once, no Neovim freeze
- [x] Photo / sticker / video / file inline preview — rendered as `![Photo](/path)` markdown; works with image renderers like `snacks.nvim` image module
- [x] Private chats (direct 1-on-1 messages) — press `c` on a message to open DM with the sender
- [x] Channel support — view channels and their messages; admin tools (member list, change info) shown based on permissions
- [x] Group management — view members (including admins and creator), ban/unban, restrict/unrestrict, promote/demote admins, add members by @username
- [x] Group settings — change title/description, granular default permissions editor (14 permission types with toggle-all), leave group, unsubscribe from channel, delete history
- [x] Invite links — create (with optional member limit and expiration), view, edit, and revoke invite links
- [x] Pin / unpin messages — press `p` on a message to pin/unpin; permission check for `can_pin_messages`
- [x] Real-time sync between devices — edits, deletions, group info changes, user name/status changes sync via WebSocket from other clients
- [x] Online status — session reports as online with periodic heartbeat; device shown as `telegram.nvim` in Telegram's active sessions list

### What doesn't work yet

- [ ] **Send media** (photos, videos, files, audio) — can't upload anything yet
- [ ] **Send stickers / GIFs**
- [ ] **Create polls**
- [ ] **Scheduled messages**
- [ ] **Emoji picker**
- [ ] **React to messages** (like, heart, etc.)
- [ ] **Poll, contact, location, dice, game, call display** — fallback shows label, content not interactive
- [ ] **Multi-select messages** for batch operations
- [ ] **Chat folders**
- [ ] **Pinned chats** section
- [ ] **Change group photo**
- [ ] **Voice message** recording and sending
- [ ] **Inline bots** / bot commands
- [ ] **Message threads** / topic view
- [ ] **Customizable keymaps** — all hardcoded for now
- [ ] **Dark/light theme adaptation** — colors are hardcoded

### Service messages

System messages (members added, group renamed, etc.) are rendered as readable text with a prefix symbol. The text color follows the `Comment` highlight group.

| Prefix | Display | Example |
|--------|---------|---------|
| `[+]` | Member joined | `[+] Kitty joined this group via invite link at 2026-05-28 19:49` |
| `[+]` | Member added | `[+] Kitty added Bob at 2026-05-28 19:49` |
| `[-]` | Member left | `[-] Kitty left the group at 2026-05-28 19:49` |
| `[~]` | Group changed | `[~] Kitty changed the group name at 2026-05-28 19:49` |
| `[~]` | Group photo changed | `[~] Kitty changed the group photo at 2026-05-28 19:49` |
| `[~]` | Group upgraded | `[~] Kitty upgraded from a basic group at 2026-05-28 19:49` |
| `[*]` | Message pinned | `[*] Kitty pinned a message at 2026-05-28 19:49` |
| `[>]` | Group/topic created | `[>] Kitty created this group at 2026-05-28 19:49` |
| `[!]` | Auto-delete timer set | `[!] Kitty set auto-delete timer at 2026-05-28 19:49` |

### Media labels

Media messages are shown as thumbnails or tags:

| Tag | Meaning |
|-----|---------|
| `![Photo](/path)` | Photo sent (clickable, HD via `@refreshmedia`) |
| `![Video](/path)` | Video sent (clickable) |
| `![Animation](/path)` | GIF sent (clickable) |
| `![Document](/path)` | File sent (clickable) |
| `![Audio](/path)` | Music sent (clickable) |
| `![Voice](/path)` | Voice message (clickable) |
| `![Video Note](/path)` | Video message (clickable) |
| `![Sticker](/path)` | Sticker sent (clickable) |
| `[Poll]` | Poll created |
| `[Contact]` | Contact shared |
| `[Location]` | Location shared |
| `[Dice]` | Dice rolled |
| `[Game]` | Game played |
| `[Call]` | Voice/video call |
| emoji character | Animated emoji (inline text) |
| `![Video](/thumbnail)` | Video thumbnail preview (click `@openlink` to play) |

## Requirements

- **Node.js** (>= 18)
- **curl**
- **libtdjson** — TDLib shared library (minimum version **1.8.64**) — `libtdjson.so` (Linux), `libtdjson.dylib` (macOS), `tdjson.dll` (Windows)
- **snacks.nvim** — optional, used for the chat picker with fuzzy search (falls back to `vim.ui.select` if not installed)
- **ImageMagick** — optional, required by snacks.nvim image module to display non-PNG images (e.g. JPEG photos). Install with `brew install imagemagick` on macOS
- **gh** (GitHub CLI) — optional, required for `:TgPr` and `:TgIssue` commands

### Installing libtdjson

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
  dependencies = {
    -- "folke/snacks.nvim",   -- optional: enables fuzzy-find chat picker
  },
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

| Command       | Description                                                                                                                   |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `:Tg`         | Global toggle: opens tg window if closed, hides it if open (from any buffer). First run: server + auth, then opens last chat |
| `:TgLogout`   | Log out, clear auth data, next `:Tg` starts fresh                                                                             |
| `:TgSend`     | Send a message: `:TgSend <text>` to current chat, or `:TgSend <chatId> <text>` to specific chat                                      |
| `:TgTool`     | Open tool picker (`@` equivalent)                                                                                             |
| `:TgPr`       | Propose changes from a feature branch to main — choose squash or full merge, branch auto-deletes on completion                |
| `:TgIssue`    | Browse your assigned issues — create, close, assign, and create branches directly from an issue                               |

> The server runs on ports 8080/8081 (configurable via `setup({ http_port, ws_port })` or `TG_PORT`/`TG_WS_PORT` env vars). Opening `:Tg` in another Neovim instance will connect to the same server — only the instance that started it will stop it on exit.

## Neovim Keymaps

```lua
-- Configure inside lazy.nvim `keys`, or map manually:
vim.keymap.set("n", "<leader>tt", "<cmd>Tg<Cr>", { desc = "Toggle Telegram" })
vim.keymap.set("n", "<leader>tL", "<cmd>TgLogout<Cr>", { desc = "Logout Telegram" })
vim.keymap.set("n", "<leader>tp", "<cmd>TgPr<Cr>", { desc = "Create PR" })
vim.keymap.set("n", "<leader>ti", "<cmd>TgIssue<Cr>", { desc = "Manage Issues" })
```

### Keymaps

Inside the chat window:

| Key | Action |
|-----|--------|
| `?` | Toggle help popup |
| `i` | Open input editor to send a message (only if user has permission — hidden for channel subscribers) |
| `<CR>` | Reply to message / jump to original (if cursor is on a quote line) |
| `e` | Edit own message at cursor |
| `d` | Delete message — prompts Revoke (for everyone) / Delete (for me) |
| `f` | Forward message to another chat |
| `p` | Pin / unpin message at cursor |
| `c` | Open DM with the sender of the message at cursor |
| `G` | Refresh messages and jump to bottom |
| `B` | Ban the sender of the message at cursor |
| `@` | Open context-aware tool picker |

In the chat picker (`@` → chats):
- Built-in fuzzy search (Snacks picker when available, `vim.ui.select` fallback)
- `<CR>` — select chat
- `<Esc>` — close

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
  -- data_dir = "/path/to/data",            -- default: plugin root
  -- http_port = 8080,                      -- HTTP server port
  -- ws_port = 8081,                        -- WebSocket server port
})
```

Environment variable overrides:

| Env var | Overrides |
|---------|-----------|
| `TG_TDLIB_PATH` | `tdlib_path` |
| `TG_PROXY` | `proxy` |
| `TG_PORT` | HTTP server port (default: `8080`) |
| `TG_WS_PORT` | WebSocket server port (default: `8081`) |
| `TG_DATA_DIR` | Data directory for `tdlib_db/` and `tdlib_files/` (default: plugin root) |


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
A: Default ports are 8080/8081. Configure via `setup({ http_port = ..., ws_port = ... })` or `TG_PORT`/`TG_WS_PORT` env vars. The plugin checks if a server is already running and reconnects if it's ours. If occupied by another process, startup fails — change to different ports. Server process is terminated on Neovim exit.

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
