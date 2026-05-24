local NuiLayout = require("nui.layout")
local NuiPopup = require("nui.popup")
local Editor = require("telegram.editor")
local server = require("telegram.server")
local render_msg = require("telegram.render").render

local M = {}

---@type table
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
  last_msg = nil,
  online_count = nil,
  typing_users = {},
  saved_cursors = {},

  layout = nil,
  msg_popup = nil,
  input_popup = nil,
  group_popup = nil,

  groups = {},
  group_ids = {},
  group_cursor = 1,

  input_mode = 'send',
  reply_to = nil,
  edit_target = nil,
  esc_count = 0,
}

M.state = state

---@param lines string[]
local function set_lines(lines)
  if not state.msg_popup then return end
  local buf = state.msg_popup.bufnr
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

---@param msg TgMessage
---@return string[]
local function fmt_msg(msg)
  return render_msg(msg)
end

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

local hl_ns = vim.api.nvim_create_namespace('TgChat')
local target_ns = vim.api.nvim_create_namespace('TgTarget')

local function apply_highlights()
  if not state.msg_popup then return end
  local buf = state.msg_popup.bufnr
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, target_ns, 0, -1)
  local total = vim.api.nvim_buf_line_count(buf)
  for line = 0, total - 1 do
    local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
    if not text then break end
    local rs, re = text:find('\xE2\x94\x83')
    if rs then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgReplyIndicator', line, rs - 1, re)
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgReplyBg', line, re, -1)
    end
    local _, ts_start = text:find('%[%d+%-%d+ %d+:%d+%] ')
    if ts_start then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgTimestamp', line, 0, ts_start)
      local _, se = text:find('%S.-:', ts_start + 1)
      if se then
        vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgSender', line, ts_start, se)
      end
    end
    local ts_s, ts_e = text:find('%[%d+%-%d+ %d+:%d+%]$')
    if ts_s then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgTimestamp', line, ts_s - 1, ts_e)
      local pre = text:sub(1, ts_s - 1)
      local ss, se = pre:find('%S+%s*$')
      if ss then
        vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgSender', line, ss - 1, se)
      end
    end
  end
  local target_id = state.reply_to or (state.edit_target and state.edit_target.id)
  local mode = state.reply_to and 'reply' or (state.edit_target and 'edit')
  if not target_id or not mode then return end
  local hl = mode == 'reply' and 'TgReplyTarget' or 'TgEditTarget'
  local label = mode == 'reply' and '  \xE2\x97\x8F Replying' or '  \xE2\x97\x8F Editing'
  local line = 1
  for _, m in ipairs(state.messages) do
    local n = #fmt_msg(m)
    if m.id == target_id then
      local start_line = line - 1
      local end_line = line + n - 2
      for l = start_line, end_line do
        vim.api.nvim_buf_add_highlight(buf, hl_ns, hl, l, 0, -1)
      end
      local last = end_line >= start_line and end_line or start_line
      vim.api.nvim_buf_set_extmark(buf, target_ns, last, 0, {
        virt_lines = {{ { label, hl } }},
      })
      break
    end
    line = line + n + 1
  end
end

local function apply_group_highlights()
  if not state.group_popup then return end
  local buf = state.group_popup.bufnr
  local win = state.group_popup.winid
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  local total = vim.api.nvim_buf_line_count(buf)
  for line = 0, total - 1 do
    local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
    if not text then break end
    if line + 1 == state.group_cursor then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgBorder', line, 0, -1)
    end
    local ds, de = text:find('\xE2\x97\x8F')
    if ds then
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'TgKey', line, ds - 1, de)
    end
  end
  pcall(vim.api.nvim_win_set_cursor, win, { state.group_cursor, 0 })
end

