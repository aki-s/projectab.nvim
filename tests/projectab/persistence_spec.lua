--- Tests for projectab.persistence module
---
--- These are pure I/O and data-structure tests. They verify path encoding,
--- JSON read/write, and dashboard history operations.

local assert = require("luassert")
local config = require("projectab.config")
local persistence = require("projectab.persistence")

-- Use a temp directory for all persistence tests to avoid polluting real data.
local test_dir

describe("projectab.persistence", function()
  before_each(function()
    test_dir = vim.fn.tempname() .. "_projectab_test"
    vim.fn.mkdir(test_dir, "p")
    config.setup({
      debug = { file = false, notify = false },
      project = {
        persistence = { enabled = true, dir = test_dir },
      },
    })
  end)

  after_each(function()
    -- Clean up test directory
    vim.fn.delete(test_dir, "rf")
    config._reset()
  end)

  -- Path encoding ---------------------------------------------------------

  describe("encode_path", function()
    it("replaces slashes with percent signs", function()
      assert.are.equal("%Users%user1%projects%appA", persistence.encode_path("/Users/user1/projects/appA"))
    end)

    it("handles root path", function()
      assert.are.equal("%", persistence.encode_path("/"))
    end)

    it("handles paths without leading slash", function()
      assert.are.equal("relative%path", persistence.encode_path("relative/path"))
    end)
  end)

  describe("decode_path", function()
    it("restores slashes from percent signs", function()
      assert.are.equal("/Users/user1/projects/appA", persistence._decode_path("%Users%user1%projects%appA"))
    end)

    it("round-trips with encode_path", function()
      local original = "/Users/user1/projects/appA"
      assert.are.equal(original, persistence._decode_path(persistence.encode_path(original)))
    end)
  end)

  -- JSON I/O --------------------------------------------------------------

  describe("read_json / write_json", function()
    it("round-trips a table through JSON", function()
      local path = test_dir .. "/test.json"
      local data = { version = 1, items = { "a", "b" } }
      assert.is_true(persistence.write_json(path, data))

      local loaded = persistence.read_json(path)
      assert.is_not_nil(loaded)
      assert.are.equal(1, loaded.version)
      assert.are.same({ "a", "b" }, loaded.items)
    end)

    it("returns nil for non-existent file", function()
      assert.is_nil(persistence.read_json(test_dir .. "/nonexistent.json"))
    end)

    it("returns nil for empty file", function()
      local path = test_dir .. "/empty.json"
      local f = io.open(path, "w")
      f:close()
      assert.is_nil(persistence.read_json(path))
    end)

    it("returns nil for invalid JSON", function()
      local path = test_dir .. "/invalid.json"
      local f = io.open(path, "w")
      f:write("not valid json{{{")
      f:close()
      assert.is_nil(persistence.read_json(path))
    end)
  end)

  -- Dashboard -------------------------------------------------------------

  describe("dashboard", function()
    it("loads default when no file exists", function()
      local d = persistence.load_dashboard()
      assert.are.equal(1, d.version)
      assert.are.same({}, d.history)
    end)

    it("saves and loads dashboard", function()
      local d = { version = 1, history = { "/a", "/b" } }
      persistence.save_dashboard(d)

      local loaded = persistence.load_dashboard()
      assert.are.same({ "/a", "/b" }, loaded.history)
    end)
  end)

  -- History operations ----------------------------------------------------

  describe("touch_history", function()
    it("adds a new root to the front", function()
      local d = { version = 1, history = { "/a", "/b" } }
      d = persistence.touch_history(d, "/c")
      assert.are.same({ "/c", "/a", "/b" }, d.history)
    end)

    it("moves an existing root to the front", function()
      local d = { version = 1, history = { "/a", "/b", "/c" } }
      d = persistence.touch_history(d, "/b")
      assert.are.same({ "/b", "/a", "/c" }, d.history)
    end)

    it("does not duplicate entries", function()
      local d = { version = 1, history = { "/a" } }
      d = persistence.touch_history(d, "/a")
      assert.are.same({ "/a" }, d.history)
    end)
  end)

  describe("remove_from_history", function()
    it("removes an existing root", function()
      local d = { version = 1, history = { "/a", "/b", "/c" } }
      d = persistence.remove_from_history(d, "/b")
      assert.are.same({ "/a", "/c" }, d.history)
    end)

    it("is a no-op for non-existent root", function()
      local d = { version = 1, history = { "/a", "/b" } }
      d = persistence.remove_from_history(d, "/z")
      assert.are.same({ "/a", "/b" }, d.history)
    end)
  end)

  -- Per-project files -----------------------------------------------------

  describe("project files", function()
    it("saves and loads per-project data", function()
      local root = "/Users/user1/projects/appA"
      local data = {
        version = 1,
        root = root,
        last_saved = 1715423000,
        state = {
          buffers = { root .. "/src/main.lua", root .. "/doc/memo.md" },
          active_buffer = root .. "/src/main.lua",
        },
      }
      persistence.save_project(root, data)

      local loaded = persistence.load_project(root)
      assert.is_not_nil(loaded)
      assert.are.equal(root, loaded.root)
      assert.are.same(data.state.buffers, loaded.state.buffers)
      assert.are.equal(data.state.active_buffer, loaded.state.active_buffer)
    end)

    it("returns nil for non-existent project", function()
      assert.is_nil(persistence.load_project("/nonexistent/project"))
    end)

    it("deletes per-project file", function()
      local root = "/tmp/test-project"
      persistence.save_project(root, { version = 1, root = root, state = {} })
      assert.is_not_nil(persistence.load_project(root))

      persistence.delete_project(root)
      assert.is_nil(persistence.load_project(root))
    end)

    it("project file path uses encoded root", function()
      local root = "/Users/user1/projects/appA"
      local expected = test_dir .. "/%Users%user1%projects%appA.json"
      assert.are.equal(expected, persistence.get_project_path(root))
    end)
  end)
end)
