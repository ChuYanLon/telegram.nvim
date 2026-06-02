if vim.g.loaded_telegram then return end
vim.g.loaded_telegram = true

local ok, tg = pcall(require, 'telegram')
if not ok then
  vim.notify('Failed to load plugin', vim.log.levels.ERROR, { title = 'tg' })
  return
end
local setup_ok, setup_err = pcall(tg.setup)
if not setup_ok then
  vim.notify('telegram.nvim setup failed: ' .. tostring(setup_err), vim.log.levels.ERROR, { title = 'tg' })
end