local function update_input_title()
  if not state.input_popup then return end
  local title = ' Message '
  if state.chat_title and #state.chat_title > 0 then
    title = ' ' .. state.chat_title .. ' '
  end
  local typing_items = {}
  for _, info in pairs(state.typing_users) do
    table.insert(typing_items, info)
  end
  if #typing_items > 0 then
    if #typing_items == 1 then
      title = title .. '| ' .. typing_items[1].name .. ' ' .. typing_items[1].action_desc
    else
      title = title .. '| ' .. typing_items[1].name .. ' +' .. (#typing_items - 1) .. ' ' .. typing_items[1].action_desc
    end
  end
  title = title .. '| ' .. (state.online_count or 0) .. ' online'
  if state.msg_popup and state.msg_popup.border then
    state.msg_popup.border:set_text('top', title)
  end
end

local function update_input_border()
  if not state.input_popup then return end
  local text
  if state.input_mode == 'edit' and state.edit_target then
    local name = (state.edit_target.sender and state.edit_target.sender.name) or 'Unknown'
    text = ' Editing ' .. name .. ' '
  elseif state.input_mode == 'reply' and state.reply_to then
    local target = nil
    for _, msg in ipairs(state.messages) do
      if msg.id == state.reply_to then target = msg; break end
    end
    local name = (target and target.sender and target.sender.name) or 'Unknown'
    text = ' Replying to ' .. name .. ' '
  else
    text = ' Message '
  end
  pcall(function()
    state.input_popup.border:set_text('top', text)
  end)
end

M.update_title = update_input_title

function M.set_typing(chat_id, user_id, user_name, action_type, active)
  if chat_id ~= state.chat_id or not user_id then return end
  if active then
    state.typing_users[user_id] = { name = user_name or 'Unknown', action_desc = action_descriptions[action_type] or 'typing...' }
  else
    state.typing_users[user_id] = nil
  end
  update_input_title()
end

function M.set_online_count(count)
  state.online_count = count
  update_input_title()
end

function M.update_group_online(chat_id, count)
  if not state.groups[chat_id] then return end
  state.groups[chat_id].online_count = count
  M.render_groups()
end

function M.update_group_last_msg(chat_id, sender_name, text)
  if not state.groups[chat_id] then return end
  if chat_id ~= state.chat_id then
    state.groups[chat_id].unread_count = (state.groups[chat_id].unread_count or 0) + 1
  end
  local preview = (sender_name or '?') .. ': ' .. (text or '')
  if #preview > 40 then preview = preview:sub(1, 40) .. '...' end
  state.groups[chat_id].last_msg_preview = preview
  M.render_groups()
end

function M.set_groups(groups)
  local new_groups = {}
  local new_ids = {}
  for _, g in ipairs(groups or {}) do
    local existing = state.groups[g.id]
    new_groups[g.id] = {
      id = g.id,
      title = g.title,
      member_count = g.memberCount or 0,
      online_count = (existing and existing.online_count) or g.onlineMemberCount or 0,
      unread_count = (existing and existing.unread_count) or g.unreadCount or 0,
      last_msg_preview = (existing and existing.last_msg_preview) or '',
    }
    table.insert(new_ids, g.id)
  end
  state.groups = new_groups
  state.group_ids = new_ids
  if state.group_cursor > #new_ids then state.group_cursor = #new_ids end
  if state.group_cursor < 1 and #new_ids > 0 then state.group_cursor = 1 end
  if state.active_group_id and new_groups[state.active_group_id] then
    for i, id in ipairs(new_ids) do
      if id == state.active_group_id then
        state.group_cursor = i
        break
      end
    end
  end
  M.render_groups()
end

function M.render_groups()
  if not state.group_popup then return end
  local buf = state.group_popup.bufnr
  local lines = {}
  for _, id in ipairs(state.group_ids) do
    local g = state.groups[id]
    if g then
      local total = (g.member_count or 0) > 0 and tostring(g.member_count) or '?'
      local label = g.title .. '(' .. total .. ')'
      if g.unread_count and g.unread_count > 0 and state.chat_id and id ~= state.chat_id then
        label = label .. '  ● +' .. g.unread_count
      end
      if #label > 36 then label = label:sub(1, 33) .. '…' end
      table.insert(lines, '  ' .. label)
    end
  end
  pcall(vim.api.nvim_buf_set_option, buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_option, buf, 'modifiable', false)
  apply_group_highlights()
end

local function render()
  if not state.msg_popup then return end
  local lines = {}
  for _, msg in ipairs(state.messages) do
    local msg_lines = fmt_msg(msg)
    for _, l in ipairs(msg_lines) do
      table.insert(lines, l)
    end
    table.insert(lines, '')
  end
  set_lines(lines)
  apply_highlights()
end

M.render = render

--- Help window (uses simple popup)

local help_popup = nil

local function close_help()
  if help_popup then
    help_popup:unmount()
    help_popup = nil
  end
end

M.close_help = close_help

local function show_help()
  close_help()
  help_popup = NuiPopup({
    relative = 'editor',
    position = { row = '50%', col = '50%' },
    size = { width = 36, height = 28 },
    zindex = 200,
    border = { style = 'rounded', text = { top = ' Help ', top_align = 'center' } },
    buf_options = { buftype = 'nofile', bufhidden = 'wipe' },
    win_options = { winhighlight = 'Normal:TgNoBg,FloatBorder:TgBorder' },
    enter = true,
    focusable = true,
  })
  local lines = {
    '-- Global --',
    ' ?        help',
    ' <C-h>    go to groups',
    ' <C-l>    go to msg',
    ' <C-j>    go to input',
    ' <C-k>    go to msg',
    '',
    '-- Main window --',
    ' i        focus input',
    ' /        search history',
    ' <CR>     reply / jump to original',
    ' e        edit own message',
    ' d        delete / revoke message',
    ' f        forward message',
    ' r        refresh',
    ' Esc Esc  close chat',
    ' q        quit plugin',
    '',
    '-- Groups --',
    ' j/k      move cursor',
    ' <CR>     open chat',
    '',
    '-- Input --',
    ' <CR>     send message',
    ' Esc      cancel reply/edit',
  }
  help_popup:mount()
  vim.api.nvim_buf_set_lines(help_popup.bufnr, 0, -1, false, lines)
  vim.keymap.set('n', '<Esc>', close_help, { buffer = help_popup.bufnr, nowait = true })
  vim.keymap.set('n', 'q', close_help, { buffer = help_popup.bufnr, nowait = true })
  vim.keymap.set('n', '?', close_help, { buffer = help_popup.bufnr, nowait = true })
end

M.show_help = show_help

local function input_send()
  if not state.editor then return end
  local text = state.editor:get_text()
  if #text == 0 then return end
  if state.input_mode == 'edit' and state.edit_target then
    local target = state.edit_target
    if server.edit_message(state.chat_id, target.id, text) then
      target.text = text
      render()
      vim.notify('[tg] Message edited', vim.log.levels.INFO)
    end
  elseif state.input_mode == 'reply' and state.reply_to then
    if server.send_message(state.chat_id, text, state.reply_to) then
      vim.notify('[tg] Reply sent', vim.log.levels.INFO)
    end
  else
    if server.send_message(state.chat_id, text) then
      vim.notify('[tg] Message sent', vim.log.levels.INFO)
    end
  end
  state.editor:clear()
  state.input_mode = 'send'
  state.reply_to = nil
  state.edit_target = nil
  apply_highlights()
  update_input_border()
end

local function focus_msg()
  if not state.msg_popup then return end
  vim.cmd('stopinsert')
  pcall(vim.api.nvim_set_current_win, state.msg_popup.winid)
end

local function focus_input()
  if state.editor then state.editor:focus() end
end

local function focus_groups()
  if state.group_popup then pcall(vim.api.nvim_set_current_win, state.group_popup.winid) end
end

local function cur_area()
  local win = vim.api.nvim_get_current_win()
  if state.msg_popup and win == state.msg_popup.winid then return 'msg' end
  if state.editor and win == state.editor:winid() then return 'input' end
  if state.group_popup and win == state.group_popup.winid then return 'group' end
  return 'msg'
end

local function restore_group_cursor()
  for i, id in ipairs(state.group_ids) do
    if id == state.active_group_id then
      state.group_cursor = i
      break
    end
  end
  if state.group_popup then
    pcall(vim.api.nvim_win_set_cursor, state.group_popup.winid, { state.group_cursor, 0 })
    apply_group_highlights()
  end
end

local function nav_h()
  if cur_area() == 'group' then restore_group_cursor() end
  if cur_area() == 'msg' then focus_groups() else focus_msg() end
end

local function nav_l()
  if cur_area() == 'group' then restore_group_cursor() end
  if cur_area() == 'group' then focus_msg() else focus_groups() end
end

local function nav_j()
  if cur_area() == 'msg' then focus_input() else focus_msg() end
end

local function nav_k()
  if cur_area() == 'input' then focus_msg() else focus_input() end
end

---@param buf integer
local function setup_nav_keymaps(buf)
  vim.keymap.set('n', '<C-h>', nav_h, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<C-j>', nav_j, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<C-k>', nav_k, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<C-l>', nav_l, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<C-h>', nav_h, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<C-j>', nav_j, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<C-k>', nav_k, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<C-l>', nav_l, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<C-w>', '<Nop>', { buffer = buf })
end

--- Chat message popup keymaps
local function setup_msg_keymaps()
  local buf = state.msg_popup.bufnr
  setup_nav_keymaps(buf)
  vim.keymap.set('n', '<Esc>', function()
    state.esc_count = state.esc_count + 1
    if state.esc_count >= 2 then
      state.esc_count = 0
      M.close_chat()
    else
      vim.defer_fn(function() state.esc_count = 0 end, 300)
    end
  end, { buffer = buf })
  vim.keymap.set('n', 'q', function()
    M.close_chat()
    state.last_chat = nil
    state.saved_cursors = {}
    require('telegram.ws').ws_stop()
    server.stop_server()
    require('telegram').set_initialized(false)
  end, { buffer = buf })
  vim.keymap.set('n', '?', '<Cmd>lua require("telegram.ui").show_help()<CR>', { buffer = buf, nowait = true })
  vim.keymap.set('n', 'i', focus_input, { buffer = buf })
  local no_insert = { 'I', 'a', 'A', 'o', 'O', 's', 'S' }
  for _, k in ipairs(no_insert) do
    pcall(vim.keymap.set, 'n', k, '<Nop>', { buffer = buf, nowait = true })
  end
  vim.keymap.set('n', 'r', function()
    if state.unread > 0 then state.unread = 0 end
    M.refresh_messages()
    if #state.messages > 0 then
      local total = 1
      for _, msg in ipairs(state.messages) do total = total + #fmt_msg(msg) + 1 end
      pcall(vim.api.nvim_win_set_cursor, state.msg_popup.winid, { total - 2, 0 })
    end
  end, { buffer = buf })
  vim.keymap.set('n', '/', function()
    if not state.msg_popup then return end
    local text = vim.fn.input('Search: ')
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
      table.insert(items, { id = m.id, label = name .. ': ' .. preview })
    end
    vim.ui.select(items, {
      prompt = 'Search: ' .. text,
      format_item = function(item) return item.label end,
    }, function(choice)
      if not choice or type(choice) ~= 'table' then return end
      M.jump_to_message(choice.id)
    end)
  end, { buffer = buf })
  vim.keymap.set('n', '<CR>', function()
    if state.unread > 0 then state.unread = 0 end
    local target = M.curr_msg()
    if not target then return end
    local cursor_line = vim.api.nvim_win_get_cursor(state.msg_popup.winid)[1]
    local text = vim.api.nvim_buf_get_lines(state.msg_popup.bufnr, cursor_line - 1, cursor_line, false)[1]
    if text and text:find('\xE2\x94\x83') then
      if target.replyTo then
        M.jump_to_message(target.replyTo.id)
      end
      return
    end
    state.input_mode = 'reply'
    state.reply_to = target.id
    apply_highlights()
    update_input_border()
    focus_input()
  end, { buffer = buf })
  vim.keymap.set('n', 'e', function()
    if state.unread > 0 then state.unread = 0 end
    local target = M.curr_msg()
    if not target or not target.id then return end
    if not target.own then
      vim.notify('[tg] Can only edit your own messages', vim.log.levels.WARN)
      return
    end
    state.input_mode = 'edit'
    state.edit_target = target
    apply_highlights()
    update_input_border()
    state.editor:set_text(target.text or '')
    state.editor:focus()
    vim.cmd('startinsert!')
  end, { buffer = buf })
  vim.keymap.set('n', 'd', function()
    local target = M.curr_msg()
    if not target or not target.id then return end
    local choices = target.own and { 'Revoke (for everyone)', 'Delete (for me)', 'Cancel' } or { 'Delete (for me)', 'Cancel' }
    vim.ui.select(choices, {
      prompt = 'Delete message?',
    }, function(choice)
      if not choice or choice == 'Cancel' then return end
      local revoke = (choice == 'Revoke (for everyone)')
      if server.delete_message(state.chat_id, target.id, revoke) then
        for i = #state.messages, 1, -1 do
          if state.messages[i].id == target.id then table.remove(state.messages, i); break end
        end
        vim.schedule(function()
          render()
          local last = state.messages[#state.messages]
          state.last_msg = last and ('[' .. os.date('%m-%d %H:%M', last.date) .. '] ' .. (last.sender and last.sender.name or '?') .. ': ' .. (last.text or '')) or ''
        end)
        vim.notify('[tg] Message ' .. (revoke and 'revoked' or 'deleted'), vim.log.levels.INFO)
      end
    end)
  end, { buffer = buf })
  vim.keymap.set('n', 'f', function()
    local target = M.curr_msg()
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
  end, { buffer = buf })
end

local function setup_group_keymaps()
  local buf = state.group_popup.bufnr
  setup_nav_keymaps(buf)
  local function move_group_cursor(delta)
    local new = state.group_cursor + delta
    if new < 1 or new > #state.group_ids then return end
    state.group_cursor = new
    pcall(vim.api.nvim_win_set_cursor, state.group_popup.winid, { new, 0 })
    apply_group_highlights()
  end

  vim.keymap.set('n', 'j', function() move_group_cursor(1) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'k', function() move_group_cursor(-1) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Down>', function() move_group_cursor(1) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Up>', function() move_group_cursor(-1) end, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<CR>', function()
    local id = state.group_ids[state.group_cursor]
    if not id then return end
    local g = state.groups[id]
    if not g then return end
    M.open_chat(id, g.title)
  end, { buffer = buf })
end

local function setup_input_keymaps()
  local buf = state.editor:bufnr()
  setup_nav_keymaps(buf)
  vim.keymap.set('n', '<CR>', input_send, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', function()
    if state.input_mode ~= 'send' then
      state.input_mode = 'send'
      state.reply_to = nil
      state.edit_target = nil
      state.editor:clear()
      apply_highlights()
      update_input_border()
      focus_msg()
    end
  end, { buffer = buf })
  vim.keymap.set('n', 'p', function()
    if not state.editor then return end
    state.editor:hide_placeholder()
    vim.cmd('normal! P')
  end, { buffer = buf })
end

---@param chat_id any
---@param chat_title string
function M.open_chat(chat_id, chat_title)
  chat_title = chat_title or 'Chat'
  if state.chat_id == chat_id and state.layout and state.layout._.mounted then
    update_input_title()
    return
  end

  M.close_chat()

  state.chat_id = chat_id
  state.chat_title = chat_title
  state.active_group_id = chat_id
  for i, id in ipairs(state.group_ids) do
    if id == chat_id then state.group_cursor = i; break end
  end
  if state.groups[chat_id] then
    state.groups[chat_id].unread_count = 0
  end

  state.msg_popup = NuiPopup({
    enter = true,
    focusable = true,
    border = {
      style = 'rounded',
      text = { top = '', top_align = 'center' },
    },
    buf_options = { buftype = 'nofile', bufhidden = 'wipe' },
    win_options = {
      wrap = true,
      winhighlight = 'Normal:TgNoBg,FloatBorder:TgBorder',
    },
  })

  state.editor = Editor.new({
    placeholder = '  Type a message...',
  })
  state.input_popup = state.editor.popup

  state.group_popup = NuiPopup({
    enter = false,
    focusable = true,
    border = { style = 'rounded', text = { top = ' Groups ', top_align = 'center' } },
    buf_options = { buftype = 'nofile', bufhidden = 'wipe' },
    win_options = {
      winhighlight = 'Normal:TgNoBg,FloatBorder:TgBorder',
    },
  })

  state.layout = NuiLayout(
    {
      relative = 'editor',
      position = { row = '50%', col = '50%' },
      size = { width = '80%', height = '80%' },
    },
    NuiLayout.Box({
      NuiLayout.Box({
        NuiLayout.Box(state.msg_popup, { grow = 1 }),
        NuiLayout.Box(state.input_popup, { size = { height = 6 } }),
      }, { dir = 'col', grow = 1 }),
      NuiLayout.Box(state.group_popup, { size = { width = 36 } }),
    }, { dir = 'row' })
  )

  state.layout:mount()
  state.editor:setup()
  update_input_border()

  state.buf = state.msg_popup.bufnr
  state.win = state.msg_popup.winid

  setup_msg_keymaps()
  setup_input_keymaps()
  setup_group_keymaps()

  server.open_chat(state.chat_id)
  server.clear_groups_cache()
  vim.defer_fn(function()
    if not state.chat_id then return end
    local chat_data = server.get_chat(state.chat_id)
    if chat_data and state.groups[state.chat_id] then
      state.groups[state.chat_id].unread_count = chat_data.unreadCount or 0
      M.render_groups()
    end
  end, 50)
  update_input_title()
  M.render_groups()
  M.refresh_messages(function()
    local restore = state.saved_cursors[state.chat_id]
    if restore then
      state.saved_cursors[state.chat_id] = nil
      M.jump_to_message(restore)
    elseif #state.messages > 0 then
      local total = 1
      for _, msg in ipairs(state.messages) do total = total + #fmt_msg(msg) + 1 end
      pcall(vim.api.nvim_win_set_cursor, state.win, { total - 2, 0 })
    end
  end)

  vim.api.nvim_create_autocmd('CursorMoved', {
    group = vim.api.nvim_create_augroup('TgChatScroll', { clear = true }),
    buffer = state.buf,
    callback = function()
      if not state.msg_popup or not vim.api.nvim_win_is_valid(state.msg_popup.winid) then return end
      if vim.api.nvim_get_current_win() ~= state.msg_popup.winid then return end
      if state.unread > 0 and vim.api.nvim_win_get_cursor(state.msg_popup.winid)[1] >= vim.api.nvim_buf_line_count(state.buf) - 1 then
        state.unread = 0
      end
      if vim.api.nvim_win_get_cursor(state.msg_popup.winid)[1] <= 1 and not state.exhausted then
        M.load_older()
      end
    end,
  })
end

function M.close_chat()
  close_help()
  if state.chat_id then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local idx = M.message_at_cursor()
      if idx then state.saved_cursors[state.chat_id] = state.messages[idx].id end
    end
    state.last_chat = { id = state.chat_id, title = state.chat_title }
    server.close_chat(state.chat_id)
  end
  if state.layout then
    state.layout:unmount()
    state.layout = nil
  end
  state.msg_popup = nil
  state.input_popup = nil
  state.editor = nil
  state.group_popup = nil
  state.buf = nil
  state.win = nil
  state.messages = {}
  state.loading = false
  state.exhausted = false
  state.online_count = nil
  state.typing_users = {}
  state.chat_id = nil
  state.chat_title = ''
end

---@return integer|nil
function M.message_at_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
  local line = 1
  for idx, msg in ipairs(state.messages) do
    local n = #fmt_msg(msg)
    if cursor_line >= line and cursor_line < line + n then
      return idx
    end
    line = line + n + 1
  end
  return nil
end

---@return table|nil
function M.curr_msg()
  local i = M.message_at_cursor()
  return i and state.messages[i]
end

function M.jump_to_message(target_id)
  local function line_of()
    for i, m in ipairs(state.messages) do
      if m.id == target_id then
        local line = 1
        for j = 1, i - 1 do line = line + #fmt_msg(state.messages[j]) + 1 end
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

function M.load_older()
  if state.loading or state.exhausted or #state.messages == 0 then return end
  state.loading = true
  local chat_id = state.chat_id
  local oldest_id = state.messages[1].id
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local old_top = cursor[1]
  server.get_messages_async(chat_id, server.DEFAULT_LIMIT, oldest_id,
    function(data)
      if state.chat_id ~= chat_id then state.loading = false; return end
      local new_msgs = data.messages or {}
      if #new_msgs == 0 then state.exhausted = true; state.loading = false; return end
      local seen = {}
      for _, m in ipairs(state.messages) do seen[m.id] = true end
      local new_lines = 0
      for i = 1, #new_msgs do
        if not seen[new_msgs[i].id] then
          seen[new_msgs[i].id] = true
          table.insert(state.messages, 1, new_msgs[i])
          new_lines = new_lines + #fmt_msg(new_msgs[i]) + 1
        end
      end
      if state.chat_id ~= chat_id then state.loading = false; return end
      if new_lines > 0 then
        render()
        pcall(vim.api.nvim_win_set_cursor, state.win, { old_top + new_lines, cursor[2] })
      end
      state.loading = false
    end,
    function() state.loading = false end
  )
end

function M.refresh_messages(on_complete)
  if not state.msg_popup then return end
  state.loading = false
  state.exhausted = false
  local chat_id = state.chat_id
  server.get_messages_async(chat_id, 10, nil,
    function(data)
      if state.chat_id ~= chat_id then return end
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
      if state.chat_id ~= chat_id then return end
      render()
      if #state.messages > 0 then
        local latest = state.messages[#state.messages]
        local ts = os.date('%m-%d %H:%M', latest.date)
        state.last_msg = '[' .. ts .. '] ' .. (latest.sender and latest.sender.name or '?') .. ': ' .. (latest.text or '')
        server.view_messages(state.chat_id, latest.id)
      end
      update_input_title()
      if on_complete then on_complete() end
    end,
    function()
      vim.notify('[tg] Failed to load messages', vim.log.levels.ERROR)
      if on_complete then on_complete() end
    end
  )
end

return M
