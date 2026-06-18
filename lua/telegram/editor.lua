local state = require("telegram.state").state
local server = require("telegram.server")
local config = require("telegram.config")

local M = {}
local editor_buf = nil
local editor_win = nil
local editor_typing_chat_id = nil
local editor_input_start = nil
local editor_title = nil
local editor_attachment = nil
local editor_attach_line = nil

local function get_input_lines()
	if not editor_buf or not vim.api.nvim_buf_is_valid(editor_buf) then return {} end
	return vim.api.nvim_buf_get_lines(editor_buf, editor_input_start or 0, -1, false)
end

local function get_input_text()
	local lines = get_input_lines()
	return table.concat(lines, "\n"):gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
end

local function update_attach_line()
	if not editor_buf or not vim.api.nvim_buf_is_valid(editor_buf) or not editor_input_start then return end
	if editor_attachment and editor_attach_line then
		local fname = vim.fn.fnamemodify(editor_attachment, ":t")
		vim.api.nvim_buf_set_lines(editor_buf, editor_attach_line - 1, editor_attach_line, false, { "📎 " .. fname })
		pcall(vim.api.nvim_buf_add_highlight, editor_buf, -1, "TgService", editor_attach_line - 1, 0, -1)
	end
end

local function pick_attachment()
	if editor_attachment then
		vim.ui.select({ "Change file", "Remove attachment" }, { prompt = "Attachment: " .. vim.fn.fnamemodify(editor_attachment, ":t") }, function(choice)
			if not choice then return end
			if choice:match("Remove") then
				editor_attachment = nil
				update_attach_line()
			else
				pick_attachment()
			end
		end)
		return
	end

	local function browse_dir(dir)
		local entries = {}
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent ~= dir then
			table.insert(entries, { name = "../", path = parent, is_dir = true })
		end
		local names = vim.fn.readdir(dir)
		table.sort(names)
		for _, name in ipairs(names) do
			local full = dir .. "/" .. name
			local is_dir = vim.fn.isdirectory(full) == 1
			table.insert(entries, { name = is_dir and (name .. "/") or name, path = full, is_dir = is_dir })
		end
		vim.ui.select(entries, {
			prompt = "File (" .. dir .. "/)",
			format_item = function(e) return e.name end,
		}, function(choice)
			if not choice then return end
			if choice.is_dir then
				browse_dir(choice.path)
			else
				editor_attachment = choice.path
				update_attach_line()
			end
		end)
	end

	browse_dir(vim.fn.expand("%:p:h"))
end

function M.close_editor(save_draft)
	if save_draft and editor_title == "Send" and editor_buf and vim.api.nvim_buf_is_valid(editor_buf) then
		local text = get_input_text()
		state.editor_draft = #text > 0 and text or nil
	end
	editor_attachment = nil
	editor_attach_line = nil
	if editor_win and vim.api.nvim_win_is_valid(editor_win) then
		pcall(vim.api.nvim_win_close, editor_win, true)
	end
	editor_win = nil
	if editor_buf and vim.api.nvim_buf_is_valid(editor_buf) then
		pcall(vim.api.nvim_buf_delete, editor_buf, { force = true })
	end
	editor_buf = nil
	if state._typing_timer then
		vim.fn.timer_stop(state._typing_timer)
		state._typing_timer = nil
	end
	if editor_typing_chat_id then
		server.send_chat_action_async(editor_typing_chat_id, "chatActionCancel")
		editor_typing_chat_id = nil
	end
end

