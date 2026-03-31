--- project.nvim integration for projectab.nvim
--- Wraps project.nvim's root detection API as an optional fallback.
--- @class ProjectabProjectNvimIntegration
local M = {}

local log = require("projectab.log")

--- Get project root using project.nvim.
--- @param filepath string Absolute path to the file
--- @return string|nil
function M.get_root(filepath)
  local ok, project = pcall(require, "project_nvim.project")
  if not ok then
    log.debug_ctx("project_nvim integration: project.nvim not available")
    return nil
  end

  local root = project.get_project_root(filepath)
  if root == "" or root == nil then
    return nil
  end

  log.debug_ctx(string.format("project_nvim: root=%s for path=%s", root, filepath))
  return root
end

return M
