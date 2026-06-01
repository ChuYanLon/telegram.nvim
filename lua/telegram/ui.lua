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

	group_cursor = 1,
	permissions = {},
	my_user_id = nil,
	default_restricted = false,

	pinned_message = nil,
	pinned_message_id = nil,

	title_buf = nil,
	title_win = nil,
	title_height = 0,

	msg_line_counts = {},
	_title_update_timer = nil,
	title_dirty = false,
}

M.state = state

local hl_ns = vim.api.nvim_create_namespace("TgChat")
local target_ns = vim.api.nvim_create_namespace("TgTarget")

vim.api.nvim_create_autocmd("BufUnload", {
	pattern = "/tmp/tg-*",
	callback = function()
		if state.chat_id then
			state.last_group = { id = state.chat_id, title = state.chat_title }
		end
	end,
})

local function hide_chat()
	state.buf = nil
	destroy_title_float()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	state.mounted = false
end

local function open_split()
	if vim.o.splitright then
		vim.cmd("botright vsplit")
	else
		vim.cmd("topleft vsplit")
	end
end

local function destroy_title_float()
	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_close, state.title_win, true)
	end
	state.title_win = nil
	if state.title_buf and vim.api.nvim_buf_is_valid(state.title_buf) then
		pcall(vim.api.nvim_buf_delete, state.title_buf, { force = true })
	end
	state.title_buf = nil
end

function M.toggle_off()
	if state.chat_id then
		state.last_group = { id = state.chat_id, title = state.chat_title }
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_set_current_win, state.win)
		local wins = vim.api.nvim_list_wins()
		if #wins > 1 then
			vim.cmd("hide")
		else
			vim.cmd("enew")
		end
	end
	state.win = nil
	state.buf = nil
	state.mounted = false
	destroy_title_float()
end

local function hide_title_float()
	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_close, state.title_win, true)
	end
	state.title_win = nil
end

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

local function title_offset()
	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		return vim.api.nvim_win_get_height(state.title_win)
	end
	return state.title_height or 0
end

local function line_of(target_id)
	local off = title_offset()
	local line_counts = state.msg_line_counts
	for i, m in ipairs(state.messages) do
		if m.id == target_id then
			local line = 1 + off
			for j = 1, i - 1 do
				line = line + (line_counts[j] or #fmt_msg(state.messages[j]))
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
	local off = title_offset()
	vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, target_ns, 0, -1)

	for l = 0, vim.api.nvim_buf_line_count(buf) - 1 do
		local line = vim.api.nvim_buf_get_lines(buf, l, l + 1, false)[1]
		if line and line:find("^%[[%+%-%~%*%>!]%]") then
			pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "TgService", l, 0, -1)
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
	local line = 1 + off
	local line_counts = state.msg_line_counts
	for i, m in ipairs(state.messages) do
		local n = line_counts[i] or #fmt_msg(m)
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
		line = line + n
	end
end

local function render()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local buf = state.buf

	local lines = {}
	local line_counts = {}
	for i, msg in ipairs(state.messages) do
		local msg_lines = fmt_msg(msg)
		local n = #msg_lines
		line_counts[i] = n
		for _, l in ipairs(msg_lines) do
			table.insert(lines, l)
		end
	end
	state.msg_line_counts = line_counts

	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		state.title_height = vim.api.nvim_win_get_height(state.title_win)
	end
	for _ = 1, state.title_height do
		table.insert(lines, 1, "")
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false

	apply_highlights()
end

M.render = render

function M.append_message(msg)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local buf = state.buf
	local msg_lines = fmt_msg(msg)
	if #msg_lines == 0 then
		return
	end
	vim.bo[buf].modifiable = true
	local total = vim.api.nvim_buf_line_count(buf)
	if total == 0 then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, msg_lines)
	else
		table.insert(msg_lines, 1, "")
		vim.api.nvim_buf_set_lines(buf, total - 1, -1, false, msg_lines)
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
end

local function show_groups_picker(on_select)
	local items = {}
	for _, id in ipairs(state.group_ids) do
		local g = state.groups[id]
		if g then
			table.insert(items, {
				id = g.id,
				title = g.title,
				type = g.type or "group",
				unread = g.unread_count or 0,
			})
		end
	end
	if #items == 0 then
		vim.notify("No chats available", vim.log.levels.INFO, { title = "tg" })
		return
	end

	local ok, snacks = pcall(require, "snacks")
	if ok and snacks.picker then
		local picker_items = {}
		for _, item in ipairs(items) do
			table.insert(picker_items, {
				id = item.id,
				text = item.title,
				unread = item.unread,
			})
		end
		local picked = false
		snacks.picker.pick({
			title = "Chats",
			items = picker_items,
			layout = "select",
			format = function(item)
				local label = item.text
				if item.unread > 0 then
					label = label .. "  \xE2\x97\x8F +" .. item.unread
				end
				return { { label } }
			end,
			confirm = function(picker, item)
				picked = true
				picker:close()
				if item then
					on_select({ id = item.id, title = item.text, unread = item.unread })
				else
					on_select(nil)
				end
			end,
			on_close = function()
				if not picked then
					on_select(nil)
				end
			end,
		})
	else
		vim.ui.select(items, {
			prompt = "Select chat:",
			format_item = function(item)
				local label = item.title
				if item.type == "channel" then
					label = "# " .. label
				elseif item.type == "private" then
					label = "\xE2\x9C\x89 " .. label
				end
				if item.unread > 0 then
					label = label .. "  \xE2\x97\x8F +" .. item.unread
				end
				return label
			end,
		}, function(item)
			if item then
				on_select({ id = item.id, title = item.title, unread = item.unread })
			else
				on_select(nil)
			end
		end)
	end
