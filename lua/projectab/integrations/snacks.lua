--- snacks.nvim integration for projectab.nvim
--- Wraps snacks.picker.projects as an optional "new project" picker.
--- @class ProjectabSnacksIntegration
local M = {}

local log = require("projectab.log")

--- Pick a new project using snacks.picker.projects.
--- If snacks.nvim (or its picker feature) is not available, returns false
--- so the caller can fall back to a generic prompt.
---
--- @param open_project_fn fun(root: string, opts?: table) Callback to open the selected project
--- @param picker_opts table|nil Extra options forwarded to snacks.picker.projects() (e.g. recent, max_depth, dev)
--- @return boolean handled true if snacks handled the interaction
function M.pick_new_project(open_project_fn, picker_opts)
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or not snacks.picker.projects then
    log.debug_ctx("snacks integration: snacks.picker.projects not available")
    return false
  end

  local opts = vim.tbl_deep_extend("force", picker_opts or {}, {
    confirm = function(picker, item)
      if not item then
        picker:close()
        return
      end
      picker:close()
      open_project_fn(item.file, {
        callback = function(_)
          -- Optionally open file picker in the new project
          if snacks.picker and snacks.picker.files then
            snacks.picker.files({ cwd = item.file })
          end
        end,
      })
    end,
  })

  snacks.picker.projects(opts)

  return true
end

--- Return a snacks.dashboard section for Projectab's managed projects.
--- @param opts? {limit?:number, action?:fun(dir:string)}
--- @return fun():table[] # A generator function that returns snacks.dashboard items
function M.dashboard_section(opts)
  return function()
    opts = opts or {}
    local session = require("projectab.session")
    local limit = opts.limit or 5
    local sessions = session.list({ limit = limit })

    local dirs = {}
    for _, root in ipairs(sessions) do
      table.insert(dirs, root)
    end

    local ret = {}
    for _, dir in ipairs(dirs) do
      ret[#ret + 1] = {
        file = dir,
        icon = "directory",
        action = function()
          if opts.action then
            return opts.action(dir)
          end
          session.project_restore(dir)
        end,
        autokey = true,
      }
    end

    return ret
  end
end

return M
