--- Buffer dispatch module for projectab.nvim
--- Routes new buffers to their project's tab.
---
--- Responsibility:
---   1. Resolve which project a buffer belongs to (via detect or project.nvim)
---   2. Allocate the buffer to the correct tab ("1 project = 1 tab" rule)
---   3. Guard against re-entrant / bulk BufEnter events (session restore, macros)
---   4. Clean up misplaced buffers after session restore
--- @class ProjectabBufferModule
local M = {}

local config = require("projectab.config")
local detect = require("projectab.detect")
local log = require("projectab.log")
local notify = require("projectab.ui.notify")
local state = require("projectab.state")

--- Try to open netrw via Explore, but gracefully fallback to enew if netrw is disabled
--- or not loaded (such as in headless tests where --noplugin is used).
local function open_fallback_explorer()
  if vim.fn.exists(":Explore") > 0 then
    vim.cmd("Explore")
  else
    vim.cmd("enew")
  end
end

--- Resolve project root for a given path.
--- Uses project.nvim integration if enabled, otherwise native detection.
--- @param path string
--- @return string|nil
function M.resolve_project_root_from_path(path)
  if not path or path == "" then
    return nil
  end

  local integration_root = nil
  -- Try project.nvim integration first if enabled
  if config.values.integrations.project_nvim then
    local ok, integration = pcall(require, "projectab.integrations.project_nvim")
    ---@cast integration ProjectabProjectNvimIntegration
    if ok then
      integration_root = integration.get_root(path)
    end
  end

  -- Fall back to native detection
  local native_root = detect.get_root(path)

  if integration_root and native_root then
    -- Deepest root wins (longest path string)
    if #native_root > #integration_root then
      return native_root
    else
      return integration_root
    end
  end

  return native_root or integration_root
end

--- Resolve project root for a buffer.
--- Uses project.nvim integration if enabled, otherwise native detection.
--- @param bufnr integer
--- @return string|nil
function M.resolve_project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  return M.resolve_project_root_from_path(path)
end

--- Core allocation logic for a buffer to a project's tab.
--- Enforces the "1 project = 1 tab" rule.
--- Can be unit-tested without requiring UI events.
---
--- Decision tree:
---   target_tab_id exists → switch to it (if not already there)
---   target_tab_id is nil:
---     current tab is unclaimed → claim it for this project
---     current tab is claimed by different project → create new tab
---
--- @param bufnr integer
--- @param project_root string
--- @param current_tab_id integer
--- @param target_tab_id integer|nil The tab already assigned to this project
--- @return integer allocated_tab_id, boolean is_new_tab
function M.allocate_buffer_to_tab(bufnr, project_root, current_tab_id, target_tab_id)
  if target_tab_id then
    -- Project already has a tab: switch to it if not already there
    if target_tab_id ~= current_tab_id and vim.api.nvim_tabpage_is_valid(target_tab_id) then
      -- Temporary buflisted toggle to prevent our on_tab_leave from hiding this
      -- buffer in the source tab context during the window switch.
      local was_listed = vim.api.nvim_get_option_value("buflisted", { buf = bufnr })
      vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
      vim.api.nvim_set_current_tabpage(target_tab_id)
      vim.api.nvim_set_option_value("buflisted", was_listed, { buf = bufnr })

      -- Ensure buffer is visible in the target tab context
      vim.cmd("buffer " .. bufnr)
      log.debug_ctx(string.format("buffer: routed bufnr=%d to existing tab=%d", bufnr, target_tab_id))
    end
    return target_tab_id, false
  else
    -- No tab for this project: create a new one OR register to current if empty
    local current_project = state.get_project(current_tab_id)
    if not current_project then
      -- Current tab is unclaimed: associate it with this project.
      -- register() handles tcd setting internally.
      state.register(project_root, current_tab_id)
      log.debug_ctx(string.format("buffer: registered current tab=%d to root=%s", current_tab_id, project_root))
      return current_tab_id, false
    else
      -- Current tab is already busy: create a new tab to maintain "1 project = 1 tab"
      -- `tab sb` splits the buffer into a new tab AND makes it visible there

      -- Temporary buflisted toggle to prevent our on_tab_leave from hiding this
      -- buffer in the source tab context during the window switch.
      local was_listed = vim.api.nvim_get_option_value("buflisted", { buf = bufnr })
      vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
      vim.cmd("tab sb " .. bufnr)
      vim.api.nvim_set_option_value("buflisted", was_listed, { buf = bufnr })

      local new_tab_id = vim.api.nvim_get_current_tabpage()
      -- register() handles tcd setting internally.
      state.register(project_root, new_tab_id)
      log.debug_ctx(string.format("buffer: created tab=%d for bufnr=%d root=%s", new_tab_id, bufnr, project_root))
      return new_tab_id, true
    end
  end
