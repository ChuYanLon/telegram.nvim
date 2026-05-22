local server = require('telegram.server')

local M = {}

function M.auth_poll(on_done)
  local function poll()
    local health = server.server_health()
    if not health then
      vim.defer_fn(poll, 500)
      return
    end
    if health.ready == true then
      on_done(true)
      return
    end
    local a = health.auth
    if not a or a.state == 'initializing' then
      vim.defer_fn(poll, 500)
      return
    end
    if a.state == 'error' then
      vim.notify('[tg] Auth failed: ' .. (type(a.error) == 'string' and a.error or 'unknown'), vim.log.levels.ERROR)
      on_done(false)
      return
    end
    if (a.state == 'waitPhone' or a.state == 'waitCode' or a.state == 'waitPassword') and a.canInput then
      local prompt
      if a.state == 'waitPhone' then
        prompt = 'Phone number'
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      elseif a.state == 'waitCode' then
        prompt = 'Verification code'
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      else
        prompt = '2FA password'
        if type(a.hint) == 'string' then prompt = prompt .. ' (hint: ' .. a.hint .. ')' end
        if type(a.error) == 'string' then prompt = prompt .. ' (' .. a.error .. ')' end
      end
      vim.ui.input({ prompt = prompt .. ': ' }, function(val)
        if val and #val > 0 then
          server.post_auth_input(val)
        else
          vim.notify('[tg] Auth cancelled', vim.log.levels.INFO)
          on_done(false)
          return
        end
        vim.defer_fn(poll, 500)
      end)
      return
    end
    vim.defer_fn(poll, 500)
  end
  poll()
end

return M
