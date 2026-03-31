--- User commands setup for projectab.nvim
--- @class ProjectabInitCommand
local M = {}

local CMD_PROJECTS_CLEAR_ROOT_CACHE = "ps-clear-root-cache"
local CMD_PROJECTS_CLOSE_EMPTY_TAB = "ps-close-empty-tab"
local CMD_PROJECTS_LIST = "ps-list"
local CMD_PROJECTS_REORGANIZE = "ps-reorganize"
local CMD_PROJECTS_RESTORE = "ps-restore"
local CMD_PROJECTS_SAVE = "ps-save"
local CMD_PROJECTS_TOGGLE_ROUTING = "ps-toggle-routing"
local CMD_PROJECT_BNEXT = "p-bnext"
local CMD_PROJECT_BPREV = "p-bprev"
local CMD_PROJECT_CLOSE = "p-close"
local CMD_PROJECT_OPEN = "p-open"
local CMD_PROJECT_PICK = "p-pick"
local CMD_PROJECT_RESTORE = "p-restore"
local CMD_PROJECT_SAVE = "p-save"

--- Register user commands
function M.setup()
  local state = require("projectab.state")
  local notify = require("projectab.ui.notify")

  -- User commands
  vim.api.nvim_create_user_command("ProjecTab", function(cmd_opts)
    local subcmd = cmd_opts.fargs[1]
    if subcmd == CMD_PROJECTS_CLEAR_ROOT_CACHE then
      require("projectab.detect").projects_clear_root_cache()
      notify("Root detection cache cleared", vim.log.levels.INFO)
    elseif subcmd == CMD_PROJECTS_CLOSE_EMPTY_TAB then
      local cleanup = require("projectab.cleanup")
      local count = cleanup.projects_close_empty_tab()
      notify(string.format("Closed %d empty tab(s)", count), vim.log.levels.INFO)
    elseif subcmd == CMD_PROJECTS_LIST then
      local projects = state.list_projects()
      if next(projects) then
        local tbl = {}
        for root, tab_id in pairs(projects) do
          local name = vim.fn.fnamemodify(root, ":t")
          table.insert(tbl, string.format("  tab=%d  %s  (%s)", tab_id, name, root))
        end
        vim.notify(table.concat(tbl, "\n"), vim.log.levels.INFO)
      else
        notify("No project is opened", vim.log.levels.INFO)
      end
    elseif subcmd == CMD_PROJECTS_REORGANIZE then
      require("projectab.cleanup").projects_reorganize()
    elseif subcmd == CMD_PROJECTS_RESTORE then
      local session = require("projectab.session")
      session.projects_restore()
    elseif subcmd == CMD_PROJECTS_SAVE then
      local session = require("projectab.session")
      session.projects_save()
      notify("All projects saved", vim.log.levels.INFO)
    elseif subcmd == CMD_PROJECTS_TOGGLE_ROUTING then
      local ret = require("projectab.buffer").routing_toggle()
      notify(string.format("buffer routing is %q", ret))
    elseif subcmd == CMD_PROJECT_BNEXT then
      require("projectab.navigate").project_bnext()
    elseif subcmd == CMD_PROJECT_BPREV then
      require("projectab.navigate").project_bprevious()
    elseif subcmd == CMD_PROJECT_CLOSE then
      local tab_id = vim.api.nvim_get_current_tabpage()
      require("projectab.cleanup").project_close(tab_id)
    elseif subcmd == CMD_PROJECT_OPEN then
      local path = cmd_opts.fargs[2]
      if path then
        require("projectab.session").project_open(path)
      else
        notify(string.format("Usage: :ProjecTab %s <path>", CMD_PROJECT_OPEN), vim.log.levels.WARN)
      end
    elseif subcmd == CMD_PROJECT_PICK then
      require("projectab.ui.pick").project_pick()
    elseif subcmd == CMD_PROJECT_RESTORE then
      local path = cmd_opts.fargs[2]
      if path then
        local session = require("projectab.session")
        session.project_restore(vim.fn.expand(path))
      else
        notify(string.format("Usage: :ProjecTab %s <path>", CMD_PROJECT_RESTORE), vim.log.levels.WARN)
      end
    elseif subcmd == CMD_PROJECT_SAVE then
      local tab_id = vim.api.nvim_get_current_tabpage()
      local root = state.get_project(tab_id)
      if root then
        local session = require("projectab.session")
        session.project_save(root, tab_id)
        notify("Saved: " .. root, vim.log.levels.INFO)
      else
        notify("Current tab has no registered project", vim.log.levels.WARN)
      end
    else
      notify(
        string.format(
          "Subcommands: %s | %s | %s | %s | %s | %s | %s| %s | %s | %s <path> | %s | %s <path> | %s | %s",
          CMD_PROJECTS_CLEAR_ROOT_CACHE,
          CMD_PROJECTS_CLOSE_EMPTY_TAB,
          CMD_PROJECTS_LIST,
          CMD_PROJECTS_REORGANIZE,
          CMD_PROJECTS_RESTORE,
          CMD_PROJECTS_SAVE,
          CMD_PROJECTS_TOGGLE_ROUTING,
          CMD_PROJECT_BNEXT,
          CMD_PROJECT_BPREV,
          CMD_PROJECT_CLOSE,
          CMD_PROJECT_OPEN, -- arg
          CMD_PROJECT_PICK,
          CMD_PROJECT_RESTORE, -- arg
          CMD_PROJECT_SAVE
        ),
        vim.log.levels.INFO
      )
    end
  end, {
    nargs = "+",
    complete = function(_, line)
      local args = vim.split(line, "%s+")
      if #args <= 2 then
        return {
          CMD_PROJECTS_CLEAR_ROOT_CACHE,
          CMD_PROJECTS_CLOSE_EMPTY_TAB,
          CMD_PROJECTS_LIST,
          CMD_PROJECTS_REORGANIZE,
          CMD_PROJECTS_RESTORE,
          CMD_PROJECTS_SAVE,
          CMD_PROJECTS_TOGGLE_ROUTING,
          CMD_PROJECT_BNEXT,
          CMD_PROJECT_BPREV,
          CMD_PROJECT_CLOSE,
          CMD_PROJECT_OPEN,
          CMD_PROJECT_PICK,
          CMD_PROJECT_RESTORE,
          CMD_PROJECT_SAVE,
        }
      end
      if args[2] == CMD_PROJECT_OPEN or args[2] == CMD_PROJECT_RESTORE then
        return vim.fn.getcompletion(args[3] or "", "dir")
      end
      return {}
    end,
  })
end

return M