end

function M.set_groups(groups)
	local new_groups = {}
	local new_ids = {}
	for _, g in ipairs(groups or {}) do
		local existing = state.groups[g.id]
		local existing_online = existing and existing.online_count
		new_groups[g.id] = {
			id = g.id,
			title = g.title,
			type = g.type or "group",
			unread_count = (existing and existing.unread_count) or g.unreadCount or 0,
			member_count = g.memberCount or (existing and existing.member_count) or 0,
			online_count = (existing_online and existing_online > 0 and existing_online) or g.onlineMemberCount or 0,
			user_id = g.userId,
		}
		table.insert(new_ids, g.id)
	end
	state.groups = new_groups
	state.group_ids = new_ids
end

function M.set_typing(chat_id, user_id, user_name, action_type, active)
	if active then
		state.typing_users[chat_id] = state.typing_users[chat_id] or {}
		state.typing_users[chat_id][user_id] =
			{ name = user_name or "Unknown", action_desc = action_descriptions[action_type] or "typing..." }
	else
		if state.typing_users[chat_id] then
			state.typing_users[chat_id][user_id] = nil
			if not next(state.typing_users[chat_id]) then
				state.typing_users[chat_id] = nil
			end
		end
	end
	M.update_title()
end

function M.set_online_count(count)
	state.online_count = count or 0
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
	if state.groups[chat_id] and count and count > 0 then
		state.groups[chat_id].online_count = count
	end
end

function M.refresh_pinned_message(chat_id, pinned_message_id)
	if chat_id ~= state.chat_id then return end
	state.pinned_message_id = pinned_message_id or 0
	if not pinned_message_id or pinned_message_id == 0 then
		state.pinned_message = nil
		M.update_title()
		return
	end
	server.get_pinned_message_async(chat_id, pinned_message_id, function(msg)
		if state.chat_id == chat_id and msg then
			state.pinned_message = msg.text and #msg.text > 0 and msg.text or ("[" .. (msg.type or "media") .. "]")
			M.update_title()
		end
	end)
end

local function truncate_text(text, max_width)
	if not text or #text == 0 then
		return text
	end
	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	local result = ""
	local w = 0
	for char in text:gmatch(".[\128-\191]*") do
		local cw = vim.fn.strdisplaywidth(char)
		if w + cw > max_width - 1 then
			return result .. "…"
		end
		result = result .. char
		w = w + cw
	end
	return result
end