end

--- Module-local flag to suppress routing globally.
--- Set by suspend()/resume() API.
--- 3rd party session managers should call suspend() before bulk buffer operations
--- and resume() after, to prevent the plugin from spawning tabs during restore.
local is_suspended = false

--- Module-local reentrancy lock.
--- Prevents recursive BufEnter cascades when allocate_buffer_to_tab
--- changes the current tab/buffer (which triggers another BufEnter).
--- Using module-local instead of _G to avoid namespace pollution.
local is_routing = false

--- Suspend buffer routing globally.
--- Useful when triggering 3rd party session managers that do not set `vim.g.SessionLoad`.
--- Useful for session plugins to perform bulk restores.
function M.suspend()
  is_suspended = true
  log.debug_ctx("buffer routing suspended")
  return is_suspended
end

--- Resume buffer routing globally.
function M.resume()
  is_suspended = false
  log.debug_ctx("buffer routing resumed")
  return is_suspended
end

--- Toggle buffer routing globally.
--- Useful when temporally open all new buffers in the current tab.
function M.routing_toggle()
  is_suspended = not is_suspended
  log.debug_ctx("buffer routing toggle to: " .. tostring(is_suspended))
  return is_suspended
end

--- Handle BufEnter event for a buffer.
--- Determines its project and routes it to the correct tab.
--- @param bufnr integer
function M.handle_buf_enter(bufnr)
  -- Guard: skip routing if suspended via API (e.g., 3rd-party session restore)
  if is_suspended then
    log.debug_ctx("buffer: skip routing (suspended via API)")
    return
  end

  -- Guard: skip routing during Neovim-native session restore (`:mksession` / `:source`).
  -- Neovim sets vim.g.SessionLoad = true while `:source Session.vim` is executing.
  -- Some 3rd party plugins (persistence.nvim) go through this path; others don't.
  if vim.g.SessionLoad then
    log.debug_ctx("buffer: skip routing (SessionLoad active)")
    return
  end

  -- Guard: buffer must be valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Guard: skip special buffers (help, quickfix, terminal, etc.)
  -- Only route normal file buffers (buftype == "")
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  -- Guard: skip unlisted buffers (Dashboard, scratch buffers, etc.)
  if not vim.bo[bufnr].buflisted then
    log.debug_ctx("buffer: skip routing (unlisted buffer)")
    return
  end

  -- Guard: skip unnamed buffers (empty buffers have no project association)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    log.debug_ctx("buffer: skip routing (unnamed buffer)")
    return
  end

  local project_root = M.resolve_project_root(bufnr)
  if not project_root then
    return
  end

  local target_tab_id = state.get_tab(project_root)
  local current_tab_id = vim.api.nvim_get_current_tabpage()
  local current_win_id = vim.api.nvim_get_current_win()

  -- Reentrancy guard: prevent infinite switching loops.
  -- allocate_buffer_to_tab may call nvim_set_current_tabpage / vim.cmd("buffer ...")
  -- which fires another BufEnter. This lock breaks that recursion.
  if is_routing then
    log.debug_ctx("buffer: skip routing (already routing)")
    return
  end

  is_routing = true
  local allocated_tab_id
  local ok, err = pcall(function()
    allocated_tab_id, _ = M.allocate_buffer_to_tab(bufnr, project_root, current_tab_id, target_tab_id)
  end)
  is_routing = false

  if not ok then
    log.debug_ctx("buffer: routing error: " .. tostring(err))
    notify("Error during buffer routing: " .. tostring(err), vim.log.levels.ERROR)
  elseif allocated_tab_id and allocated_tab_id ~= current_tab_id then
    -- Clean up the source window if we moved the buffer to a different tab,
    -- which happens when users do e.g., `:vsplit /other_project_file`.
    if vim.api.nvim_win_is_valid(current_win_id) and vim.api.nvim_tabpage_is_valid(current_tab_id) then
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(current_win_id) or not vim.api.nvim_tabpage_is_valid(current_tab_id) then
          return
        end

        local wins_in_tab = #vim.api.nvim_tabpage_list_wins(current_tab_id)
        local all_wins_in_nvim = #vim.api.nvim_list_wins()
        local remaining_bufnr = vim.api.nvim_win_get_buf(current_win_id)
        local remaining_is_unnamed = vim.api.nvim_buf_is_valid(remaining_bufnr)
          and vim.api.nvim_buf_get_name(remaining_bufnr) == ""

        if all_wins_in_nvim <= 1 then
          vim.api.nvim_win_call(current_win_id, function()
            open_fallback_explorer()
          end)
        elseif wins_in_tab <= 1 then
          if remaining_is_unnamed then
            pcall(vim.api.nvim_tabpage_close, current_tab_id, false)
            log.debug_ctx(string.format("buffer: closed empty tab=%d (remaining buffer was unnamed)", current_tab_id))
          else
            vim.api.nvim_win_call(current_win_id, function()
              open_fallback_explorer()
            end)
            log.debug_ctx(
              string.format(
                "buffer: replaced source window=%d with Explore (preserved empty tab=%d)",
                current_win_id,
                current_tab_id
              )
            )
          end
        else
          vim.api.nvim_win_close(current_win_id, false)
          log.debug_ctx(
            string.format("buffer: closed source split window=%d in tab=%d", current_win_id, current_tab_id)
          )
        end
      end)
    end
  end
