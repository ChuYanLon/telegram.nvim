---@class TgHealth
---@field ready boolean
---@field auth TgAuth|nil

---@class TgAuth
---@field state string
---@field error string|nil
---@field hint string|nil
---@field canInput boolean|nil

---@class TgChat
---@field id any
---@field title string
---@field lastMessage TgMessage|nil
---@field memberCount integer|nil

local config = require('telegram.config')
local server = require('telegram.server')
local auth = require('telegram.auth')
local ws = require('telegram.ws')
local ui = require('telegram.ui')

local M = {}

local initialized = false

---@param v boolean
function M.set_initialized(v)
  initialized = v
end

M.setup = config.setup

local function finish_init()
  ws.ws_start(function(msg)
    if msg.event == 'newMessage' then
      local state = ui.state
      if state.chat_id and msg.chat and msg.chat.id == state.chat_id then
        vim.schedule(function()
          local total_before = vim.api.nvim_buf_line_count(state.buf)
          local cur = vim.api.nvim_win_get_cursor(state.win)
          local at_bottom = cur[1] >= total_before - 1
          if not at_bottom then state.unread = state.unread + 1 end
          local ts = os.date('%m-%d %H:%M', msg.date)
          local preview = '[' .. ts .. '] ' .. (msg.sender and msg.sender.name or '?') .. ': ' .. (msg.text or '')
          state.last_msg = preview:sub(1, 60)
          ui.update_title()
          table.insert(state.messages, {
            id = msg.id or (os.time() .. math.random()),
            date = msg.date,
            sender = msg.sender,
            text = msg.text,
            replyTo = msg.replyTo,
          })
          ui.render()
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

---@param force_picker boolean|nil
function M.list_groups(force_picker)
  force_picker = force_picker == true
  if not initialized then
    if not config.ensure_deps() then return end
    vim.notify('[tg] Starting server...', vim.log.levels.INFO)
    if not server.start_server() then return end
    local health = server.server_health()
    if health and health.ready == true then
      finish_init()
    else
      vim.notify('[tg] Waiting for auth...', vim.log.levels.INFO)
      auth.auth_poll(function(success)
        if success then
          finish_init()
          vim.schedule(function() M.list_groups(force_picker) end)
        else
          server.stop_server()
          local db = config.config.data_dir .. '/tdlib_db'
          local files = config.config.data_dir .. '/tdlib_files'
          vim.fn.delete(db, 'rf')
          vim.fn.delete(files, 'rf')
        end
      end)
      return
    end
  end
  if not force_picker then
    if ui.state.last_chat and not (ui.state.buf and vim.api.nvim_buf_is_valid(ui.state.buf)) then
      ui.open_chat(ui.state.last_chat.id, ui.state.last_chat.title)
      return
    end
    if ui.state.buf and vim.api.nvim_buf_is_valid(ui.state.buf) then
      ui.refresh_messages()
      return
    end
  end
  local groups = server.get_groups()
  if not groups then
    vim.notify('[tg] No groups found', vim.log.levels.WARN)
    return
  end
  if #groups == 0 then
    vim.notify('[tg] Syncing chats, please wait...', vim.log.levels.INFO)
    local ok = vim.wait(15000, function()
      vim.wait(1000)
      groups = server.get_groups()
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
      ui.close_chat()
      ui.open_chat(choice.id, choice.label)
    end
  end)
end

function M.logout()
  vim.notify('[tg] Logging out and clearing auth data...', vim.log.levels.INFO)
  server.stop_server()
  local db_dir = config.config.data_dir .. '/tdlib_db'
  local files_dir = config.config.data_dir .. '/tdlib_files'
  vim.fn.delete(db_dir, 'rf')
  vim.fn.delete(files_dir, 'rf')
  initialized = false
  vim.notify('[tg] Logged out. Run :Tg again to re-authenticate', vim.log.levels.INFO)
end

-- API re-exports
M.get_groups = server.get_groups
M.get_messages = server.get_messages
M.send_message = server.send_message
M.edit_message = server.edit_message
M.ws_start = ws.ws_start
M.ws_stop = ws.ws_stop
M.open_chat = ui.open_chat

-- Cleanup on exit
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('TgCleanup', { clear = true }),
  callback = function()
    ws.ws_stop()
    server.stop_server()
  end,
})

vim.api.nvim_create_user_command('Tg', M.list_groups, {})
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
  if server.send_message(chat_id, text) then
    vim.notify('[tg] Message sent', vim.log.levels.INFO)
  end
end, { nargs = '+' })

return M
