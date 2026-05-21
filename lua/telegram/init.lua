local info = debug.getinfo(1, 'S')
local plugin_root = vim.fn.fnamemodify(info.source:match('@(.+)'), ':h:h:h')

local M = {}

M.config = {
  data_dir = plugin_root,
  tdlib_path = nil,
  api_id = nil,
  api_hash = nil,
  proxy = nil,
}

local http_port = 8080
local ws_port = 8081

local function base_url() return 'http://localhost:' .. http_port end
local function ws_url() return 'ws://localhost:' .. ws_port end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  vim.api.nvim_set_hl(0, 'TgTimestamp', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'TgSender', { link = 'Identifier', default = true })
  vim.api.nvim_set_hl(0, 'TgKey', { link = 'Keyword', default = true })
  vim.api.nvim_set_hl(0, 'TgNoBg', { fg = 'NONE', bg = 'NONE', default = true })
  local bfg = (vim.api.nvim_get_hl(0, { id = vim.api.nvim_get_hl_id_by_name('FloatBorder') }) or {}).fg or '#6c6c6c'
  vim.api.nvim_set_hl(0, 'TgBorder', { fg = bfg, bg = 'NONE', default = true })
end

local function ensure_deps()
  if vim.fn.executable('node') ~= 1 then
    vim.notify('[tg] Node.js not found. Install nodejs first.', vim.log.levels.ERROR)
    return false
  end
  if vim.fn.executable('curl') ~= 1 then
    vim.notify('[tg] curl not found.', vim.log.levels.ERROR)
    return false
  end
  if not M.config.tdlib_path then
    vim.notify('[tg] tdlib_path not set. Set config.tdlib_path in setup().', vim.log.levels.ERROR)
    vim.notify('[tg] See https://github.com/Bannerets/tdl#installation', vim.log.levels.INFO)
    return false
  end
  local ws_helper = plugin_root .. '/bin/tg-ws-helper.js'
  if vim.fn.filereadable(ws_helper) ~= 1 then
    vim.notify('[tg] Missing ws helper', vim.log.levels.ERROR)
    return false
  end
  local server_src = plugin_root .. '/src/server.js'
  if vim.fn.filereadable(server_src) ~= 1 then
    vim.notify('[tg] Missing server source. Run npm install', vim.log.levels.ERROR)
    return false
  end
  return true
end

local server_job = nil
local initialized = false

local function http_get(path)
  local url = base_url() .. path
  local result = vim.fn.system({ 'curl', '-s', '--fail-with-body', url })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, result)
  if not ok then return nil end
  return data
end

local function http_post(path, body)
  local url = base_url() .. path
  local encoded = vim.json.encode(body)
  local result = vim.fn.system({
    'curl', '-s', '--fail-with-body', '-X', 'POST', url,
    '-H', 'Content-Type: application/json',
    '-d', encoded,
  })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, result)
  if not ok then return nil end
  if type(data) == 'table' and data.error then
    vim.notify('[tg] ' .. data.error, vim.log.levels.ERROR)
    return nil
  end
  return data
end

local function server_health()
  local r = vim.fn.system({ 'curl', '-s', '--connect-timeout', '2', '--max-time', '3', base_url() .. '/health' })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, r)
  if not ok or type(data) ~= 'table' then return nil end
  return data
end

local function post_auth_input(value)
  local url = base_url() .. '/auth/input'
  local encoded = vim.json.encode({ value = value })
  vim.fn.system({
    'curl', '-s', '-X', 'POST', url,
    '-H', 'Content-Type: application/json',
    '-d', encoded,
  })
  return vim.v.shell_error == 0
end

-- Returns "ready" | "ours" | "other" | "free"
local function check_port()
  local r = vim.fn.system({ 'curl', '-s', '--connect-timeout', '1', '--max-time', '2', base_url() .. '/health' })
  if vim.v.shell_error ~= 0 then return 'free' end
  local ok, data = pcall(vim.json.decode, r)
  if ok and type(data) == 'table' then
    if data.ready == true then return 'ready' end
    if data.ready == false then return 'ours' end
  end
  return 'other'
end

local function server_wait_reachable()
  for _ = 1, 20 do
    if server_health() then return true end
    vim.wait(500)
  end
  return false
end

