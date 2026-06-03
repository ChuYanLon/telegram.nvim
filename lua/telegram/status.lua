return {
	function()
		local ok, m = pcall(require, "telegram")
		if not ok then return "" end
		local s = m.status and m.status() or ""
		if s == "disconnected" then return "" end
		return "  "
	end,
	cond = function() local ok = pcall(require, "telegram"); return ok end,
	color = function()
		local ok, m = pcall(require, "telegram")
		if not ok or not m.status then return end
		local c = { disconnected = "#6c7086", connecting = "#f9e2af", connected = "#a6e3a1", error = "#f38ba8" }
		return { fg = c[m.status()] or c.disconnected }
	end,
}
