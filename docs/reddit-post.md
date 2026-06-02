# Reddit r/neovim 发帖草稿

Title: telegram.nvim — a full Telegram client inside Neovim (TDLib + TypeScript + Lua)

Body:

```
I've been building telegram.nvim — a Telegram chat client that runs entirely inside Neovim.

It uses TDLib via a TypeScript backend + Lua frontend, communicating over HTTP and WebSocket.

**What works:**
- Real-time messaging (send/receive via WebSocket)
- Group & channel management (members, permissions, invite links)
- Photo / video / file previews
- Send formatted messages (markdown)
- Edit, delete, forward, reply, pin messages
- Group admin tools (ban, restrict, promote)
- Typing indicators & online member count
- Session persistence (no re-login)
- Proxy support (SOCKS5/HTTP)
- Customizable keymaps
- GitHub PR & Issue integration (:TgPr, :TgIssue)
- HD media download (@refreshmedia)

**Tech stack:**
- TDLib (C++) → TypeScript (Express + WebSocket) → Lua (Neovim plugin)
- No build step — runs via tsx

Install with lazy.nvim:
```lua
{
  "ChuYanLon/telegram.nvim",
  build = "npm i",
  event = "VeryLazy",
  keys = { { "<leader>tt", "<cmd>Tg<Cr>", desc = "Toggle Telegram" } },
  opts = {},
}
```

Requires libtdjson + Node.js ≥ 18.

GitHub: https://github.com/ChuYanLon/telegram.nvim
Docs: https://chuyanlon.github.io/telegram.nvim

Would love feedback and contributions!
```
