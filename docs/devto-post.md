# Dev.to 文章草稿

Title: Building a Telegram Client Inside Neovim with TDLib and TypeScript

Tags: neovim, telegram, typescript, lua, tui

---

Outline:

1. **Why a Telegram client in Neovim?**
   - Stay in the terminal, context switching costs
   - telegra.el inspired, but for Neovim users
   - Vim keybindings for chat navigation

2. **Architecture overview**
   - TDLib handles the Telegram protocol (auth, messages, groups)
   - TypeScript backend: Express HTTP + WebSocket server
   - Lua plugin: buffer rendering, keymaps, UI
   - `bin/tg-ws-helper.ts` for WebSocket relaying
   - Device identified as "telegram.nvim"

3. **Key challenges**
   - Async auth flow (phone → code → 2FA) non-blocking
   - Infinite scroll in both directions
   - Real-time sync (edits, deletes, typing) via WebSocket
   - Rendering markdown-formatted messages with Treesitter
   - State management across Vim events (CursorMoved, WinScrolled)

4. **Features highlight**
   - Single-panel layout with floating input popup
   - Inline fuzzy-find chat picker (Snacks/vim.ui.select)
   - Permissions editor (14 toggle types)
   - HD media download
   - GitHub integration (:TgPr, :TgIssue)

5. **What I learned**
   - TDLib event-driven model
   - Lua/JIT performance for buffer rendering
   - WebSocket heartbeat and reconnection

6. **Links**
   - GitHub: https://github.com/ChuYanLon/telegram.nvim
   - Docs: https://chuyanlon.github.io/telegram.nvim
