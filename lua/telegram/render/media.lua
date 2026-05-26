local M = {}

local labels = {
	messagePhoto = "📷 Photo",
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
	if text and #text > 0 then
		local parts = vim.split(text, "\n")
		parts[1] = label .. " " .. parts[1]
		return parts
	end
	return { label }
end

return M
