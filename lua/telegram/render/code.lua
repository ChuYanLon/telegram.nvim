local M = {}

function M.render(msg)
  local text = msg.text or ''
  local lines = vim.split(text, '\n')
  if text:find('```') or #lines <= 1 then
    return lines
  end
  local out = { '```' }
  for _, l in ipairs(lines) do
    table.insert(out, l)
  end
  table.insert(out, '```')
  return out
end

return M
