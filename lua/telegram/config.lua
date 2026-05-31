local info = debug.getinfo(1, "S")
local plugin_root = vim.fn.fnamemodify(info.source:match("@(.+)"), ":h:h:h")

local M = {}

M.config = {
	data_dir = plugin_root,
	tdlib_path = nil,
	proxy = nil,
	http_port = 8080,
	ws_port = 8081,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	local ok, comment_hl = pcall(vim.api.nvim_get_hl, 0, { name = "Comment" })
	if ok and comment_hl then
		vim.api.nvim_set_hl(0, "TgTimestamp", { fg = comment_hl.fg, italic = false, default = true })
	else
		vim.api.nvim_set_hl(0, "TgTimestamp", { link = "Comment", default = true })
	end
	vim.api.nvim_set_hl(0, "TgPlaceholder", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgReplyTarget", { bg = "#2d4a3e", default = true })
	vim.api.nvim_set_hl(0, "TgEditTarget", { bg = "#4a3e2d", default = true })
	vim.api.nvim_set_hl(0, "TgDeleteTarget", { bg = "#4e2d2d", default = true })
	vim.api.nvim_set_hl(0, "TgForwardTarget", { bg = "#3d2d4e", default = true })
	vim.api.nvim_set_hl(0, "TgNoBg", { fg = "NONE", bg = "NONE", default = true })
	vim.api.nvim_set_hl(0, "TgService", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgWinbarHeader", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "TgWinbarTitle", { bold = true, default = true })
	vim.api.nvim_set_hl(0, "TgDescription", { link = "Comment", default = true })
	local bfg = "#6c6c6c"
	pcall(function()
		bfg = (vim.api.nvim_get_hl(0, { id = vim.api.nvim_get_hl_id_by_name("FloatBorder") }) or {}).fg or bfg
	end)
	vim.api.nvim_set_hl(0, "TgBorder", { fg = bfg, bg = "NONE", default = true })
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
