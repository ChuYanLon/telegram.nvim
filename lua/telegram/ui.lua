local Editor = require("telegram.editor")
local server = require("telegram.server")
local render_msg = require("telegram.render").render

local M = {}

local state = {
	buf = nil,
	win = nil,
	chat_id = nil,
	chat_title = "",
	messages = {},
	loading = false,
	exhausted = false,
	unread = 0,
	last_chat = nil,
	last_msg = nil,
	online_count = nil,
	typing_users = {},

	mounted = false,
	groups = {},
	group_ids = {},

	input_mode = "send",
	reply_to = nil,
	edit_target = nil,
	delete_target = nil,
	forward_target = nil,
	esc_count = 0,
	sending = false,
	loading_newer = false,
	exhausted_forward = false,

	separator_line = "────────────────────",
	_input_start = 0,
}

M.state = state

local SEPARATOR = "────────────────────"
local hl_ns = vim.api.nvim_create_namespace("TgChat")
local target_ns = vim.api.nvim_create_namespace("TgTarget")

local action_descriptions = {
	chatActionTyping = "typing...",
	chatActionRecordingVideo = "recording video...",
	chatActionRecordingVoiceNote = "recording voice...",
	chatActionUploadingVideo = "uploading video...",
	chatActionUploadingVoiceNote = "uploading voice...",
	chatActionUploadingPhoto = "uploading photo...",
	chatActionUploadingDocument = "uploading document...",
	chatActionChoosingSticker = "choosing sticker...",
	chatActionChoosingLocation = "choosing location...",
	chatActionChoosingContact = "choosing contact...",
	chatActionStartPlayingGame = "playing game...",
	chatActionRecordingVideoNote = "recording video note...",
	chatActionUploadingVideoNote = "uploading video note...",
	chatActionWatchingAnimations = "watching animations...",
}

local function fmt_msg(msg)
	return render_msg(msg)
end

local function line_of(target_id)
	for i, m in ipairs(state.messages) do
		if m.id == target_id then
			local line = 1
			for j = 1, i - 1 do
				line = line + #fmt_msg(state.messages[j]) + 1
			end
			return line
		end
	end
end

local function apply_highlights()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local buf = state.buf
	vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, target_ns, 0, -1)
	local total = vim.api.nvim_buf_line_count(buf)

	for line = 0, total - 1 do
		local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
		if not text then
			break
		end

		if text:match("^> [+>~*!-] ") then
			vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgService", line, 0, -1)
		end

		if text:match("^## ") then
			vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgHeader", line, 0, 2)
			local s, e = text:find("(%d+%-%d+ %d+:%d+)$")
			if s then
				vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgTimestamp", line, s - 1, e)
			end
		end

		if text:match("^> %S+:") and not text:match("^> [%+%>%*%~%!%-] ") then
			local _, se = text:find("^> %S+:")
			if se then
				vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgReplyQuote", line, 0, se)
				vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgReplyBg", line, se, -1)
			end
		end

		if text == SEPARATOR then
			vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgSeparator", line, 0, -1)
		end

		if text:match("^```") then
			vim.api.nvim_buf_add_highlight(buf, hl_ns, "TgCodeBlock", line, 0, -1)
		end
	end

	local target_id = state.reply_to
		or (state.edit_target and state.edit_target.id)
		or (state.delete_target and state.delete_target.id)
		or (state.forward_target and state.forward_target.id)
	local mode = state.reply_to and "reply"
		or (state.edit_target and "edit")
		or (state.delete_target and "delete")
		or (state.forward_target and "forward")
	if not target_id or not mode then
		return
	end
	local hl = mode == "reply" and "TgReplyTarget"
		or mode == "edit" and "TgEditTarget"
		or mode == "delete" and "TgDeleteTarget"
		or "TgForwardTarget"
	local label = mode == "reply" and "  \xE2\x97\x8F Replying"
		or mode == "edit" and "  \xE2\x97\x8F Editing"
		or mode == "delete" and "  \xE2\x97\x8F Deleting"
		or "  \xE2\x97\x8F Forwarding"
	local line = 1
	for _, m in ipairs(state.messages) do
		local n = #fmt_msg(m)
		if m.id == target_id then
			local start_line = line - 1
			local end_line = line + n - 2
			for l = start_line, end_line do
				vim.api.nvim_buf_add_highlight(buf, hl_ns, hl, l, 0, -1)
			end
			local last = end_line >= start_line and end_line or start_line
			vim.api.nvim_buf_set_extmark(buf, target_ns, last, 0, {
				virt_lines = { { { label, hl } } },
			})
			break
		end
		line = line + n + 1
	end
