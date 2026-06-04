local state = require("telegram.state").state
local server = require("telegram.server")
local config = require("telegram.config")

local M = {}

function M.open_editor(title, default_text, callback)
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
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	local width, height = 60, 8
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, (vim.o.lines - height) / 2),
		col = math.max(0, (vim.o.columns - width) / 2),
		zindex = 150,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})
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
	local lines = vim.split(default_text or "", "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines == 0 and { "" } or lines)
	vim.cmd("startinsert!")
	do
		local k = config.key("editor_submit")
		if k then
			vim.keymap.set("n", k, function()
				local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
				text = text:gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
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
