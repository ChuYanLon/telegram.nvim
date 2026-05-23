local M = {}

function M.render(msg, lines)
  local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or '?'
  local r_text = msg.replyTo.text and msg.replyTo.text:gsub('\n', ' ') or ''
  if #r_text > 50 then r_text = r_text:sub(1, 50) .. '...' end
  table.insert(lines, string.format('[reply] %s: %s', r_sender, r_text))
end

return M
