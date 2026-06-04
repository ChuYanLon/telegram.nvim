local state = require("telegram.state").state
local server = require("telegram.server")
local emojis = require("telegram.emojis")

local M = {}

local render_cb = nil
local curr_msg_cb = nil

function M.set_render_fn(fn)
	render_cb = fn
end

function M.set_curr_msg_fn(fn)
	curr_msg_cb = fn
end

local function norm_e(e)
	return (e or ""):gsub("\xEF\xB8\x8F", "")
end

function M.toggle_reaction_on(msg, emoji)
	if not msg or not msg.id then return end
	emoji = norm_e(emoji)

	local chosen_emoji
	for _, r in ipairs(msg.reactions or {}) do
		if r.is_chosen then
			chosen_emoji = norm_e(r.emoji)
			break
		end
	end

	local ok = false
	if chosen_emoji then
		if chosen_emoji == emoji then
			local res = server.remove_reaction(state.chat_id, msg.id, emoji)
			ok = res and res.ok == true
		else
			local res = server.add_reaction(state.chat_id, msg.id, emoji)
			ok = res and res.ok == true
		end
	else
		local res = server.add_reaction(state.chat_id, msg.id, emoji)
		ok = res and res.ok == true
	end
	if not ok then return end

	if chosen_emoji then
		if chosen_emoji == emoji then
			local new_reactions = {}
			for _, r in ipairs(msg.reactions or {}) do
				local rc = r.count or 0
				if r.emoji == emoji then
					if rc > 1 then
						table.insert(new_reactions, { emoji = r.emoji, count = rc - 1, is_chosen = false })
					end
				else
					table.insert(new_reactions, r)
				end
			end
			msg.reactions = #new_reactions > 0 and new_reactions or nil
		else
			local new_reactions = {}
			for _, r in ipairs(msg.reactions or {}) do
				local rc = r.count or 0
				if r.emoji == chosen_emoji then
					if rc > 1 then
						table.insert(new_reactions, { emoji = r.emoji, count = rc - 1, is_chosen = false })
					end
				elseif r.emoji == emoji then
					table.insert(new_reactions, { emoji = r.emoji, count = rc + 1, is_chosen = true })
				else
					table.insert(new_reactions, r)
				end
			end
			local found_new = false
			for _, r in ipairs(new_reactions) do
				if r.emoji == emoji then found_new = true; break end
			end
			if not found_new then
				table.insert(new_reactions, { emoji = emoji, count = 1, is_chosen = true })
			end
			msg.reactions = #new_reactions > 0 and new_reactions or nil
		end
	else
		msg.reactions = msg.reactions or {}
		local found = false
		for _, r in ipairs(msg.reactions) do
			if r.emoji == emoji then
				r.count = (r.count or 0) + 1
				r.is_chosen = true
				found = true
				break
			end
		end
		if not found then
			table.insert(msg.reactions, { emoji = emoji, count = 1, is_chosen = true })
		end
	end
	if render_cb then render_cb() end
end

function M.show_reaction_picker()
	local target = curr_msg_cb and curr_msg_cb()
	if not target or not target.id then
		vim.notify("No message at cursor", vim.log.levels.WARN, { title = "tg" })
		return
	end

	local target_ref = target
	local items = {
		{ emoji = "👍" }, { emoji = "👎" }, { emoji = "❤️" }, { emoji = "🔥" }, { emoji = "😢" },
		{ emoji = "😱" }, { emoji = "😨" }, { emoji = "😁" }, { emoji = "😎" },
		{ emoji = "😘" }, { emoji = "😡" }, { emoji = "😈" }, { emoji = "😇" },
		{ emoji = "😴" }, { emoji = "😐" }, { emoji = "🤔" }, { emoji = "🤗" },
		{ emoji = "🤣" }, { emoji = "🤓" }, { emoji = "🤝" }, { emoji = "🙏" },
		{ emoji = "🙈" }, { emoji = "🙊" }, { emoji = "💋" }, { emoji = "💘" },
		{ emoji = "💯" }, { emoji = "💩" }, { emoji = "💊" }, { emoji = "💅" },
		{ emoji = "👀" }, { emoji = "👌" }, { emoji = "👎" }, { emoji = "🖕" },
		{ emoji = "🏆" }, { emoji = "🎉" }, { emoji = "🎄" }, { emoji = "🎃" },
		{ emoji = "🎅" }, { emoji = "🆒" }, { emoji = "⚡" }, { emoji = "🐳" },
		{ emoji = "🦄" }, { emoji = "🌚" }, { emoji = "🍌" }, { emoji = "🍓" },
	}
	for _, item in ipairs(items) do
		local name = emojis.get_name(item.emoji)
		item.label = item.emoji
		if name then
			item.label = item.emoji .. "  " .. name
		end
		if target.reactions then
			local item_e = norm_e(item.emoji)
			for _, r in ipairs(target.reactions) do
				if r.is_chosen and norm_e(r.emoji) == item_e then
					item.label = item.label .. "  ✓"
					break
				end
			end
		end
	end
	vim.ui.select(items, {
		prompt = "React to message",
		format_item = function(item) return item.label end,
	}, function(choice)
		if choice then
			M.toggle_reaction_on(target_ref, choice.emoji)
		end
	end)
end

return M
