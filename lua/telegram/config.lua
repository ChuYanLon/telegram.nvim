---@class TgConfig
---@field data_dir string
---@field tdlib_path string|nil
---@field api_id integer|nil
---@field api_hash string|nil
---@field proxy string|nil

local info = debug.getinfo(1, 'S')
local plugin_root = vim.fn.fnamemodify(info.source:match('@(.+)'), ':h:h:h')

local M = {}

---@type TgConfig
M.config = {
  data_dir = plugin_root,
  tdlib_path = nil,
  api_id = nil,
  api_hash = nil,
  proxy = nil,
}

---@param opts TgConfig|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  vim.api.nvim_set_hl(0, 'TgTimestamp', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'TgPlaceholder', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'TgSender', { link = 'Identifier', default = true })
  vim.api.nvim_set_hl(0, 'TgKey', { link = 'Keyword', default = true })
  vim.api.nvim_set_hl(0, 'TgReplyIndicator', { bold = true, default = true })
  vim.api.nvim_set_hl(0, 'TgReplyBg', { bg = '#2e3a4e', default = true })
  vim.api.nvim_set_hl(0, 'TgNoBg', { fg = 'NONE', bg = 'NONE', default = true })
  local bfg = (vim.api.nvim_get_hl(0, { id = vim.api.nvim_get_hl_id_by_name('FloatBorder') }) or {}).fg or '#6c6c6c'
  vim.api.nvim_set_hl(0, 'TgBorder', { fg = bfg, bg = 'NONE', default = true })
end

---@type string
M.plugin_root = plugin_root

---@return boolean
function M.ensure_deps()
  if vim.fn.executable('node') ~= 1 then
    vim.notify('[tg] Node.js not found. Install nodejs first.', vim.log.levels.ERROR)
    return false
  end
  if vim.fn.executable('curl') ~= 1 then
    vim.notify('[tg] curl not found.', vim.log.levels.ERROR)
    return false
  end
  if M.config.tdlib_path then
    vim.notify('[tg] tdlib_path: ' .. M.config.tdlib_path, vim.log.levels.INFO)
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

return M
