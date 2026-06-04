return {
	function()
		local ok, ui = pcall(require, "telegram.ui")
		if not ok then return "" end
		local total, mentions = 0, 0
		for _, g in pairs(ui.state and ui.state.groups or {}) do
			total = total + (g.unread_count or 0)
			mentions = mentions + (g.mention_count or 0)
		end
		if mentions > 0 then return "  " .. total .. "!" end
		if total > 0 then return "  " .. total end
		return "  "
	end,
	cond = function() local ok = pcall(require, "telegram.ui"); return ok end,
	color = function()
		local ok, ui = pcall(require, "telegram.ui")
		if not ok then return end
		local mentions = 0
		for _, g in pairs(ui.state and ui.state.groups or {}) do
			mentions = mentions + (g.mention_count or 0)
		end
		if mentions > 0 then return { fg = "#f38ba8" } end
		local ok2, m = pcall(require, "telegram")
		if not ok2 or not m.status then return end
		local c = { disconnected = "#6c7086", connecting = "#f9e2af", connected = "#a6e3a1", error = "#f38ba8" }
		return { fg = c[m.status()] or c.disconnected }
	end,
}
