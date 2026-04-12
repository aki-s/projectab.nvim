--- @class ProjectabUiDashboardModule
local M = {}

local config = require("projectab.config")
local pick = require("projectab.ui.pick")
local state = require("projectab.state")

--- Open the standalone projectab dashboard.
--- Replaces the current window's buffer with a new dashboard buffer.
function M.open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "projectab_dashboard"

  -- Collect projects
  local session = require("projectab.session")
  local items = {}
  for _, root in ipairs(session.list()) do
    table.insert(items, {
      name = vim.fn.fnamemodify(root, ":t"),
      root = root,
      tab_id = state.get_tab(root),
    })
  end

  local lines = {}
  local keymaps = {}

  -- Add header
  table.insert(lines, "")
  if config.values.ui.dashboard.header then
    for _, line in ipairs(config.values.ui.dashboard.header) do
      table.insert(lines, "  " .. line)
    end
    if #config.values.ui.dashboard.header > 0 then
      table.insert(lines, "")
      table.insert(lines, "")
    end
  end

  table.insert(lines, "  Projects:")
  for i, item in ipairs(items) do
    if i <= 9 then
      local key = tostring(i)
      table.insert(lines, string.format("    [%s] %s  (%s)", key, item.name, item.root))
      keymaps[key] = function()
        if item.tab_id then
          vim.api.nvim_set_current_tabpage(item.tab_id)
        else
          session.project_restore(item.root)
        end
      end
    end
  end

  if #items == 0 then
    table.insert(lines, "    (No active projects)")
  end

  table.insert(lines, "")
  table.insert(lines, "  Commands:")

  table.insert(lines, "    [R] Restore projects")
  keymaps["R"] = function()
    local session = require("projectab.session")
    local sessions = session.list({ limit = 10 })

    local dirs = {}
    for _, root in ipairs(sessions) do
      table.insert(dirs, root)
    end

    local ret = {}
    for _, dir in ipairs(dirs) do
      session.project_restore(dir)
    end
  end

  table.insert(lines, "    [p] Pick Project")
  keymaps["p"] = pick.project_pick

  table.insert(lines, "    [n] New empty tab")
  keymaps["n"] = function()
    vim.cmd("tabnew")
  end

  table.insert(lines, "    [q] Quit Neovim")
  keymaps["q"] = function()
    vim.cmd("qa")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].colorcolumn = ""

  -- Setup keymaps
  for key, fn in pairs(keymaps) do
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end
end

return M
