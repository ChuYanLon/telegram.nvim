local emojis = require("telegram.emojis")
local text = require("telegram.render.text")
local link = require("telegram.render.link")
local media = require("telegram.render.media")
local other = require("telegram.render.other")

local M = {}

local function fmt_count(n)
	if n >= 1000000 then
		return ("%.1fM"):format(n / 1000000)
	elseif n >= 1000 then
		return ("%.1fk"):format(n / 1000)
	end
	return tostring(n)
end

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
	if msg.deleted then
		local s = msg.own and "You" or (msg.sender and msg.sender.name or "Unknown")
		local date_str = os.date("%Y-%m-%d %H:%M", msg.date)
		return { string.format("[-] %s: [Message deleted] at %s", s, date_str), "" }
	end
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
	elseif msg.type and (msg.type:match("^messageChat") or msg.type:match("^messageBasicGroup") or msg.type:match("^messageSupergroup") or msg.type:match("^messageForum")) and not (msg.text and #msg.text > 0) then
		local s = msg.sender and msg.sender.name or (msg.own and "You" or "Someone")
		table.insert(out, "[~] " .. s .. " performed an action at " .. date_str)
	else
		local header = string.format("## %s (%s", sender, date_str)
		if msg.own and msg.readDate and msg.readDate > 0 then
			local read_str = os.date("%H:%M", msg.readDate)
			header = header .. string.format(", read %s", read_str)
		end
		header = header .. ")"
		table.insert(out, header)

		if msg.replyTo then
			local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or "?"
			local r_text = msg.replyTo.text and msg.replyTo.text:gsub("\n", " ") or ""
			if #r_text > 50 then
				r_text = r_text:sub(1, 50) .. "..."
			end
			table.insert(out, string.format("> %s: %s", r_sender, r_text))
		end

		local function trunc(s, n)
			n = n or 50
			if vim.fn.strdisplaywidth(s) <= n then return s end
			local r = ""
			for c in s:gmatch(".[\128-\191]*") do
				if vim.fn.strdisplaywidth(r .. c) > n - 1 then
					return r .. "…"
				end
				r = r .. c
			end
			return r
		end
		if msg.forwardInfo and msg.forwardInfo.name then
			table.insert(out, "  ↳ " .. msg.forwardInfo.name)
		end
		local content = get_renderer(msg).render(msg)
		if msg.linkPreview and msg.linkPreview.url then
			table.insert(out, "↗ " .. msg.linkPreview.url)
			local has_info = false
			if msg.linkPreview.siteName and #msg.linkPreview.siteName > 0 then
				table.insert(out, "  " .. msg.linkPreview.siteName)
				has_info = true
			end
			if msg.linkPreview.title and #msg.linkPreview.title > 0 then
				table.insert(out, "  " .. msg.linkPreview.title)
				has_info = true
			end
			if msg.linkPreview.description and #msg.linkPreview.description > 0 then
				table.insert(out, "  " .. msg.linkPreview.description)
				has_info = true
			end
			if not has_info then
				for _, l in ipairs(content) do
					table.insert(out, l)
				end
			end
		else
			for _, l in ipairs(content) do
				table.insert(out, l)
			end
		end
		local footer_parts = {}
		if msg.editDate and msg.editDate > 0 then
			table.insert(footer_parts, "[edited]")
		end
		if msg.views and msg.views > 0 then
			table.insert(footer_parts, "👀 " .. fmt_count(msg.views))
		end
		if msg.reactions and #msg.reactions > 0 then
			for _, r in ipairs(msg.reactions) do
				local txt = emojis.get(emojis.get_name(r.emoji or "")) or r.emoji or ""
				local cnt = r.count or 0
				if r.is_chosen then
					txt = txt .. " **" .. cnt .. "**"
				else
					txt = txt .. " " .. cnt
				end
				table.insert(footer_parts, txt)
			end
		end
		if #footer_parts > 0 then
			table.insert(out, "└─ " .. table.concat(footer_parts, "  "))
		end
	end

	table.insert(out, "")
	return out
end

return M