local function start_server()
  local status = check_port()
  if status == 'ready' then return true end

  while status == 'other' do
    http_port = http_port + 2
    ws_port = ws_port + 2
    if http_port > 9000 then
      vim.notify('[tg] No free port', vim.log.levels.ERROR)
      return false
    end
    status = check_port()
  end

  if status == 'ours' then
    return server_wait_reachable()
  end

  if http_port ~= 8080 then
    vim.notify('[tg] Using port ' .. http_port, vim.log.levels.INFO)
  end

  local env = { TG_DATA_DIR = M.config.data_dir, TG_PORT = tostring(http_port), TG_WS_PORT = tostring(ws_port) }
  if M.config.tdlib_path then env.TG_TDLIB_PATH = M.config.tdlib_path end
  if M.config.api_id then env.TG_API_ID = tostring(M.config.api_id) end
  if M.config.api_hash then env.TG_API_HASH = M.config.api_hash end
  if M.config.proxy then env.TG_PROXY = M.config.proxy end

  local server_script = plugin_root .. '/src/server.js'

  server_job = vim.fn.jobstart({ 'node', server_script }, {
    cwd = plugin_root,
    env = env,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and #line > 0 then
          if line:find('Error:') or line:find('MODULE_NOT_FOUND') then
            vim.notify('[tg] ' .. line, vim.log.levels.ERROR)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code > 0 then
        vim.notify('[tg] Server exited with code ' .. code, vim.log.levels.ERROR)
      end
      server_job = nil
    end,
  })

  if not server_job or server_job <= 0 then
    vim.notify('[tg] Failed to start server', vim.log.levels.ERROR)
    return false
  end

  return server_wait_reachable()
end

-- Async auth: polls /health, shows input via vim.ui.input, calls on_done(success)
local function auth_poll(on_done)
  local function poll()
    local health = server_health()
    if not health then
      vim.defer_fn(poll, 500)
      return
    end
    if health.ready == true then
      on_done(true)
      return
    end

    local a = health.auth
    if not a or a.state == 'initializing' then
      vim.defer_fn(poll, 500)
      return
    end

    if a.state == 'error' then
      vim.notify('[tg] Auth failed: ' .. (type(a.error) == 'string' and a.error or 'unknown'), vim.log.levels.ERROR)
      on_done(false)
      return
    end

    if (a.state == 'waitPhone' or a.state == 'waitCode' or a.state == 'waitPassword') and a.canInput then
      local prompt
      if a.state == 'waitPhone' then
        prompt = 'Phone number'
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      elseif a.state == 'waitCode' then
        prompt = 'Verification code'
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      else
        prompt = '2FA password'
        if type(a.hint) == 'string' then prompt = prompt .. ' (hint: ' .. a.hint .. ')' end
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      end

      vim.ui.input({ prompt = prompt .. ': ' }, function(val)
        if val and #val > 0 then
          post_auth_input(val)
        else
          vim.notify('[tg] Auth cancelled', vim.log.levels.INFO)
          on_done(false)
          return
        end
        vim.defer_fn(poll, 500)
      end)
      return
    end

    vim.defer_fn(poll, 500)
  end

  poll()
end

local function stop_server()
  if server_job then
    vim.fn.jobstop(server_job)
    server_job = nil
  end
end

function M.get_groups()
  return http_get('/groups')
end

local DEFAULT_LIMIT = 10

function M.get_messages(chat_id, limit, before)
  local path = '/messages?chatId=' .. chat_id .. '&limit=' .. (limit or DEFAULT_LIMIT)
  if before then path = path .. '&before=' .. before end
  return http_get(path)
end

function M.send_message(chat_id, text)
  return http_post('/sendMessage', { chatId = chat_id, text = text })
end

-- WS
local ws_job_id = nil
local ws_on_message = nil

function M.ws_start(on_msg)
  ws_on_message = on_msg
  if ws_job_id then
    vim.fn.jobstop(ws_job_id)
    ws_job_id = nil
  end
  local helper = plugin_root .. '/bin/tg-ws-helper.js'
  ws_job_id = vim.fn.jobstart({ 'node', helper, ws_url() }, {
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and #line > 0 then
          local ok, msg = pcall(vim.json.decode, line)
          if ok and ws_on_message then
            ws_on_message(msg)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            vim.notify('[tg-ws] ' .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function() ws_job_id = nil end,
  })
end

function M.ws_stop()
  if ws_job_id then
    vim.fn.jobstop(ws_job_id)
    ws_job_id = nil
  end
end

-- Chat UI

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
  menu_width = nil,
}

