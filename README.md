# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

A Telegram chat tool for neovim, similar to telega.el

Backend powered by TDLib + Node.js (TypeScript), frontend in pure Lua with HTTP + WebSocket communication.

> 💬 Join the discussion on Telegram: [t.me/+h4aEOaABJJ1mMzhl](https://t.me/+h4aEOaABJJ1mMzhl)

## Screenshots

> Partial screenshots — see Feature Status below for the full list.

| | |
|-|-|
| <img width="400" src="https://github.com/user-attachments/assets/0ff29034-aaca-4d3a-8994-3418436f20d0" /> | <img width="400" src="https://github.com/user-attachments/assets/cb7b56cd-e498-47b2-9808-49af00b0d2c8" /> |
| <img width="400" src="https://github.com/user-attachments/assets/46ec08d6-a275-47e0-a196-7d0eab7a51d5" /> | <img width="400" src="https://github.com/user-attachments/assets/c53202ab-7f40-4adb-8e99-8b0ba16d2643" /> |
| <img width="400" src="https://github.com/user-attachments/assets/bb72b4a5-15e3-4cf5-89cb-c4673cea40db" /> | <img width="400" src="https://github.com/user-attachments/assets/2bedeb8e-ced1-4173-a7fd-5073344155b3" /> |
| <img width="400" src="https://github.com/user-attachments/assets/9efb7eac-0175-4b00-bf5c-ba48cee129c6" /> | <img width="400" src="https://github.com/user-attachments/assets/8e14abba-cbd2-44d7-add2-db16e08ca38e" /> |
| <img width="400" src="https://github.com/user-attachments/assets/20f1304d-7f6c-4fba-82f7-b7510d590481" /> | <img width="400" src="https://github.com/user-attachments/assets/abc5d65b-1799-4459-93f0-734b886cef07" /> |
| <img width="400" src="https://github.com/user-attachments/assets/a5f07ec6-bc8c-4a78-89cd-14d4c40520e9" /> | <img width="400" src="https://github.com/user-attachments/assets/8b50a9ae-8ca1-44c3-9ea1-4e3aa4631e56" /> |
| <img width="400" src="https://github.com/user-attachments/assets/89b745c1-e86f-4f78-b88f-117464bbee59" /> | <img width="400" src="https://github.com/user-attachments/assets/480cccf9-6b2b-420f-8a01-6553b78cc92e" /> |
| <img width="400" src="https://github.com/user-attachments/assets/f6581d0f-fa3f-4d1f-9874-0648774ad506" /> | <img width="400" src="https://github.com/user-attachments/assets/f03d1de1-55e0-49ba-ac76-2117515d2db3" /> |

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
- [x] Target line highlighting (reply/edit/delete/forward) using theme's `Diff*` colors
- [x] `:TgPr` — create GitHub PR with branch picker, auto-fill, optional merge
- [x] `:TgIssue` — list, create branch, close, assign, open in browser
- [x] Proxy support (SOCKS5 / HTTP) for restricted regions
- [x] Service messages shown as readable text with prefix symbols
- [x] Download HD media — `@refreshmedia` downloads highest-quality version of photos/videos under cursor (async, non-blocking)
- [x] Context-aware tool picker — `@` only shows applicable tools (e.g. `refreshmedia` only on media messages)
- [x] Wake-up safe — messages received after sleep are batched and rendered at once, no Neovim freeze
- [x] Admin custom titles — shows `[头衔]` next to admin names in messages and member list; admins without title show `[Administrator]`
- [x] Photo / sticker / video / file inline preview — rendered as `![Photo](/path)` markdown; works with image renderers like `snacks.nvim` image module
- [x] Private chats (direct 1-on-1 messages) — press `c` on a message to open DM with the sender
- [x] Channel support — view channels and their messages; admin tools (member list, change info) shown based on permissions
- [x] Group management — view members (including admins and creator), ban/unban, restrict/unrestrict, promote/demote admins, add members by @username
- [x] Group settings — change title/description, granular default permissions editor (14 permission types with toggle-all), leave group, unsubscribe from channel, delete history
- [x] Invite links — create (with optional member limit and expiration), view, edit, and revoke invite links
- [x] Pin / unpin messages — press `p` on a message to pin/unpin; permission check for `can_pin_messages`
- [x] React to messages — press `r` to open reaction picker with 40+ verified emojis; same emoji toggles off, different auto-switches; real-time sync via WebSocket
- [x] Real-time sync between devices — edits, deletions, reactions, group info changes, user name/status changes sync via WebSocket from other clients
- [x] Online status — session reports as online with periodic heartbeat; device shown as `telegram.nvim` in Telegram's active sessions list
- [x] Customizable keymaps — all keys configurable via `setup({ keys = { ... } })`
- [x] Theme adaptation — all highlight groups derive from your Neovim theme (`Comment`, `DiffAdd`, `DiagnosticOk`, etc.)

### What doesn't work yet

- [ ] **Send media** (photos, videos, files, audio) — can't upload anything yet
- [ ] **Send stickers / GIFs**
- [ ] **Create polls**
- [ ] **Scheduled messages**
- [ ] **Poll, contact, location, dice, game, call display** — fallback shows label, content not interactive
- [ ] **Inline bots** / bot commands

### Customizing keys

```lua
require("telegram").setup({
  keys = {
    input_editor = "I",  -- rebind i → I
    refresh = "<F5>",
    help = "<F1>",
    ban = false,  -- disable ban key
  },
})
```

All available keys and their defaults:

| Key name | Default | Action |
|----------|---------|--------|
| `tool_picker` | `@` | Open tool picker |
| `input_editor` | `i` | Open message input editor |
| `reply` | `<CR>` | Reply to / jump to message |
| `edit` | `e` | Edit own message |
| `delete` | `d` | Delete / revoke message |
| `forward` | `f` | Forward message |
| `pin` | `p` | Pin / unpin message |
| `refresh` | `G` | Refresh messages, jump to bottom |
| `ban` | `B` | Ban message sender |
| `open_dm` | `c` | Open DM with message sender |
| `help` | `?` | Toggle help popup |
| `editor_submit` | `<CR>` | Submit message in editor |
| `editor_cancel` | `<Esc>` | Cancel editing |
| `help_close` | `<Esc>` | Close help popup |
| `help_close_q` | `q` | Close help popup (alt) |
| `perms_down` | `j` | Permission editor: move down |
| `perms_up` | `k` | Permission editor: move up |
| `perms_toggle` | `<Tab>` | Permission editor: toggle item |
| `perms_up_alt` | `<S-Tab>` | Permission editor: move up (alt) |
| `perms_save` | `<CR>` | Permission editor: save |
| `perms_discard` | `<Esc>` | Permission editor: discard |

Set any key to `false` to disable it.

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

## Lua API

### Statusline

`require("telegram").lualine` is a pre-built lualine component:

```lua
require("lualine").setup({
  sections = {
    lualine_x = { require("telegram").lualine },
  },
})
```

For other statuslines (heirline, feline, etc.):

```lua
require("telegram").status()       -- "disconnected" | "connecting" | "connected" | "error"
require("telegram").status_color() -- { fg = "#..." }   -- color matching current status
require("telegram").total_unread() -- total, mentions   -- unread counts across all chats
```

Displays `  ` with:
- 🟢 green — connected, no unread
- 🟡 yellow — connecting
- ⚫ gray — disconnected
- 🔴 red — error or has @mentions
- Shows unread count after icon when there are new messages, e.g. `  5`
- Appends `!` when there are @mentions, e.g. `  3!`

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
  -- notify_chat_types = { "private", "mention" },  -- types: "private", "group", "channel"; add "mention" for @mentions
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
