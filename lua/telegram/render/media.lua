local M = {}

local labels = {
	messagePhoto = "🖼 Photo",
	messageVideo = "🎥 Video",
	messageAnimation = "🎬 Animation",
	messageDocument = "📄 Document",
	messageVoiceNote = "🎤 Voice",
	messageVideoNote = "🎞 Video Note",
	messageAudio = "🎵 Audio",
}

function M.render(msg)
	local label = labels[msg.type] or ("[" .. (msg.type or "Unknown") .. "]")
	local text = msg.text or ""
	local file_path = msg.filePath

	local parts = {}
	if file_path and #file_path > 0 then
		local caption = (text and #text > 0) and text:gsub("\n", " "):sub(1, 40) or label
		table.insert(parts, "![" .. caption .. "](" .. file_path .. ")")
		if text and #text > 0 then
			for _, line in ipairs(vim.split(text, "\n")) do
				table.insert(parts, line)
			end
		end
	else
		table.insert(parts, label)
		if text and #text > 0 then
			for _, line in ipairs(vim.split(text, "\n")) do
				table.insert(parts, line)
			end
		end
	end
	return parts
end

return M
