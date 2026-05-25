# telegram.nvim

A Telegram chat tool for Neovim, similar to telegra.el.

## Quick Start

1. Install the plugin (see [README](https://github.com/ChuYanLon/telegram.nvim))
2. Run `:Tg`
3. Enter your phone number, verification code, and 2FA password if needed
4. The group list opens automatically

## Features

- Group list with virtual scrolling
- Real-time message push via WebSocket
- Send, edit, delete/recall, forward messages
- Reply to messages with context
- Message search
- Typing indicators
- Online member count
- Multi-line input editor
- Auth flow (phone → code → 2FA)
- Proxy support for restricted regions

## Project Structure

```
lua/telegram/     # Neovim frontend
src/              # Node.js backend (TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
```
