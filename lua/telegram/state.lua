local M = {}

local state = {
	buf = nil,
	win = nil,
	chat_id = nil,
	chat_title = "",
	messages = {},
	loading = false,
	exhausted = false,
	unread = 0,
	last_chat = nil,
	last_msg = nil,
	online_count = nil,
	typing_users = {},

	mounted = false,
	groups = {},
	group_ids = {},

	input_mode = "send",
	reply_to = nil,
	edit_target = nil,
	delete_target = nil,
	forward_target = nil,
	esc_count = 0,
	sending = false,
	loading_newer = false,
	exhausted_forward = false,

	separator_line = "────────────────────",
	_input_start = 0,

	group_cursor = 1,
	permissions = {},
	my_user_id = nil,
	default_restricted = false,

	pinned_message = nil,
	pinned_message_id = nil,
	saved_chat_id = nil,

	title_buf = nil,
	title_win = nil,
	title_height = 0,
	_typing_timer = nil,

	msg_line_counts = {},
	_title_update_timer = nil,
	_scroll_timer = nil,
	title_dirty = false,
}

M.state = state

local MAX_WINDOW_MESSAGES = 200

function M.trim_oldest()
	if #state.messages <= MAX_WINDOW_MESSAGES then return end
	local remove = #state.messages - MAX_WINDOW_MESSAGES
	local new = {}
	for i = remove + 1, #state.messages do
		new[#new + 1] = state.messages[i]
	end
	state.messages = new
	state.exhausted = false
end

local function trim_newest()
	if #state.messages <= MAX_WINDOW_MESSAGES then return end
	local keep = MAX_WINDOW_MESSAGES
	local new = {}
	for i = 1, keep do
		new[i] = state.messages[i]
	end
	state.messages = new
	state.exhausted_forward = false
end

local hl_ns = vim.api.nvim_create_namespace("TgChat")
local target_ns = vim.api.nvim_create_namespace("TgTarget")

M.hl_ns = hl_ns
M.target_ns = target_ns
M.trim_newest = trim_newest
M.MAX_WINDOW_MESSAGES = MAX_WINDOW_MESSAGES

vim.api.nvim_create_autocmd("BufUnload", {
	pattern = "/tmp/tg-*",
	callback = function()
		if state.chat_id then
			state.last_group = { id = state.chat_id, title = state.chat_title }
		end
	end,
})

return M
