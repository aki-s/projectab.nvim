--- Tests for projectab.buffer module
---
--- Structure:
---   1. Integration tests: use real filesystem temp trees and Neovim tab/buffer APIs.
---      These test the full BufEnter → resolve → allocate pipeline.
---   2. Unit tests: mock Neovim APIs to test allocate_buffer_to_tab in isolation.

local assert = require("luassert")
local config = require("projectab.config")
local buffer = require("projectab.buffer")
local state = require("projectab.state")

--- Create a temporary directory tree with the given structure.
--- Keys are names; string values create files, table values create subdirs.
--- Returns the absolute path to the root temp directory.
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

describe("projectab.buffer integration", function()
  local tmp_root

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
    -- Ensure routing is not suspended from a previous test
    buffer.resume()
    vim.g.SessionLoad = nil

    tmp_root = create_temp_tree({
      projectA = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["file1.txt"] = "1",
      },
      projectB = {
        [".git"] = { HEAD = "ref: refs/heads/main\n" },
        ["file2.txt"] = "2",
      },
    })
  end)

  after_each(function()
    remove_temp_tree(tmp_root)
    state._reset()
    config._reset()
    vim.g.SessionLoad = nil

    -- Close all extra tabs. Use while-loop instead of for-loop because
    -- tabclose changes the tab list mid-iteration.
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose")
    end
  end)

  it("skips routing during session restore (SessionLoad)", function()
    -- When Neovim is restoring a session via :source, vim.g.SessionLoad is set.
    -- Buffer routing must be suppressed to avoid spawning tabs during restore.
    vim.g.SessionLoad = true
    local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(bufnr)

    local initial_tab = vim.api.nvim_get_current_tabpage()
    buffer.handle_buf_enter(bufnr)

    -- Should not map project or change tab
    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
    assert.is_nil(state.get_tab(tmp_root .. "/projectA"))
  end)

  it("skips routing when suspended via API", function()
    -- 3rd party session managers should call suspend() before bulk restores.
    buffer.suspend()
    local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(bufnr)

    local initial_tab = vim.api.nvim_get_current_tabpage()
    buffer.handle_buf_enter(bufnr)

    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
    assert.is_nil(state.get_tab(tmp_root .. "/projectA"))

    buffer.resume()
  end)

  it("skips special buffers", function()
    -- Special buffers (quickfix, help, terminal, etc.) should never be routed.
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].buftype = "quickfix"
    vim.api.nvim_buf_set_name(bufnr, tmp_root .. "/projectA/qf.txt")

    local initial_tab = vim.api.nvim_get_current_tabpage()
    buffer.handle_buf_enter(bufnr)

    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
    assert.is_nil(state.get_tab(tmp_root .. "/projectA"))
  end)

  it("skips routing for unlisted buffers", function()
    -- Buffers that are unlisted (e.g. scratch buffers) should not trigger routing.
    local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file_unlisted.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = false

    local initial_tab = vim.api.nvim_get_current_tabpage()
    buffer.handle_buf_enter(bufnr)

    -- Should not route or register tab
    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
    assert.is_nil(state.get_tab(tmp_root .. "/projectA"))
  end)

  it("skips routing for unnamed buffers", function()
    -- Empty [No Name] buffers shouldn't route to any project.
    local bufnr = vim.api.nvim_create_buf(false, true)

    local initial_tab = vim.api.nvim_get_current_tabpage()
    buffer.handle_buf_enter(bufnr)

    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
  end)

  it("closes the source split window if buffer was routed to a different tab", function()
    local current_tab = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", current_tab)

    -- Create another tab for projectB
    vim.cmd("tabnew")
    local target_tab = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectB", target_tab)

    -- Go back to projectA tab and create a split
    vim.api.nvim_set_current_tabpage(current_tab)
    vim.cmd("vsplit")
    local win_count_before = #vim.api.nvim_tabpage_list_wins(current_tab)

    -- Open projectB buffer in this split (should trigger routing)
    local bufnr_B = vim.fn.bufadd(tmp_root .. "/projectB/file2.txt")
    vim.fn.bufload(bufnr_B)
    vim.bo[bufnr_B].buflisted = true

    buffer.handle_buf_enter(bufnr_B)

    -- Pump event loop for vim.schedule (since window cleanup runs asynchronously)
    vim.wait(50, function()
      return false
    end)

    -- We should now be in Project B's tab
    assert.are.equal(target_tab, vim.api.nvim_get_current_tabpage())

    -- The split in Project A's tab should have been closed
    local win_count_after = #vim.api.nvim_tabpage_list_wins(current_tab)
    assert.are.equal(win_count_before - 1, win_count_after)
  end)

  it("registers unclaimed current tab to a new project buffer", function()
    -- When the current tab has no project association, it should be claimed
    -- by the first project buffer that enters it.
    local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true
    local initial_tab = vim.api.nvim_get_current_tabpage()

    buffer.handle_buf_enter(bufnr)

    assert.are.equal(initial_tab, vim.api.nvim_get_current_tabpage())
    assert.are.equal(initial_tab, state.get_tab(tmp_root .. "/projectA"))
    assert.are.equal(tmp_root .. "/projectA", state.get_project(initial_tab))
  end)

  it("creates a new tab if current tab is claimed by another project", function()
    -- When the current tab already belongs to project A and a buffer from
    -- project B enters, a new tab must be created for project B.
    local current_tab = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", current_tab)

    local bufnr_B = vim.fn.bufadd(tmp_root .. "/projectB/file2.txt")
    vim.fn.bufload(bufnr_B)
    vim.bo[bufnr_B].buflisted = true

    buffer.handle_buf_enter(bufnr_B)

    local new_tab = vim.api.nvim_get_current_tabpage()

    assert.not_are.equal(current_tab, new_tab)
    assert.are.equal(new_tab, state.get_tab(tmp_root .. "/projectB"))
  end)

  it("sets tcd when claiming an unclaimed tab", function()
    -- When a buffer claims an unclaimed tab, tcd must be set to the project root
    -- so that LSP / file pickers use the correct working directory.
    local bufnr = vim.fn.bufadd(tmp_root .. "/projectA/file1.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true

    buffer.handle_buf_enter(bufnr)

    local cwd = vim.fn.getcwd(-1, 0)
    -- tcd should be set to the project root
    assert.are.equal(tmp_root .. "/projectA", cwd)
  end)

  it("sets tcd when creating a new tab for a project", function()
    -- When a new tab is created for a project, tcd must be set.
    local current_tab = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", current_tab)

    local bufnr_B = vim.fn.bufadd(tmp_root .. "/projectB/file2.txt")
    vim.fn.bufload(bufnr_B)
    vim.bo[bufnr_B].buflisted = true

    buffer.handle_buf_enter(bufnr_B)

    local new_tab = vim.api.nvim_get_current_tabpage()
    assert.not_are.equal(current_tab, new_tab)

    -- Verify tcd is set on the new tab
    local tab_nr = vim.api.nvim_tabpage_get_number(new_tab)
    local cwd = vim.fn.getcwd(-1, tab_nr)
    assert.are.equal(tmp_root .. "/projectB", cwd)
  end)
end)

