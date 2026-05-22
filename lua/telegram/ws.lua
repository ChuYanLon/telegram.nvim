local server = require('telegram.server')

local M = {}

local ws_job_id = nil

---@param on_msg fun(msg: table)
function M.ws_start(on_msg)
  if ws_job_id then
    vim.fn.jobstop(ws_job_id)
    ws_job_id = nil
  end
  local config = require('telegram.config')
  local helper = config.plugin_root .. '/bin/tg-ws-helper.js'
  ws_job_id = vim.fn.jobstart({ 'node', helper, server.ws_url() }, {
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        if line and #line > 0 then
          local ok, msg = pcall(vim.json.decode, line)
          if ok and on_msg then
            on_msg(msg)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            vim.notify('[tg-ws] ' .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function() ws_job_id = nil end,
  })
end

function M.ws_stop()
  if ws_job_id then
    vim.fn.jobstop(ws_job_id)
    ws_job_id = nil
  end
end

return M
