local Editor = require("telegram.editor")
local server = require("telegram.server")
local render_msg = require("telegram.render").render

local M = {}

local typing_popup = nil

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
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	state.mounted = false
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

local function line_of(target_id)
	for i, m in ipairs(state.messages) do
		if m.id == target_id then
			local line = 1
			for j = 1, i - 1 do
				line = line + #fmt_msg(state.messages[j])
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
		line = line + n
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
				if item.type == "private" then
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
		new_groups[g.id] = {
			id = g.id,
			title = g.title,
			type = g.type or "group",
			unread_count = (existing and existing.unread_count) or g.unreadCount or 0,
			member_count = g.memberCount or (existing and existing.member_count) or 0,
			online_count = (existing and existing.online_count) or g.onlineMemberCount or 0,
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
	if not count or count == 0 then
		return
	end
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
	if state.groups[chat_id] and count and count > 0 then
		state.groups[chat_id].online_count = count
	end
end

function M.update_title()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_set_name, state.buf, "tg")
	end
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local title = state.chat_title or ""
	local online = state.online_count or 0
	local count = tostring(online)
	if state.chat_id and state.groups[state.chat_id] then
		local total = state.groups[state.chat_id].member_count or 0
		if total > 0 then
			count = online .. "/" .. total
		end
	end
	if state.unread > 0 then
		count = count .. "  \xE2\x97\x8F+" .. state.unread
	end

	local typing_items = {}
	for _, info in pairs(state.typing_users) do
		table.insert(typing_items, info)
	end
	local typing = ""
	if #typing_items > 0 then
		if #typing_items == 1 then
			typing = typing_items[1].name .. " " .. typing_items[1].action_desc
		else
			typing = typing_items[1].name .. " +" .. (#typing_items - 1) .. " " .. typing_items[1].action_desc
		end
	end

	local winbar = "%#TgWinbarHeader### %*%#TgWinbarTitle#" .. title .. "%*%#TgTimestamp# (" .. count .. ")%*"
	pcall(vim.api.nvim_set_option_value, "winbar", winbar, { win = state.win })
	if typing_popup and vim.api.nvim_win_is_valid(typing_popup) then
		vim.api.nvim_win_close(typing_popup, true)
		typing_popup = nil
	end
	if typing ~= "" and state.win and vim.api.nvim_win_is_valid(state.win) then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " " .. typing })
		local width = vim.api.nvim_win_get_width(state.win)
		typing_popup = vim.api.nvim_open_win(buf, false, {
			relative = "win",
			win = state.win,
			row = 0,
			col = 0,
			width = width,
			height = 1,
			style = "minimal",
			noautocmd = true,
		})
		vim.api.nvim_set_option_value("winhighlight", "Normal:TgService", { win = typing_popup })
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
	vim.keymap.set("n", "G", function()
		M.refresh_messages(function()
			M.jump_to_bottom()
		end)
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
		help_popup:unmount()
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
		" G          refresh + jump to bottom",
		" c          open DM with message sender",
		"",
		"-- Tools (@) --",
		" chats      switch chat (Snacks picker)",
		" refresh    reload messages",
		" send       send a message",
		" search     search history",
		" refreshmedia  re-download HD media",
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
		" q / :Tg    close chat / quit",
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
		vim.cmd("botright vsplit")
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

		vim.cmd("botright vsplit")
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
				if not state.win or not vim.api.nvim_win_is_valid(state.win) then
					return
				end
				local wins = vim.api.nvim_list_wins()
				if #wins == 1 and vim.api.nvim_win_get_buf(state.win) == state.buf then
					vim.schedule(function()
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
						vim.cmd("botright vsplit")
						vim.cmd("vertical resize " .. (vim.g.telegram_width or 50))
						vim.api.nvim_set_current_win(state.win)
					end)
				end
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
				local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
				local total_lines = vim.api.nvim_buf_line_count(state.buf)
				local l = 1
				for _, msg in ipairs(state.messages) do
					local n = #fmt_msg(msg)
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
				if cursor_line <= 1 and not state.exhausted then
					M.load_older()
				elseif cursor_line >= total_lines - 1 and not state.exhausted_forward then
					M.load_newer()
				end
			end,
		})

		vim.api.nvim_create_autocmd("VimResized", {
			group = vim.api.nvim_create_augroup("TgResize", { clear = true }),
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					local width = vim.g.telegram_width or 50
					vim.api.nvim_win_set_config(state.win, {
						width = width,
						height = vim.o.lines - 2,
						col = vim.o.columns - width,
						row = 0,
					})
				end
			end,
		})

		vim.api.nvim_create_autocmd("BufUnload", {
			buffer = state.buf,
			callback = function()
				if state.chat_id then
					state.last_group = { id = state.chat_id, title = state.chat_title }
				end
				hide_chat()
			end,
		})
	else
		if not state.win or not vim.api.nvim_win_is_valid(state.win) then
			vim.cmd("botright vsplit")
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
	M.update_title()

	server.open_chat(state.chat_id)

	local cached = state.groups[state.chat_id]
	state.online_count = (cached and cached.online_count) or 0
	local chat_info = server.get_chat(state.chat_id)
	if chat_info then
		state.online_count = chat_info.onlineMemberCount or state.online_count
		M.update_title()
	end

	local saved_id = state.saved_cursors and state.saved_cursors[state.chat_id]
	if saved_id then
		state.messages = {}
		state.exhausted = false
		state.exhausted_forward = false
		local cid = state.chat_id
		server.get_messages_around_async(state.chat_id, saved_id, 31, function(data)
			if state.chat_id == cid then
				state.messages = data.messages or {}
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

local function close_typing_popup()
	if typing_popup and vim.api.nvim_win_is_valid(typing_popup) then
		vim.api.nvim_win_close(typing_popup, true)
		typing_popup = nil
	end
end

function M.close_chat()
	close_help()
	close_typing_popup()
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
				new_lines = new_lines + #fmt_msg(new_msgs[i])
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
	end, function()
		vim.notify("Failed to load messages", vim.log.levels.ERROR, { title = "tg" })
		if on_complete then
			on_complete()
		end
	end)
end

M.show_groups_picker = show_groups_picker

return M
