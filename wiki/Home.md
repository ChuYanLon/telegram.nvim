# telegram.nvim

A Telegram chat client inside Neovim.

## Quick Start

1. Install the plugin, ensure `libtdjson` is available
2. Run `:Tg`
3. Enter phone number, verification code, 2FA password if needed
4. Chat list opens automatically — select a chat and start messaging

## Features

### Messages
- Read text, media, links, code blocks, service messages in real-time via WebSocket
- Send/edit/delete/forward/reply with markdown formatting
- Search messages, copy text, save to Favorites
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

### GitHub integration
- `:TgPr` — create/merge PRs with branch picker, squash option, auto-delete
- `:TgIssue` — browse issues, close, assign, create branches, open in browser

## Project Structure

```
lua/telegram/     # Neovim frontend (Lua)
src/              # TypeScript backend (Express + TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
```