local function set_lines(lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_option, state.buf, 'modifiable', false)
end

local function fmt_msg(msg)
  local date_str = os.date('%m-%d %H:%M', msg.date)
  local sender = msg.sender and msg.sender.name or 'unknown'
  local parts = vim.split(msg.text or '', '\n')
  local out = { string.format('[%s] %s: %s', date_str, sender, parts[1]) }
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
    local ts_end = text:match('^%[%d+%-%d+ %d+:%d+%] ')
    if ts_end then
      local ts_len = #ts_end
      vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgTimestamp', line, 0, ts_len)
      local rest = text:sub(ts_len + 1)
      local _, se = rest:find('^[^:]+: ')
      if se then
        vim.api.nvim_buf_add_highlight(state.buf, hl_ns, 'TgSender', line, ts_len, ts_len + se - 2)
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

local function update_title()
  if not state.menu_buf or not vim.api.nvim_buf_is_valid(state.menu_buf) then return end
  local line = vim.api.nvim_buf_get_lines(state.menu_buf, 0, 1, false)[1]
  if not line then return end
  local clean = line:gsub('^  ◆ %d+  ', '')
  vim.api.nvim_buf_set_lines(state.menu_buf, 0, 1, false, { '  ◆ ' .. state.unread .. '  ' .. clean })
end

local function close_chat()
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

local function close_chat_forget()
  close_chat()
  state.last_chat = nil
  M.ws_stop()
  stop_server()
  initialized = false
end

