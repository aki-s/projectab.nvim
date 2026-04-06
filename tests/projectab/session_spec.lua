local assert = require("luassert")
local config = require("projectab.config")
local session = require("projectab.session")
local buffer = require("projectab.buffer")
local state = require("projectab.state")
local persistence = require("projectab.persistence")

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

describe("projectab.session", function()
  local tmp_root
  local original_save_project

  before_each(function()
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
      integrations = { project_nvim = false, bufferline = false },
    })
    state._reset()
    buffer.resume()
    vim.g.SessionLoad = nil

    original_save_project = persistence.save_project
  end)

  after_each(function()
    if tmp_root then
      remove_temp_tree(tmp_root)
      tmp_root = nil
    end
    state._reset()
    config._reset()
    persistence.save_project = original_save_project

    -- Close all extra tabs. Use while-loop instead of for-loop because
    -- tabclose changes the tab list mid-iteration.
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose")
    end
  end)

  it("does not save nested project buffers in parent project session", function()
    tmp_root = create_temp_tree({
      parent = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["parent.txt"] = "1",
        child = {
          [".git"] = { HEAD = "ref: refs/heads/main\n" },
          ["child.txt"] = "2",
        },
      },
    })

    local parent_root = tmp_root .. "/parent"
    local child_root = parent_root .. "/child"
    local parent_file = parent_root .. "/parent.txt"
    local child_file = child_root .. "/child.txt"

    -- Open parent buffer
    local bufnr_parent = vim.fn.bufadd(parent_file)
    vim.fn.bufload(bufnr_parent)
    vim.bo[bufnr_parent].buflisted = true
    buffer.handle_buf_enter(bufnr_parent)

    -- Open child buffer
    local bufnr_child = vim.fn.bufadd(child_file)
    vim.fn.bufload(bufnr_child)
    vim.bo[bufnr_child].buflisted = true
    buffer.handle_buf_enter(bufnr_child)

    local parent_tab = state.get_tab(parent_root)
    assert.is_not_nil(parent_tab, "Parent tab should exist")

    -- Intercept the save call
    local saved_data
    persistence.save_project = function(root, data)
      if root == parent_root then
        saved_data = data
      end
      return true
    end

    session.project_save(parent_root, parent_tab)

    assert.is_not_nil(saved_data, "Should have attempted to save parent project")
    assert.is_not_nil(saved_data.state.buffers, "Should have a buffers list")

    local function contains_buffer(buffers, target_path)
      for _, path in ipairs(buffers) do
        if path == target_path then
          return true
        end
      end
      return false
    end

    assert.is_true(contains_buffer(saved_data.state.buffers, parent_file), "Parent session should contain parent.txt")
    assert.is_false(
      contains_buffer(saved_data.state.buffers, child_file),
      "Parent session MUST NOT contain child.txt (nested project bleed)"
    )
  end)

  it("filters out buffers that do not belong to the project during restore", function()
    tmp_root = create_temp_tree({
      parent = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["parent.txt"] = "1",
        child = {
          [".git"] = { HEAD = "ref: refs/heads/main\n" },
          ["child.txt"] = "2",
        },
      },
    })

    local parent_root = tmp_root .. "/parent"
    local child_root = parent_root .. "/child"
    local parent_file = parent_root .. "/parent.txt"
    local child_file = child_root .. "/child.txt"

    -- Mock persistence to return a "corrupted" save state containing the child file
    local data = {
      version = 1,
      root = parent_root,
      last_saved = os.time(),
      state = {
        buffers = { parent_file, child_file },
        active_buffer = parent_file,
      },
    }
    persistence.load_project = function(root)
      if root == parent_root then
        return data
      end
      return nil
    end

    -- Run restore
    local success = session.project_restore(parent_root)
    assert.is_true(success, "Restore should succeed")

    -- Check which buffers were actually opened in Neovim
    -- The restore process should open parent.txt but skip child.txt
    local opened_buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name ~= "" then
          table.insert(opened_buffers, name)
        end
      end
    end

    local function contains_buffer(buffers, target_path)
      for _, path in ipairs(buffers) do
        if path == target_path then
          return true
        end
      end
      return false
    end

    assert.is_true(contains_buffer(opened_buffers, parent_file), "Parent session should restore parent.txt")
    assert.is_false(
      contains_buffer(opened_buffers, child_file),
      "Parent session MUST NOT restore child.txt (filtered out)"
    )
  end)

  it("does not save buffers from other projects even if they are visible in a window", function()
    tmp_root = create_temp_tree({
      projectA = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["fileA.txt"] = "1",
      },
      projectB = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["fileB.txt"] = "1",
      },
    })

    local rootA = tmp_root .. "/projectA"
    local rootB = tmp_root .. "/projectB"
    local fileA = rootA .. "/fileA.txt"
    local fileB = rootB .. "/fileB.txt"

    -- Open A normally so it claims the current tab
    local bufnrA = vim.fn.bufadd(fileA)
    vim.fn.bufload(bufnrA)
    vim.bo[bufnrA].buflisted = true
    buffer.handle_buf_enter(bufnrA)

    local tabA = state.get_tab(rootA)
    assert.is_not_nil(tabA, "tabA must exist")
    vim.api.nvim_set_current_tabpage(tabA)

    -- Suspend buffer routing so we can artificially force fileB into tabA's window
    buffer.suspend()
    local bufnrB = vim.fn.bufadd(fileB)
    vim.fn.bufload(bufnrB)
    vim.bo[bufnrB].buflisted = true
    -- Force fileB to be visible in the current window (in tabA)
    vim.api.nvim_win_set_buf(0, bufnrB)

    -- Now tabA has fileB active in its main window!

    -- Intercept the save call
    local saved_data
    persistence.save_project = function(root, data)
      if root == rootA then
        saved_data = data
      end
      return true
    end

    session.project_save(rootA, tabA)

    assert.is_not_nil(saved_data, "Should have attempted to save projectA")
    assert.is_not_nil(saved_data.state.buffers, "Should have a buffers list")

    local function contains_buffer(buffers, target_path)
      for _, path in ipairs(buffers) do
        if path == target_path then
          return true
        end
      end
      return false
    end

    assert.is_true(contains_buffer(saved_data.state.buffers, fileA), "Should save fileA")
    assert.is_false(
      contains_buffer(saved_data.state.buffers, fileB),
      "MUST NOT save fileB even if it was visible in tabA's window"
    )
  end)

  it("normalizes relative buffer paths to absolute paths during save", function()
    tmp_root = create_temp_tree({
      project = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["file.txt"] = "content",
      },
    })

    local root = tmp_root .. "/project"
    local file = root .. "/file.txt"

    -- Change to project directory
    vim.cmd("cd " .. vim.fn.fnameescape(root))

    -- Open buffer with relative path
    local bufnr = vim.fn.bufadd("file.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true
    buffer.handle_buf_enter(bufnr)

    local tab = state.get_tab(root)
    assert.is_not_nil(tab, "Tab should exist")

    -- Intercept the save call
    local saved_data
    persistence.save_project = function(r, data)
      if r == root then
        saved_data = data
      end
      return true
    end

    session.project_save(root, tab)

    assert.is_not_nil(saved_data, "Should have saved project")
    assert.is_not_nil(saved_data.state.buffers, "Should have buffers list")
    assert.equals(1, #saved_data.state.buffers, "Should have exactly one buffer")

    -- The saved path must be absolute, not relative
    local saved_path = saved_data.state.buffers[1]
    assert.equals(file, saved_path, "Buffer path must be normalized to absolute path")
    assert.is_true(saved_path:sub(1, 1) == "/", "Saved path must start with /")
  end)

  it("list returns projects sorted by recency from persistence", function()
    persistence.list_projects_by_recency = function(limit)
      if limit == 1 then
        return { "/tmp/project2" }
      end
      return { "/tmp/project2", "/tmp/project1" }
    end

    local history = session.list()
    assert.are.same({ "/tmp/project2", "/tmp/project1" }, history)

    local limited = session.list({ limit = 1 })
    assert.are.same({ "/tmp/project2" }, limited)
  end)
end)
