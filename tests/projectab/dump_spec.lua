--- Tests for projectab.dump module

local assert = require("luassert")
local config = require("projectab.config")
local state = require("projectab.state")
local detect = require("projectab.detect")
local buffer = require("projectab.buffer")
local dump = require("projectab.dump")

describe("projectab.dump", function()
  local tmp_root

  before_each(function()
    -- Minimal config; no filesystem writes needed for most tests.
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
      integrations = { project_nvim = false, bufferline = { enabled = false } },
    })
    state._reset()
    detect.projects_clear_root_cache()
    buffer._tab_buffers = {}
    buffer.resume()
  end)

  after_each(function()
    if tmp_root then
      vim.fn.delete(tmp_root, "rf")
      tmp_root = nil
    end
    state._reset()
    config._reset()
    buffer._tab_buffers = {}
    detect.projects_clear_root_cache()

    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose")
    end
  end)

  -- ── helpers ──────────────────────────────────────────────────────────

  local function read_file(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local content = f:read("*a")
    f:close()
    return content
  end

  -- ── tests ─────────────────────────────────────────────────────────────

  it("creates a file and returns its path", function()
    local path = dump.dump()
    assert.is_string(path)
    assert.is_truthy(path:find("projectab_dump", 1, true))

    local content = read_file(path)
    assert.is_not_nil(content)
    assert.is_truthy(#content > 0)
  end)

  it("output file contains all expected section headers", function()
    local path = dump.dump()
    local content = read_file(path)
    assert.is_not_nil(content)

    local expected_sections = {
      "=== projectab internal state dump ===",
      "=== config.values ===",
      "=== state.project_to_tab ===",
      "=== state.tab_to_project ===",
      "=== detect.root_cache ===",
      "=== buffer._tab_buffers ===",
      "=== nvim tab/window/buffer state ===",
    }
    for _, header in ipairs(expected_sections) do
      assert.is_truthy(content:find(header, 1, true), "Missing section in dump: " .. header)
    end
  end)

  it("output path is under stdpath('cache')/projectab", function()
    local path = dump.dump()
    local expected_dir = vim.fn.stdpath("cache") .. "/projectab"
    assert.is_truthy(
      path:sub(1, #expected_dir) == expected_dir,
      "Expected dump path under projectab cache dir, got: " .. path
    )
  end)

  it("creates a timestamped file and a symlink", function()
    local path = dump.dump()
    local cache_dir = vim.fn.stdpath("cache") .. "/projectab"
    local symlink = cache_dir .. "/projectab_dump.txt"

    -- Verify the returned path is timestamped
    assert.is_truthy(path:match("projectab_dump%.txt%.%d%d%d%d%-%d%d%-%d%dT%d%d%-%d%d%-%d%d%.txt$"))

    -- Verify symlink exists and points to the right file
    local stat = vim.uv.fs_lstat(symlink)
    assert.is_not_nil(stat, "Symlink should exist")
    assert.is_equal("link", stat.type)

    local target = vim.uv.fs_readlink(symlink)
    assert.is_equal(path, target)
  end)

  it("reflects current state.project_to_tab in output", function()
    local tab_id = vim.api.nvim_get_current_tabpage()
    state.register("/fake/project", tab_id)

    local path = dump.dump()
    local content = read_file(path)
    assert.is_not_nil(content)
    assert.is_truthy(content:find("/fake/project", 1, true), "project root not found in dump output")
  end)

  it("reflects buffer._tab_buffers in output", function()
    local tab_id = vim.api.nvim_get_current_tabpage()
    -- Create a scratch buffer just for the ID; we inject it into _tab_buffers directly
    local bufnr = vim.api.nvim_create_buf(false, true)
    buffer._tab_buffers[tab_id] = { bufnr }

    local path = dump.dump()
    local content = read_file(path)
    assert.is_not_nil(content)
    -- The buffer number should appear inside the _tab_buffers section
    assert.is_truthy(content:find(tostring(bufnr), 1, true), "buffer number not found in dump output")

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("includes tab/window information in nvim state section", function()
    local path = dump.dump()
    local content = read_file(path)
    assert.is_not_nil(content)
    -- At least one tab line should appear
    assert.is_truthy(content:find("tab1", 1, true), "tab1 not found in nvim state section")
    -- At least one window line
    assert.is_truthy(content:find("win1", 1, true), "win1 not found in nvim state section")
  end)
end)