describe("projectab.buffer unit (allocation logic)", function()
  local real_vim = _G.vim
  --- Track all vim.cmd calls in order, since allocate_buffer_to_tab may issue
  --- multiple commands (e.g., "tab sb N" then "tcd /path").
  local cmd_history, last_tab

  before_each(function()
    state._reset()
    cmd_history = {}
    last_tab = nil

    -- Mock Neovim APIs to test allocation in isolation.
    -- NOTE: We use vim.deepcopy which cannot copy C functions/userdata.
    -- To mitigate, we explicitly override all APIs that allocate_buffer_to_tab
    -- calls. If a new API call is added to the production code, a corresponding
    -- mock must be added here or the test will fail with a clear error.
    _G.vim = vim.deepcopy(real_vim)
    _G.vim.api.nvim_buf_is_valid = function()
      return true
    end
    _G.vim.api.nvim_get_current_tabpage = function()
      return 1
    end
    _G.vim.api.nvim_tabpage_is_valid = function()
      return true
    end
    _G.vim.api.nvim_set_current_tabpage = function(id)
      last_tab = id
    end
    _G.vim.api.nvim_get_option_value = function(name, opts)
      if name == "buflisted" then
        return true
      end
      return nil
    end
    _G.vim.api.nvim_set_option_value = function(name, value, opts)
      -- No-op for tests
    end
    _G.vim.cmd = function(c)
      table.insert(cmd_history, c)
    end
    -- fnameescape is called by allocate_buffer_to_tab for tcd arguments.
    -- In unit tests we return the input unchanged since paths don't have special chars.
    _G.vim.fn.fnameescape = function(s)
      return s
    end
    -- fs_stat returns nil for fake paths, so register() won't call tcd.
    -- This is correct: unit tests use fake paths like "/my/project".
    _G.vim.uv = {
      fs_stat = function()
        return nil
      end,
    }
  end)

  after_each(function()
    _G.vim = real_vim
  end)

  it("assigns project to current tab if current tab is unclaimed", function()
    -- When no project owns the current tab, it should be claimed without creating a new tab.
    local allocated_tab, is_new = buffer.allocate_buffer_to_tab(10, "/my/project", 1, nil)
    assert.are.equal(1, allocated_tab)
    assert.is_false(is_new)
    assert.are.equal("/my/project", state.get_project(1))
    -- tcd is not set in unit tests because paths are fake (fs_stat returns nil).
    -- tcd setting is verified in integration tests with real paths.
  end)

  it("creates a new tab if current tab is claimed by a different project", function()
    -- When the current tab belongs to project A and project B needs a tab,
    -- allocate_buffer_to_tab should run `tab sb` to create a new tab,
    -- followed by `tcd` to set the working directory.
    state.register("/project/A", 1)
    _G.vim.api.nvim_get_current_tabpage = function()
      return 2
    end

    local allocated_tab, is_new = buffer.allocate_buffer_to_tab(10, "/project/B", 1, nil)

    assert.are.equal("tab sb 10", cmd_history[1])
    -- tcd is not in cmd_history because register() skips it for non-existent paths.
    assert.are.equal(2, allocated_tab)
    assert.is_true(is_new)
  end)

  it("switches to the project's target tab if not already there", function()
    -- When the buffer's project already owns tab 2, routing should switch there.
    -- No tcd needed here — the target tab should already have it set.
    state.register("/project/A", 2)
    local allocated_tab, is_new = buffer.allocate_buffer_to_tab(10, "/project/A", 1, 2)

    assert.are.equal(2, last_tab)
    assert.are.equal("buffer 10", cmd_history[1])
    assert.are.equal(2, allocated_tab)
  end)

  it("hides the buffer from scope.nvim caching during tab jump by toggling buflisted", function()
    -- scope.nvim works by hooking TabLeave to cache all listed buffers in the outgoing tab.
    -- We verify that when allocate_buffer_to_tab jumps tabs, buflisted is strictly false,
    -- tricking TabLeave into ignoring the buffer.
    state.register("/project/A", 2)

    local was_listed_during_jump = nil

    -- Mock the tab jump API to act as our "TabLeave" hook listener
    _G.vim.api.nvim_set_current_tabpage = function(id)
      last_tab = id
      -- Capture the buflisted status exactly when the jump (and TabLeave) occurs
      was_listed_during_jump = _G.vim.api.nvim_get_option_value("buflisted", { buf = 10 })
    end

    -- Initial state: The buffer is naturally listed
    local buflisted_state = true
    _G.vim.api.nvim_get_option_value = function(name, opts)
      if name == "buflisted" then
        return buflisted_state
      end
      return nil
    end
    _G.vim.api.nvim_set_option_value = function(name, value, opts)
      if name == "buflisted" then
        buflisted_state = value
      end
    end

    buffer.allocate_buffer_to_tab(10, "/project/A", 1, 2)

    -- It must be FALSE during the jump to avoid scope.nvim caching
    assert.is_false(was_listed_during_jump)
    -- It must be restored to TRUE after the routine finishes
    assert.is_true(buflisted_state)
  end)
end)

