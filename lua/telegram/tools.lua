local server = require("telegram.server")
local ui = require("telegram.ui")
local st = require("telegram.state")

local M = {}
local tool_list = {}

function M.register(name, opts)
	M[name] = opts
	table.insert(tool_list, name)
end

function M.run(name, ...)
	local tool = M[name]
	if tool then
		tool.callback(...)
	end
end

function M.list()
	return tool_list
end

function M.pick()
	local items = {}
	for _, name in ipairs(tool_list) do
		local tool = M[name]
		if not tool.condition or tool.condition() then
			table.insert(items, { name = name, label = "@" .. name .. "  " .. tool.description })
		end
	end
	if #items == 0 then
		vim.notify("No tools available for this context", vim.log.levels.INFO, { title = "tg" })
		return
	end
	vim.ui.select(items, {
		prompt = "@ Tools",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if choice then
			M.run(choice.name)
		end
	end)
end

M.register("chats", {
	description = "Switch to another chat",
	callback = function()
		ui.show_groups_picker(function(item)
			if item then require("telegram").open_chat(item.id, item.title) end
		end)
	end,
})

M.register("newchat", {
	description = "Start a new private chat by @username",
	callback = function()
		vim.ui.input({ prompt = "Enter @username: " }, function(username)
			if not username or #username == 0 then
				return
			end
			vim.notify("Searching for @" .. username .. "...", vim.log.levels.INFO, { title = "tg" })
			local chat = require("telegram.server").search_user(username)
			if chat then
				require("telegram").open_chat(chat.id, chat.title, chat.type)
			else
				vim.notify("User not found", vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end,
})

M.register("refresh", {
	description = "Refresh messages",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		ui.refresh_messages()
		vim.notify("Refreshed", vim.log.levels.INFO, { title = "tg" })
	end,
})

M.register("send", {
	description = "Send a message to current chat",
	condition = function()
		return ui.state.chat_id ~= nil and ui.state.permissions.can_send_messages == true
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		ui.open_editor("Send", "", function(text)
			if not text then
				return
			end
			local msg = server.send_message(ui.state.chat_id, text)
			if msg then
				table.insert(ui.state.messages, msg)
				ui.render()
			end
		end, "[Send]")
	end,
})

M.register("search", {
	description = "Search message history",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		vim.ui.input({ prompt = "Search: " }, function(query)
			if not query or #query == 0 then
				return
			end
			vim.notify("Searching...", vim.log.levels.INFO, { title = "tg" })
			server.search_messages_async(chat_id, query, function(data)
				if not data or not data.messages or #data.messages == 0 then
					vim.notify('No results for "' .. query .. '"', vim.log.levels.INFO, { title = "tg" })
					return
				end
				local items = {}
				for _, m in ipairs(data.messages) do
					local name = m.sender and m.sender.name or "?"
					local preview = (m.text or ""):gsub("\n", " "):sub(1, 80)
					table.insert(items, { id = m.id, label = name .. ": " .. preview })
				end
				vim.ui.select(items, {
					prompt = "Search: " .. query,
					format_item = function(item)
						return item.label
					end,
				}, function(choice)
					if choice then
						ui.jump_to_message(choice.id)
					end
				end)
			end, function()
				vim.notify("Search failed", vim.log.levels.ERROR, { title = "tg" })
			end)
		end)
	end,
})

local function is_service()
	local t = ui.curr_msg()
	if not t or not t.type then return false end
	return t.type:find("Chat") or t.type:find("Group") or t.type:find("Service")
		or t.type:find("Forum") or t.type:find("^messagePin")
		or t.type == "messageScreenshotTaken" or t.type == "messageCustomServiceAction"
end

local function open_target(target)
	if vim.fn.has("mac") == 1 then
		vim.fn.jobstart({ "open", "--", target })
	else
		vim.fn.jobstart({ "xdg-open", target })
	end
end

M.register("reaction", {
	description = "React to message",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		ui.show_reaction_picker()
	end,
})

M.register("openlink", {
	description = "Open URL or media file under cursor",
	condition = function()
		if is_service() then return false end
		if not ui.state.win or not vim.api.nvim_win_is_valid(ui.state.win) then return false end
		if not ui.state.buf or not vim.api.nvim_buf_is_valid(ui.state.buf) then return false end
		local cursor = vim.api.nvim_win_get_cursor(ui.state.win)
		local text = vim.api.nvim_buf_get_lines(ui.state.buf, cursor[1] - 1, cursor[1], false)[1]
		if not text then return false end
		local url = text:match("https?://[^%s<>\"']+")
		if url then
			url = url:gsub("[%]%)>%.%,%;%!%?:;'\"]+$", "")
		end
		return url or text:match("!%[%w+%]%((.-)%)")
	end,
	callback = function()
		if not ui.state.win or not vim.api.nvim_win_is_valid(ui.state.win) then return end
		if not ui.state.buf or not vim.api.nvim_buf_is_valid(ui.state.buf) then return end
		local cursor = vim.api.nvim_win_get_cursor(ui.state.win)
		local text = vim.api.nvim_buf_get_lines(ui.state.buf, cursor[1] - 1, cursor[1], false)[1]
		if not text then return end
		local url = text:match("https?://[^%s<>\"']+")
		if url then
			url = url:gsub("[%]%)>%.%,%;%!%?:;'\"]+$", "")
		end
		if url then
			vim.notify("Opening: " .. url, vim.log.levels.INFO, { title = "tg" })
			open_target(url)
			return
		end
		-- For media messages, prefer mediaPath (original file) over filePath (thumbnail)
		local media = ui.curr_msg()
		if media and media.mediaPath and #media.mediaPath > 0 then
			vim.notify("Opening: " .. media.mediaPath, vim.log.levels.INFO, { title = "tg" })
			open_target(media.mediaPath)
			return
		end
		local filepath = text:match("!%[%w+%]%((.-)%)")
		if filepath and #filepath > 0 then
			vim.notify("Opening: " .. filepath, vim.log.levels.INFO, { title = "tg" })
			open_target(filepath)
		end
	end,
})

local function is_group()
	local cid = ui.state.chat_id
	if not cid then return false end
	local g = ui.state.groups[cid]
	return g and g.type == "group"
end

local function is_channel()
	local cid = ui.state.chat_id
	if not cid then return false end
	local g = ui.state.groups[cid]
	return g and g.type == "channel"
end

M.register("members", {
	description = "View and manage chat members",
	condition = function()
		if is_channel() then
			return ui.state.permissions.can_manage_chat == true
		end
		return is_group()
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		ui.show_member_list(ui.state.chat_id)
	end,
})

M.register("invitelinks", {
	description = "Manage invite links",
	condition = function()
		return is_group() and not is_channel() and (ui.state.permissions.can_invite_users == true)
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		ui.show_invite_links(ui.state.chat_id)
	end,
})

M.register("groupsettings", {
	description = "Group / channel settings (title, description, permissions, etc.)",
	condition = function() return is_group() or is_channel() end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		ui.show_group_settings(ui.state.chat_id)
	end,
})

M.register("toggleheader", {
	description = "Toggle floating title bar visibility",
	callback = function()
		st.state.hide_title = not st.state.hide_title
		if st.state.hide_title then
			local title = require("telegram.render.title")
			title.update_title()
		end
		ui.render()
		vim.notify("Title bar " .. (st.state.hide_title and "hidden" or "shown"), vim.log.levels.INFO, { title = "tg" })
	end,
})

M.register("archive", {
	description = "Archive/unarchive current chat",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		local chat_title = ui.state.chat_title
		local is_archived = ui.state.current_chat_archived
		local action = is_archived and "Unarchive" or "Archive"
		vim.ui.select({ action, "Cancel" }, {
			prompt = action .. " " .. (chat_title or "chat") .. "?",
		}, function(choice)
			if choice ~= action then return end
			if is_archived then
				if server.unarchive_chat(chat_id) then
					vim.notify("Unarchived: " .. (chat_title or ""), vim.log.levels.INFO, { title = "tg" })
					ui.state.current_chat_archived = false
					require("telegram.render.title").update_title()
				end
			else
				if server.archive_chat(chat_id) then
					vim.notify("Archived: " .. (chat_title or ""), vim.log.levels.INFO, { title = "tg" })
					if ui.state.groups[chat_id] then
						ui.state.groups[chat_id] = nil
						for i, id in ipairs(ui.state.group_ids) do
							if id == chat_id then
								table.remove(ui.state.group_ids, i)
								break
							end
						end
					end
					ui.destroy_chat()
				else
					vim.notify("Failed to archive chat", vim.log.levels.WARN, { title = "tg" })
				end
			end
		end)
	end,
})


M.register("markunread", {
	description = "Mark current chat as unread / read",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		local is_unread = ui.state.groups[chat_id] and ui.state.groups[chat_id].is_marked_unread
		if server.mark_chat_unread(chat_id, not is_unread) then
			ui.state.groups[chat_id] = ui.state.groups[chat_id] or {}
			ui.state.groups[chat_id].is_marked_unread = not is_unread
			vim.notify((is_unread and "Marked as read" or "Marked as unread"), vim.log.levels.INFO, { title = "tg" })
			vim.cmd("redrawstatus")
		end
	end,
})

M.register("mute", {
	description = "Mute / unmute current chat",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		local is_muted = ui.state.groups[chat_id] and ui.state.groups[chat_id].is_muted
		if is_muted then
			if server.unmute_chat(chat_id) then
				ui.state.groups[chat_id] = ui.state.groups[chat_id] or {}
				ui.state.groups[chat_id].is_muted = false
				vim.notify("Unmuted chat", vim.log.levels.INFO, { title = "tg" })
			end
		else
			if server.mute_chat(chat_id) then
				ui.state.groups[chat_id] = ui.state.groups[chat_id] or {}
				ui.state.groups[chat_id].is_muted = true
				vim.notify("Muted chat (forever)", vim.log.levels.INFO, { title = "tg" })
			end
		end
	end,
})

M.register("mentions", {
	description = "Search @mentions in current chat",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		vim.notify("Searching mentions...", vim.log.levels.INFO, { title = "tg" })
		server.search_messages_filtered_async(chat_id, "", "searchMessagesFilterMention", function(data)
			if not data or not data.messages or #data.messages == 0 then
				vim.notify("No mentions found", vim.log.levels.INFO, { title = "tg" })
				return
			end
			local items = {}
			for _, m in ipairs(data.messages) do
				local name = m.sender and m.sender.name or "?"
				local preview = (m.text or ""):gsub("\n", " "):sub(1, 80)
				table.insert(items, { id = m.id, label = name .. ": " .. preview })
			end
			vim.ui.select(items, {
				prompt = "Mentions",
				format_item = function(item) return item.label end,
			}, function(choice)
				if choice then ui.jump_to_message(choice.id) end
			end)
		end, function()
			vim.notify("Search failed", vim.log.levels.ERROR, { title = "tg" })
		end)
	end,
})

M.register("saved", {
	description = "Open Saved Messages",
	callback = function()
		local sid = ui.state.saved_chat_id
		if not sid then
			vim.notify("Saved Messages not loaded yet", vim.log.levels.INFO, { title = "tg" })
			return
		end
		require("telegram").open_chat(sid, "Favorites")
	end,
})

M.register("groups", {
	description = "Switch to a group (filtered)",
	callback = function()
		local items = {}
		for _, id in ipairs(ui.state.group_ids) do
			local g = ui.state.groups[id]
			if g and g.type == "group" then
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
			end
		end
		if #items == 0 then
			vim.notify("No groups", vim.log.levels.INFO, { title = "tg" })
			return
		end
		ui.show_groups_picker(function(item)
			if item then require("telegram").open_chat(item.id, item.title) end
		end, items)
	end,
})

M.register("channels", {
	description = "Switch to a channel (filtered)",
	callback = function()
		local items = {}
		for _, id in ipairs(ui.state.group_ids) do
			local g = ui.state.groups[id]
			if g and g.type == "channel" then
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
			end
		end
		if #items == 0 then
			vim.notify("No channels", vim.log.levels.INFO, { title = "tg" })
			return
		end
		ui.show_groups_picker(function(item)
			if item then require("telegram").open_chat(item.id, item.title) end
		end, items)
	end,
})

M.register("dm", {
	description = "Switch to a private chat (filtered)",
	callback = function()
		local items = {}
		for _, id in ipairs(ui.state.group_ids) do
			local g = ui.state.groups[id]
			if g and g.type == "private" then
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
			end
		end
		if #items == 0 then
			vim.notify("No private chats", vim.log.levels.INFO, { title = "tg" })
			return
		end
		ui.show_groups_picker(function(item)
			if item then require("telegram").open_chat(item.id, item.title) end
		end, items)
	end,
})

M.register("translate", {
	description = "Translate message under cursor",
	condition = function()
		local t = ui.curr_msg()
		return t and t.text and #t.text > 0
	end,
	callback = function()
		local msg = ui.curr_msg()
		if not msg or not msg.text or #msg.text == 0 then
			vim.notify("No text at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Translate to (lang code, e.g. en, zh): ", default = "en" }, function(lang)
			if not lang or #lang == 0 then return end
			vim.notify("Translating...", vim.log.levels.INFO, { title = "tg" })
			local data = server.translate_text(msg.text, lang)
			if data and data.text and #data.text > 0 then
				vim.notify(data.text, vim.log.levels.INFO, { title = "Translation" })
			else
				local reason = (data and data.error) or "unknown error"
				vim.notify("Translation error: " .. reason, vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end,
})

M.register("draft", {
	description = "Save draft to server / clear draft",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		local draft = ui.state.editor_draft or ""
		local has_draft = #draft > 0
		local choices = has_draft and { "Save draft to server", "Clear server draft", "Cancel" } or { "Cancel" }
		vim.ui.select(choices, { prompt = has_draft and "Draft: " .. draft:sub(1, 40) or "No draft" }, function(choice)
			if not choice or choice == "Cancel" then return end
			if choice:find("Save") then
				local ok, err = server.set_draft(chat_id, draft)
				if ok then
					vim.notify("Draft saved to server", vim.log.levels.INFO, { title = "tg" })
				else
					vim.notify("Draft save failed: " .. (err or "unknown"), vim.log.levels.WARN, { title = "tg" })
				end
			elseif choice:find("Clear") then
				local ok, err = server.set_draft(chat_id, "")
				if ok then
					ui.state.editor_draft = nil
					vim.notify("Draft cleared", vim.log.levels.INFO, { title = "tg" })
				else
					vim.notify("Draft clear failed: " .. (err or "unknown"), vim.log.levels.WARN, { title = "tg" })
				end
			end
		end)
	end,
})
M.register("showarchived", {
	description = "Toggle archived chats in picker",
	callback = function()
		local st = require("telegram.state").state
		st.show_archived = not st.show_archived
		if st.show_archived then
			vim.notify("Loading archived chats...", vim.log.levels.INFO, { title = "tg" })
			local srv = require("telegram.server")
			srv.get_archived_chats_async(function(chats)
				if not st.show_archived then return end
				if not chats or #chats == 0 then
					vim.notify("No archived chats", vim.log.levels.INFO, { title = "tg" })
					st.show_archived = false
					return
				end
				local items = {}
				for _, g in ipairs(chats) do
					table.insert(items, {
						id = g.id,
						title = g.title,
						type = g.type or "group",
						unread = g.unreadCount or 0,
						is_saved = g.isSaved or false,
						is_archived = true,
					})
				end
				ui.show_groups_picker(function(item)
					st.show_archived = false
					if item then
						require("telegram").open_chat(item.id, item.title)
						local st = require("telegram.state").state
						st.current_chat_archived = true
					end
				end, items)
				vim.notify("Showing archived chats (" .. #chats .. ")", vim.log.levels.INFO, { title = "tg" })
			end)
		else
			vim.notify("Showing main chat list", vim.log.levels.INFO, { title = "tg" })
		end
	end,
})

M.register("refreshmedia", {
	description = "Download and update image for message under cursor",
	condition = function()
		if is_service() then return false end
		local t = ui.curr_msg()
		return t and t.type and t.type ~= "messageText" and t.type:find("^message")
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local target = ui.curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local t = target.type or ""
		if t == "messageText" or not t:find("^message") then
			vim.notify("Not a media message", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.notify("Downloading media...", vim.log.levels.INFO, { title = "tg" })
		server.get_media_async(ui.state.chat_id, target.id, function(res)
			if res and res.path and #res.path > 0 then
				target.filePath = res.path
				ui.render()
				vim.notify("Media updated", vim.log.levels.INFO, { title = "tg" })
			else
				vim.notify("No media path found", vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

return M
