local assert = require("luassert")
local dashboard = require("projectab.ui.dashboard")
local session = require("projectab.session")
local config = require("projectab.config")
local state = require("projectab.state")

describe("projectab.ui.dashboard", function()
  before_each(function()
    config._reset()
    state._reset()
  end)

  it("open creates a nofile buffer with keymaps", function()
    local original_list_history = session.list_history
    session.list_history = function()
      return { "/tmp/my_fake_project" }
    end

    config.values.ui.dashboard.header = { "TEST_HEADER" }

    dashboard.open()

    local buf = vim.api.nvim_get_current_buf()
    assert.equals("projectab_dashboard", vim.bo[buf].filetype)
    assert.equals("nofile", vim.bo[buf].buftype)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local found_header = false
    local found_project = false
    for _, line in ipairs(lines) do
      if line:match("TEST_HEADER") then
        found_header = true
      end
      if line:match("my_fake_project") then
        found_project = true
      end
    end
    assert.is_true(found_header, "Header should be drawn")
    assert.is_true(found_project, "Project should be drawn")

    -- Clean up
    vim.api.nvim_buf_delete(buf, { force = true })
    session.list_history = original_list_history
  end)

  it("handles empty project history gracefully", function()
    local original_list_history = session.list_history
    session.list_history = function()
      return {}
    end

    dashboard.open()

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local found_empty_msg = false
    for _, line in ipairs(lines) do
      if line:match("(No active projects)") then
        found_empty_msg = true
      end
    end
    assert.is_true(found_empty_msg, "Should show empty projects message")

    vim.api.nvim_buf_delete(buf, { force = true })
    session.list_history = original_list_history
  end)
end)