describe("projectab.buffer.clean_misplaced_buffers", function()
  local tmp_root

  before_each(function()
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = true, notify = false },
      integrations = { project_nvim = false, bufferline = false },
    })
    state._reset()
    buffer.resume()
  end)

  after_each(function()
    if tmp_root then
      vim.fn.delete(tmp_root, "rf")
      tmp_root = nil
    end
    state._reset()
    config._reset()

    state._reset()
    config._reset()

    -- Close all extra tabs. Use while-loop instead of for-loop because
    -- tabclose changes the tab list mid-iteration.
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose")
    end
  end)

  it("leaves an Explore buffer instead of closing the tab to preserve session restored tabs", function()
    -- Scenario: a persistence.nvim plugin restores a tab for project B,
    -- but all its windows have misplaced buffers from project A.
    -- After cleanup, tab 2 should survive with an Explore (netrw) buffer
    -- to preserve the user's workspace, rather than closing entirely.
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/projectA", "p")
    vim.fn.mkdir(tmp_root .. "/projectB", "p")
    vim.fn.mkdir(tmp_root .. "/projectA/.git", "p")
    vim.fn.mkdir(tmp_root .. "/projectB/.git", "p")

    -- Setup tab 1 for project A
    local tab1 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab1)

    -- Create project A buffer
    local bufnr_A = vim.fn.bufadd(tmp_root .. "/projectA/file.txt")
    vim.fn.bufload(bufnr_A)
    vim.api.nvim_set_current_buf(bufnr_A)

    -- Setup tab 2 for project B, but intentionally open project A's buffer in it
    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectB", tab2)
    vim.api.nvim_set_current_buf(bufnr_A) -- Misplaced!

    local tabs_before = vim.api.nvim_list_tabpages()
    assert.are.equal(2, #tabs_before)

    -- Run cleanup
    buffer.clean_misplaced_buffers()

    -- Tab 2 should survive as an empty workspace so project B is not destroyed
    local tabs_after = vim.api.nvim_list_tabpages()
    assert.are.equal(2, #tabs_after)

    local wins = vim.api.nvim_tabpage_list_wins(tab2)
    assert.are.equal(1, #wins)
    local final_buf = vim.api.nvim_win_get_buf(wins[1])
    -- The fallback opens the current directory (Explore) or falls back to `enew`
    local name = vim.api.nvim_buf_get_name(final_buf)
    assert.is_true(
      name == "" or name == tmp_root .. "/projectB",
      "Expected buffer name to be empty (enew) or project root (Explore)"
    )
  end)

  it("closes only the misplaced window in a multi-window tab", function()
    -- Scenario: tab 2 has 2 windows. One window has a misplaced buffer (project A),
    -- and another has a project B buffer. Only the misplaced window should be closed;
    -- the tab should remain with the correctly-placed window.
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/projectA", "p")
    vim.fn.mkdir(tmp_root .. "/projectB", "p")
    vim.fn.mkdir(tmp_root .. "/projectA/.git", "p")
    vim.fn.mkdir(tmp_root .. "/projectB/.git", "p")

    -- Setup tab 1 for project A
    local tab1 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab1)

    local bufnr_A = vim.fn.bufadd(tmp_root .. "/projectA/file.txt")
    vim.fn.bufload(bufnr_A)
    vim.api.nvim_set_current_buf(bufnr_A)

    local bufnr_B = vim.fn.bufadd(tmp_root .. "/projectB/file.txt")
    vim.fn.bufload(bufnr_B)

    -- Setup tab 2 for project B with two windows
    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectB", tab2)
    vim.api.nvim_set_current_buf(bufnr_B) -- Correct window

    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(bufnr_A) -- Misplaced window!

    local wins_before = #vim.api.nvim_tabpage_list_wins(tab2)
    assert.are.equal(2, wins_before)

    buffer.clean_misplaced_buffers()

    -- Tab 2 should still exist but with only 1 window
    assert.is_true(vim.api.nvim_tabpage_is_valid(tab2))
    local wins_after = #vim.api.nvim_tabpage_list_wins(tab2)
    assert.are.equal(1, wins_after)

    -- Both tabs should still be alive
    local tabs_after = vim.api.nvim_list_tabpages()
    assert.are.equal(2, #tabs_after)
  end)

  it("does nothing when all buffers are correctly placed", function()
    -- Scenario: all buffers are in the correct tab. Cleanup should not
    -- modify any tabs or windows.
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/projectA", "p")
    vim.fn.mkdir(tmp_root .. "/projectA/.git", "p")

    local tab1 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab1)

    local bufnr_A = vim.fn.bufadd(tmp_root .. "/projectA/file.txt")
    vim.fn.bufload(bufnr_A)
    vim.api.nvim_set_current_buf(bufnr_A)

    local tabs_before = vim.api.nvim_list_tabpages()
    local wins_before = #vim.api.nvim_tabpage_list_wins(tab1)

    buffer.clean_misplaced_buffers()

    -- Nothing should change
    local tabs_after = vim.api.nvim_list_tabpages()
    assert.are.equal(#tabs_before, #tabs_after)
    assert.are.equal(wins_before, #vim.api.nvim_tabpage_list_wins(tab1))
  end)

  it("cleans up misplaced hidden buffers from _tab_buffers cache", function()
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/projectA/.git", "p")
    vim.fn.mkdir(tmp_root .. "/projectB/.git", "p")

    local tab1 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectA", tab1)

    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    state.register(tmp_root .. "/projectB", tab2)

    local filepath_A = tmp_root .. "/projectA/hidden.txt"
    local f = io.open(filepath_A, "w")
    if f then
      f:write("hidden buffer simulation")
      f:close()
    end

    local bufnr_A = vim.fn.bufadd(filepath_A)
    vim.fn.bufload(bufnr_A)
    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr_A })
    vim.api.nvim_set_option_value("buftype", "", { buf = bufnr_A })

    buffer._tab_buffers[tab2] = { bufnr_A }

    buffer.clean_misplaced_buffers()

    local tab2_cache = buffer._tab_buffers[tab2] or {}
    local found_in_B = false
    for _, b in ipairs(tab2_cache) do
      if b == bufnr_A then
        found_in_B = true
      end
    end
    assert.is_false(found_in_B, "projectA buffer erroneously remained in projectB's cache!")
  end)
end)

