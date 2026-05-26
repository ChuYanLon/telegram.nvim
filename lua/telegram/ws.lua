local server = require("telegram.server")

local M = {}

local ws_job_id = nil
local last_ids = {}
local last_ids_order = {}
local LAST_IDS_MAX = 3000
local should_reconnect = false
local reconnect_delay = 1

local function trim_last_ids()
	local n = 0
	for _ in pairs(last_ids) do
		n = n + 1
	end
	if n <= LAST_IDS_MAX then
		return
	end
	local excess = n - LAST_IDS_MAX
	for i = 1, excess do
		local key = last_ids_order[i]
		if key then
			last_ids[key] = nil
		end
	end
	for i = 1, excess do
		table.remove(last_ids_order, 1)
	end
end

local function start_ws_job(on_msg)
	if ws_job_id then
		vim.fn.jobstop(ws_job_id)
		ws_job_id = nil
	end
	local config = require("telegram.config")
	local helper = config.plugin_root .. "/bin/tg-ws-helper.ts"
	ws_job_id = vim.fn.jobstart({ "npx", "tsx", helper, server.ws_url() }, {
		on_stdout = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line and #line > 0 then
					local ok, msg = pcall(vim.json.decode, line)
					if ok and on_msg then
						if msg.id and msg.event == "newMessage" then
							local key = tostring(msg.id)
							if last_ids[key] then
								return
							end
							last_ids[key] = true
							table.insert(last_ids_order, key)
							trim_last_ids()
						end
						on_msg(msg)
					end
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line and #line > 0 then
						vim.notify(line, vim.log.levels.WARN, { title = "tg-ws" })
					end
				end
			end
		end,
		on_exit = function()
			ws_job_id = nil
			if should_reconnect then
				vim.defer_fn(function()
					start_ws_job(on_msg)
				end, reconnect_delay * 1000)
				reconnect_delay = math.min(reconnect_delay * 2, 30)
			end
		end,
	})
end

function M.ws_start(on_msg)
	should_reconnect = true
	reconnect_delay = 1
	start_ws_job(on_msg)
end

function M.ws_stop()
	should_reconnect = false
	if ws_job_id then
		vim.fn.jobstop(ws_job_id)
		ws_job_id = nil
	end
end

return M
