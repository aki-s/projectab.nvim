--- @class ProjectabUiTablineModule
local M = {}

--- Renders the custom tabline.
--- Display format per tab: `[TabNumber] ProjectName (or filename)`
--- Evaluated frequently by Neovim.
--- @return string
function M.render()
  local s = ""
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tabs = vim.api.nvim_list_tabpages()

  -- state module lookup is O(1)
  local state = require("projectab.state")

  for i, tab_id in ipairs(tabs) do
    -- Set highlighting: TabLineSel for active, TabLine for inactive.
    if tab_id == current_tab then
      s = s .. "%#TabLineSel#"
    else
      s = s .. "%#TabLine#"
    end

    -- Set click target for mouse handling (%n is tab index)
    s = s .. "%" .. i .. "T"

    -- Get label text
    local label = ""
    local root = state.get_project(tab_id)

    if root then
      label = vim.fn.fnamemodify(root, ":t")
    else
      -- Fallback: If no project is assigned, get the name of the active buffer in that tab
      local win = vim.api.nvim_tabpage_get_win(tab_id)
      local buf = vim.api.nvim_win_get_buf(win)
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name ~= "" then
        label = vim.fn.fnamemodify(buf_name, ":t")
      else
        label = "[No Name]"
      end
    end

    -- Add some padding and format
    s = s .. " " .. i .. ":" .. label .. " "
  end

  -- Fill the rest of the line and reset mouse click targets
  s = s .. "%#TabLineFill#%T"

  return s
end

return M
