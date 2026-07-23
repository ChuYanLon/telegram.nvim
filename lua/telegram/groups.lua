local state = require("telegram.state").state
local server = require("telegram.server")
local config = require("telegram.config")
local title = require("telegram.render.title")

local M = {}

local render_cb = nil
local curr_msg_cb = nil
local destroy_chat_cb = nil
local open_chat_cb = nil

function M.set_render_fn(fn) render_cb = fn end
function M.set_curr_msg_fn(fn) curr_msg_cb = fn end
function M.set_destroy_chat_fn(fn) destroy_chat_cb = fn end
function M.set_open_chat_fn(fn) open_chat_cb = fn end

function M.set_groups(groups)
	local new_groups = {}
	local new_ids = {}
	for _, g in ipairs(groups or {}) do
		local existing = state.groups[g.id]
		local existing_online = existing and existing.online_count
		local uc = (existing and existing.unread_count) or g.unreadCount or 0
		local mc = (existing and existing.mention_count) or (uc > 0 and g.unreadMentionCount) or 0
		new_groups[g.id] = {
			id = g.id,
			title = g.title,
			type = g.type or "group",
			unread_count = uc,
			mention_count = mc,
			member_count = g.memberCount or (existing and existing.member_count) or 0,
			online_count = (existing_online and existing_online > 0 and existing_online) or g.onlineMemberCount or 0,
			user_id = g.userId,
			last_msg = existing and existing.last_msg,
			is_saved = g.isSaved or false,
			is_archived = g.isArchived or false,
		}
		table.insert(new_ids, g.id)
	end
	state.groups = new_groups
	state.group_ids = new_ids
	if state.chat_id and new_groups[state.chat_id] then
		local oc = new_groups[state.chat_id].online_count
		if oc and oc > 0 then
			state.online_count = oc
			title.update_title()
		end
	end
end

function M.set_typing(chat_id, user_id, user_name, action_type, active)
	if active then
		state.typing_users[chat_id] = state.typing_users[chat_id] or {}
		state.typing_users[chat_id][user_id] =
			{ name = user_name or "Unknown", action_desc = title.action_descriptions[action_type] or "typing..." }
	else
		if state.typing_users[chat_id] then
			state.typing_users[chat_id][user_id] = nil
			if not next(state.typing_users[chat_id]) then
				state.typing_users[chat_id] = nil
			end
		end
	end
	title.update_title()
end

function M.set_online_count(count)
	state.online_count = count or 0
	title.update_title()
end

function M.update_group_last_msg(chat_id, sender_name, text)
	if not state.groups[chat_id] then
		return
	end
	state.groups[chat_id].last_msg = ("[%s] %s: %s"):format(os.date("%H:%M"), sender_name, (text or ""):gsub("\n", " "):sub(1, 40))
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
		title.update_title()
		return
	end
	server.get_pinned_message_async(chat_id, pinned_message_id, function(msg)
		if state.chat_id == chat_id and msg then
			state.pinned_message = msg.text and #msg.text > 0 and msg.text or ("[" .. (msg.type or "media") .. "]")
			title.update_title()
		end
	end)
end

