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

local M = {}

local initialized = false

local notify_queue = {}
local notify_timer_id = nil

local function flush_notify()
	if #notify_queue == 0 then return end
	local lines = table.concat(notify_queue, '\n')
	notify_queue = {}
	notify_timer_id = nil
	vim.notify(lines, vim.log.levels.INFO, { title = 'tg' })
end

local function queue_notify(preview)
	table.insert(notify_queue, preview)
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

local function finish_init()
	ws.ws_start(function(msg)
		if msg.event == "newMessage" then
			vim.schedule(function()
				local st = ui.state
				local is_current = st.chat_id and msg.chat and msg.chat.id == st.chat_id
				local sender = msg.sender and msg.sender.name or '?'
				local text = (msg.text or ''):gsub('\n', ' '):sub(1, 50)

				if is_current then
					if not st.buf or not st.win or not vim.api.nvim_buf_is_valid(st.buf) or not vim.api.nvim_win_is_valid(st.win) then
						return
					end
					local total_before = vim.api.nvim_buf_line_count(st.buf)
					local cur = vim.api.nvim_win_get_cursor(st.win)
					local at_bottom = cur[1] >= total_before - 1
					if not at_bottom then
						st.unread = st.unread + 1
						if st.groups[st.chat_id] then
							st.groups[st.chat_id].unread_count = st.unread
							ui.render_groups()
						end
						queue_notify(sender .. ': ' .. text)
					end
					local ts = os.date("%m-%d %H:%M", msg.date)
					local preview = "[" .. ts .. "] " .. (msg.sender and msg.sender.name or "?") .. ": " .. (msg.text or "")
					st.last_msg = preview:sub(1, 60)
					ui.update_title()
					local mid = msg.id or (os.time() .. math.random())
					local function dup()
						for _, m in ipairs(st.messages) do
							if m.id == mid then return true end
							if msg.own and m.own and m.text == msg.text and math.abs(m.date - msg.date) <= 2 then
								return true
							end
						end
					end
					if dup() then return end
					table.insert(st.messages, { id = mid, type = msg.type, date = msg.date, sender = msg.sender, text = msg.text, own = msg.own, replyTo = msg.replyTo })
					ui.render()
					if at_bottom then
						pcall(vim.api.nvim_win_set_cursor, st.win, { vim.api.nvim_buf_line_count(st.buf) - 1, cur[2] })
					end
					st.exhausted = false
					st.exhausted_forward = false
				else
					local group_title = msg.chat and msg.chat.title or '?'
					ui.update_group_last_msg(msg.chat and msg.chat.id, sender, msg.text and msg.text:sub(1, 60) or "")
					queue_notify('[' .. group_title .. '] ' .. sender .. ': ' .. text)
				end
			end)
		elseif msg.event == "userAction" then
			local state = ui.state
			if state.chat_id and msg.chat_id == state.chat_id then
				vim.schedule(function()
					if msg.action._ == "chatActionCancel" then
						ui.set_typing(msg.chat_id, msg.user_id, nil, nil, false)
					else
						ui.set_typing(msg.chat_id, msg.user_id, msg.user_name, msg.action._, true)
					end
				end)
			end
		elseif msg.event == "chatOnlineMemberCount" then
			vim.schedule(function()
				if ui.state.chat_id and msg.chat_id == ui.state.chat_id then
					ui.set_online_count(msg.online_member_count)
				end
				ui.update_group_online(msg.chat_id, msg.online_member_count)
			end)
		end
	end)
	initialized = true
	vim.notify("[tg] Ready", vim.log.levels.INFO)
end

