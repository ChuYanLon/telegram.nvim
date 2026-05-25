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

## 3. Your Development

1. Work directly on `main` or create a feature branch:
   ```
   git checkout -b feat/your-feature
   # write code...
   git add .
   git commit -m 'feat: short description'
   git push
   ```

2. Open a Pull Request targeting `main`.
