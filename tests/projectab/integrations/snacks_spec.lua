local assert = require("luassert")
local snacks_integration = require("projectab.integrations.snacks")
local session = require("projectab.session")

describe("projectab.integrations.snacks", function()
  it("dashboard_section generates correctly formatted snacks section", function()
    local original_list_history = session.list_history
    session.list_history = function()
      return { "/tmp/my_dashboard_project", "/tmp/another_project" }
    end

    local generator = snacks_integration.dashboard_section({ limit = 10 })
    assert.is_function(generator, "Should return a generator function")

    local items = generator()
    assert.equals(2, #items, "Should generate items based on history")
    assert.equals("/tmp/my_dashboard_project", items[1].file)
    assert.equals("/tmp/another_project", items[2].file)
    assert.is_function(items[1].action, "Item should have an action callback")

    session.list_history = original_list_history
  end)

  it("dashboard_section respects the limit parameter", function()
    local original_list_history = session.list_history
    session.list_history = function()
      return { "/tmp/project1", "/tmp/project2", "/tmp/project3" }
    end

    local generator = snacks_integration.dashboard_section({ limit = 2 })
    local items = generator()

    assert.equals(2, #items, "Should respect the limit")

    session.list_history = original_list_history
  end)
end)
