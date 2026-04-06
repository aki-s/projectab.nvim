--- State management module for projectab.nvim
--- Maintains bidirectional mapping between project roots and tab handles.
---
--- Design: "tcd as persistence, maps as runtime cache"
---   - register() is the ONLY function that sets tcd and updates maps.
---     This eliminates the "dual Source of Truth" problem where tcd and
---     maps could diverge.
---   - scan_existing_tabs() rebuilds maps from tcd (priority 1) or buffer
---     detection (priority 2, fallback). This handles session restore.
---   - All lookups go through the maps for O(1) performance.
---
--- Invariant: project_to_tab[root] == tab_id ⇔ tab_to_project[tab_id] == root
---            (1-to-1 mapping, enforced by register/unregister)
---
--- All lookups are O(1). Space is O(T) where T = number of tabs.
--- @class ProjectabStateModule
local M = {}

local log = require("projectab.log")

--- @class ProjectabState
--- @field project_to_tab table<string, integer> Project root path → tab handle
--- @field tab_to_project table<integer, string> Tab handle → project root path

--- @type ProjectabState
local state = {
  project_to_tab = {},
  tab_to_project = {},
}

--- Register a project-to-tab mapping (bidirectional) and set tcd.
---
--- This is the SINGLE entry point for associating a project with a tab.
--- It performs THREE operations atomically:
---   1. Evict any stale mappings (maintains 1-to-1 invariant)
---   2. Update the bidirectional maps
---   3. Set tcd on the tab (if currently on that tab and path exists)
---
--- Callers MUST NOT call `vim.cmd("tcd ...")` separately — register handles it.
---
--- O(1) time.
--- @param project_root string
--- @param tab_id integer
function M.register(project_root, tab_id)
  -- 1. If this project was already associated with another tab, unregister that tab first.
  local old_tab = state.project_to_tab[project_root]
  if old_tab and old_tab ~= tab_id then
    state.tab_to_project[old_tab] = nil
  end

  -- 2. If this tab was already associated with another project, unregister that project first.
  local old_project = state.tab_to_project[tab_id]
  if old_project and old_project ~= project_root then
    state.project_to_tab[old_project] = nil
  end

  state.project_to_tab[project_root] = tab_id
  state.tab_to_project[tab_id] = project_root

  -- 3. Set tcd if we're currently on the target tab AND the directory exists.
  --    - We check current tab because `tcd` is a tab-local command that affects
  --      the CURRENT tab only. Callers are expected to be on the right tab.
  --    - We check directory existence because tcd errors on non-existent paths
  --      (this also prevents errors in unit tests with fake paths).
  if vim.api.nvim_get_current_tabpage() == tab_id then
    if vim.uv.fs_stat(project_root) then
      vim.cmd("tcd " .. vim.fn.fnameescape(project_root))
    end
  end

  log.debug_ctx(string.format("register root=%s tab=%d", project_root, tab_id))
end

--- Get the tab handle for a project root.
--- Returns nil if the tab is no longer valid (and cleans up stale entry).
--- O(1) time.
--- @param project_root string
--- @return integer|nil
function M.get_tab(project_root)
  local tab_id = state.project_to_tab[project_root]
  if tab_id and not vim.api.nvim_tabpage_is_valid(tab_id) then
    -- Stale entry: the tab was closed outside of our control. Clean up.
    M.unregister_tab(tab_id)
    return nil
  end
  return tab_id
end

--- Get the project root for a tab handle.
--- Does NOT validate tab existence (caller should check if needed).
--- O(1) time.
--- @param tab_id integer
--- @return string|nil
function M.get_project(tab_id)
  return state.tab_to_project[tab_id]
end

--- Unregister a tab and its associated project mapping.
--- O(1) time using bidirectional map.
--- @param tab_id integer
function M.unregister_tab(tab_id)
  local project_root = state.tab_to_project[tab_id]
  if project_root then
    state.project_to_tab[project_root] = nil
    log.debug_ctx(string.format("unregister root=%s tab=%d", project_root, tab_id))
  end
  state.tab_to_project[tab_id] = nil
end

