local server = require("telegram.server")
local config = require("telegram.config")
local render_msg = require("telegram.render").render
local state = require("telegram.state").state
local st = require("telegram.state")
local title = require("telegram.render.title")
local groups = require("telegram.groups")
local help = require("telegram.help")
local editor = require("telegram.editor")
local reactions = require("telegram.reactions")

local M = {}

M.state = state

-- ─── Formatting helpers ─────────────────────────────────────────────────

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
			local line = 1 + off + (state.extra_before[i] or 0)
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
	vim.api.nvim_buf_clear_namespace(buf, st.hl_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, st.target_ns, 0, -1)
	for l = 0, vim.api.nvim_buf_line_count(buf) - 1 do
		local line = vim.api.nvim_buf_get_lines(buf, l, l + 1, false)[1]
		if not line then
		elseif line:find("^%[%+%-%~%*%>!]%]") then
			pcall(vim.api.nvim_buf_add_highlight, buf, st.hl_ns, "TgService", l, 0, -1)
		elseif line:find("^  ── .+ ──  $") then
			pcall(vim.api.nvim_buf_add_highlight, buf, st.hl_ns, "TgDateSeparator", l, 0, -1)
		elseif line:find("^── %d+ unread messages ──$") then
			pcall(vim.api.nvim_buf_add_highlight, buf, st.hl_ns, "TgUnreadDivider", l, 0, -1)
		elseif line:find("^  ↳ ") then
			pcall(vim.api.nvim_buf_add_highlight, buf, st.hl_ns, "TgService", l, 0, -1)
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
	local prev_extra = 0
	for i, m in ipairs(state.messages) do
		local extra = state.extra_before[i] or 0
		line = line + (extra - prev_extra)
		prev_extra = extra
		local n = line_counts[i] or #fmt_msg(m)
		if m.id == target_id then
			local start_line = line - 1
			local end_line = line + n - 2
			for l = start_line, end_line do
				vim.api.nvim_buf_add_highlight(buf, st.hl_ns, hl, l, 0, -1)
			end
			local last = end_line >= start_line and end_line or start_line
			vim.api.nvim_buf_set_extmark(buf, st.target_ns, last, 0, {
				virt_lines = { { { label, hl } } },
			})
			break
		end
		line = line + n
	end
end

-- ─── Date separator formatting ──────────────────────────────────────────

local weekday_names = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local function format_date_separator(date_ts)
	local t = os.date("*t", date_ts)
	local now = os.date("*t")
	local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0 })
	local msg_day = os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
	local diff = math.floor((today - msg_day) / 86400)
	if diff == 0 then
		return "  ── Today ──  "
	elseif diff == 1 then
		return "  ── Yesterday ──  "
	elseif diff <= 7 and t.wday then
		return "  ── " .. weekday_names[t.wday] .. " ──  "
	elseif t.year == now.year then
		return string.format("  ── %s %d ──  ", os.date("%B", date_ts), t.day)
	else
		return string.format("  ── %s %d, %d ──  ", os.date("%B", date_ts), t.day, t.year)
	end
end

-- ─── Core render ────────────────────────────────────────────────────────

local function render()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	if #state.messages > st.MAX_WINDOW_MESSAGES then
		st.trim_oldest()
	end
	local buf = state.buf
	local cursor_msg_id = nil
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
		local off = title_offset()
		local l = 1 + off
		for i, m in ipairs(state.messages) do
			local n = state.msg_line_counts[i] or #fmt_msg(m)
			if cursor_line >= l and cursor_line < l + n then
				cursor_msg_id = m.id
				break
			end
			l = l + n
		end
	end
	local lines = {}
	local line_counts = {}
	local extra_before = {}
	local extra_count = 0
	local prev_date_key = nil
	local unread_idx = nil
	if state.unread > 0 then
		if state._unread_start then
			unread_idx = state._unread_start
		else
			for i, m in ipairs(state.messages) do
				if m._unread then unread_idx = i; break end
			end
		end
	end
	if #state.messages == 0 then
		if state.loading then
			table.insert(lines, "[~ Loading...]")
		else
			table.insert(lines, "[~ No messages yet]")
		end
	end
	if state.loading and #state.messages > 0 then
		table.insert(lines, "[~ Loading older messages...]")
	end
	for i, msg in ipairs(state.messages) do
		local date_key = os.date("%Y%m%d", msg.date)
		if prev_date_key and date_key ~= prev_date_key then
			table.insert(lines, format_date_separator(msg.date))
			extra_count = extra_count + 1
		end
		prev_date_key = date_key
		if unread_idx and i == unread_idx then
			table.insert(lines, "── " .. state.unread .. " unread messages ──")
			extra_count = extra_count + 1
		end
		extra_before[i] = extra_count
		local msg_lines = fmt_msg(msg)
		local n = #msg_lines
		line_counts[i] = n
		for _, l in ipairs(msg_lines) do
			table.insert(lines, l)
		end
	end
	if state.loading_newer and #state.messages > 0 then
		table.insert(lines, "[~ Loading newer messages...]")
	end
	state.msg_line_counts = line_counts
	state.extra_before = extra_before
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
	if cursor_msg_id and not state.loading and not state.loading_newer then
		local l = line_of(cursor_msg_id)
		if l then
			pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		end
	end
