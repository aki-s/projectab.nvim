local M = {}

local log = require("projectab.log")

--- @param tabnr? integer
local function serialize_window_layout(tabnr)
  local function walk(layout)
    local t = layout[1]
    if t == "row" or t == "col" then
      return { type = t, children = walk(layout[2]) }
    end
    if t == "leaf" then
      return { type = t, winid = layout[2] }
    end
    if type(t) == "table" then
      local children = {}
      for i = 1, #layout do
        table.insert(children, walk(layout[i]))
      end
      return children
    end
    log.debug_ctx("serialize_window_layout: impl error") -- TODO: create error level of logging method
  end
  return walk(vim.fn.winlayout(tabnr))
end

--- @class WinInfo
--- @field win_id integer
--- @field bufname string fullpath of filename
--- @field cursor integer[] position in buffer

--- @class Layout
--- @field type ("row" | "col" | "leaf")
--- @field bufname? string if leaf
--- @field cursor? integer[] if leaf
--- @field children Layout[]

--- @class TabWinsInfo
--- @field layout
--- @field wins WinInfo[]
--- @field cwd dir for the tab

--- @param tabnr? integer
--- @return string JSON format of TabWinsInfo
function M.export_tab_raw(tabnr)
  local wins = vim.api.nvim_tabpage_list_wins(tabnr)

  local win_infos = {}
  for _, win_id in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win_id)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      table.insert(win_infos, {
        winid = win_id,
        bufname = name,
        cursor = cursor,
      })
    end
  end

  local data = {
    layout = serialize_window_layout(tabnr),
    wins = win_infos,
    cwd = vim.loop.cwd(),
  }

  return vim.json.encode(data)
end

--- @param layout Layout
--- @param win_info_iter WinInfo func of win
local function restore_layout(layout, win_info_iter)
  log.debug_ctx(vim.inspect(layout))

  if layout.type == "leaf" then
    local info = win_info_iter()
    if not info then
      return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(info.bufname))
    vim.api.nvim_win_set_cursor(0, info.cursor)
    return
  end

  local first = true
  for _, child in ipairs(layout.children) do
    if first then
      first = false
      restore_layout(child, win_info_iter)
    else
      if layout.type == "row" then
        vim.cmd("vsplit")
      else
        vim.cmd("split")
      end
      restore_layout(child, win_info_iter)
    end
  end
end

function M.import_tab_from_json(json)
  local ok, data = pcall(vim.json.decode, json)
  if not ok or type(data) ~= "table" then
    log.debug_ctx("invalid layout json")
    return
  end

  if data.cwd then
    vim.cmd("cd " .. vim.fn.fnameescape(data.cwd))
  end

  local i = 0
  local function iter()
    i = i + 1
    return data.wins[i]
  end

  vim.cmd("tabnew")
  restore_layout(data.layout, iter)
end

--- @class NeovideCloneOpts
--- @field tab_id integer id of tab

--- Clone all the windows and its bound buffer of the specified tab_id using Neovide
---
--- @param opts? NeovideCloneOpts
function M.tab_clone_wins(opts)
  if os.execute("neovide --version") ~= 0 then
    vim.notify("neovide is not found", vim.log.levels.WARN)
  end

  opts = opts or {}
  if not opts.tab_id then
    opts.tab_id = vim.api.nvim_get_current_tabpage()
  end
  local json = M.export_tab_raw(opts.tab_id)

  local cache_dir = vim.fn.stdpath("cache") .. "/projectab"
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, "p")
  end
  local tmp_filename = cache_dir .. "/neovide_wins.lua"
  local file = io.open(tmp_filename, "w+")
  file:write(string.format("require('projectab.experiments.neovide').import_tab_from_json('%s')", json))
  file:close()
  local cmd = {
    "neovide",
    --    "--reuse-instance",
    --    "--new-window",
    "--",
    --    "--noplugin", -- If new instance of neovide is used, using '--noplugin' make loading module fail.
    "-n",
    "-i",
    "NONE",
    "-S",
    tmp_filename,
  }
  local on_exit = function(obj)
    print(obj.code)
    print(obj.signal)
    print(obj.stdout)
    print(obj.stderr)
  end
  vim.system(cmd, { text = true, detach = true }, on_exit)

  vim.fn.jobstart(cmd, { detach = true })
end

return M
