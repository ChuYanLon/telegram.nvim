local text = require('telegram.render.text')
local code = require('telegram.render.code')
local link = require('telegram.render.link')
local media = require('telegram.render.media')
local other = require('telegram.render.other')

local M = {}

local function get_renderer(msg)
  local t = msg.type or 'messageText'
  if t == 'messageText' then
    local txt = msg.text or ''
    if txt:find('`[^`]+`') or txt:find('%$%{') then
      return code
    end
    if txt:find('https?://') or txt:find('www%.[%w_-]+%.') then
      return link
    end
    return text
  end
  if t == 'messagePhoto' or t == 'messageVideo' or t == 'messageAnimation' or t == 'messageDocument' or t == 'messageVoiceNote' or t == 'messageVideoNote' or t == 'messageAudio' then
    return media
  end
  return other
end

function M.render(msg)
  local date_str = os.date('%m-%d %H:%M', msg.date)
  local sender = msg.own and 'You' or (msg.sender and msg.sender.name or 'unknown')
  local content = get_renderer(msg).render(msg)
  local out = {}
  if msg.replyTo then
    local r_sender = msg.replyTo.sender and msg.replyTo.sender.name or '?'
    local r_text = msg.replyTo.text and msg.replyTo.text:gsub('\n', ' ') or ''
    if #r_text > 50 then r_text = r_text:sub(1, 50) .. '...' end
    table.insert(out, string.format('[%s] %s:', date_str, sender))
    table.insert(out, string.format('  \xE2\x94\x83 %s: %s', r_sender, r_text))
    for _, l in ipairs(content) do
      table.insert(out, '  ' .. l)
    end
  else
    local first = content[1] or ''
    if first:match('^```') or #content > 1 or vim.fn.strwidth(first) > 50 then
      table.insert(out, string.format('[%s] %s:', date_str, sender))
      table.insert(out, '  ' .. first)
    else
      table.insert(out, string.format('[%s] %s: %s', date_str, sender, first))
    end
    for i = 2, #content do
      table.insert(out, '  ' .. content[i])
    end
  end
  return out
end

return M
