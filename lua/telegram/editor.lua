local state = require("telegram.state").state
local server = require("telegram.server")
local config = require("telegram.config")

local M = {}

function M.open_editor(title, default_text, callback, context)
	if state._typing_timer then
		vim.fn.timer_stop(state._typing_timer)
	end
	state._typing_timer = nil
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
	local function close()
		if state._typing_timer then
			vim.fn.timer_stop(state._typing_timer)
			state._typing_timer = nil
		end
		if typing_chat_id then
			server.send_chat_action_async(typing_chat_id, "chatActionCancel")
		end
		pcall(vim.api.nvim_win_close, win, true)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	local content = vim.split(default_text or "", "\n")
	if #content == 0 then content = { "" } end
	local sep = string.rep("─", width)
	local buf_lines = { sep }
	if #context_lines > 0 then
		for _, l in ipairs(context_lines) do table.insert(buf_lines, l) end
		table.insert(buf_lines, sep)
	end
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
	pcall(vim.api.nvim_win_set_cursor, win, { input_start + 1, 0 })
	if #context_lines > 0 then
		vim.keymap.set("i", "<BS>", function()
			local cur = vim.api.nvim_win_get_cursor(win)
			if cur[1] == input_start + 1 and cur[2] == 0 then return end
			local bs = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
			vim.api.nvim_feedkeys(bs, "n", false)
		end, { buffer = buf, nowait = true })
	end
	vim.cmd("startinsert!")
	do
		local k = config.key("editor_submit")
		if k then
			vim.keymap.set("n", k, function()
				local lines = vim.api.nvim_buf_get_lines(buf, input_start, -1, false)
				local text = table.concat(lines, "\n"):gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
				close()
				if #text > 0 then
					callback(text)
				end
			end, { buffer = buf, nowait = true })
			vim.keymap.set("i", "<C-s>", function()
				local lines = vim.api.nvim_buf_get_lines(buf, input_start, -1, false)
				local text = table.concat(lines, "\n"):gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
				close()
				if #text > 0 then
					callback(text)
				end
			end, { buffer = buf, nowait = true })
		end
	end
	do
		local k = config.key("editor_cancel")
		if k then
			vim.keymap.set("n", k, function()
				close()
				callback(nil)
			end, { buffer = buf, nowait = true })
		end
	end
end

return M
