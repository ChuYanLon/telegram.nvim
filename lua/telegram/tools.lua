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
			-- Resolve t.me links in-app instead of opening in browser
			if url:match("^https?://t%.me/") then
				vim.notify("Resolving message link...", vim.log.levels.INFO, { title = "tg" })
				server.get_message_link_info_async(url, function(info, err)
					if info and info.chat_id and info.message_id then
						if ui.state.chat_id == info.chat_id then
							ui.jump_to_message(info.message_id)
						else
							ui.state._jump_to_msg = info.message_id
							ui.open_chat(info.chat_id, "Message link")
						end
					else
						vim.notify("Link resolve failed: " .. (err or "unknown error") .. ", opening in browser", vim.log.levels.WARN, { title = "tg" })
						open_target(url)
					end
				end)
				return
			end
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


M.register("pinchat", {
	description = "Pin / unpin current chat",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = ui.state.chat_id
		local g = ui.state.groups[chat_id]
		local is_pinned = g and g.is_pinned
		if server.toggle_pin_chat(chat_id, not is_pinned) then
			ui.state.groups[chat_id] = ui.state.groups[chat_id] or {}
			ui.state.groups[chat_id].is_pinned = not is_pinned
			vim.notify((is_pinned and "Unpinned" or "Pinned") .. " chat", vim.log.levels.INFO, { title = "tg" })
			vim.cmd("redrawstatus")
		end
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
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_pinned = g.is_pinned or false, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
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
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_pinned = g.is_pinned or false, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
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
				table.insert(items, { id = g.id, title = g.title, type = g.type, unread = g.unread_count or 0, is_pinned = g.is_pinned or false, is_saved = g.is_saved or false, is_archived = g.is_archived or false })
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

local translate_win = nil

local function close_translate()
	if translate_win then
		pcall(vim.api.nvim_win_close, translate_win, true)
		translate_win = nil
	end
end

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
			close_translate()
			local data = server.translate_text(msg.text, lang)
			if data and data.text and #data.text > 0 then
				local buf = vim.api.nvim_create_buf(false, true)
				vim.bo[buf].buftype = "nofile"
				vim.bo[buf].bufhidden = "wipe"

				local lines = vim.split(data.text, "\n")
				local source_label = msg.sender and msg.sender.name or "Unknown"
				local header = "── " .. source_label .. " → " .. lang .. " ──"
				table.insert(lines, 1, header)
				table.insert(lines, "")

				local height = math.min(#lines + 2, 30)
				local width = 40
				for _, l in ipairs(lines) do
					local w = vim.fn.strdisplaywidth(l)
					if w + 4 > width then width = math.min(w + 4, 80) end
				end

				translate_win = vim.api.nvim_open_win(buf, true, {
					relative = "editor",
					width = width,
					height = height,
					row = math.max(0, (vim.o.lines - height) / 2),
					col = math.max(0, (vim.o.columns - width) / 2),
					zindex = 200,
					style = "minimal",
					border = "rounded",
					title = " Translation ",
					title_pos = "center",
				})
				vim.wo[translate_win].winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder"
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.keymap.set("n", "q", close_translate, { buffer = buf, nowait = true })
				vim.keymap.set("n", "<Esc>", close_translate, { buffer = buf, nowait = true })
			else
				local reason = (data and data.error) or "unknown error"
				vim.notify("Translation error: " .. reason, vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end,
})

M.register("translate_zh", {
	description = "Translate message under cursor to Chinese",
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
		close_translate()
		local data = server.translate_text(msg.text, "zh")
		if data and data.text and #data.text > 0 then
			local buf = vim.api.nvim_create_buf(false, true)
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].bufhidden = "wipe"

			local lines = vim.split(data.text, "\n")
			local source_label = msg.sender and msg.sender.name or "Unknown"
			local header = "── " .. source_label .. " → 中文 ──"
			table.insert(lines, 1, header)
			table.insert(lines, "")

			local height = math.min(#lines + 2, 30)
			local width = 40
			for _, l in ipairs(lines) do
				local w = vim.fn.strdisplaywidth(l)
				if w + 4 > width then width = math.min(w + 4, 80) end
			end

			translate_win = vim.api.nvim_open_win(buf, true, {
				relative = "editor",
				width = width,
				height = height,
				row = math.max(0, (vim.o.lines - height) / 2),
				col = math.max(0, (vim.o.columns - width) / 2),
				zindex = 200,
				style = "minimal",
				border = "rounded",
				title = " 中文翻译 ",
				title_pos = "center",
			})
			vim.wo[translate_win].winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.keymap.set("n", "q", close_translate, { buffer = buf, nowait = true })
			vim.keymap.set("n", "<Esc>", close_translate, { buffer = buf, nowait = true })
		else
			local reason = (data and data.error) or "unknown error"
			vim.notify("Translation error: " .. reason, vim.log.levels.ERROR, { title = "tg" })
		end
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

M.register("messagelink", {
	description = "Copy shareable link of message under cursor",
	condition = function()
		local t = ui.curr_msg()
		return t and t.id ~= nil
	end,
	callback = function()
		local msg = ui.curr_msg()
		if not msg or not msg.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if not ui.state.chat_id then return end
		local link = server.get_message_link(ui.state.chat_id, msg.id)
		if link then
			vim.fn.setreg("+", link)
			vim.notify("Link copied: " .. link, vim.log.levels.INFO, { title = "tg" })
		else
			vim.notify("Failed to generate message link", vim.log.levels.WARN, { title = "tg" })
		end
	end,
})
M.register("userinfo", {
	description = "View profile of message sender",
	condition = function()
		local t = ui.curr_msg()
		return t and t.sender and t.sender.id and not t.own
	end,
	callback = function()
		local target = ui.curr_msg()
		if not target or not target.sender or not target.sender.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if target.own then
			vim.notify("That is you", vim.log.levels.INFO, { title = "tg" })
			return
		end
		local user_id = tonumber(target.sender.id)
		if not user_id then
			vim.notify("Cannot identify sender", vim.log.levels.WARN, { title = "tg" })
			return
		end
		server.get_user_profile_async(user_id, function(profile)
			if not profile then
				vim.notify("User not found", vim.log.levels.ERROR, { title = "tg" })
				return
			end

			local buf = vim.api.nvim_create_buf(false, true)
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].bufhidden = "wipe"

			local name = profile.firstName or ""
			if profile.lastName and #profile.lastName > 0 then
				name = name .. " " .. profile.lastName
			end
			local badge = profile.isPremium and " \xe2\xad\x90" or ""
			local username = (profile.username and #profile.username > 0) and "@" .. profile.username or ""

			-- Format "last seen" from status
			local status_str = nil
			if profile.status and #profile.status > 0 then
				if profile.status == "online" then
					status_str = "online"
				elseif profile.status == "recently" then
					status_str = "was recently"
				elseif profile.status == "last_week" then
					status_str = "was last week"
				elseif profile.status == "last_month" then
					status_str = "was last month"
				else
					local _, _, ts = profile.status:find("^offline:(%d+)$")
					if ts then
						local was_online = tonumber(ts)
						if was_online and was_online > 0 then
							local now = os.time()
							local diff = now - was_online
							if diff < 60 then
								status_str = "just now"
							elseif diff < 3600 then
								status_str = math.floor(diff / 60) .. " min ago"
							elseif diff < 86400 then
								local h = math.floor(diff / 3600)
								local m = math.floor((diff % 3600) / 60)
								status_str = h .. "h" .. (m > 0 and " " .. m .. "m" or "") .. " ago"
							else
								local days = math.floor(diff / 86400)
								status_str = days .. (days > 1 and " days ago" or " day ago")
							end
						end
					end
				end
			end

			-- Format birthdate
			local birth_str = nil
			if profile.birthdate and type(profile.birthdate) == "table" then
				local month_names = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
				local day = profile.birthdate.day
				local month = profile.birthdate.month
				local year = profile.birthdate.year
				if day and month and day > 0 and month > 0 then
					local mname = month_names[month] or month
					birth_str = day .. " " .. mname
					if year and year > 0 then
						birth_str = birth_str .. " " .. year
					end
				end
			end

			local sep = string.rep("\xe2\x94\x80", 22)

			-- Build rows with highlight annotations
			local rows = {}
			local function row(t, hl)
				table.insert(rows, { text = t, hl = hl })
			end
			local function lbl(text, val, hl)
				local value_col = 2 + 10  -- margin + padded label width
				local r = { text = "  " .. text .. string.rep(" ", 10 - #text) .. val, value_col = value_col }
				if hl then r.hl = hl end
				table.insert(rows, r)
			end
			row("  " .. name .. badge .. (profile.isBot and " \xf0\x9f\xa4\x96" or ""), "TgWinbarTitle")
			if #username > 0 then
				row("  " .. username, "Comment")
			end
			row("  " .. sep, "TgDateSeparator")

			-- Info: phone, status, birthday
			local has_info = false
			if profile.phone and #profile.phone > 0 then
				lbl("Phone", profile.phone); has_info = true
			end
			if status_str then
				local hl = status_str == "online" and "DiagnosticOk" or nil
				lbl("Seen", status_str, hl); has_info = true
			end
			if birth_str then
				lbl("Birthday", birth_str); has_info = true
			end
			if has_info then
				row("")
			end
			if profile.canBeCalled then
				lbl("Call", "available")
			end

			-- Bio
			if profile.bio and #profile.bio > 0 then
				local first = true
				for b in profile.bio:gmatch("[^\n]+") do
					if first then
						lbl("Bio", b); first = false
					else
						lbl("", b)
					end
				end
				row("")
			end

			-- Groups in common
			if profile.groupInCommon and profile.groupInCommon > 0 and profile.commonGroups then
				row("  Groups(" .. #profile.commonGroups .. ")")
				local group_indent = string.rep(" ", 12)
				for _, g in ipairs(profile.commonGroups) do
					local gn = g.title or ("Group " .. g.id)
					row(group_indent .. "\xe2\x94\x80\xe2\x94\x80 " .. gn, "Comment")
				end
				row("")
			end
			-- Separator + bottom info
			local has_bottom = profile.id or (profile.isContact ~= nil)
			if has_bottom then
				row("  " .. sep, "TgDateSeparator")
			end
			if profile.id then
				lbl("ID", tostring(profile.id))
			end
			if profile.isContact ~= nil then
				local contact_icon = profile.isContact and "\xe2\x9c\x93" or "\xe2\x9c\x97"
				lbl("Contact", contact_icon,
						profile.isContact and "DiagnosticOk" or "DiagnosticError")
			end
			if profile.isBlocked then
				row("  Blocked", "DiagnosticError")
			end
			row("")
			row("", "TgWinbarTitle")
			row("")

			-- Window sizing
			local height = #rows
			local width = 36
			for _, r in ipairs(rows) do
				local w = vim.fn.strdisplaywidth(r.text)
				if w + 4 > width then
					width = w + 4
				end
			end
			width = math.min(width, 54)
			height = math.min(height, 28)
			-- Resize separators to match window width
			local sep_str = string.rep("\xe2\x94\x80", math.max(8, width - 4))
			for _, r in ipairs(rows) do
				if r.hl == "TgDateSeparator" then
					r.text = "  " .. sep_str
				end
			end
			-- Center hint row with key highlights
			for _, r in ipairs(rows) do
				if r.hl == "TgWinbarTitle" and r.text == "" then
					local hint = "[m] DM  [b] Block  [c] Contact"
					local hint_w = vim.fn.strdisplaywidth(hint)
					local pad = math.max(2, math.floor((width - hint_w) / 2))
					r.text = string.rep(" ", pad) .. hint
					-- Store key highlight positions: { start_col, end_col, hl_group }
						local key_colors = { m = "DiagnosticOk", b = "DiagnosticError", c = "DiagnosticInfo" }
						local keys = {}
						for off in hint:gmatch("()%[%w%]") do
							local k = hint:sub(off + 1, off + 1)
							local hl = key_colors[k] or "TgTitleKey"
							table.insert(keys, { pad + off, pad + off + 1, hl })
						end
					r.key_hls = keys
				end
			end
			local lines = {}
			for _, r in ipairs(rows) do
				table.insert(lines, r.text)
			end

			local win = vim.api.nvim_open_win(buf, true, {
				relative = "editor",
				width = width,
				height = height,
				row = math.max(0, (vim.o.lines - height) / 2 - 1),
				col = math.max(0, (vim.o.columns - width) / 2),
				zindex = 200,
				style = "minimal",
				border = "rounded",
				title = " User Info ",
				title_pos = "center",
			})
			vim.wo[win].winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			for i, r in ipairs(rows) do
				if r.value_col then
					if r.hl then
						pcall(vim.api.nvim_buf_add_highlight, buf, -1, r.hl, i - 1, r.value_col, -1)
					else
						pcall(vim.api.nvim_buf_add_highlight, buf, -1, "Comment", i - 1, r.value_col, -1)
					end
				elseif r.hl then
					pcall(vim.api.nvim_buf_add_highlight, buf, -1, r.hl, i - 1, 0, -1)
				end
				if r.key_hls then
					for _, kh in ipairs(r.key_hls) do
						pcall(vim.api.nvim_buf_add_highlight, buf, -1, kh[3], i - 1, kh[1], kh[2])
					end
				end
			end
			vim.keymap.set("n", "q", function()
				pcall(vim.api.nvim_win_close, win, true)
			end, { buffer = buf, nowait = true })
			vim.keymap.set("n", "<Esc>", function()
				pcall(vim.api.nvim_win_close, win, true)
			end, { buffer = buf, nowait = true })
			vim.keymap.set("n", "m", function()
				pcall(vim.api.nvim_win_close, win, true)
				local chat = require("telegram.server").open_private_chat(profile.id)
				if chat then
					require("telegram").open_chat(chat.id, chat.title, chat.type)
				else
					vim.notify("Cannot open DM", vim.log.levels.WARN, { title = "tg" })
				end
			end, { buffer = buf, nowait = true })
			vim.keymap.set("n", "b", function()
				pcall(vim.api.nvim_win_close, win, true)
				if profile.isBlocked then
					require("telegram.server").unblock_user(profile.id)
					vim.notify("Unblocked", vim.log.levels.INFO, { title = "tg" })
				else
					require("telegram.server").block_user(profile.id)
					vim.notify("Blocked", vim.log.levels.INFO, { title = "tg" })
				end
			end, { buffer = buf, nowait = true })
			vim.keymap.set("n", "c", function()
				pcall(vim.api.nvim_win_close, win, true)
				if profile.isContact then
					require("telegram.server").delete_contact(profile.id)
					vim.notify("Contact deleted", vim.log.levels.INFO, { title = "tg" })
				else
					require("telegram.server").add_contact(profile.id)
					vim.notify("Contact added", vim.log.levels.INFO, { title = "tg" })
				end
			end, { buffer = buf, nowait = true })
		end)
	end,
})

M.register("blocked", {
	description = "List and manage blocked users",
	callback = function()
		vim.notify("Loading blocked users...", vim.log.levels.INFO, { title = "tg" })
		local users = require("telegram.server").get_blocked_users()
		if not users or #users == 0 then
			vim.notify("No blocked users", vim.log.levels.INFO, { title = "tg" })
			return
		end
		local items = {}
		for _, u in ipairs(users) do
			table.insert(items, { id = u.id, name = u.name, label = u.name .. "  [unblock]" })
		end
		vim.ui.select(items, {
			prompt = "Blocked users (select to unblock)",
			format_item = function(item) return item.label end,
		}, function(choice)
			if not choice then return end
			local ok = require("telegram.server").unblock_user(choice.id)
			if ok then
				vim.notify("Unblocked " .. choice.name, vim.log.levels.INFO, { title = "tg" })
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
						is_pinned = g.isPinned or false,
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

M.register("folders", {
	description = "Switch chat folder",
	callback = function()
		local st = require("telegram.state").state
		local srv = require("telegram.server")

		local function on_folder_chosen(folder_id, folder_name)
			if not folder_id then return end
			vim.notify("Loading folder: " .. (folder_name or "") .. "...", vim.log.levels.INFO, { title = "tg" })
			srv.get_folder_chats_async(folder_id, function(chats)
				if not chats or #chats == 0 then
					vim.notify("No chats in this folder", vim.log.levels.INFO, { title = "tg" })
					return
				end
				local picker_items = {}
				for _, g in ipairs(chats) do
					table.insert(picker_items, {
						id = g.id,
						title = g.title,
						type = g.type or "group",
						unread = g.unreadCount or 0,
						is_pinned = g.isPinned or false,
						is_saved = g.isSaved or false,
						is_archived = false,
					})
				end
				require("telegram.ui").show_groups_picker(function(item)
					if item then
						require("telegram").open_chat(item.id, item.title)
					end
				end, picker_items)
			end)
		end

		local function show_folder_picker(folders)
			if #folders == 0 then
				vim.notify("No chat folders found", vim.log.levels.INFO, { title = "tg" })
				return
			end
			-- Use a tmp buffer picker via vim.ui.select (avoid snacks picker direct API)
			local items = {}
			for _, f in ipairs(folders) do
				local label = tostring(f.name or "")
				table.insert(items, { id = f.id, text = label, title = label })
			end
			vim.ui.select(items, {
				prompt = "Select folder:",
				format_item = function(item)
					return item.title
				end,
			}, function(choice)
				if choice then on_folder_chosen(choice.id, choice.title) end
			end)
		end

		-- Try cache from WS event first, then HTTP fallback
		local folders = {}
		for _, f in pairs(st.chat_folders) do
			table.insert(folders, f)
		end
		table.sort(folders, function(a, b) return a.id < b.id end)
		if #folders > 0 then
			show_folder_picker(folders)
		else
			srv.get_folders_async(function(data)
				if not data or type(data) ~= "table" or #data == 0 then
					vim.notify("No chat folders found", vim.log.levels.INFO, { title = "tg" })
					return
				end
				for _, f in ipairs(data) do
					st.chat_folders[f.id] = { id = f.id, name = f.name, is_shareable = f.is_shareable }
				end
				local folder_list = {}
				for _, f in pairs(st.chat_folders) do
					table.insert(folder_list, f)
				end
				table.sort(folder_list, function(a, b) return a.id < b.id end)
				show_folder_picker(folder_list)
			end)
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

-- ─── Poll tools ───────────────────────────────────────────────────────

M.register("vote", {
	description = "Vote on the poll message under cursor",
	condition = function()
		local t = ui.curr_msg()
		return t and t.type == "messagePoll" and t.pollInfo and not t.pollInfo.isClosed
	end,
	callback = function()
		local msg = ui.curr_msg()
		local poll = msg.pollInfo
		if not poll or not poll.options then
			vim.notify("Not a poll message", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if poll.allowsMultipleAnswers then
			vim.ui.input({ prompt = "Enter option numbers (e.g. 1,3): " }, function(input)
				if not input or #input == 0 then return end
				local ids = {}
				for num in input:gmatch("(%d+)") do
					local n = tonumber(num)
					if n and n > 0 and n <= #poll.options then
						table.insert(ids, n - 1)
					end
				end
				if #ids == 0 then
					vim.notify("No valid option numbers", vim.log.levels.WARN, { title = "tg" })
					return
				end
				vim.notify("Voting...", vim.log.levels.INFO, { title = "tg" })
				if not ui.state.chat_id then return end
				server.vote_poll(ui.state.chat_id, msg.id, ids)
			end)
		else
			local items = {}
			for i, opt in ipairs(poll.options) do
				local prefix = opt.isChosen and "✓ " or "  "
				local label = prefix .. opt.text
					.. "  (" .. opt.voterCount .. " votes, " .. opt.votePercentage .. "%)"
				table.insert(items, { id = opt.id, index = i, label = label, chosen = opt.isChosen })
			end
			vim.ui.select(items, {
				prompt = "Vote: " .. poll.question:sub(1, 40),
				format_item = function(item) return item.label end,
			}, function(choice)
				if not choice then return end
				if not ui.state.chat_id then return end
				local msg_id = msg.id
				if not msg_id then return end
				vim.notify("Voting...", vim.log.levels.INFO, { title = "tg" })
				server.vote_poll(ui.state.chat_id, msg_id, { choice.index - 1 })
			end)
		end
	end,
})

M.register("createpoll", {
	description = "Create a poll in current chat",
	condition = function()
		return ui.state.chat_id ~= nil and ui.state.permissions.can_send_polls ~= false
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Poll question: " }, function(question)
			if not question or #question == 0 then return end
			vim.ui.input({ prompt = "Options (separated by ,): " }, function(options_str)
				if not options_str or #options_str == 0 then return end
				-- Support both ASCII and Chinese commas
				local normalized = options_str:gsub("[“,，]", ",")
				local opts = vim.split(normalized, ",")
				for i, o in ipairs(opts) do
					opts[i] = o:match("^%s*(.-)%s*$")
				end
				local clean = {}
				for _, o in ipairs(opts) do
					if #o > 0 then table.insert(clean, o) end
				end
				if #clean < 2 then
					vim.notify("Need at least 2 options", vim.log.levels.WARN, { title = "tg" })
					return
				end
				vim.ui.input({ prompt = "Anonymous? (y/n, default y): " }, function(anon_str)
					if anon_str == nil then return end
					local is_anon = anon_str == "" or anon_str:lower():sub(1, 1) == "y"
					vim.ui.input({ prompt = "Allow multiple answers? (y/n, default n): " }, function(multi_str)
						if multi_str == nil then return end
						local is_multi = multi_str:lower():sub(1, 1) == "y"
						vim.ui.input({ prompt = "Timer (seconds, 0 for none): " }, function(timer_str)
							if timer_str == nil then return end
							local open_period = tonumber(timer_str) or 0
							vim.notify("Creating poll...", vim.log.levels.INFO, { title = "tg" })
							local result = server.send_poll(ui.state.chat_id, question, clean, {
								is_anonymous = is_anon,
								allows_multiple_answers = is_multi,
								open_period = open_period,
							})
							if result and not result.error then
								vim.notify("Poll created", vim.log.levels.INFO, { title = "tg" })
							else
								vim.notify("Failed to create poll: " .. (result and result.error or "unknown error"), vim.log.levels.ERROR, { title = "tg" })
							end
						end)
					end)
				end)
			end)
		end)
	end,
})


M.register("voters", {
	description = "List who voted on each poll option",
	condition = function()
		local t = ui.curr_msg()
		return t and t.type == "messagePoll" and t.pollInfo and t.pollInfo.canGetVoters ~= false
	end,
	callback = function()
		local msg = ui.curr_msg()
		local poll = msg.pollInfo
		if not poll or not poll.options then
			vim.notify("Not a poll message", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if not ui.state.chat_id then return end
		local items = {}
		for i, opt in ipairs(poll.options) do
			local label = opt.text .. "  (" .. opt.voterCount .. " votes)"
			table.insert(items, { index = i, label = label })
		end
		vim.ui.select(items, {
			prompt = "Select option to see voters:",
			format_item = function(item) return item.label end,
		}, function(choice)
			if not choice then return end
			if not ui.state.chat_id then return end
			local msg_id = msg.id
			if not msg_id then return end
			vim.notify("Loading voters...", vim.log.levels.INFO, { title = "tg" })
			local data = server.get_poll_voters(ui.state.chat_id, msg_id, choice.index - 1)
			if not data or not data.voters or #data.voters == 0 then
				vim.notify("No voters found", vim.log.levels.INFO, { title = "tg" })
				return
			end
			local lines = {}
			for _, v in ipairs(data.voters) do
				local name = v.name or "user_" .. tostring(v.user_id)
				table.insert(lines, name)
			end
			vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Voters" })
		end)
	end,
})

M.register("stoppoll", {
	description = "Stop a poll",
	condition = function()
		local t = ui.curr_msg()
		return t and t.type == "messagePoll" and t.pollInfo and not t.pollInfo.isClosed
	end,
	callback = function()
		local msg = ui.curr_msg()
		if not msg or not ui.state.chat_id then return end
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Stop this poll?",
		}, function(choice)
			if choice ~= "Yes" then return end
			vim.notify("Stopping poll...", vim.log.levels.INFO, { title = "tg" })
			local result = server.stop_poll(ui.state.chat_id, msg.id)
			if result and not result.error then
				vim.notify("Poll stopped", vim.log.levels.INFO, { title = "tg" })
			else
				vim.notify("Failed to stop poll: " .. (result and result.error or "unknown error"), vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end,
})

M.register("openshared", {
	description = "Open shared chat or user DM",
	condition = function()
		local t = ui.curr_msg()
		return t and t.sharedInfo and (t.sharedInfo.chatId or (t.sharedInfo.userIds and #t.sharedInfo.userIds > 0))
	end,
	callback = function()
		local msg = ui.curr_msg()
		if not msg or not msg.sharedInfo then return end
		local info = msg.sharedInfo
		if info.chatId then
			-- Open shared chat directly
			require("telegram").open_chat(info.chatId, info.chatTitle or "Shared chat")
		elseif info.userIds and #info.userIds > 0 then
			-- Pick which user to DM
			local items = {}
			for i, uid in ipairs(info.userIds) do
				local name = (info.userNames and info.userNames[i]) or ("user_" .. uid)
				table.insert(items, { id = uid, label = name })
			end
			if #items == 1 then
				-- Only one user, open directly
				local chat = require("telegram.server").open_private_chat(items[1].id)
				if chat then
					require("telegram").open_chat(chat.id, items[1].label, chat.type)
				end
			else
				vim.ui.select(items, {
					prompt = "Open DM with:",
					format_item = function(item) return item.label end,
				}, function(choice)
					if not choice then return end
					local chat = require("telegram.server").open_private_chat(choice.id)
					if chat then
						require("telegram").open_chat(chat.id, choice.label, chat.type)
					end
				end)
			end
		end
	end,
})

return M
