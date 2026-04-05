--- @class ProjectabUiPickModule
local M = {}

--- @class PickAction
--- @field action fun(self: PickAction) Callback invoked when this item is selected
--- @field label string Display string for vim.ui.select
--- @field root string|nil Project root path (nil for meta-items)
--- @field tab_id integer|nil Tab handle (only for already-open projects)
--- @field type string Category: "tab" | "hist_projectab" | "hist_entry" | "integ_snacks" | "dir"

--- Build a PickAction for an already-open project tab.
--- @param root string
--- @param tab_id integer
--- @return PickAction
local function _make_tab_item(root, tab_id)
  local log = require("projectab.log")
  local name = vim.fn.fnamemodify(root, ":t")
  return {
    label = string.format("%s  (%s)", name, root),
    root = root,
    tab_id = tab_id,
    type = "tab",
    action = function(self)
      vim.api.nvim_set_current_tabpage(self.tab_id)
      log.debug_ctx(string.format("pick_project: switched to tab=%d for root=%s", self.tab_id, self.root))
    end,
  }
end

--- Build a PickAction for the 2-stage Projectab history picker.
--- @return PickAction
local function _make_history_pick_item()
  local session = require("projectab.session")
  local notify = require("projectab.ui.notify")
  return {
    label = "🕒 Open project using Projectab...",
    root = nil,
    tab_id = nil,
    type = "hist_projectab",
    action = function(_self)
      local hist = session.list_history({ limit = 50 })
      if not hist or #hist == 0 then
        notify("No project history found", vim.log.levels.INFO)
        return
      end

      local hist_items = {}
      local hist_labels = {}
      for _, root in ipairs(hist) do
        local name = vim.fn.fnamemodify(root, ":t")
        local hist_label = string.format("%s  (%s)", name, root)
        table.insert(hist_items, { label = hist_label, root = root })
        table.insert(hist_labels, hist_label)
      end

      vim.ui.select(hist_labels, { prompt = "Projectab: Recent projects" }, function(h_choice, h_idx)
        if h_choice and h_idx then
          session.project_restore(hist_items[h_idx].root)
        end
      end)
    end,
  }
end

--- Build a PickAction for the snacks.nvim project picker.
--- @return PickAction
local function _make_snacks_item()
  local config = require("projectab.config")
  local session = require("projectab.session")
  local notify = require("projectab.ui.notify")
  return {
    label = "🍿 Open project using Snacks...",
    root = nil,
    tab_id = nil,
    type = "integ_snacks",
    action = function(_self)
      local ok, snacks_int = pcall(require, "projectab.integrations.snacks")
      ---@cast snacks_int ProjectabSnacksIntegration
      if ok then
        snacks_int.pick_new_project(session.project_open, config.values.integrations.snacks.pickerProjectsOpts)
      else
        notify("Failed to load snacks integration", vim.log.levels.ERROR)
      end
    end,
  }
end

--- Build a PickAction for the "Open directory..." prompt.
--- @return PickAction
local function _make_dir_item()
  local config = require("projectab.config")
  local session = require("projectab.session")
  return {
    label = "📂 Open directory...",
    root = nil,
    tab_id = nil,
    type = "dir",
    action = function(_self)
      config.values.project.directory_picker_func(
        { prompt = "Project directory: ", completion = "dir" },
        function(input)
          if input and input ~= "" then
            session.project_open(input)
          end
        end
      )
    end,
  }
end

--- Build a PickAction for a history entry (single-step selection).
--- @param root string
--- @return PickAction
local function _make_history_entry_item(root)
  local log = require("projectab.log")
  local session = require("projectab.session")
  local name = vim.fn.fnamemodify(root, ":t")
  return {
    label = string.format("🕒 %s  (%s)", name, root),
    root = root,
    tab_id = nil,
    type = "hist_entry",
    action = function(self)
      log.debug_ctx(string.format("pick_project: restore history entry root=%s", self.root))
      session.project_restore(self.root)
    end,
  }
end

--- Build a default PickActions
---
-- @return PickAction[]
local function _defaultPickerActions()
  local items = {}
  local config = require("projectab.config")
  local state = require("projectab.state")
  local session = require("projectab.session")
  local projects = state.list_projects()

  for root, tab_id in pairs(projects) do
    table.insert(items, _make_tab_item(root, tab_id))
  end
  table.sort(items, function(a, b)
    return a.label < b.label
  end)

  table.insert(items, _make_history_pick_item())

  if config.values.integrations.snacks.enabled then
    table.insert(items, _make_snacks_item())
  end

  table.insert(items, _make_dir_item())

  -- Append history entries directly below "📂 Open directory..."
  local history = session.list_history({ limit = 50 })
  for _, root in ipairs(history) do
    if not projects[root] then
      table.insert(items, _make_history_entry_item(root))
    end
  end
  return items
end

--- @class ProjectabPickOptions
--- @field actions? (fun(): PickAction)[]

--- Open a picker to select a project
---
--- @param opts? ProjectabPickOptions
function M.project_pick(opts)
  opts = opts or {}
  -- Build sorted list of known project entries
  --- @type PickAction[]
  local items = {}

  if opts.actions and #opts.actions > 0 then
    -- Add extra items provided via opts
    for _, action_fn in ipairs(opts.actions or {}) do
      table.insert(items, action_fn())
    end
  else
    items = _defaultPickerActions()
  end

  -- Build labels for vim.ui.select
  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, { prompt = "Projectab: Select project" }, function(choice, idx)
    if not choice or not idx then
      return
    end
    items[idx]:action()
  end)
end

return M