describe("projectab.buffer reentrancy guard", function()
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
  end)

  after_each(function()
    state._reset()
    config._reset()

    -- Close all extra tabs. Use while-loop instead of for-loop because
    -- tabclose changes the tab list mid-iteration.
    while #vim.api.nvim_list_tabpages() > 1 do
      pcall(vim.cmd, "tabclose")
    end
  end)

  it("suspend and resume toggle routing correctly", function()
    -- Verify that suspend/resume actually prevent/allow routing respectively.
    local tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/proj", "p")
    vim.fn.mkdir(tmp_root .. "/proj/.git", "p")

    local bufnr = vim.fn.bufadd(tmp_root .. "/proj/file.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true

    -- While suspended, routing should be no-op
    buffer.suspend()
    buffer.handle_buf_enter(bufnr)
    assert.is_nil(state.get_tab(tmp_root .. "/proj"))

    -- After resume, routing should work
    buffer.resume()
    buffer.handle_buf_enter(bufnr)
    assert.is_not_nil(state.get_tab(tmp_root .. "/proj"))

    vim.fn.delete(tmp_root, "rf")
  end)

  it("routing_toggle toggles the suspended state", function()
    buffer.resume()
    assert.is_true(buffer.routing_toggle())
    assert.is_false(buffer.routing_toggle())
    buffer.resume()
  end)

  it("aborts recursive BufEnter cascades due to is_routing lock", function()
    -- This test triggers the lock by overriding allocate_buffer_to_tab temporarily
    -- to invoke handle_buf_enter inside itself.
    local orig_alloc = buffer.allocate_buffer_to_tab
    local called_count = 0
    buffer.allocate_buffer_to_tab = function(...)
      called_count = called_count + 1
      buffer.handle_buf_enter(1) -- Attempt recursion
      return orig_alloc(...)
    end

    local tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root
    vim.fn.mkdir(tmp_root .. "/proj/.git", "p")

    local bufnr = vim.fn.bufadd(tmp_root .. "/proj/file.txt")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true

    buffer.handle_buf_enter(bufnr)

    -- Ensure it only successfully entered the allocation routing ONCE.
    assert.are.equal(1, called_count)

    buffer.allocate_buffer_to_tab = orig_alloc
    vim.fn.delete(tmp_root, "rf")
  end)
end)

