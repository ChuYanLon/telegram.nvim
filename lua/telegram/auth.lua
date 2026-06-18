local server = require("telegram.server")

local M = {}

---@param on_done fun(success: boolean)
function M.auth_poll(on_done)
	local function poll()
		local health = server.server_health()
		if not health then
			vim.defer_fn(poll, 500)
			return
		end
		if health.ready == true then
			on_done(true)
			return
		end
		local a = health.auth
		if not a or a.state == "initializing" then
			vim.defer_fn(poll, 500)
			return
		end
		if a.state == "error" then
			vim.notify(
				"Auth failed: " .. (type(a.error) == "string" and a.error or "unknown"),
				vim.log.levels.ERROR,
				{ title = "tg" }
			)
			on_done(false)
			return
		end
		if (a.state == "waitPhone" or a.state == "waitCode" or a.state == "waitPassword") and a.canInput then
			local prompt
			if a.state == "waitPhone" then
				prompt = "Phone number"
				if type(a.error) == "string" then
					prompt = prompt .. " (" .. a.error .. ")"
				end
			elseif a.state == "waitCode" then
				prompt = "Verification code"
				if type(a.error) == "string" then
					prompt = prompt .. " (" .. a.error .. ")"
				end
			else
				prompt = "2FA password"
				if type(a.hint) == "string" then
					prompt = prompt .. " (hint: " .. a.hint .. ")"
				end
				if type(a.error) == "string" then
					prompt = prompt .. " (" .. a.error .. ")"
				end
			end
			vim.ui.input({ prompt = prompt .. ": " }, function(val)
			if val and #val > 0 then
				server.post_auth_input(val)
				local ack_retries = 60
				local function wait_ack()
					if ack_retries <= 0 then
						vim.notify("Auth ack timed out, retrying...", vim.log.levels.WARN, { title = "tg" })
						vim.defer_fn(poll, 1000)
						return
					end
					ack_retries = ack_retries - 1
					local h = server.server_health()
					if h and h.auth and h.auth.canInput == false then
						vim.defer_fn(poll, 500)
					else
						vim.defer_fn(wait_ack, 200)
					end
				end
				wait_ack()
			else
				vim.notify("Auth cancelled", vim.log.levels.INFO, { title = "tg" })
				on_done(false)
			end
		end)
			return
		end
		vim.defer_fn(poll, 500)
	end
	poll()
end

return M
