--- Tests for projectab.health module

local assert = require("luassert")
local config = require("projectab.config")

describe("projectab.health", function()
  local health

  before_each(function()
    config._reset()
    -- Ensure we get a fresh module just in case
    package.loaded["projectab.health"] = nil
    health = require("projectab.health")
  end)

  after_each(function()
    config._reset()
  end)

  it("exports a check function", function()
    assert.is_function(health.check)
  end)

  it("runs check() without error under default config", function()
    -- Mute stdout/stderr prints during the healthcheck run if we want,
    -- but since we run in headless tests, usually it's fine.
    assert.has_no.errors(function()
      health.check()
    end)
  end)

  it("runs check() without error when persistence is enabled", function()
    config.setup({
      project = {
        persistence = { enabled = true, dir = vim.fn.tempname() },
      },
    })
    assert.has_no.errors(function()
      health.check()
    end)
  end)

  it("runs check() without error when all integrations are enabled", function()
    config.setup({
      integrations = {
        project_nvim = true,
        bufferline = { enabled = true },
        snacks = { enabled = true },
      },
    })
    assert.has_no.errors(function()
      health.check()
    end)
  end)
end)