end
M.render = render

title.set_render_fn(render)
reactions.set_render_fn(render)
groups.set_render_fn(render)

local function curr_msg()
	local i = M.message_at_cursor()
	return i and state.messages[i]
end
M.curr_msg = curr_msg

reactions.set_curr_msg_fn(curr_msg)
groups.set_curr_msg_fn(curr_msg)
groups.set_destroy_chat_fn(function() M.destroy_chat() end)
groups.set_open_chat_fn(function(id, title, typ) M.open_chat(id, title, typ) end)

-- ─── Re-exports ─────────────────────────────────────────────────────────

M.set_groups = groups.set_groups
M.set_typing = groups.set_typing
M.set_online_count = groups.set_online_count
M.update_group_last_msg = groups.update_group_last_msg
M.update_group_online = groups.update_group_online
M.refresh_pinned_message = groups.refresh_pinned_message
M.show_groups_picker = groups.show_groups_picker
M.show_member_list = groups.show_member_list
M.show_invite_links = groups.show_invite_links
M.show_group_settings = groups.show_group_settings
M.show_user_actions = groups.show_user_actions
M.ban_sender = groups.ban_sender
M.show_help = help.show_help
M.open_editor = editor.open_editor
M.close_editor = editor.close_editor
M.show_reaction_picker = reactions.show_reaction_picker
M.toggle_reaction_on = reactions.toggle_reaction_on
M.destroy_title_float = title.destroy_title_float
M.update_title = title.update_title
M.trim_oldest = st.trim_oldest

-- ─── Basic window operations ────────────────────────────────────────────

local function panel_pos()
	return config.config.panel_position or "right"
end

local function is_vertical_split()
	local p = panel_pos()
	return p == "right" or p == "left"
end

local function open_split()
	local p = panel_pos()
	if p == "right" then
		vim.cmd("botright vsplit")
	elseif p == "left" then
		vim.cmd("topleft vsplit")
	elseif p == "bottom" then
		vim.cmd("botright split")
	elseif p == "top" then
		vim.cmd("topleft split")
	end
end

local function panel_resize_cmd()
	if is_vertical_split() then
		return "vertical resize " .. (vim.g.telegram_width or 50)
	else
		return "resize " .. (vim.g.telegram_height or 15)
	end
end

local function apply_panel_winopts(win)
	vim.wo[win].wrap = true
	if is_vertical_split() then
		vim.wo[win].winfixwidth = true
	else
		vim.wo[win].winfixheight = true
	end
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
end

local function hide_chat()
	editor.close_editor(true)
	state.buf = nil
	title.destroy_title_float()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	state.mounted = false
end

function M.toggle_off()
	editor.close_editor(true)
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
	title.destroy_title_float()
end

-- ─── Keymaps ────────────────────────────────────────────────────────────

