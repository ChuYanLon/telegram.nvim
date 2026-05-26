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

local service_styles = {
  messageBasicGroupChatCreate = { prefix = '>', text = 'created this group' },
  messageChatJoinByLink = { prefix = '+', text = 'joined this group via invite link' },
  messageChatJoinByRequest = { prefix = '+', text = 'joined this group' },
  messageChatDeleteMember = { prefix = '-', text = 'left the group' },
  messageChatChangeTitle = { prefix = '~', text = 'changed the group name' },
  messageChatChangePhoto = { prefix = '~', text = 'changed the group photo' },
  messageChatDeletePhoto = { prefix = '~', text = 'removed the group photo' },
  messagePinMessage = { prefix = '*', text = 'pinned a message' },
  messageMessagePinned = { prefix = '*', text = 'pinned a message' },
  messageForumTopicCreated = { prefix = '>', text = 'created a topic' },
  messageChatSetMessageAutoDeleteTime = { prefix = '!', text = 'set auto-delete timer' },
}

function M.render(msg)
  if msg.type == 'messageChatAddMembers' then
    local time_str = os.date('%H:%M:%S on %B %d, %Y', msg.date)
    local sender = msg.sender and msg.sender.name or (msg.own and 'You' or 'Someone')
    local is_self_join = false
    if msg.memberUserIds and msg.sender and msg.sender.id then
      for _, uid in ipairs(msg.memberUserIds) do
        if uid == msg.sender.id then
          is_self_join = true
          break
        end
      end
    end
    if is_self_join then
      return { '+ ' .. sender .. ' joined this group at ' .. time_str }
    else
      local names = msg.addedMemberNames and table.concat(msg.addedMemberNames, ', ') or 'someone'
      return { '+ ' .. sender .. ' added ' .. names .. ' at ' .. time_str }
    end
  end
  local style = msg.type and service_styles[msg.type]
  if style then
    local sender = msg.sender and msg.sender.name or (msg.own and 'You' or 'Someone')
    local time_str = os.date('%H:%M:%S on %B %d, %Y', msg.date)
    local text = style.prefix .. ' ' .. sender .. ' ' .. style.text .. ' at ' .. time_str
    return { text }
  end
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
