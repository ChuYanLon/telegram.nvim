# telegram.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)
[![CI](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ChuYanLon/telegram.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.9-blueviolet)](https://neovim.io)

A Telegram chat tool for neovim, similar to telega.el

Backend powered by TDLib + Node.js (TypeScript), frontend in pure Lua with HTTP + WebSocket communication.

> 💬 Join the discussion on Telegram: [t.me/+h4aEOaABJJ1mMzhl](https://t.me/+h4aEOaABJJ1mMzhl)

## Screenshots

<img width="600" src="https://github.com/user-attachments/assets/9efb7eac-0175-4b00-bf5c-ba48cee129c6" />

<!-- FEATURES_START -->
## Feature Status

### Messages
- Read text, media, links, code blocks, service messages in real-time via WebSocket
- Rich text highlighting: **bold**, *italic*, `code`, ~~strikethrough~~, ||spoiler||, [links](url) with distinct highlight groups
- Rich display for contacts (`👤`), venues (`📍` with map link), locations, invoices, gifts, calls, dice, and more
- Full service message coverage: screenshot, contact registered, proximity alert, theme/background changes, boosts, payments, web apps, admin events, and more
- Send/edit/delete/forward/reply with markdown formatting
- Polls: display with progress bars, vote (`@vote`), create (`@createpoll`), view voters (`@voters`), stop (`@stoppoll`). Supports multi-answer and timed polls.
- Search messages, copy text, save to Favorites
- Jump to any date with `@jump_to_date` — supports `YYYY-MM-DD`, `today`, `yesterday`
- Auto-download media with `@refreshmedia`, inline previews (photo/video/sticker/file)
- Read receipts, edited indicators, view counts, typing indicators

### Chat management
- Group, channel, and private chat (DM) support
- Member management: promote/demote, ban/unban, restrict, add by @username
- Invite links with member limit and expiration
- Group settings: title, description, granular permissions editor (14 types)
- Pin/unpin messages, react with emojis (40+), mark unread, archive chats
- Favorites (Saved Messages)

### UI & UX
- Configurable panel position (right/left/bottom/top)
- Rich text highlighting: **bold**, *italic*, `code`, ~~strikethrough~~, ||spoiler||, [links](url) in messages
- Footer metadata ([edited], views, reactions) styled with distinct highlight group
- Floating input editor with markdown treesitter highlight and reply preview
- Cursor persistence per chat, unread-aware loading with divider
- Scroll infinitely in both directions, date separators
- Statusline integration (lualine/heirline), help popup
- Theme adaptation (all highlights from your Neovim theme)
- Customizable keymaps, toggleable title bar with connection status
- Wake-up safe: batches messages received during sleep

### Authentication & connectivity
- Phone → code → 2FA flow, session persists across restarts
- `:TgLogout` to clear auth
- Online status with periodic heartbeat (shows as `telegram.nvim`)
- Real-time sync between devices
- Proxy support (SOCKS5 / HTTP) for restricted regions
<!-- FEATURES_END -->
- `:TgPr` — create/merge PRs with branch picker, squash option, auto-delete
- `:TgIssue` — browse issues, close, assign, create branches, open in browser

### Known limitations
- Send media (photos/videos/files/audio), stickers/GIFs
- Scheduled messages
- Inline bots / bot commands

### `@` Tools

Available tools via the tool picker (`@` or `:TgTool`):

<!-- TOOLS_TABLE_START -->
| Tool | Description |
|------|-------------|
| `@archive` | Archive/unarchive current chat |
| `@blocked` | List and manage blocked users |
| `@channels` | Switch to a channel (filtered) |
| `@chats` | Switch to another chat |
| `@createpoll` | Create a poll in current chat |
| `@dm` | Switch to a private chat (filtered) |
| `@draft` | Save draft to server / clear draft |
| `@eventlog` | View recent admin events (member changes, edits, etc.) |
| `@folders` | Switch chat folder |
| `@groups` | Switch to a group (filtered) |
| `@groupsettings` | Group / channel settings (title, description, permissions, etc.) |
| `@invitelinks` | Manage invite links |
| `@joinrequests` | View and manage pending join requests |
| `@jump_to_date` | Jump to messages on a specific date |
| `@markunread` | Mark current chat as unread / read |
| `@members` | View and manage chat members |
| `@mentions` | Search @mentions in current chat |
| `@messagelink` | Copy shareable link of message under cursor |
| `@mute` | Mute / unmute current chat |
| `@newchat` | Start a new private chat by @username |
| `@openlink` | Open URL or media file under cursor |
| `@openshared` | Open shared chat or user DM |
| `@pinchat` | Pin / unpin current chat |
| `@reaction` | React to message |
| `@refresh` | Refresh messages |
| `@refreshmedia` | Download and update image for message under cursor |
| `@saved` | Open Saved Messages |
| `@search` | Search message history |
| `@send` | Send a message to current chat |
| `@showarchived` | Toggle archived chats in picker |
| `@stoppoll` | Stop a poll |
| `@toggleheader` | Toggle floating title bar visibility |
| `@translate` | Translate message under cursor |
| `@translate_zh` | Translate message under cursor to Chinese |
| `@userinfo` | View profile of message sender |
| `@vote` | Vote on the poll message under cursor |
| `@voters` | List who voted on each poll option |

<!-- TOOLS_TABLE_END -->

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

<!-- KEYMAPS_TABLE_START -->
| Key name | Default | Action |
|----------|---------|--------|
| `translate_zh` | `tt` | translate message to Chinese |
| `tool_picker` | `@` | open tool picker |
| `input_editor` | `i` | open input editor |
| `reply` | `<CR>` | reply / jump to original |
| `edit` | `e` | edit own message |
| `delete` | `d` | delete / revoke |
| `forward` | `f` | forward message |
| `forward_with_reply` | `F` | forward with reply context |
| `pin` | `p` | pin / unpin message |
| `save` | `s` | save to Favorites |
| `copy` | `yy` | copy message text |
| `refresh` | `G` | refresh + jump to bottom |
| `ban` | `B` | ban message sender |
| `open_dm` | `c` | open DM with message sender |
| `help` | `?` | toggle this help |
| `editor_submit` | `<CR>` | submit message in editor |
| `editor_cancel` | `<Esc>` | cancel editing |
| `help_close` | `<Esc>` | close this help |
| `help_close_q` | `q` | close this help (alt) |
| `goto_last` | `<C-o>` | switch to previous chat |
| `reaction` | `r` | react to message |
| `archive` | `a` | archive/unarchive chat |
| `mark_unread` | `u` | mark unread / mark as read |
| `message_link` | `L` | copy message link |
| `user_profile` | `U` | view user profile |
| `mute` | `m` | mute / unmute chat |
| `perms_down` | `j` | permission editor: move down |
| `perms_up` | `k` | permission editor: move up |
| `perms_toggle` | `<Tab>` | permission editor: toggle item |
| `perms_up_alt` | `<S-Tab>` | permission editor: move up (alt) |
| `perms_save` | `<CR>` | permission editor: save |
| `perms_discard` | `<Esc>` | permission editor: discard |

<!-- KEYMAPS_TABLE_END -->

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
| `[Poll]` | Poll with progress bars. `@vote` to vote, `@voters` to see voters, `@stoppoll` to close |
| `[Contact]` | Contact shared |
| `[Location]` | Location shared |
| `🎲 5` / `🏀 3` etc. | Dice / emoji roll |
| `🎮 Title` | Game played |
| `[Call]` | Voice/video call |
| emoji character | Animated emoji (inline text) |
| `![Video](/thumbnail)` | Video thumbnail preview (click `@openlink` to play) |
| `👤 Name` / `📞 phone` | Contact shared |
| `📍 Name` / `address` / `🗺️ link` | Venue shared (click `@openlink` for map) |
| `📍 Live: lat, lng` | Live location with expiry |
| `💬 Chat shared: name` | Chat shared (click `@openshared` to open) |
| `👥 Users shared: ...` | Users shared (click `@openshared` for DM) |
| `⭐ Alice gifted Premium` | Premium gift / Stars / Gift code |
| `🎁 Alice sent a gift` | Gift message |
| `📱 Story` | Story share |
| `🔋 Chat boosted ×N` | Chat boost |
| `🎮 Score: +N` | Game score |
| `✅ Payment: N curr` | Successful payment |
| `📸 Screenshot taken` | Screenshot notification |
| `📅 / 🔊 / 🔇` | Video chat scheduled / started / ended |
| `📍 Proximity alert` | Proximity trigger |
| `📌 Topic renamed: ...` | Forum topic edited |
| `🎲 5` etc. | Stake dice (🎯🎳🎰 etc.) |
| `🎉 Giveaway created` / `🏆 Winners` / `✅ Completed` | Giveaway lifecycle |
| `⭐ Giveaway prize: N Stars` | Giveaway star prize |
| `💎 Alice gifted N TON` | TON gift |
| `📱 Joined Telegram` | Contact registered notification |
| `🔊 Group call started` / `📞 Missed` / `🔇 Ended` | Group call events |
| `🌐 WebApp: button` | WebApp data sent |
| `🎨 Theme set: name` | Chat theme changed |
| `🖼️ Background changed` | Chat background changed |

<!-- INSTALLATION_START -->
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

> The server auto-detects `libtdjson` on startup via `ldconfig`, `LD_LIBRARY_PATH`, and common paths. See [Configuration](#configuration) for details.
<!-- INSTALLATION_END -->

<!-- LUA_API_START -->
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
<!-- LUA_API_END -->

<!-- COMMANDS_START -->
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
<!-- COMMANDS_END -->

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

<!-- INPUT_EDITOR_START -->
## Input Editor

| Key | Action |
|-----|--------|
| `<CR>` | Send message / confirm edit |
| `Esc` | Cancel reply/edit/forward mode |
<!-- INPUT_EDITOR_END -->

<!-- MOUSE_START -->
## Mouse

Scrolling near the top/bottom of the buffer automatically loads older/newer messages.
<!-- MOUSE_END -->

## Auth Flow

First run of `:Tg`:

1. Backend starts on port 8080
2. TDLib enters authentication flow
3. Neovim shows an input prompt — **async and non-blocking**, you can keep editing
4. Enter: **phone number** → **verification code** → (optional) **2FA password**
5. On success, the group list opens automatically

Cancelling the input prompt (ESC / close dialog) aborts auth and cleans cached state. The next `:Tg` starts from scratch.

<!-- CONFIG_REFERENCE_START -->
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
  -- hide_title = false,  -- start with floating title bar hidden
  -- panel_position = "right",  -- "right" | "left" | "bottom" | "top"
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
<!-- CONFIG_REFERENCE_END -->

<!-- DATABASE_START -->
## Database

TDLib stores data in `data_dir/tdlib_db/` (SQLite + binlog) and files in `data_dir/tdlib_files/`.  
Delete these directories to force re-authentication.  
`:TgLogout` does this automatically.
<!-- DATABASE_END -->

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