local function setup_chat_keymaps()
	local buf = state.buf
	local tools = require("telegram.tools")

	local function set(key, cb, opts)
		local k = config.key(key)
		if k then
			vim.keymap.set("n", k, cb, vim.tbl_deep_extend("force", { buffer = buf, nowait = true }, opts or {}))
		end
	end

	set("tool_picker", tools.pick)
	set("input_editor", function()
		if state.permissions.can_send_messages ~= true then
			vim.notify("No permission to send messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		editor.open_editor("Send", state.editor_draft or "", function(text)
			if not text then return end
			local msg = server.send_message(state.chat_id, text)
			if msg then
				state.editor_draft = nil
				table.insert(state.messages, msg)
				render()
			end
		end, "[Send]")
	end)
	set("reply", function()
		local target = curr_msg()
		if not target then return end
		local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
		local text = vim.api.nvim_buf_get_lines(state.buf, cursor_line - 1, cursor_line, false)[1]
		if text and text:find("^> ") and target.replyTo then
			M.jump_to_message(target.replyTo.id)
			return
		end
		state.reply_to = target.id
		apply_highlights()
		local ctx = target.sender and ("[Reply] " .. target.sender.name .. ": " .. (target.text or "")) or nil
		if ctx then ctx = ctx:gsub("\n", " "):sub(1, 70) end
		editor.open_editor("Reply", "", function(input)
			state.reply_to = nil
			apply_highlights()
			if not input then return end
			local msg = server.send_message(state.chat_id, input, target.id)
			if msg then
				table.insert(state.messages, msg)
				render()
			end
		end, ctx)
	end, { nowait = false })
	set("edit", function()
		local target = curr_msg()
		if not target or not target.id then return end
		if not target.own then
			vim.notify("Can only edit your own messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		state.edit_target = target
		apply_highlights()
		editor.open_editor("Edit", target.text or "", function(input)
			state.edit_target = nil
			apply_highlights()
			if not input then return end
			local edited = server.edit_message(state.chat_id, target.id, input)
			if edited then
				target.text = edited.text or input
				if edited.editDate then target.editDate = edited.editDate end
				state._pending_edit = state._pending_edit or {}
				local key = tostring(target.id)
				state._pending_edit[key] = (state._pending_edit[key] or 0) + 1
				local seq = state._pending_edit[key]
				vim.defer_fn(function()
					if state._pending_edit and state._pending_edit[key] == seq then
					state._pending_edit[key] = nil
					end
				end, 3000)
				render()
			else
				vim.notify("Failed to edit message", vim.log.levels.WARN, { title = "tg" })
			end
		end, "[Edit]")
	end)
	set("delete", function()
		local target = curr_msg()
		if not target or not target.id then return end
		state.delete_target = target
		apply_highlights()
		local choices = target.own and { "Revoke (for everyone)", "Delete (for me)", "Cancel" }
			or { "Delete (for me)", "Cancel" }
		vim.ui.select(choices, { prompt = "Delete message?" }, function(choice)
			state.delete_target = nil
			apply_highlights()
			if not choice or choice == "Cancel" then return end
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
			else
				vim.notify("Failed to delete message", vim.log.levels.WARN, { title = "tg" })
			end
		end)
	end)
	set("save", function()
		local target = curr_msg()
		if not target or not target.id then return end
		local saved_id
		for _, g in pairs(state.groups) do
			if g.is_saved then
				saved_id = g.id
				break
			end
		end
		if not saved_id then
			vim.notify("Saved Messages not found", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.select({ "Save", "Cancel" }, {
			prompt = "Save to Favorites?",
		}, function(choice)
			if choice ~= "Save" then return end
			local ok = server.forward_messages(state.chat_id, target.id, saved_id)
			if ok then
				vim.notify("Saved to Favorites", vim.log.levels.INFO, { title = "tg" })
			else
				vim.notify("Failed to save message", vim.log.levels.WARN, { title = "tg" })
			end
		end)
	end)
	set("user_profile", function()
		require("telegram.tools").run("userinfo")
	end)
	set("message_link", function()
		local target = curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local link = server.get_message_link(state.chat_id, target.id)
		if link then
			vim.fn.setreg("+", link)
			vim.notify("Link copied: " .. link, vim.log.levels.INFO, { title = "tg" })
		else
			vim.notify("No link available for this message", vim.log.levels.WARN, { title = "tg" })
		end
	end)
	set("copy", function()
		local target = curr_msg()
		if not target or not target.text then return end
		vim.fn.setreg("+", target.text)
		vim.notify("Copied to clipboard", vim.log.levels.INFO, { title = "tg" })
	end)
	set("forward", function()
		local target = curr_msg()
		if not target or not target.id then return end
		state.forward_target = target
		apply_highlights()
		if #state.group_ids == 0 then
			state.forward_target = nil
			apply_highlights()
			vim.notify("No chats to forward to", vim.log.levels.WARN, { title = "tg" })
			return
		end
		groups.show_groups_picker(function(item)
			state.forward_target = nil
			apply_highlights()
			if not item then return end
			local ok = server.forward_messages(state.chat_id, target.id, item.id)
			if ok then
				vim.notify("Forwarded to " .. item.title, vim.log.levels.INFO, { title = "tg" })
			else
				vim.notify("Failed to forward message", vim.log.levels.WARN, { title = "tg" })
			end
		end)
	end)
	set("pin", function()
		local target = curr_msg()
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
				title.update_title()
				vim.notify("Unpinned message", vim.log.levels.INFO, { title = "tg" })
			end
		else
			if server.pin_message(state.chat_id, target.id) then
				state.pinned_message_id = target.id
				server.get_pinned_message_async(state.chat_id, target.id, function(msg)
					if msg then
						state.pinned_message = msg.text and #msg.text > 0 and msg.text or ("[" .. (msg.type or "media") .. "]")
						title.update_title()
					end
				end)
				title.update_title()
				vim.notify("Pinned message", vim.log.levels.INFO, { title = "tg" })
			end
		end
	end)
	set("refresh", function()
		M.refresh_messages(function()
			M.jump_to_bottom()
		end)
	end)
	set("goto_last", function()
		if not state.prev_chat then
			vim.notify("No previous chat", vim.log.levels.INFO, { title = "tg" })
			return
		end
		if state.chat_id and tostring(state.chat_id) == tostring(state.prev_chat.id) then
			vim.notify("Already in previous chat", vim.log.levels.INFO, { title = "tg" })
			return
		end
		local pc = state.prev_chat
		if state.chat_id then
			state.prev_chat = { id = state.chat_id, title = state.chat_title }
		end
		M.open_chat(pc.id, pc.title)
	end)
	set("ban", function() groups.ban_sender() end)
	set("archive", function()
		if not state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = state.chat_id
		local action = state.current_chat_archived and "Unarchive" or "Archive"
		vim.ui.select({ action, "Cancel" }, {
			prompt = action .. " " .. (state.chat_title or "chat") .. "?",
		}, function(choice)
			if choice ~= action then return end
			if state.current_chat_archived then
				if server.unarchive_chat(chat_id) then
					vim.notify("Unarchived: " .. (state.chat_title or ""), vim.log.levels.INFO, { title = "tg" })
					state.current_chat_archived = false
					require("telegram.render.title").update_title()
				end
			else
				if server.archive_chat(chat_id) then
					vim.notify("Archived: " .. (state.chat_title or ""), vim.log.levels.INFO, { title = "tg" })
					M.destroy_chat()
				end
			end
		end)
	end)
	set("reaction", function() reactions.show_reaction_picker() end)
	set("open_dm", function()
		local target = curr_msg()
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
		vim.ui.select({ "Yes", "No" }, { prompt = "Open DM with " .. target.sender.name .. "?" }, function(choice)
			if choice ~= "Yes" then return end
			local chat = server.open_private_chat(user_id)
			if chat then
				M.open_chat(chat.id, chat.title, chat.type)
			else
				vim.notify("Failed to open private chat", vim.log.levels.ERROR, { title = "tg" })
			end
		end)
	end)
	set("help", help.show_help)
	set("mark_unread", function()
		if not state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = state.chat_id
		local is_unread = state.groups[chat_id] and state.groups[chat_id].is_marked_unread
		if server.mark_chat_unread(chat_id, not is_unread) then
			state.groups[chat_id] = state.groups[chat_id] or {}
			state.groups[chat_id].is_marked_unread = not is_unread
			vim.notify((is_unread and "Marked as read" or "Marked as unread"), vim.log.levels.INFO, { title = "tg" })
			vim.cmd("redrawstatus")
		end
	end)
	set("mute", function()
		if not state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local chat_id = state.chat_id
		local is_muted = state.groups[chat_id] and state.groups[chat_id].is_muted
		if is_muted then
			if server.unmute_chat(chat_id) then
				state.groups[chat_id] = state.groups[chat_id] or {}
				state.groups[chat_id].is_muted = false
				vim.notify("Unmuted chat", vim.log.levels.INFO, { title = "tg" })
			end
		else
			if server.mute_chat(chat_id) then
				state.groups[chat_id] = state.groups[chat_id] or {}
				state.groups[chat_id].is_muted = true
				vim.notify("Muted chat (forever)", vim.log.levels.INFO, { title = "tg" })
			end
		end
	end)
end

local function show_group_selector()
	groups.show_groups_picker(function(item)
		if item then M.open_chat(item.id, item.title) end
	end)
end

-- ─── Chat lifecycle ─────────────────────────────────────────────────────

function M.open_chat(chat_id, chat_title, chat_type)
	chat_title = chat_title or "Chat"
	state.current_chat_archived = false
	if
		state.chat_id == chat_id
		and state.buf
		and vim.api.nvim_buf_is_valid(state.buf)
		and vim.bo[state.buf].filetype == "telegram"
		and not state._jump_to_msg
	then
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			title.update_title()
			return
		end
		open_split()
		vim.cmd(panel_resize_cmd())
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		apply_panel_winopts(state.win)
		title.update_title()
		return
	end
	if state.chat_id then
		if state.chat_id ~= chat_id then
			state.prev_chat = { id = state.chat_id, title = state.chat_title }
			state.editor_draft = nil
		end
		server.close_chat(state.chat_id)
		state.typing_users[state.chat_id] = nil
	end
	editor.close_editor()
	state.chat_id = chat_id
	state.chat_title = chat_title
	state.unread = 0
	state.last_group = { id = chat_id, title = chat_title }
	if state.groups[chat_id] then
		state.groups[chat_id].unread_count = 0
		state.groups[chat_id].mention_count = 0
	else
		state.groups[chat_id] = {
			id = chat_id,
			title = chat_title,
			type = chat_type or "private",
			unread_count = 0,
			mention_count = 0,
			online_count = 0,
		}
		table.insert(state.group_ids, 1, chat_id)
	end
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, false)
		pcall(vim.treesitter.language.register, "markdown", "telegram")
		vim.bo[state.buf].filetype = "telegram"
		pcall(vim.diagnostic.disable, state.buf)
		pcall(vim.diagnostic.reset, state.buf)
		open_split()
		vim.cmd(panel_resize_cmd())
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		apply_panel_winopts(state.win)
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
						title.destroy_title_float()
						state.win = nil
						state.mounted = false
						return
					end
					local wins = vim.api.nvim_list_wins()
					if #wins == 1 and vim.api.nvim_win_get_buf(state.win) == state.buf then
						if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
						local ok, curbuf = pcall(vim.api.nvim_win_get_buf, state.win)
						if not ok or curbuf ~= state.buf then return end
						local wins2 = vim.api.nvim_list_wins()
						if #wins2 > 1 then return end
						open_split()
						vim.cmd(panel_resize_cmd())
						vim.api.nvim_set_current_win(state.win)
						title.update_title()
					end
				end)
			end,
		})
		setup_chat_keymaps()
		vim.api.nvim_create_autocmd("CursorMoved", {
			group = vim.api.nvim_create_augroup("TgChatScroll", { clear = true }),
			buffer = state.buf,
			callback = function()
				if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
				if vim.api.nvim_get_current_win() ~= state.win then return end
				local off = title_offset()
				local min_line = 1 + off
				local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
				if cursor_line <= off then
					pcall(vim.api.nvim_win_set_cursor, state.win, { min_line, 0 })
					return
				end
				local total_lines = vim.api.nvim_buf_line_count(state.buf)
				if state.unread > 0 then
					local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
					local off = title_offset()
					local line = 1 + off
					local last_read_id = nil
					local prev_extra = 0
					for i, m in ipairs(state.messages) do
						local extra = state.extra_before[i] or 0
						line = line + (extra - prev_extra)
						prev_extra = extra
						local n = state.msg_line_counts[i] or #fmt_msg(m)
						if cursor_line >= line and m._unread then
							m._unread = nil
							state.unread = math.max(0, state.unread - 1)
							last_read_id = m.id
						end
						line = line + n
					end
					if last_read_id then
						server.view_messages(state.chat_id, last_read_id)
						if state.chat_id and state.groups[state.chat_id] then
							state.groups[state.chat_id].unread_count = state.unread
						end
						title.update_title()
						vim.cmd("redrawstatus")
						end
				end
				if cursor_line == min_line and not state.exhausted and not state.loading then
					M.load_older()
				elseif cursor_line >= total_lines - 1 and not state.exhausted_forward and not state.loading_newer then
					M.load_newer()
				end
				if state._scroll_timer then
					vim.fn.timer_stop(state._scroll_timer)
				end
				state._scroll_timer = vim.fn.timer_start(50, function()
					state._scroll_timer = nil
				local line_counts = state.msg_line_counts
				local l = min_line
				local prev_extra = 0
				for i, msg in ipairs(state.messages) do
					local extra = state.extra_before[i] or 0
					l = l + (extra - prev_extra)
					prev_extra = extra
					local n = line_counts[i] or #fmt_msg(msg)
						if cursor_line >= l and cursor_line < l + n then
							state.saved_cursors = state.saved_cursors or {}
							state.saved_cursors[state.chat_id] = msg.id
							local t = msg.type or ""
							if ({ messagePhoto = true, messageVideo = true, messageAnimation = true, messageDocument = true, messageAudio = true, messageVoiceNote = true, messageVideoNote = true, messageSticker = true })[t] and (not msg.filePath or #msg.filePath == 0) then
								local mid = msg.id
								if mid and type(mid) == "number" then
									if state._media_dl_timer then
										vim.fn.timer_stop(state._media_dl_timer)
									end
									state._media_dl_timer = vim.fn.timer_start(400, function()
										state._media_dl_timer = nil
										state._req_media = state._req_media or {}
										if not state._req_media[mid] then
											state._req_media[mid] = true
											vim.notify("Downloading media...", vim.log.levels.INFO, { title = "tg" })
											server.get_media_async(state.chat_id, mid, function(res)
												if not state.chat_id then return end
												if res and res.path and #res.path > 0 then
													for _, m in ipairs(state.messages) do
														if tostring(m.id) == tostring(mid) then
															if res.mediaPath and #res.mediaPath > 0 then
																m.mediaPath = res.mediaPath
																m.filePath = res.mediaPath
															else
																m.filePath = res.path
															end
															render()
															break
														end
													end
												end
											end)
										end
									end, { ["repeat"] = 1 })
								end
							end
							break
						end
						l = l + n
					end
				end, { ["repeat"] = 1 })
			end,
		})
		local function debounced_title_update()
			if state._title_update_timer then
				state.title_dirty = true
				return
			end
			state.title_dirty = false
			title.update_title()
			state._title_update_timer = vim.defer_fn(function()
				state._title_update_timer = nil
				if state.title_dirty then
					state.title_dirty = false
					title.update_title()
				end
			end, 100)
		end
		vim.api.nvim_create_autocmd("VimResized", {
			group = vim.api.nvim_create_augroup("TgResizeVim", { clear = true }),
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					vim.cmd(panel_resize_cmd())
					debounced_title_update()
				end
			end,
		})
		vim.api.nvim_create_autocmd("WinScrolled", {
			group = vim.api.nvim_create_augroup("TgScroll", { clear = true }),
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
			vim.cmd(panel_resize_cmd())
			state.win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.win, state.buf)
		end
		apply_panel_winopts(state.win)
	end
	pcall(vim.api.nvim_buf_set_name, state.buf, "tg")
	do
		local k = config.key("help")
		if k then vim.keymap.set("n", k, help.show_help, { buffer = state.buf }) end
	end
	state.mounted = true
	state.pinned_message = nil
	state.pinned_message_id = nil
	title.update_title()
	server.open_chat(state.chat_id)
	local cid = state.chat_id
	local cached = state.groups[cid]
	state.online_count = (cached and cached.online_count) or 0
	title.update_title()
	state.permissions = {}
	state.description = ""
	local saved_id = state.saved_cursors and state.saved_cursors[cid]
	local chat_info_holder = nil
	local pending = 2
	local function check_done()
		pending = pending - 1
		local function count_unread()
			local server_last = chat_info_holder and chat_info_holder.lastReadInboxMessageId or 0
			local last_read = math.max(server_last, state.last_read_id or 0)
			local unread_count = 0
			local first_unread_idx
			for i, m in ipairs(state.messages) do
				if last_read > 0 and m.id > last_read and not m.own then
					m._unread = true
					unread_count = unread_count + 1
					if not first_unread_idx then first_unread_idx = i end
				else
					m._unread = nil
				end
			end
			state.unread = unread_count
			state._unread_start = first_unread_idx
			return first_unread_idx
		end

		local function set_cursor_to_idx(target_idx)
			if not target_idx then return end
			local msg = state.messages[target_idx]
			if not msg then return end
			local l = line_of(msg.id)
			if not l then return end
			if state.unread > 0 and state._unread_start == target_idx then
				l = l + 1
			end
			pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		end

		if pending == 0 then
			title.update_title()
			if state._jump_to_msg then
				local jump_id = state._jump_to_msg
				state._jump_to_msg = nil
				state.messages = {}
				state.exhausted = false
				state.exhausted_forward = false
				render()
				server.get_messages_around_async(state.chat_id, jump_id, 31, function(data)
					if state.chat_id == cid then
						state.messages = data.messages or {}
						table.sort(state.messages, function(a, b)
							if a.date ~= b.date then return a.date < b.date end
							return a.id < b.id
						end)
						count_unread()
						render()
						title.update_title()
						local target_idx
						for i, m in ipairs(state.messages) do
							if tostring(m.id) == tostring(jump_id) then target_idx = i; break end
						end
						set_cursor_to_idx(target_idx or #state.messages)
					end
				end)
			elseif saved_id then
				state.messages = {}
				state.exhausted = false
				state.exhausted_forward = false
				render()
				server.get_messages_around_async(state.chat_id, saved_id, 31, function(data)
					if state.chat_id == cid then
						state.messages = data.messages or {}
						table.sort(state.messages, function(a, b)
							if a.date ~= b.date then return a.date < b.date end
							return a.id < b.id
						end)
						local first_unread_idx = count_unread()
						render()
						title.update_title()
						local target_idx = first_unread_idx or #state.messages
						set_cursor_to_idx(target_idx)
					end
				end)
			elseif chat_info_holder and chat_info_holder.unreadCount
					and chat_info_holder.unreadCount > 0
					and chat_info_holder.lastReadInboxMessageId
					and chat_info_holder.lastReadInboxMessageId > 0 then
				state.messages = {}
				state.exhausted = false
				state.exhausted_forward = false
				render()
				server.get_messages_around_async(state.chat_id, chat_info_holder.lastReadInboxMessageId, 31, function(data)
					if state.chat_id == cid then
						state.messages = data.messages or {}
						table.sort(state.messages, function(a, b)
							if a.date ~= b.date then return a.date < b.date end
							return a.id < b.id
						end)
						local first_unread_idx = count_unread()
						render()
						title.update_title()
						local target_idx = first_unread_idx or #state.messages
						set_cursor_to_idx(target_idx)
					end
				end)
			else
				state.messages = {}
				state.exhausted = false
				state.exhausted_forward = false
				render()
				M.refresh_messages(function()
					local first_unread_idx = count_unread()
					render()
					local target_idx = first_unread_idx or #state.messages
					set_cursor_to_idx(target_idx)
				end)
			end
		end
	end
	server.get_chat_async(cid, function(chat_info)
		if state.chat_id ~= cid then return end
		if chat_info then
			chat_info_holder = chat_info
			local from_server = chat_info.lastReadInboxMessageId or 0
			local from_event = state.saved_last_read and state.saved_last_read[cid] or 0
			state.last_read_id = math.max(from_server, from_event)
			if chat_info.onlineMemberCount and chat_info.onlineMemberCount > 0 then
				state.online_count = chat_info.onlineMemberCount
				title.update_title()
			end
			state.description = chat_info.description or ""
			state.default_restricted = chat_info.defaultRestricted or false
			groups.refresh_pinned_message(cid, chat_info.pinnedMessageId)
			if chat_info.draftText and #chat_info.draftText > 0 then
				state.editor_draft = chat_info.draftText
			end
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
end

function M.close_chat()
	help.close_help()
	title.destroy_title_float()
	if state.chat_id then
		state.last_group = { id = state.chat_id, title = state.chat_title }
		server.close_chat(state.chat_id)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		local safe = (state.chat_title or "chat"):gsub("[^%w%p]", "_"):sub(1, 30)
		pcall(vim.api.nvim_buf_set_name, state.buf, "/tmp/tg-" .. safe .. "-cached")
	end
	state.mounted = false
end

function M.destroy_chat()
	if state._title_update_timer then
		vim.fn.timer_stop(state._title_update_timer)
		state._title_update_timer = nil
	end
	state.title_dirty = false
	M.close_chat()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local curbuf = vim.api.nvim_win_get_buf(state.win)
		if curbuf == state.buf then
			vim.cmd("enew")
		end
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	state.buf = nil
	state.messages = {}
	state._pending_edit = nil
	state.msg_line_counts = {}
	state.extra_before = {}
	state._unread_start = nil
	state.loading = false
	state.exhausted = false
	state.exhausted_forward = false
	state.online_count = nil
	state.typing_users = {}
	state.chat_id = nil
	state.chat_title = ""
	state.win = nil
	if state._scroll_timer then
		vim.fn.timer_stop(state._scroll_timer)
		state._scroll_timer = nil
	end
	if state._typing_timer then
		vim.fn.timer_stop(state._typing_timer)
		state._typing_timer = nil
	end
	if state._media_dl_timer then
		vim.fn.timer_stop(state._media_dl_timer)
		state._media_dl_timer = nil
	end
end

-- ─── Message operations ─────────────────────────────────────────────────

function M.message_at_cursor()
	if not state.win then return nil end
	local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
	local off = title_offset()
	local line_counts = state.msg_line_counts
	local line = 1 + off
	local prev_extra = 0
	for idx, msg in ipairs(state.messages) do
		local extra = state.extra_before[idx] or 0
		line = line + (extra - prev_extra)
		prev_extra = extra
		local n = line_counts[idx] or #fmt_msg(msg)
		if cursor_line >= line and cursor_line < line + n then
			return idx
		end
		line = line + n
	end
	return nil
end

function M.jump_to_message(target_id, callback)
	local l = line_of(target_id)
	if l then
		pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		title.update_title()
		if callback then callback(true) end
		return
	end
	state.messages = {}
	state.exhausted = false
	state.exhausted_forward = false
	server.get_messages_around_async(state.chat_id, target_id, 31, function(data)
		if not state.chat_id then return end
		state.messages = data.messages or {}
		render()
		title.update_title()
		local l = line_of(target_id)
		if l then
			pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 })
		end
		if callback then callback(true) end
	end, function()
		vim.notify("Failed to load message context", vim.log.levels.ERROR, { title = "tg" })
		if callback then callback(false) end
	end)
end

function M.jump_to_bottom()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
	local total = vim.api.nvim_buf_line_count(state.buf)
	pcall(vim.api.nvim_win_set_cursor, state.win, { total - 1, 0 })
end

function M.load_older()
	if state.loading or state.exhausted or #state.messages == 0 then return end
	state.loading = true
	render()
	local chat_id = state.chat_id
	local oldest = state.messages[1]
	local cursor_idx = M.message_at_cursor()
	local cursor_msg_id = cursor_idx and state.messages[cursor_idx].id
	local cursor_col = cursor_idx and vim.api.nvim_win_get_cursor(state.win)[2] or 0
	server.get_messages_async(chat_id, server.DEFAULT_LIMIT, oldest.id, function(data)
		if state.chat_id ~= chat_id then state.loading = false; return end
		local new_msgs = data.messages or {}
		if #new_msgs == 0 then
			state.exhausted = true
			state.loading = false
			render()
			return
		end
		local added = false
		local seen = {}
		for _, m in ipairs(state.messages) do seen[tostring(m.id)] = true end
		for _, m in ipairs(new_msgs) do
			if not seen[tostring(m.id)] then
				seen[tostring(m.id)] = true
				table.insert(state.messages, m)
				added = true
			end
		end
		if state.chat_id ~= chat_id then state.loading = false; return end
		if added then
			table.sort(state.messages, function(a, b)
				if a.date ~= b.date then return a.date < b.date end
				return a.id < b.id
			end)
			st.trim_newest()
				state.loading = false
			render()
		end
		if cursor_msg_id then
			local restored_line = line_of(cursor_msg_id)
			if restored_line then
				pcall(vim.api.nvim_win_set_cursor, state.win, { restored_line, cursor_col })
			end
		end
		state.loading = false
	end, function() state.loading = false end, { before_date = oldest.date })
end

function M.load_newer()
	if state.loading_newer or state.exhausted_forward or #state.messages == 0 then return end
	state.loading_newer = true
	render()
	local chat_id = state.chat_id
	local newest = state.messages[#state.messages]
	server.get_messages_after_async(chat_id, newest.id, server.DEFAULT_LIMIT, function(data)
		if state.chat_id ~= chat_id then state.loading_newer = false; return end
		local new_msgs = data.messages or {}
		if #new_msgs == 0 then
			state.exhausted_forward = true
			state.loading_newer = false
			render()
			return
		end
		local seen = {}
		for _, m in ipairs(state.messages) do seen[tostring(m.id)] = true end
		local newly_inserted = {}
		for _, m in ipairs(new_msgs) do
			if not seen[tostring(m.id)] then
				seen[tostring(m.id)] = true
				table.insert(state.messages, m)
				table.insert(newly_inserted, m)
			end
		end
		if #new_msgs > 0 then
			table.sort(state.messages, function(a, b)
				if a.date ~= b.date then return a.date < b.date end
				return a.id < b.id
			end)
			if state.last_read_id and state.last_read_id > 0 then
				local new_unread = 0
				for _, m in ipairs(newly_inserted) do
					if m.id > state.last_read_id and not m.own then
						m._unread = true
						new_unread = new_unread + 1
					end
				end
				if new_unread > 0 then
					state.unread = state.unread + new_unread
				end
			end
			st.trim_oldest()
				state.loading_newer = false
			render()
		end
		state.loading_newer = false
	end, function() state.loading_newer = false end, { after_date = newest.date })
end

function M.refresh_messages(on_complete)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
	state.loading = false
	state.exhausted = false
	state.exhausted_forward = false
	local chat_id = state.chat_id
	server.get_messages_async(chat_id, 30, nil, function(data)
		if state.chat_id ~= chat_id then return end
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
		if state.chat_id ~= chat_id then return end
		render()
		title.update_title()
		if state.win and vim.api.nvim_win_is_valid(state.win) and #state.messages > 0 then
			local last = state.messages[#state.messages]
			local head = line_of(last.id)
			if head then
				pcall(vim.api.nvim_win_set_cursor, state.win, { head, 0 })
			end
		end
		if #state.messages > 0 then
			local latest = state.messages[#state.messages]
			local ts = os.date("%Y-%m-%d %H:%M", latest.date)
			state.last_msg = "[" .. ts .. "] " .. (latest.sender and latest.sender.name or "?") .. ": " .. (latest.text or "")
		end
		if on_complete then on_complete() end
	end, function(err)
		vim.notify("Failed to load messages: " .. tostring(err), vim.log.levels.ERROR, { title = "tg" })
		if on_complete then on_complete() end
	end)
end

function M.append_message(msg)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
	local buf = state.buf
	local msg_lines = fmt_msg(msg)
	if #msg_lines == 0 then return end
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

return M
