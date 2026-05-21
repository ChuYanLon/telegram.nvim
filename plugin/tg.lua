if vim.g.loaded_telegram then return end
vim.g.loaded_telegram = true

local ok, tg = pcall(require, 'telegram')
if not ok then
  vim.notify('[tg] Failed to load plugin', vim.log.levels.ERROR)
  return
end
tg.setup()
