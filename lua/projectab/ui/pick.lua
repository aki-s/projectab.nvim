--- @class ProjectabUiPickModule
local M = {}

--- Open a picker to select a known project or enter a new directory.
--- Uses vim.ui.select (works in TUI and GUI).
--- When "New project..." is selected, delegates to the snacks integration
--- (if enabled) or falls back to vim.ui.input.
function M.project_pick()
  local config = require("projectab.config")
  local state = require("projectab.state")
  local log = require("projectab.log")
  local notify = require("projectab.ui.notify")

  local projects = state.list_projects()

  -- Build sorted list of known project entries
  local items = {}
  for root, tab_id in pairs(projects) do
    local name = vim.fn.fnamemodify(root, ":t")
    table.insert(items, {
      label = string.format("%s  (%s)", name, root),
      root = root,
      tab_id = tab_id,
      is_new = false,
    })
  end
  table.sort(items, function(a, b)
    return a.label < b.label
  end)

  table.insert(items, {
    label = "🕒 Open project using ProjecTab...",
    is_history = true,
  })

  if config.values.integrations.snacks.enabled then
    table.insert(items, {
      label = "🍿 Open project using Snacks...",
      is_snacks = true,
    })
  end

  table.insert(items, {
    label = "📂 Open directory...",
    is_new = true,
  })

  -- Build labels for vim.ui.select
  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, { prompt = "ProjecTab: Select project" }, function(choice, idx)
    if not choice or not idx then
      return
    end
    local session = require("projectab.session")

    local selected = items[idx]
    if selected.is_new then
      -- Prompt for a directory path
      config.values.project.directory_picker_func(
        { prompt = "Project directory: ", completion = "dir" },
        function(input)
          if input and input ~= "" then
            session.project_open(input)
          end
        end
      )
    elseif selected.is_history then
      local history = require("projectab.session").list_history()
      if not history or #history == 0 then
        notify("No project history found", vim.log.levels.INFO)
        return
      end

      local hist_items = {}
      local hist_labels = {}
      for _, root in ipairs(history) do
        local name = vim.fn.fnamemodify(root, ":t")
        local hist_label = string.format("%s  (%s)", name, root)
        table.insert(hist_items, { label = hist_label, root = root })
        table.insert(hist_labels, hist_label)
      end

      vim.ui.select(hist_labels, { prompt = "ProjecTab: Recent projects" }, function(h_choice, h_idx)
        if h_choice and h_idx then
          session.project_restore(hist_items[h_idx].root)
        end
      end)
    elseif selected.is_snacks then
      local ok, snacks_int = pcall(require, "projectab.integrations.snacks")
      ---@cast snacks_int ProjectabSnacksIntegration
      if ok then
        snacks_int.pick_new_project(session.project_open, config.values.integrations.snacks.pickerProjectsOpts)
      else
        notify("Failed to load snacks integration", vim.log.levels.ERROR)
      end
    else
      -- Switch to existing project tab
      vim.api.nvim_set_current_tabpage(selected.tab_id)
      log.debug_ctx(string.format("pick_project: switched to tab=%d for root=%s", selected.tab_id, selected.root))
    end
  end)
end

return M
