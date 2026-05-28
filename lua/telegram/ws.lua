local server = require("telegram.server")

local M = {}

local ws_job_id = nil
local should_reconnect = false
local reconnect_delay = 1

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
