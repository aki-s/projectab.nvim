--- Tests for projectab config module.
---
local assert = require("luassert")
local config = require("projectab.config")

describe("projectab config.lua", function()
  before_each(function()
    require("projectab.state")._reset()
    config._reset()
  end)

  after_each(function()
    require("projectab.state")._reset()
    config._reset()
  end)

  it("has correct default values", function()
    local c = config.values

    -- UI
    assert.is_false(c.ui.dashboard.enabled)
    assert.are.same({ "Projectab" }, c.ui.dashboard.header)

    -- Project
    assert.is_true(#c.project.root_markers > 0)
    assert.are.same({}, c.project.excluded_root_dirs)
    assert.is_true(c.project.persistence.enabled)
    assert.is_nil(c.project.persistence.dir)

    -- Debug
    assert.is_false(c.debug.file)
    assert.is_false(c.debug.notify)

    -- Integrations
    assert.is_false(c.integrations.project_nvim)
    assert.is_false(c.integrations.bufferline.enabled)
    assert.is_false(c.integrations.snacks.enabled)
    assert.are.same({}, c.integrations.snacks.pickerProjectsOpts)
  end)

  it("can override all config options via setup", function()
    local custom_opts = {
      ui = {
        dashboard = {
          enabled = true,
          header = { "Custom Header 1", "Custom Header 2" },
        },
      },
      project = {
        root_markers = { ".custom_marker" },
        excluded_root_dirs = { "/tmp/exclude" },
        persistence = {
          enabled = false,
          dir = "/tmp/projectab_data",
        },
      },
      debug = {
        file = true,
        notify = true,
      },
      integrations = {
        project_nvim = true,
        bufferline = {
          enabled = true,
        },
        snacks = {
          enabled = true,
          pickerProjectsOpts = { recent = true, max_depth = 5, dev = { "~/src" } },
        },
      },
    }

    config.setup(custom_opts)
    local c = config.values

    -- UI
    assert.is_true(c.ui.dashboard.enabled)
    assert.are.same(custom_opts.ui.dashboard.header, c.ui.dashboard.header)

    -- Project
    assert.are.same(custom_opts.project.root_markers, c.project.root_markers)
    assert.are.same(custom_opts.project.excluded_root_dirs, c.project.excluded_root_dirs)
    assert.is_false(c.project.persistence.enabled)
    assert.are.equal(custom_opts.project.persistence.dir, c.project.persistence.dir)

    -- Debug
    assert.is_true(c.debug.file)
    assert.is_true(c.debug.notify)

    -- Integrations
    assert.is_true(c.integrations.project_nvim)
    assert.is_true(c.integrations.bufferline.enabled)
    assert.is_true(c.integrations.snacks.enabled)
    assert.are.same(custom_opts.integrations.snacks.pickerProjectsOpts, c.integrations.snacks.pickerProjectsOpts)
  end)

  it("partially overrides config and keeps other defaults", function()
    config.setup({
      ui = { dashboard = { enabled = true } },
    })

    assert.is_true(config.values.ui.dashboard.enabled)
    assert.are.same({ "Projectab" }, config.values.ui.dashboard.header, "Should retain default header")
    assert.is_true(config.values.project.persistence.enabled, "Should retain default persistence")
  end)

  it("resets to defaults correctly", function()
    config.setup({ debug = { file = true } })
    assert.is_true(config.values.debug.file)

    config._reset()
    assert.is_false(config.values.debug.file)
  end)

  it("handles nil/empty setup by keeping defaults", function()
    config.setup(nil)
    assert.are.same({ "Projectab" }, config.values.ui.dashboard.header)

    config.setup({})
    assert.are.same({ "Projectab" }, config.values.ui.dashboard.header)
  end)
end)
