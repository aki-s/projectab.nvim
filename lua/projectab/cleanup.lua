--- Tab cleanup module for projectab.nvim
--- Handles cleanup of empty tabs and misplaced buffers.
---
--- Separation of concerns:
---   - This module owns tab cleanup logic
---   - state.lua owns project-to-tab mapping
---   - buffer.lua owns buffer routing logic
--- @class ProjectabCleanupModule
local M = {}

local log = require("projectab.log")
local state = require("projectab.state")

--- Close tabs that only contain unnamed/empty buffers.
--- Preserves at least one tab (never closes the last tab).
--- Preserves tabs with modified buffers (unsaved changes).
--- @return integer count Number of empty tabs closed
function M.projects_close_empty_tab()
  local closed_count = 0
  local all_tabs = vim.api.nvim_list_tabpages()

  -- Don't close the last tab
  if #all_tabs <= 1 then
    return 0
  end

  local projects = state.list_projects()
  for project_root, tab_id in pairs(projects) do
    if vim.api.nvim_tabpage_is_valid(tab_id) then
      local wins = vim.api.nvim_tabpage_list_wins(tab_id)
      local has_content = false

      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          local bufname = vim.api.nvim_buf_get_name(buf)
          local is_modified = vim.bo[buf].modified
          local is_normal_buffer = vim.bo[buf].buftype == ""

          -- Keep tab if it has a named buffer, modified buffer, or non-normal buffer type
          if (bufname ~= "" and is_normal_buffer) or is_modified then
            has_content = true
            break
          end
        end
      end

      if not has_content then
        -- Check again if this is the last tab (in case we closed others)
        all_tabs = vim.api.nvim_list_tabpages()
        if #all_tabs > 1 then
          -- Switch to a different tab before closing if we're on the tab to be closed
          local current_tab = vim.api.nvim_get_current_tabpage()
          if current_tab == tab_id then
            -- Find another tab to switch to
            for _, other_tab in ipairs(all_tabs) do
              if other_tab ~= tab_id then
                vim.api.nvim_set_current_tabpage(other_tab)
                break
              end
            end
          end

          -- Get tab number for :tabclose command
          local tab_nr = vim.api.nvim_tabpage_get_number(tab_id)
          local ok, err = pcall(vim.cmd, tab_nr .. "tabclose")
          if ok then
            state.unregister_tab(tab_id)
            closed_count = closed_count + 1
            log.debug_ctx(string.format("cleanup: closed empty tab=%d for root=%s", tab_id, project_root))
          else
            log.debug_ctx(string.format("cleanup: failed to close tab=%d: %s", tab_id, tostring(err)))
          end
        end
      end
    end
  end

  return closed_count
end

--- Reorganize tabs and buffers to maintain "1 project = 1 tab" rule.
--- 1. Consolidates duplicate tabs for the same project
--- 2. Moves misplaced buffers to their correct project tabs
--- @return table stats { consolidated: number, moved: number }
function M.projects_reorganize()
  local buffer = require("projectab.buffer")

  -- Step 1: Consolidate duplicate tabs
  local consolidated = state.consolidate_duplicate_tabs()

  -- Step 2: Clean misplaced buffers
  buffer.clean_misplaced_buffers()

  local msg = string.format("Reorganized: %d duplicate tab(s) closed, buffers moved to correct tabs", consolidated)
  log.debug_ctx(msg)
  if consolidated > 0 then
    vim.notify("[ProjecTab] " .. msg, vim.log.levels.INFO)
  end

  return { consolidated = consolidated }
end

--- Called by `p-close` command to explicitly close a project tab.
--- Saves the session and closes the tab, which naturally triggers TabClosed.
--- @param tab_id integer The tab page ID to close
function M.project_close(tab_id)
  local project_root = state.get_project(tab_id)
  if project_root then
    require("projectab.session").project_save(project_root, tab_id)
  end
  if vim.api.nvim_tabpage_is_valid(tab_id) then
    local tab_nr = vim.api.nvim_tabpage_get_number(tab_id)
    local ok, err = pcall(vim.cmd, tab_nr .. "tabclose")
    if ok then
      log.debug_ctx(string.format("cleanup: explicit close_project closed tab=%d", tab_id))
    else
      log.debug_ctx(string.format("cleanup: explicit close_project failed to close tab=%d: %s", tab_id, tostring(err)))
    end
  end
end

--- Called by TabClosed event. Handles clearing state and deleting related buffers.
--- @param tab_id integer The tab page ID that was closed
function M.on_tab_closed(tab_id)
  local buffer_module = require("projectab.buffer")
  -- Grab buffers to delete BEFORE clearing the cache
  local buffers_to_delete = buffer_module._tab_buffers[tab_id] or {}
  local buffers_copy = {}
  for _, bufnr in ipairs(buffers_to_delete) do
    table.insert(buffers_copy, bufnr)
  end
  -- Clear state caches
  buffer_module.on_tab_closed(tab_id)
  state.unregister_tab(tab_id)
  -- Delete buffers safely
  local deleted = 0
  for _, bufnr in ipairs(buffers_copy) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
      if ok then
        deleted = deleted + 1
      else
        require("projectab.log").debug_ctx("failed to delete buf " .. bufnr .. ": " .. tostring(err))
      end
    end
  end
  log.debug_ctx(string.format("cleanup: on_tab_closed deleted %d buffers for tab=%d", deleted, tab_id))
end

return M