function M.open_editor(title, default_text, callback, context)
	M.close_editor()
	editor_title = title
	editor_attachment = nil
	editor_attach_line = nil
	local typing_ticks = 0
	local typing_chat_id = state.chat_id
	if typing_chat_id then
		server.send_chat_action_async(typing_chat_id, "chatActionTyping")
		state._typing_timer = vim.fn.timer_start(5000, function()
			typing_ticks = typing_ticks + 1
			if typing_ticks >= 12 then
				state._typing_timer = nil
				return
			end
			server.send_chat_action_async(typing_chat_id, "chatActionTyping")
		end, { ["repeat"] = -1 })
	end
	local width = state.win and vim.api.nvim_win_get_width(state.win) or 50
	local editor_row = state.win and vim.api.nvim_win_get_position(state.win)
	local context_lines = {}
	if context and #context > 0 then
		for _, l in ipairs(vim.split(context, "\n")) do
			if #l > 60 then l = l:sub(1, 60) .. "…" end
			table.insert(context_lines, "  ┃ " .. l)
		end
	end
	local extra = #context_lines > 0 and (#context_lines + 2) or 1
	local height = 8 + extra
	local row = editor_row and (editor_row[1] + vim.api.nvim_win_get_height(state.win) - height) or (vim.o.lines - height)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	pcall(vim.treesitter.language.register, "markdown", "telegram")
	vim.bo[buf].filetype = "telegram"
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, row),
		col = editor_row and editor_row[2] or 0,
		zindex = 150,
		style = "minimal",
		border = "none",
	})
	vim.wo[win].winhighlight = "Normal:TgNoBg"
	editor_buf = buf
	editor_win = win
	editor_typing_chat_id = typing_chat_id
	local function close()
		M.close_editor()
	end
	local content = vim.split(default_text or "", "\n")
	if #content == 0 then content = { "" } end
	local sep = string.rep("─", width)
	local buf_lines = { sep }
	if #context_lines > 0 then
		for _, l in ipairs(context_lines) do table.insert(buf_lines, l) end
		table.insert(buf_lines, sep)
	end
	table.insert(buf_lines, "")
	editor_attach_line = #buf_lines
	for _, l in ipairs(content) do table.insert(buf_lines, l) end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
	pcall(vim.api.nvim_buf_add_highlight, buf, -1, "TgBorder", 0, 0, -1)
	if #context_lines > 0 then
		pcall(vim.api.nvim_buf_add_highlight, buf, -1, "TgBorder", #context_lines + 1, 0, -1)
		for i = 1, #context_lines do
			pcall(vim.api.nvim_buf_add_highlight, buf, -1, "TgService", i, 0, -1)
		end
	end
	local input_start = #context_lines > 0 and (#context_lines + 2) or 1
	editor_input_start = input_start + 1
	if #context_lines > 0 then
		vim.keymap.set("i", "<BS>", function()
			local cur = vim.api.nvim_win_get_cursor(win)
			if cur[1] == editor_input_start + 1 and cur[2] == 0 then return end
			local bs = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
			vim.api.nvim_feedkeys(bs, "n", false)
		end, { buffer = buf, nowait = true })
	end
	-- file attachment key
	vim.keymap.set("n", "<C-f>", pick_attachment, { buffer = buf, nowait = true })
	vim.keymap.set("i", "<C-f>", pick_attachment, { buffer = buf, nowait = true })
	pcall(vim.api.nvim_win_set_cursor, win, { editor_input_start + 1, 0 })
	vim.cmd("startinsert!")
	do
		local k = config.key("editor_submit")
		if k then
			vim.keymap.set("n", k, function()
				local text = get_input_text()
				local attach = editor_attachment
				close()
				if #text > 0 or attach then
					callback(text, attach)
				end
			end, { buffer = buf, nowait = true })
			vim.keymap.set("i", "<C-s>", function()
				local text = get_input_text()
				local attach = editor_attachment
				close()
				if #text > 0 or attach then
					callback(text, attach)
				end
			end, { buffer = buf, nowait = true })
		end
	end
	do
		local k = config.key("editor_cancel")
		if k then
			vim.keymap.set("n", k, function()
				if title == "Send" then
					local text = get_input_text()
					state.editor_draft = #text > 0 and text or nil
				end
				close()
				callback(nil)
			end, { buffer = buf, nowait = true })
		end
	end
end

return M
