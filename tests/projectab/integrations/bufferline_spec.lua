--- Unit tests for projectab.integrations.bufferline
---
local assert = require("luassert")

--- Create a temporary directory tree for testing.
--- Resolves symlinks (e.g. macOS /tmp → /private/tmp).
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

local function remove_temp_tree(dir)
  vim.fn.delete(dir, "rf")
end

describe("projectab.integrations.bufferline", function()
  local state
  local bl
  local tmp_root

  before_each(function()
    require("projectab.state")._reset()
    package.loaded["projectab.integrations.bufferline"] = nil
    package.loaded["bufferline"] = nil
    package.loaded["bufferline.groups"] = nil

    state = require("projectab.state")
    bl = require("projectab.integrations.bufferline")

    tmp_root = create_temp_tree({
      projectA = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["file1.txt"] = "content",
      },
    })
  end)

  after_each(function()
    remove_temp_tree(tmp_root)
    package.loaded["bufferline"] = nil
    package.loaded["bufferline.groups"] = nil
    package.loaded["projectab.integrations.bufferline"] = nil
    require("projectab.state")._reset()
  end)

  -- ─── get_project_name_by_tab ─────────────────────────────────────────────

  describe("get_project_name_by_tab", function()
    it("returns nil when tab has no registered project", function()
      local tab_id = vim.api.nvim_get_current_tabpage()
      assert.is_nil(bl.get_project_name_by_tab(tab_id))
    end)

    it("returns the basename of the registered project root", function()
      local tab_id = vim.api.nvim_get_current_tabpage()
      state.register(tmp_root .. "/projectA", tab_id)
      assert.are.equal("projectA", bl.get_project_name_by_tab(tab_id))
    end)
  end)

  -- ─── get_project_name_by_buffer ──────────────────────────────────────────

  describe("get_project_name_by_buffer", function()
    it("returns nil for a buffer with no resolvable project root", function()
      -- Use a scratch buffer not tied to any file
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_nil(bl.get_project_name_by_buffer(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns the project basename for a buffer inside a git repo", function()
      local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
      vim.fn.bufload(bufnr)
      -- get_project_name_by_buffer uses buffer.resolve_project_root which calls
      -- detect.get_root; with a real .git directory this should resolve.
      local name = bl.get_project_name_by_buffer(bufnr)
      assert.are.equal("projectA", name)
    end)
  end)

  -- ─── build_groups ────────────────────────────────────────────────────────

  describe("build_groups", function()
    it("returns at least the pinned group when bufferline.groups is available", function()
      package.loaded["bufferline.groups"] = {
        builtin = {
          pinned = {
            with = function()
              return { name = "Pinned" }
            end,
          },
        },
        set_groups = function() end,
      }

      local tab_id = vim.api.nvim_get_current_tabpage()
      local groups = bl.build_groups(tab_id)
      assert.is_true(#groups >= 1)
      assert.are.equal("Pinned", groups[1].name)
    end)

    it("returns a project group for buffers in a tracked project window", function()
      package.loaded["bufferline.groups"] = {
        builtin = {
          pinned = {
            with = function()
              return { name = "Pinned" }
            end,
          },
        },
        set_groups = function() end,
      }

      local tab_id = vim.api.nvim_get_current_tabpage()
      state.register(tmp_root .. "/projectA", tab_id)

      local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].buftype = ""

      local groups = bl.build_groups(tab_id)
      -- Expect pinned + at least one project group
      assert.is_true(#groups >= 2)
      -- Find the projectA group
      local found = false
      for _, g in ipairs(groups) do
        if g.name == "projectA" then
          found = true
          break
        end
      end
      assert.is_true(found, "Expected a group named 'projectA'")
    end)

    it("group matcher returns true for a buffer inside the project root", function()
      package.loaded["bufferline.groups"] = {
        builtin = {
          pinned = {
            with = function()
              return { name = "Pinned" }
            end,
          },
        },
        set_groups = function() end,
      }

      local tab_id = vim.api.nvim_get_current_tabpage()
      local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].buftype = ""

      local groups = bl.build_groups(tab_id)
      local project_group
      for _, g in ipairs(groups) do
        if g.name == "projectA" then
          project_group = g
          break
        end
      end
      assert.is_not_nil(project_group, "Expected a group named 'projectA'")
      assert.is_function(project_group.matcher)

      -- Simulate a bufferline buf object
      local buf_obj = { id = bufnr }
      assert.is_true(project_group.matcher(buf_obj))
    end)
  end)

  -- ─── on_tab_enter ────────────────────────────────────────────────────────

  describe("on_tab_enter", function()
    it("calls bufferline.groups.set_groups when available", function()
      -- (moved from config_spec.lua)
      local set_groups_called = false
      package.loaded["bufferline"] = { setup = function() end }
      package.loaded["bufferline.groups"] = {
        builtin = {
          pinned = {
            with = function()
              return { name = "Pinned" }
            end,
          },
        },
        set_groups = function(_)
          set_groups_called = true
        end,
      }

      local tab_id = vim.api.nvim_get_current_tabpage()
      state.register(tmp_root .. "/projectA", tab_id)

      local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].buftype = ""

      bl.on_tab_enter(tab_id)

      assert.is_true(set_groups_called)
    end)

    it("falls back to bufferline.setup when set_groups is unavailable", function()
      local setup_called = false
      package.loaded["bufferline"] = {
        setup = function(_)
          setup_called = true
        end,
      }
      package.loaded["bufferline.groups"] = {
        builtin = {
          pinned = {
            with = function()
              return { name = "Pinned" }
            end,
          },
        },
        -- set_groups intentionally absent to trigger fallback
      }

      local tab_id = vim.api.nvim_get_current_tabpage()
      bl.on_tab_enter(tab_id)

      assert.is_true(setup_called)
    end)

    it("does nothing when bufferline is not available", function()
      -- bufferline module is not loaded; on_tab_enter should return silently
      package.loaded["bufferline"] = nil
      package.loaded["bufferline.groups"] = nil

      local tab_id = vim.api.nvim_get_current_tabpage()
      -- Should not throw an error
      assert.has_no.errors(function()
        bl.on_tab_enter(tab_id)
      end)
    end)
  end)
end)
