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
		table.insert(items, { name = name, label = "@" .. name .. "  " .. tool.description })
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

local function curr_msg()
	local i = ui.message_at_cursor()
	if not i then
		return nil
	end
	return ui.state.messages[i]
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
	callback = function()
		ui.refresh_messages()
		vim.notify("Refreshed", vim.log.levels.INFO, { title = "tg" })
	end,
})

M.register("send", {
	description = "Send a message to current chat",
	callback = function()
		if not ui.state.chat_id then
			vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Message: " }, function(text)
			if not text or #text == 0 then
				return
			end
			local msg = server.send_message(ui.state.chat_id, text)
			if msg then
				table.insert(ui.state.messages, msg)
				ui.render()
				vim.notify("Sent", vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

return M
