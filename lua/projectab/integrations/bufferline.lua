--- Bufferline.nvim integration for projectab.nvim
--- Provides project-based buffer grouping in bufferline.
---
--- Note: This module does NOT require "projectab.buffer" at module level
--- to avoid circular dependency (buffer → state → ... → bufferline → buffer).
--- Instead, buffer.resolve_project_root is accessed via lazy require.
--- @class ProjectabBufferlineIntegration
local M = {}

local state = require("projectab.state")
local log = require("projectab.log")

--- Get the project name (basename of root) for a tab.
--- @param tab_id integer
--- @return string|nil
function M.get_project_name_by_tab(tab_id)
  local root = state.get_project(tab_id)
  if root then
    return vim.fn.fnamemodify(root, ":t")
  end
  return nil
end

--- Get the project name for a buffer by detecting its root.
--- Uses the same resolve logic as buffer routing (project.nvim → native fallback).
--- @param bufnr integer
--- @return string|nil
function M.get_project_name_by_buffer(bufnr)
  local buffer = require("projectab.buffer")
  local root = buffer.resolve_project_root(bufnr)
  if root then
    return vim.fn.fnamemodify(root, ":t")
  end
  return nil
end

--- Build bufferline group entries for the given tab.
--- @param tab_id integer
--- @return table[] List of group definitions for bufferline
function M.build_groups(tab_id)
  local groups = {}

  -- Add the built-in pinned group
  local ok, bfgrps = pcall(require, "bufferline.groups")
  if ok then
    table.insert(groups, bfgrps.builtin.pinned:with({ icon = "" }))
  end

  if not vim.api.nvim_tabpage_is_valid(tab_id) then
    return groups
  end

  -- detect is used inside the matcher closure below to verify exact root
  -- matches, preventing parent projects from capturing nested project buffers.
  -- With Phase A caching, detect.get_root is O(1) on cache hit.
  local detect = require("projectab.detect")
  local seen_roots = {}
  local wins = vim.api.nvim_tabpage_list_wins(tab_id)

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.bo[bufnr].buftype == "" then
      -- Lazy require to avoid circular dependency
      local buffer = require("projectab.buffer")
      local root = buffer.resolve_project_root(bufnr)
      if root and not seen_roots[root] then
        seen_roots[root] = true

        -- Only register if this project isn't already assigned to a valid tab.
        if not state.get_tab(root) then
          state.register(root, tab_id)
        end

        local name = vim.fn.fnamemodify(root, ":t")
        table.insert(groups, {
          name = name,
          matcher = function(buf)
            local buf_path = vim.api.nvim_buf_get_name(buf.id)
            -- Quick prefix check first (O(1)), then verify exact root
            -- to prevent parent projects from capturing nested project buffers.
            if buf_path:find(root, 1, true) ~= 1 then
              return false
            end
            -- detect.get_root is O(1) on cache hit (Phase A caching).
            local buf_root = detect.get_root(buf_path)
            return buf_root == root
          end,
        })
      end
    end
  end

  return groups
end

--- Called on TabEnter to update bufferline groups.
--- Uses bufferline's internal API to set groups without re-calling setup().
--- @param tab_id integer
function M.on_tab_enter(tab_id)
  local groups = M.build_groups(tab_id)

  -- Update bufferline groups configuration
  local bl_ok, bufferline = pcall(require, "bufferline")
  if not bl_ok then
    return
  end

  -- Use bufferline's set_groups if available, otherwise fall back to setup
  local grp_ok, bl_groups = pcall(require, "bufferline.groups")
  if grp_ok and bl_groups.set_groups then
    bl_groups.set_groups(groups)
  else
    -- Fallback: re-setup with updated groups (not ideal but functional)
    bufferline.setup({
      options = {
        groups = {
          items = groups,
        },
      },
    })
  end

  log.debug_ctx(string.format("bufferline: updated groups for tab=%d (%d groups)", tab_id, #groups))
end

return M
