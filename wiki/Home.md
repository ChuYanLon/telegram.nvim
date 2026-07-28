# telegram.nvim

A Telegram chat client inside Neovim.

## Quick Start

1. Install the plugin, ensure `libtdjson` is available
2. Run `:Tg`
3. Enter phone number, verification code, 2FA password if needed
4. Chat list opens automatically — select a chat and start messaging

<!-- FEATURES_START -->
## Feature Status

### Messages
- Read text, media, links, code blocks, service messages in real-time via WebSocket
- Rich text highlighting: **bold**, *italic*, `code`, ~~strikethrough~~, ||spoiler||, [links](url) with distinct highlight groups
- Rich display for contacts (`👤`), venues (`📍` with map link), locations, invoices, gifts, calls, dice, and more
- Full service message coverage: screenshot, contact registered, proximity alert, theme/background changes, boosts, payments, web apps, admin events, and more
- Send/edit/delete/forward/reply with markdown formatting
- Polls: display with progress bars, vote (`@vote`), create (`@createpoll`), view voters (`@voters`), stop (`@stoppoll`). Supports multi-answer and timed polls.
- Search messages, copy text, save to Favorites
- Jump to any date with `@jump_to_date` — supports `YYYY-MM-DD`, `today`, `yesterday`
- Auto-download media with `@refreshmedia`, inline previews (photo/video/sticker/file)
- Read receipts, edited indicators, view counts, typing indicators

### Chat management
- Group, channel, and private chat (DM) support
- Member management: promote/demote, ban/unban, restrict, add by @username
- Invite links with member limit and expiration
- Group settings: title, description, granular permissions editor (14 types)
- Pin/unpin messages, react with emojis (40+), mark unread, archive chats
- Favorites (Saved Messages)

### UI & UX
- Configurable panel position (right/left/bottom/top)
- Rich text highlighting: **bold**, *italic*, `code`, ~~strikethrough~~, ||spoiler||, [links](url) in messages
- Footer metadata ([edited], views, reactions) styled with distinct highlight group
- Floating input editor with markdown treesitter highlight and reply preview
- Cursor persistence per chat, unread-aware loading with divider
- Scroll infinitely in both directions, date separators
- Statusline integration (lualine/heirline), help popup
- Theme adaptation (all highlights from your Neovim theme)
- Customizable keymaps, toggleable title bar with connection status
- Wake-up safe: batches messages received during sleep

### Authentication & connectivity
- Phone → code → 2FA flow, session persists across restarts
- `:TgLogout` to clear auth
- Online status with periodic heartbeat (shows as `telegram.nvim`)
- Real-time sync between devices
- Proxy support (SOCKS5 / HTTP) for restricted regions
- `:TgPr` — create/merge PRs with branch picker, squash option, auto-delete
- `:TgIssue` — browse issues, close, assign, create branches, open in browser

### Known limitations
- Send media (photos/videos/files/audio), stickers/GIFs
- Scheduled messages
- Inline bots / bot commands

### blink.cmp integration

telegram.nvim provides a [blink.cmp](https://github.com/saghen/blink.cmp) source for auto-completion in the input editor:

| Trigger | Input | Completes |
|---------|-------|-----------|
| `:` | `:heart` | ❤️ emoji (60+ names) |
| `@` | `@alice` | 👤 chat member mentions |
| `#` | `#dev` | 👥 chat/channel references |
| `/` | `/ty` | 💬 quick phrase templates |
| ``` ``` ``` | ```` ```lua```` | 🖥️ code block language (42 langs) |

Add to your blink.cmp setup:

```lua
sources = {
  { name = 'telegram', module = 'telegram.blink' },
}
```
<!-- FEATURES_END -->

### GitHub integration
- `:TgPr` — create/merge PRs with branch picker, squash option, auto-delete
- `:TgIssue` — browse issues, close, assign, create branches, open in browser

### `@` Tools

Available tools via the tool picker (`@` or `:TgTool`):

<!-- TOOLS_TABLE_START -->
| Tool | Description |
|------|-------------|
| `@archive` | Archive/unarchive current chat |
| `@blocked` | List and manage blocked users |
| `@channels` | Switch to a channel (filtered) |
| `@chats` | Switch to another chat |
| `@contacts` | Browse your contacts list |
| `@createpoll` | Create a poll in current chat |
| `@dm` | Switch to a private chat (filtered) |
| `@draft` | Save draft to server / clear draft |
| `@eventlog` | View recent admin events (member changes, edits, etc.) |
| `@folders` | Switch chat folder |
| `@groups` | Switch to a group (filtered) |
| `@groupsettings` | Group / channel settings (title, description, permissions, etc.) |
| `@invitelinks` | Manage invite links |
| `@joinrequests` | View and manage pending join requests |
| `@jump_to_date` | Jump to messages on a specific date |
| `@markunread` | Mark current chat as unread / read |
| `@members` | View and manage chat members |
| `@mentions` | Search @mentions in current chat |
| `@messagelink` | Copy shareable link of message under cursor |
| `@mute` | Mute / unmute current chat |
| `@myprofile` | View and edit your profile name and bio |
| `@newchat` | Start a new private chat by @username |
| `@openlink` | Open URL or media file under cursor |
| `@openshared` | Open shared chat or user DM |
| `@pinchat` | Pin / unpin current chat |
| `@reaction` | React to message |
| `@refresh` | Refresh messages |
| `@refreshmedia` | Download and update image for message under cursor |
| `@saved` | Open Saved Messages |
| `@search` | Search message history |
| `@send` | Send a message to current chat |
| `@showarchived` | Toggle archived chats in picker |
| `@stoppoll` | Stop a poll |
| `@toggleheader` | Toggle floating title bar visibility |
| `@translate` | Translate message under cursor |
| `@translate_zh` | Translate message under cursor to Chinese |
| `@userinfo` | View profile of message sender |
| `@vote` | Vote on the poll message under cursor |
| `@voters` | List who voted on each poll option |

<!-- TOOLS_TABLE_END -->

## Project Structure

```
lua/telegram/     # Neovim frontend (Lua)
src/              # TypeScript backend (Express + TDLib)
bin/              # Helper scripts
plugin/           # Plugin loader
```
