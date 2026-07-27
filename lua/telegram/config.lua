local info = debug.getinfo(1, "S")
local plugin_root = vim.fn.fnamemodify(info.source:match("@(.+)"), ":h:h:h")

local M = {}

M.default_keys = {
	translate_zh = "z",
	tool_picker = "@",
	input_editor = "i",
	reply = "<CR>",
	edit = "e",
	delete = "d",
	forward = "f",
	forward_with_reply = "F",
	pin = "p",
	save = "s",
	copy = "yy",
	refresh = "G",
	ban = "B",
	open_dm = "c",
	help = "?",
	editor_submit = "<CR>",
	editor_cancel = "<Esc>",
	help_close = "<Esc>",
	help_close_q = "q",
	goto_last = "<C-o>",
	reaction = "r",
	archive = "a",
	mark_unread = "u",
	message_link = "L",
	user_profile = "U",
	mute = "m",
	perms_down = "j",
	perms_up = "k",
	perms_toggle = "<Tab>",
	perms_up_alt = "<S-Tab>",
	perms_save = "<CR>",
	perms_discard = "<Esc>",
}

M.key_labels = {
	input_editor = "open input editor",
	reply = "reply / jump to original",
	edit = "edit own message",
	delete = "delete / revoke",
	forward = "forward message",
	forward_with_reply = "forward with reply context",
	pin = "pin / unpin message",
	refresh = "refresh + jump to bottom",
	ban = "ban message sender",
	open_dm = "open DM with message sender",
	reaction = "react to message",
	save = "save to Favorites",
	copy = "copy message text",
	archive = "archive/unarchive chat",
	mark_unread = "mark unread / mark as read",
	message_link = "copy message link",
	user_profile = "view user profile",
	mute = "mute / unmute chat",
	goto_last = "switch to previous chat",
	help = "toggle this help",
	translate_zh = "translate message to Chinese",
	tool_picker = "open tool picker",
	help_close = "close this help",
	editor_submit = "submit message in editor",
	editor_cancel = "cancel editing",
	help_close_q = "close this help (alt)",
	perms_down = "permission editor: move down",
	perms_up = "permission editor: move up",
	perms_toggle = "permission editor: toggle item",
	perms_up_alt = "permission editor: move up (alt)",
	perms_save = "permission editor: save",
	perms_discard = "permission editor: discard",
}

M.config = {
	data_dir = plugin_root,
	tdlib_path = nil,
	proxy = nil,
	http_port = 8080,
	ws_port = 8081,
	keys = {},
	notify_chat_types = { "private", "mention" },
	hide_title = false,
	panel_position = "right",
}

local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	return ok and hl and hl.fg
end

local function hl_bg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	return ok and hl and hl.bg
end

---@param name string
---@return string|nil
function M.key(name)
	local k = M.config.keys[name]
	if k == nil or k == false then
		return nil
	end
	return k
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	M.config.keys = vim.tbl_deep_extend("force", vim.deepcopy(M.default_keys), M.config.keys or {})
	local comment_fg = hl_fg("Comment")
	vim.api.nvim_set_hl(0, "TgTimestamp", { fg = comment_fg, italic = false, default = true })
	vim.api.nvim_set_hl(0, "TgPlaceholder", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgReplyTarget", { bg = hl_bg("DiffAdd"), default = true })
	vim.api.nvim_set_hl(0, "TgEditTarget", { bg = hl_bg("DiffChange"), default = true })
	vim.api.nvim_set_hl(0, "TgDeleteTarget", { bg = hl_bg("DiffDelete"), default = true })
	vim.api.nvim_set_hl(0, "TgForwardTarget", { bg = hl_bg("DiffText"), default = true })
	vim.api.nvim_set_hl(0, "TgNoBg", { fg = "NONE", bg = "NONE", default = true })
	vim.api.nvim_set_hl(0, "TgService", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgWinbarHeader", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgWinbarTitle", { bold = true, default = true })
	vim.api.nvim_set_hl(0, "TgDescription", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgTitleKey", { bold = true, default = true })
	vim.api.nvim_set_hl(0, "TgPermOn", { link = "DiagnosticOk", default = true })
	vim.api.nvim_set_hl(0, "TgPermOff", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgPermUnknown", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "TgPermToggle", { fg = hl_fg("DiagnosticInfo"), bold = true, default = true })
	local border_fg = hl_fg("FloatBorder")
	vim.api.nvim_set_hl(0, "TgBorder", { fg = border_fg, bg = "NONE", default = true })
	vim.api.nvim_set_hl(0, "TgDateSeparator", { fg = comment_fg, default = true })
	vim.api.nvim_set_hl(0, "TgEdited", { fg = comment_fg, italic = true, default = true })
	vim.api.nvim_set_hl(0, "TgConnectionOff", { fg = "#f38ba8", bold = true, default = true })
	vim.api.nvim_set_hl(
		0,
		"TgUnreadDivider",
		{ fg = hl_fg("DiagnosticInfo") or "#89b4fa", bold = true, default = true }
	)
end

M.plugin_root = plugin_root

function M.ensure_deps()
	if vim.fn.executable("node") ~= 1 then
		vim.notify("Node.js not found. Install nodejs first.", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	if vim.fn.executable("curl") ~= 1 then
		vim.notify("curl not found.", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	if M.config.tdlib_path then
		vim.notify("tdlib_path: " .. M.config.tdlib_path, vim.log.levels.INFO, { title = "tg" })
	end
	local ws_helper = plugin_root .. "/bin/tg-ws-helper.ts"
	if vim.fn.filereadable(ws_helper) ~= 1 then
		vim.notify("Missing ws helper", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	local server_src = plugin_root .. "/src/server.ts"
	if vim.fn.filereadable(server_src) ~= 1 then
		vim.notify("Missing server source. Run npm install", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	local tsx_bin = plugin_root .. "/node_modules/.bin/tsx"
	if vim.fn.executable("npx") ~= 1 and vim.fn.filereadable(tsx_bin) ~= 1 then
		vim.notify("tsx not found. Run npm install", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	return true
end

return M
