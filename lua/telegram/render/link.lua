local M = {}

local function clean_url(url)
	url = url:gsub("^<+", "")
	url = url:gsub("[%]%)>%.%,%;%!%?:;'\"]+$", "")
	return url
end

function M.render(msg)
	local text = msg.text or ""
	text = text:gsub("<(https?://.-)>", function(url)
		return url
	end)
	text = text:gsub("(https?://[^%s\"']+)", function(url)
		return "<" .. clean_url(url) .. ">"
	end)
	text = text:gsub("(%s)(www%.[%w_-]+%.[^%s\"']+)", function(sp, url)
		return sp .. "<" .. clean_url(url) .. ">"
	end)
	text = text:gsub("^(www%.[%w_-]+%.[^%s\"']+)", function(url)
		return "<" .. clean_url(url) .. ">"
	end)
	return vim.split(text, "\n")
end

return M
