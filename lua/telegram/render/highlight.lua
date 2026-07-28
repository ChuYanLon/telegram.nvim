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
--- Handles overlapping matches by taking the earliest-starting match
--- and skipping overlapping regions.
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
			local s, e, open, _, close = text:find(pat, pos)
			if not s then
				break
			end
			table.insert(matches, {
				start = s,
				end_pos = e,
				hl = hl,
				-- Highlight the full match range (including markers)
				inner_start = s + #open - 1,
				inner_end = e - #close + 1,
				marker_start = s,
				marker_end = e,
			})
			pos = e + 1
		end
	end

	if #matches == 0 then
		return
	end

	-- Sort by start position, then by length (longest first for tiebreakers)
	table.sort(matches, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end
		return a.end_pos > b.end_pos
	end)

	-- Resolve overlaps: greedily take earliest-starting match
	local selected = {}
	table.sort(matches, function(a, b)
		return a.start < b.start
	end)

	local i = 1
	while i <= #matches do
		local best = matches[i]
		local j = i + 1
		while j <= #matches and matches[j].start <= best.end_pos do
			-- Same-start: prefer longer match
			if matches[j].end_pos > best.end_pos then
				best = matches[j]
			end
			j = j + 1
		end
		table.insert(selected, best)
		-- Move cursor past this match
		i = j
		-- Skip any matches that overlap with this one
		while i <= #matches and matches[i].start < best.end_pos + 1 do
			i = i + 1
		end
	end

	-- Apply highlights
	for _, m in ipairs(selected) do
		pcall(vim.api.nvim_buf_add_highlight, buf, ns, m.hl, line_idx, m.marker_start - 1, m.marker_end)
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
