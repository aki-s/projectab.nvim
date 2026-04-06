--- Entry point for projectab.nvim
--- Sets up autocmds, user commands, and keymaps.
---
--- @class ProjectabModule
local M = {}

--- Suspend buffer routing globally.
--- Useful when triggering 3rd party session managers that do not set `vim.g.SessionLoad`.
function M.suspend()
  require("projectab.buffer").suspend()
end

--- Resume buffer routing globally.
function M.resume()
  require("projectab.buffer").resume()
end

--- Setup the plugin with user options.
--- @param opts table|nil User configuration (see config.lua for schema)
function M.setup(opts)
  local config = require("projectab.config")
  local log = require("projectab.log")

  config.setup(opts)

  if not config.values.integrations.bufferline.enabled then
    vim.opt.tabline = "%!v:lua.require('projectab.ui.tabline').render()"
    log.debug_ctx("enabled built-in tabline")
  end

  require("projectab.init.autocmd").setup()
  require("projectab.init.command").setup()
  require("projectab.init.keymap").setup()

  log.debug_ctx("setup complete")
end

--- Return internal state for debugging.
--- @return ProjectabState
function M._get_state()
  return require("projectab.state")._get_state()
end

return M
