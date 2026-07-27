local M = {}

local type_labels = {
	messagePoll = "[Poll]",
	messageContact = "[Contact]",
	messageLocation = "[Location]",
	messageDice = "[Dice]",
	messageGame = "[Game]",
	messageCall = "[Call]",
	messageAnimatedEmoji = "",
	messageInvoice = "[Invoice]",
	messageGiveaway = "[Giveaway]",
	messagePremiumGiveaway = "[Premium Giveaway]",
	messageForumTopicCreated = "[Topic Created]",
	messageExpiredPhoto = "[Expired Photo]",
	messageExpiredVideo = "[Expired Video]",
}

---@param msg { pollInfo?: { question: string, options: { id: string, text: string, voterCount: number, votePercentage: number, isChosen: boolean }[], totalVoterCount: number, isAnonymous: boolean, allowsMultipleAnswers: boolean, isClosed: boolean }, text?: string }
---@return string[]
local function render_poll(msg)
	local poll = msg.pollInfo
	if not poll or not poll.options then
		local text = msg.text or ""
		if #text > 0 then
			return vim.split(text, "\n")
		end
		return { "[Poll]" }
	end

	local lines = {}

	-- Question
	local q_icon = poll.isClosed and "🔒" or "📊"
	table.insert(lines, "  " .. q_icon .. "  " .. poll.question)

	-- Separator
	local sep_width = 32
	if poll.allowsMultipleAnswers then
		table.insert(lines, "  " .. string.rep("─", sep_width) .. "  (multi)")
	else
		table.insert(lines, "  " .. string.rep("─", sep_width))
	end

	-- Options with progress bars
	for i, opt in ipairs(poll.options) do
		local chosen = opt.isChosen and "✓ " or "  "
		local opt_text = opt.text
		-- Truncate long option text
		local max_text = 26
		if #opt_text > max_text then
			opt_text = opt_text:sub(1, max_text - 1) .. "…"
		end

		-- Progress bar: 16 chars wide
		local bar_chars = 16
		local filled = math.floor(opt.votePercentage / 100 * bar_chars + 0.5)
		local bar = string.rep("█", filled) .. string.rep("░", math.max(0, bar_chars - filled))
		local pct = string.format("%3d%%", opt.votePercentage)
		local votes = "(" .. opt.voterCount .. ")"

		local line = chosen .. string.format("%-2d", i) .. ") " .. opt_text
		-- Pad to align bar
		local text_w = vim.fn.strdisplaywidth(opt_text)
		local pad = math.max(0, max_text - text_w)
		line = line .. string.rep(" ", pad + 1) .. bar .. " " .. pct .. "  " .. votes
		table.insert(lines, line)
	end

	-- Footer
	table.insert(lines, "  " .. string.rep("─", sep_width))
	local footer = {}
	table.insert(footer, poll.isAnonymous and "Anonymous" or "Public")
	table.insert(footer, poll.totalVoterCount .. " vote" .. (poll.totalVoterCount ~= 1 and "s" or ""))
	if poll.isClosed then
		table.insert(footer, "Closed")
	end
	table.insert(lines, "  " .. table.concat(footer, " · "))

	return lines
end

function M.render(msg)
	-- Poll messages with pollInfo get the rich renderer
	if msg.type == "messagePoll" and msg.pollInfo then
		return render_poll(msg)
	end

	local text = msg.text or ""
	if text and #text > 0 then
		return vim.split(text, "\n")
	end
	local label = type_labels[msg.type] or "[" .. (msg.type or "Unknown") .. "]"
	return { label }
end

return M
