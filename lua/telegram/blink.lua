--- blink.cmp source for telegram.nvim
--- Provides completions in the input editor:
---   :name  → emoji
---   @name  → chat member mention
---   #chat  → chat/channel reference
---   /cmd   → bot commands (from group info)
---   !cmd   → quick phrase templates
---   ```    → code block language
---
--- Register in blink.cmp setup:
---   sources = {
---     { name = 'telegram', module = 'telegram.blink' },
---   }

local state = require("telegram.state").state

-- ── Emoji name → character ─────────────────────────────────────────────

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



-- ── Code languages ─────────────────────────────────────────────────────

local code_languages = {
	"bash", "c", "cpp", "csharp", "css", "diff", "elixir", "erlang",
	"go", "graphql", "haskell", "html", "java", "javascript", "json",
	"jsx", "kotlin", "lua", "makefile", "markdown", "nim", "ocaml",
	"perl", "php", "powershell", "python", "r", "ruby", "rust",
	"scala", "scheme", "shell", "solidity", "sql", "swift", "toml",
	"typescript", "tsx", "vim", "yaml", "zig",
}

-- ── Kind constants ─────────────────────────────────────────────────────

local ItemKind = { Text = 1, User = 2, Snippet = 15, Keyword = 14 }
pcall(function()
	ItemKind = require("blink.cmp.types").CompletionItemKind
end)

-- ── Source ─────────────────────────────────────────────────────────────

local source = {}

function source.new(_opts, _config)
	return setmetatable({}, { __index = source })
end

function source:enabled()
	return vim.bo.filetype == "telegram"
end

function source:get_trigger_characters()
	return { ":", "@", "#", "!", "`" }
end

function source:get_completions(ctx, callback)
	local line = ctx.line
	local cursor = ctx.cursor[2]
	local line_idx = ctx.cursor[1]

	-- Triple backtick
	if cursor >= 3 then
		local before = line:sub(cursor - 2, cursor)
		if before == "```" then
			callback({ items = self:get_language_items({
				start = { line = line_idx, character = cursor - 2 },
				["end"] = { line = line_idx, character = cursor },
			}) })
			return
		end
	end

	-- Find trigger at word boundary
	local trigger_pos
	for i = cursor, 1, -1 do
		local char = line:sub(i, i)
		if char == ":" or char == "@" or char == "#" or char == "!" then
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
	local keyword = line:sub(trigger_pos + 1, cursor)
	local range = {
		start = { line = line_idx, character = trigger_pos - 1 },
		["end"] = { line = line_idx, character = cursor },
	}

	local items = {}
	if trigger == ":" then
		items = self:get_emoji_items(keyword, range)
	elseif trigger == "@" then
		items = self:get_member_items(keyword, range)
	elseif trigger == "#" then
		items = self:get_chat_items(keyword, range)
	elseif trigger == "!" then
		items = self:get_command_items(keyword, range)

	end
	callback({ items = items })
end

-- ── Emoji items ────────────────────────────────────────────────────────

function source:get_emoji_items(keyword, range)
	local kw = keyword:lower()
	local items = {}
	for name, char in pairs(emoji_names) do
		if #kw == 0 or name:find(kw, 1, true) then
			table.insert(items, {
				label = char .. "  " .. name,
				filterText = name,
				textEdit = { newText = char, range = range },
				kind = ItemKind.Text,
				score_offset = 10000,
			})
		end
	end
	table.sort(items, function(a, b)
		local an, bn = a.filterText, b.filterText
		if #kw > 0 then
			local a_exact, b_exact = an == kw, bn == kw
			if a_exact ~= b_exact then return a_exact end
		end
		return an < bn
	end)
	return items
end

-- ── Member items (@name) ─────────────────────────────────────────────

function source:get_member_items(keyword, range)
	local kw = keyword:lower()
	local items = {}
	local seen = {}

	for _, msg in ipairs(state.messages or {}) do
		if msg.sender and msg.sender.name and #msg.sender.name > 0 then
			local name = msg.sender.name
			if not seen[name] then
				seen[name] = true
				if #kw == 0 or name:lower():find(kw, 1, true) then
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

	local chat_id = state.chat_id
	if chat_id then
		local g = state.groups[chat_id]
		if g and g.title and #g.title > 0 and not seen[g.title] then
			if #kw == 0 or g.title:lower():find(kw, 1, true) then
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
		if #kw > 0 then
			local a_exact = a.filterText:lower() == kw
			local b_exact = b.filterText:lower() == kw
			if a_exact ~= b_exact then return a_exact end
		end
		return a.filterText < b.filterText
	end)
	return items
end

-- ── Chat items (#name) ───────────────────────────────────────────────

function source:get_chat_items(keyword, range)
	local kw = keyword:lower()
	local items = {}

	for _, id in ipairs(state.group_ids or {}) do
		local g = state.groups[id]
		if g and g.title and #g.title > 0 then
			local icon = g.type == "private" and "👤 " or g.type == "channel" and "📢 " or "👥 "
			local label = icon .. "#" .. g.title
			if #kw == 0 or g.title:lower():find(kw, 1, true) then
				table.insert(items, {
					label = label,
					filterText = g.title:lower(),
					textEdit = { newText = "#" .. g.title .. " ", range = range },
					kind = ItemKind.Text,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		if #kw > 0 then
			local a_exact = a.filterText == kw
			local b_exact = b.filterText == kw
			if a_exact ~= b_exact then return a_exact end
		end
		return a.filterText < b.filterText
	end)
	return items
end

-- ── Bot command items (/cmd) ─────────────────────────────────────────

function source:get_command_items(keyword, range)
	local kw = keyword:lower()
	local items = {}
	local chat_id = state.chat_id
	if not chat_id then return items end

	local g = state.groups[chat_id]
	if not g or not g.bot_commands then return items end

	for _, bc in ipairs(g.bot_commands) do
		for _, cmd in ipairs(bc.commands or {}) do
			local name = cmd.command or ""
			if #kw == 0 or name:find(kw, 1, true) then
				table.insert(items, {
					label = "/" .. name .. "  " .. (cmd.description or ""),
					filterText = name,
					textEdit = { newText = "/" .. name .. " ", range = range },
					kind = ItemKind.Keyword,
					score_offset = 10000,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		if #kw > 0 then
			local a_exact = a.filterText == kw
			local b_exact = b.filterText == kw
			if a_exact ~= b_exact then return a_exact end
		end
		return a.filterText < b.filterText
	end)
	return items
end



-- ── Language items (```) ─────────────────────────────────────────────

function source:get_language_items(range)
	local items = {}
	for _, lang in ipairs(code_languages) do
		local icon = ""
		if lang == "lua" then icon = "🌙 "
		elseif lang == "python" then icon = "🐍 "
		elseif lang == "javascript" or lang == "jsx" then icon = "🟨 "
		elseif lang == "typescript" or lang == "tsx" then icon = "🔵 "
		elseif lang == "go" then icon = "🔷 "
		elseif lang == "rust" then icon = "🦀 "
		elseif lang == "html" then icon = "🌐 "
		elseif lang == "css" then icon = "🎨 "
		elseif lang == "bash" or lang == "shell" or lang == "powershell" then icon = "🖥️ "
		elseif lang == "sql" then icon = "🗃️ "
		elseif lang == "json" or lang == "toml" or lang == "yaml" then icon = "📋 "
		end
		table.insert(items, {
			label = icon .. lang,
			filterText = lang,
			textEdit = { newText = lang .. "\n", range = range },
			kind = ItemKind.Text,
		})
	end
	return items
end

return source
