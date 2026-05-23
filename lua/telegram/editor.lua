local NuiPopup = require("nui.popup")

local Editor = {}
Editor.__index = Editor

local function default_win_opts()
  return { wrap = true, winhighlight = 'Normal:TgNoBg,FloatBorder:TgBorder' }
end

local function default_border()
  return { style = 'rounded', text = { top = '', top_align = 'center' } }
end

function Editor.new(opts)
  opts = opts or {}
  local self = setmetatable({
    placeholder = opts.placeholder or '',
    placeholder_ns = vim.api.nvim_create_namespace('editor_placeholder'),
    placeholder_active = false,
    popup = nil,
  }, Editor)

  self.popup = NuiPopup({
    enter = opts.enter == true,
    focusable = opts.focusable ~= false,
    zindex = opts.zindex or 100,
    border = opts.border or default_border(),
    buf_options = vim.tbl_deep_extend('force', { buftype = 'nofile', bufhidden = 'wipe' }, opts.buf_options or {}),
    win_options = vim.tbl_deep_extend('force', default_win_opts(), opts.win_options or {}),
    relative = opts.relative,
    position = opts.position,
    size = opts.size,
  })

  return self
end

function Editor:mount()
  self.popup:mount()
  self:setup()
end

function Editor:setup()
  self:_setup_autocmds()
  self:show_placeholder()
end

function Editor:unmount()
  self.popup:unmount()
end

function Editor:bufnr()
  return self.popup.bufnr
end

function Editor:winid()
  return self.popup.winid
end

function Editor:focus()
  pcall(vim.api.nvim_set_current_win, self.popup.winid)
end

function Editor:border()
  return self.popup.border
end

function Editor:set_border_text(text)
  if self.popup and self.popup.border then
    self.popup.border:set_text('top', text)
  end
end

function Editor:get_text()
  if self.placeholder_active then return '' end
  local lines = vim.api.nvim_buf_get_lines(self.popup.bufnr, 0, -1, false)
  local text = table.concat(lines, '\n'):gsub('^[\n ]+', ''):gsub('[\n ]+$', '')
  return text
end

function Editor:set_text(text)
  self:hide_placeholder()
  local lines = vim.split(text or '', '\n')
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, lines)
end

function Editor:clear()
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, { '' })
  pcall(vim.api.nvim_win_set_cursor, self.popup.winid, { 1, 0 })
  self:show_placeholder()
end

function Editor:show_placeholder()
  if self.placeholder_active or #self.placeholder == 0 then return end
  local buf = self.popup.bufnr
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    if line ~= '' then return end
  end
  self.placeholder_active = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { self.placeholder })
  vim.api.nvim_buf_clear_namespace(buf, self.placeholder_ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, self.placeholder_ns, 0, 0, {
    hl_group = 'TgPlaceholder',
    end_col = #self.placeholder,
  })
end

function Editor:hide_placeholder()
  if not self.placeholder_active then return end
  self.placeholder_active = false
  local buf = self.popup.bufnr
  if not buf then return end
  vim.api.nvim_buf_clear_namespace(buf, self.placeholder_ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  pcall(vim.api.nvim_win_set_cursor, self.popup.winid, { 1, 0 })
end

function Editor:_setup_autocmds()
  local buf = self.popup.bufnr
  vim.api.nvim_create_autocmd('InsertEnter', {
    buffer = buf,
    callback = function() self:hide_placeholder() end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = buf,
    callback = function() self:show_placeholder() end,
  })
  vim.api.nvim_create_autocmd('TextChanged', {
    buffer = buf,
    callback = function() self:show_placeholder() end,
  })
end

return Editor