--[[
---@param on_select fun(item: table|nil)
---@param custom_items table|nil  Optional: show these items instead of state groups
]]
local function show_groups_picker(on_select, custom_items)
	local items = {}
	if custom_items then
		for _, item in ipairs(custom_items) do
			table.insert(items, item)
		end
	else
		for _, id in ipairs(state.group_ids) do
			local g = state.groups[id]
			if g then
				table.insert(items, {
					id = g.id,
					title = g.title,
					type = g.type or "group",
					unread = g.unread_count or 0,
					is_saved = g.is_saved or false,
					is_archived = g.is_archived or false,
				})
			end
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
				is_saved = item.is_saved,
			})
		end
		local picked = false
		snacks.picker.pick({
			title = "Chats",
			items = picker_items,
			layout = "select",
			format = function(item)
				local label = item.text
				if item.is_saved then
					label = "\xF0\x9F\x93\x8C " .. label
				end
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
				if item.is_saved then
					label = "\xF0\x9F\x93\x8C " .. label
				elseif item.type == "channel" then
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
M.show_groups_picker = show_groups_picker

local function can(perm)
	return state.permissions and state.permissions[perm] == true
end

local function status_icon(status)
	local icons = { creator = "\xE2\xAD\x90", administrator = "\xE2\x9C\xA8", member = "\xF0\x9F\x91\xA4", restricted = "\xE2\x9B\x94", banned = "\xE2\x9D\x8C", left = "\xE2\x9C\x8C" }
	return icons[status] or ""
end

local function user_actions_menu(chat_id, user, on_done)
	local actions = { "Open DM" }
	local s = user.status
	if can("can_restrict_members") then
		if s ~= "banned" and s ~= "administrator" and s ~= "creator" then
			table.insert(actions, "Ban")
		end
		if s == "banned" then
			table.insert(actions, "Unban")
		end
		if s ~= "restricted" and s ~= "banned" and s ~= "administrator" and s ~= "creator" then
			table.insert(actions, "Restrict")
		end
		if s == "restricted" then
			table.insert(actions, "Unrestrict")
		end
	end
	if can("can_promote_members") then
		if s == "member" or s == "restricted" then
			table.insert(actions, "Promote to admin")
		end
		if s == "administrator" then
			table.insert(actions, "Demote")
		end
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
			if chat and open_chat_cb then
				open_chat_cb(chat.id, chat.title, chat.type)
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
		elseif choice ~= "Open DM" then
			vim.notify(choice .. " failed: " .. user.name, vim.log.levels.WARN, { title = "tg" })
		end
		if chat_id == state.chat_id then
			title.update_title()
		end
		if on_done then on_done() end
	end)
end

function M.show_member_list(chat_id)
	vim.notify("Loading members...", vim.log.levels.INFO, { title = "tg" })
	server.get_members_async(chat_id, function(data)
		if not data or not data.members then
			return
		end
		local items = {}
		for _, m in ipairs(data.members) do
			if m.user_id ~= state.my_user_id then
				local title_str = m.custom_title and #m.custom_title > 0 and " [" .. m.custom_title .. "]" or ""
				table.insert(items, { user_id = m.user_id, name = m.name, status = m.status, label = status_icon(m.status) .. " " .. m.name .. title_str .. " (" .. m.status .. ")" })
			end
		end
		if #items == 0 then
			vim.notify("No members found", vim.log.levels.INFO, { title = "tg" })
			return
		end
		local total_str = data.total_count and ("/" .. data.total_count) or ""
		vim.ui.select(items, {
			prompt = "Members (" .. #items .. total_str .. ")",
			format_item = function(item) return item.label end,
		}, function(choice)
			if choice then
				user_actions_menu(chat_id, choice)
			end
		end)
	end)
end

function M.show_invite_links(chat_id)
	local actions = {}
	if can("can_invite_users") then
		table.insert(actions, "Create new invite link")
		table.insert(actions, "View existing links")
		table.insert(actions, "Edit a link")
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
				vim.ui.input({ prompt = "Expire after hours (0 = never): " }, function(hours)
					local expire_date = hours and tonumber(hours) or nil
					if expire_date and expire_date > 0 then
						expire_date = math.floor(os.time() + expire_date * 3600)
					else
						expire_date = nil
					end
					local res = server.create_invite_link(chat_id, expire_date, member_limit)
					if res and res.invite_link then
						vim.notify(res.invite_link, vim.log.levels.INFO, { title = "Invite Link" })
					end
				end)
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
		elseif choice == "Edit a link" then
			vim.notify("Loading invite links...", vim.log.levels.INFO, { title = "tg" })
			server.get_invite_links_async(chat_id, function(data)
				if not data or not data.invite_links or #data.invite_links == 0 then
					vim.notify("No invite links to edit", vim.log.levels.INFO, { title = "tg" })
					return
				end
				local items = {}
				for _, link in ipairs(data.invite_links) do
					local label = link.invite_link
					if link.member_limit and link.member_limit > 0 then
						label = label .. " (limit: " .. link.member_limit .. ")"
					end
					table.insert(items, { link = link.invite_link, member_limit = link.member_limit, label = label })
				end
				vim.ui.select(items, {
					prompt = "Select link to edit",
					format_item = function(item) return item.label end,
				}, function(choice)
					if not choice then return end
					vim.ui.input({ prompt = "New member limit (0 = unlimited): ", default = tostring(choice.member_limit or 0) }, function(limit)
						local member_limit = limit and tonumber(limit) or nil
						if member_limit and member_limit <= 0 then member_limit = nil end
						vim.ui.input({ prompt = "Expire after hours (0 = never): " }, function(hours)
							local expire_date = hours and tonumber(hours) or nil
							if expire_date and expire_date > 0 then
								expire_date = math.floor(os.time() + expire_date * 3600)
							else
								expire_date = nil
							end
							if server.edit_invite_link(chat_id, choice.link, expire_date, member_limit) then
								vim.notify("Link updated", vim.log.levels.INFO, { title = "tg" })
							end
						end)
					end)
				end)
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
						require("telegram.render.title").update_title()
						vim.notify("Title updated", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		elseif choice == "Change description" then
			vim.ui.input({ prompt = "New description: ", default = state.description }, function(desc)
				if desc then
					if server.set_chat_description(chat_id, desc) then
						state.description = desc
						require("telegram.render.title").update_title()
						vim.notify("Description updated", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		elseif choice == "Add member" then
			vim.ui.input({ prompt = "Enter @username: " }, function(username)
				if not username or #username == 0 then return end
				local search = server.search_user(username)
				if not search then
					vim.notify("User not found", vim.log.levels.ERROR, { title = "tg" })
					return
				end
				if not search.userId then
					vim.notify("Not a user: " .. (search.title or username), vim.log.levels.ERROR, { title = "tg" })
					return
				end
				local res = server.add_member(chat_id, search.userId)
				if res and res.ok then
					vim.notify("Member added: " .. (search.title or username), vim.log.levels.INFO, { title = "tg" })
				elseif res and res.inviteLink then
					vim.notify("Share this invite link:\n" .. res.inviteLink, vim.log.levels.INFO, { title = "tg" })
				elseif res and res.error then
					vim.notify("Failed to add member: " .. res.error, vim.log.levels.ERROR, { title = "tg" })
				else
					vim.notify("Failed to add member", vim.log.levels.ERROR, { title = "tg" })
				end
			end)
		elseif choice == "Set default permissions" then
			local perm_keys = {
				{ label = "Send messages", key = "can_send_messages" },
				{ label = "Send audios", key = "can_send_audios" },
				{ label = "Send documents", key = "can_send_documents" },
				{ label = "Send photos", key = "can_send_photos" },
				{ label = "Send videos", key = "can_send_videos" },
				{ label = "Send video notes", key = "can_send_video_notes" },
				{ label = "Send voice notes", key = "can_send_voice_notes" },
				{ label = "Send polls", key = "can_send_polls" },
				{ label = "Send other messages", key = "can_send_other_messages" },
				{ label = "Add link previews", key = "can_add_web_page_previews" },
				{ label = "Change info", key = "can_change_info" },
				{ label = "Invite users", key = "can_invite_users" },
				{ label = "Pin messages", key = "can_pin_messages" },
				{ label = "Manage topics", key = "can_manage_topics" },
			}
			local current = {}
			server.get_chat_async(chat_id, function(chat_info)
				if chat_info and chat_info.defaultPermissions then
					current = chat_info.defaultPermissions
				end
				local buf = vim.api.nvim_create_buf(false, true)
				local num_perms = #perm_keys
				local max_idx = num_perms + 1
				local win_w = 56
				local win_h = max_idx + 1
				local editor_win = vim.api.nvim_get_current_win()
				local editor_pos = vim.api.nvim_win_get_position(editor_win)
				local editor_width = vim.api.nvim_win_get_width(editor_win)
				local editor_height = vim.api.nvim_win_get_height(editor_win)
				local win = vim.api.nvim_open_win(buf, true, {
					relative = "editor", width = win_w, height = win_h,
					row = math.max(0, editor_pos[1] + editor_height / 2 - win_h / 2 - 2),
					col = math.max(0, editor_pos[2] + editor_width / 2 - win_w / 2),
					style = "minimal", border = "single",
				})
				vim.wo[win].cursorline = true
				local idx = 1

				local function all_enabled()
					for _, pk in ipairs(perm_keys) do
						if current[pk.key] ~= true then return false end
					end
					return true
				end

				local ns = vim.api.nvim_create_namespace("tg_perms")

				local function render_perms()
					local lines = {}
					table.insert(lines, " [j/k] navigate [Tab] toggle [Enter] save [Esc] discard")
					table.insert(lines, (all_enabled() and "[x]" or "[ ]") .. " Toggle all")
					for _, pk in ipairs(perm_keys) do
						local val = current[pk.key]
						local icon = val == true and "[x]" or val == false and "[ ]" or "[?]"
						table.insert(lines, icon .. " " .. pk.label)
					end
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
					vim.bo[buf].modified = false
					vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
					vim.api.nvim_buf_add_highlight(buf, ns, "TgPermToggle", 1, 0, -1)
					vim.api.nvim_buf_add_highlight(buf, ns, all_enabled() and "TgPermOn" or "TgPermOff", 1, 0, 3)
					vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 1, 3, -1)
					for i, pk in ipairs(perm_keys) do
						local line = i + 1
						local val = current[pk.key]
						local hl = val == true and "TgPermOn" or val == false and "TgPermOff" or "TgPermUnknown"
						vim.api.nvim_buf_add_highlight(buf, ns, hl, line, 0, 3)
						if val ~= true then
							vim.api.nvim_buf_add_highlight(buf, ns, "Comment", line, 3, -1)
						end
					end
				end

				local function toggle()
					if idx == 1 then
						local new_val = not all_enabled()
						for _, pk in ipairs(perm_keys) do current[pk.key] = new_val end
						render_perms()
					else
						local pk = perm_keys[idx - 1]
						current[pk.key] = current[pk.key] == nil and false or not current[pk.key]
						local icon = current[pk.key] == true and "[x]" or "[ ]"
						local hl = current[pk.key] == true and "TgPermOn" or "TgPermOff"
						vim.api.nvim_buf_set_lines(buf, idx, idx + 1, false, { icon .. " " .. pk.label })
						vim.api.nvim_buf_clear_namespace(buf, ns, idx, idx + 1)
						vim.api.nvim_buf_add_highlight(buf, ns, hl, idx, 0, 3)
						if current[pk.key] ~= true then
							vim.api.nvim_buf_add_highlight(buf, ns, "Comment", idx, 3, -1)
						end
						local ta_icon = all_enabled() and "[x]" or "[ ]"
						vim.api.nvim_buf_set_lines(buf, 1, 2, false, { ta_icon .. " Toggle all" })
						vim.api.nvim_buf_clear_namespace(buf, ns, 1, 2)
						vim.api.nvim_buf_add_highlight(buf, ns, "TgPermToggle", 1, 0, -1)
						vim.api.nvim_buf_add_highlight(buf, ns, all_enabled() and "TgPermOn" or "TgPermOff", 1, 0, 3)
						vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 1, 3, -1)
					end
				end

				local function close_win()
					pcall(vim.api.nvim_win_close, win, true)
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end

				local function on_enter()
					close_win()
					vim.ui.select({ "Save", "Discard" }, {
						prompt = "Save permission changes?",
					}, function(choice)
						if choice == "Save" then
							if server.set_default_permissions(chat_id, current) then
								vim.notify("Permissions saved", vim.log.levels.INFO, { title = "tg" })
							end
						end
					end)
				end

				local function on_esc()
					close_win()
				end

				local function set_cursor()
					pcall(vim.api.nvim_win_set_cursor, win, { idx + 1, 0 })
				end
				do local k = config.key("perms_down")
					if k then vim.keymap.set("n", k, function() idx = math.min(idx + 1, max_idx) set_cursor() end, { buffer = buf, nowait = true }) end end
				do local k = config.key("perms_up")
					if k then vim.keymap.set("n", k, function() idx = math.max(idx - 1, 1) set_cursor() end, { buffer = buf, nowait = true }) end end
				do local k = config.key("perms_toggle")
					if k then vim.keymap.set("n", k, toggle, { buffer = buf, nowait = true }) end end
				do local k = config.key("perms_up_alt")
					if k then vim.keymap.set("n", k, function() idx = math.max(idx - 1, 1) set_cursor() end, { buffer = buf, nowait = true }) end end
				do local k = config.key("perms_save")
					if k then vim.keymap.set("n", k, on_enter, { buffer = buf, nowait = true }) end end
				do local k = config.key("perms_discard")
					if k then vim.keymap.set("n", k, on_esc, { buffer = buf, nowait = true }) end end
			vim.api.nvim_create_autocmd("WinClosed", {
				buffer = buf,
				once = true,
				callback = close_win,
			})
			vim.schedule(function()
				set_cursor()
			end)
				render_perms()
			end)
		elseif choice == "Unsubscribe from channel" then
			vim.ui.select({ "Yes, unsubscribe", "Cancel" }, {
				prompt = "Unsubscribe from this channel?",
			}, function(confirm)
				if confirm == "Yes, unsubscribe" then
					if server.leave_chat(chat_id) then
						state.groups[chat_id] = nil
						for i, id in ipairs(state.group_ids) do
							if id == chat_id then
								table.remove(state.group_ids, i)
								break
							end
						end
						vim.notify("Unsubscribed from channel", vim.log.levels.INFO, { title = "tg" })
						vim.schedule(function()
							if destroy_chat_cb then destroy_chat_cb() end
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
							if destroy_chat_cb then destroy_chat_cb() end
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
						state.messages = {}
						state.msg_line_counts = {}
						state.exhausted = false
						state.exhausted_forward = false
						require("telegram.render.title").update_title()
						if render_cb then render_cb() end
						vim.notify("History deleted", vim.log.levels.INFO, { title = "tg" })
					end
				end
			end)
		end
	end)
end

function M.show_user_actions(chat_id, user_id, user_name)
	user_actions_menu(chat_id, { user_id = user_id, name = user_name, status = "member" })
end

function M.ban_sender()
	if not can("can_restrict_members") then
		vim.notify("No permission to restrict members", vim.log.levels.WARN, { title = "tg" })
		return
	end
	local target = curr_msg_cb and curr_msg_cb()
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

return M
