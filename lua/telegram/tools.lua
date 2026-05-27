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

M.register("send", {
	description = "Send a message to current chat",
	callback = function()
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

M.register("reply", {
	description = "Reply to the message under cursor",
	callback = function()
		local target = curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Reply: " }, function(text)
			if not text or #text == 0 then
				return
			end
			local msg = server.send_message(ui.state.chat_id, text, target.id)
			if msg then
				table.insert(ui.state.messages, msg)
				ui.render()
				vim.notify("Reply sent", vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

M.register("edit", {
	description = "Edit your own message under cursor",
	callback = function()
		local target = curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		if not target.own then
			vim.notify("Can only edit your own messages", vim.log.levels.WARN, { title = "tg" })
			return
		end
		vim.ui.input({ prompt = "Edit: ", default = target.text or "" }, function(text)
			if not text or #text == 0 then
				return
			end
			local ok = server.edit_message(ui.state.chat_id, target.id, text)
			if ok then
				target.text = text
				ui.render()
				vim.notify("Edited", vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

M.register("delete", {
	description = "Delete/revoke the message under cursor",
	callback = function()
		local target = curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local choices = target.own and { "Revoke (for everyone)", "Delete (for me)", "Cancel" }
			or { "Delete (for me)", "Cancel" }
		vim.ui.select(choices, { prompt = "Delete message?" }, function(choice)
			if not choice or choice == "Cancel" then
				return
			end
			local revoke = choice == "Revoke (for everyone)"
			if server.delete_message(ui.state.chat_id, target.id, revoke) then
				for i = #ui.state.messages, 1, -1 do
					if ui.state.messages[i].id == target.id then
						table.remove(ui.state.messages, i)
						break
					end
				end
				ui.render()
				vim.notify("Message " .. (revoke and "revoked" or "deleted"), vim.log.levels.INFO, { title = "tg" })
			end
		end)
	end,
})

M.register("forward", {
	description = "Forward the message under cursor to another group",
	callback = function()
		local target = curr_msg()
		if not target or not target.id then
			vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local groups = server.get_groups()
		if not groups or #groups == 0 then
			vim.notify("No groups to forward to", vim.log.levels.WARN, { title = "tg" })
			return
		end
		local items = {}
		for _, g in ipairs(groups) do
			table.insert(items, { id = g.id, label = g.title })
		end
		vim.ui.select(items, {
			prompt = "Forward to:",
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if not choice then
				return
			end
			local ok = server.forward_messages(ui.state.chat_id, target.id, choice.id)
			if ok then
				vim.notify("Forwarded to " .. choice.label, vim.log.levels.INFO, { title = "tg" })
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

return M
