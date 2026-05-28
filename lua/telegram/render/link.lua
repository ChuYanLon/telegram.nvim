local M = {}

function M.render(msg)
	local text = msg.text or ""
	text = text:gsub("(https?://[%w_%.%/%?&=#~%+%-]+)", function(url)
		return "<" .. url .. ">"
	end)
	text = text:gsub("(www%.[%w_-]+%.[%w%./%?&=#~%%]+)", function(url)
		return "<" .. url .. ">"
	end)
	return vim.split(text, "\n")
end

return M
