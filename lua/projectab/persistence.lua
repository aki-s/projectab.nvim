--- Persistence module for projectab.nvim
--- Handles JSON file I/O and path encoding for project state storage.
---
--- Storage layout (under stdpath("data") .. "/projectab/"):
---   persistence.json             — list of project roots
---   %Users%user1%app.json        — per-project state (buffers, active_buffer)
---
--- Path encoding: "/" → "%" so that project roots become flat filenames.
--- @class ProjectabPersistenceModule
local M = {}

--- @class ProjectabPersistenceProjects
--- @field projects string[] List of project root directories
--- @field version number Schema version

--- @class ProjectabProjectState
--- @field active_buffer string|nil Absolute path to the last active buffer
--- @field buffers string[] List of absolute buffer paths

--- @class ProjectabPersistenceProjectData
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
function M.get_data_root_dir()
  local dir = config.values.project.persistence.dir
  if not dir then
    dir = vim.fn.stdpath("data") .. "/projectab"
  end
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Return the path to persistence.json.
--- @return string
function M.get_persistence_path()
  return M.get_data_root_dir() .. "/persistence.json"
end

--- Return the root path containing each project data.
--- @return string
function M.get_project_data_root_dir()
  return M.get_data_root_dir() .. "/projects"
end

--- Return the path to a per-project JSON file.
--- @param root string Project root (absolute path)
--- @return string
function M.get_project_path(root)
  return M.get_project_data_root_dir() .. "/" .. M.encode_path(root) .. ".json"
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
  local parent = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(parent, "p")
  local file = io.open(path, "w")
  if not file then
    log.debug_ctx("persistence: failed to open file for writing: " .. path)
    return false
  end
  file:write(encoded)
  file:close()
  return true
end

--- @return ProjectabPersistenceProjects data
local function emptyProjectabData()
  --- @type ProjectabPersistenceProjects
  local data = { version = 1, projects = {} }
  return data
end

--- Load persistence.json.
--- Returns a default structure if the file does not exist.
--- @param file_path string fully qualified file path where data is saved
--- @return ProjectabPersistenceProjects projects
function M.load_data(file_path)
  --- @type ProjectabPersistenceProjects|nil
  local data = M.read_json(file_path)
  if data and data.version then
    return data
  end
  return emptyProjectabData()
end

--- Save persistence.json.
--- @param file_path string fully qualified file path where data is saved
--- @param projects string[]
--- @return boolean success
function M.save_data(file_path, projects)
  --- @type ProjectabPersistenceProjects
  local data = emptyProjectabData()
  data.projects = projects
  return M.write_json(file_path, data)
end

--- Load per-project state from its JSON file.
--- Returns nil if the file does not exist.
--- @param root string Project root (absolute path)
--- @return ProjectabPersistenceProjectData|nil project_data
function M.load_project(root)
  return M.read_json(M.get_project_path(root))
end

--- Save per-project state to its JSON file.
--- @param root string Project root (absolute path)
--- @param data ProjectabPersistenceProjectData Project state data
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

--- Return a list of project roots sorted by most recently saved.
--- @param limit integer? Optional maximum number of results to return
--- @return string[] Unencoded absolute paths of recent projects
function M.list_projects_by_recency(limit)
  limit = limit or 50
  local projects_dir = M.get_project_data_root_dir()
  local stat = vim.uv.fs_stat(projects_dir)
  if not stat or stat.type ~= "directory" then
    return {}
  end

  local scan = vim.uv.fs_scandir(projects_dir)
  if not scan then
    return {}
  end

  local projects = {} ---@type { root: string, last_saved: integer }[]
  while true do
    local name, type = vim.uv.fs_scandir_next(scan)
    if not name then
      break
    end
    if type == "file" and name:match("%.json$") then
      local path = projects_dir .. "/" .. name
      local data = M.read_json(path)
      if data and data.root and data.last_saved then
        table.insert(projects, { root = data.root, last_saved = data.last_saved })
      end
    end
  end

  table.sort(projects, function(a, b)
    return a.last_saved > b.last_saved
  end)

  local result = {}
  for i, p in ipairs(projects) do
    if i > limit then
      break
    end
    table.insert(result, p.root)
  end
  return result
end

return M
