# Contributing

Thank you for considering contributing to telegram.nvim!

## Development Setup

```bash
git clone https://github.com/ChuYanLon/telegram.nvim.git
cd telegram.nvim
pnpm install
```

## Project Structure

```
├── lua/telegram/          # Neovim Lua frontend
│   ├── init.lua           # Entry point, message handling, WS routing
│   ├── ui.lua             # UI rendering (popups, keymaps, virtual scroll)
│   ├── server.lua         # HTTP client to backend (curl-based, retry)
│   ├── ws.lua             # WebSocket client (subprocess, reconnect)
│   ├── auth.lua           # Authentication flow
│   ├── config.lua         # Configuration, highlight groups
│   ├── editor.lua         # Input editor component
│   ├── tools.lua          # Extensible tool system (@ key)
│   └── render/            # Message rendering pipeline
│       ├── init.lua
│       ├── text.lua
│       ├── code.lua
│       ├── link.lua
│       ├── media.lua
│       └── other.lua
├── src/                   # TypeScript backend (tsx runtime)
│   ├── server.ts          # Express + WebSocket server
│   ├── client.ts          # TelegramLSPClient orchestrator
│   ├── types.ts           # Shared TS interfaces
│   ├── tdlib.ts           # libtdjson path auto-detection
│   ├── auth.ts            # AuthManager (phone → code → 2FA)
│   ├── format.ts          # Message formatting
│   ├── resolve.ts         # Sender resolution caching
│   └── updates.ts         # WebSocket update dispatcher
├── bin/                   # Helper scripts (tg-ws-helper.ts)
├── plugin/tg.lua          # Plugin loader
└── tests/                 # Vitest tests (FakeTdClient)
```

## Code Style

- **Lua**: Follow existing patterns. Use tabs for indentation. No semicolons.
- **TypeScript**: Full type annotations. Use `_` instead of `@type` for TDLib objects.
- Keep functions focused and well-named. Avoid unnecessary comments.
- No build step — `tsx` runs TypeScript directly from source.

## Making Changes

1. Fork the repo and create a branch from `main` (e.g. `fix/login-crash`)
2. Make your changes
3. Test locally:
   - `pnpm test` to verify tests pass
   - `pnpm typecheck` to verify TypeScript types
   - `pnpm start` to check the backend starts
4. Commit and push
5. Open a Pull Request targeting the `main` branch
6. CI will run automatically on your PR (test + typecheck)

## Commit Messages

Use concise, descriptive commit messages in English. Focus on the "why" rather than the "what".

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
