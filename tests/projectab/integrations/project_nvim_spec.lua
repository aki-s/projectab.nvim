--- Unit tests for projectab.integrations.project_nvim
---
local assert = require("luassert")

describe("projectab.integrations.project_nvim", function()
  before_each(function()
    require("projectab.state")._reset()
    -- Unload so each test gets a fresh require
    package.loaded["projectab.integrations.project_nvim"] = nil
    package.loaded["project_nvim.project"] = nil
  end)

  after_each(function()
    package.loaded["project_nvim.project"] = nil
    package.loaded["projectab.integrations.project_nvim"] = nil
    require("projectab.state")._reset()
  end)

  it("get_root returns nil when project.nvim is not available", function()
    -- Ensure project_nvim.project cannot be required
    package.loaded["project_nvim.project"] = nil
    -- Override pcall to simulate missing module
    local int = require("projectab.integrations.project_nvim")
    -- project_nvim is not installed → should return nil gracefully
    local root = int.get_root("/some/path/file.txt")
    assert.is_nil(root)
  end)

  it("get_root returns nil when project.nvim returns empty string", function()
    package.loaded["project_nvim.project"] = {
      get_project_root = function(_)
        return ""
      end,
    }
    local int = require("projectab.integrations.project_nvim")
    local root = int.get_root("/some/path/file.txt")
    assert.is_nil(root)
  end)

  it("get_root returns nil when project.nvim returns nil", function()
    package.loaded["project_nvim.project"] = {
      get_project_root = function(_)
        return nil
      end,
    }
    local int = require("projectab.integrations.project_nvim")
    local root = int.get_root("/some/path/file.txt")
    assert.is_nil(root)
  end)

  it("get_root delegates to project_nvim.project.get_project_root and returns the result", function()
    local called_with
    package.loaded["project_nvim.project"] = {
      get_project_root = function(path)
        called_with = path
        return "/detected/project/root"
      end,
    }
    local int = require("projectab.integrations.project_nvim")
    local root = int.get_root("/detected/project/root/src/main.lua")
    assert.are.equal("/detected/project/root", root)
    assert.are.equal("/detected/project/root/src/main.lua", called_with)
  end)

  it("get_root uses mocked project.nvim root for a matching path", function()
    local tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root .. "/projectA", "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root

    package.loaded["project_nvim.project"] = {
      get_project_root = function(path)
        if path:match("projectA") then
          return tmp_root .. "/projectA_mocked_by_project_nvim"
        end
        return nil
      end,
    }

    local int = require("projectab.integrations.project_nvim")
    local root = int.get_root(tmp_root .. "/projectA/file1.txt")
    assert.are.equal(tmp_root .. "/projectA_mocked_by_project_nvim", root)

    vim.fn.delete(tmp_root, "rf")
  end)
end)
