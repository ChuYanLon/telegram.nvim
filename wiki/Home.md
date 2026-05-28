# telegram.nvim

A Telegram chat tool for Neovim, similar to telegra.el.

Backend powered by TDLib + Node.js (TypeScript), frontend in pure Lua with HTTP + WebSocket communication.

## Quick Start

1. Install the plugin (see [Installation](Installation))
2. Run `:Tg`
3. Enter your phone number, verification code, and 2FA password if needed
4. The group list opens automatically

## Features

- Group list with unread badges and inline fuzzy search (Snacks picker with `vim.ui.select` fallback)
- **Private chats** — press `c` on a message to open DM with sender, or use `@newchat` tool
- Real-time message push via WebSocket
- Infinite scroll in both directions (older and newer messages)
- Send, edit, delete/recall, forward messages
- Reply to messages with quoted context
- Markdown formatting in messages
- Message search with context jump
- Typing indicators and online member count
- Media preview (photo, sticker, video, file) — works with `snacks.nvim`
- HD media download via `@refreshmedia`
- Auth flow (phone → code → 2FA), session persists across restarts
- Proxy support for restricted regions
- `:TgPr` — create and merge GitHub PRs
- `:TgIssue` — list, create branch, close, assign issues
- Context-aware tool picker (`@` key)

## Project Structure

```
lua/telegram/     # Neovim frontend
src/              # TypeScript backend (TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
tests/            # Vitest tests
```