---@param force_picker boolean|nil
function M.list_groups(force_picker)
	force_picker = force_picker == true
	local function show_groups(f_picker)
		local groups = server.get_groups()
		if not groups then
			vim.notify("[tg] No groups found", vim.log.levels.WARN)
			return
		end
		if #groups == 0 then
			vim.notify("[tg] Syncing chats, please wait...", vim.log.levels.INFO)
			local ok = vim.wait(15000, function()
				vim.wait(1000)
				groups = server.get_groups()
				return groups and #groups > 0
			end, 0, true)
			if not ok or not groups or #groups == 0 then
				vim.notify("[tg] No groups found", vim.log.levels.WARN)
				return
			end
		end
		ui.set_groups(groups)
		if not f_picker then
			if ui.state.last_chat and not (ui.state.layout and ui.state.layout._.mounted) then
				ui.open_chat(ui.state.last_chat.id, ui.state.last_chat.title)
				return
			end
			if ui.state.layout and ui.state.layout._.mounted then
				ui.refresh_messages()
				return
			end
			if #groups > 0 then
				ui.open_chat(groups[1].id, groups[1].title)
				return
			end
		end
		local items = {}
		for _, g in ipairs(groups) do
			local desc = ""
			if g.lastMessage then
				local s = g.lastMessage.sender and g.lastMessage.sender.name or "?"
				desc = s .. ": " .. (g.lastMessage.text:len() > 60 and g.lastMessage.text:sub(1, 60) .. "…" or g.lastMessage.text)
			end
			local member_info = g.memberCount and (" (" .. g.memberCount .. " members)") or ""
			table.insert(items, { id = g.id, label = g.title .. member_info, detail = desc })
		end
		vim.ui.select(items, {
			prompt = "Select a group:",
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if choice then
				ui.close_chat()
				ui.open_chat(choice.id, choice.label)
			end
		end)
	end

	if not initialized then
		vim.notify("[tg] Starting server...", vim.log.levels.INFO)
		vim.defer_fn(function()
			if not config.ensure_deps() then return end
			if not server.start_server() then return end
			local health = server.server_health()
			if health and health.ready == true then
				finish_init()
				show_groups(force_picker)
			else
				vim.notify("[tg] Waiting for auth...", vim.log.levels.INFO)
				auth.auth_poll(function(success)
					if success then
						finish_init()
						show_groups(force_picker)
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
	show_groups(force_picker)
end

function M.logout()
	vim.notify("[tg] Logging out and clearing auth data...", vim.log.levels.INFO)
	ui.close_chat()
	ui.state.last_chat = nil
	server.stop_server()
	local db_dir = config.config.data_dir .. "/tdlib_db"
	local files_dir = config.config.data_dir .. "/tdlib_files"
	vim.fn.delete(db_dir, "rf")
	vim.fn.delete(files_dir, "rf")
	initialized = false
	vim.notify("[tg] Logged out. Run :Tg again to re-authenticate", vim.log.levels.INFO)
end

-- API re-exports
M.get_groups = server.get_groups
M.get_messages = server.get_messages
M.send_message = server.send_message
M.edit_message = server.edit_message
M.delete_message = server.delete_message
M.forward_messages = server.forward_messages
M.ws_start = ws.ws_start
M.ws_stop = ws.ws_stop
M.open_chat = ui.open_chat

-- Cleanup on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("TgCleanup", { clear = true }),
	callback = function()
		ws.ws_stop()
		server.stop_server()
	end,
})

vim.api.nvim_create_user_command("Tg", M.list_groups, {})
vim.api.nvim_create_user_command("TgLogout", M.logout, {})
vim.api.nvim_create_user_command("TgGroups", function()
	M.list_groups(true)
end, {})
vim.api.nvim_create_user_command("TgSend", function(opts)
	local args = vim.fn.split(opts.args)
	if #args < 2 then
		vim.notify("[tg] Usage: TgSend <chatId> <text>", vim.log.levels.ERROR)
		return
	end
	local chat_id = tonumber(args[1])
	if not chat_id then
		vim.notify("[tg] chatId must be a number", vim.log.levels.ERROR)
		return
	end
	local text = table.concat(args, " ", 2)
	if server.send_message(chat_id, text) then
		vim.notify("[tg] Message sent", vim.log.levels.INFO)
	end
end, { nargs = "+" })

return M
