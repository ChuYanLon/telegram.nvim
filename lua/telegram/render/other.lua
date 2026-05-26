local M = {}

local type_labels = {
	messageSticker = "[Sticker]",
	messageVoiceNote = "[Voice]",
	messageVideoNote = "[Video Note]",
	messageAudio = "[Audio]",
	messagePoll = "[Poll]",
	messageContact = "[Contact]",
	messageLocation = "[Location]",
	messageDice = "[Dice]",
	messageGame = "[Game]",
	messageCall = "[Call]",
	messageBasicGroupChatCreate = "[Basic Group Created]",
	messageChatAddMembers = "[Members Added]",
	messageChatJoinByLink = "[Joined by Link]",
	messageChatJoinByRequest = "[Join Request]",
	messageChatDeleteMember = "[Member Removed]",
	messageChatChangeTitle = "[Group Renamed]",
	messageChatChangePhoto = "[Photo Changed]",
	messageChatDeletePhoto = "[Photo Removed]",
	messageChatSetMessageAutoDeleteTime = "[Auto-delete Set]",
	messagePinMessage = "[Message Pinned]",
	messageForumTopicCreated = "[Topic Created]",
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
