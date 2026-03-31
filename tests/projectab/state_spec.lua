--- Tests for projectab.state module
---
--- These are pure state-management tests. They verify the bidirectional map
--- (project_to_tab ↔ tab_to_project) invariants, stale entry cleanup, and
--- scan_existing_tabs behaviour.

local assert = require("luassert")
local config = require("projectab.config")
local state = require("projectab.state")

describe("projectab.state", function()
  before_each(function()
    config.setup({ debug = { file = false, notify = false } })
    state._reset()
  end)

  after_each(function()
    state._reset()
  end)

  it("registers and gets state correctly", function()
    -- Basic round-trip: register a project→tab and verify both directions.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    state.register("/home/user/projectA", tab1)

    assert.are.equal(tab1, state.get_tab("/home/user/projectA"))
    assert.are.equal("/home/user/projectA", state.get_project(tab1))
  end)

  it("unregister_tab handles bidirectional cleanup", function()
    -- After unregistering, both directions must return nil.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    state.register("/home/user/projectA", tab1)
    state.unregister_tab(tab1)

    assert.is_nil(state.get_tab("/home/user/projectA"))
    assert.is_nil(state.get_project(tab1))
  end)

  it("get_tab auto-cleans stale tab handle", function()
    -- If a tab handle becomes invalid (tab was closed externally),
    -- get_tab should detect this and clean up the stale mapping automatically.
    local fake_tab = 999999 -- Guaranteed to not be a real tab handle

    state.register("/home/user/stale", fake_tab)

    -- get_tab should detect the invalid tab and return nil
    local result = state.get_tab("/home/user/stale")
    assert.is_nil(result)

    -- The stale entry should be cleaned up on both sides
    assert.is_nil(state.get_project(fake_tab))
  end)

  it("handles multiple projects", function()
    -- Two projects should coexist independently. Unregistering one must not
    -- affect the other.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()

    state.register("/home/user/projectA", tab1)
    state.register("/home/user/projectB", tab2)

    assert.are.equal(tab1, state.get_tab("/home/user/projectA"))
    assert.are.equal(tab2, state.get_tab("/home/user/projectB"))
    assert.are.equal("/home/user/projectA", state.get_project(tab1))
    assert.are.equal("/home/user/projectB", state.get_project(tab2))

    state.unregister_tab(tab1)
    assert.is_nil(state.get_tab("/home/user/projectA"))
    assert.are.equal(tab2, state.get_tab("/home/user/projectB"))

    vim.cmd("tabclose")
  end)

  it("cleanup removes only invalid tabs", function()
    -- cleanup() is called on TabClosed. It should only remove entries for tabs
    -- that no longer exist, leaving valid entries intact.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    state.register("/home/user/valid", tab1)
    state.register("/home/user/invalid", 999998)

    state.cleanup()

    assert.are.equal(tab1, state.get_tab("/home/user/valid"))
    assert.is_nil(state.get_project(999998))
  end)

  it("_reset clears all state", function()
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    state.register("/home/user/project", tab1)
    state._reset()

    local s = state._get_state()
    assert.is_nil(next(s.project_to_tab))
    assert.is_nil(next(s.tab_to_project))
  end)

  it("register evicts stale project when re-registering a tab", function()
    -- If a tab was associated with project A, and we register the same tab
    -- to project B, the old project A mapping must be removed.
    -- This tests the 1-to-1 invariant enforcement.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    state.register("/project/A", tab1)
    state.register("/project/B", tab1)

    assert.is_nil(state.get_tab("/project/A"))
    assert.are.equal(tab1, state.get_tab("/project/B"))
    assert.are.equal("/project/B", state.get_project(tab1))
  end)

  it("register evicts stale tab when re-registering a project", function()
    -- If project A was associated with tab 1, and we register project A
    -- to a new tab 2, the old tab 1 mapping must be removed.
    local tabs = vim.api.nvim_list_tabpages()
    local tab1 = tabs[1]

    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()

    state.register("/project/A", tab1)
    state.register("/project/A", tab2)

    assert.are.equal(tab2, state.get_tab("/project/A"))
    assert.is_nil(state.get_project(tab1))
    assert.are.equal("/project/A", state.get_project(tab2))

    vim.cmd("tabclose")
  end)
end)
