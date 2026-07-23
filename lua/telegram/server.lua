local config = require("telegram.config")

local M = {}

do
	local existing = vim.env.NO_PROXY or ""
	if not existing:find("localhost") then
		vim.env.NO_PROXY = existing .. ",localhost,127.0.0.1,::1"
	end
end

local function http_port()
	return tonumber(vim.env.TG_PORT) or config.config.http_port or 8080
end
M.get_http_port = http_port
local function ws_port()
	return tonumber(vim.env.TG_WS_PORT) or config.config.ws_port or 8081
end
local server_job = nil
local server_pid = nil
local server_owner = false
local _status = "disconnected"

local function base_url()
	return "http://localhost:" .. http_port()
end
local function ws_url_internal()
	return "ws://localhost:" .. ws_port()
end

function M.ws_url()
	return ws_url_internal()
end

---@return string "disconnected"|"connecting"|"connected"|"error"
function M.status()
	return _status
end

local STATUS_COLORS = {
	disconnected = "#6c7086",
	connecting = "#f9e2af",
	connected = "#a6e3a1",
	error = "#f38ba8",
}

---@return { fg: string }
function M.status_color()
	return { fg = STATUS_COLORS[_status] or STATUS_COLORS.disconnected }
end

local RETRY_DELAYS = { 300, 500 }

---@param curl_args string[]
---@return string|nil body, string|nil error_msg
local function curl_with_retry(curl_args)
	for attempt = 1, 2 do
		local result = vim.fn.system(curl_args)
		if vim.v.shell_error == 0 then
			return result
		end
		if result and #result > 0 then
			local ok, data = pcall(vim.json.decode, result)
			local err = (ok and type(data) == "table" and data.error) or result
			return nil, err
		end
		if attempt < 2 then
			vim.wait(RETRY_DELAYS[attempt])
		end
	end
	return nil, "connection failed after 4 retries"
end

