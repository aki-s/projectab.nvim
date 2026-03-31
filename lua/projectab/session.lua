--- Session save/restore module for projectab.nvim
--- Collects buffer state from tabs and restores them.
---
--- Save flow:
---   1. For each registered project→tab, collect absolute buffer paths and active buffer.
---   2. Write per-project JSON via persistence module.
---   3. Update dashboard.json MRU history.
---
--- Restore flow:
---   1. Read per-project JSON.
---   2. If project root does not exist → delete registration + project file.
---   3. Skip buffers whose files no longer exist on disk.
---   4. If no buffers can be opened → open project root directory.
---   5. Focus the active_buffer if it was restored.
--- @class ProjectabSessionModule
local M = {}

local log = require("projectab.log")
local persistence = require("projectab.persistence")
local state = require("projectab.state")

--- Collect the buffer list for a given tab.
--- Only includes normal file buffers (buftype == "") with non-empty names.
--- All paths are absolute.
--- @param tab_id integer
--- @return string[] buffers List of absolute buffer paths
--- @return string|nil active_buffer The buffer that currently has focus
local function collect_tab_buffers(tab_id)
  local buffers = {}
  local seen = {}

  -- Collect from all windows in the tab
  local wins = vim.api.nvim_tabpage_list_wins(tab_id)
  local active_win = vim.api.nvim_tabpage_get_win(tab_id)
  local active_buffer = nil

  local project_root = state.get_project(tab_id)
  local buffer_module = require("projectab.buffer")

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "" then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        name = vim.fn.fnamemodify(name, ":p")
        if not seen[name] then
          if project_root and buffer_module.resolve_project_root_from_path(name) == project_root then
            seen[name] = true
            table.insert(buffers, name)
            if win == active_win then
              active_buffer = name
            end
          else
            log.debug_ctx("session: skipping window buffer belonging to another project: " .. name)
          end
        end
      end
    end
  end

  -- Also collect listed buffers that are loaded but not visible in any window.
  -- These are buffers the user had open (e.g., in a buffer list) but not displayed.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted and vim.bo[bufnr].buftype == "" then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        name = vim.fn.fnamemodify(name, ":p")
        if not seen[name] then
          -- Check if this buffer belongs to this project tab.
          -- Use buffer routing logic instead of string prefix to properly handle nested projects.
          if project_root and buffer_module.resolve_project_root_from_path(name) == project_root then
            seen[name] = true
            table.insert(buffers, name)
          end
        end
      end
    end
  end

  return buffers, active_buffer
end

--- Open a project in its own tab, or open a file/directory in its project's tab.
--- If the project is already open, switch to its tab.
--- Otherwise, create a new tab with tcd set to the project root.
--- @param path string Absolute path to a file or directory within the project
--- @param opts? { callback?: fun(tab_id: integer), edit?: boolean } Optional callback after tab is ready
function M.project_open(path, opts)
  opts = opts or {}
  local state = require("projectab.state")
  local log = require("projectab.log")
  local buffer = require("projectab.buffer")

  -- Normalize: expand ~, resolve symlinks (e.g., macOS /tmp → /private/tmp)
  local target_path = vim.fn.expand(path)
  target_path = vim.uv.fs_realpath(target_path) or target_path

  -- Resolve project root from the given path (works for both files and directories)
  local project_root = buffer.resolve_project_root_from_path(target_path)
  if not project_root then
    vim.notify(string.format("[ProjecTab] No project root found for: %s", target_path), vim.log.levels.ERROR)
    return
  end

  -- Remove trailing slash for consistent registration
  project_root = project_root:gsub("/$", "")

  -- Check if project already has a tab
  local existing_tab = state.get_tab(project_root)
  if existing_tab then
    vim.api.nvim_set_current_tabpage(existing_tab)
    log.debug_ctx(string.format("open_project: switched to existing tab=%d for root=%s", existing_tab, project_root))

    -- Open the target file or directory
    if opts.edit ~= false then
      local stat = vim.uv.fs_stat(target_path)
      if stat and stat.type == "file" then
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      end
      -- For directories on existing tabs, don't open explorer
    end

    if opts.callback then
      opts.callback(existing_tab)
    end
    return
  end

  -- Create a new tab
  vim.cmd("tabnew")
  local new_tab_id = vim.api.nvim_get_current_tabpage()

  -- Register in state (this also sets tcd via register())
  state.register(project_root, new_tab_id)

  log.debug_ctx(string.format("open_project: created tab=%d for root=%s", new_tab_id, project_root))

  -- Open the target file or directory (must be done after tcd)
  if opts.edit ~= false then
    local stat = vim.uv.fs_stat(target_path)
    if stat and stat.type == "file" then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
    elseif stat and stat.type == "directory" then
      -- For directories, check if there are any buffers in the current tab
      local buffers = vim.api.nvim_list_bufs()
      local has_named_buffer = false
      for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
          has_named_buffer = true
          break
        end
      end

      -- Only open explorer if no named buffers exist (empty project)
      if not has_named_buffer then
        vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      end
    end
  end

  if opts.callback then
    opts.callback(new_tab_id)
  end
