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

1. Fork the repo and create a branch from `master`
2. Make your changes
3. Test locally — run `pnpm start` to verify the backend starts
4. Submit a pull request

## Commit Messages

Use concise, descriptive commit messages in English. Focus on the "why" rather than the "what".

## Pull Request Process

1. Update the README / Progress section if adding or changing features
2. Ensure the PR description clearly describes the problem and solution
3. Link any related issues

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
