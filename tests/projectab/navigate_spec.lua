--- Tests for projectab.navigate module

local assert = require("luassert")
local config = require("projectab.config")
local state = require("projectab.state")
local buffer = require("projectab.buffer")
local navigate = require("projectab.navigate")

--- Construct a clean test environment by clearing config, state, and tabs.
local function setup_env()
  config.setup({
    project = {
      root_markers = { ".git" },
      excluded_root_dirs = {},
    },
    debug = { file = false, notify = false },
    integrations = { project_nvim = false, bufferline = false, snacks = { enabled = false } },
  })
  state._reset()
  buffer.resume()
end

local function teardown_env()
  state._reset()
  config._reset()

  while #vim.api.nvim_list_tabpages() > 1 do
    pcall(vim.cmd, "tabclose")
  end

  -- Wipe out all non-essential buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

describe("projectab.navigate", function()
  local tmp_root

  before_each(function()
    setup_env()

    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root

    vim.fn.mkdir(tmp_root .. "/projectA", "p")
    vim.fn.mkdir(tmp_root .. "/projectA/.git", "p")
    vim.fn.mkdir(tmp_root .. "/projectB", "p")
    vim.fn.mkdir(tmp_root .. "/projectB/.git", "p")
  end)

  after_each(function()
    if tmp_root then
      vim.fn.delete(tmp_root, "rf")
    end
    teardown_env()
  end)

  it("cycles bnext and bprevious constrained to the current project", function()
    -- Set up Tab 1 -> Project A
    local tab_A = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab_A)

    local buf_A1 = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(buf_A1)
    vim.bo[buf_A1].buflisted = true

    local buf_A2 = vim.fn.bufadd(tmp_root .. "/projectA/file2.txt")
    vim.fn.bufload(buf_A2)
    vim.bo[buf_A2].buflisted = true

    local buf_A3 = vim.fn.bufadd(tmp_root .. "/projectA/file3.txt")
    vim.fn.bufload(buf_A3)
    vim.bo[buf_A3].buflisted = true

    -- Put Project B buffers into the global pool
    local buf_B1 = vim.fn.bufadd(tmp_root .. "/projectB/file1.txt")
    vim.fn.bufload(buf_B1)
    vim.bo[buf_B1].buflisted = true

    local buf_B2 = vim.fn.bufadd(tmp_root .. "/projectB/file2.txt")
    vim.fn.bufload(buf_B2)
    vim.bo[buf_B2].buflisted = true

    -- We are on Tab 1 (Project A), standing on A1
    vim.cmd("buffer " .. buf_A1)

    -- Test bnext wrapping
    navigate.project_bnext()
    assert.are.equal(buf_A2, vim.api.nvim_get_current_buf())

    navigate.project_bnext()
    assert.are.equal(buf_A3, vim.api.nvim_get_current_buf())

    -- Bnext from the end should wrap around back to the beginning of Project A
    -- and should NEVER visit B1 or B2.
    navigate.project_bnext()
    assert.are.equal(buf_A1, vim.api.nvim_get_current_buf())

    -- Test bprevious wrapping
    navigate.project_bprevious()
    assert.are.equal(buf_A3, vim.api.nvim_get_current_buf())

    navigate.project_bprevious()
    assert.are.equal(buf_A2, vim.api.nvim_get_current_buf())

    navigate.project_bprevious()
    assert.are.equal(buf_A1, vim.api.nvim_get_current_buf())
  end)

  it("handles bnext and bprevious correctly when there is only one buffer", function()
    local tab_A = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab_A)

    local buf_A1 = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(buf_A1)
    vim.bo[buf_A1].buflisted = true

    -- A project B buffer exists globally
    local buf_B1 = vim.fn.bufadd(tmp_root .. "/projectB/file1.txt")
    vim.fn.bufload(buf_B1)
    vim.bo[buf_B1].buflisted = true

    vim.cmd("buffer " .. buf_A1)

    -- Call next, it should remain on A1
    navigate.project_bnext()
    assert.are.equal(buf_A1, vim.api.nvim_get_current_buf())

    -- Call prev, it should remain on A1
    navigate.project_bprevious()
    assert.are.equal(buf_A1, vim.api.nvim_get_current_buf())
  end)

  it("handles bnext from an unlisted/unrelated buffer by jumping to the first valid one", function()
    local tab_A = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab_A)

    local buf_A1 = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(buf_A1)
    vim.bo[buf_A1].buflisted = true

    local buf_A2 = vim.fn.bufadd(tmp_root .. "/projectA/file2.txt")
    vim.fn.bufload(buf_A2)
    vim.bo[buf_A2].buflisted = true

    -- We are on an empty unlisted buffer
    vim.cmd("enew")
    local current_buf = vim.api.nvim_get_current_buf()
    vim.bo[current_buf].buflisted = false

    -- bnext should jump to the very first buffer assigned to Project A (A1)
    navigate.project_bnext()
    assert.are.equal(buf_A1, vim.api.nvim_get_current_buf())
  end)

  it("handles bprevious from an unlisted/unrelated buffer by jumping to the last valid one", function()
    local tab_A = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab_A)

    local buf_A1 = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(buf_A1)
    vim.bo[buf_A1].buflisted = true

    local buf_A2 = vim.fn.bufadd(tmp_root .. "/projectA/file2.txt")
    vim.fn.bufload(buf_A2)
    vim.bo[buf_A2].buflisted = true

    -- We are on an empty unlisted buffer
    vim.cmd("enew")
    local current_buf = vim.api.nvim_get_current_buf()
    vim.bo[current_buf].buflisted = false

    -- bprevious should jump to the very last buffer assigned to Project A (A2)
    navigate.project_bprevious()
    assert.are.equal(buf_A2, vim.api.nvim_get_current_buf())
  end)
end)
