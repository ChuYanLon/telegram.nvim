--- Apply markdown entity highlights to buffer lines.
--- The text from format.ts already contains markdown markers
--- (**bold**, *italic*, `code`, ~~strikethrough~~, ||spoiler||, [text](url)).
--- This module scans each content line and applies Neovim highlights
--- to the matching ranges.

local M = {}

-- Entity type → highlight group mapping
-- Ordered by priority: more specific markers matched first
local entity_patterns = {
	-- bold: **text** (needs to be matched before *italic*)
	{ pattern = "([%*]{2})([^%*]+)([%*]{2})", hl_group = "TgBold" },
	-- strikethrough: ~~text~~
	{ pattern = "([~]{2})([^~]+)([~]{2})", hl_group = "TgStrikethrough" },
	-- spoiler: ||text||
	{ pattern = "([|]{2})([^|]+)([|]{2})", hl_group = "TgSpoiler" },
	-- italic: *text* (single asterisk)
	{ pattern = "([%*])([^%*]+)([%*])", hl_group = "TgItalic" },
	-- link text: [label](url)
	{ pattern = "(%[)([^%[%]]+)(%]%([^%)]+%))", hl_group = "TgLinkText" },
	-- inline code: `text` or ``text`` (double backtick first)
	{ pattern = "(`{2,})(.-)(%1)", hl_group = "TgCode" },
	{ pattern = "(`)([^`]+)(`)", hl_group = "TgCode" },
}

--- Apply highlights for all markdown pattern matches in a line.
--- Non-overlapping matches selected via earliest-starting greedy strategy.
---@param buf number buffer handle
---@param ns number highlight namespace
---@param line_idx integer 0-based buffer line index
---@param text string the line content
function M.apply_line_highlights(buf, ns, line_idx, text)
	if not text or #text == 0 then
		return
	end

	-- Collect all matches with positions
	local matches = {}
	for _, ent in ipairs(entity_patterns) do
		local pat = ent.pattern
		local hl = ent.hl_group
		local pos = 1
		while pos <= #text do
			local s, e = text:find(pat, pos)
			if not s then
				break
			end
			table.insert(matches, { s = s, e = e, hl = hl })
			pos = e + 1
		end
	end

	if #matches == 0 then
		return
	end

	-- Sort by start position
	table.sort(matches, function(a, b) return a.s < b.s end)

	-- Greedy non-overlapping selection:
	-- pick the earliest-starting match, then skip past its end
	local selected = {}
	local i = 1
	while i <= #matches do
		local best = matches[i]
		-- Among matches that overlap with this one, keep the longest
		local j = i + 1
		while j <= #matches and matches[j].s <= best.e do
			if matches[j].e > best.e then
				best = matches[j]
			end
			j = j + 1
		end
		table.insert(selected, best)
		-- Skip all matches overlapping with the selected one
		while i <= #matches and matches[i].s <= best.e do
			i = i + 1
		end
	end

	-- Apply highlights
	for _, m in ipairs(selected) do
		-- text:find returns 1-indexed positions; nvim_buf_add_highlight
		-- uses 0-indexed columns with exclusive end.
		-- col_start = s - 1, col_end = e (since 1-indexed e = 0-indexed exclusive end)
		pcall(vim.api.nvim_buf_add_highlight, buf, ns, m.hl, line_idx, m.s - 1, m.e)
	end
end

--- Check if a line is a content line (eligible for entity highlighting).
--- Lines like headers, service messages, date separators, etc. are skipped.
---@param line string
---@return boolean
function M.is_content_line(line)
	if not line or #line == 0 then
		return false
	end
	-- Service messages: [+], [-], [~], [*], [>], [!]
	if line:find("^%[%+%-%~%*%>!%]") then
		return false
	end
	-- Headers: ## Sender (date)
	if line:find("^## ") then
		return false
	end
	-- Reply chain: > sender: text
	if line:find("^> ") then
		return false
	end
	-- Forward info:   ↳ name
	if line:find("^  ↳ ") then
		return false
	end
	-- Link preview: ↗ url or   siteName/title/description
	if line:find("^↗ ") or line:find("^  %S") then
		return false
	end
	-- Date separator:   ── Today ──
	if line:find("^  ── ") then
		return false
	end
	-- Unread divider: ── N unread messages ──
	if line:find("^── ") then
		return false
	end
	-- Footer: └─ edited views reactions
	if line:find("^└─ ") then
		return false
	end
	-- Poll lines: "  📊  Question" or "  option text ████░ 100%"
	if line:find("^  [📊🔒]") then
		return false
	end
	-- Deleted message lines
	if line:find("^%[%-%]") then
		return false
	end
	return true
end

return M
