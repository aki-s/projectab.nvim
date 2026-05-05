--- Tests for projectab.cleanup module
local assert = require("luassert")
local config = require("projectab.config")
local state = require("projectab.state")
local cleanup = require("projectab.cleanup")

describe("projectab.cleanup", function()
  before_each(function()
    config.setup({
      debug = { file = false, notify = false },
      project = {
        persistence = {
          dir = vim.fn.tempname(),
        },
      },
    })
    state._reset()
  end)

  after_each(function()
    state._reset()
    -- Close all extra tabs
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose!")
    end
  end)

  it("close_empty_tabs closes tabs with only unnamed buffers", function()
    -- Ensure the first tab has content so it won't be closed
    local first_tab = vim.api.nvim_list_tabpages()[1]
    vim.api.nvim_set_current_tabpage(first_tab)
    local tmpfile = vim.fn.tempname()
    vim.fn.writefile({ "test" }, tmpfile)
    vim.cmd("edit " .. vim.fn.fnameescape(tmpfile))
    state.register("/home/user/projectFirst", first_tab)

    -- Create a new tab with explicitly unnamed buffer
    vim.cmd("tabnew")
    vim.cmd("enew!") -- Ensure unnamed buffer
    local empty_tab = vim.api.nvim_get_current_tabpage()
    state.register("/home/user/projectA", empty_tab)

    -- Verify we have 2 tabs now
    local tabs_before = vim.api.nvim_list_tabpages()
    assert.equals(2, #tabs_before)

    -- The empty tab only has an unnamed buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    assert.equals("", bufname, "Expected unnamed buffer but got: " .. bufname)
    assert.is_false(vim.bo[bufnr].modified, "Buffer should not be modified")

    -- Run cleanup
    local count = cleanup.projects_close_empty_tab()

    -- Should have closed 1 tab
    assert.equals(1, count, "Expected to close 1 tab")

    -- Verify tab was actually closed
    local tabs_after = vim.api.nvim_list_tabpages()
    assert.equals(1, #tabs_after, "Expected 1 tab remaining but got " .. #tabs_after)
    assert.is_false(vim.api.nvim_tabpage_is_valid(empty_tab))
    assert.is_nil(state.get_project(empty_tab))

    -- Cleanup
    vim.fn.delete(tmpfile)
  end)

  it("close_empty_tabs preserves tabs with named buffers", function()
    -- Create a temp file
    local tmpfile = vim.fn.tempname()
    vim.fn.writefile({ "test" }, tmpfile)

    -- Create a new tab with a named buffer
    vim.cmd("tabnew " .. vim.fn.fnameescape(tmpfile))
    local tab_with_file = vim.api.nvim_get_current_tabpage()
    state.register("/home/user/projectB", tab_with_file)

    -- Run cleanup
    local count = cleanup.projects_close_empty_tab()

    -- Should not have closed any tabs
    assert.equals(0, count)
    assert.is_true(vim.api.nvim_tabpage_is_valid(tab_with_file))
    assert.equals("/home/user/projectB", state.get_project(tab_with_file))

    -- Cleanup
    vim.fn.delete(tmpfile)
  end)

  it("close_empty_tabs preserves tabs with modified buffers", function()
    -- Create a new tab with an unnamed but modified buffer
    vim.cmd("tabnew")
    local modified_tab = vim.api.nvim_get_current_tabpage()
    state.register("/home/user/projectC", modified_tab)

    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals("", vim.api.nvim_buf_get_name(bufnr))

    -- Modify the buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "some content" })
    assert.is_true(vim.bo[bufnr].modified)

    -- Run cleanup
    local count = cleanup.projects_close_empty_tab()

    -- Should not have closed the modified tab
    assert.equals(0, count)
    assert.is_true(vim.api.nvim_tabpage_is_valid(modified_tab))
    assert.equals("/home/user/projectC", state.get_project(modified_tab))
  end)

  it("close_empty_tabs never closes the last tab", function()
    -- Close all tabs except one
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose!")
    end

    -- Only one tab exists (the default one)
    local tabs = vim.api.nvim_list_tabpages()
    assert.equals(1, #tabs)

    local only_tab = tabs[1]
    state.register("/home/user/projectD", only_tab)

    -- Ensure the tab only has an unnamed buffer
    vim.cmd("enew!")
    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    assert.equals("", bufname, "Buffer should be unnamed but got: " .. bufname)

    -- Run cleanup
    local count = cleanup.projects_close_empty_tab()

    -- Should not have closed any tabs (last tab protection)
    assert.equals(0, count)
    assert.is_true(vim.api.nvim_tabpage_is_valid(only_tab))
  end)

  describe("close_project", function()
    it("closes the tab and unregisters the project", function()
      -- Close all tabs except one
      while #vim.api.nvim_list_tabpages() > 1 do
        pcall(vim.cmd, "tabclose!")
      end

      -- Create a new tab
      vim.cmd("tabnew")
      local new_tab = vim.api.nvim_get_current_tabpage()
      state.register("/home/user/project_to_close", new_tab)

      -- Create a buffer for this project so `_tab_buffers` gets populated
      local tmpfile = vim.fn.tempname()
      vim.fn.writefile({ "test data" }, tmpfile)
      vim.cmd("edit " .. vim.fn.fnameescape(tmpfile))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Ensure the plugin knows about the buffer
      local buffer_module = require("projectab.buffer")
      buffer_module.handle_buf_enter(bufnr)

      -- Verify setup
      assert.equals(2, #vim.api.nvim_list_tabpages())
      assert.equals("/home/user/project_to_close", state.get_project(new_tab))
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

      -- Run close_project
      cleanup.project_close(new_tab)

      cleanup.on_tab_closed(new_tab)

      -- Verify tab is closed and state is cleared
      assert.is_false(vim.api.nvim_tabpage_is_valid(new_tab))
      assert.is_nil(state.get_project(new_tab))

      -- Cleanup
      vim.fn.delete(tmpfile)
    end)

    it("preserves unsaved buffers during cleanup", function()
      vim.cmd("tabnew")
      local new_tab = vim.api.nvim_get_current_tabpage()
      state.register("/home/user/project_unsaved", new_tab)

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)

      -- Mark buffer modified
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified content" })
      assert.is_true(vim.bo[bufnr].modified)

      local buffer_module = require("projectab.buffer")
      buffer_module.handle_buf_enter(bufnr)

      -- Run on_tab_closed directly to bypass tabclose stopping us
      cleanup.on_tab_closed(new_tab)

      -- Verify state is cleared but buffer is PRESERVED because it's modified
      assert.is_nil(state.get_project(new_tab))
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

      -- Cleanup manually
      vim.api.nvim_buf_delete(bufnr, { force = true })
      pcall(vim.cmd, "tabclose!")
    end)
  end)
end)
