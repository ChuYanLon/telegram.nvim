local config = require("telegram.config")

local M = {}

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
