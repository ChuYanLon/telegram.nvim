# Changelog

## [Unreleased]

### Added

- **`:TgPr` squash merge** — now offers "squash" and "commit" merge strategies when merging PRs

### Changed

- **Updated all documentation** — CONTRIBUTING, WORKFLOW, wiki pages, PR template, and CHANGELOG synced with current TypeScript architecture and feature set

### Changed

- **Removed dev branch** — workflow is now main-only; CI only triggers on main; branch creation bases on main instead of dev

## [0.3.1] - 2026-05-26

### Changed

- **Migrated from JS to TypeScript** — full type annotations, module split (auth, format, resolve, updates, tdlib), tsconfig, tsx runtime
- **Converted tests to TypeScript** — client.test.ts, fake-td-client.ts, server.test.ts

### Fixed

- **editMessage** — ensure chatId/messageId are numbers to avoid TDLib "Message not found"
- **Editor state** — clear edit target highlight and border indicator after editing

## [0.3.0] - 2026-05-26

### Added

- **WebSocket auto-reconnect** — exponential backoff (1s → 2s → 4s → ... → 30s max) on connection drop (#3)
- **Lua HTTP retry** — `http_get`/`http_post` retry up to 3 times with backoff on transient failures (#6)
- **Test coverage** — 13 new tests for `getChat`, `handleNewMessage`, `handleChatMemberUpdate`, `handleChatOnlineMemberCount`, `handleChatAction`, `handleUserChatAction`, `_formatMessage` with `messageChatAddMembers`
- **`updateChatAction` handling** — separate handler resolves `sender_id` (MessageSender) instead of missing `user_id` (#62)

### Fixed

- **Blocking `vim.wait`** — replaced with `vim.defer_fn`-based async polling in `list_groups`, no more UI freeze (#64)
- **`getChat` crash** — non-group/unknown chat types no longer throw 500 on `/chat` endpoint (#63)
- **Member add display** — `messageChatAddMembers` now shows "X added Y" instead of "X joined" when someone invites another member (#98)
- **Navigation direction** — `<C-h>`/`<C-l>` now consistently go to groups/msg instead of toggling (#61)

### Performance

- **Batch sender resolution** — pre-resolve all unique senders before formatting bulk messages, eliminating redundant `getUser` calls (#5)
- **Break-early filter** — `getMessagesAfter` stops iterating once messages ≤ afterId are reached (#9)

### Styles

- **Consistent indentation** — all Lua files reformatted with `stylua` to use tab indentation, aligning with `.editorconfig` (#97)

## [0.2.1] - 2026-05-25

### Fixed

- **Duplicate messages** — own messages no longer appear twice due to send response / WebSocket race (#8 follow-up)

## [0.2.0] - 2026-05-25

### Fixed

- **Message dedup** — use message ID instead of text+time heuristic (#8)
- **Cross-chat reply** — `_formatReplyTo` now fetches original message from source chat (#7)
- **Chat wrapper** — `getMessagesAfter`/`getMessagesAround` now include `chat` object (#2)
- `vim.notify` calls now use `title` option instead of `[tg]` text prefix

### Added

- **`:TgIssue` command** — list, create branch, close, assign issues
- **Branch auto-delete** — `:TgPr` deletes source branch after merge (except main)
- **Multi-instance support** — share one server across Neovim instances
- **Unit tests** — Vitest + FakeTdClient, no TDLib dependency

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
