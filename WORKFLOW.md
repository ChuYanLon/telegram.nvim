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
4. Open a Pull Request targeting the `dev` branch
5. Maintainer reviews and merges to `dev`

## 3. Your Development

1. Work on the `dev` branch:
   ```
   git checkout dev
   # write code...
   git add .
   git commit -m 'fix: short description'
   git push
   ```

2. Merge `dev` to `main`:
   - Open https://github.com/ChuYanLon/telegram.nvim/compare/dev?expand=1
   - Click "Create pull request"
   - Write title and description
   - Click "Create pull request"
   - Wait for CI to pass (green checkmark ✓)
   - Click "Merge pull request" → "Confirm merge"

   Or use `:TgPr` inside Neovim (requires `gh` CLI).

## 4. Notes

- Never commit directly to `main`
- Keep `dev` in sync with `main` after merges:
  ```
  git checkout dev
  git pull --rebase origin main
  git push
  ```
- This is handled automatically when using `:TgPr` to merge to `main`.
