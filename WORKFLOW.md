telegram.nvim 工作流程指南
===========================

一、分支命名规范
------------------
创建分支时使用前缀 + 描述，例如：

| 前缀 | 用途 | 示例 |
|------|------|------|
| `feat/` | 新功能 | `feat/add-rich-text` |
| `fix/` | 修 Bug | `fix/message-dup` |
| `chore/` | 杂项（依赖、配置） | `chore/update-deps` |
| `docs/` | 文档 | `docs/fix-typo` |
| `refactor/` | 重构 | `refactor/tdlib-client` |
| `style/` | 代码格式 | `style/indent-fix` |

二、其他人贡献代码
-------------------
1. Fork 仓库
2. 在自己的 fork 创建分支（如 `fix/login-crash`）
3. 提交代码
4. 开 Pull Request（PR）到上游的 dev 分支
5. 你审核 → 合并到 dev

三、你自己开发
----------------
1. 在 dev 分支上开发
   git checkout dev
   （写代码...）
   git add .
   git commit -m 'fix: 描述你的修改'
   git push

2. 合并 dev 到 main
   a. 打开 https://github.com/ChuYanLon/telegram.nvim/compare/dev?expand=1
   b. 点 "Create pull request"
   c. 写标题和描述
   d. 点 "Create pull request"
   e. 等 CI 检查通过（显示绿色 ✓）
   f. 点 "Merge pull request" → "Confirm merge"

四、注意事项
---------------
- 永远不要在 main 分支上直接开发
- dev 分支保持与 main 同步：
  git checkout dev
  git pull --rebase origin main
  git push

二、你自己开发
---------------
1. 在 dev 分支上开发
   git checkout dev
   （写代码...）
   git add .
   git commit -m '你的修改'
   git push

2. 合并 dev 到 main
   a. 打开 https://github.com/ChuYanLon/telegram.nvim/compare/dev?expand=1
   b. 点 "Create pull request"
   c. 写标题和描述
   d. 点 "Create pull request"
   e. 等 CI 检查通过（显示绿色 ✓）
   f. 点 "Merge pull request" → "Confirm merge"

三、注意事项
---------------
- 永远不要在 main 分支上直接开发
- dev 分支保持与 main 同步：
  git checkout dev
  git pull --rebase origin main
  git push
