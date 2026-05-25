## Requirements

- Node.js >= 18
- curl
- libtdjson (TDLib shared library, minimum 1.8.64)

## Install with lazy.nvim

```lua
{
  "ChuYanLon/telegram.nvim",
  build = "npm i",
  cmd = { "Tg", "TgLogout" },
  keys = {
    { "<leader>tt", "<cmd>Tg<Cr>" },
    { "<leader>tL", "<cmd>TgLogout<Cr>" },
  },
  opts = {},
}
```

`build = "npm i"` installs Node.js dependencies automatically.

## Installing libtdjson

**Arch Linux:** `sudo pacman -S tdlib`

**macOS:** `brew install tdlib`

**Other Linux:** Build from source ([instructions](https://github.com/tdlib/td#building)).