local function load_older()
  if state.loading or state.exhausted or #state.messages == 0 then return end
  state.loading = true
  local oldest_id = state.messages[1].id
  local data = M.get_messages(state.chat_id, DEFAULT_LIMIT, oldest_id)
  if not data then state.loading = false; return end
  local new_msgs = data.messages or {}
  if #new_msgs == 0 or #new_msgs < DEFAULT_LIMIT then
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
  local data = M.get_messages(state.chat_id, DEFAULT_LIMIT)
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
    vim.api.nvim_win_set_cursor(state.win, { #state.messages, 0 })
  end
end

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
  local bar_text = 'i:reply    s:switch    r:refresh    Esc:back    q:quit'
  local left = math.floor((width - #bar_text) / 2)
  local bar = string.rep(' ', left) .. bar_text .. string.rep(' ', width - #bar_text - left)
  state.menu_width = width
  state.menu_bar = bar_text
  state.menu_win = vim.api.nvim_open_win(state.menu_buf, false, {
    relative = 'editor', width = width, height = 1,
    row = row + msg_h + 2, col = col,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 5,
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:TgNoBg,FloatBorder:TgBorder', { win = state.menu_win })
  vim.api.nvim_buf_set_lines(state.menu_buf, 0, -1, false, { bar })
  for pos, key in bar:gmatch('()([%w<>]+):') do
    vim.api.nvim_buf_add_highlight(state.menu_buf, hl_ns, 'TgKey', 0, pos - 1, pos - 1 + #key)
  end
  update_title()
  vim.keymap.set('n', '<Esc>', close_chat, { buffer = state.buf })
  vim.keymap.set('n', 'q', close_chat_forget, { buffer = state.buf })
  vim.keymap.set('n', 's', function()
    M.list_groups(true)
  end, { buffer = state.buf })
  vim.keymap.set('n', 'r', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    refresh_messages()
  end, { buffer = state.buf })
  vim.keymap.set('n', 'i', function()
    if state.unread > 0 then state.unread = 0; update_title() end
    vim.ui.input({ prompt = 'Message: ' }, function(text)
      if text and #text > 0 then
        local ok = M.send_message(state.chat_id, text)
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

local function finish_init()
  M.ws_start(function(msg)
    if msg.event == 'newMessage' then
      if state.chat_id and msg.chat and msg.chat.id == state.chat_id then
        vim.schedule(function()
          local total_before = vim.api.nvim_buf_line_count(state.buf)
          local cur = vim.api.nvim_win_get_cursor(state.win)
          local at_bottom = cur[1] >= total_before - 1

          if not at_bottom then state.unread = state.unread + 1 end
          update_title()

          table.insert(state.messages, {
            id = msg.id or (os.time() .. math.random()),
            date = msg.date,
            sender = msg.sender,
            text = msg.text,
          })
          render()

          if at_bottom then
            pcall(vim.api.nvim_win_set_cursor, state.win, { vim.api.nvim_buf_line_count(state.buf) - 1, cur[2] })
          end
          state.exhausted = false
        end)
      else
        vim.notify(string.format('[%s] %s: %s',
          msg.chat and msg.chat.title or '?',
          msg.sender and msg.sender.name or '?',
          msg.text and msg.text:sub(1, 80) or '?'
        ), vim.log.levels.INFO, { title = 'Telegram' })
      end
    end
  end)
  initialized = true
end

function M.list_groups(force_picker)
  force_picker = force_picker == true
  if not initialized then
    if not ensure_deps() then return end
    vim.notify('[tg] Starting server...', vim.log.levels.INFO)
    if not start_server() then return end

    local health = server_health()
    if health and health.ready == true then
      finish_init()
    else
      vim.notify('[tg] Waiting for auth...', vim.log.levels.INFO)
      auth_poll(function(success)
        if success then
          finish_init()
          vim.schedule(function() M.list_groups(force_picker) end)
        else
          stop_server()
          local db = M.config.data_dir .. '/tdlib_db'
          local files = M.config.data_dir .. '/tdlib_files'
          vim.fn.delete(db, 'rf')
          vim.fn.delete(files, 'rf')
        end
      end)
      return
    end
  end

  -- If chat window is already open, reopen to refresh
  -- If last_chat exists, reopen directly
  if not force_picker then
    if state.last_chat and not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
      M.open_chat(state.last_chat.id, state.last_chat.title)
      return
    end
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      refresh_messages()
      return
    end
  end

  local groups = M.get_groups()
  if not groups then
    vim.notify('[tg] No groups found', vim.log.levels.WARN)
    return
  end
  if #groups == 0 then
    vim.notify('[tg] Syncing chats, please wait...', vim.log.levels.INFO)
    local ok = vim.wait(15000, function()
      vim.wait(1000)
      groups = M.get_groups()
      return groups and #groups > 0
    end, 0, true)
    if not ok or not groups or #groups == 0 then
      vim.notify('[tg] No groups found', vim.log.levels.WARN)
      return
    end
  end
  local items = {}
  for _, g in ipairs(groups) do
    local desc = ''
    if g.lastMessage then
      local s = g.lastMessage.sender and g.lastMessage.sender.name or '?'
      desc = s .. ': ' .. (g.lastMessage.text:len() > 60 and g.lastMessage.text:sub(1, 60) .. '…' or g.lastMessage.text)
    end
    local member_info = g.memberCount and (' (' .. g.memberCount .. ' members)') or ''
    table.insert(items, { id = g.id, label = g.title .. member_info, detail = desc })
  end
  vim.ui.select(items, {
    prompt = 'Select a group:',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then
      close_chat()
      M.open_chat(choice.id, choice.label)
    end
  end)
end

-- Cleanup on exit
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('TgCleanup', { clear = true }),
  callback = function()
    M.ws_stop()
    stop_server()
  end,
})

vim.api.nvim_create_user_command('Tg', M.list_groups, {})

function M.logout()
  vim.notify('[tg] Logging out and clearing auth data...', vim.log.levels.INFO)
  stop_server()
  local db_dir = M.config.data_dir .. '/tdlib_db'
  local files_dir = M.config.data_dir .. '/tdlib_files'
  vim.fn.delete(db_dir, 'rf')
  vim.fn.delete(files_dir, 'rf')
  initialized = false
  vim.notify('[tg] Logged out. Run :Tg again to re-authenticate', vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('TgLogout', M.logout, {})
vim.api.nvim_create_user_command('TgGroups', M.list_groups, {})
vim.api.nvim_create_user_command('TgSend', function(opts)
  local args = vim.fn.split(opts.args)
  if #args < 2 then
    vim.notify('[tg] Usage: TgSend <chatId> <text>', vim.log.levels.ERROR)
    return
  end
  local chat_id = tonumber(args[1])
  if not chat_id then
    vim.notify('[tg] chatId must be a number', vim.log.levels.ERROR)
    return
  end
  local text = table.concat(args, ' ', 2)
  if M.send_message(chat_id, text) then
    vim.notify('[tg] Message sent', vim.log.levels.INFO)
  end
end, { nargs = '+' })

return M