---@param path string
---@return table|nil
local function http_get(path)
	local result, err = curl_with_retry({ "curl", "-s", "--noproxy", "*", "--fail-with-body", "--connect-timeout", "2", "--max-time", "5", base_url() .. path })
	if not result then
		vim.notify(err, vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	local ok, data = pcall(vim.json.decode, result)
	if not ok then
		vim.notify("Invalid response from server", vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	if type(data) == "table" and data.error then
		vim.notify(data.error, vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	return data
end

---@param path string
---@param body table
---@return table|nil
local function http_post(path, body)
	local url = base_url() .. path
	local encoded = vim.json.encode(body)
	local result, err = curl_with_retry({
		"curl",
		"-s",
		"--noproxy", "*",
		"--fail-with-body",
		"--connect-timeout", "2",
		"--max-time", "5",
		"-X",
		"POST",
		url,
		"-H",
		"Content-Type: application/json",
		"-d",
		encoded,
	})
	if not result then
		vim.notify(err, vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	local ok, data = pcall(vim.json.decode, result)
	if not ok then
		vim.notify("Invalid response from server", vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	if type(data) == "table" and data.error then
		vim.notify(data.error, vim.log.levels.ERROR, { title = "tg" })
		return nil
	end
	return data
end

---@param opts { url: string, body?: string }
---@param callback fun(data: table|nil, err: string|nil)
local function request_curl(opts, callback)
	local args = { "curl", "-s", "--noproxy", "*", "--connect-timeout", "3", "--max-time", "15" }
	if opts.body then
		table.insert(args, "-X"); table.insert(args, "POST")
		table.insert(args, "-H"); table.insert(args, "Content-Type: application/json")
		table.insert(args, "-d"); table.insert(args, opts.body)
	end
	table.insert(args, opts.url)
	local stdout = {}
	vim.fn.jobstart(args, {
		stdout_buffered = true,
		on_stdout = function(_, data) stdout = data end,
		on_exit = function(_, code)
			if code ~= 0 then callback(nil, "curl exit " .. code) return end
			local ok, data = pcall(vim.json.decode, table.concat(stdout))
			if not ok then callback(nil, "Invalid JSON response") return end
			if type(data) == "table" and data.error then callback(nil, data.error) return end
			callback(data, nil)
		end,
	})
end

local function request_async(opts, callback)
	if vim.net and vim.net.request then
		local ok2, result = pcall(vim.net.request, opts.url, {
			method = opts.body and "POST" or "GET",
			headers = opts.body and { ["Content-Type"] = "application/json" } or nil,
			body = opts.body,
			timeout = 15000,
		}, function(...)
			local args = { ... }
			if args[1] then
				callback(nil, args[1])
				return
			end
			local data, status = args[2], args[3]
			if type(data) == "table" and data.body then
				status = data.status or status
				local ok, d = pcall(vim.json.decode, data.body)
				if ok then data = d end
			end
			if type(data) == "string" then
				local ok, d = pcall(vim.json.decode, data)
				if ok then data = d end
			end
			if type(data) ~= "table" then
				callback(nil, "invalid response: " .. tostring(data))
				return
			end
			status = tonumber(status) or 200
			if status >= 400 or data.error then
				callback(nil, data.error or ("HTTP " .. tostring(status)))
				return
			end
			callback(data, nil)
		end)
		if not ok2 then
			vim.notify("vim.net.request call failed: " .. tostring(result), vim.log.levels.ERROR, { title = "tg" })
			request_curl(opts, callback)
		end
	else
		request_curl(opts, callback)
	end
end

---@return table|nil
function M.server_health()
	local r = vim.fn.system({ "curl", "-s", "--noproxy", "*", "--connect-timeout", "1", "--max-time", "2", base_url() .. "/health" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local ok, data = pcall(vim.json.decode, r)
	if not ok or type(data) ~= "table" then
		return nil
	end
	_status = data.ready == true and "connected" or "connecting"
	return data
end

---@param value string
---@return boolean
function M.post_auth_input(value)
	local url = base_url() .. "/auth/input"
	local encoded = vim.json.encode({ value = value })
	vim.fn.system({
		"curl",
		"-s",
		"--noproxy", "*",
		"--connect-timeout", "2",
		"--max-time", "5",
		"-X",
		"POST",
		url,
		"-H",
		"Content-Type: application/json",
		"-d",
		encoded,
	})
	return vim.v.shell_error == 0
end

---@return '"free"'|'"ready"'|'"ours"'|'"other"'
local function check_port()
	local r = vim.fn.system({ "curl", "-s", "--noproxy", "*", "--connect-timeout", "1", "--max-time", "2", base_url() .. "/health" })
	if vim.v.shell_error ~= 0 then
		return "free"
	end
	local ok, data = pcall(vim.json.decode, r)
	if ok and type(data) == "table" then
		if data.ready == true then
			return "ready"
		end
		if data.ready == false then
			return "ours"
		end
	end
	return "other"
end

---@return boolean
local function server_wait_reachable()
	for _ = 1, 10 do
		if M.server_health() then
			return true
		end
		vim.wait(500)
	end
	return false
end

---@return boolean
function M.start_server()
	local status = check_port()
	if status == "ready" then
		_status = "connected"
		return true
	end
	if status == "ours" then
		_status = "connecting"
		return server_wait_reachable()
	end
	if status == "other" then
		_status = "error"
		vim.notify("Port " .. http_port() .. " is occupied by another process", vim.log.levels.WARN, { title = "tg" })
		return false
	end
	_status = "connecting"
	server_owner = true
	local env = {
		TG_DATA_DIR = config.config.data_dir,
		TG_PORT = tostring(http_port()),
		TG_WS_PORT = tostring(ws_port()),
	}
	if config.config.tdlib_path then
		env.TG_TDLIB_PATH = config.config.tdlib_path
	end
	if config.config.api_id then
		env.TG_API_ID = tostring(config.config.api_id)
	end
	if config.config.api_hash then
		env.TG_API_HASH = config.config.api_hash
	end
	if config.config.proxy then
		env.TG_PROXY = config.config.proxy
	end
	local server_script = config.plugin_root .. "/src/server.ts"
	server_job = vim.fn.jobstart({ "npx", "tsx", server_script }, {
		cwd = config.plugin_root,
		env = env,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line and #line > 0 then
					if line:find("Error:") or line:find("MODULE_NOT_FOUND") then
						vim.notify(line, vim.log.levels.ERROR, { title = "tg" })
					end
				end
			end
		end,
		on_exit = function(_, code)
			_status = "disconnected"
			if code > 0 then
				vim.notify("Server exited with code " .. code, vim.log.levels.ERROR, { title = "tg" })
			end
			server_job = nil
		end,
	})
	if not server_job or server_job <= 0 then
		vim.notify("Failed to start server", vim.log.levels.ERROR, { title = "tg" })
		return false
	end
	server_pid = vim.fn.jobpid(server_job)
	local ok = server_wait_reachable()
	if not ok then _status = "error" end
	return ok
end

function M.stop_server()
	if not server_owner then
		return
	end
	_status = "disconnected"
	if server_pid then
		vim.fn.system({ "kill", tostring(server_pid) })
		server_pid = nil
	end
	if server_job then
		vim.fn.jobstop(server_job)
		server_job = nil
	end
	server_owner = false
end

---@param chat_id any
---@return table|nil
function M.get_chat(chat_id)
	return http_get("/chat?chatId=" .. chat_id)
end

---@param chat_id any
---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_chat_async(chat_id, on_ok, on_err)
	request_async({ url = base_url() .. "/chat?chatId=" .. chat_id }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param chat_id any
---@return boolean
function M.open_chat(chat_id)
	return http_post("/chat/open", { chatId = chat_id }) ~= nil
end

---@param chat_id any
function M.open_chat_async(chat_id)
	request_async({ url = base_url() .. "/chat/open", body = vim.json.encode({ chatId = chat_id }) }, function() end)
end

---@param chat_id any
---@param message_id any
function M.view_messages(chat_id, message_id)
	http_post("/chat/viewMessages", { chatId = chat_id, messageId = message_id })
end

---@param chat_id any
---@return boolean
function M.close_chat(chat_id)
	request_async({ url = base_url() .. "/chat/close", body = vim.json.encode({ chatId = chat_id }) }, function() end)
end

---@param chat_id any
---@param action string  e.g. 'chatActionTyping'
---@return boolean
function M.send_chat_action(chat_id, action)
	return http_post("/chat/action", { chatId = chat_id, action = action }) ~= nil
end

---@param chat_id any
---@param action string
function M.send_chat_action_async(chat_id, action)
	request_async({ url = base_url() .. "/chat/action", body = vim.json.encode({ chatId = chat_id, action = action }) }, function() end)
end

---@type integer
M.DEFAULT_LIMIT = 50

---@return table|nil
function M.get_chats()
	return http_get("/chats")
end

---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_chats_async(on_ok, on_err)
	request_async({ url = base_url() .. "/chats" }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param username string
---@return table|nil
function M.search_user(username)
	return http_post("/chats/searchUser", { username = username })
end

---@param user_id number
---@return table|nil
function M.open_private_chat(user_id)
	return http_post("/chats/openByUserId", { userId = user_id })
end

---@return table|nil
function M.get_saved_chat()
	return http_get("/chats/saved")
end

---@return table|nil
function M.get_groups()
	return http_get("/groups")
end

---@param chat_id any
---@param message_id any
---@return table|nil
function M.get_message(chat_id, message_id)
	return http_get("/message?chatId=" .. chat_id .. "&messageId=" .. message_id)
end

---@param chat_id any
---@param message_id any
---@param on_ok fun(data: table)|nil
function M.get_pinned_message_async(chat_id, message_id, on_ok)
	request_async({ url = base_url() .. "/message?chatId=" .. chat_id .. "&messageId=" .. message_id }, function(data, err)
		if not err and data and on_ok then
			vim.schedule(function() on_ok(data) end)
		end
	end)
end

---@param chat_id any
---@param query string
---@return table|nil
function M.search_messages(chat_id, query)
	return http_get("/searchMessages?chatId=" .. chat_id .. "&query=" .. vim.uri_encode(query, "RFC3986"))
end

---@param chat_id any
---@param query string
---@param on_ok fun(data: table)
---@param on_err fun()|nil
function M.search_messages_async(chat_id, query, on_ok, on_err)
	request_async({ url = base_url() .. "/searchMessages?chatId=" .. chat_id .. "&query=" .. vim.uri_encode(query, "RFC3986") }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

function M.get_media(chat_id, message_id)
	local url = base_url() .. "/messageMedia?chatId=" .. chat_id .. "&messageId=" .. message_id
	local result = vim.fn.system({ "curl", "-s", "--noproxy", "*", "--connect-timeout", "5", "--max-time", "20", url })
	if vim.v.shell_error ~= 0 or #result == 0 then
		vim.notify("Failed to get media for message " .. message_id, vim.log.levels.WARN, { title = "tg" })
		return nil
	end
	local ok, data = pcall(vim.json.decode, result)
	if ok then
		return data
	end
	vim.notify("Invalid media response for message " .. message_id, vim.log.levels.WARN, { title = "tg" })
	return nil
end

function M.get_media_async(chat_id, message_id, on_ok)
	request_async({ url = base_url() .. "/messageMedia?chatId=" .. chat_id .. "&messageId=" .. message_id }, function(data, err)
		vim.schedule(function() on_ok(err and nil or data) end)
	end)
end

---@param chat_id any
---@param limit integer|nil
---@param before any|nil
---@return table|nil
function M.get_messages(chat_id, limit, before)
	local path = "/messages?chatId=" .. chat_id .. "&limit=" .. (limit or M.DEFAULT_LIMIT)
	if before then
		path = path .. "&before=" .. before
	end
	return http_get(path)
end

---@param chat_id any
---@param limit integer|nil
---@param before any|nil
---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_messages_async(chat_id, limit, before, on_ok, on_err, opts)
	opts = opts or {}
	local path = "/messages?chatId=" .. chat_id .. "&limit=" .. (limit or M.DEFAULT_LIMIT)
	if before then
		path = path .. "&before=" .. before
	end
	if opts.before_date then
		path = path .. "&beforeDate=" .. opts.before_date
	end
	request_async({ url = base_url() .. path }, function(data, err)
		if err then
			if on_err then vim.schedule(function() on_err(err) end) end
		else
			vim.schedule(function() on_ok(data) end)
		end
	end)
end

function M.get_messages_after_async(chat_id, after_id, limit, on_ok, on_err, opts)
	opts = opts or {}
	local url = base_url()
		.. "/messages?chatId="
		.. chat_id
		.. "&limit="
		.. (limit or M.DEFAULT_LIMIT)
		.. "&after="
		.. after_id
	if opts.after_date then
		url = url .. "&afterDate=" .. opts.after_date
	end
	request_async({ url = url }, function(data, err)
		if err then if on_err then vim.schedule(function() on_err(err) end) end else vim.schedule(function() on_ok(data) end) end
	end)
end

function M.get_messages_around_async(chat_id, message_id, limit, on_ok, on_err)
	local url = base_url()
		.. "/messages/around?chatId="
		.. chat_id
		.. "&messageId="
		.. message_id
		.. "&limit="
		.. (limit or 11)
	request_async({ url = url }, function(data, err)
		if err then if on_err then vim.schedule(function() on_err(err) end) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param chat_id any
---@param text string
---@param replyTo any|nil
---@return table|nil
function M.send_message(chat_id, text, replyTo)
	local body = { chatId = chat_id, text = text }
	if replyTo then
		body.replyTo = replyTo
	end
	local data = http_post("/sendMessage", body)
	if type(data) == "table" and data.message then
		return data.message
	end
	return nil
end

---@param chat_id any
---@param message_id any
---@param text string
---@return boolean
function M.edit_message(chat_id, message_id, text)
	local data = http_post("/editMessage", { chatId = chat_id, messageId = message_id, text = text })
	if type(data) == "table" and data.message then
		return data.message
	end
	return nil
end

---@param chat_id any
---@param message_id any
---@param revoke boolean|nil
---@return boolean
function M.delete_message(chat_id, message_id, revoke)
	return http_post("/deleteMessage", { chatId = chat_id, messageId = message_id, revoke = revoke })
end

---@param from_chat_id any
---@param message_ids any|any[]
---@param to_chat_id any
---@return boolean
function M.forward_messages(from_chat_id, message_ids, to_chat_id)
	return http_post("/forwardMessages", { fromChatId = from_chat_id, messageIds = message_ids, toChatId = to_chat_id })
end

---@param chat_id any
---@param message_id any
---@return boolean
function M.pin_message(chat_id, message_id)
	return http_post("/pinMessage", { chatId = chat_id, messageId = message_id }) ~= nil
end

---@param chat_id any
---@param message_id any
---@return boolean
function M.unpin_message(chat_id, message_id)
	return http_post("/unpinMessage", { chatId = chat_id, messageId = message_id }) ~= nil
end

-- ─── Member Management ─────────────────────────────────────────────────

---@param chat_id any
---@param user_id any
---@return boolean
function M.ban_member(chat_id, user_id)
	return http_post("/chat/ban", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return boolean
function M.unban_member(chat_id, user_id)
	return http_post("/chat/unban", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return boolean
function M.promote_member(chat_id, user_id)
	return http_post("/chat/promote", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return boolean
function M.demote_member(chat_id, user_id)
	return http_post("/chat/demote", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return boolean
function M.restrict_member(chat_id, user_id)
	return http_post("/chat/restrict", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return boolean
function M.unrestrict_member(chat_id, user_id)
	return http_post("/chat/unrestrict", { chatId = chat_id, userId = user_id }) ~= nil
end

---@param chat_id any
---@param user_id any
---@return table|nil
function M.add_member(chat_id, user_id)
	return http_post("/chat/add-member", { chatId = chat_id, userId = user_id })
end

---@param chat_id any
---@return table|nil
function M.get_my_permissions(chat_id)
	return http_get("/chat/my-permissions?chatId=" .. chat_id)
end

---@param chat_id any
---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_my_permissions_async(chat_id, on_ok, on_err)
	request_async({ url = base_url() .. "/chat/my-permissions?chatId=" .. chat_id }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param chat_id any
---@return table|nil
function M.get_members(chat_id)
	return http_get("/chat/members?chatId=" .. chat_id)
end

---@param chat_id any
---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_members_async(chat_id, on_ok, on_err)
	request_async({ url = base_url() .. "/chat/members?chatId=" .. chat_id }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param chat_id any
---@param restrict_all boolean
---@return boolean
function M.set_default_permissions(chat_id, perms)
	return http_post("/chat/set-permissions", { chatId = chat_id, permissions = perms }) ~= nil
end

-- ─── Group Settings ─────────────────────────────────────────────────────

---@param chat_id any
---@param title string
---@return boolean
function M.set_chat_title(chat_id, title)
	return http_post("/chat/set-title", { chatId = chat_id, title = title }) ~= nil
end

---@param chat_id any
---@param description string
---@return boolean
function M.set_chat_description(chat_id, description)
	return http_post("/chat/set-description", { chatId = chat_id, description = description }) ~= nil
end

---@param chat_id any
---@return boolean
function M.leave_chat(chat_id)
	return http_post("/chat/leave", { chatId = chat_id }) ~= nil
end

---@param chat_id any
---@return boolean
function M.delete_chat_history(chat_id)
	return http_post("/chat/delete-history", { chatId = chat_id }) ~= nil
end

-- ─── Archive ──────────────────────────────────────────────────────────

---@param chat_id any
---@return boolean
function M.archive_chat(chat_id)
	return http_post("/chat/archive", { chatId = chat_id }) ~= nil
end

---@param chat_id any
---@return boolean
function M.unarchive_chat(chat_id)
	return http_post("/chat/unarchive", { chatId = chat_id }) ~= nil
end

---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_archived_chats_async(on_ok, on_err)
	request_async({ url = base_url() .. "/chats/archived" }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

-- ─── Mark Unread ─────────────────────────────────────────────────────

---@param chat_id any
---@param is_unread boolean
---@return boolean
function M.mark_chat_unread(chat_id, is_unread)
	return http_post("/chat/mark-unread", { chatId = chat_id, isMarkedAsUnread = is_unread }) ~= nil
end

-- ─── Mute ──────────────────────────────────────────────────────────────

---@param chat_id any
---@param mute_for integer|nil  Seconds to mute (default: forever)
---@return boolean
function M.mute_chat(chat_id, mute_for)
	return http_post("/chat/mute", { chatId = chat_id, muteFor = mute_for }) ~= nil
end

---@param chat_id any
---@return boolean
function M.unmute_chat(chat_id)
	return http_post("/chat/unmute", { chatId = chat_id }) ~= nil
end

-- ─── Reactions ──────────────────────────────────────────────────────────

---@param chat_id any
---@param message_id any
---@param emoji string
---@return table|nil
function M.add_reaction(chat_id, message_id, emoji)
	local url = base_url() .. "/message/reaction/add"
	local body = vim.json.encode({ chatId = chat_id, messageId = message_id, emoji = emoji })
	local res = vim.fn.system({ "curl", "-s", "--noproxy", "*", "--connect-timeout", "2", "--max-time", "5", "-X", "POST", url, "-H", "Content-Type: application/json", "-d", body })
	if vim.v.shell_error ~= 0 then return nil end
	local ok, data = pcall(vim.json.decode, res)
	if ok and type(data) == "table" then
		if data.error then
			vim.notify(data.error, vim.log.levels.WARN, { title = "tg" })
		end
		return data
	end
	return nil
end

---@param chat_id any
---@param message_id any
---@param emoji string
---@return table|nil
function M.remove_reaction(chat_id, message_id, emoji)
	local url = base_url() .. "/message/reaction/remove"
	local body = vim.json.encode({ chatId = chat_id, messageId = message_id, emoji = emoji })
	local res = vim.fn.system({ "curl", "-s", "--noproxy", "*", "--connect-timeout", "2", "--max-time", "5", "-X", "POST", url, "-H", "Content-Type: application/json", "-d", body })
	if vim.v.shell_error ~= 0 then return nil end
	local ok, data = pcall(vim.json.decode, res)
	if ok and type(data) == "table" then
		if data.error then
			vim.notify(data.error, vim.log.levels.WARN, { title = "tg" })
		end
		return data
	end
	return nil
end

-- ─── Invite Links ──────────────────────────────────────────────────────

---@param chat_id any
---@return table|nil
function M.get_invite_links(chat_id)
	return http_get("/chat/invite-links?chatId=" .. chat_id)
end

---@param chat_id any
---@param on_ok fun(data: table)|nil
---@param on_err fun()|nil
function M.get_invite_links_async(chat_id, on_ok, on_err)
	request_async({ url = base_url() .. "/chat/invite-links?chatId=" .. chat_id }, function(data, err)
		if err then if on_err then vim.schedule(on_err) end else vim.schedule(function() on_ok(data) end) end
	end)
end

---@param chat_id any
---@param expire_date integer|nil
---@param member_limit integer|nil
---@return table|nil
function M.create_invite_link(chat_id, expire_date, member_limit)
	local body = { chatId = chat_id }
	if expire_date then body.expireDate = expire_date end
	if member_limit then body.memberLimit = member_limit end
	return http_post("/chat/create-invite-link", body)
end

---@param chat_id any
---@param invite_link string
---@param expire_date integer|nil
---@param member_limit integer|nil
---@return boolean
function M.edit_invite_link(chat_id, invite_link, expire_date, member_limit)
	local body = { chatId = chat_id, inviteLink = invite_link }
	if expire_date then body.expireDate = expire_date end
	if member_limit then body.memberLimit = member_limit end
	return http_post("/chat/edit-invite-link", body) ~= nil
end

---@param chat_id any
---@param invite_link string
---@return boolean
function M.revoke_invite_link(chat_id, invite_link)
	return http_post("/chat/revoke-invite-link", { chatId = chat_id, inviteLink = invite_link }) ~= nil
end

return M
