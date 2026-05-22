local server = require('telegram.server')

---@class TgSender
---@field id any
---@field name string

---@class TgMessage
---@field id any
---@field date integer
---@field sender TgSender|nil
---@field text string|nil
---@field own boolean|nil
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
---@field online_count integer|nil
---@field typing_users table<number, {name:string, action_desc:string}>

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
  online_count = nil,
  typing_users = {},
  saved_cursors = {},
}

M.state = state

---@param lines string[]
local function set_lines(lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', false)
end

---@param prompt string
---@param default string|nil
---@param callback fun(text:string|nil)
local function multi_line_input(prompt, default, callback)
  if state.chat_id then server.send_chat_action(state.chat_id, 'chatActionTyping') end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  if default and #default > 0 then
    local lines = vim.split(default, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  local width = math.floor(vim.o.columns * 0.6)
  local height = 6
  local row = math.floor((vim.o.lines - height) / 2) - 2
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = row, col = col, style = 'minimal', border = 'rounded',
    title = ' ' .. prompt .. ' ',
    title_pos = 'center',
  })
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:TgNoBg,FloatBorder:TgBorder')

  local function close()
    if state.chat_id then server.send_chat_action(state.chat_id, 'chatActionCancel') end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end

  vim.keymap.set('n', '<Esc>', function()
    close(); callback(nil)
  end, { buffer = buf, nowait = true })

  vim.keymap.set('n', 'q', function()
    close(); callback(nil)
  end, { buffer = buf, nowait = true })

  vim.keymap.set('n', '<CR>', function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n'):gsub('[\n ]+$', '')
    close(); callback(#text > 0 and text or nil)
  end, { buffer = buf, nowait = true })

  vim.cmd('startinsert!')
end

---@param msg TgMessage
---@return string[]
local function fmt_msg(msg)
  local date_str = os.date('%m-%d %H:%M', msg.date)
  local sender = msg.sender and msg.sender.name or 'unknown'
  local out = {}
  local parts = vim.split(msg.text or '', '\n')
  if msg.replyTo then
    local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or '?'
    local r_text = msg.replyTo.text and msg.replyTo.text:gsub('\n', ' ') or ''
    if #r_text > 50 then r_text = r_text:sub(1, 50) .. '...' end
    table.insert(out, string.format('[%s] %s:', date_str, sender))
    table.insert(out, '  \xE2\x94\x83 ' .. r_sender .. ': ' .. r_text)
    table.insert(out, '  ' .. parts[1])
  else
    table.insert(out, string.format('[%s] %s: %s', date_str, sender, parts[1]))
  end
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
    if text:byte(1) == 0x20 and text:byte(2) == 0x20 and text:byte(3) == 0xE2 and text:byte(4) == 0x94 then
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgReplyIndicator', line, 2, 5)
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgReplyBg', line, 5, -1)
    end
    local _, ts_end = text:find('%[%d+%-%d+ %d+:%d+%] ')
    if ts_end then
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgTimestamp', line, 0, ts_end)
      local _, se = text:find('%S+:', ts_end + 1)
      if se then
        vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgSender', line, ts_end, se)
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

local action_descriptions = {
  chatActionTyping = 'typing...',
  chatActionRecordingVideo = 'recording video...',
  chatActionRecordingVoiceNote = 'recording voice...',
  chatActionUploadingVideo = 'uploading video...',
  chatActionUploadingVoiceNote = 'uploading voice...',
  chatActionUploadingPhoto = 'uploading photo...',
  chatActionUploadingDocument = 'uploading document...',
  chatActionChoosingSticker = 'choosing sticker...',
  chatActionChoosingLocation = 'choosing location...',
  chatActionChoosingContact = 'choosing contact...',
  chatActionStartPlayingGame = 'playing game...',
  chatActionRecordingVideoNote = 'recording video note...',
  chatActionUploadingVideoNote = 'uploading video note...',
  chatActionWatchingAnimations = 'watching animations...',
}

local function update_title()
  if not state.menu_buf or not vim.api.nvim_buf_is_valid(state.menu_buf) then return end
  local w = vim.api.nvim_win_get_width(state.menu_win)
  local left = '  ◆ ' .. state.unread .. '  '
  local right = '  help(?)  '

  local middle = ''
  local typing_items = {}
  for _, info in pairs(state.typing_users) do
    table.insert(typing_items, info)
  end
  if #typing_items > 0 then
    if #typing_items == 1 then
      middle = typing_items[1].name .. ' ' .. typing_items[1].action_desc
    else
      middle = typing_items[1].name .. ' +' .. (#typing_items - 1) .. ' ' .. typing_items[1].action_desc
    end
  elseif state.online_count and state.online_count > 0 then
    middle = state.online_count .. ' online'
  end

  local avail = w - strvis(left) - strvis(right)
  if strvis(middle) > avail then
    while strvis(middle) > avail - 3 do
      middle = vim.fn.strcharpart(middle, 0, vim.fn.strchars(middle) - 1)
    end
    middle = middle .. '...'
  end
  local bar = left .. middle
  bar = bar .. string.rep(' ', math.max(w - strvis(bar) - strvis(right), 0)) .. right
  vim.api.nvim_buf_set_lines(state.menu_buf, 0, 1, false, { bar })
  vim.api.nvim_buf_clear_namespace(state.menu_buf, hl_ns, 0, -1)
  vim.api.nvim_buf_add_highlight(state.menu_buf, hl_ns, 'TgKey', 0, 2, strvis(left))
  vim.api.nvim_buf_add_highlight(state.menu_buf, hl_ns, 'TgKey', 0, w - 9, w - 1)
end

M.update_title = update_title

function M.set_typing(chat_id, user_id, user_name, action_type, active)
  if chat_id ~= state.chat_id or not user_id then return end
  if active then
    state.typing_users[user_id] = { name = user_name or 'Unknown', action_desc = action_descriptions[action_type] or 'typing...' }
  else
    state.typing_users[user_id] = nil
  end
  update_title()
end

function M.set_online_count(count)
  state.online_count = count
  update_title()
end

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
    ' i       new message',
    ' /       search / clear search',
    ' d       delete / recall own',
    ' e       edit own',
    ' Enter   reply / jump to original',
    ' f       forward',
    ' s       switch group',
    ' r       refresh',
    ' ?       help | Esc close | q quit',
  }
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  local maxw = 0
  for _, l in ipairs(lines) do maxw = math.max(maxw, strvis(l)) end
  local width = maxw + 4
  local height = #lines
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

---@return table|nil
local function curr_msg() local i = message_at_cursor(); return i and state.messages[i] end

local function jump_to_message(target_id)
  local function line_of()
    for i, m in ipairs(state.messages) do
      if m.id == target_id then
        local line = 1
        for j = 1, i - 1 do line = line + #fmt_msg(state.messages[j]) end
        return line
      end
    end
  end
  local l = line_of()
  if not l then
    local ctx = server.get_messages(state.chat_id, 100, target_id)
    if ctx and ctx.messages then
      local oldest = state.messages[1] and state.messages[1].id or 0
      for _, m in ipairs(ctx.messages) do
        if m.id < oldest then table.insert(state.messages, 1, m); oldest = m.id end
      end
    end
    local single = server.get_message(state.chat_id, target_id)
    if single then
      local seen = {}
      for _, m in ipairs(state.messages) do seen[m.id] = true end
      if not seen[target_id] then table.insert(state.messages, 1, single) end
    end
    l = line_of()
  end
  if l then
    render()
    pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
    return true
  end
  return false
end

local function close_chat()
  close_help()
  if state.chat_id then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local idx = message_at_cursor()
      if idx then state.saved_cursors[state.chat_id] = state.messages[idx].id end
    end
    state.last_chat = { id = state.chat_id, title = state.chat_title }
    server.close_chat(state.chat_id)
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
  state.online_count = nil
  state.typing_users = {}
end

M.close_chat = close_chat

local function load_older()
  if state.loading or state.exhausted or #state.messages == 0 then return end
  state.loading = true
  local oldest_id = state.messages[1].id
  local data = server.get_messages(state.chat_id, server.DEFAULT_LIMIT, oldest_id)
  if not data then state.loading = false; return end
  local new_msgs = data.messages or {}
  if #new_msgs == 0 then
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
  local new_lines = 0
  for i = 1, #new_msgs do
    if not seen[new_msgs[i].id] then
      seen[new_msgs[i].id] = true
      table.insert(state.messages, 1, new_msgs[i])
      new_lines = new_lines + #fmt_msg(new_msgs[i])
    end
  end
  if new_lines > 0 then
    render()
    vim.api.nvim_win_set_cursor(state.win, { old_top + new_lines, cursor[2] })
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
  end
  update_title()
end

M.refresh_messages = refresh_messages

local function open_windows(chat_title)
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
end

---@param chat_id any
---@param chat_title string
function M.open_chat(chat_id, chat_title)
  chat_title = chat_title or 'Chat'
  if state.chat_id == chat_id and state.buf and vim.api.nvim_buf_is_valid(state.buf) and not state.win then
    open_windows(chat_title)
    update_title()
    return
  end
  close_chat()
  state.chat_id = chat_id
  state.chat_title = chat_title
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'wipe')
  state.menu_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.menu_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.menu_buf, 'bufhidden', 'wipe')
  state.menu_bar = 'i:msg e:edit Enter:reply/original s:switch r:refresh Esc:back q:quit'
  open_windows(chat_title)
  do
    local win_w = vim.api.nvim_win_get_width(state.win)
    local win_h = vim.api.nvim_win_get_height(state.win)
    local text = '◇ Loading...'
    local text_w = vim.fn.strwidth(text)
    local pad = math.max(0, math.floor((win_w - text_w) / 2))
    local top = math.max(0, math.floor(win_h / 2))
    local lines = {}
    for _ = 1, top do table.insert(lines, '') end
    table.insert(lines, string.rep(' ', pad) .. text)
    set_lines(lines)
  end
  server.open_chat(state.chat_id)
  update_title()
  vim.keymap.set('n', '<Esc>', close_chat, { buffer = state.buf })
  vim.keymap.set('n', 'q', function()
    close_chat()
    state.last_chat = nil
    state.saved_cursors = {}
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
    if #state.messages > 0 then
      local total = 1
      for _, msg in ipairs(state.messages) do total = total + #fmt_msg(msg) end
      pcall(vim.api.nvim_win_set_cursor, state.win, { total - 1, 0 })
    end
  end, { buffer = state.buf })
  vim.keymap.set('n', 'i', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    multi_line_input('Message', nil, function(text)
      if text and server.send_message(state.chat_id, text) then
        vim.notify('[tg] Message sent', vim.log.levels.INFO)
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', '<CR>', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    local target = curr_msg()
    if not target then return end
    local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
    local text = vim.api.nvim_buf_get_lines(state.buf, cursor_line - 1, cursor_line, false)[1]
    if text and text:byte(1) == 0x20 and text:byte(2) == 0x20 and text:byte(3) == 0xE2 and text:byte(4) == 0x94 then
      if target.replyTo then
        jump_to_message(target.replyTo.id)
      end
      return
    end
    multi_line_input('Reply to ' .. (target.sender and target.sender.name or '?'), nil, function(text)
      if text and server.send_message(state.chat_id, text, target.id) then
        vim.notify('[tg] Reply sent', vim.log.levels.INFO)
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', '/', function()
    multi_line_input('Search', nil, function(text)
      if not text or #text == 0 then return end
      local data = server.search_messages(state.chat_id, text)
      if not data or not data.messages or #data.messages == 0 then
        vim.notify('[tg] No results for "' .. text .. '"', vim.log.levels.INFO)
        return
      end
      local items = {}
      for _, m in ipairs(data.messages) do
        local name = m.sender and m.sender.name or '?'
        local preview = (m.text or ''):gsub('\n', ' '):sub(1, 80)
        table.insert(items, { msg = m, label = name .. ': ' .. preview })
      end
      vim.ui.select(items, {
        prompt = 'Search: ' .. text,
        format_item = function(item) return item.label end,
      }, function(choice)
        if not choice then return end
        jump_to_message(choice.msg.id)
      end)
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'e', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    local target = curr_msg()
    if not target or not target.id then return end
    if not target.own then
      vim.notify('[tg] Can only edit your own messages', vim.log.levels.WARN)
      return
    end
    multi_line_input('Edit', target.text or '', function(text)
      if not text then return end
      if server.edit_message(state.chat_id, target.id, text) then
        target.text = text
        render()
        vim.notify('[tg] Message edited', vim.log.levels.INFO)
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'f', function()
    local target = curr_msg()
    if not target or not target.id then return end
    local groups = server.get_groups()
    if not groups or #groups == 0 then
      vim.notify('[tg] No groups to forward to', vim.log.levels.WARN)
      return
    end
    local items = {}
    for _, g in ipairs(groups) do
      table.insert(items, { id = g.id, label = g.title })
    end
    vim.ui.select(items, {
      prompt = 'Forward to:',
      format_item = function(item) return item.label end,
    }, function(choice)
      if choice then
        local ok = server.forward_messages(state.chat_id, target.id, choice.id)
        if ok then vim.notify('[tg] Forwarded to ' .. choice.label, vim.log.levels.INFO) end
      end
    end)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'd', function()
    local target = curr_msg()
    if not target or not target.id then return end
    local sender = target.sender and target.sender.name or '?'
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = 'Delete message from ' .. sender .. '?',
    }, function(choice)
      if choice == 'Yes' then
        if server.delete_message(state.chat_id, target.id) then
          for i = #state.messages, 1, -1 do
            if state.messages[i].id == target.id then table.remove(state.messages, i); break end
          end
          vim.schedule(function()
            render()
            local last = state.messages[#state.messages]
            state.last_msg = last and ('[' .. os.date('%m-%d %H:%M', last.date) .. '] ' .. (last.sender and last.sender.name or '?') .. ': ' .. (last.text or '')) or ''
            update_title()
          end)
          vim.notify('[tg] Message deleted', vim.log.levels.INFO)
        end
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
  vim.defer_fn(function()
    refresh_messages()
    local restore = state.saved_cursors[state.chat_id]
    if restore then
      state.saved_cursors[state.chat_id] = nil
      jump_to_message(restore)
    elseif #state.messages > 0 then
      local total = 1
      for _, msg in ipairs(state.messages) do total = total + #fmt_msg(msg) end
      pcall(vim.api.nvim_win_set_cursor, state.win, { total - 1, 0 })
    end
  end, 300)
end

return M
