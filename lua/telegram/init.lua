---@class TgHealth
---@field ready boolean
---@field auth TgAuth|nil

---@class TgAuth
---@field state string
---@field error string|nil
---@field hint string|nil
---@field canInput boolean|nil

---@class TgChat
---@field id any
---@field title string
---@field lastMessage TgMessage|nil
---@field memberCount integer|nil

local config = require("telegram.config")
local server = require("telegram.server")
local auth = require("telegram.auth")
local ws = require("telegram.ws")
local ui = require("telegram.ui")
local tools = require("telegram.tools")
require("telegram.github")

local M = {}

local initialized = false
local starting = false

local notify_groups = {}
local notify_timer_id = nil

local function flush_notify()
	if not next(notify_groups) then
		return
	end
	local lines = {}
	for cid, g in pairs(notify_groups) do
		if g.count > 1 then
			table.insert(lines, string.format("[%s] %d new messages", g.title, g.count))
		else
			table.insert(lines, string.format("[%s] %s: %s", g.title, g.sender, g.preview))
		end
	end
	notify_groups = {}
	notify_timer_id = nil
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "tg" })
end

local function should_notify(msg)
	if not msg or not msg.chat then return false end
	for _, t in ipairs(config.config.notify_chat_types) do
		if t == "mention" and msg.containsMention then return true end
		if msg.chat.type == t then return true end
	end
	return false
end

local function queue_notify(chat_id, chat_title, sender, text)
	local preview = (text or ""):gsub("\n", " "):sub(1, 50)
	local g = notify_groups[chat_id]
	if g then
		g.count = g.count + 1
	else
		notify_groups[chat_id] = { title = chat_title, sender = sender, preview = preview, count = 1 }
	end
	if not notify_timer_id then
		notify_timer_id = vim.fn.timer_start(500, function()
			notify_timer_id = nil
			flush_notify()
		end, { ["repeat"] = 1 })
	end
end

---@param v boolean
function M.set_initialized(v)
	initialized = v
end

M.setup = config.setup

local msg_queue = {}
local msg_timer = nil
local redraw_pending = false

local function debounced_redraw()
	if not redraw_pending then
		redraw_pending = true
		vim.defer_fn(function()
			redraw_pending = false
			vim.cmd("redrawstatus")
		end, 0)
	end
end