describe("projectab.buffer resolve_project_root_from_path (deepest root wins)", function()
  -- Regression test for the bug where project.nvim returns a shallow ancestor
  -- repo root (e.g. an outer workspace .git) while the file actually belongs to a
  -- deeper nested project. The fix ensures that both project.nvim and native
  -- detection are consulted and the deepest (longest path) root is returned.
  --
  -- Simulated layout on disk:
  --   outer/                ← outer .git repo (project.nvim would return this)
  --     .git/
  --     inner/              ← separate project with its own .git
  --       .git/
  --       file.txt
  --
  -- Before the fix: project.nvim returns "outer" and it was returned immediately.
  -- After the fix:  both "outer" (project.nvim) and "outer/inner" (native) are
  --                 collected, and "outer/inner" is returned because it is deeper.

  local tmp_root

  before_each(function()
    tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root) or tmp_root

    vim.fn.mkdir(tmp_root .. "/.git", "p")
    vim.fn.mkdir(tmp_root .. "/inner/.git", "p")
    local f = io.open(tmp_root .. "/inner/file.txt", "w")
    if f then
      f:write("hello")
      f:close()
    end

    -- Enable project_nvim integration but mock it to simulate the bug:
    -- project.nvim returns the outer (shallower) root even for files inside inner/.
    config.setup({
      project = {
        root_markers = { ".git" },
        excluded_root_dirs = {},
      },
      debug = { file = false, notify = false },
      integrations = { project_nvim = true, bufferline = false },
    })

    -- Inject a fake project_nvim integration that always returns the outer root
    -- (mimicking the real bug where project.nvim walks to the outermost .git).
    package.loaded["projectab.integrations.project_nvim"] = {
      get_root = function(_path)
        return tmp_root -- shallow / outer root
      end,
    }
  end)

  after_each(function()
    if tmp_root then
      vim.fn.delete(tmp_root, "rf")
      tmp_root = nil
    end
    package.loaded["projectab.integrations.project_nvim"] = nil
    state._reset()
    config._reset()
  end)

  it("returns the deeper native root over the shallower project.nvim root", function()
    -- Native detection finds "outer/inner" (.git marker there).
    -- project.nvim (mocked) returns "outer".
    -- Expected: "outer/inner" is returned because it is more specific.
    local inner_file = tmp_root .. "/inner/file.txt"
    local result = buffer.resolve_project_root_from_path(inner_file)
    assert.are.equal(tmp_root .. "/inner", result)
  end)

  it("returns equal-depth root when both sources agree", function()
    -- When project.nvim is mocked to return the same root as native detection,
    -- the result should be that root (no regression for the happy path).
    package.loaded["projectab.integrations.project_nvim"] = {
      get_root = function(_path)
        return tmp_root .. "/inner"
      end,
    }
    local inner_file = tmp_root .. "/inner/file.txt"
    local result = buffer.resolve_project_root_from_path(inner_file)
    assert.are.equal(tmp_root .. "/inner", result)
  end)

  it("returns project.nvim root when native detection finds nothing", function()
    -- If only project.nvim finds a root (native returns nil),
    -- project.nvim's result should still be used.
    package.loaded["projectab.integrations.project_nvim"] = {
      get_root = function(_path)
        return tmp_root
      end,
    }
    -- Use a path with no .git markers (native will return nil)
    local no_git_path = tmp_root .. "/no_git_file.txt"
    local f = io.open(no_git_path, "w")
    if f then
      f:write("x")
      f:close()
    end
    -- The native detect walks up and will reach tmp_root which HAS .git.
    -- So let's use a path entirely outside the tmp_root tree.
    local outside = "/tmp"
    local result = buffer.resolve_project_root_from_path(outside)
    -- project.nvim mock returns tmp_root; native returns nil (no .git in /tmp).
    -- Result should be tmp_root.
    assert.are.equal(tmp_root, result)
    io.open(no_git_path, "w"):close() -- cleanup
  end)

  it("returns nil when no project root marker is found", function()
    -- When no project root marker is found in the path, the function should return nil.
    local tmp_root = vim.fn.tempname()
    vim.fn.mkdir(tmp_root, "p")
    tmp_root = vim.uv.fs_realpath(tmp_root)

    local file_path = tmp_root .. "/file.txt"
    io.open(file_path, "w"):close()

    config.setup()

    local result = buffer.resolve_project_root_from_path(file_path)
    assert.is_nil(result)

    vim.fn.delete(tmp_root, "rf")
  end)
