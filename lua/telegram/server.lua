local config = require('telegram.config')

local M = {}

local http_port = 8080
local ws_port = 8081
local server_job = nil

local function base_url() return 'http://localhost:' .. http_port end
local function ws_url_internal() return 'ws://localhost:' .. ws_port end

function M.ws_url() return ws_url_internal() end

---@param path string
---@return table|nil
local function http_get(path)
  local url = base_url() .. path
  local result = vim.fn.system({ 'curl', '-s', '--fail-with-body', url })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, result)
  if not ok then return nil end
  return data
end

---@param path string
---@param body table
---@return table|nil
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

---@return table|nil
function M.server_health()
  local r = vim.fn.system({ 'curl', '-s', '--connect-timeout', '2', '--max-time', '3', base_url() .. '/health' })
  if vim.v.shell_error ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, r)
  if not ok or type(data) ~= 'table' then return nil end
  return data
end

---@param value string
---@return boolean
function M.post_auth_input(value)
  local url = base_url() .. '/auth/input'
  local encoded = vim.json.encode({ value = value })
  vim.fn.system({
    'curl', '-s', '-X', 'POST', url,
    '-H', 'Content-Type: application/json',
    '-d', encoded,
  })
  return vim.v.shell_error == 0
end

---@return '"free"'|'"ready"'|'"ours"'|'"other"'
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

---@return boolean
local function server_wait_reachable()
  for _ = 1, 20 do
    if M.server_health() then return true end
    vim.wait(500)
  end
  return false
end

---@return boolean
function M.start_server()
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
  local env = {
    TG_DATA_DIR = config.config.data_dir,
    TG_PORT = tostring(http_port),
    TG_WS_PORT = tostring(ws_port),
  }
  if config.config.tdlib_path then env.TG_TDLIB_PATH = config.config.tdlib_path end
  if config.config.api_id then env.TG_API_ID = tostring(config.config.api_id) end
  if config.config.api_hash then env.TG_API_HASH = config.config.api_hash end
  if config.config.proxy then env.TG_PROXY = config.config.proxy end
  local server_script = config.plugin_root .. '/src/server.js'
  server_job = vim.fn.jobstart({ 'node', server_script }, {
    cwd = config.plugin_root,
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

function M.stop_server()
  if server_job then
    vim.fn.jobstop(server_job)
    server_job = nil
  end
end

---@type integer
M.DEFAULT_LIMIT = 10

---@return table|nil
function M.get_groups()
  return http_get('/groups')
end

---@param chat_id any
---@param limit integer|nil
---@param before any|nil
---@return table|nil
function M.get_messages(chat_id, limit, before)
  local path = '/messages?chatId=' .. chat_id .. '&limit=' .. (limit or M.DEFAULT_LIMIT)
  if before then path = path .. '&before=' .. before end
  return http_get(path)
end

---@param chat_id any
---@param text string
---@param replyTo any|nil
---@return boolean
function M.send_message(chat_id, text, replyTo)
  local body = { chatId = chat_id, text = text }
  if replyTo then body.replyTo = replyTo end
  return http_post('/sendMessage', body)
end

---@param chat_id any
---@param message_id any
---@param text string
---@return boolean
function M.edit_message(chat_id, message_id, text)
  return http_post('/editMessage', { chatId = chat_id, messageId = message_id, text = text })
end

---@param chat_id any
---@param message_id any
---@return boolean
function M.delete_message(chat_id, message_id)
  return http_post('/deleteMessage', { chatId = chat_id, messageId = message_id })
end

return M
