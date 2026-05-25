# Contributing

Thank you for considering contributing to telegram.nvim!

## Development Setup

```bash
git clone -b dev https://github.com/ChuYanLon/telegram.nvim.git
cd telegram.nvim
pnpm install
```

## Project Structure

```
├── lua/telegram/          # Neovim Lua frontend
│   ├── init.lua           # Entry point, message handling
│   ├── ui.lua             # UI rendering (popups, keymaps)
│   ├── server.lua         # HTTP client to backend
│   ├── ws.lua             # WebSocket client
│   ├── auth.lua           # Authentication flow
│   └── config.lua         # Configuration
├── src/                   # Node.js backend
│   ├── server.js          # Express + WebSocket server
│   └── tdlib-client.js    # TDLib wrapper
├── bin/                   # Helper scripts
└── plugin/tg.lua          # Plugin loader
```

## Code Style

- **Lua**: Follow existing patterns. Use tabs for indentation. No semicolons.
- **JavaScript**: CommonJS modules. Use `_` instead of `@type` for TDLib objects.
- Keep functions focused and well-named. Avoid unnecessary comments.
- No build step — plain CJS JS and Lua.

## Making Changes

1. Fork the repo and create a branch from `dev` (e.g. `fix/login-crash`)
2. Make your changes
3. Test locally — `pnpm run test` to verify tests pass, `pnpm start` to check the backend starts
4. Commit and push
5. Open a Pull Request **targeting the `dev` branch** (not `main`)
6. CI will run automatically on your PR

## Commit Messages

Use concise, descriptive commit messages in English. Focus on the "why" rather than the "what".

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
