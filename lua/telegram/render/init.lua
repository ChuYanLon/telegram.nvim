local emojis = require("telegram.emojis")
local text = require("telegram.render.text")
local link = require("telegram.render.link")
local media = require("telegram.render.media")
local other = require("telegram.render.other")

local M = {}

local function get_renderer(msg)
	local t = msg.type or "messageText"
	if t == "messageText" then
		local txt = msg.text or ""
		if txt:find("https?://") or txt:find("www%.[%w_-]+%.") then
			return link
		end
		return text
	end
	if
		t == "messagePhoto"
		or t == "messageVideo"
		or t == "messageAnimation"
		or t == "messageDocument"
		or t == "messageVoiceNote"
		or t == "messageVideoNote"
		or t == "messageAudio"
		or t == "messageSticker"
	then
		return media
	end
	return other
end

local service_styles = {
	messageBasicGroupChatCreate = { prefix = "[>]", text = "created this group" },
	messageChatJoinByLink = { prefix = "[+]", text = "joined this group via invite link" },
	messageChatJoinByRequest = { prefix = "[+]", text = "joined this group" },
	messageChatDeleteMember = { prefix = "[-]", text = "left the group" },
	messageChatChangeTitle = { prefix = "[~]", text = "changed the group name" },
	messageChatChangePhoto = { prefix = "[~]", text = "changed the group photo" },
	messageChatDeletePhoto = { prefix = "[~]", text = "removed the group photo" },
	messagePinMessage = { prefix = "[*]", text = "pinned a message" },
	messageMessagePinned = { prefix = "[*]", text = "pinned a message" },
	messageForumTopicCreated = { prefix = "[>]", text = "created a topic" },
	messageChatSetMessageAutoDeleteTime = { prefix = "[!]", text = "set auto-delete timer" },
	messageChatUpgradeFrom = { prefix = "[~]", text = "upgraded from a basic group" },
	messageChatUpgradeTo = { prefix = "[~]", text = "upgraded to a supergroup" },
}

function M.render(msg)
	local date_str = os.date("%Y-%m-%d %H:%M", msg.date)
	local sender_name = msg.own and "Me" or (msg.sender and msg.sender.name or "unknown")
	local title_str = ""
	if not msg.own and msg.sender and msg.sender.custom_title and #msg.sender.custom_title > 0 then
		title_str = " [" .. msg.sender.custom_title .. "]"
	end
	local sender = sender_name .. title_str
	local out = {}

	if msg.type == "messageChatAddMembers" then
		local s = msg.sender and msg.sender.name or (msg.own and "You" or "Someone")
		local is_self_join = false
		if msg.memberUserIds and msg.sender and msg.sender.id then
			for _, uid in ipairs(msg.memberUserIds) do
				if uid == msg.sender.id then
					is_self_join = true
					break
				end
			end
		end
		if is_self_join then
			table.insert(out, "[+] " .. s .. " joined this group at " .. date_str)
		else
			local names = msg.addedMemberNames and table.concat(msg.addedMemberNames, ", ") or "someone"
			table.insert(out, "[+] " .. s .. " added " .. names .. " at " .. date_str)
		end
	elseif msg.type and service_styles[msg.type] then
		local style = service_styles[msg.type]
		local s = msg.sender and msg.sender.name or (msg.own and "You" or "Someone")
		table.insert(out, style.prefix .. " " .. s .. " " .. style.text .. " at " .. date_str)
	elseif msg.type and (msg.type:match("^messageChat") or msg.type:match("^messageBasicGroup") or msg.type:match("^messageSupergroup") or msg.type:match("^messageForum")) then
		local s = msg.sender and msg.sender.name or (msg.own and "You" or "Someone")
		table.insert(out, "[~] " .. s .. " performed an action at " .. date_str)
	else
		local header = string.format("## %s (%s)", sender, date_str)
		if msg.views and msg.views > 0 then
			header = header .. string.format(" [%d views]", msg.views)
		end
		table.insert(out, header)

		if msg.replyTo then
			local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or "?"
			local r_text = msg.replyTo.text and msg.replyTo.text:gsub("\n", " ") or ""
			if #r_text > 50 then
				r_text = r_text:sub(1, 50) .. "..."
			end
			table.insert(out, string.format("> %s: %s", r_sender, r_text))
		end

		local content = get_renderer(msg).render(msg)
		for _, l in ipairs(content) do
			table.insert(out, l)
		end
		if msg.reactions and #msg.reactions > 0 then
			local parts = {}
			for _, r in ipairs(msg.reactions) do
				local txt = emojis.get(emojis.get_name(r.emoji or "")) or r.emoji or ""
				local cnt = r.count or 0
				if r.is_chosen then
					txt = txt .. " **" .. cnt .. "**"
				else
					txt = txt .. " " .. cnt
				end
				table.insert(parts, txt)
			end
			table.insert(out, "└─ " .. table.concat(parts, "  "))
		end
	end

	table.insert(out, "")
	return out
end

return M