local function flush_msg_queue()
	msg_timer = nil
	local batch = msg_queue
	msg_queue = {}

	if #batch == 0 then
		return
	end

	local st = ui.state
	local cur_chat_id = st.chat_id
	local current_msgs = {}
	local seen = {}

	for _, msg in ipairs(batch) do
		local mid = msg.id
		local skip = false
		if mid then
			local key = tostring(mid)
			if seen[key] then
				skip = true
			else
				seen[key] = true
			end
		end

		if not skip then
			local is_current = cur_chat_id and msg.chat and msg.chat.id == cur_chat_id
			if not is_current then
				local sender = msg.sender and msg.sender.name or "?"
				ui.update_group_last_msg(msg.chat and msg.chat.id, sender, msg.text and msg.text:sub(1, 60) or "")
				if should_notify(msg) then
					queue_notify(msg.chat.id, msg.chat.title or "?", sender, msg.text)
				end
			else
				local exists = false
				if mid then
					for _, m in ipairs(st.messages) do
						if tostring(m.id) == tostring(mid) then
							exists = true
							break
						end
					end
				end
				if not exists then
					table.insert(current_msgs, msg)
				end
			end
		end
	end

	if #current_msgs == 0 then
		return
	end

	if not st.buf or not st.win or not vim.api.nvim_buf_is_valid(st.buf) or not vim.api.nvim_win_is_valid(st.win) then
		for _, msg in ipairs(current_msgs) do
			if should_notify(msg) then
				local sender = msg.sender and msg.sender.name or "?"
				queue_notify(msg.chat.id, msg.chat.title or "?", sender, msg.text)
			end
		end
		return
	end

	local cur = vim.api.nvim_win_get_cursor(st.win)
	local total_before = vim.api.nvim_buf_line_count(st.buf)
	local at_bottom = cur[1] >= total_before - 1

	local added_to_buffer = false
	for _, msg in ipairs(current_msgs) do
		local mid = msg.id or (os.time() + math.random())
		local skip_insert = false

		if msg.own and mid then
			for _, m in ipairs(st.messages) do
				if m.own and tostring(m.id) == tostring(mid) then
					m.id = mid
					m.date = msg.date
					m.sender = msg.sender
					m.text = msg.text
					m.replyTo = msg.replyTo
					m.filePath = msg.filePath
					m.mediaPath = msg.mediaPath
					m.mimeType = msg.mimeType
					skip_insert = true
					break
				end
			end
		end

		if not skip_insert then
			st.unread = st.unread + 1
			if st.groups[st.chat_id] then
				st.groups[st.chat_id].unread_count = st.unread
			end

			if at_bottom or msg.own then
				added_to_buffer = true
				local is_focused = st.win and vim.api.nvim_win_is_valid(st.win) and vim.api.nvim_get_current_win() == st.win
				if not is_focused then
					if should_notify(msg) then
						local sender = msg.sender and msg.sender.name or "?"
						queue_notify(msg.chat.id, msg.chat.title or "?", sender, msg.text)
					end
				end
				table.insert(st.messages, {
					id = mid,
					type = msg.type,
					date = msg.date,
					sender = msg.sender,
					text = msg.text,
					own = msg.own,
					replyTo = msg.replyTo,
					filePath = msg.filePath,
					mediaPath = msg.mediaPath,
					mimeType = msg.mimeType,
					_unread = not msg.own,
				})
			else
				st.exhausted_forward = false
				local sender = msg.sender and msg.sender.name or "?"
				queue_notify(msg.chat and msg.chat.id, msg.chat and msg.chat.title or "?", sender, msg.text)
			end
		end
	end

	if added_to_buffer then
		table.sort(st.messages, function(a, b)
			if a.date ~= b.date then return a.date < b.date end
			return a.id < b.id
		end)

		ui.trim_oldest()
		ui.render()
		st.exhausted = false
		st.exhausted_forward = false
	end

	local last = current_msgs[#current_msgs]
	if last then
		local ts = os.date("%Y-%m-%d %H:%M", last.date)
		st.last_msg = ("[%s] %s: %s"):format(ts, last.sender and last.sender.name or "?", (last.text or ""):sub(1, 40))
		ui.update_title()
	end

	if at_bottom and st.win and vim.api.nvim_win_is_valid(st.win) then
		pcall(vim.api.nvim_win_set_cursor, st.win, { vim.api.nvim_buf_line_count(st.buf) - 1, cur[2] })
	end

	local t = last and last.type or ""
	if ({ messagePhoto = true, messageVideo = true, messageAnimation = true, messageDocument = true, messageAudio = true, messageVoiceNote = true, messageVideoNote = true, messageSticker = true })[t] and (not last.filePath or #last.filePath == 0) then
		local media_chat_id = st.chat_id
		local media_msg_id = last.id
		if media_msg_id and type(media_msg_id) == "number" then
			server.get_media_async(media_chat_id, media_msg_id, function(res)
				if media_chat_id ~= st.chat_id then return end
				if res and res.path and #res.path > 0 then
					for _, m in ipairs(st.messages) do
						if tostring(m.id) == tostring(media_msg_id) then
							if res.mediaPath and #res.mediaPath > 0 then
								m.mediaPath = res.mediaPath
								m.filePath = res.mediaPath
							else
								m.filePath = res.path
							end
							ui.render()
							break
						end
					end
				end
			end)
		end
	end
end

local function queue_msg(msg)
	table.insert(msg_queue, msg)
	if msg_timer then
		vim.fn.timer_stop(msg_timer)
	end
	msg_timer = vim.fn.timer_start(100, flush_msg_queue, { ["repeat"] = 1 })
end

local refresh_timer = nil
local function stop_refresh_timer()
	if refresh_timer then
		vim.fn.timer_stop(refresh_timer)
		refresh_timer = nil
	end
end
local function refresh_groups_list()
	if refresh_timer then
		vim.fn.timer_stop(refresh_timer)
	end
	refresh_timer = vim.fn.timer_start(500, function()
		refresh_timer = nil
		server.get_chats_async(function(chats)
			if chats then
				ui.set_groups(chats)
			end
		end)
	end, { ["repeat"] = 1 })
end

local function finish_init()
	ws.ws_start(function(msg)
		if msg.event == "newMessage" then
			queue_msg(msg)
		elseif msg.event == "userAction" then
			local action_chat_id = msg.chat_id
			if ui.state.chat_id and action_chat_id == ui.state.chat_id then
				vim.schedule(function()
					if ui.state.chat_id ~= action_chat_id then return end
					if msg.action._ == "chatActionCancel" then
						ui.set_typing(action_chat_id, msg.user_id, nil, nil, false)
					else
						ui.set_typing(action_chat_id, msg.user_id, msg.user_name, msg.action._, true)
					end
				end)
			end
		elseif msg.event == "chatOnlineMemberCount" then
			local om_chat_id = msg.chat_id
			local om_count = msg.online_member_count
			vim.schedule(function()
				if ui.state.chat_id and om_chat_id == ui.state.chat_id and om_count and om_count > 0 then
					ui.set_online_count(om_count)
				end
				ui.update_group_online(om_chat_id, om_count)
			end)
		elseif msg.event == "messageSendSucceeded" then
			local old_id = msg.old_message_id
			local snd_chat_id = msg.chat and msg.chat.id
			if old_id then
				vim.schedule(function()
					if snd_chat_id and ui.state.chat_id ~= snd_chat_id then return end
					for i, m in ipairs(ui.state.messages) do
						if tonumber(m.id) == tonumber(old_id) then
							ui.state.messages[i] = {
								id = msg.id,
								type = msg.type,
								date = msg.date,
								sender = msg.sender,
								text = msg.text,
								own = msg.own,
								replyTo = msg.replyTo,
								filePath = msg.filePath,
								mediaPath = msg.mediaPath,
								mimeType = msg.mimeType,
							}
							ui.render()
							break
						end
					end
				end)
			end
		elseif msg.event == "messageSendFailed" then
			local old_id = msg.old_message_id
			local fail_chat_id = msg.chat_id
			if old_id then
				vim.schedule(function()
					if fail_chat_id and ui.state.chat_id ~= fail_chat_id then return end
					for i, m in ipairs(ui.state.messages) do
						if tonumber(m.id) == tonumber(old_id) then
							table.remove(ui.state.messages, i)
							ui.render()
							break
						end
					end
					vim.notify("Message send failed: " .. (msg.error_message or "Unknown error"), vim.log.levels.WARN, { title = "tg" })
				end)
			end
		elseif msg.event == "messageContentUpdated" then
			local mcu_chat_id = msg.chat_id
			vim.schedule(function()
				if not mcu_chat_id or mcu_chat_id ~= ui.state.chat_id then return end
				local mid = tostring(msg.message_id)
				local pending = ui.state._pending_edit and ui.state._pending_edit[mid]
				for _, m in ipairs(ui.state.messages) do
					if tostring(m.id) == mid then
						if not pending then
							m.text = msg.text or ""
						end
						m.type = msg.type or m.type
						ui.render()
						break
					end
				end
			end)
		elseif msg.event == "messagesDeleted" then
			local del_chat_id = msg.chat_id
			vim.schedule(function()
				if not del_chat_id or del_chat_id ~= ui.state.chat_id then return end
				local ids = {}
				for _, id in ipairs(msg.message_ids) do
					ids[tostring(id)] = true
				end
				local i = 1
				while i <= #ui.state.messages do
					if ids[tostring(ui.state.messages[i].id)] then
						table.remove(ui.state.messages, i)
					else
						i = i + 1
					end
				end
				ui.render()
			end)
		elseif msg.event == "messageReactions" then
			local mr_chat_id = msg.chat_id
			vim.schedule(function()
				if not mr_chat_id or mr_chat_id ~= ui.state.chat_id then return end
				local mid = tostring(msg.message_id)
				for _, m in ipairs(ui.state.messages) do
					if tostring(m.id) == mid then
						m.reactions = msg.reactions
						ui.render()
						break
					end
				end
			end)
		elseif msg.event == "chatLastMessageUpdated" then
			local clm_chat_id = msg.chat_id
			vim.schedule(function()
				if clm_chat_id and ui.state.groups[clm_chat_id] then
					local g = ui.state.groups[clm_chat_id]
					if type(msg.last_message) == "table" then
						local lm = msg.last_message
						local sender = type(lm.sender) == "table" and lm.sender.name or "?"
						g.last_msg = ("[%s] %s: %s"):format(
							os.date("%Y-%m-%d %H:%M", lm.date),
							sender,
							(lm.text or ""):gsub("\n", " "):sub(1, 40)
						)
					else
						g.last_msg = nil
					end
					ui.update_title()
				end
			end)
		elseif msg.event == "chatReadInbox" then
			vim.schedule(function()
				if msg.chat_id and ui.state.groups[msg.chat_id] then
					ui.state.groups[msg.chat_id].unread_count = msg.unread_count or 0
					if msg.chat_id == ui.state.chat_id then
						ui.state.unread = msg.unread_count or 0
						ui.update_title()
					end
					debounced_redraw()
				end
			end)
		elseif msg.event == "chatUnreadMentionCount" then
			vim.schedule(function()
				if msg.chat_id and ui.state.groups[msg.chat_id] then
					ui.state.groups[msg.chat_id].mention_count = msg.unread_mention_count or 0
				end
			end)
		elseif msg.event == "chatTitle" then
			vim.schedule(function()
				if msg.chat_id and ui.state.groups[msg.chat_id] then
					ui.state.groups[msg.chat_id].title = msg.title
					if msg.chat_id == ui.state.chat_id then
						ui.state.chat_title = msg.title
						ui.update_title()
					end
				end
			end)
		elseif msg.event == "chatPermissions" then
			vim.schedule(function()
				if msg.chat_id == ui.state.chat_id then
					ui.state.default_restricted = msg.default_restricted or false
					if msg.can_send_messages ~= nil then
						ui.state.permissions.can_send_messages = msg.can_send_messages
					end
					ui.update_title()
				end
			end)
		elseif msg.event == "ChatPinnedMessage" then
			vim.schedule(function()
				ui.refresh_pinned_message(msg.chat_id, msg.pinned_message_id)
			end)
		elseif msg.event == "userUpdate" then
			local uid = msg.user_id
			local name = msg.name or ""
			local orig_chat_id = ui.state.chat_id
			if uid and name and #name > 0 then
				vim.schedule(function()
					local need_render = false
					if ui.state.chat_id == orig_chat_id then
						for _, m in ipairs(ui.state.messages) do
							if m.sender and m.sender.id and tonumber(m.sender.id) == tonumber(uid) then
								m.sender.name = name
								need_render = true
							end
						end
					end
					local found_group = false
					for _, g in pairs(ui.state.groups) do
						if g.user_id and g.user_id == uid then
							g.title = name
							found_group = true
							if ui.state.chat_id == g.id then
								ui.state.chat_title = name
								ui.update_title()
								need_render = false
							end
							break
						end
					end
					if need_render then
						ui.render()
					end
				end)
			end
		elseif msg.event == "userStatus" then
			vim.schedule(function()
	local uid = msg.user_id
	if not uid then return end
	if ui.state.chat_id ~= uid then
		for _, g in pairs(ui.state.groups) do
			if g.user_id == uid then
							g.online_count = msg.is_online and 1 or 0
							if g.id == ui.state.chat_id then
								ui.set_online_count(g.online_count)
							end
							break
						end
					end
					return
				end
				ui.set_online_count(msg.is_online and 1 or 0)
			end)
		elseif msg.event == "chatGroupInfo" then
			vim.schedule(function()
				local cid = msg.chat_id
				if cid and ui.state.groups[cid] then
					ui.state.groups[cid].description = msg.description or ""
					ui.state.groups[cid].member_count = msg.member_count or 0
					if cid == ui.state.chat_id then
						ui.state.description = msg.description or ""
						ui.update_title()
					end
				end
			end)
		elseif msg.event == "chatPosition" then
			local order = msg.order
			local cid = msg.chat_id
			if not cid then return end
			if order == "0" or order == 0 then
				vim.schedule(function()
					if ui.state.groups[cid] then
						ui.state.groups[cid] = nil
						for i, id in ipairs(ui.state.group_ids) do
							if id == cid then
								table.remove(ui.state.group_ids, i)
								break
							end
						end
					end
					if ui.state.chat_id == cid then
						ui.destroy_chat()
					end
				end)
			end
		elseif msg.event == "chatGroupRemoved" then
			local cid = msg.chat_id
			if cid then
				vim.schedule(function()
					if ui.state.groups[cid] then
						ui.state.groups[cid] = nil
						for i, id in ipairs(ui.state.group_ids) do
							if id == cid then
								table.remove(ui.state.group_ids, i)
								break
							end
						end
					end
					if ui.state.chat_id == cid then
						ui.destroy_chat()
					end
				end)
			end
		elseif msg.event == "NewChat" then
			refresh_groups_list()
		elseif msg.event == "chatMember" then
			local ns = msg.new_status and msg.new_status._
			if ns == "chatMemberStatusLeft" or ns == "chatMemberStatusBanned" then
				local cid = msg.chat_id
				local mid = msg.member and msg.member.id
				if cid and mid and ui.state.my_user_id and mid == ui.state.my_user_id then
					vim.schedule(function()
						if ui.state.groups[cid] then
							ui.state.groups[cid] = nil
							for i, id in ipairs(ui.state.group_ids) do
								if id == cid then
									table.remove(ui.state.group_ids, i)
									break
								end
							end
						end
						if ui.state.chat_id == cid then
							ui.destroy_chat()
						end
						vim.notify("Removed from " .. (msg.chat_title or "chat"), vim.log.levels.INFO, { title = "tg" })
					end)
				else
					refresh_groups_list()
				end
			end
		elseif msg.event == "authState" then
			if msg.state == "authorizationStateClosed" or msg.state == "authorizationStateLoggingOut" then
				ui.destroy_chat()
				ui.state.last_group = nil
				ws.ws_stop()
				initialized = false
				vim.notify("Session closed from another device", vim.log.levels.WARN, { title = "tg" })
			end
		end
	end)
	initialized = true
	vim.notify("Ready", vim.log.levels.INFO, { title = "tg" })
end

local function finish_open(chats)
	ui.set_groups(chats or {})
	ui.destroy_chat()
	if chats and #chats > 0 then
		local last = ui.state.last_group
		if last and ui.state.groups[last.id] then
			ui.open_chat(last.id, last.title)
		else
			ui.open_chat(chats[1].id, chats[1].title)
		end
	end
end

local poll_cancelled = false
local function poll_chats(remaining, chats)
	if remaining <= 0 then
		finish_open(chats or {})
		return
	end
	chats = server.get_chats()
	if chats and #chats > 1 then
		finish_open(chats)
		return
	end
	vim.defer_fn(function()
		if poll_cancelled then return end
		poll_chats(remaining - 1, chats)
	end, 1000)
end

function M.list_groups()
	local function show_groups()
		if ui.state.buf and not vim.api.nvim_buf_is_valid(ui.state.buf) then
			ui.state.buf = nil
			ui.state.win = nil
			ui.state.mounted = false
		end

		if ui.state.mounted then
			ui.refresh_messages()
			return
		end

		local chats = server.get_chats()
		if not chats then
			vim.notify("No chats found", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if #chats <= 1 then
			vim.notify("Syncing chats, please wait...", vim.log.levels.INFO, { title = "tg" })
			poll_chats(15, chats)
			return
		end
		finish_open(chats)
	end

	if not initialized then
		if starting then return end
		poll_cancelled = false
		starting = true
		vim.notify("Starting server...", vim.log.levels.INFO, { title = "tg" })
		vim.defer_fn(function()
			if not config.ensure_deps() then
				starting = false
				return
			end
			if not server.start_server() then
				starting = false
				return
			end
			local health = server.server_health()
			if health and health.ready == true then
				finish_init()
				show_groups()
			else
				vim.notify("Waiting for auth...", vim.log.levels.INFO, { title = "tg" })
				auth.auth_poll(function(success)
					starting = false
					if success then
						finish_init()
						show_groups()
					else
						server.stop_server()
						local db = config.config.data_dir .. "/tdlib_db"
						local files = config.config.data_dir .. "/tdlib_files"
						vim.fn.delete(db, "rf")
						vim.fn.delete(files, "rf")
					end
				end)
			end
		end, 100)
		return
	end

	if ui.state.win and vim.api.nvim_win_is_valid(ui.state.win) then
		ui.toggle_off()
		return
	end

	local chats = server.get_chats()
	if chats and #chats > 0 then
		local last = ui.state.last_group
		if last and ui.state.groups[last.id] then
			ui.open_chat(last.id, last.title)
		else
			ui.open_chat(chats[1].id, chats[1].title)
		end
	else
		vim.notify("No chats available", vim.log.levels.WARN, { title = "tg" })
	end
end

function M.logout()
	stop_refresh_timer()
	vim.notify("Logging out and clearing auth data...", vim.log.levels.INFO, { title = "tg" })
	ui.destroy_chat()
	ui.state.last_group = nil
	poll_cancelled = true
	server.stop_server()
	local db_dir = config.config.data_dir .. "/tdlib_db"
	local files_dir = config.config.data_dir .. "/tdlib_files"
	vim.fn.delete(db_dir, "rf")
	vim.fn.delete(files_dir, "rf")
	initialized = false
	vim.notify("Logged out. Run :Tg again to re-authenticate", vim.log.levels.INFO, { title = "tg" })
end

-- API re-exports
M.get_chats = server.get_chats
M.get_groups = server.get_groups
M.get_messages = server.get_messages
M.send_message = server.send_message
M.edit_message = server.edit_message
M.delete_message = server.delete_message
M.forward_messages = server.forward_messages
M.ws_start = ws.ws_start
M.ws_stop = ws.ws_stop
M.open_chat = ui.open_chat
M.status = server.status
M.status_color = server.status_color

local function unread_counts()
	local total, mentions = 0, 0
	for _, g in pairs(ui.state.groups) do
		total = total + (g.unread_count or 0)
		mentions = mentions + (g.mention_count or 0)
	end
	return total, mentions
end

M.total_unread = unread_counts

M.lualine = {
	function()
		local total, mentions = unread_counts()
		if mentions > 0 then
			return "  " .. total .. "!"
		end
		if total > 0 then
			return "  " .. total
		end
		return "  "
	end,
	cond = function() return true end,
	color = function()
		local _, mentions = unread_counts()
		if mentions > 0 then return { fg = "#f38ba8" } end
		local c = { disconnected = "#6c7086", connecting = "#f9e2af", connected = "#a6e3a1", error = "#f38ba8" }
		return { fg = c[M.status()] or c.disconnected }
	end,
}

-- Cleanup on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("TgCleanup", { clear = true }),
	callback = function()
		stop_refresh_timer()
		ui.destroy_chat()
		ws.ws_stop()
		server.stop_server()
	end,
})

vim.api.nvim_create_user_command("Tg", M.list_groups, {})
vim.api.nvim_create_user_command("TgLogout", M.logout, {})
vim.api.nvim_create_user_command("TgTool", function()
	tools.pick()
end, {})

vim.api.nvim_create_user_command("TgSend", function(opts)
	local args = vim.fn.split(opts.args)
	local chat_id, text
	if #args == 1 then
		chat_id = ui.state.chat_id
		text = args[1]
	else
		chat_id = tonumber(args[1])
		text = table.concat(args, " ", 2)
	end
	if not chat_id then
		vim.notify("No chat open and no chatId provided", vim.log.levels.ERROR, { title = "tg" })
		return
	end
	if not text or #text == 0 then
		vim.notify("Text is required", vim.log.levels.ERROR, { title = "tg" })
		return
	end
	local sent = server.send_message(chat_id, text)
	if sent then
		table.insert(ui.state.messages, sent)
		ui.render()
	else
		vim.notify("Failed to send message", vim.log.levels.ERROR, { title = "tg" })
	end
end, { nargs = "+" })

return M
