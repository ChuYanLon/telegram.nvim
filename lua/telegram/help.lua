local config = require("telegram.config")

local M = {}

local help_win = nil

local function close_help()
	if help_win then
		pcall(vim.api.nvim_win_close, help_win, true)
		help_win = nil
	end
end

-- Look up label from config.key_labels; if the key is disabled, skip it
local function key_line(key_name)
	local k = config.key(key_name)
	if not k then return nil end
	local label = config.key_labels[key_name]
	if not label then return nil end
	local padding = math.max(1, 11 - (1 + #k))
	return " " .. k .. string.rep(" ", padding) .. label
end

function M.show_help()
	close_help()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local lines = {}

	table.insert(lines, "-- Messages --")
	local msg_keys = { "input_editor", "reply", "edit", "delete", "forward", "pin", "refresh", "ban", "open_dm", "reaction", "save", "copy", "archive" }
	for _, name in ipairs(msg_keys) do
		local l = key_line(name)
		if l then table.insert(lines, l) end
	end

	table.insert(lines, "")
	local tool_key = config.key("tool_picker") or "@"
	table.insert(lines, "-- Tools (" .. tool_key .. ") --")
	local tools = require("telegram.tools")
	for _, name in ipairs(tools.list()) do
		local tool = tools[name]
		if tool and tool.description then
			local padding = math.max(1, 12 - (1 + #name))
			table.insert(lines, " " .. name .. string.rep(" ", padding) .. tool.description)
		end
	end

	table.insert(lines, "")
	table.insert(lines, "-- Chat Picker --")
	table.insert(lines, " built-in fuzzy search via Snacks picker")
	table.insert(lines, " <CR> / <Esc>  select / cancel")

	table.insert(lines, "")
	table.insert(lines, "-- General --")
	for _, name in ipairs({ "help", "tool_picker", "help_close" }) do
		local l = key_line(name)
		if l then table.insert(lines, l) end
	end
	table.insert(lines, " :Tg        close chat / quit")

	local height = #lines + 2
	local width = 42
	for _, l in ipairs(lines) do
		local w = vim.fn.strdisplaywidth(l)
		if w + 4 > width then width = w + 4 end
	end

	help_win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = math.min(width, 60),
		height = math.min(height, 30),
		row = math.max(0, (vim.o.lines - height) / 2),
		col = math.max(0, (vim.o.columns - math.min(width, 60)) / 2),
		zindex = 200,
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})
	vim.wo[help_win].winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder"
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
