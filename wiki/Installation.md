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

Build from source on all platforms:

```bash
git clone https://github.com/tdlib/td.git
cd td
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=~/.local \
    -DCMAKE_CXX_FLAGS="-O2 -g0" \
    ..
cmake --build . --target install -j$(nproc)
ldconfig 2>/dev/null || true
```

The plugin auto-detects `libtdjson` via `ldconfig`, `LD_LIBRARY_PATH`, and common paths.


