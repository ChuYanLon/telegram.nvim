local M = {}

local labels = {
	messagePhoto = "Photo",
	messageVideo = "Video",
	messageAnimation = "Animation",
	messageDocument = "Document",
	messageVoiceNote = "Voice",
	messageVideoNote = "Video Note",
	messageAudio = "Audio",
	messageSticker = "Sticker",

}

function M.render(msg)
	local label = labels[msg.type] or msg.type or "Unknown"
	local text = msg.text or ""
	local file_path = msg.filePath

	local parts = {}
	if file_path and #file_path > 0 then
		table.insert(parts, "![" .. label .. "](" .. file_path .. ")")
	else
		table.insert(parts, "[" .. label .. "]")
	end
	if text and #text > 0 then
		for _, line in ipairs(vim.split(text, "\n")) do
			table.insert(parts, line)
		end
	end
	return parts
end

return M
