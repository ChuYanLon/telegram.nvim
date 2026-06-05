# telegram.nvim

A Telegram chat client inside Neovim.

## Quick Start

1. Install the plugin, ensure `libtdjson` is available
2. Run `:Tg`
3. Enter phone number, verification code, 2FA password if needed
4. Chat list opens automatically — select a chat and start messaging

## Features

- Chat UI with virtual scrolling, cursor position memory per chat
- Real-time message push via WebSocket (sync edits, deletions, group info changes from other clients)
- Send, edit, delete/recall, forward messages
- Reply with context preview, highlighted reply/edit/delete/forward targets
- React to messages with 40+ verified emojis (`r` key), synced across devices in real-time
- Favorites — dedicated chat always in list; press `s` on any message to save with confirmation
- View counts — channel messages show `👀 N` footer; real-time sync
- Read receipts — outgoing private messages show `(read HH:MM)` when read
- Message search within a chat
- Media display (photos, video, documents, stickers, audio, voice)
- Typing indicators in title bar, online member count
- Multi-line input editor with placeholder
- Tool system (`@` key): group switcher, refresh, quick send, search, refresh media
- Group management: view members (incl. admins), ban/unban, restrict/unrestrict, promote/demote, add members by @username
- Granular default permissions editor with interactive floating window and toggle-all
- Invite links: create (with expiry + member limit), view, edit, revoke
- GitHub integration: PR creation (`:TgPr`), issue browser (`:TgIssue`)
- Full auth flow (phone → code → 2FA), logout support
- Proxy support (SOCKS5/HTTP) for restricted regions
- Theme-adaptive colors — all highlights derive from your Neovim theme (`Comment`, `DiffAdd`, `DiagnosticOk`, etc.)
- Lualine integration — drop `require("telegram").lualine` into your lualine config for connection status, unread count, and @mention indicators

## Project Structure

```
lua/telegram/     # Neovim frontend (Lua)
src/              # TypeScript backend (Express + TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
```
