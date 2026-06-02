local server = require("telegram.server")
local ui = require("telegram.ui")

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
		end)
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
	vim.fn.jobstart({
		"sh", "-c",
		'xdg-open "' .. target .. '" 2>/dev/null || open "' .. target .. '" 2>/dev/null || true',
	})
end

M.register("openlink", {
	description = "Open URL or media file under cursor",
	condition = function()
		if is_service() then return false end
		if not ui.state.win or not vim.api.nvim_win_is_valid(ui.state.win) then return false end
		if not ui.state.buf or not vim.api.nvim_buf_is_valid(ui.state.buf) then return false end
		local cursor = vim.api.nvim_win_get_cursor(ui.state.win)
		local text = vim.api.nvim_buf_get_lines(ui.state.buf, cursor[1] - 1, cursor[1], false)[1]
		if not text then return false end
		return text:match("https?://[%w%._~:/?#%@!$&'()*+,;=-]+")
			or text:match("!%[%w+%]%((.-)%)")
	end,
	callback = function()
		if not ui.state.win or not vim.api.nvim_win_is_valid(ui.state.win) then return end
		if not ui.state.buf or not vim.api.nvim_buf_is_valid(ui.state.buf) then return end
		local cursor = vim.api.nvim_win_get_cursor(ui.state.win)
		local text = vim.api.nvim_buf_get_lines(ui.state.buf, cursor[1] - 1, cursor[1], false)[1]
		if not text then return end
		local url = text:match("https?://[%w%._~:/?#%@!$&'()*+,;=-]+")
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
