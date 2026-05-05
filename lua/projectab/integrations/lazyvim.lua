--- @class ProjectabLazyVimIntegration
local M = {}

local cfg = require("projectab.init.keymap")

--- If you use Lazyvim, you can set the return value at 'keys' property.
---
--- @return table 'keys' in LazyVim format
function M.keys()
  local keys = {}
  local defs = cfg.presetKeyDefs()

  for _, kpco in pairs(defs) do
    table.insert(keys, { kpco.key, kpco.plug, desc = kpco.opts.desc })
  end
  return keys
end

--- If you use Lazyvim with `Projectab.nvim`, then write the following in keymap.lua
---
--- `require("projectab.init.keymap").setDefaultKeymaps()`
function M.setDefaultKeymaps()
  local defs = cfg.presetKeyDefs()
  for _, kpco in pairs(defs) do
    if vim.fn.hasmapto(kpco.plug) then
      vim.notify(string.format("%s already used", kpco.plug), vim.log.levels.WARN)
    end
    vim.keymap.set("n", kpco.key, kpco.plug, kpco.opts)
  end
end

return M
