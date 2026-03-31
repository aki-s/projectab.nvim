--- Autocmds setup for projectab.nvim
---
--- Lifecycle overview:
---   1. setup() registers autocmds for BufEnter, SessionLoadPost, TabEnter,
---      VimEnter, and TabClosed.
---   2. On VimEnter (once), a deferred scan runs to pick up tabs/buffers
---      that were restored by session plugins before projectab loaded.
---   3. On each BufEnter, buffer.handle_buf_enter routes the buffer to
---      the correct tab (or creates a new tab).
---   4. On SessionLoadPost, misplaced buffers are cleaned up.
---   5. On TabClosed, stale state entries are removed.
---
--- ref. https://neovim.io/doc/user/autocmd.html#_5.-events
---
--- @class ProjectabInitAutocmd
local M = {}

--- Register autocmds
function M.setup()
  local config = require("projectab.config")
  local log = require("projectab.log")
  local state = require("projectab.state")
  local buffer = require("projectab.buffer")

  local augroup = vim.api.nvim_create_augroup("ProjecTab", { clear = true })

  -- ======================================================================
  -- Read: BufReadPre -> BufReadPost -> BufWinEnter -> BufEnter
  --                                        BuffAdd -> BufEnter
  --                                        BuffNew -> BufEnter
  -- ======================================================================

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(_)
      require("projectab.ui.winbar").update()
    end,
  })
  -- Route buffers to their project's tab when entering them.
  -- NOT deferred (no vim.schedule) to prevent background race conditions
  -- where multiple BufEnter events interleave.
  -- Reentrancy is guarded by buffer.handle_buf_enter's internal lock.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      log.debug_ctx("autocmd/BufEnter")
      buffer.handle_buf_enter(args.buf)
      require("projectab.ui.winbar").update()
    end,
  })

  -- ======================================================================
  -- :mksession -> SessionLoadPost
  -- ======================================================================
  -- Refresh state after a session finishes loading (e.g. via persistence.nvim).
  -- Clean up misplaced buffers enforcing 1 project = 1 tab.
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = augroup,
    callback = function(_)
      log.debug_ctx("autocmd/SessionLoadPost")
      require("projectab.cleanup").projects_reorganize()

      -- Deferred: runs after all SessionLoadPost firings complete (one per buffer).
      -- At that point every buffer is in its correct tab, so we can rebuild the
      -- visibility cache from actual window state and hide non-current-tab buffers.
      vim.defer_fn(function()
        local cleanup = require("projectab.cleanup")
        local count = cleanup.projects_close_empty_tab()
        if count > 0 then
          log.debug_ctx(string.format("autocmd/SessionLoadPost: cleaned up %d empty tab(s)", count))
        end

        buffer.rebuild_visibility_from_windows()
      end, 100)
    end,
  })

  -- ======================================================================
  -- WinEnter -> (TabNew ->) TabEnter -> BufEnter (-> TabNewEnter)
  -- ======================================================================
  -- Restore buffer visibility and notify integrations on tab enter.
  vim.api.nvim_create_autocmd("TabEnter", {
    group = augroup,
    callback = function(_)
      log.debug_wd("autocmd/TabEnter")

      buffer.on_tab_enter()

      local tab_id = vim.api.nvim_get_current_tabpage()

      -- Default mode "require("bufferline.config").options.mode" 'buffer' does not work well with ProjecTab.
      if config.values.integrations.bufferline.enabled and require("bufferline.config").options.mode == "tabs" then
        local ok, bl = pcall(require, "projectab.integrations.bufferline")
        ---@cast bl ProjectabBufferlineIntegration
        if ok then
          bl.on_tab_enter(tab_id)
        end
      end
    end,
  })

  -- ======================================================================
  -- WinLeave -> TabLeave
  -- ======================================================================
  -- Hide buffers before leaving the tab to enforce tab-based buffer separation.
  vim.api.nvim_create_autocmd("TabLeave", {
    group = augroup,
    callback = function(_)
      log.debug_ctx("autocmd/TabLeave")
      buffer.on_tab_leave()
    end,
  })

  -- ======================================================================
  -- TabLeave -> TabClosed
  -- ======================================================================
  -- Clean up state and delete related buffers when a tab is closed.
  -- Removes the project→tab mapping for tabs that no longer exist.
  -- NOTE: `vim.cmd("tabclose")` synchronously triggers `TabLeave` followed by `TabClosed`.
  -- `TabLeave` will re-populate the buffer cache for the dying tab since it hasn't unregistered yet.
  -- To prevent race conditions and duplicate executions, explicit close commands MUST NOT
  -- manually delete buffers or clear states directly, but instead rely entirely on this `TabClosed`
  -- event handler to perform the full lifecycle teardown using `on_tab_closed`.
  vim.api.nvim_create_autocmd("TabClosed", {
    group = augroup,
    callback = function(args)
      log.debug_ctx("autocmd/TabClosed")
      local tab_id = tonumber(args.file)
      if tab_id then
        require("projectab.cleanup").on_tab_closed(tab_id)
      end
    end,
  })

  -- Scan existing tabs on startup to support session restore.
  -- Only VimEnter is used (not UIEnter) to avoid running twice.
  -- `once = true` ensures this fires exactly once.
  -- The 50ms defer allows other plugins (e.g., session managers) to finish
  -- loading their buffers before we scan.
  vim.api.nvim_create_autocmd("VimEnter", {
    group = augroup,
    once = true,
    callback = function(_)
      log.debug_ctx("autocmd/VimEnter")
      vim.defer_fn(function()
        -- 'reorganize' is for cases when buffer or tab is loaded before "VimEnter".
        require("projectab.cleanup").projects_reorganize()

        if config.values.ui.dashboard.enabled then
          local is_empty = vim.fn.argc(-1) == 0
            and vim.api.nvim_buf_get_name(0) == ""
            and vim.api.nvim_buf_line_count(0) == 1
            and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""

          if is_empty and not vim.bo[0].modified then
            require("projectab.ui.dashboard").open()
          end
        end
      end, 50)
    end,
  })

  -- ======================================================================
  -- VimLeavePre -> VimLeave
  -- ======================================================================
  -- Save all project states on VimLeavePre (before exit).
  if config.values.project.persistence.enabled then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = augroup,
      callback = function(_)
        log.debug_ctx("autocmd/VimLeavePre")
        local session = require("projectab.session")
        session.projects_save()
      end,
    })
  end
end

return M
