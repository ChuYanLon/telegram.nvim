local server = require('telegram.server')

---@class TgSender
---@field id any
---@field name string

---@class TgMessage
---@field id any
---@field date integer
---@field sender TgSender|nil
---@field text string|nil
---@field replyTo {id:any, sender:TgSender|nil, text:string|nil}|nil

---@class TgState
---@field buf integer|nil
---@field win integer|nil
---@field chat_id any|nil
---@field chat_title string
---@field messages TgMessage[]
---@field loading boolean
---@field exhausted boolean
---@field unread integer
---@field last_chat {id:any, title:string}|nil
---@field menu_buf integer|nil
---@field menu_win integer|nil
---@field last_msg string|nil

local M = {}

---@type TgState
local state = {
  buf = nil,
  win = nil,
  chat_id = nil,
  chat_title = '',
  messages = {},
  loading = false,
  exhausted = false,
  unread = 0,
  last_chat = nil,
  menu_buf = nil,
  menu_win = nil,
  last_msg = nil,
}

M.state = state

---@param lines string[]
local function set_lines(lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', false)
end

---@param msg TgMessage
---@return string[]
local function fmt_msg(msg)
  local date_str = os.date('%m-%d %H:%M', msg.date)
  local sender = msg.sender and msg.sender.name or 'unknown'
  local out = {}
  if msg.replyTo then
    local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or '?'
    local r_text = msg.replyTo.text and msg.replyTo.text:gsub('\n', ' ') or ''
    if #r_text > 50 then r_text = r_text:sub(1, 50) .. '...' end
    table.insert(out, '\xE2\x95\xAD\xE2\x94\x80 to ' .. r_sender .. ' \xE2\x94\x80\xE2\x95\xAE')
    table.insert(out, '  \xE2\x94\x82 ' .. r_text)
  end
  local parts = vim.split(msg.text or '', '\n')
  table.insert(out, string.format('[%s] %s: %s', date_str, sender, parts[1]))
  for i = 2, #parts do
    table.insert(out, '  ' .. parts[i])
  end
  return out
end

local hl_ns = vim.api.nvim_create_namespace('TgChat')

local function apply_highlights()
  vim.api.nvim_buf_clear_namespace(state.buf, hl_ns, 0, -1)
  local total = vim.api.nvim_buf_line_count(state.buf)
  for line = 0, total - 1 do
    local text = vim.api.nvim_buf_get_lines(state.buf, line, line + 1, false)[1]
    if not text then break end
    if text:byte(1) == 0xE2 and text:byte(2) == 0x95 and text:byte(3) == 0xAD then
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgReplyIndicator', line, 0, #text)
    elseif text:byte(1) == 0x20 and text:byte(2) == 0x20 and text:byte(3) == 0xE2 and text:byte(4) == 0x94 then
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgReplyIndicator', line, 2, 6)
    else
      local _, ts_end = text:find('%[%d+%-%d+ %d+:%d+%] ')
      if ts_end then
        vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgTimestamp', line, 0, ts_end)
        local _, se = text:find('[^:]+: ', ts_end + 1)
        if se then
          vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgSender', line, ts_end, se - 2)
        end
      end
    end
  end
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines = {}
  for _, msg in ipairs(state.messages) do
    for _, l in ipairs(fmt_msg(msg)) do
      table.insert(lines, l)
    end
  end
  set_lines(lines)
  apply_highlights()
end

M.render = render

---@param s string
---@return integer
local function strvis(s) return vim.fn.strwidth(s) end

local function update_title()
  if not state.menu_buf or not vim.api.nvim_buf_is_valid(state.menu_buf) then return end
  local w = vim.api.nvim_win_get_width(state.menu_win)
  local left = '  ◆ ' .. state.unread .. '  '
  local right = '  help(?)  '
  local preview = (state.last_msg or 'latest'):gsub('\n', ' ')
  local avail = w - strvis(left) - strvis(right)
  if strvis(preview) > avail then
    while strvis(preview) > avail - 3 do
      preview = vim.fn.strcharpart(preview, 0, vim.fn.strchars(preview) - 1)
    end
    preview = preview .. '...'
  end
  local bar = left .. preview
  bar = bar .. string.rep(' ', math.max(w - strvis(bar) - strvis(right), 0)) .. right
  vim.api.nvim_buf_set_lines(state.menu_buf, 0, 1, false, { bar })
  vim.api.nvim_buf_clear_namespace(state.menu_buf, hl_ns, 0, -1)
  vim.api.nvim_buf_add_highlight(state.menu_buf, hl_ns, 'TgKey', 0, 2, strvis(left))
  vim.api.nvim_buf_add_highlight(state.menu_buf, hl_ns, 'TgKey', 0, w - 9, w - 1)
end

M.update_title = update_title

--- Help window

local help_win = nil
local help_buf = nil

local function close_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end
  if help_buf and vim.api.nvim_buf_is_valid(help_buf) then
    vim.api.nvim_buf_delete(help_buf, { force = true })
  end
  help_win = nil
  help_buf = nil
end

M.close_help = close_help

local function show_help()
  close_help()
  help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(help_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(help_buf, 'bufhidden', 'wipe')
  local lines = {
    ' i          new message',
    ' e          edit message under cursor',
    ' Enter      reply to message under cursor',
    ' s          switch to another group',
    ' r          refresh messages',
    ' ?          show this help',
    ' Esc        close chat window',
    ' q          quit telegram (close all)',
  }
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  local width = 36
  local height = #lines + 2
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor', width = width, height = height,
    row = row, col = col, style = 'minimal', border = 'rounded',
    title = ' Help ',
    title_pos = 'center',
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:TgNoBg,FloatBorder:TgBorder', { win = help_win })
  vim.keymap.set('n', '<Esc>', close_help, { buffer = help_buf, nowait = true })
  vim.keymap.set('n', 'q', close_help, { buffer = help_buf, nowait = true })
  vim.keymap.set('n', '?', close_help, { buffer = help_buf, nowait = true })
end

--- Chat window management

local function close_chat()
  close_help()
  if state.chat_id then
    state.last_chat = { id = state.chat_id, title = state.chat_title }
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  if state.menu_win and vim.api.nvim_win_is_valid(state.menu_win) then
    vim.api.nvim_win_close(state.menu_win, true)
  end
  if state.menu_buf and vim.api.nvim_buf_is_valid(state.menu_buf) then
    vim.api.nvim_buf_delete(state.menu_buf, { force = true })
  end
  state.buf = nil
  state.win = nil
  state.menu_buf = nil
  state.menu_win = nil
  state.messages = {}
  state.loading = false
  state.exhausted = false
end

M.close_chat = close_chat

local function load_older()
  if state.loading or state.exhausted or #state.messages == 0 then return end
  state.loading = true
  local oldest_id = state.messages[1].id
  local data = server.get_messages(state.chat_id, server.DEFAULT_LIMIT, oldest_id)
  if not data then state.loading = false; return end
  local new_msgs = data.messages or {}
  if #new_msgs == 0 or #new_msgs < server.DEFAULT_LIMIT then
    state.exhausted = true
    state.loading = false
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local old_top = cursor[1]
  local seen = {}
  for _, m in ipairs(state.messages) do
    seen[m.id] = true
  end
  local added = 0
  for i = 1, #new_msgs do
    if not seen[new_msgs[i].id] then
      seen[new_msgs[i].id] = true
      table.insert(state.messages, 1, new_msgs[i])
      added = added + 1
    end
  end
  if added > 0 then
    render()
    vim.api.nvim_win_set_cursor(state.win, { old_top + added, cursor[2] })
  end
  state.loading = false
end

local function refresh_messages()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  state.loading = false
  state.exhausted = false
  local data = server.get_messages(state.chat_id)
  if not data then
    vim.notify('[tg] Failed to load messages', vim.log.levels.ERROR)
    return
  end
  local raw = data.messages or {}
  state.messages = {}
  local seen = {}
  for i = #raw, 1, -1 do
    local msg = raw[i]
    if not seen[msg.id] then
      seen[msg.id] = true
      table.insert(state.messages, msg)
    end
  end
  render()
  if #state.messages > 0 then
    local latest = state.messages[#state.messages]
    local ts = os.date('%m-%d %H:%M', latest.date)
    state.last_msg = '[' .. ts .. '] ' .. (latest.sender and latest.sender.name or '?') .. ': ' .. (latest.text or '')
    vim.api.nvim_win_set_cursor(state.win, { #state.messages, 0 })
  end
  update_title()
end

M.refresh_messages = refresh_messages

---@return integer|nil
local function message_at_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
  local line = 1
  for idx, msg in ipairs(state.messages) do
    local n = #fmt_msg(msg)
    if cursor_line >= line and cursor_line < line + n then
      return idx
    end
    line = line + n
  end
  return nil
end

---@param chat_id any
---@param chat_title string
function M.open_chat(chat_id, chat_title)
  close_chat()
  state.chat_id = chat_id
  state.chat_title = chat_title or 'Chat'
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'wipe')
  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local msg_h = height - 3
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor', width = width, height = msg_h,
    row = row, col = col, style = 'minimal', border = 'rounded',
    title = ' ' .. chat_title .. ' ',
    title_pos = 'center',
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:TgNoBg,FloatBorder:TgBorder', { win = state.win })
  state.menu_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.menu_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.menu_buf, 'bufhidden', 'wipe')
  state.menu_bar = 'i:msg e:edit Enter:reply s:switch r:refresh Esc:back q:quit'
  state.menu_win = vim.api.nvim_open_win(state.menu_buf, false, {
    relative = 'editor', width = width, height = 1,
    row = row + msg_h + 2, col = col,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 5,
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:TgNoBg,FloatBorder:TgBorder', { win = state.menu_win })
  vim.api.nvim_win_set_option(state.menu_win, 'wrap', false)
  update_title()
  vim.keymap.set('n', '<Esc>', close_chat, { buffer = state.buf })
  vim.keymap.set('n', 'q', function()
    close_chat()
    state.last_chat = nil
    require('telegram.ws').ws_stop()
    server.stop_server()
    require('telegram').set_initialized(false)
  end, { buffer = state.buf })
  vim.keymap.set('n', '?', function()
    show_help()
  end, { buffer = state.buf })
  vim.keymap.set('n', 's', function()
    require('telegram').list_groups(true)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'r', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    refresh_messages()
  end, { buffer = state.buf })
  vim.keymap.set('n', 'i', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    vim.ui.input({ prompt = 'Message: ' }, function(text)
      if text and #text > 0 then
        local ok = server.send_message(state.chat_id, text)
        if ok then vim.schedule(refresh_messages) end
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', '<CR>', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    local idx = message_at_cursor()
    if not idx then return end
    local target = state.messages[idx]
    local prompt = 'Reply to ' .. (target.sender and target.sender.name or '?') .. ': '
    vim.ui.input({ prompt = prompt }, function(text)
      if text and #text > 0 then
        local ok = server.send_message(state.chat_id, text, target.id)
        if ok then vim.schedule(refresh_messages) end
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'e', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    local idx = message_at_cursor()
    if not idx then return end
    local target = state.messages[idx]
    if not target or not target.id then return end
    vim.ui.input({ prompt = 'Edit: ', default = target.text or '' }, function(text)
      if text and #text > 0 then
        local ok = server.edit_message(state.chat_id, target.id, text)
        if ok then vim.schedule(refresh_messages) end
      end
    end)
  end, { buffer = state.buf })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = vim.api.nvim_create_augroup('TgChatScroll', { clear = true }),
    buffer = state.buf,
    callback = function()
      if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
      if vim.api.nvim_get_current_win() ~= state.win then return end
      if state.unread > 0 and vim.api.nvim_win_get_cursor(state.win)[1] >= vim.api.nvim_buf_line_count(state.buf) - 1 then
        state.unread = 0
        update_title()
      end
      if vim.api.nvim_win_get_cursor(state.win)[1] <= 1 and not state.exhausted then
        load_older()
      end
    end,
  })
  refresh_messages()
end

return M
