## Chat Window

| Key | Action |
|-----|--------|
| `?` | Toggle help popup |
| `i` | Open input editor to send a message |
| `<CR>` | Reply to message / jump to original (if cursor is on a quote line) |
| `e` | Edit own message at cursor |
| `d` | Delete message — prompts Revoke (for everyone) / Delete (for me) |
| `f` | Forward message to another chat |
| `c` | Open DM with the sender of the message at cursor |
| `G` | Refresh messages and jump to bottom |
| `@` | Open context-aware tool picker |

## Chat Picker (`@` → chats)

- Built-in fuzzy search (Snacks picker when available, `vim.ui.select` fallback)
- `<CR>` — select chat
- `<Esc>` — close

## Input Editor

| Key | Action |
|-----|--------|
| `<CR>` | Send message / confirm edit |
| `Esc` | Cancel reply/edit mode |
