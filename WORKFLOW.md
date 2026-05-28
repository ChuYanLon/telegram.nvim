# telegram.nvim Workflow Guide

## 1. Branch Naming Convention

Use a prefix + short description when creating branches:

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feat/` | New feature | `feat/add-rich-text` |
| `fix/` | Bug fix | `fix/message-dup` |
| `chore/` | Maintenance (deps, config) | `chore/update-deps` |
| `docs/` | Documentation | `docs/fix-typo` |
| `refactor/` | Code refactoring | `refactor/tdlib-client` |
| `style/` | Code formatting | `style/indent-fix` |

## 2. External Contributions

1. Fork the repository
2. Create a branch on your fork (e.g. `fix/login-crash`)
3. Write code and commit
4. Open a Pull Request targeting the `main` branch
5. Maintainer reviews and merges

## 3. Development Workflow

1. Create a feature/fix branch from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```
2. Make changes and test:
   ```bash
   pnpm test
   pnpm typecheck
   pnpm start
   ```
3. Commit and push:
   ```bash
   git add .
   git commit -m 'feat: short description'
   git push -u origin feat/your-feature
   ```
4. Open a Pull Request targeting `main`
5. Use `:TgPr` from Neovim to create and optionally merge the PR
6. After merge, the source branch auto-deletes

> **Note:** `main` is a protected branch — do not push directly. Always work on a feature branch.
