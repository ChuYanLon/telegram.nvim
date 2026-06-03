# Changelog

## [0.5.2] - 2026-06-03

### Performance

- **Message window capped at 200** — `state.messages` no longer grows unbounded; trimmed on scroll and new message arrival to prevent long-session lag
- **CursorMoved handler debounced** — O(n) message scan and pagination trigger deferred to 50ms after last cursor movement, eliminating jank on rapid scrolling
- **`curl_with_retry` timeouts reduced** — retries 4→2, max-time 15s→5s, connect-timeout 5s→2s for faster failure recovery
- **Chat title update debounced** — `VimResized`/`WinScrolled` no longer share the same augroup (VimResized was silently dropped)
- **`close_chat` non-blocking** — replaced synchronous `vim.fn.system("curl")` with fire-and-forget `request_async`, preventing exit freeze
- **Timer leaks fixed** — `refresh_timer`, `_scroll_timer`, `_typing_timer`, `_title_update_timer` now properly stopped in `destroy_chat`, logout, and VimLeavePre
- **`_edit_ts` stale entries cleaned** — expired edit debounce timestamps removed on each new edit

### Caching

- **`_users` cache** — capped at 5,000 entries with gentle FIFO eviction; updated in real-time via `updateUser` events
- **`_chats` cache** — capped at 500 entries; new chats from `updateNewChat` evict oldest when full; individual chat inserts use `_cacheChat`
- **`_pinnedMessageIds` cache** — capped at 200 entries; pin/unpin events update cache; unpin removes entry

### Fixed

- **Exit freeze on Neovim close** — server now exits immediately on SIGTERM (without awaiting TDLib close), Neovim doesn't wait for the job
- **First-exit lag** — TDLib's first-time database finalization no longer blocks Neovim's shutdown
- **Remote session termination** — `updateAuthorizationState` (closed/logging-out) clears all caches and notifies Lua UI
- **Stale typing indicators** — `typing_users` entries for the previous chat are cleaned up on `open_chat` switch

### Changed

- **SIGTERM exits immediately** — closes HTTP/WS servers and calls `process.exit(0)` without `tgClient.shutdown()`; SIGINT (Ctrl+C) still does graceful shutdown
- **`getGroups()` always fetches fresh** — reverted to `getChats(true)` to avoid stale chat list when chats are removed

## [0.5.0] - 2026-06-01

### Added

- **Customizable keymaps** — all 21 keymaps configurable via `setup({ keys = { ... } })`; set to `false` to disable
- **Theme-adaptive highlights** — all highlight groups derive from Neovim theme (`Comment`, `DiffAdd`, `DiagnosticOk`, etc.) with no hardcoded colors
- **Granular default permissions editor** — interactive floating window with 14 permission toggles, toggle-all switch, color-coded highlights for enabled/disabled/unknown states
- **Edit invite links** — frontend wrapper and UI entry for editing invite links (member limit + expiration)
- **Expiration support for invite links** — create/edit invite links with optional expiry time
- **@username search for adding members** — search by username instead of raw numeric user ID
- **Invite link fallback** — when adding a member to a supergroup fails, the invite link is returned to the user instead of a generic error
- **Member list includes admins and creator** — dual-filter search merges `chatMembersFilterAdministrators` and `chatMembersFilterMembers`
- **WebSocket sync for chat metadata** — user name changes, online/offline status, group description/member count, group kicked/banned now sync in real-time from other clients
- **Online status** — user is marked as online after login with periodic heartbeat (30s), visible to other clients
- **Device model** — session shows as `telegram.nvim` (with version and OS) in Telegram device list
- **Defensive error guards** — `getChatInviteLinks` handles `getMe()` failure; `handleChatMemberUpdate` guards undefined user IDs; SIGTERM now does graceful shutdown

### Fixed

- **Channel unsubscribe now actually leaves** — changed from `deleteChatHistory` to `leaveChat`
- **`restrictChatMember`/`unrestrictChatMember` not working** — used wrong TDLib field `can_send_messages` instead of `can_send_basic_messages`
- **Member actions shown regardless of status** — Ban/Unban/Restrict/Promote now dynamically shown based on member's current status
- **promoteChatMember grants `can_promote_members`** — removed to prevent privilege escalation
- **Title float covering messages** — buffer padding now syncs with float height on every `update_title()` call, preventing overlap (#123)
- **Cursor move freeze** — `msg_line_counts` cache eliminates `#fmt_msg()` re-render on every cursor movement
- **WinScrolled storm** — debounced `update_title()` calls (100ms) reduce float recreation overhead on scroll
- **User name not updating in rendered messages** — on `userUpdate`, sender names in existing messages are refreshed via `render()`
- **`ChatPosition` event name mismatch** — migrated from `broadcastRaw` (uppercase) to explicit lowercase handler
- **`truncate_text` negative width** — pinned message/description titles no longer break at narrow window widths

### Changed

- **Removed nui.nvim dependency** — help popup and input editor migrated from `nui.popup` to built-in `nvim_open_win`
- **`request_async`** — restored to prefer `vim.net.request` with curl fallback (reverted experimental change)
- **`set_groups`** — now stores `user_id` for private chat lookups

## [0.4.0] - 2026-05-28

### Added

- **`:TgPr` squash merge** — now offers "squash" and "commit" merge strategies when merging PRs
- **Private chat support** — press `c` on a message to open DM with sender; `@newchat` tool to start DM by @username
- **Snacks picker** — chat picker now uses `snacks.nvim` with fuzzy search, falls back to `vim.ui.select`
- **Confirmation prompt before opening DM** — `vim.ui.select` asks Yes/No before opening a private chat
- **ImageMagick requirement** — documented in README for image display in Kitty terminal

### Changed

- **Updated all documentation** — CONTRIBUTING, WORKFLOW, wiki pages, PR template, and CHANGELOG synced with current TypeScript architecture and feature set
- **Terminology** — user-facing text unified to use "chat" instead of "group" (picker, help popup, notifications)
- **Online count** — now fetched synchronously from TDLib on chat open with cache fallback; stale 0 values from WebSocket ignored
- **Typing indicator** — shown in a floating popup below the winbar instead of replacing the title bar
- **Service message prefixes** — changed from markdown-significant characters (`+`, `-`, `*`, `>`) to bracket format (`[+]`, `[-]`, `[*]`, `[>]`)
- **README screenshots** — reorganized with new screenshot categories and Image Preview section

### Fixed

- **Service message highlighting** — added `TgService` highlight group for service messages
- **Wiki sync workflow** — pull rebase before push to avoid push conflicts
- **Online count** - stale 0 values from WebSocket no longer overwrite cached counts

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