end

--- Save the state of a single project (tab).
--- @param root string Project root (absolute path)
--- @param tab_id integer Tab handle
--- @return boolean success
function M.project_save(root, tab_id)
  local buffers, active_buffer = collect_tab_buffers(tab_id)

  local data = {
    version = 1,
    root = root,
    last_saved = os.time(),
    state = {
      buffers = buffers,
      active_buffer = active_buffer,
    },
  }

  local ok = persistence.save_project(root, data)
  if ok then
    log.debug_ctx(string.format("session: saved project root=%s buffers=%d", root, #buffers))
  end
  return ok
end

--- Save all registered projects and update dashboard history.
--- Intended to be called on VimLeavePre or manually.
function M.projects_save()
  local projects = state.list_projects()
  local dashboard = persistence.load_dashboard()

  for root, tab_id in pairs(projects) do
    M.project_save(root, tab_id)
    dashboard = persistence.touch_history(dashboard, root)
  end

  persistence.save_dashboard(dashboard)
  log.debug_ctx("session: save_all complete")
end

--- Restore a single project into a new tab.
--- @param root string Project root (absolute path)
--- @return boolean success true if at least one buffer (or root dir) was opened
function M.project_restore(root)
  -- If the project root itself does not exist, clean up and bail out.
  if not vim.uv.fs_stat(root) then
    log.debug_ctx("session: project root does not exist, removing: " .. root)
    persistence.delete_project(root)
    local dashboard = persistence.load_dashboard()
    dashboard = persistence.remove_from_history(dashboard, root)
    persistence.save_dashboard(dashboard)
    vim.notify("[ProjecTab] Project no longer exists, removed: " .. root, vim.log.levels.WARN)
    return false
  end

  local data = persistence.load_project(root)
  if not data or not data.state then
    log.debug_ctx("session: no saved state for root=" .. root)
    return false
  end

  -- Open project using the existing open_project API
  -- (this creates a new tab or switches to existing one, and sets tcd)
  M.project_open(root, { edit = false })

  local buffers = data.state.buffers or {}
  local active_buffer = data.state.active_buffer

  local buffer_module = require("projectab.buffer")

  -- Filter out files that no longer exist OR do not belong to this project
  local valid_buffers = {}
  for _, buf_path in ipairs(buffers) do
    if vim.uv.fs_stat(buf_path) then
      local actual_root = buffer_module.resolve_project_root_from_path(buf_path)
      if actual_root == root then
        table.insert(valid_buffers, buf_path)
      else
        log.debug_ctx("session: skipping buffer belonging to another project: " .. buf_path)
      end
    else
      log.debug_ctx("session: skipping missing file: " .. buf_path)
    end
  end

  if #valid_buffers == 0 then
    -- No buffers can be opened: open the project root directory instead
    vim.cmd("edit " .. vim.fn.fnameescape(root))
    log.debug_ctx("session: no valid buffers, opened project root dir: " .. root)
    return true
  end

  -- Open all valid buffers
  for i, buf_path in ipairs(valid_buffers) do
    if i == 1 then
      -- First buffer: open in the current window (replacing the empty [No Name] buffer)
      vim.cmd("edit " .. vim.fn.fnameescape(buf_path))
    else
      -- Subsequent buffers: add to buffer list without switching
      vim.cmd("badd " .. vim.fn.fnameescape(buf_path))
    end
  end

  -- Focus the active buffer (if it still exists)
  if active_buffer and vim.uv.fs_stat(active_buffer) then
    vim.cmd("edit " .. vim.fn.fnameescape(active_buffer))
  end

  log.debug_ctx(string.format("session: restored project root=%s buffers=%d", root, #valid_buffers))
  return true
end

--- Restore all (default to limit the latest 50) projects from dashboard history.
--- Each project is restored into its own tab.
--- @param opts? { limit?: integer }
function M.projects_restore(opts)
  opts = opts or { limit = 50 }
  local limit = opts.limit
  local dashboard = persistence.load_dashboard()
  local restored = 0

  -- Suspend buffer routing during bulk restore to prevent tab-spawning cascades
  local buffer = require("projectab.buffer")
  buffer.suspend()

  local ok, err = pcall(function()
    for _, root in ipairs(dashboard.history) do
      if restored >= limit then
        break
      end
      if M.project_restore(root) then
        restored = restored + 1
      end
    end
  end)

  buffer.resume()

  if not ok then
    log.debug_ctx("session: error during restore_all: " .. tostring(err))
    vim.notify("[ProjecTab] Error during restore: " .. tostring(err), vim.log.levels.ERROR)
  end

  log.debug_ctx(string.format("session: restore_all complete, restored=%d", restored))
end

--- Return a list of historically accessed project roots from persistence.
--- @return string[] history
function M.list_history()
  local dashboard = persistence.load_dashboard()
  return dashboard.history or {}
end

return M
