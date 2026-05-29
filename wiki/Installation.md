## Requirements

- **Neovim >= 0.9** (with LuaJIT)
- **Node.js >= 18**
- **curl**
- **libtdjson** (TDLib shared library, minimum **1.8.64**)

## Install with lazy.nvim

```lua
{
  "ChuYanLon/telegram.nvim",
  build = "npm i",
  cmd = { "Tg", "TgLogout", "TgSend", "TgTool", "TgIssue", "TgPr" },
  keys = {
    { "<leader>tt", "<cmd>Tg<Cr>" },
  },
  opts = {},
}
```

`build = "npm i"` installs Node.js dependencies (tsx, express, etc.) automatically.

## Installing libtdjson

| OS | Command |
|----|---------|
| **Arch Linux** | `sudo pacman -S tdlib` |
| **macOS** | `brew install tdlib` |
| **Ubuntu/Debian** | Build from source |
| **Windows** | Download from TDLib releases |

For other Linux distros, build from [source](https://github.com/tdlib/td#building). The plugin auto-detects `libtdjson` via `ldconfig`, `LD_LIBRARY_PATH`, and common paths.


