local info = debug.getinfo(1, "S")
local plugin_root = vim.fn.fnamemodify(info.source:match("@(.+)"), ":h:h:h")

local M = {}

M.default_keys = {
	tool_picker = "@",
	input_editor = "i",
	reply = "<CR>",
	edit = "e",
	delete = "d",
	forward = "f",
	pin = "p",
	refresh = "G",
	ban = "B",
	open_dm = "c",
	help = "?",
	editor_submit = "<CR>",
	editor_cancel = "<Esc>",
	help_close = "<Esc>",
	help_close_q = "q",
	reaction = "r",
	perms_down = "j",
	perms_up = "k",
	perms_toggle = "<Tab>",
	perms_up_alt = "<S-Tab>",
	perms_save = "<CR>",
	perms_discard = "<Esc>",
}

M.config = {
	data_dir = plugin_root,
	tdlib_path = nil,
	proxy = nil,
	http_port = 8080,
	ws_port = 8081,
	keys = {},
	notify_chat_types = { "private", "mention" },
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
	if k == nil or k == false then return nil end
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
