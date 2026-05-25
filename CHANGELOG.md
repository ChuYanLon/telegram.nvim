# Changelog

## [Unreleased]

### Added

- Feature progress table in README with per-category tracking
- `vim.notify` calls now use `title` option instead of `[tg]` text prefix
- Issue templates (bug report, feature request)
- Pull request template
- Contributing guide
- Code of Conduct
- CI workflow

### Fixed

- Various `vim.notify` calls: `[tg]` prefix moved to notification title

## [0.2.0] - 2026-05-25

### Fixed

- **Message dedup** — use message ID instead of text+time heuristic (#8)
- **Cross-chat reply** — `_formatReplyTo` now fetches original message from source chat (#7)
- **Chat wrapper** — `getMessagesAfter`/`getMessagesAround` now include `chat` object (#2)

### Added

- **`:TgIssue` command** — list, create branch, close, assign issues
- **Branch auto-delete** — `:TgPr` deletes source branch after merge (except dev/main)
- **Multi-instance support** — share one server across Neovim instances
- **Unit tests** — Vitest + FakeTdClient, no TDLib dependency
- **`dev` branch protection** — ruleset prevents direct pushes/deletion

## [0.1.0] - 2025-05-25

### Added

- Initial release
- Group list (supergroups / basic groups)
- Message viewing with bidirectional auto-load
- Send, edit, delete/recall, forward messages
- Reply to messages with quoted context
- Message search with context jump
- Real-time WebSocket push for new messages
- Typing indicators (receive + broadcast)
- Online member count
- Multi-line input editor (NuiPopup)
- Auth flow (phone → code → 2FA)
- Proxy support
- Auto-detect libtdjson
- Virtual-scrolled groups panel
- Cursor position persistence
- Target highlighting (reply/edit/delete/forward)
- Async non-blocking UI
