local M = {}

function M.render(msg)
	return vim.split(msg.text or "", "\n")
end

return M