end

local function render()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local buf = state.buf

	local lines = {}
	for _, msg in ipairs(state.messages) do
		local msg_lines = fmt_msg(msg)
		for _, l in ipairs(msg_lines) do
			table.insert(lines, l)
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false

	apply_highlights()
end

M.render = render

function M.set_groups(groups)
	local new_groups = {}
	local new_ids = {}
	for _, g in ipairs(groups or {}) do
		local existing = state.groups[g.id]
		new_groups[g.id] = {
			id = g.id,
			title = g.title,
			unread_count = (existing and existing.unread_count) or g.unreadCount or 0,
		}
		table.insert(new_ids, g.id)
	end
	state.groups = new_groups
	state.group_ids = new_ids
end

function M.set_typing(chat_id, user_id, user_name, action_type, active)
	if chat_id ~= state.chat_id or not user_id then
		return
	end
	if active then
		state.typing_users[user_id] =
			{ name = user_name or "Unknown", action_desc = action_descriptions[action_type] or "typing..." }
	else
		state.typing_users[user_id] = nil
	end
	M.update_title()
end

function M.set_online_count(count)
	state.online_count = count
	M.update_title()
end

function M.update_group_last_msg(chat_id, sender_name, text)
	if not state.groups[chat_id] then
		return
	end
	if chat_id ~= state.chat_id then
		state.groups[chat_id].unread_count = (state.groups[chat_id].unread_count or 0) + 1
	end
end

function M.update_group_online(chat_id, count)
	if state.groups[chat_id] then
		state.groups[chat_id].online_count = count
	end
end