function M.update_title()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_set_name, state.buf, "tg")
	end
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		hide_title_float()
		return
	end
	local title = state.chat_title or ""

	local typing_items = {}
	if state.chat_id and state.typing_users[state.chat_id] then
		for _, info in pairs(state.typing_users[state.chat_id]) do
			table.insert(typing_items, info)
		end
	end
	local typing = ""
	if #typing_items > 0 then
		if #typing_items == 1 then
			typing = typing_items[1].name .. " " .. typing_items[1].action_desc
		else
			typing = typing_items[1].name .. " +" .. (#typing_items - 1) .. " " .. typing_items[1].action_desc
		end
	end

	local win_pos = vim.api.nvim_win_get_position(state.win)
	local win_width = vim.api.nvim_win_get_width(state.win)
	local text_width = win_width - 2

	local has_pinned = state.pinned_message and #state.pinned_message > 0
	local has_desc = state.description and #state.description > 0
	local has_typing = typing ~= ""

	local lines = {}

	-- Line 1: Title (always)
	lines[#lines + 1] = title

	-- Line 2: Status (always)
	local online = state.online_count or 0
	local is_private = state.chat_id and state.groups[state.chat_id] and state.groups[state.chat_id].type == "private"
	if has_typing then
		lines[#lines + 1] = "status: " .. typing
	elseif is_private then
		lines[#lines + 1] = "status: " .. (online > 0 and "online" or "offline")
	else
		local count = tostring(online)
		local total = state.chat_id and state.groups[state.chat_id] and state.groups[state.chat_id].member_count
		if total and total > 0 then
			count = online .. "/" .. total
		end
		if state.unread > 0 then
			count = count .. "  \xE2\x97\x8F+" .. state.unread
		end
		lines[#lines + 1] = "status: " .. count
	end

	-- Line 3: Pinned message (only if present)
	if has_pinned then
		local w = math.max(text_width - 8, 1)
		lines[#lines + 1] = "pinned: " .. truncate_text(state.pinned_message:gsub("\n", " "), w)
	end

	-- Line 4: Description (only if present)
	if has_desc then
		local w = math.max(text_width - 6, 1)
		lines[#lines + 1] = "desc: " .. truncate_text(state.description:gsub("\n", " "), w)
	end

	-- Separator
	local label = " messages "
	local side = string.rep("=", math.floor((text_width - #label) / 2))
	lines[#lines + 1] = side .. label .. side

	local old_h = state.title_win and vim.api.nvim_win_is_valid(state.title_win)
		and vim.api.nvim_win_get_height(state.title_win) or 0
	local new_h = #lines

	if not state.title_buf or not vim.api.nvim_buf_is_valid(state.title_buf) then
		state.title_buf = vim.api.nvim_create_buf(false, true)
	end

	state.title_height = new_h

	vim.bo[state.title_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.title_buf, 0, -1, false, lines)
	vim.bo[state.title_buf].modifiable = false
	vim.bo[state.title_buf].modified = false

	local float_opts = {
		relative = "editor",
		width = win_width,
		height = new_h,
		row = win_pos[1],
		col = win_pos[2],
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 50,
	}

	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_set_config, state.title_win, float_opts)
		pcall(vim.api.nvim_win_set_buf, state.title_win, state.title_buf)
		vim.wo[state.title_win].winhighlight = "Normal:TgNoBg"
	else
		state.title_win = vim.api.nvim_open_win(state.title_buf, false, float_opts)
		vim.wo[state.title_win].winhighlight = "Normal:TgNoBg"
		vim.api.nvim_create_autocmd("WinEnter", {
			buffer = state.title_buf,
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					vim.api.nvim_set_current_win(state.win)
				end
			end,
		})
	end

	vim.api.nvim_buf_clear_namespace(state.title_buf, hl_ns, 0, -1)
	for li, line in ipairs(lines) do
		if line:match("^=") then
			vim.api.nvim_buf_add_highlight(state.title_buf, hl_ns, "TgBorder", li - 1, 0, -1)
		elseif li == 1 then
			vim.api.nvim_buf_add_highlight(state.title_buf, hl_ns, "TgWinbarTitle", li - 1, 0, #title)
			vim.api.nvim_buf_add_highlight(state.title_buf, hl_ns, "TgTimestamp", li - 1, #title, -1)
		else
			local colon = line:find(":")
			if colon then
				vim.api.nvim_buf_add_highlight(state.title_buf, hl_ns, "TgTitleKey", li - 1, 0, colon + 1)
			end
		end
	end

	if new_h ~= old_h and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		render()
	end
end

local function show_group_selector()
	show_groups_picker(function(item)
		if item then M.open_chat(item.id, item.title) end
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
	else
		local msg = server.send_message(state.chat_id, text)
		insert_msg(msg)
		render()
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
	local tools = require("telegram.tools")

	vim.keymap.set("n", "@", tools.pick, { buffer = buf, nowait = true })
	vim.keymap.set("n", "i", function()
		if state.permissions.can_send_messages ~= true then
			vim.notify("No permission to send messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		M.open_editor("Send", "", function(text)
			if not text then
				return
			end
			local msg = server.send_message(state.chat_id, text)
			if msg then
				table.insert(state.messages, msg)
				render()
			end
		end)
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<CR>", function()
		local target = M.curr_msg()
		if not target then
			return
		end
		local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
		local text = vim.api.nvim_buf_get_lines(state.buf, cursor_line - 1, cursor_line, false)[1]
		if text and text:find("^> ") and target.replyTo then
			M.jump_to_message(target.replyTo.id)
			return
		end
		state.reply_to = target.id
		apply_highlights()
		M.open_editor("Reply", "", function(input)
			state.reply_to = nil
			apply_highlights()
			if not input then
				return
			end
			local msg = server.send_message(state.chat_id, input, target.id)
			if msg then
				table.insert(state.messages, msg)
				render()
			end
		end)
	end, { buffer = buf })
	vim.keymap.set("n", "e", function()
		local target = M.curr_msg()
		if not target or not target.id then
			return
		end
		if not target.own then
			vim.notify("Can only edit your own messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		state.edit_target = target
		apply_highlights()
		M.open_editor("Edit", target.text or "", function(input)
			state.edit_target = nil
			apply_highlights()
			if not input then
				return
			end
			if server.edit_message(state.chat_id, target.id, input) then
				target.text = input
				render()
			end
		end)
	end, { buffer = buf })
	vim.keymap.set("n", "d", function()
		local target = M.curr_msg()
		if not target or not target.id then
			return
		end
		state.delete_target = target
		apply_highlights()
		local choices = target.own and { "Revoke (for everyone)", "Delete (for me)", "Cancel" }
			or { "Delete (for me)", "Cancel" }
		vim.ui.select(choices, { prompt = "Delete message?" }, function(choice)
			state.delete_target = nil
			apply_highlights()
			if not choice or choice == "Cancel" then
				return
			end
			local revoke = choice == "Revoke (for everyone)"
			if server.delete_message(state.chat_id, target.id, revoke) then
				for i = #state.messages, 1, -1 do
					if state.messages[i].id == target.id then
						table.remove(state.messages, i)
						break
					end
				end
				render()
				vim.notify("Message " .. (revoke and "revoked" or "deleted"), vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end, { buffer = buf })
	vim.keymap.set("n", "f", function()
		local target = M.curr_msg()
		if not target or not target.id then
			return
		end
		state.forward_target = target
		apply_highlights()
		if #state.group_ids == 0 then
			state.forward_target = nil
			apply_highlights()
			vim.notify("No chats to forward to", vim.log.levels.WARN, { title = "tg" })
			return
		end
		show_groups_picker(function(item)
			state.forward_target = nil
			apply_highlights()
			if not item then return end
			local ok = server.forward_messages(state.chat_id, target.id, item.id)
			if ok then
				vim.notify("Forwarded to " .. item.title, vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end, { buffer = buf })
	vim.keymap.set("n", "p", function()
		local target = M.curr_msg()
		if not target or not target.id then return end
		if state.permissions.can_pin_messages ~= true then
			vim.notify("No permission to pin messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local is_pinned = state.pinned_message_id and state.pinned_message_id == target.id
		if is_pinned then
			if server.unpin_message(state.chat_id, target.id) then
				state.pinned_message = nil
				state.pinned_message_id = nil
				M.update_title()
				vim.notify("Unpinned message", vim.log.levels.INFO, { title = "tg" })
			end
		else
			if server.pin_message(state.chat_id, target.id) then
				state.pinned_message_id = target.id
				server.get_pinned_message_async(state.chat_id, target.id, function(msg)
					if msg then
						state.pinned_message = msg.text and #msg.text > 0 and msg.text or ("[" .. (msg.type or "media") .. "]")
						M.update_title()
					end
				end)
				M.update_title()
				vim.notify("Pinned message", vim.log.levels.INFO, { title = "tg" })
			end
		end
	end, { buffer = buf })
	vim.keymap.set("n", "G", function()
		M.refresh_messages(function()
			M.jump_to_bottom()
		end)
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "B", function()
		M.ban_sender()
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "c", function()
		local target = M.curr_msg()
		if not target or not target.sender or not target.sender.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if target.own then
			vim.notify("That's you", vim.log.levels.INFO, { title = "tg" })
			return
		end
		local user_id = tonumber(target.sender.id)
		if not user_id then
			vim.notify("Cannot open chat with this sender", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Open DM with " .. target.sender.name .. "?",
		}, function(choice)
			if choice ~= "Yes" then
				return
			end
			local chat = server.open_private_chat(user_id)
			if chat then
				M.open_chat(chat.id, chat.title)
			else
				vim.notify("Failed to open private chat", vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "?", M.show_help, { buffer = buf })
end

local help_popup = nil

local function close_help()
	if help_popup then
		pcall(help_popup.unmount, help_popup)
		help_popup = nil
	end
end

function M.show_help()
	close_help()
	local NuiPopup = require("nui.popup")
	help_popup = NuiPopup({
		relative = "editor",
		position = { row = "50%", col = "50%" },
		size = { width = 42, height = 26 },
		zindex = 200,
		border = { style = "rounded", text = { top = " Help ", top_align = "center" } },
		buf_options = { buftype = "nofile", bufhidden = "wipe" },
		win_options = { winhighlight = "Normal:TgNoBg,FloatBorder:TgBorder" },
		enter = true,
		focusable = true,
	})
	local lines = {
		"-- Messages --",
		" i          open input editor",
		" <CR>       reply / jump to original",
		" e          edit own message",
		" d          delete / revoke",
		" f          forward message",
		" p          pin / unpin message",
		" G          refresh + jump to bottom",
		" B          ban message sender",
		" c          open DM with message sender",
		"",
		"-- Tools (@) --",
		" chats      switch chat (Snacks picker)",
		" members    view and manage members",
		" invitelinks  manage invite links",
		" groupsettings  group settings menu",
		" refresh    reload messages",
		" send       send a message",
		" search     search history",
		" refreshmedia  re-download HD media",
		" openlink    open URL or media file",
		" newchat     start DM by @username",
		"",
		"-- Chat Picker --",
		" built-in fuzzy search via Snacks picker",
		" <CR> / <Esc>  select / cancel",
		"",
		"-- General --",
		" ?          toggle this help",
		" @          open tool picker",
		" <Esc>      close this help",
		" :Tg        close chat / quit",
	}
	help_popup:mount()
	vim.api.nvim_buf_set_lines(help_popup.bufnr, 0, -1, false, lines)
	vim.keymap.set("n", "<Esc>", close_help, { buffer = help_popup.bufnr, nowait = true })
	vim.keymap.set("n", "q", close_help, { buffer = help_popup.bufnr, nowait = true })
	vim.keymap.set("n", "?", close_help, { buffer = help_popup.bufnr, nowait = true })
end

function M.open_editor(title, default_text, callback)
	local NuiPopup = require("nui.popup")
	local popup = NuiPopup({
		relative = "editor",
		position = { row = "50%", col = "50%" },
		size = { width = 60, height = 8 },
		zindex = 150,
		border = { style = "rounded", text = { top = " " .. title .. " ", top_align = "center" } },
		buf_options = { buftype = "acwrite" },
		enter = true,
		focusable = true,
	})
	popup:mount()
	local lines = vim.split(default_text or "", "\n")
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, #lines == 0 and { "" } or lines)
	vim.cmd("startinsert!")
	vim.keymap.set("n", "<CR>", function()
		local text = table.concat(vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n")
		text = text:gsub("^[\n ]+", ""):gsub("[\n ]+$", "")
		popup:unmount()
		if #text > 0 then
			callback(text)
		end
	end, { buffer = popup.bufnr, nowait = true })
	vim.keymap.set("n", "<Esc>", function()
		popup:unmount()
		callback(nil)
	end, { buffer = popup.bufnr, nowait = true })
end

function M.open_chat(chat_id, chat_title)
	chat_title = chat_title or "Chat"

	if
		state.chat_id == chat_id
		and state.buf
		and vim.api.nvim_buf_is_valid(state.buf)
		and vim.bo[state.buf].filetype == "telegram"
	then
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			M.update_title()
			return
		end
		open_split()
		vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		vim.wo[state.win].wrap = true
		vim.wo[state.win].winfixwidth = true
		vim.wo[state.win].number = false
		vim.wo[state.win].relativenumber = false
		vim.wo[state.win].signcolumn = "no"
		vim.wo[state.win].foldcolumn = "0"
		M.update_title()
		return
	end

	if state.chat_id then
		server.close_chat(state.chat_id)
	end

	state.chat_id = chat_id
	state.chat_title = chat_title
	state.last_group = { id = chat_id, title = chat_title }
	if state.groups[chat_id] then
		state.groups[chat_id].unread_count = 0
	end

	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, false)
		pcall(vim.treesitter.language.register, "markdown", "telegram")
		vim.bo[state.buf].filetype = "telegram"
		pcall(vim.diagnostic.disable, state.buf)
		pcall(vim.diagnostic.reset, state.buf)

		open_split()
		vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		vim.wo[state.win].wrap = true
		vim.wo[state.win].winfixwidth = true
		vim.wo[state.win].number = false
		vim.wo[state.win].relativenumber = false
		vim.wo[state.win].signcolumn = "no"
		vim.wo[state.win].foldcolumn = "0"

		vim.api.nvim_create_autocmd("BufWriteCmd", {
			group = vim.api.nvim_create_augroup("TgBufWrite", { clear = true }),
			buffer = state.buf,
			callback = function()
				vim.bo[state.buf].modified = false
			end,
		})

		vim.api.nvim_create_autocmd("WinClosed", {
			group = vim.api.nvim_create_augroup("TgWinFix", { clear = true }),
			callback = function()
				vim.schedule(function()
					if not state.win or not vim.api.nvim_win_is_valid(state.win) then
						destroy_title_float()
						state.win = nil
						state.mounted = false
						return
					end
					local wins = vim.api.nvim_list_wins()
					if #wins == 1 and vim.api.nvim_win_get_buf(state.win) == state.buf then
						if not state.win or not vim.api.nvim_win_is_valid(state.win) then
							return
						end
						local ok, curbuf = pcall(vim.api.nvim_win_get_buf, state.win)
						if not ok or curbuf ~= state.buf then
							return
						end
						local wins2 = vim.api.nvim_list_wins()
						if #wins2 > 1 then
							return
						end
						open_split()
						vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
						vim.api.nvim_set_current_win(state.win)
						M.update_title()
					end
				end)
			end,
		})

		setup_chat_keymaps()

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
				local off = title_offset()
				local min_line = 1 + off
				local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
				if cursor_line <= off then
					pcall(vim.api.nvim_win_set_cursor, state.win, { min_line, 0 })
					return
				end
				local total_lines = vim.api.nvim_buf_line_count(state.buf)
				local line_counts = state.msg_line_counts
				local l = min_line
				for i, msg in ipairs(state.messages) do
					local n = line_counts[i] or #fmt_msg(msg)
					if cursor_line >= l and cursor_line < l + n then
						state.saved_cursors = state.saved_cursors or {}
						state.saved_cursors[state.chat_id] = msg.id
						break
					end
					l = l + n
				end
				if state.unread > 0 and cursor_line >= total_lines - 1 then
					state.unread = 0
				end
				if cursor_line == min_line and not state.exhausted and not state.loading then
					M.load_older()
				elseif cursor_line >= total_lines - 1 and not state.exhausted_forward and not state.loading_newer then
					M.load_newer()
				end
			end,
		})

		local function debounced_title_update()
			if state._title_update_timer then
				state.title_dirty = true
				return
			end
			state.title_dirty = false
			M.update_title()
			state._title_update_timer = vim.defer_fn(function()
				state._title_update_timer = nil
				if state.title_dirty then
					state.title_dirty = false
					M.update_title()
				end
			end, 100)
		end

		vim.api.nvim_create_autocmd("VimResized", {
			group = vim.api.nvim_create_augroup("TgResize", { clear = true }),
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
					debounced_title_update()
				end
			end,
		})

		vim.api.nvim_create_autocmd("WinScrolled", {
			group = vim.api.nvim_create_augroup("TgResize", { clear = true }),
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					debounced_title_update()
				end
			end,
		})

		vim.api.nvim_create_autocmd("BufUnload", {
			buffer = state.buf,
			callback = function()
				M.toggle_off()
			end,
		})
	else
		if not state.win or not vim.api.nvim_win_is_valid(state.win) then
			open_split()
			vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
			state.win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.win, state.buf)
		end
		vim.wo[state.win].wrap = true
		vim.wo[state.win].number = false
		vim.wo[state.win].relativenumber = false
		vim.wo[state.win].signcolumn = "no"
		vim.wo[state.win].foldcolumn = "0"
	end

	pcall(vim.api.nvim_buf_set_name, state.buf, "tg")
	vim.keymap.set("n", "?", M.show_help, { buffer = state.buf })
	state.mounted = true
	state.pinned_message = nil
	state.pinned_message_id = nil
	M.update_title()

	server.open_chat(state.chat_id)

	local cid = state.chat_id
	local cached = state.groups[cid]
	state.online_count = (cached and cached.online_count) or 0
	state.permissions = {}
	state.description = ""

	local pending = 2
	local function check_done()
		pending = pending - 1
		if pending == 0 then
			M.update_title()
		end
	end
	server.get_chat_async(cid, function(chat_info)
		if state.chat_id ~= cid then return end
		if chat_info then
			if chat_info.onlineMemberCount and chat_info.onlineMemberCount > 0 then
				state.online_count = chat_info.onlineMemberCount
			end
			state.description = chat_info.description or ""
			state.default_restricted = chat_info.defaultRestricted or false
			M.refresh_pinned_message(cid, chat_info.pinnedMessageId)
		end
		check_done()
	end)
	server.get_my_permissions_async(cid, function(perms)
		if state.chat_id ~= cid then return end
		if perms then
			state.permissions = perms
			state.my_user_id = perms.my_user_id
		end
		check_done()
	end)

	local saved_id = state.saved_cursors and state.saved_cursors[cid]
	if saved_id then
		state.messages = {}
		state.exhausted = false
		state.exhausted_forward = false
		render()
		local cid = state.chat_id
		server.get_messages_around_async(state.chat_id, saved_id, 31, function(data)
			if state.chat_id == cid then
				state.messages = data.messages or {}
				table.sort(state.messages, function(a, b)
					if a.date ~= b.date then return a.date < b.date end
					return a.id < b.id
				end)
				render()
				M.update_title()
				if #state.messages > 0 then
					server.view_messages(state.chat_id, state.messages[#state.messages].id)
				end
				local l = line_of(saved_id)
				if l then
					pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
				else
					M.jump_to_bottom()
				end
			end
		end)
	else
		state.messages = {}
		state.exhausted = false
		state.exhausted_forward = false
		render()
		M.refresh_messages(function()
			M.jump_to_bottom()
		end)
	end
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
	destroy_title_float()
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
	state.msg_line_counts = {}
	state.loading = false
	state.exhausted = false
	state.exhausted_forward = false
	state.online_count = nil
	state.typing_users = {}
	state.chat_id = nil
	state.chat_title = ""
	state.win = nil
	if state._title_update_timer then
		state._title_update_timer = nil
	end
	state.title_dirty = false
end

function M.message_at_cursor()
	if not state.win then
		return nil
	end
	local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
	local off = title_offset()
	local line_counts = state.msg_line_counts
	local line = 1 + off
	for idx, msg in ipairs(state.messages) do
		local n = line_counts[idx] or #fmt_msg(msg)
		if cursor_line >= line and cursor_line < line + n then
			return idx
		end
		line = line + n
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
		M.update_title()
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
		M.update_title()
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
	local oldest = state.messages[1]
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local old_top = cursor[1]
	server.get_messages_async(chat_id, server.DEFAULT_LIMIT, oldest.id, function(data)
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
		for _, m in ipairs(new_msgs) do
			if not seen[tostring(m.id)] then
				seen[tostring(m.id)] = true
				table.insert(state.messages, m)
				new_lines = new_lines + #fmt_msg(m)
			end
		end
		if state.chat_id ~= chat_id then
			state.loading = false
			return
		end
		if new_lines > 0 then
			table.sort(state.messages, function(a, b)
				if a.date ~= b.date then return a.date < b.date end
				return a.id < b.id
			end)
			render()
			pcall(vim.api.nvim_win_set_cursor, state.win, { old_top + new_lines, cursor[2] })
		end
		state.loading = false
	end, function()
		state.loading = false
	end, { before_date = oldest.date })
end

function M.load_newer()
	if state.loading_newer or state.exhausted_forward or #state.messages == 0 then
		return
	end
	state.loading_newer = true
	local chat_id = state.chat_id
	local newest = state.messages[#state.messages]
	server.get_messages_after_async(chat_id, newest.id, server.DEFAULT_LIMIT, function(data)
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
			table.sort(state.messages, function(a, b)
				if a.date ~= b.date then return a.date < b.date end
				return a.id < b.id
			end)
			render()
		end
		state.loading_newer = false
	end, function()
		state.loading_newer = false
	end, { after_date = newest.date })
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
		for _, msg in ipairs(raw) do
			if not seen[tostring(msg.id)] then
				seen[tostring(msg.id)] = true
				table.insert(state.messages, msg)
			end
		end
		table.sort(state.messages, function(a, b)
			if a.date ~= b.date then return a.date < b.date end
			return a.id < b.id
		end)
		if state.chat_id ~= chat_id then
			return
		end
		render()
		M.update_title()
		if state.win and vim.api.nvim_win_is_valid(state.win) and #state.messages > 0 then
			local last = state.messages[#state.messages]
			local head = line_of(last.id)
			if head then
				pcall(vim.api.nvim_win_set_cursor, state.win, { head - 1, 0 })
			end
		end
		if #state.messages > 0 then
			local latest = state.messages[#state.messages]
			local ts = os.date("%Y-%m-%d %H:%M", latest.date)
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
	end, function(err)
		vim.notify("Failed to load messages: " .. tostring(err), vim.log.levels.ERROR, { title = "tg" })
		if on_complete then
			on_complete()
		end
	end)
end

M.show_groups_picker = show_groups_picker

-- ─── Group Management UI ────────────────────────────────────────────────

local function can(perm)
	return state.permissions and state.permissions[perm] == true
end

local function user_actions_menu(chat_id, user, on_done)
	local actions = { "Open DM" }
	if can("can_restrict_members") then
		table.insert(actions, "Ban")
		table.insert(actions, "Unban")
		table.insert(actions, "Restrict")
		table.insert(actions, "Unrestrict")
	end
	if can("can_promote_members") then
		table.insert(actions, "Promote to admin")
		table.insert(actions, "Demote")
	end
	table.insert(actions, "Cancel")
	vim.ui.select(actions, {
		prompt = user.name .. " (" .. user.status .. "):",
	}, function(choice)
		if not choice or choice == "Cancel" then
			if on_done then on_done() end
			return
		end
		local ok = false
		if choice == "Open DM" then
			local chat = server.open_private_chat(user.user_id)
			if chat then
				M.open_chat(chat.id, chat.title)
			end
			ok = true
		elseif choice == "Ban" then ok = server.ban_member(chat_id, user.user_id)
		elseif choice == "Unban" then ok = server.unban_member(chat_id, user.user_id)
		elseif choice == "Promote to admin" then ok = server.promote_member(chat_id, user.user_id)
		elseif choice == "Demote" then ok = server.demote_member(chat_id, user.user_id)
		elseif choice == "Restrict" then ok = server.restrict_member(chat_id, user.user_id)
		elseif choice == "Unrestrict" then ok = server.unrestrict_member(chat_id, user.user_id)
		end
		if ok then
			vim.notify(choice .. ": " .. user.name, vim.log.levels.INFO, { title = "tg" })
		end
		if on_done then on_done() end
	end)
end

local function status_icon(status)
	local icons = { creator = "\xE2\xAD\x90", administrator = "\xE2\x9C\xA8", member = "\xF0\x9F\x91\xA4", restricted = "\xE2\x9B\x94", banned = "\xE2\x9D\x8C", left = "\xE2\x9C\x8C" }
	return icons[status] or ""
end

---@param chat_id any
function M.show_member_list(chat_id)
	vim.notify("Loading members...", vim.log.levels.INFO, { title = "tg" })
	server.get_members_async(chat_id, function(data)
		if not data or not data.members then
			vim.notify("Failed to load members", vim.log.levels.ERROR, { title = "tg" })
			return
		end
		local items = {}
		for _, m in ipairs(data.members) do
			if m.user_id ~= state.my_user_id then
				table.insert(items, { user_id = m.user_id, name = m.name, status = m.status, label = status_icon(m.status) .. " " .. m.name .. " (" .. m.status .. ")" })
			end
		end
		if #items == 0 then
			vim.notify("No members found", vim.log.levels.INFO, { title = "tg" })
			return
		end
		vim.ui.select(items, {
			prompt = "Members (" .. #items .. ")",
			format_item = function(item) return item.label end,
		}, function(choice)
			if choice then
				user_actions_menu(chat_id, choice)
			end
		end)
	end)
end

---@param chat_id any
function M.show_invite_links(chat_id)
	local actions = {}
	if can("can_invite_users") then
		table.insert(actions, "Create new invite link")
		table.insert(actions, "View existing links")
		table.insert(actions, "Revoke a link")
	end
	table.insert(actions, "Cancel")
	vim.ui.select(actions, {
		prompt = "Invite Links",
	}, function(choice)
		if not choice or choice == "Cancel" then return end
		if choice == "Create new invite link" then
			vim.ui.input({ prompt = "Member limit (0 = unlimited): " }, function(limit)
				local member_limit = limit and tonumber(limit) or nil
				if member_limit and member_limit <= 0 then member_limit = nil end
				if server.create_invite_link(chat_id, nil, member_limit) then
					vim.notify("Invite link created!", vim.log.levels.INFO, { title = "tg" })
				end
			end)
		elseif choice == "View existing links" then
			vim.notify("Loading invite links...", vim.log.levels.INFO, { title = "tg" })
			server.get_invite_links_async(chat_id, function(data)
				if not data or not data.invite_links or #data.invite_links == 0 then
					vim.notify("No invite links", vim.log.levels.INFO, { title = "tg" })
					return
				end
				local lines = {}
				for _, link in ipairs(data.invite_links) do
					local info = link.invite_link
					if link.member_limit and link.member_limit > 0 then
						info = info .. " (limit: " .. link.member_limit .. ")"
					end
					table.insert(lines, info)
				end
				vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Invite Links" })
			end)
		elseif choice == "Revoke a link" then
			vim.notify("Loading invite links...", vim.log.levels.INFO, { title = "tg" })
			server.get_invite_links_async(chat_id, function(data)
				if not data or not data.invite_links or #data.invite_links == 0 then
					vim.notify("No invite links to revoke", vim.log.levels.INFO, { title = "tg" })
					return
				end
				local items = {}
				for _, link in ipairs(data.invite_links) do
					table.insert(items, { link = link.invite_link, label = link.invite_link })
				end
				vim.ui.select(items, {
					prompt = "Select link to revoke",
					format_item = function(item) return item.label end,
				}, function(choice)
					if choice then
						if server.revoke_invite_link(chat_id, choice.link) then
							vim.notify("Link revoked", vim.log.levels.INFO, { title = "tg" })
						end
					end
				end)
			end)
		end
	end)
end

local function is_channel()
	local g = state.chat_id and state.groups[state.chat_id]
	return g and g.type == "channel"
end

---@param chat_id any
function M.show_group_settings(chat_id)
	local channel = is_channel()
	local actions = {}
	if can("can_change_info") then
		table.insert(actions, "Change title")
		table.insert(actions, "Change description")
	end
	if not channel and can("can_invite_users") then
		table.insert(actions, "Add member")
	end
	if not channel and can("can_restrict_members") then
		table.insert(actions, "Set default permissions")
	end
	if channel then
		table.insert(actions, "Unsubscribe from channel")
	else
		table.insert(actions, "Leave group")
	end
	table.insert(actions, "Delete history")
	table.insert(actions, "Cancel")
	vim.ui.select(actions, {
		prompt = "Group Settings",
	}, function(choice)
		if not choice or choice == "Cancel" then return end
		if choice == "Change title" then
			vim.ui.input({ prompt = "New title: ", default = state.chat_title }, function(title)
				if title and #title > 0 then
					if server.set_chat_title(chat_id, title) then
						state.chat_title = title
						if state.groups[chat_id] then
							state.groups[chat_id].title = title
						end
						M.update_title()
						vim.notify("Title updated", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		elseif choice == "Change description" then
			vim.ui.input({ prompt = "New description: ", default = state.description }, function(desc)
				if desc then
					if server.set_chat_description(chat_id, desc) then
						vim.notify("Description updated", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		elseif choice == "Add member" then
			vim.ui.input({ prompt = "User ID to add: " }, function(user_id)
				if user_id and #user_id > 0 then
					local id = tonumber(user_id)
					if not id then
						vim.notify("Invalid user ID", vim.log.levels.ERROR, { title = "tg" })
						return
					end
					local ok, err = server.add_member(chat_id, id)
					if ok then
						vim.notify("Member added", vim.log.levels.INFO, { title = "tg" })
					else
						vim.notify(err or "Failed to add member", vim.log.levels.ERROR, { title = "tg" })
					end
				end
			end)
		elseif choice == "Set default permissions" then
			server.get_chat_async(chat_id, function(chat_info)
				if chat_info then
					state.default_restricted = chat_info.defaultRestricted or false
				end
			end)
			local restrict_options = { "Normal (send)", "Restrict all (read only)" }
			for i, v in ipairs(restrict_options) do
				local is_restrict = v:find("^Restrict") ~= nil
				local on = is_restrict == state.default_restricted
				restrict_options[i] = on and v .. " (current)" or v
			end
			table.insert(restrict_options, "Cancel")
			vim.ui.select(restrict_options, {
				prompt = "Default permissions for new members",
			}, function(perm_choice)
				if not perm_choice or perm_choice == "Cancel" then return end
				local restrict = perm_choice:find("^Restrict") ~= nil
				if server.set_default_permissions(chat_id, restrict) then
					state.default_restricted = restrict
					vim.notify("Permissions " .. (restrict and "restricted" or "allowed"), vim.log.levels.INFO, { title = "tg" })
				end
			end)
		elseif choice == "Unsubscribe from channel" then
			vim.ui.select({ "Yes, unsubscribe", "Cancel" }, {
				prompt = "Unsubscribe from this channel?",
			}, function(confirm)
				if confirm == "Yes, unsubscribe" then
					if server.delete_chat_history(chat_id) then
						state.groups[chat_id] = nil
						for i, id in ipairs(state.group_ids) do
							if id == chat_id then
								table.remove(state.group_ids, i)
								break
							end
						end
						vim.notify("Unsubscribed from channel", vim.log.levels.INFO, { title = "tg" })
						vim.schedule(function()
							M.destroy_chat()
						end)
					end
				end
			end)
		elseif choice == "Leave group" then
			vim.ui.select({ "Yes, leave", "Cancel" }, {
				prompt = "Are you sure you want to leave this group?",
			}, function(confirm)
				if confirm == "Yes, leave" then
					if server.leave_chat(chat_id) then
						state.groups[chat_id] = nil
						for i, id in ipairs(state.group_ids) do
							if id == chat_id then
								table.remove(state.group_ids, i)
								break
							end
						end
						vim.notify("Left group", vim.log.levels.INFO, { title = "tg" })
						vim.schedule(function()
							M.destroy_chat()
						end)
					end
				end
			end)
		elseif choice == "Delete history" then
			vim.ui.select({ "Yes, delete history", "Cancel" }, {
				prompt = "Delete chat history permanently?",
			}, function(confirm)
				if confirm == "Yes, delete history" then
					if server.delete_chat_history(chat_id) then
						vim.notify("History deleted", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		end
	end)
end

---@param chat_id any
---@param user_id any
---@param user_name string
function M.show_user_actions(chat_id, user_id, user_name)
	user_actions_menu(chat_id, { user_id = user_id, name = user_name, status = "member" })
end

function M.ban_sender()
	if not can("can_restrict_members") then
		vim.notify("No permission to restrict members", vim.log.levels.WARN, { title = "tg" })
		return
	end
	local target = M.curr_msg()
	if not target or not target.sender or not target.sender.id then
		vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
		return
	end
	if target.own then
		vim.notify("Cannot ban yourself", vim.log.levels.WARN, { title = "tg" })
		return
	end
	local user_id = tonumber(target.sender.id)
	if not user_id then
		vim.notify("Cannot identify sender", vim.log.levels.WARN, { title = "tg" })
		return
	end
	vim.ui.select({ "Ban " .. target.sender.name, "Cancel" }, {
		prompt = "Ban user?",
	}, function(choice)
		if choice and choice ~= "Cancel" then
			if server.ban_member(state.chat_id, user_id) then
				vim.notify("Banned " .. target.sender.name, vim.log.levels.INFO, { title = "tg" })
			end
		end
	end)
end

M.destroy_title_float = destroy_title_float

return M
