local config = require("telegram.config")

local M = {}

local help_win = nil

local function close_help()
	if help_win then
		pcall(vim.api.nvim_win_close, help_win, true)
		help_win = nil
	end
end

function M.show_help()
	close_help()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	local width, height = 42, 26
	help_win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, (vim.o.lines - height) / 2),
		col = math.max(0, (vim.o.columns - width) / 2),
		zindex = 200,
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})
	vim.wo[help_win].winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder"
	local lines = {
		"-- Messages --",
		" i          open input editor",
		" <CR>       reply / jump to original",
		" e          edit own message",
		" d          delete / revoke",
		" f          forward message",
		" p          pin / unpin message",
		" G          refresh + jump to bottom",
		" B          ban message sender",
		" c          open DM with message sender",
		" r          react to message",
		"",
		"-- Tools (@) --",
		" chats      switch chat (Snacks picker)",
		" members    view and manage members",
		" invitelinks  manage invite links",
		" groupsettings  group settings menu",
		" refresh    reload messages",
		" send       send a message",
		" search     search history",
		" refreshmedia  re-download HD media",
		" openlink    open URL or media file",
		" newchat     start DM by @username",
		"",
		"-- Chat Picker --",
		" built-in fuzzy search via Snacks picker",
		" <CR> / <Esc>  select / cancel",
		"",
		"-- General --",
		" ?          toggle this help",
		" @          open tool picker",
		" <Esc>      close this help",
		" :Tg        close chat / quit",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	do
		local k = config.key("help_close")
		if k then vim.keymap.set("n", k, close_help, { buffer = buf, nowait = true }) end
	end
	do
		local k = config.key("help_close_q")
		if k then vim.keymap.set("n", k, close_help, { buffer = buf, nowait = true }) end
	end
end

function M.close_help()
	close_help()
end

return M
