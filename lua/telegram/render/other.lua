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
	table.insert(lines, "  " .. string.rep("─", 36)
		.. (poll.allowsMultipleAnswers and "  (multi)" or ""))

	-- Find longest option text (display width) for alignment
	local max_text_w = 0
	for _, opt in ipairs(poll.options) do
		local w = vim.fn.strdisplaywidth(opt.text)
		if w > max_text_w then max_text_w = w end
	end
	local name_col_w = math.min(max_text_w, 24)

	-- Options with progress bars
	for _, opt in ipairs(poll.options) do
		local opt_text = opt.text
		local opt_w = vim.fn.strdisplaywidth(opt_text)
		-- Truncate if too long
		if opt_w > name_col_w then
			local s = ""
			for c in opt_text:gmatch(".[\128-\191]*") do
				if vim.fn.strdisplaywidth(s .. c) > name_col_w - 1 then
					s = s .. "…"
					break
				end
				s = s .. c
			end
			opt_text = s
			opt_w = name_col_w + 1  -- includes ellipsis
		end

		-- Progress bar: 10 chars wide
		local filled = math.floor(opt.votePercentage / 100 * 10 + 0.5)
		local bar = string.rep("█", filled) .. string.rep("░", 10 - filled)
		local pct = string.format("%3d%%", opt.votePercentage)
		local votes = string.format("%4d", opt.voterCount)
		local check = opt.isChosen and " ✓" or ""

		local line = "  " .. opt_text .. string.rep(" ", name_col_w - opt_w + 1)
			.. bar .. " " .. pct .. " " .. votes .. check
		table.insert(lines, line)
	end

	-- Footer
	local footer = {}
	table.insert(footer, poll.isAnonymous and "Anonymous" or "Public")
	table.insert(footer, poll.totalVoterCount .. " vote" .. (poll.totalVoterCount ~= 1 and "s" or ""))
	if poll.isClosed then
		table.insert(footer, "Closed")
	end
	table.insert(lines, "  " .. string.rep("─", 36))
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