function M.update_title()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local title = ""
	if state.chat_title and #state.chat_title > 0 then
		title = state.chat_title
	end
	local typing_items = {}
	for _, info in pairs(state.typing_users) do
		table.insert(typing_items, info)
	end
	if #typing_items > 0 then
		if #typing_items == 1 then
			title = title .. " | " .. typing_items[1].name .. " " .. typing_items[1].action_desc
		else
			title = title
				.. " | "
				.. typing_items[1].name
				.. " +"
				.. (#typing_items - 1)
				.. " "
				.. typing_items[1].action_desc
		end
	end
	title = title .. " | " .. (state.online_count or 0) .. " online"
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		local safe = title:gsub("[^%w%p]", "_"):sub(1, 60)
		pcall(vim.api.nvim_buf_set_name, state.buf, "/tmp/tg-" .. safe)
	end
end

local function show_group_selector()
	local items = {}
	for _, id in ipairs(state.group_ids) do
		local g = state.groups[id]
		if g then
			table.insert(items, { id = g.id, label = g.title })
		end
	end
	if #items == 0 then
		vim.notify("No groups available", vim.log.levels.INFO, { title = "tg" })
		return
	end
	vim.ui.select(items, {
		prompt = "@ Groups",
		format_item = function(item)
			local g = state.groups[item.id]
			local suffix = ""
			if g and g.unread_count and g.unread_count > 0 then
				suffix = "  \xE2\x97\x8F +" .. g.unread_count
			end
			return item.label .. suffix
		end,
	}, function(choice)
		if choice then
			M.open_chat(choice.id, choice.label)
		end
	end)
end

local function input_send()
	if not state.editor or state.sending then
		return
	end
	state.sending = true
	local text = state.editor:get_text()
	if #text == 0 then
		state.sending = false
		return
	end
	if state.input_mode == "edit" and state.edit_target then
		local target = state.edit_target
		local ok = server.edit_message(state.chat_id, target.id, text)
		if ok then
			target.text = text
			vim.notify("Message edited", vim.log.levels.INFO, { title = "tg" })
		end
		state.editor:clear()
		state.input_mode = "send"
		state.reply_to = nil
		state.edit_target = nil
		state.sending = false
		render()
		return
	end
	local function insert_msg(msg)
		if not msg then
			return
		end
		local id = msg.id
		if id ~= nil then
			id = tostring(id)
			for _, m in ipairs(state.messages) do
				if m.id ~= nil and tostring(m.id) == id then
					return
				end
			end
		end
		table.insert(state.messages, msg)
	end
	if state.input_mode == "reply" and state.reply_to then
		local msg = server.send_message(state.chat_id, text, state.reply_to)
		insert_msg(msg)
		render()
		if msg then
			vim.notify("Reply sent", vim.log.levels.INFO, { title = "tg" })
		end
	else
		local msg = server.send_message(state.chat_id, text)
		insert_msg(msg)
		render()
		if msg then
			vim.notify("Message sent", vim.log.levels.INFO, { title = "tg" })
		end
	end
	state.editor:clear()
	state.input_mode = "send"
	state.reply_to = nil
	state.edit_target = nil
	state.sending = false
	apply_highlights()
end

local function focus_input()
	if state.editor then
		state.editor:focus()
	end
end

local function cur_area()
	local win = vim.api.nvim_get_current_win()
	if state.win and win == state.win then
		return "msg"
	end
	return "msg"
end

local function setup_chat_keymaps()
	local buf = state.buf
	vim.keymap.set("n", "<C-w>", "<Nop>", { buffer = buf })
end

local function setup_input_keymaps() end

local help_popup = nil

local function close_help()
	if help_popup then
		help_popup:unmount()
		help_popup = nil
	end
end

M.close_help = close_help

function M.show_help()
	close_help()
	local NuiPopup = require("nui.popup")
	help_popup = NuiPopup({
		relative = "editor",
		position = { row = "50%", col = "50%" },
		size = { width = 36, height = 26 },
		zindex = 200,
		border = { style = "rounded", text = { top = " Help ", top_align = "center" } },
		buf_options = { buftype = "nofile", bufhidden = "wipe" },
		win_options = { winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder" },
		enter = true,
		focusable = true,
	})
	local lines = {
		"-- Navigation --",
		" i        focus input",
		" @        switch group",
		" /        search history",
		"",
		"-- Messages --",
		" <CR>     reply / jump to original",
		" e        edit own message",
		" d        delete / revoke",
		" f        forward",
		" r        refresh",
		"",
		"-- General --",
		" ?        help",
		" Esc Esc  close chat",
		" q        quit plugin",
		"",
		"-- Input --",
		" <CR>     send message",
		" Esc      cancel reply/edit",
	}
	help_popup:mount()
	vim.api.nvim_buf_set_lines(help_popup.bufnr, 0, -1, false, lines)
	vim.keymap.set("n", "<Esc>", close_help, { buffer = help_popup.bufnr, nowait = true })
	vim.keymap.set("n", "q", close_help, { buffer = help_popup.bufnr, nowait = true })
	vim.keymap.set("n", "?", close_help, { buffer = help_popup.bufnr, nowait = true })
end

function M.open_chat(chat_id, chat_title)
	chat_title = chat_title or "Chat"

	if state.buf and not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = nil
		state.win = nil
		state.mounted = false
	end

	if state.chat_id == chat_id and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			M.update_title()
			return
		end
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		vim.wo[state.win].wrap = true
		state.mounted = true
		M.update_title()
		return
	end

	M.close_chat()

	state.chat_id = chat_id
	state.chat_title = chat_title
	if state.groups[chat_id] then
		state.groups[chat_id].unread_count = 0
	end

	state.buf = vim.api.nvim_create_buf(true, false)
	vim.bo[state.buf].filetype = "markdown"
	local safe_name = chat_title:gsub("[^%w%p]", "_"):sub(1, 30)
	vim.api.nvim_buf_set_name(state.buf, "/tmp/tg-" .. safe_name)

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = vim.api.nvim_create_augroup("TgBufCleanup", { clear = false }),
		pattern = "/tmp/tg-*",
		callback = function()
			state.buf = nil
			state.win = nil
			state.mounted = false
		end,
	})

	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.win, state.buf)
	vim.wo[state.win].wrap = true

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = vim.api.nvim_create_augroup("TgBufWrite", { clear = true }),
		buffer = state.buf,
		callback = function()
			vim.bo[state.buf].modified = false
		end,
	})

	state.mounted = true

	server.open_chat(state.chat_id)
	render()

	M.refresh_messages(function()
		if #state.messages > 0 then
			local total = 1
			for _, msg in ipairs(state.messages) do
				total = total + #fmt_msg(msg) + 1
			end
			M.jump_to_bottom()
		end
	end)

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = vim.api.nvim_create_augroup("TgChatScroll", { clear = true }),
		buffer = state.buf,
		callback = function()
			if not state.win or not vim.api.nvim_win_is_valid(state.win) then
				return
			end
			if vim.api.nvim_get_current_win() ~= state.win then
				return
			end
			local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
			local total_lines = vim.api.nvim_buf_line_count(state.buf)
			if state.unread > 0 and cursor_line >= total_lines - 1 then
				state.unread = 0
			end
			if cursor_line <= 1 and not state.exhausted then
				M.load_older()
			elseif cursor_line >= total_lines - 1 and not state.exhausted_forward then
				M.load_newer()
			end
		end,
	})
