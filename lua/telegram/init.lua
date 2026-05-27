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
local tools = require("telegram.tools")

local M = {}

local initialized = false
local seen_ids = {}
local seen_ids_order = {}
local SEEN_IDS_MAX = 3000

local function trim_seen_ids(chat_key)
	local keys = seen_ids[chat_key]
	if not keys then
		return
	end
	local n = 0
	for _ in pairs(keys) do
		n = n + 1
	end
	if n <= SEEN_IDS_MAX then
		return
	end
	local order = seen_ids_order[chat_key] or {}
	local excess = n - SEEN_IDS_MAX
	for i = 1, excess do
		local id = order[i]
		if id then
			keys[id] = nil
		end
	end
	for i = 1, excess do
		table.remove(order, 1)
	end
end

local notify_queue = {}
local notify_timer_id = nil

local function flush_notify()
	if #notify_queue == 0 then
		return
	end
	local lines = table.concat(notify_queue, "\n")
	notify_queue = {}
	notify_timer_id = nil
	vim.notify(lines, vim.log.levels.INFO, { title = "tg" })
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
				local sender = msg.sender and msg.sender.name or "?"
				local text = (msg.text or ""):gsub("\n", " "):sub(1, 50)

				if is_current then
					if
						not st.buf
						or not st.win
						or not vim.api.nvim_buf_is_valid(st.buf)
						or not vim.api.nvim_win_is_valid(st.win)
					then
						return
					end
					local total_before = vim.api.nvim_buf_line_count(st.buf)
					local cur = vim.api.nvim_win_get_cursor(st.win)
					local at_bottom = cur[1] >= total_before - 1
					if not at_bottom then
						st.unread = st.unread + 1
						if st.groups[st.chat_id] then
							st.groups[st.chat_id].unread_count = st.unread
						end
						queue_notify(sender .. ": " .. text)
					end
					local ts = os.date("%m-%d %H:%M", msg.date)
					local preview = "["
						.. ts
						.. "] "
						.. (msg.sender and msg.sender.name or "?")
						.. ": "
						.. (msg.text or "")
					st.last_msg = preview:sub(1, 60)
					ui.update_title()
					local mid = msg.id
					if mid ~= nil then
						local chat_key = msg.chat and tostring(msg.chat.id) or "_"
						if not seen_ids[chat_key] then
							seen_ids[chat_key] = {}
							seen_ids_order[chat_key] = {}
						end
						if seen_ids[chat_key][mid] then
							return
						end
						seen_ids[chat_key][mid] = true
						table.insert(seen_ids_order[chat_key], mid)
						trim_seen_ids(chat_key)
						for _, m in ipairs(st.messages) do
							if tostring(m.id) == tostring(mid) then
								return
							end
						end
					else
						mid = os.time() .. math.random()
					end
					table.insert(st.messages, {
						id = mid,
						type = msg.type,
						date = msg.date,
						sender = msg.sender,
						text = msg.text,
						own = msg.own,
						replyTo = msg.replyTo,
					})
					ui.render()
					if at_bottom then
						pcall(vim.api.nvim_win_set_cursor, st.win, { vim.api.nvim_buf_line_count(st.buf) - 1, cur[2] })
					end
					st.exhausted = false
					st.exhausted_forward = false
				else
					local group_title = msg.chat and msg.chat.title or "?"
					ui.update_group_last_msg(msg.chat and msg.chat.id, sender, msg.text and msg.text:sub(1, 60) or "")
					queue_notify("[" .. group_title .. "] " .. sender .. ": " .. text)
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
	vim.notify("Ready", vim.log.levels.INFO, { title = "tg" })
end

local function finish_open(groups)
	ui.set_groups(groups or {})
	ui.destroy_chat()
	if groups and #groups > 0 then
		ui.open_chat(groups[1].id, groups[1].title)
	end
end

local function poll_groups(remaining, groups)
	if remaining <= 0 then
		finish_open(groups or {})
		return
	end
	groups = server.get_groups()
	if groups and #groups > 1 then
		finish_open(groups)
		return
	end
	vim.defer_fn(function()
		poll_groups(remaining - 1, groups)
	end, 1000)
end

