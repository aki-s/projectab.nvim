--- Test for projectab.detect module using plenary.busted
---
--- Covers:
---   - Basic root detection (various markers)
---   - Nested project handling (nearest root wins)
---   - Exclude directory support
---   - Root detection cache (hit, miss, clear, negative caching)

local assert = require("luassert")
local config = require("projectab.config")
local detect = require("projectab.detect")

--- Create a temporary directory structure for testing.
--- Uses fs_realpath to resolve symlinks (e.g., macOS /tmp → /private/tmp).
--- @param structure table<string, string|table> File tree spec
--- @return string Root temp directory path
local function create_temp_tree(structure)
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  tmpdir = vim.uv.fs_realpath(tmpdir) or tmpdir

  local function build(base, tree)
    for name, content in pairs(tree) do
      local path = base .. "/" .. name
      if type(content) == "table" then
        vim.fn.mkdir(path, "p")
        build(path, content)
      else
        local f = io.open(path, "w")
        if f then
          f:write(content)
          f:close()
        end
      end
    end
  end

  build(tmpdir, structure)
  return tmpdir
end

--- Remove a temporary directory tree.
--- @param dir string
local function remove_temp_tree(dir)
  vim.fn.delete(dir, "rf")
end

describe("projectab.detect", function()
  before_each(function()
    config.setup({
      project = {
        root_markers = { ".git", "go.mod", "Makefile" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
    })
    -- Always start with a clean cache
    detect.projects_clear_root_cache()
  end)

  after_each(function()
    config._reset()
    detect.projects_clear_root_cache()
  end)

  it("finds root by .git directory", function()
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["main.lua"] = "-- main",
        nested = {
          ["deep.lua"] = "-- deep",
        },
      },
    })

    assert.are.equal(tmp, detect.get_root(tmp .. "/src/main.lua"))
    assert.are.equal(tmp, detect.get_root(tmp .. "/src/nested/deep.lua"))
    remove_temp_tree(tmp)
  end)

  it("finds root by go.mod", function()
    local tmp = create_temp_tree({
      ["go.mod"] = "module example.com/foo\n",
      cmd = {
        ["main.go"] = "package main",
      },
    })

    assert.are.equal(tmp, detect.get_root(tmp .. "/cmd/main.go"))
    remove_temp_tree(tmp)
  end)

  it("no marker returns nil", function()
    local tmp = create_temp_tree({
      src = {
        ["main.lua"] = "-- main",
      },
    })

    assert.is_nil(detect.get_root(tmp .. "/src/main.lua"))
    remove_temp_tree(tmp)
  end)

  it("nested projects return nearest root", function()
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      subproject = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["file.lua"] = "-- in subproject",
      },
      ["top.lua"] = "-- at top",
    })

    assert.are.equal(tmp .. "/subproject", detect.get_root(tmp .. "/subproject/file.lua"))
    assert.are.equal(tmp, detect.get_root(tmp .. "/top.lua"))
    remove_temp_tree(tmp)
  end)

  it("empty/nil path returns nil", function()
    assert.is_nil(detect.get_root(""))
    assert.is_nil(detect.get_root(nil))
  end)

  it("exclude dirs prevents root detection", function()
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      ["main.lua"] = "-- main",
    })

    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = { tmp },
      },
      debug = { file = false, notify = false },
    })

    assert.is_nil(detect.get_root(tmp .. "/main.lua"))

    remove_temp_tree(tmp)
  end)
end)

describe("projectab.detect cache", function()
  before_each(function()
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
    })
    detect.projects_clear_root_cache()
  end)

  after_each(function()
    config._reset()
    detect.projects_clear_root_cache()
  end)

  it("caches positive results (cache hit returns same value)", function()
    -- After the first call, the result should be cached.
    -- The second call should return the same value without needing fs_stat.
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["main.lua"] = "-- main",
      },
    })

    local root1 = detect.get_root(tmp .. "/src/main.lua")
    assert.are.equal(tmp, root1)
    assert.are.equal(1, detect._cache_size())

    -- Second call should hit cache
    local root2 = detect.get_root(tmp .. "/src/main.lua")
    assert.are.equal(tmp, root2)
    -- Cache size should not grow (same directory)
    assert.are.equal(1, detect._cache_size())

    remove_temp_tree(tmp)
  end)

  it("caches negative results (no root found)", function()
    -- When no root is found, the cache should store `false` so subsequent
    -- calls don't repeat the upward traversal.
    local tmp = create_temp_tree({
      src = {
        ["main.lua"] = "-- no markers anywhere",
      },
    })

    local root1 = detect.get_root(tmp .. "/src/main.lua")
    assert.is_nil(root1)
    assert.are.equal(1, detect._cache_size())

    -- Second call should hit cache (negative)
    local root2 = detect.get_root(tmp .. "/src/main.lua")
    assert.is_nil(root2)
    assert.are.equal(1, detect._cache_size())

    remove_temp_tree(tmp)
  end)

  it("cache is per-directory, not per-file", function()
    -- Two files in the same directory should share one cache entry.
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["a.lua"] = "a",
        ["b.lua"] = "b",
      },
    })

    detect.get_root(tmp .. "/src/a.lua")
    assert.are.equal(1, detect._cache_size())

    detect.get_root(tmp .. "/src/b.lua")
    -- Same directory → same cache entry, no growth
    assert.are.equal(1, detect._cache_size())

    remove_temp_tree(tmp)
  end)

  it("different directories create separate cache entries", function()
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["a.lua"] = "a",
      },
      lib = {
        ["b.lua"] = "b",
      },
    })

    detect.get_root(tmp .. "/src/a.lua")
    detect.get_root(tmp .. "/lib/b.lua")
    -- Two different directories → two cache entries
    assert.are.equal(2, detect._cache_size())

    remove_temp_tree(tmp)
  end)

  it("clear_cache removes all entries", function()
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["a.lua"] = "a",
      },
    })

    detect.get_root(tmp .. "/src/a.lua")
    assert.are.equal(1, detect._cache_size())

    detect.projects_clear_root_cache()
    assert.are.equal(0, detect._cache_size())

    remove_temp_tree(tmp)
  end)

  it("returns correct result after cache clear", function()
    -- After clearing cache, get_root should still work (cache miss → re-compute).
    local tmp = create_temp_tree({
      [".git"] = { HEAD = "ref: refs/heads/main\n" },
      src = {
        ["main.lua"] = "-- main",
      },
    })

    local root1 = detect.get_root(tmp .. "/src/main.lua")
    assert.are.equal(tmp, root1)

    detect.projects_clear_root_cache()

    local root2 = detect.get_root(tmp .. "/src/main.lua")
    assert.are.equal(tmp, root2)

    remove_temp_tree(tmp)
  end)
end)
