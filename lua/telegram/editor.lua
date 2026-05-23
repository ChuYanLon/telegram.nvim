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
    input_lines = opts.input_lines or 4,
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
  local lines = vim.api.nvim_buf_get_lines(self.popup.bufnr, 0, -1, false)
  local text = table.concat(lines, '\n'):gsub('^[\n ]+', ''):gsub('[\n ]+$', '')
  return text
end

function Editor:set_text(text)
  local lines = vim.split(text or '', '\n')
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, lines)
end

function Editor:clear()
  local empty = {}
  for _ = 1, self.input_lines do empty[#empty + 1] = '' end
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, empty)
end

function Editor:set_lines(opts)
  local count = opts and opts.count or self.input_lines
  local empty = {}
  for _ = 1, count do empty[#empty + 1] = '' end
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, empty)
end

return Editor
