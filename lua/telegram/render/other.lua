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

function M.render(msg)
	local label = type_labels[msg.type] or "[" .. (msg.type or "Unknown") .. "]"
	local text = msg.text or ""
	if text and #text > 0 then
		local parts = vim.split(text, "\n")
		parts[1] = label .. " " .. parts[1]
		return parts
	end
	return { label }
end

return M
