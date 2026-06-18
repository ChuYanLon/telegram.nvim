local state = require("telegram.state").state
local server = require("telegram.server")

local M = {}

function M.show_picker()
	if not state.chat_id then
		vim.notify("No chat open", vim.log.levels.WARN, { title = "tg" })
		return
	end

	vim.notify("Loading sticker packs...", vim.log.levels.INFO, { title = "tg" })
	server.get_installed_sticker_sets_async(function(data)
		if not data or not data.sets or #data.sets == 0 then
			vim.notify("No installed sticker packs found", vim.log.levels.WARN, { title = "tg" })
			return
		end

		local items = {}
		for _, set in ipairs(data.sets) do
			table.insert(items, { id = set.id, label = set.title or "Sticker pack #" .. set.id })
		end

		vim.ui.select(items, {
			prompt = "Select sticker pack (" .. #items .. " installed)",
			format_item = function(item) return item.label end,
	}, function(choice)
			if not choice then return end

			vim.notify("Loading stickers...", vim.log.levels.INFO, { title = "tg" })
			server.get_sticker_set_async(choice.id, function(set_data)
				if not set_data or not set_data.stickers or #set_data.stickers == 0 then
					vim.notify("No stickers in this pack", vim.log.levels.WARN, { title = "tg" })
					return
				end

				local stickers = set_data.stickers
				local s_items = {}
				for _, s in ipairs(stickers) do
					table.insert(s_items, { fileId = s.stickerFileId, emoji = s.emoji, label = (s.emoji or "") .. "  [" .. s.fileId .. "]" })
				end

				vim.ui.select(s_items, {
					prompt = "Pick a sticker (" .. #s_items .. " in " .. (set_data.title or "pack") .. ")",
					format_item = function(item) return item.label end,
				}, function(selected)
					if not selected then return end

				server.send_sticker_async(state.chat_id, selected.fileId, selected.emoji, function(msg)
					if msg then
						local id = tostring(msg.id)
						local dup = false
						for _, m in ipairs(state.messages) do
							if tostring(m.id) == id then dup = true; break end
						end
						if not dup then
							table.insert(state.messages, msg)
							if require("telegram.ui").render then
								require("telegram.ui").render()
							end
						end
					end
				end)
				end)
			end)
		end)
	end)
end

return M