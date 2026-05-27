local Editor = {}
Editor.__index = Editor

function Editor.new(opts)
	opts = opts or {}
	return setmetatable({
		placeholder = opts.placeholder or "",
		placeholder_ns = vim.api.nvim_create_namespace("editor_placeholder"),
		placeholder_active = false,
	}, Editor)
end

function Editor:input_line()
	return self._input_line or 0
end

function Editor:set_input_line(line)
	self._input_line = line
end

function Editor:bufnr()
	return self._bufnr
end

function Editor:set_bufnr(buf)
	self._bufnr = buf
end

function Editor:winid()
	return self._winid
end

function Editor:set_winid(win)
	self._winid = win
end

function Editor:focus()
	if self._winid and vim.api.nvim_win_is_valid(self._winid) then
		pcall(vim.api.nvim_set_current_win, self._winid)
	end
end

function Editor:get_text()
	if self.placeholder_active then
		return ""
	end
	local buf = self._bufnr
	local start = self._input_line
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not start or start == 0 then
		return ""
	end
	local line_count = vim.api.nvim_buf_line_count(buf)
	if start > line_count then
		return ""
	end
	local lines = vim.api.nvim_buf_get_lines(buf, start - 1, line_count, false)
	local text = table.concat(lines, "\n"):gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
	return text
end

function Editor:set_text(text)
	if not self._bufnr or not vim.api.nvim_buf_is_valid(self._bufnr) then
		return
	end
	self:hide_placeholder()
	local buf = self._bufnr
	local start = self._input_line
	local lines = vim.split(text or "", "\n")
	if #lines == 0 or (#lines == 1 and lines[1] == "") then
		lines = { "" }
	end
	local line_count = vim.api.nvim_buf_line_count(buf)
	local end_line = math.max(start, line_count)
	vim.api.nvim_buf_set_lines(buf, start - 1, end_line, false, lines)
end

function Editor:clear()
	if not self._bufnr or not vim.api.nvim_buf_is_valid(self._bufnr) then
		return
	end
	local buf = self._bufnr
	local start = self._input_line
	local line_count = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_buf_set_lines(buf, start - 1, line_count, false, { "" })
	local win = self._winid
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_set_cursor, win, { start, 0 })
	end
	self:show_placeholder()
end

function Editor:show_placeholder()
	if self.placeholder_active or #self.placeholder == 0 then
		return
	end
	local buf = self._bufnr
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(buf)
	local start = self._input_line
	if start > line_count then
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, start - 1, line_count, false)
	for _, line in ipairs(lines) do
		if line ~= "" then
			return
		end
	end
	self.placeholder_active = true
	vim.api.nvim_buf_set_lines(buf, start - 1, line_count, false, { self.placeholder })
	vim.api.nvim_buf_clear_namespace(buf, self.placeholder_ns, start - 2, -1)
	vim.api.nvim_buf_set_extmark(buf, self.placeholder_ns, start - 1, 0, {
		hl_group = "TgPlaceholder",
		end_col = #self.placeholder,
	})
end

function Editor:hide_placeholder()
	if not self.placeholder_active then
		return
	end
	self.placeholder_active = false
	local buf = self._bufnr
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, self.placeholder_ns, 0, -1)
	local start = self._input_line
	local line_count = vim.api.nvim_buf_line_count(buf)
	if start <= line_count then
		local first = vim.api.nvim_buf_get_lines(buf, start - 1, start, false)[1]
		if first == self.placeholder then
			vim.api.nvim_buf_set_lines(buf, start - 1, line_count, false, { "" })
		end
	end
	local win = self._winid
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_set_cursor, win, { start, 0 })
	end
end

function Editor:setup_autocmds()
	local buf = self._bufnr
	if not buf then
		return
	end
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = buf,
		callback = function()
			self:hide_placeholder()
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = buf,
		callback = function()
			self:show_placeholder()
		end,
	})
	vim.api.nvim_create_autocmd("TextChanged", {
		buffer = buf,
		callback = function()
			self:show_placeholder()
		end,
	})
end

return Editor
