## Requirements

- Node.js >= 18
- curl
- libtdjson (TDLib shared library, minimum 1.8.64)
- nui.nvim (automatically installed by lazy.nvim)
- gh (GitHub CLI) — optional, required for `:TgPr` and `:TgIssue`

## Install with lazy.nvim

```lua
{
  "ChuYanLon/telegram.nvim",
  build = "npm i",
  event = "VeryLazy",
  dependencies = { "MunifTanjim/nui.nvim" },
  keys = {
    { "<leader>tt", "<cmd>Tg<Cr>", desc = "Toggle Telegram" },
    { "<leader>tL", "<cmd>TgLogout<Cr>", desc = "Logout Telegram" },
    { "<leader>tp", "<cmd>TgPr<Cr>", desc = "Create PR" },
    { "<leader>ti", "<cmd>TgIssue<Cr>", desc = "Manage Issues" },
  },
  cmd = { "Tg", "TgLogout", "TgPr", "TgIssue" },
  opts = {},
}
```

`build = "npm i"` installs Node.js dependencies automatically on first install.

## Installing libtdjson

**Arch Linux:** `sudo pacman -S tdlib`

**macOS:** `brew install tdlib`

**Other Linux:** Build from source ([instructions](https://github.com/tdlib/td#building)).
