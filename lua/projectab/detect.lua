--- Project root detection module for projectab.nvim
--- Uses vim.uv.fs_stat to traverse upward and find project markers.
---
--- Strategy: "nearest root wins" — starts from the file's directory and walks
--- upward until a marker (e.g., .git, go.mod) is found. The first (deepest)
--- match is returned. This correctly handles nested project repositories.
---
--- Caching: Results are cached per directory (not per file) since all files
--- in the same directory share the same project root. Cache entries are either
--- a string (root path) or false (no root found). The cache persists for the
--- lifetime of the Neovim session and can be cleared manually via clear_cache().
--- @class ProjectabDetectModule
local M = {}

local config = require("projectab.config")
local log = require("projectab.log")

--- Root detection cache.
--- Key:   directory path (the file's parent directory, normalized)
--- Value: string (project root path) or false (no root exists for this dir)
---
--- Using false instead of nil so we can distinguish:
---   cache[dir] == nil   → not yet cached (cache miss)
---   cache[dir] == false → cached negative result (no root found)
---   cache[dir] == "/x"  → cached positive result
--- @type table<string, string|false>
local root_cache = {}

--- Get the parent directory of a path.
--- @param path string
--- @return string|nil Parent path, or nil if already at root
local function parent_dir(path)
  if path == "/" then
    return nil
  end
  local parent = vim.fn.fnamemodify(path, ":h")
  if parent == path then
    return nil
  end
  return parent
end

--- Check if a directory should be excluded.
--- @param dir string Directory path to check
--- @param expanded_excludes string[] List of already-expanded directory prefixes
--- @return boolean
local function is_excluded(dir, expanded_excludes)
  for _, exclude in ipairs(expanded_excludes) do
    if dir:find(exclude, 1, true) == 1 then
      return true
    end
  end
  return false
end

--- Check if any pattern marker exists in the given directory.
--- Uses vim.uv.fs_stat (libuv synchronous syscall) rather than vim.fn.glob
--- because fs_stat is faster and doesn't trigger wildignore filtering.
--- O(P) per directory level where P = number of patterns.
--- @param dir string Directory to check
--- @param patterns string[] Marker names to look for
--- @return boolean
local function has_marker(dir, patterns)
  for _, pattern in ipairs(patterns) do
    local marker_path = dir .. "/" .. pattern
    local stat = vim.uv.fs_stat(marker_path)
    if stat then
      return true
    end
  end
  return false
end

--- Detect the project root for a given file path.
--- Walks upward from the file's directory, checking each level for marker patterns.
--- Returns the nearest (deepest) matching root.
---
--- Results are cached per directory. On cache hit, no fs_stat calls are made.
---
--- Time (cache miss): O(D * (P + E)) where D = depth, P = patterns, E = excludes.
--- Time (cache hit):  O(1).
--- Space: O(D_unique) where D_unique = number of unique directories ever queried.
---
--- @param filepath string Absolute path to the file
--- @return string|nil Project root path, or nil if not found
function M.get_root(filepath)
  if not filepath or filepath == "" then
    return nil
  end

  -- Start from the file's directory (or the directory itself if it's already one)
  local stat = vim.uv.fs_stat(filepath)
  local dir
  if stat and stat.type == "directory" then
    dir = vim.fn.fnamemodify(filepath, ":p")
  else
    dir = vim.fn.fnamemodify(filepath, ":p:h")
  end
  dir = vim.fs.normalize(dir)

  -- Cache lookup: all files in the same directory share the same root.
  local cached = root_cache[dir]
  if cached ~= nil then
    -- cached is either a string (root) or false (no root)
    if cached == false then
      return nil
    end
    return cached
  end

  local opts = config.values
  local patterns = opts.project.root_markers
  -- Expand excluded_root_dirs once per call, not once per directory level.
  -- This avoids repeated VimL calls for the same exclude patterns.
  local expanded_excludes = {}
  for _, exclude in ipairs(opts.project.excluded_root_dirs) do
    table.insert(expanded_excludes, vim.fs.normalize(vim.fn.expand(exclude)))
  end

  -- Walk upward from the file's directory
  local search_dir = dir
  while search_dir do
    if is_excluded(search_dir, expanded_excludes) then
      log.debug_ctx(string.format("detect: excluded dir=%s", search_dir))
      -- Cache the negative result for the original query directory
      root_cache[dir] = false
      return nil
    end

    if has_marker(search_dir, patterns) then
      log.debug_ctx(string.format("detect: root=%s for path=%s", search_dir, filepath))
      -- Cache the result for the original query directory
      root_cache[dir] = search_dir
      return search_dir
    end

    search_dir = parent_dir(search_dir)
  end

  log.debug_ctx(string.format("detect: no root for path=%s", filepath))
  -- Cache the negative result
  root_cache[dir] = false
  return nil
end

--- Clear the root detection cache.
--- Call this if project structure changes during a session
--- (e.g., `git init` in a previously untracked directory).
function M.projects_clear_root_cache()
  log.debug_ctx("detect: cache to be cleared: " .. tostring(root_cache))
  root_cache = {}
  log.debug_ctx("detect: cache cleared")
end

--- Return the number of cached entries (for testing/debugging).
--- @return integer
function M._cache_size()
  local count = 0
  for _ in pairs(root_cache) do
    count = count + 1
  end
  return count
end

return M