end)

describe("projectab.buffer visibility management", function()
  local buffer = require("projectab.buffer")
  local state = require("projectab.state")

  local buf1, buf2
  local initial_tab

  before_each(function()
    state._reset()
    buffer._tab_buffers = {}

    initial_tab = vim.api.nvim_get_current_tabpage()

    -- Create two real buffers
    buf1 = vim.api.nvim_create_buf(true, false)
    buf2 = vim.api.nvim_create_buf(true, false)

    -- Make buf1 listed, buf2 unlisted
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf1 })
    vim.api.nvim_set_option_value("buflisted", false, { buf = buf2 })
  end)

  after_each(function()
    -- Clean up buffers
    if vim.api.nvim_buf_is_valid(buf1) then
      vim.api.nvim_buf_delete(buf1, { force = true })
    end
    if vim.api.nvim_buf_is_valid(buf2) then
      vim.api.nvim_buf_delete(buf2, { force = true })
    end
    state._reset()
    buffer._tab_buffers = {}
  end)

  it("on_tab_leave hides listed buffers and caches them", function()
    buffer.on_tab_leave()

    -- Buffer 1 was listed, should be hidden now
    assert.is_false(vim.api.nvim_get_option_value("buflisted", { buf = buf1 }))
    -- Buffer 2 was unlisted, should remain hidden
    assert.is_false(vim.api.nvim_get_option_value("buflisted", { buf = buf2 }))

    -- Cache for initial_tab should have buffer 1 but not 2
    local cached = buffer._tab_buffers[initial_tab]
    assert.is_not_nil(cached)
    local found1, found2 = false, false
    for _, b in ipairs(cached) do
      if b == buf1 then
        found1 = true
      end
      if b == buf2 then
        found2 = true
      end
    end
    assert.is_true(found1)
    assert.is_false(found2)
  end)

  it("on_tab_enter un-hides buffers from cache", function()
    -- Manually populate cache for initial_tab with buf2 (even though it's currently unlisted)
    buffer._tab_buffers[initial_tab] = { buf2 }

    buffer.on_tab_enter()

    -- Buffer 2 was in cache, should be listed now
    assert.is_true(vim.api.nvim_get_option_value("buflisted", { buf = buf2 }))
    -- Buffer 1 was not in cache, shouldn't be affected by on_tab_enter unhiding
    -- It started as true, it remains true
    assert.is_true(vim.api.nvim_get_option_value("buflisted", { buf = buf1 }))
  end)

  it("on_tab_closed removes tab from cache", function()
    buffer._tab_buffers[1] = { buf1 }
    buffer._tab_buffers[2] = { buf2 }

    buffer.on_tab_closed(1)

    assert.is_nil(buffer._tab_buffers[1])
    assert.is_not_nil(buffer._tab_buffers[2])
  end)

  it("rebuild_visibility_from_windows builds per-tab cache from window state", function()
    -- Simulate post-session-restore state:
    --   tab1 (dashboard): window with unnamed buffer only
    --   tab2 (project):   window with a named file buffer
    -- After rebuild:
    --   _tab_buffers[tab1] = []       (no file buffers)
    --   _tab_buffers[tab2] = [named]
    --   named buffer is buflisted=false (hidden, not in current tab)
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local named = vim.fn.bufadd(tmp .. "/file.txt")
    vim.fn.bufload(named)
    vim.api.nvim_set_option_value("buflisted", true, { buf = named })
    vim.api.nvim_set_option_value("buftype", "", { buf = named })

    -- Open a new tab and put named buffer in its window
    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_win_set_buf(0, named)

    -- Switch back to tab1 (dashboard/current tab has unnamed buf only)
    vim.api.nvim_set_current_tabpage(initial_tab)

    -- All caches are empty (simulating just-cleared state)
    buffer._tab_buffers = {}

    buffer.rebuild_visibility_from_windows()

    -- tab1 cache should have no named file-buffers (dashboard has only unnamed buf)
    local tab1_bufs = buffer._tab_buffers[initial_tab] or {}
    local found_named_in_tab1 = false
    for _, b in ipairs(tab1_bufs) do
      if b == named then
        found_named_in_tab1 = true
      end
    end
    assert.is_false(found_named_in_tab1)

    -- tab2 cache should contain the named buffer
    local tab2_bufs = buffer._tab_buffers[tab2] or {}
    local found_named_in_tab2 = false
    for _, b in ipairs(tab2_bufs) do
      if b == named then
        found_named_in_tab2 = true
      end
    end
    assert.is_true(found_named_in_tab2)

    -- named buffer must be hidden (not in current tab=tab1)
    assert.is_false(vim.api.nvim_get_option_value("buflisted", { buf = named }))

    -- cleanup: capture tab number before buf_delete, which may auto-close the tab
    local tab2_nr = vim.api.nvim_tabpage_get_number(tab2)
    vim.api.nvim_buf_delete(named, { force = true })
    vim.fn.delete(tmp, "rf")
    pcall(vim.cmd, "tabclose " .. tab2_nr)
  end)

  it("rebuild_visibility_from_windows skips on_tab_leave capture across all tabs", function()
    -- Regression: without rebuild, on_tab_leave from the first tab captures ALL
    -- listed buffers (including other projects'), starving every other tab.
    -- After rebuild, on_tab_leave from tab1 captures only tab1's own files (none for
    -- dashboard tab), so each project tab can restore its own buffers independently.
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local named = vim.fn.bufadd(tmp .. "/file.txt")
    vim.fn.bufload(named)
    vim.api.nvim_set_option_value("buflisted", true, { buf = named })
    vim.api.nvim_set_option_value("buftype", "", { buf = named })

    vim.cmd("tabnew")
    local tab2 = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_win_set_buf(0, named)
    vim.api.nvim_set_current_tabpage(initial_tab)

    buffer._tab_buffers = {}
    buffer.rebuild_visibility_from_windows()

    -- Simulate user leaving tab1 (dashboard) to switch to tab2
    buffer.on_tab_leave()

    -- named must still be hidden (tab1's cache had no named files → nothing was restored)
    assert.is_false(vim.api.nvim_get_option_value("buflisted", { buf = named }))

    -- Simulate entering tab2: named buffer should be restored
    vim.api.nvim_set_current_tabpage(tab2)
    buffer.on_tab_enter()
    assert.is_true(vim.api.nvim_get_option_value("buflisted", { buf = named }))

    -- cleanup: capture tab number before buf_delete, which may auto-close the tab
    local tab2_nr = vim.api.nvim_tabpage_get_number(tab2)
    vim.api.nvim_buf_delete(named, { force = true })
    vim.fn.delete(tmp, "rf")
    pcall(vim.cmd, "tabclose " .. tab2_nr)
  end)
end)