end

function M.jump_to_bottom()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local total = vim.api.nvim_buf_line_count(state.buf)
	pcall(vim.api.nvim_win_set_cursor, state.win, { total - 1, 0 })
end

function M.close_chat()
	close_help()
	if state.chat_id then
		state.last_chat = { id = state.chat_id, title = state.chat_title }
		server.close_chat(state.chat_id)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		local safe = (state.chat_title or "chat"):gsub("[^%w%p]", "_"):sub(1, 30)
		pcall(vim.api.nvim_buf_set_name, state.buf, "/tmp/tg-" .. safe .. "-cached")
	end
	if state.editor then
		state.editor:set_winid(nil)
	end
	state.mounted = false
end

function M.destroy_chat()
	M.close_chat()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local curbuf = vim.api.nvim_win_get_buf(state.win)
		if curbuf == state.buf then
			vim.cmd("enew")
		end
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.buf = nil
	state.editor = nil
	state.messages = {}
	state.loading = false
	state.exhausted = false
	state.exhausted_forward = false
	state.online_count = nil
	state.typing_users = {}
	state.chat_id = nil
	state.chat_title = ""
	state.win = nil
end

function M.message_at_cursor()
	if not state.win then
		return nil
	end
	local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
	local line = 1
	for idx, msg in ipairs(state.messages) do
		local n = #fmt_msg(msg)
		if cursor_line >= line and cursor_line < line + n then
			return idx
		end
		line = line + n + 1
	end
	return nil
end

function M.curr_msg()
	local i = M.message_at_cursor()
	return i and state.messages[i]
end

