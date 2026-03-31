--- Project-specific buffer navigation module for projectab.nvim
--- Implements :bnext and :bprev constrained to buffers belonging to the current project.
--- @class ProjectabNavigateModule
local M = {}

local state = require("projectab.state")
local buffer = require("projectab.buffer")

--- Get sorted list of valid, listed buffers belonging to the given project root.
--- @param project_root string The project root path
--- @return integer[] List of buffer numbers
local function get_project_buffers(project_root)
  local bufs = {}
  local all_bufs = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(all_bufs) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.bo[bufnr].buflisted
      and vim.bo[bufnr].buftype == ""
      and vim.api.nvim_buf_get_name(bufnr) ~= ""
    then
      local buf_project = buffer.resolve_project_root(bufnr)
      if buf_project == project_root then
        table.insert(bufs, bufnr)
      end
    end
  end

  -- Sort so order is consistent across sequential calls
  table.sort(bufs)
  return bufs
end

--- Find the index of an item in a list.
--- @param list any[]
--- @param item any
--- @return integer|nil Index if found, nil otherwise
local function index_of(list, item)
  for i, val in ipairs(list) do
    if val == item then
      return i
    end
  end
  return nil
end

--- Navigate to the next buffer within the current project tab.
function M.project_bnext()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local project_root = state.get_project(current_tab)

  if not project_root then
    vim.notify("[ProjecTab] Current tab has no assigned project", vim.log.levels.WARN)
    return
  end

  local bufs = get_project_buffers(project_root)
  if #bufs <= 1 then
    -- Nothing to cycle to (already at only buffer, or empty)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_idx = index_of(bufs, current_buf)

  -- If current buffer is not in list (e.g. an unlisted or empty buffer), start from 1
  if not current_idx then
    vim.cmd("buffer " .. bufs[1])
    return
  end

  local next_idx = current_idx + 1
  if next_idx > #bufs then
    next_idx = 1
  end

  vim.cmd("buffer " .. bufs[next_idx])
end

--- Navigate to the previous buffer within the current project tab.
function M.project_bprevious()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local project_root = state.get_project(current_tab)

  if not project_root then
    vim.notify("[ProjecTab] Current tab has no assigned project", vim.log.levels.WARN)
    return
  end

  local bufs = get_project_buffers(project_root)
  if #bufs <= 1 then
    -- Nothing to cycle to
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_idx = index_of(bufs, current_buf)

  -- If current buffer is not in list, fallback to the last valid project buffer
  if not current_idx then
    vim.cmd("buffer " .. bufs[#bufs])
    return
  end

  local prev_idx = current_idx - 1
  if prev_idx < 1 then
    prev_idx = #bufs
  end

  vim.cmd("buffer " .. bufs[prev_idx])
end

return M
