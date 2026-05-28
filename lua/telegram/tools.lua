local server = require("telegram.server")
local ui = require("telegram.ui")

local M = {}
local tool_list = {}

function M.register(name, opts)
	M[name] = opts
	table.insert(tool_list, name)
end

function M.run(name, ...)
	local tool = M[name]
	if tool then
		tool.callback(...)
	end
end

function M.pick()
	local items = {}
	for _, name in ipairs(tool_list) do
		local tool = M[name]
		if not tool.condition or tool.condition() then
			table.insert(items, { name = name, label = "@" .. name .. "  " .. tool.description })
		end
	end
	if #items == 0 then
		vim.notify("No tools available for this context", vim.log.levels.INFO, { title = "tg" })
		return
	end
	vim.ui.select(items, {
		prompt = "@ Tools",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if choice then
			M.run(choice.name)
		end
	end)
end

M.register("groups", {
	description = "Switch to another group",
	callback = function()
		local items = {}
		for _, id in ipairs(ui.state.group_ids) do
			local g = ui.state.groups[id]
			if g then
				table.insert(items, { id = g.id, label = g.title })
			end
		end
		if #items == 0 then
			vim.notify("No groups available", vim.log.levels.INFO, { title = "tg" })
			return
		end
		vim.ui.select(items, {
			prompt = "@ groups",
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if choice then
				require("telegram").open_chat(choice.id, choice.label)
			end
		end)
	end,
})

M.register("refresh", {
	description = "Refresh messages",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		ui.refresh_messages()
		vim.notify("Refreshed", vim.log.levels.INFO, { title = "tg" })
	end,
})

M.register("send", {
	description = "Send a message to current chat",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		ui.open_editor("Send", "", function(text)
			if not text then
				return
			end
			local msg = server.send_message(ui.state.chat_id, text)
			if msg then
				table.insert(ui.state.messages, msg)
				ui.render()
			end
		end)
	end,
})

M.register("search", {
	description = "Search message history",
	condition = function() return ui.state.chat_id ~= nil end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Search: " }, function(query)
			if not query or #query == 0 then
				return
			end
			local data = server.search_messages(ui.state.chat_id, query)
			if not data or not data.messages or #data.messages == 0 then
				vim.notify('No results for "' .. query .. '"', vim.log.levels.INFO, { title = "tg" })
				return
			end
			local items = {}
			for _, m in ipairs(data.messages) do
				local name = m.sender and m.sender.name or "?"
				local preview = (m.text or ""):gsub("\n", " "):sub(1, 80)
				table.insert(items, { id = m.id, label = name .. ": " .. preview })
			end
			vim.ui.select(items, {
				prompt = "Search: " .. query,
				format_item = function(item)
					return item.label
				end,
			}, function(choice)
				if choice then
					ui.jump_to_message(choice.id)
				end
			end)
		end)
	end,
})

M.register("refreshmedia", {
	description = "Download and update image for message under cursor",
	condition = function()
		local t = ui.curr_msg()
		return t and t.type and t.type ~= "messageText" and t.type:find("^message")
	end,
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local target = ui.curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local t = target.type or ""
		if t == "messageText" or not t:find("^message") then
			vim.notify("Not a media message", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.notify("Downloading media...", vim.log.levels.INFO, { title = "tg" })
		server.get_media_async(ui.state.chat_id, target.id, function(res)
			if res and res.path and #res.path > 0 then
				target.filePath = res.path
				ui.render()
				vim.notify("Media updated", vim.log.levels.INFO, { title = "tg" })
			else
				vim.notify("No media path found", vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

return M