--- Consolidate duplicate tabs for the same project.
--- Keeps the first known tab, moves buffers from duplicates, then closes them.
--- @return integer count Number of duplicate tabs closed
function M.consolidate_duplicate_tabs()
  local closed_count = 0
  local valid_tabs = vim.api.nvim_list_tabpages()

  -- Reverse iterate so closing tabs doesn't disrupt traversal
  for i = #valid_tabs, 1, -1 do
    local dup_tab = valid_tabs[i]
    if vim.api.nvim_tabpage_is_valid(dup_tab) then
      local dup_root = state.tab_to_project[dup_tab]

      -- If tab is unregistered, try to detect its root directly
      if not dup_root then
        local tab_nr = vim.api.nvim_tabpage_get_number(dup_tab)
        if vim.fn.haslocaldir(-1, tab_nr) == 1 then
          dup_root = vim.fs.normalize(vim.fn.getcwd(-1, tab_nr))
        else
          -- Fallback to buffering detection
          local wins = vim.api.nvim_tabpage_list_wins(dup_tab)
          for _, win in ipairs(wins) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].buftype == "" then
              -- Need to dynamically invoke resolve to avoid cyclic req
              local ok, buffer_mod = pcall(require, "projectab.buffer")
              if ok and buffer_mod.resolve_project_root then
                dup_root = buffer_mod.resolve_project_root(buf)
                if dup_root then
                  break
                end
              end
            end
          end
        end
      end

      if dup_root then
        local keep_tab = state.project_to_tab[dup_root]
        -- If this project has a registered tab that IS NOT dup_tab, then dup_tab is a duplicate!
        if keep_tab and keep_tab ~= dup_tab and vim.api.nvim_tabpage_is_valid(keep_tab) then
          -- Move all buffers from duplicate tab to keep_tab
          local wins = vim.api.nvim_tabpage_list_wins(dup_tab)
          for _, win in ipairs(wins) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" then
              -- Switch to keep_tab and open the buffer there
              vim.api.nvim_set_current_tabpage(keep_tab)
              vim.cmd("buffer " .. buf)
            end
          end

          -- Close the duplicate tab
          pcall(vim.api.nvim_tabpage_close, dup_tab, false)
          M.unregister_tab(dup_tab)
          closed_count = closed_count + 1
          log.debug_ctx(
            string.format("consolidated duplicate tab=%d into tab=%d for root=%s", dup_tab, keep_tab, dup_root)
          )
        end
      end
    end
  end

  return closed_count
end

--- Clean up all entries for tabs that no longer exist.
--- Called on TabClosed event.
--- O(T + P) time where T = valid tabs, P = registered projects.
function M.cleanup()
  local valid_tabs = {}
  for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
    valid_tabs[tab_id] = true
  end

  for tab_id, _ in pairs(state.tab_to_project) do
    if not valid_tabs[tab_id] then
      M.unregister_tab(tab_id)
    end
  end
end

--- Scan all existing tabs and build state from scratch.
--- Used on VimEnter / SessionLoadPost to discover project→tab associations
--- that exist before (or were restored without) projectab's runtime maps.
---
--- Source priority:
---   1. tcd (persistent, preserved by :mksession and most session managers)
---   2. detect_fn (fallback for tabs where tcd was not preserved)
---
--- Only registers a tab if:
---   - The tab has no existing state mapping
---   - The detected project isn't already claimed by another tab
---
--- Note: Does NOT call register() because we may not be on the target tab
--- (and register() requires being on the current tab to set tcd). Instead,
--- populates the maps directly. tcd is either already set (source 1) or will
--- be set lazily when the user switches to that tab and BufEnter fires.
---
--- @param detect_fn fun(bufnr: integer): string|nil
---   Receives a buffer number (NOT a filepath). Must return the project root
---   path or nil. Typically `buffer.resolve_project_root`.
function M.scan_existing_tabs(detect_fn)
  for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
    if not state.tab_to_project[tab_id] then
      local root = nil

      -- Source 1: tcd (preserved across session restore by :mksession).
      -- haslocaldir(-1, tabnr) returns 1 when a tab-local directory is set.
      local tab_nr = vim.api.nvim_tabpage_get_number(tab_id)
      if vim.fn.haslocaldir(-1, tab_nr) == 1 then
        root = vim.fs.normalize(vim.fn.getcwd(-1, tab_nr))
        log.debug_ctx(string.format("scan found tcd=%s for tab=%d", root, tab_id))
      end

      -- Source 2: detect from buffers (fallback when tcd not preserved).
      if not root and detect_fn then
        local wins = vim.api.nvim_tabpage_list_wins(tab_id)
        for _, win in ipairs(wins) do
          local bufnr = vim.api.nvim_win_get_buf(win)
          if vim.bo[bufnr].buftype == "" then
            root = detect_fn(bufnr)
            if root then
              break
            end
          end
        end
      end

      -- Populate maps directly (not via register — we may not be on this tab).
      if root and not M.get_tab(root) then
        state.project_to_tab[root] = tab_id
        state.tab_to_project[tab_id] = root
        log.debug_ctx(string.format("scan registered root=%s tab=%d", root, tab_id))
      end
    end
  end
  log.debug_ctx("scan_existing_tabs complete")
end

--- List all opened projects with their tab handles.
--- Filters out stale entries (tabs that no longer exist) and cleans them up.
--- @return table<string, integer> Map of project_root → tab_id (valid tabs only)
function M.list_projects()
  local result = {}
  local stale_tabs = {}
  for root, tab_id in pairs(state.project_to_tab) do
    if vim.api.nvim_tabpage_is_valid(tab_id) then
      result[root] = tab_id
    else
      -- Collect stale entries for cleanup (don't modify during iteration)
      table.insert(stale_tabs, tab_id)
    end
  end
  -- Clean up stale entries
  for _, tab_id in ipairs(stale_tabs) do
    M.unregister_tab(tab_id)
  end
  return result
end

--- Return a copy of the internal state (for debugging / testing).
--- @return ProjectabState
function M._get_state()
  return vim.deepcopy(state)
end

--- Reset all state (for testing).
function M._reset()
  state.project_to_tab = {}
  state.tab_to_project = {}
end

return M