function M.jump_to_message(target_id, callback)
	local l = line_of(target_id)
	if l then
		pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		if callback then
			callback(true)
		end
		return
	end
	state.messages = {}
	state.exhausted = false
	state.exhausted_forward = false
	server.get_messages_around_async(state.chat_id, target_id, 31, function(data)
		if not state.chat_id then
			return
		end
		state.messages = data.messages or {}
		render()
		local l = line_of(target_id)
		if l then
			pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		end
		if callback then
			callback(true)
		end
	end, function()
		vim.notify("Failed to load message context", vim.log.levels.ERROR, { title = "tg" })
		if callback then
			callback(false)
		end
	end)
end

function M.load_older()
	if state.loading or state.exhausted or #state.messages == 0 then
		return
	end
	state.loading = true
	local chat_id = state.chat_id
	local oldest_id = state.messages[1].id
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local old_top = cursor[1]
	server.get_messages_async(chat_id, server.DEFAULT_LIMIT, oldest_id, function(data)
		if state.chat_id ~= chat_id then
			state.loading = false
			return
		end
		local new_msgs = data.messages or {}
		if #new_msgs == 0 then
			state.exhausted = true
			state.loading = false
			return
		end
		local new_lines = 0
		local seen = {}
		for _, m in ipairs(state.messages) do
			seen[tostring(m.id)] = true
		end
		for i = 1, #new_msgs do
			if not seen[tostring(new_msgs[i].id)] then
				seen[tostring(new_msgs[i].id)] = true
				table.insert(state.messages, 1, new_msgs[i])
				new_lines = new_lines + #fmt_msg(new_msgs[i]) + 1
			end
		end
		if state.chat_id ~= chat_id then
			state.loading = false
			return
		end
		if new_lines > 0 then
			render()
			pcall(vim.api.nvim_win_set_cursor, state.win, { old_top + new_lines, cursor[2] })
		end
		state.loading = false
	end, function()
		state.loading = false
	end)
end

function M.load_newer()
	if state.loading_newer or state.exhausted_forward or #state.messages == 0 then
		return
	end
	state.loading_newer = true
	local chat_id = state.chat_id
	local newest_id = state.messages[#state.messages].id
	server.get_messages_after_async(chat_id, newest_id, server.DEFAULT_LIMIT, function(data)
		if state.chat_id ~= chat_id then
			state.loading_newer = false
			return
		end
		local new_msgs = data.messages or {}
		if #new_msgs == 0 then
			state.exhausted_forward = true
			state.loading_newer = false
			return
		end
		local seen = {}
		for _, m in ipairs(state.messages) do
			seen[tostring(m.id)] = true
		end
		for _, m in ipairs(new_msgs) do
			if not seen[tostring(m.id)] then
				seen[tostring(m.id)] = true
				table.insert(state.messages, m)
			end
		end
		if #new_msgs > 0 then
			render()
		end
		state.loading_newer = false
	end, function()
		state.loading_newer = false
	end)
end

function M.refresh_messages(on_complete)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	state.loading = false
	state.exhausted = false
	state.exhausted_forward = false
	local chat_id = state.chat_id
	server.get_messages_async(chat_id, 10, nil, function(data)
		if state.chat_id ~= chat_id then
			return
		end
		local raw = data.messages or {}
		state.messages = {}
		local seen = {}
		for i = #raw, 1, -1 do
			local msg = raw[i]
			if not seen[tostring(msg.id)] then
				seen[tostring(msg.id)] = true
				table.insert(state.messages, msg)
			end
		end
		if state.chat_id ~= chat_id then
			return
		end
		render()
		if #state.messages > 0 then
			local latest = state.messages[#state.messages]
			local ts = os.date("%m-%d %H:%M", latest.date)
			state.last_msg = "["
				.. ts
				.. "] "
				.. (latest.sender and latest.sender.name or "?")
				.. ": "
				.. (latest.text or "")
			server.view_messages(state.chat_id, latest.id)
		end
		if on_complete then
			on_complete()
		end
	end, function()
		vim.notify("Failed to load messages", vim.log.levels.ERROR, { title = "tg" })
		if on_complete then
			on_complete()
		end
	end)
end

return M
