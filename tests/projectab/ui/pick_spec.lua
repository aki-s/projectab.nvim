--- Tests for projectab.ui.pick module
---
--- These tests verify the pick_project function's behavior using stubbed
--- vim.ui.select and mocked dependencies.

local assert = require("luassert")
local config = require("projectab.config")
local state = require("projectab.state")

describe("projectab.ui.pick", function()
  local pick
  local real_vim_ui_select
  local select_calls

  before_each(function()
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
      integrations = {
        project_nvim = false,
        bufferline = false,
        snacks = { enabled = false },
      },
    })
    state._reset()

    -- Reload the pick module freshly (clear module cache)
    package.loaded["projectab.ui.pick"] = nil
    pick = require("projectab.ui.pick")

    -- Stub vim.ui.select to capture calls without showing UI
    select_calls = {}
    real_vim_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
      -- By default, do NOT invoke on_choice (simulates user cancellation)
    end
  end)

  after_each(function()
    vim.ui.select = real_vim_ui_select
    state._reset()
    config._reset()
    package.loaded["projectab.ui.pick"] = nil
  end)

  it("calling pick_project opens a vim.ui.select dialog", function()
    pick.project_pick()
    assert.are.equal(1, #select_calls)
    assert.are.equal("Projectab: Select project", select_calls[1].opts.prompt)
  end)

  it("includes known projects in the list", function()
    -- Create real tabs to use as valid tab handles
    local tab1 = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabfirst")

    state.register("/tmp/projectA", tab1)
    state.register("/tmp/projectB", tab2)

    pick.project_pick()

    local items = select_calls[1].items
    -- At minimum: 2 projects + "Open project using Projectab..." + "📂 Open directory..."
    assert.is_true(#items >= 4, "Expected at least 4 items, got " .. #items)

    -- Check that project labels are present
    local labels_str = table.concat(items, "|")
    assert.is_truthy(labels_str:find("projectA"))
    assert.is_truthy(labels_str:find("projectB"))

    -- Cleanup extra tab
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(tab2))
  end)

  it("includes '📂 Open directory...' option", function()
    pick.project_pick()
    local items = select_calls[1].items
    local found = false
    for _, label in ipairs(items) do
      if label:find("Open directory") then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected '📂 Open directory...' to be in items")
  end)

  it("does not include snacks option when snacks integration is disabled", function()
    pick.project_pick()
    local items = select_calls[1].items
    for _, label in ipairs(items) do
      assert.is_falsy(label:find("Snacks"), "Snacks option should not appear when disabled")
    end
  end)

  it("includes snacks option when snacks integration is enabled", function()
    config.setup({
      project = { root_markers = { ".git" }, excluded_root_dirs = {} },
      debug = { file = false, notify = false },
      integrations = {
        project_nvim = false,
        bufferline = false,
        snacks = { enabled = true, pickerProjectsOpts = {} },
      },
    })
    package.loaded["projectab.ui.pick"] = nil
    pick = require("projectab.ui.pick")

    pick.project_pick()
    local items = select_calls[1].items
    local found = false
    for _, label in ipairs(items) do
      if label:find("Snacks") then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected Snacks option when integration is enabled")
  end)

  it("cancelling the picker (nil choice) does not error", function()
    -- When user presses Escape, on_choice is called with nil
    vim.ui.select = function(items, opts, on_choice)
      on_choice(nil, nil)
    end

    -- Should not raise
    local ok = pcall(pick.project_pick)
    assert.is_true(ok)
  end)

  it("switching to an existing project tab calls nvim_set_current_tabpage", function()
    local tab1 = vim.api.nvim_get_current_tabpage()
    state.register("/tmp/projectA", tab1)
    local switched_to = nil
    local orig_set = vim.api.nvim_set_current_tabpage
    vim.api.nvim_set_current_tabpage = function(id)
      switched_to = id
    end

    vim.ui.select = function(items, opts, on_choice)
      -- Find the project A label
      for i, label in ipairs(items) do
        if label:find("projectA") then
          on_choice(label, i)
          return
        end
      end
    end

    pick.project_pick()

    vim.api.nvim_set_current_tabpage = orig_set
    assert.are.equal(tab1, switched_to)
  end)

  it("selecting 'Open directory...' invokes directory_picker_func via action()", function()
    local picker_called = false
    config.values.project.directory_picker_func = function(_opts, _cb)
      picker_called = true
    end

    vim.ui.select = function(items, _opts, on_choice)
      for i, label in ipairs(items) do
        if label:find("Open directory") then
          on_choice(label, i)
          return
        end
      end
    end

    pick.project_pick()
    assert.is_true(picker_called, "Expected directory_picker_func to be invoked for 'dir' action")
  end)

  it("all items have expected label patterns for default config", function()
    pick.project_pick()
    local items = select_calls[1].items

    -- With no projects and default config (snacks disabled), expect:
    -- 1. "🕒 Open project using Projectab..."
    -- 2. "📂 Open directory..."
    -- (plus any history entries from persistence, which may be 0)
    assert.is_true(#items >= 2, "Expected at least 2 items, got " .. #items)

    local has_history_picker = false
    local has_dir = false
    for _, label in ipairs(items) do
      if label:find("Open project using Projectab") then
        has_history_picker = true
      end
      if label:find("Open directory") then
        has_dir = true
      end
    end
    assert.is_true(has_history_picker, "Expected history picker item")
    assert.is_true(has_dir, "Expected directory item")
  end)

  it("includes extra items from opts.actions", function()
    local custom_action_called = false
    local opts = {
      actions = {
        function()
          return {
            label = "⭐ Custom Action",
            action = function()
              custom_action_called = true
            end,
            type = "custom",
          }
        end,
      },
    }

    vim.ui.select = function(items, _opts, on_choice)
      for i, label in ipairs(items) do
        if label:find("Custom Action") then
          on_choice(label, i)
          return
        end
      end
    end

    pick.project_pick(opts)
    assert.is_true(custom_action_called, "Expected custom action to be called")
  end)
end)
