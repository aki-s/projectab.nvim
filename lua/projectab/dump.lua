--- Dump module for projectab.nvim.
---
--- DESIGN: This module is intentionally one-directional.
---   Other modules MUST NOT require("projectab.dump").
---   dump.lua only reads from: config, state, detect, buffer.
---   This prevents cyclic dependencies and keeps the module a
---   pure "observer" of the plugin state.
---
--- @class ProjectabDumpModule
local M = {}

--- Collect the buffer flag string similar to :ls output.
--- Returns a short flag like "%a", "#h", " h", " u", "  " etc.
--- @param bufnr integer
--- @param current_bufnr integer The current buffer number
--- @param alt_bufnr integer The alternate buffer number
--- @return string
local function __buf_flags(bufnr, current_bufnr, alt_bufnr)
  local active = (bufnr == current_bufnr) and "%" or (bufnr == alt_bufnr and "#" or " ")
  local loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local listed = vim.bo[bufnr].buflisted
  local modified = vim.bo[bufnr].modified

  local state_flag
  if not listed then
    state_flag = "u" -- unlisted
  elseif not loaded then
    state_flag = " " -- unloaded (not in memory)
  else
    -- loaded & listed
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      state_flag = "a" -- active (visible in a window)
    else
      state_flag = "h" -- hidden
    end
  end

  local mod_flag = modified and "+" or " "
  return active .. state_flag .. mod_flag
end

--- Collect Neovim tab/window/buffer state as a string.
--- @param state_snap ProjectabState
--- @return string
local function __collect_nvim_state(state_snap)
  local lines = {}
  local current_bufnr = vim.api.nvim_get_current_buf()
  local alt_bufnr = vim.fn.bufnr("#")

  for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_nr = vim.api.nvim_tabpage_get_number(tab_id)
    local has_tcd = vim.fn.haslocaldir(-1, tab_nr) == 1
    local tcd = has_tcd and vim.fs.normalize(vim.fn.getcwd(-1, tab_nr)) or "(none)"
    local proj = state_snap.tab_to_project[tab_id] or "(unregistered)"
    local current_marker = (tab_id == vim.api.nvim_get_current_tabpage()) and " *" or ""

    table.insert(
      lines,
      string.format(
        "tab%d (tabpage_id=%d%s)  tcd=%s  [projectab_project=%s]",
        tab_nr,
        tab_id,
        current_marker,
        tcd,
        proj
      )
    )

    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(tab_id)) do
      local win_nr = vim.api.nvim_win_get_number(win_id)
      local is_current_win = (win_id == vim.api.nvim_get_current_win()) and " *" or ""
      table.insert(lines, string.format("  win%d (win_id=%d%s)", win_nr, win_id, is_current_win))

      -- All buffers "visible" in this window context: show the window's buffer plus
      -- the cached _tab_buffers list (hidden/unlisted ones included).
      local win_buf = vim.api.nvim_win_get_buf(win_id)
      local seen = {}

      local function add_buf(bufnr)
        if seen[bufnr] then
          return
        end
        seen[bufnr] = true
        local flags = __buf_flags(bufnr, current_bufnr, alt_bufnr)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == "" then
          name = "[No Name]"
        end
        local buftype = vim.bo[bufnr].buftype
        local bt_str = (buftype ~= "") and (" buftype=" .. buftype) or ""
        table.insert(lines, string.format("    buf%-4d  [%s]  %s%s", bufnr, flags, name, bt_str))
      end

      add_buf(win_buf)
    end
  end

  -- All buffers section: show every buffer Neovim knows about
  table.insert(lines, "")
  table.insert(lines, "-- all buffers (vim.api.nvim_list_bufs) --")
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local flags = __buf_flags(bufnr, current_bufnr, alt_bufnr)
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "" then
        name = "[No Name]"
      end
      local buftype = vim.bo[bufnr].buftype
      local listed = vim.bo[bufnr].buflisted
      local bt_str = (buftype ~= "") and (" buftype=" .. buftype) or ""
      local listed_str = listed and " listed" or " unlisted"
      table.insert(lines, string.format("  buf%-4d  [%s]%s%s  %s", bufnr, flags, listed_str, bt_str, name))
    end
  end

  return table.concat(lines, "\n")
end

--- Dump the current internal state of projectab to a file.
--- Writes to stdpath("cache")/projectab_dump.txt and notifies the path.
--- @return string output_path Path of the written file
function M.dump()
  local config = require("projectab.config")
  local state = require("projectab.state")
  local detect = require("projectab.detect")
  local buffer = require("projectab.buffer")

  local state_snap = state._get_state()

  local sections = {
    "=== projectab internal state dump ===",
    "generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "",
    "=== config.values ===",
    vim.inspect(config.values),
    "",
    "=== state.project_to_tab ===",
    vim.inspect(state_snap.project_to_tab),
    "",
    "=== state.tab_to_project ===",
    vim.inspect(state_snap.tab_to_project),
    "",
    "=== detect.root_cache ===",
    vim.inspect(detect._get_root_cache()),
    "",
    "=== buffer._tab_buffers ===",
    vim.inspect(buffer._get_tab_buffers()),
    "",
    "=== nvim tab/window/buffer state ===",
    __collect_nvim_state(state_snap),
    "",
  }

  local output = table.concat(sections, "\n")

  local cache_dir = vim.fn.stdpath("cache")
  local output_path = cache_dir .. "/projectab_dump.txt"

  local f, err = io.open(output_path, "w")
  if not f then
    vim.notify("[projectab] dump failed: " .. tostring(err), vim.log.levels.ERROR)
    return output_path
  end
  f:write(output)
  f:close()

  vim.notify("[projectab] state dumped to: " .. output_path, vim.log.levels.INFO)
  return output_path
end

return M
