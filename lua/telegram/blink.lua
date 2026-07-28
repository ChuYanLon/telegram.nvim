--- blink.cmp source for telegram.nvim
--- Provides emoji (`:name`) and @user completions in the input editor.
---
--- Register in blink.cmp setup:
---   sources = {
---     { name = 'telegram', module = 'telegram.blink' },
---   }

local state = require("telegram.state").state

-- ── Emoji name → character mapping ────────────────────────────────────

local emoji_names = {
	smile = "😊", grin = "😁", joy = "😂", sweat_smile = "😅",
	laugh = "🤣", wink = "😉", heart_eyes = "😍",
	kissing_heart = "😘", sleepy = "😴", sob = "😭", cry = "😢",
	angry = "😡", skull = "💀", ghost = "👻",
	wave = "👋", clap = "👏", thumbsup = "👍", thumbsdown = "👎",
	ok_hand = "👌", pray = "🙏", muscle = "💪", middle_finger = "🖕",
	thinking = "🤔", hug = "🤗", rolling_eyes = "🙄",
	heart = "❤️", broken_heart = "💔", sparkles = "✨",
	fire = "🔥", zap = "⚡", boom = "💥", poop = "💩",
	star = "⭐", crown = "👑", gem = "💎", trophy = "🏆",
	rocket = "🚀", gift = "🎁", tada = "🎉",
	dog = "🐶", cat = "🐱", unicorn = "🦄",
	apple = "🍎", banana = "🍌", pizza = "🍕", burger = "🍔",
	see_no_evil = "🙈", hear_no_evil = "🙉", speak_no_evil = "🙊",
	_100 = "💯", nerd = "🤓", sunglasses = "😎", devil = "😈",
	angel = "😇", neutral = "😐", money = "💰",
	moon = "🌚", whale = "🐳", octopus = "🐙",
	cool = "🆒", lightning = "⚡", pills = "💊", nails = "💅",
	santa = "🎅", christmas = "🎄", halloween = "🎃",
}

-- ── Kind constants (safe fallback if blink.cmp not loaded) ────────────

local ItemKind = { Text = 1, User = 2 }
pcall(function()
	ItemKind = require("blink.cmp.types").CompletionItemKind
end)

-- ── Source ────────────────────────────────────────────────────────────

local source = {}

function source.new(_opts, _config)
	return setmetatable({}, { __index = source })
end

function source:enabled()
	return vim.bo.filetype == "telegram"
end

function source:get_trigger_characters()
	return { ":", "@" }
end

function source:get_completions(ctx, callback)
	local line = ctx.line
	local cursor = ctx.cursor[2] -- 0-indexed column
	local line_idx = ctx.cursor[1]

	-- Find trigger character before cursor, at word boundary
	local trigger_pos
	for i = cursor, 1, -1 do
		local char = line:sub(i, i)
		if char == ":" or char == "@" then
			if i == 1 or line:sub(i - 1, i - 1):match("%s") then
				trigger_pos = i
				break
			end
		end
	end

	if not trigger_pos then
		callback({ items = {} })
		return
	end

	local trigger = line:sub(trigger_pos, trigger_pos)
	local keyword = line:sub(trigger_pos + 1, cursor):lower()

	-- Range to replace: from trigger char to cursor
	local range = {
		start = { line = line_idx, character = trigger_pos - 1 },
		["end"] = { line = line_idx, character = cursor },
	}

	local items = {}
	if trigger == ":" then
		items = self:get_emoji_items(keyword, range)
	else
		items = self:get_member_items(keyword, range)
	end

	callback({ items = items })
end

-- ── Emoji items ───────────────────────────────────────────────────────

function source:get_emoji_items(keyword, range)
	local items = {}
	for name, char in pairs(emoji_names) do
		if #keyword == 0 or name:find(keyword, 1, true) then
			table.insert(items, {
				label = char .. "  " .. name,
				filterText = name,
				textEdit = { newText = char, range = range },
				kind = ItemKind.Text,
			})
		end
	end
	table.sort(items, function(a, b)
		local an, bn = a.filterText, b.filterText
		if #keyword > 0 then
			local a_exact, b_exact = an == keyword, bn == keyword
			if a_exact ~= b_exact then return a_exact end
			local a_pref, b_pref = an:find("^" .. keyword, 1, true) == 1, bn:find("^" .. keyword, 1, true) == 1
			if a_pref ~= b_pref then return a_pref end
		end
		return an < bn
	end)
	return items
end

-- ── Member items ──────────────────────────────────────────────────────

function source:get_member_items(keyword, range)
	local items = {}
	local seen = {}

	-- Collect unique names from currently loaded messages
	for _, msg in ipairs(state.messages or {}) do
		if msg.sender and msg.sender.name and #msg.sender.name > 0 then
			local name = msg.sender.name
			if not seen[name] then
				seen[name] = true
				if #keyword == 0 or name:lower():find(keyword, 1, true) then
					table.insert(items, {
						label = "@" .. name,
						filterText = name,
						textEdit = { newText = "@" .. name .. " ", range = range },
						kind = ItemKind.User,
					})
				end
			end
		end
	end

	-- Add chat title as mention target
	local chat_id = state.chat_id
	if chat_id then
		local g = state.groups[chat_id]
		if g and g.title and #g.title > 0 and not seen[g.title] then
			if #keyword == 0 or g.title:lower():find(keyword, 1, true) then
				table.insert(items, {
					label = "@" .. g.title,
					filterText = g.title,
					textEdit = { newText = "@" .. g.title .. " ", range = range },
					kind = ItemKind.User,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		if #keyword > 0 then
			local a_exact = a.filterText:lower() == keyword
			local b_exact = b.filterText:lower() == keyword
			if a_exact ~= b_exact then return a_exact end
		end
		return a.filterText < b.filterText
	end)

	return items
end

return source
