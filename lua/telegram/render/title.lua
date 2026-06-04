local state = require("telegram.state").state
local st = require("telegram.state")

local M = {}

local render_cb = nil

function M.set_render_fn(fn)
	render_cb = fn
end

local function truncate_text(text, max_width)
	if not text or #text == 0 then
		return text
	end
	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	local result = ""
	local w = 0
	for char in text:gmatch(".[\128-\191]*") do
		local cw = vim.fn.strdisplaywidth(char)
		if w + cw > max_width - 1 then
			return result .. "…"
		end
		result = result .. char
		w = w + cw
	end
	return result
end

local function hide_title_float()
	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_close, state.title_win, true)
	end
	state.title_win = nil
end

local function destroy_title_float()
	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_close, state.title_win, true)
	end
	state.title_win = nil
	if state.title_buf and vim.api.nvim_buf_is_valid(state.title_buf) then
		pcall(vim.api.nvim_buf_delete, state.title_buf, { force = true })
	end
	state.title_buf = nil
end

local action_descriptions = {
	chatActionTyping = "typing...",
	chatActionRecordingVideo = "recording video...",
	chatActionRecordingVoiceNote = "recording voice...",
	chatActionUploadingVideo = "uploading video...",
	chatActionUploadingVoiceNote = "uploading voice...",
	chatActionUploadingPhoto = "uploading photo...",
	chatActionUploadingDocument = "uploading document...",
	chatActionChoosingSticker = "choosing sticker...",
	chatActionChoosingLocation = "choosing location...",
	chatActionChoosingContact = "choosing contact...",
	chatActionStartPlayingGame = "playing game...",
	chatActionRecordingVideoNote = "recording video note...",
	chatActionUploadingVideoNote = "uploading video note...",
	chatActionWatchingAnimations = "watching animations...",
}

function M.update_title()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_set_name, state.buf, "tg")
	end
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		hide_title_float()
		return
	end
	local title = state.chat_title or ""

	local typing_items = {}
	if state.chat_id and state.typing_users[state.chat_id] then
		for _, info in pairs(state.typing_users[state.chat_id]) do
			table.insert(typing_items, info)
		end
	end
	local is_private = state.chat_id and state.groups[state.chat_id] and state.groups[state.chat_id].type == "private"
	local typing = ""
	if #typing_items > 0 then
		if #typing_items == 1 and not is_private then
			typing = typing_items[1].name .. " " .. typing_items[1].action_desc
		elseif #typing_items == 1 then
			typing = typing_items[1].action_desc
		else
			typing = typing_items[1].name .. " +" .. (#typing_items - 1) .. " " .. typing_items[1].action_desc
		end
	end

	local win_pos = vim.api.nvim_win_get_position(state.win)
	local win_width = vim.api.nvim_win_get_width(state.win)
	local text_width = win_width - 2

	local has_pinned = state.pinned_message and #state.pinned_message > 0
	local has_desc = state.description and #state.description > 0
	local has_typing = typing ~= ""

	local lines = {}

	lines[#lines + 1] = title

	local online = state.online_count or 0
	if has_typing then
		lines[#lines + 1] = "status: " .. typing
	elseif is_private then
		lines[#lines + 1] = "status: " .. (online > 0 and "online" or "offline")
	else
		local count = tostring(online)
		local total = state.chat_id and state.groups[state.chat_id] and state.groups[state.chat_id].member_count
		if total and total > 0 then
			count = online .. "/" .. total
		end
		if state.unread > 0 then
			count = count .. "  \xE2\x97\x8F+" .. state.unread
		end
		lines[#lines + 1] = "status: " .. count
	end

	if has_pinned then
		local w = math.max(text_width - 8, 1)
		lines[#lines + 1] = "pinned: " .. truncate_text(state.pinned_message:gsub("\n", " "), w)
	end

	if has_desc then
		local w = math.max(text_width - 6, 1)
		lines[#lines + 1] = "desc: " .. truncate_text(state.description:gsub("\n", " "), w)
	end

	local label = " messages "
	local side = string.rep("=", math.floor((text_width - #label) / 2))
	lines[#lines + 1] = side .. label .. side

	local old_h = state.title_win and vim.api.nvim_win_is_valid(state.title_win)
		and vim.api.nvim_win_get_height(state.title_win) or 0
	local new_h = #lines

	if not state.title_buf or not vim.api.nvim_buf_is_valid(state.title_buf) then
		state.title_buf = vim.api.nvim_create_buf(false, true)
	end

	state.title_height = new_h

	vim.bo[state.title_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.title_buf, 0, -1, false, lines)
	vim.bo[state.title_buf].modifiable = false
	vim.bo[state.title_buf].modified = false

	local float_opts = {
		relative = "editor",
		width = win_width,
		height = new_h,
		row = win_pos[1],
		col = win_pos[2],
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 50,
	}

	if state.title_win and vim.api.nvim_win_is_valid(state.title_win) then
		pcall(vim.api.nvim_win_set_config, state.title_win, float_opts)
		pcall(vim.api.nvim_win_set_buf, state.title_win, state.title_buf)
		vim.wo[state.title_win].winhighlight = "Normal:TgNoBg"
	else
		state.title_win = vim.api.nvim_open_win(state.title_buf, false, float_opts)
		vim.wo[state.title_win].winhighlight = "Normal:TgNoBg"
		state._title_winenter = vim.api.nvim_create_autocmd("WinEnter", {
			group = vim.api.nvim_create_augroup("TgTitleWinEnter", { clear = true }),
			buffer = state.title_buf,
			callback = function()
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					vim.api.nvim_set_current_win(state.win)
				end
			end,
		})
	end

	vim.api.nvim_buf_clear_namespace(state.title_buf, st.hl_ns, 0, -1)
	for li, line in ipairs(lines) do
		if line:match("^=") then
			vim.api.nvim_buf_add_highlight(state.title_buf, st.hl_ns, "TgBorder", li - 1, 0, -1)
		elseif li == 1 then
			vim.api.nvim_buf_add_highlight(state.title_buf, st.hl_ns, "TgWinbarTitle", li - 1, 0, #title)
			vim.api.nvim_buf_add_highlight(state.title_buf, st.hl_ns, "TgTimestamp", li - 1, #title, -1)
		else
			local colon = line:find(":")
			if colon then
				vim.api.nvim_buf_add_highlight(state.title_buf, st.hl_ns, "TgTitleKey", li - 1, 0, colon + 1)
			end
		end
	end

	if new_h ~= old_h and render_cb then
		render_cb()
	end
end

M.destroy_title_float = destroy_title_float
M.hide_title_float = hide_title_float
M.truncate_text = truncate_text
M.action_descriptions = action_descriptions

return M