function M.list_groups()
	local function show_groups()
		if ui.state.mounted then
			ui.refresh_messages()
			return
		end

		if ui.state.buf and not vim.api.nvim_buf_is_valid(ui.state.buf) then
			ui.state.buf = nil
			ui.state.win = nil
		end

		local groups = server.get_groups()
		if not groups then
			vim.notify("No groups found", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if #groups <= 1 then
			vim.notify("Syncing chats, please wait...", vim.log.levels.INFO, { title = "tg" })
			poll_groups(15, groups)
			return
		end
		finish_open(groups)
	end

	if not initialized then
		vim.notify("Starting server...", vim.log.levels.INFO, { title = "tg" })
		vim.defer_fn(function()
			if not config.ensure_deps() then
				return
			end
			if not server.start_server() then
				return
			end
			local health = server.server_health()
			if health and health.ready == true then
				finish_init()
				show_groups()
			else
				vim.notify("Waiting for auth...", vim.log.levels.INFO, { title = "tg" })
				auth.auth_poll(function(success)
					if success then
						finish_init()
						show_groups()
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

	local groups = server.get_groups()
	if groups and #groups > 0 then
		ui.open_chat(groups[1].id, groups[1].title)
	else
		vim.notify("No groups available", vim.log.levels.WARN, { title = "tg" })
	end
end

function M.logout()
	vim.notify("Logging out and clearing auth data...", vim.log.levels.INFO, { title = "tg" })
	ui.destroy_chat()
	ui.state.last_chat = nil
	server.stop_server()
	local db_dir = config.config.data_dir .. "/tdlib_db"
	local files_dir = config.config.data_dir .. "/tdlib_files"
	vim.fn.delete(db_dir, "rf")
	vim.fn.delete(files_dir, "rf")
	initialized = false
	vim.notify("Logged out. Run :Tg again to re-authenticate", vim.log.levels.INFO, { title = "tg" })
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

local function git(args)
	return vim.fn.systemlist(vim.list_extend({ "git", "-C", config.plugin_root }, vim.split(args, " ")))
end

local function current_branch()
	local out = git("rev-parse --abbrev-ref HEAD")
	if vim.v.shell_error ~= 0 or #out == 0 then
		return "main"
	end
	return out[1]
end

vim.api.nvim_create_user_command("TgPr", function()
	if vim.fn.executable("gh") ~= 1 then
		vim.notify(
			"gh (GitHub CLI) not found. Install it first:\n  sudo pacman -S github-cli  # Arch\n  brew install gh            # macOS",
			vim.log.levels.ERROR,
			{ title = "tg" }
		)
		return
	end
	vim.notify("Checking environment...", vim.log.levels.INFO, { title = "tg" })
	local cur = current_branch()
	local src, title, can_merge_main
	local dst = "main"

	local function check_perm(cb)
		vim.notify("Checking permissions...", vim.log.levels.INFO, { title = "tg" })
		vim.fn.jobstart({ "gh", "api", "repos/ChuYanLon/telegram.nvim", "-q", ".permissions.admin" }, {
			stdout_buffered = true,
			on_stdout = function(_, d)
				can_merge_main = d and d[1] and d[1]:match("true")
			end,
			on_exit = function()
				vim.schedule(cb)
			end,
		})
	end

	local function pick_title()
		vim.ui.input({ prompt = "PR title (optional): " }, function(t)
			title = t or ""
			local args = { "pr", "create", "--base", dst, "--head", src, "--repo", "ChuYanLon/telegram.nvim" }
			if title and #title > 0 then
				vim.list_extend(args, { "--title", title, "--fill" })
			else
				local last = git("log -1 --format=%s")
				vim.list_extend(
					args,
					{ "--title", (vim.v.shell_error == 0 and #last > 0 and last[1]) or src, "--fill" }
				)
			end

			vim.notify("Creating PR " .. src .. " → " .. dst .. "...", vim.log.levels.INFO, { title = "tg" })

			local stdout = {}
			vim.fn.jobstart({ "gh", unpack(args) }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					stdout = data
				end,
				on_exit = function(_, code)
					if code ~= 0 then
						vim.schedule(function()
							vim.notify("PR creation failed", vim.log.levels.ERROR, { title = "tg" })
						end)
						return
					end
					local url = table.concat(stdout, "\n"):match("https[%w:/.%-]+")
					vim.schedule(function()
						vim.notify("PR created: " .. (url or "?"), vim.log.levels.INFO, { title = "tg" })
						if url then
							local pr_num = url:match("/(%d+)$")
							if pr_num and can_merge_main then
								vim.ui.select({ "Merge (squash)", "Merge (commit)", "No (just PR)" }, {
									prompt = "Merge PR #" .. pr_num .. " to " .. dst .. "?",
								}, function(choice)
									if not choice or choice:match("^No") then
										return
									end
									local flag = choice:match("squash") and "--squash" or "--merge"
									vim.notify(
										"Merging (" .. flag:gsub("^%-%-", "") .. ")...",
										vim.log.levels.INFO,
										{ title = "tg" }
									)
									vim.fn.jobstart({
										"gh",
										"pr",
										"merge",
										pr_num,
										"--repo",
										"ChuYanLon/telegram.nvim",
										flag,
										"--admin",
										"--delete-branch",
									}, {
										on_exit = function(_, mc)
											vim.schedule(function()
												if mc == 0 then
													vim.notify("Merged!", vim.log.levels.INFO, { title = "tg" })
													if src ~= "main" then
														local root = vim.fn.shellescape(config.plugin_root)
														vim.fn.jobstart({
															"sh",
															"-c",
															"cd "
																.. root
																.. " && git branch -D "
																.. vim.fn.shellescape(src)
																.. " 2>/dev/null; true",
														})
													end
												else
													vim.notify("Merge failed", vim.log.levels.ERROR, { title = "tg" })
												end
											end)
										end,
									})
								end)
							end
						end
					end)
				end,
			})
		end)
	end

	local sources = vim.tbl_filter(function(b)
		return b ~= "main"
	end, git("branch --format=%(refname:short)"))
	if #sources == 0 then
		vim.notify("No feature branch to create PR from", vim.log.levels.WARN, { title = "tg" })
		return
	end

	check_perm(function()
		vim.ui.select(sources, {
			prompt = "Source branch",
			format_item = function(b)
				return (b == cur and b .. " (current)" or b)
			end,
		}, function(choice)
			if not choice then
				return
			end
			src = choice
			pick_title()
		end)
	end)
end, {})

vim.api.nvim_create_user_command("Tg", M.list_groups, {})
vim.api.nvim_create_user_command("TgLogout", M.logout, {})
vim.api.nvim_create_user_command("TgSend", function(opts)
	local args = vim.fn.split(opts.args)
	if #args < 2 then
		vim.notify("Usage: TgSend <chatId> <text>", vim.log.levels.ERROR, { title = "tg" })
		return
	end
	local chat_id = tonumber(args[1])
	if not chat_id then
		vim.notify("chatId must be a number", vim.log.levels.ERROR, { title = "tg" })
		return
	end
	local text = table.concat(args, " ", 2)
	if server.send_message(chat_id, text) then
		vim.notify("Message sent", vim.log.levels.INFO, { title = "tg" })
	end
end, { nargs = "+" })

vim.api.nvim_create_user_command("TgTool", function()
	tools.pick()
end, {})

vim.api.nvim_create_user_command("TgIssue", function()
	if vim.fn.executable("gh") ~= 1 then
		vim.notify("gh (GitHub CLI) not found", vim.log.levels.ERROR, { title = "tg" })
		return
	end
	vim.ui.select({
		"List issues",
		"Create issue (web)",
	}, {
		prompt = "Issue actions",
	}, function(choice)
		if not choice then
			return
		end

		if choice:match("List") then
			vim.notify("Fetching issues...", vim.log.levels.INFO, { title = "tg" })
			local git_root = vim.fn.shellescape(config.plugin_root)
			local is_admin = false
			vim.fn.jobstart({ "gh", "api", "repos/ChuYanLon/telegram.nvim", "-q", ".permissions.admin" }, {
				stdout_buffered = true,
				on_stdout = function(_, d)
					is_admin = d and d[1] and d[1]:match("true")
				end,
				on_exit = function()
					vim.schedule(function()
						local stdout = {}
						vim.fn.jobstart({
							"gh",
							"issue",
							"list",
							"--repo",
							"ChuYanLon/telegram.nvim",
							"--assignee",
							"@me",
							"--limit",
							"20",
							"--json",
							"number,title,labels,assignees",
						}, {
							stdout_buffered = true,
							on_stdout = function(_, data)
								stdout = data
							end,
							on_exit = function()
								vim.schedule(function()
									local ok, issues = pcall(vim.json.decode, table.concat(stdout, "\n"))
									if not ok or not issues then
										vim.notify("Failed to parse issues", vim.log.levels.ERROR, { title = "tg" })
										return
									end
									local items = {}
									for _, issue in ipairs(issues) do
										local tags = ""
										for _, l in ipairs(issue.labels or {}) do
											tags = tags .. "[" .. l.name .. "] "
										end
										if issue.assignees and #issue.assignees > 0 then
											tags = tags .. "(" .. issue.assignees[1].login .. ") "
										end
										table.insert(items, {
											num = issue.number,
											label = "#" .. issue.number .. " " .. tags .. issue.title,
										})
									end
									vim.ui.select(items, {
										prompt = "Select issue",
										format_item = function(item)
											return item.label
										end,
									}, function(issue)
										if not issue then
											return
										end
										vim.ui.select({
											"Create branch",
											"Open in browser",
											"Close issue",
										}, {
											prompt = "#" .. issue.num .. " — what next?",
										}, function(action)
											if not action then
												return
											end

											if action:match("branch") then
												local prefixes = { "fix", "feat", "chore", "docs", "refactor", "style" }
												vim.ui.select(prefixes, { prompt = "Branch type" }, function(prefix)
													if not prefix then
														return
													end
													vim.ui.input(
														{ prompt = "Branch description (required): " },
														function(desc)
															if not desc or #desc == 0 then
																return
															end
															local branch = prefix .. "/" .. issue.num .. "-" .. desc
															local cmd = "cd "
																.. git_root
																.. " && git checkout main && git pull --rebase --autostash origin main && git checkout -b "
																.. vim.fn.shellescape(branch)
															if is_admin then
																cmd = cmd
																	.. " && git push -u origin "
																	.. vim.fn.shellescape(branch)
															else
																cmd = cmd .. " || true"
																vim.notify(
																	"Branch created locally. Push to your fork:\n  git push -u <your-fork> "
																		.. branch,
																	vim.log.levels.INFO,
																	{ title = "tg" }
																)
															end
															vim.notify(
																"Creating branch " .. branch .. "...",
																vim.log.levels.INFO,
																{ title = "tg" }
															)
															local out = {}
															vim.fn.jobstart({
																"sh",
																"-c",
																"(cd "
																	.. git_root
																	.. " && git checkout main && git pull --rebase --autostash origin main && git checkout -b "
																	.. vim.fn.shellescape(branch)
																	.. " && git push -u origin "
																	.. vim.fn.shellescape(branch)
																	.. ") 2>&1",
															}, {
																stdout_buffered = true,
																on_stdout = function(_, data)
																	out = data
																end,
																on_exit = function(_, sc)
																	vim.schedule(function()
																		if sc == 0 or not is_admin then
																			vim.notify(
																				"Branch: " .. branch,
																				vim.log.levels.INFO,
																				{ title = "tg" }
																			)
																		else
																			vim.notify(
																				"Branch creation failed:\n"
																					.. table
																						.concat(out, "\n")
																						:sub(1, 200),
																				vim.log.levels.ERROR,
																				{ title = "tg" }
																			)
																		end
																	end)
																end,
															})
														end
													)
												end)
											elseif action:match("Open") then
												vim.fn.jobstart({
													"sh",
													"-c",
													'xdg-open "https://github.com/ChuYanLon/telegram.nvim/issues/'
														.. issue.num
														.. '" 2>/dev/null || open "https://github.com/ChuYanLon/telegram.nvim/issues/'
														.. issue.num
														.. '" 2>/dev/null || true',
												})
											elseif action:match("Close") then
												vim.fn.jobstart({
													"gh",
													"issue",
													"close",
													tostring(issue.num),
													"--repo",
													"ChuYanLon/telegram.nvim",
												}, {
													on_exit = function()
														vim.schedule(function()
															vim.notify(
																"#" .. issue.num .. " closed",
																vim.log.levels.INFO,
																{ title = "tg" }
															)
														end)
													end,
												})
											end
										end)
									end)
								end)
							end,
						})
					end)
				end,
			})
		elseif choice:match("Create") then
			vim.fn.jobstart({
				"sh",
				"-c",
				'xdg-open "https://github.com/ChuYanLon/telegram.nvim/issues/new/choose" 2>/dev/null || open "https://github.com/ChuYanLon/telegram.nvim/issues/new/choose" 2>/dev/null || true',
			})
		end
	end)
end, {})

return M
