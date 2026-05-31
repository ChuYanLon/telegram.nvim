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
- Message search within a chat
- Media display (photos, video, documents, stickers, audio, voice)
- Typing indicators in title bar, online member count
- Multi-line input editor with placeholder
- Tool system (`@` key): group switcher, refresh, quick send, search, refresh media
- GitHub integration: PR creation (`:TgPr`), issue browser (`:TgIssue`)
- Full auth flow (phone → code → 2FA), logout support
- Proxy support (SOCKS5/HTTP) for restricted regions

## Project Structure

```
lua/telegram/     # Neovim frontend (Lua)
src/              # TypeScript backend (Express + TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
```