end

--- Cleanup misplaced buffers based on "1 project = 1 tab" rule.
--- Called after session restore (SessionLoadPost, VimEnter) to fix buffers
--- that ended up in the wrong tab.
---
--- Uses a 2-pass approach for safety:
---   Pass 1: Scan all tabs/windows and collect a list of moves needed.
---           No tab/window mutations happen — safe to iterate.
---   Pass 2: Execute the collected moves. Suspend routing first to prevent
---           BufEnter cascades during the moves.
function M.clean_misplaced_buffers()
  -- Step 1: scan to ensure at least one tab is registered per project.
  -- This builds state from tcd / buffer paths for any tabs not yet tracked.
  state.scan_existing_tabs(M.resolve_project_root)

  local valid_tabs = vim.api.nvim_list_tabpages()

  -- Pass 1: collect moves without mutating tabs/windows
  --- @type { bufnr: integer, source_tab: integer, source_win: integer, target_tab: integer, project_root: string }[]
  local moves = {}

  for _, tab_id in ipairs(valid_tabs) do
    local tab_project = state.get_project(tab_id)
    local wins = vim.api.nvim_tabpage_list_wins(tab_id)

    for _, win_id in ipairs(wins) do
      local bufnr = vim.api.nvim_win_get_buf(win_id)

      -- Skip special buffers (only route normal file buffers)
      if vim.bo[bufnr].buftype == "" then
        local buf_project = M.resolve_project_root(bufnr)

        if buf_project and buf_project ~= tab_project then
          -- Buffer is in the wrong tab (or an unmapped tab)
          local target_tab_id = state.get_tab(buf_project)

          if target_tab_id and target_tab_id ~= tab_id then
            table.insert(moves, {
              bufnr = bufnr,
              source_tab = tab_id,
              source_win = win_id,
              target_tab = target_tab_id,
              project_root = buf_project,
            })
          end
        end
      end
    end
  end

  if #moves == 0 then
    return
  end

  -- Pass 2: execute moves with routing suspended to prevent BufEnter cascades.
  -- Each move: open the buffer in the target tab, then close/replace the source window.
  M.suspend()
  local restore_ok, restore_err = pcall(function()
    for _, move in ipairs(moves) do
      -- Validate handles before acting — earlier moves may have closed the tab/window
      if
        vim.api.nvim_tabpage_is_valid(move.target_tab)
        and vim.api.nvim_tabpage_is_valid(move.source_tab)
        and vim.api.nvim_win_is_valid(move.source_win)
      then
        -- Open the buffer in the target tab
        vim.api.nvim_set_current_tabpage(move.target_tab)
        vim.cmd("buffer " .. move.bufnr)

        -- Ensure target tab has correct tcd (skip if already correct).
        -- We're on the target tab now, so register() can set tcd.
        local target_project = state.get_project(move.target_tab)
        if target_project then
          local tab_nr = vim.api.nvim_tabpage_get_number(move.target_tab)
          local current_tcd = vim.fn.getcwd(-1, tab_nr)
          if current_tcd ~= target_project then
            -- Re-register to set tcd (we're on the correct tab)
            state.register(target_project, move.target_tab)
          end
        end

        log.debug_ctx(
          string.format("cleanup: moved bufnr=%d from tab=%d to tab=%d", move.bufnr, move.source_tab, move.target_tab)
        )

        -- Deal with the source window that now holds a stale buffer
        if vim.api.nvim_tabpage_is_valid(move.source_tab) then
          vim.api.nvim_set_current_tabpage(move.source_tab)

          local wins_in_tab = #vim.api.nvim_tabpage_list_wins(move.source_tab)
          local all_wins_in_nvim = #vim.api.nvim_list_wins()

          if all_wins_in_nvim <= 1 then
            -- Absolute last window in Neovim: can't close it at all; fallback to Explore
            vim.api.nvim_set_current_win(move.source_win)
            open_fallback_explorer()
            log.debug_ctx(string.format("cleanup: replaced window=%d with Explore (last window)", move.source_win))
          elseif wins_in_tab <= 1 then
            -- Use the actual current buffer in the window to check if it's unnamed
            local remaining_buf = vim.api.nvim_win_get_buf(move.source_win)
            local remaining_is_unnamed = vim.api.nvim_buf_is_valid(remaining_buf)
              and vim.api.nvim_buf_get_name(remaining_buf) == ""

            if remaining_is_unnamed then
              pcall(vim.api.nvim_tabpage_close, move.source_tab, false)
              log.debug_ctx(string.format("cleanup: closed completely empty tab=%d", move.source_tab))
            else
              vim.api.nvim_set_current_win(move.source_win)
              open_fallback_explorer()
              log.debug_ctx(
                string.format(
                  "cleanup: replaced window=%d with Explore (preserved empty workspace=%d)",
                  move.source_win,
                  move.source_tab
                )
              )
            end
          else
            -- Normal window inside a multi-window tab: just close the window
            vim.api.nvim_win_close(move.source_win, false)
            log.debug_ctx(string.format("cleanup: closed window=%d in tab=%d", move.source_win, move.source_tab))
          end
        end
      end
    end
  end)
  M.resume()

  if not restore_ok then
    log.debug_ctx("cleanup: error during misplaced buffer cleanup: " .. tostring(restore_err))
    notify("Error during misplaced buffer cleanup: " .. tostring(restore_err), vim.log.levels.ERROR)
  end
end

-- ============================================================================
-- (tab <-> buffers) mapping
-- ============================================================================

--- Cache for tab-local buffer visibility.
--- Tracks which buffers are listed in which tab.
--- @type table<integer, integer[]> Array of valid listed buffers per tab ID
M._tab_buffers = {}

--- Get all valid, listed buffers
--- @return integer[]
local function get_valid_listed_buffers()
  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      table.insert(buffers, bufnr)
    end
  end
  return buffers
end

--- Handle TabLeave: Save current tab's listed buffers and hide them from other tabs
function M.on_tab_leave()
  -- Skip during session restore: Neovim cycles through tabs while loading;
  -- caching half-restored state would corrupt the visibility cache.
  if vim.g.SessionLoad then
    return
  end
  local tab_id = vim.api.nvim_get_current_tabpage()
  local buffers = get_valid_listed_buffers()
  M._tab_buffers[tab_id] = buffers

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
    end
  end
  log.debug_ctx(string.format("buffer visibility: hid %d buffers for tab=%d", #buffers, tab_id))
end

--- Handle TabEnter: Restore this tab's listed buffers
function M.on_tab_enter()
  -- Skip during session restore: state is not yet stable.
  if vim.g.SessionLoad then
    return
  end
  local tab_id = vim.api.nvim_get_current_tabpage()
  local buffers = M._tab_buffers[tab_id]
  if buffers then
    local restored = 0
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
        restored = restored + 1
      end
    end
    log.debug_ctx(string.format("buffer visibility: restored %d buffers for tab=%d", restored, tab_id))
  end
end

--- Rebuild _tab_buffers from the current window state and hide non-current-tab buffers.
---
--- Called once after session restore (via a deferred callback in SessionLoadPost).
--- By that point every buffer has been reorganised into the correct tab by
--- clean_misplaced_buffers().  This function:
---   1. Scans each tab's windows to discover which named file-buffers live there.
---   2. Writes those buffers into _tab_buffers[tab_id], ensuring buflisted=true.
---   3. Hides (buflisted=false) every named file-buffer that does NOT belong to
---      the currently active tab.
---
--- After this call the invariant is:
---   - _tab_buffers[t]  is populated for every tab t  (never nil)
---   - Only the current tab's file-buffers are listed
---   - The first real on_tab_leave therefore only captures the current tab's
---     files, preventing them from being erroneously claimed by tab=1's cache.
--- @return nil
function M.rebuild_visibility_from_windows()
  local current_tab = vim.api.nvim_get_current_tabpage()

  M._tab_buffers = {}
  for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_bufs = {}
    local seen = {}
    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(tab_id)) do
      local bufnr = vim.api.nvim_win_get_buf(win_id)
      if
        vim.api.nvim_buf_is_valid(bufnr)
        and not seen[bufnr]
        and vim.bo[bufnr].buftype == ""
        and vim.api.nvim_buf_get_name(bufnr) ~= ""
      then
        table.insert(tab_bufs, bufnr)
        seen[bufnr] = true
        -- Ensure listed (may have been toggled during restore)
        vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
      end
    end
    M._tab_buffers[tab_id] = tab_bufs
  end

  -- Hide file-buffers that don't belong to the current tab so that the next
  -- on_tab_leave only sees the current tab's own files.
  local current_bufs = {}
  for _, bufnr in ipairs(M._tab_buffers[current_tab] or {}) do
    current_bufs[bufnr] = true
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.bo[bufnr].buflisted
      and vim.bo[bufnr].buftype == ""
      and vim.api.nvim_buf_get_name(bufnr) ~= ""
      and not current_bufs[bufnr]
    then
      vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
    end
  end

  log.debug_ctx(
    string.format(
      "buffer visibility: rebuilt from windows for %d tab(s); current tab has %d file-buffer(s)",
      #vim.api.nvim_list_tabpages(),
      #(M._tab_buffers[current_tab] or {})
    )
  )
end

--- Handle TabClosed: Cleanup visibility cache
--- @param tab_id integer
function M.on_tab_closed(tab_id)
  M._tab_buffers[tab_id] = nil
  log.debug_ctx(string.format("buffer visibility: cleared cache for tab=%d", tab_id))
end

return M
