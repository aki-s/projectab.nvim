--- Persistence module for projectab.nvim
--- Handles JSON file I/O and path encoding for project state storage.
---
--- Storage layout (under stdpath("data") .. "/projectab/"):
---   dashboard.json               — MRU history of project roots
---   %Users%user1%app.json        — per-project state (buffers, active_buffer)
---
--- Path encoding: "/" → "%" so that project roots become flat filenames.
--- @class ProjectabPersistenceModule
local M = {}

--- @class ProjectabDashboard
--- @field history string[] List of project roots in MRU order
--- @field version number Schema version

--- @class ProjectabProjectState
--- @field active_buffer string|nil Absolute path to the last active buffer
--- @field buffers string[] List of absolute buffer paths

--- @class ProjectabProjectData
--- @field last_saved integer Timestamp of last save (UNIX time)
--- @field root string Absolute path to project root
--- @field state ProjectabProjectState Per-project buffer state
--- @field version number Schema version

local log = require("projectab.log")
local config = require("projectab.config")

--- Encode a project root path into a flat filename.
--- "/" is replaced with "%" so the path can be used as a filename.
--- @param root string Absolute path, e.g. "/Users/user1/projects/appA"
--- @return string encoded e.g. "%Users%user1%projects%appA"
function M.encode_path(root)
  return (root:gsub("/", "%%"))
end

--- Decode a flat filename back into a project root path.  (for testing/debugging).
--- "%" is replaced with "/".
--- @param encoded string e.g. "%Users%user1%projects%appA"
--- @return string root  e.g. "/Users/user1/projects/appA"
function M._decode_path(encoded)
  return (encoded:gsub("%%", "/"))
end

--- Return the persistence data directory, creating it if necessary.
--- @return string dir Absolute path to the data directory
function M.get_data_dir()
  local dir = config.values.project.persistence.dir
  if not dir then
    dir = vim.fn.stdpath("data") .. "/projectab"
  end
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Return the path to dashboard.json.
--- @return string
function M.get_dashboard_path()
  return M.get_data_dir() .. "/dashboard.json"
end

--- Return the path to a per-project JSON file.
--- @param root string Project root (absolute path)
--- @return string
function M.get_project_path(root)
  return M.get_data_dir() .. "/" .. M.encode_path(root) .. ".json"
end

--- Read and decode a JSON file.
--- Returns nil if the file does not exist or is malformed.
--- @param path string File path
--- @return table|nil data Decoded JSON, or nil on error
function M.read_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  if not content or content == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    log.debug_ctx("persistence: failed to decode JSON from " .. path .. ": " .. tostring(data))
    return nil
  end
  return data
end

--- Encode and write a Lua table as JSON to a file.
--- Creates parent directories if needed.
--- @param path string File path
--- @param data table Data to encode
--- @return boolean success
function M.write_json(path, data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    log.debug_ctx("persistence: failed to encode JSON: " .. tostring(encoded))
    return false
  end
  local file = io.open(path, "w")
  if not file then
    log.debug_ctx("persistence: failed to open file for writing: " .. path)
    return false
  end
  file:write(encoded)
  file:close()
  return true
end

--- Load dashboard.json.
--- Returns a default structure if the file does not exist.
--- @return ProjectabDashboard dashboard
function M.load_dashboard()
  --- @type ProjectabDashboard|nil
  local data = M.read_json(M.get_dashboard_path())
  if data and data.version then
    return data
  end
  return { version = 1, history = {} }
end

--- Save dashboard.json.
--- @param dashboard ProjectabDashboard
--- @return boolean success
function M.save_dashboard(dashboard)
  return M.write_json(M.get_dashboard_path(), dashboard)
end

--- Load per-project state from its JSON file.
--- Returns nil if the file does not exist.
--- @param root string Project root (absolute path)
--- @return ProjectabProjectData|nil project_data
function M.load_project(root)
  return M.read_json(M.get_project_path(root))
end

--- Save per-project state to its JSON file.
--- @param root string Project root (absolute path)
--- @param data ProjectabProjectData Project state data
--- @return boolean success
function M.save_project(root, data)
  return M.write_json(M.get_project_path(root), data)
end

--- Delete per-project JSON file.
--- @param root string Project root (absolute path)
function M.delete_project(root)
  local path = M.get_project_path(root)
  os.remove(path)
  log.debug_ctx("persistence: deleted project file: " .. path)
end

--- Update dashboard history with a project root (MRU order).
--- Moves/adds the root to the front of the history list.
--- @param dashboard ProjectabDashboard Dashboard data
--- @param root string Project root
--- @return ProjectabDashboard dashboard Updated dashboard
function M.touch_history(dashboard, root)
  -- Remove existing entry if present
  local new_history = {}
  for _, entry in ipairs(dashboard.history) do
    if entry ~= root then
      table.insert(new_history, entry)
    end
  end
  -- Insert at front (most recent)
  table.insert(new_history, 1, root)
  dashboard.history = new_history
  return dashboard
end

--- Remove a root from dashboard history.
--- @param dashboard ProjectabDashboard Dashboard data
--- @param root string Project root to remove
--- @return ProjectabDashboard dashboard Updated dashboard
function M.remove_from_history(dashboard, root)
  local new_history = {}
  for _, entry in ipairs(dashboard.history) do
    if entry ~= root then
      table.insert(new_history, entry)
    end
  end
  dashboard.history = new_history
  return dashboard
end

return M
