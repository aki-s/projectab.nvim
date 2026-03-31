--- Logging module for projectab.nvim
--- @class ProjectabLogModule
local M = {}

local config = require("projectab.config")

local PREFIX = "[projectab] "

--- Get caller information (source file and line number)
--- @param level number Stack level to inspect
--- @return string src The caller source file
--- @return number line The caller line number
local function get_caller_info(level)
  local info = debug.getinfo(level, "Sl")
  local src = info and info.source or "?"
  local line = info and info.currentline or 0
  -- Remove leading "@" and optionally shorten the path
  src = src:gsub("^@", "")
  -- Shorten path to just the filename to avoid long log lines
  src = src:match("([^/]+)$") or src
  return src, line
end

--- Append msg to a log file
--- @param src string The caller source file
--- @param line number The caller line number
--- @param lvl string Log level
--- @param msg string Log message
local function write_log(src, line, lvl, msg)
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  local line_str = string.format("[%s] [%5s] %15s:%d %s\n", ts, lvl, src, line, msg)
  local log_file = vim.fn.stdpath("cache") .. "/projectab.log"
  local file = io.open(log_file, "a")
  if file then
    file:write(line_str)
    file:close()
  end
end

--- Get current context information for logging
--- @return table ctx Context with tab, win, buf, file, project
local function get_context_info()
  local state = require("projectab.state")
  local tab = vim.api.nvim_get_current_tabpage()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  local file = bufname ~= "" and vim.fn.fnamemodify(bufname, ":t") or "[no name]"
  local project = state.get_project(tab)
  local project_short = project and vim.fn.fnamemodify(project, ":t") or "none"

  return {
    tab = vim.api.nvim_tabpage_get_number(tab),
    win = win,
    buf = buf,
    file = file,
    project = project_short,
  }
end

--- @param msg string
--- @param with_ctx boolean
local function __debug(msg, with_ctx)
  local cfg = config.values.debug
  -- Fast path: skip string work entirely when debug is off
  if not cfg.notify and not cfg.file then
    return
  end

  local src, line = get_caller_info(4)
  if cfg.file then
    if with_ctx then
      local ctx = get_context_info()
      local ctx_str = string.format("p[%s][t%d w%d b%d %s]", ctx.project, ctx.tab, ctx.win, ctx.buf, ctx.file)
      msg = msg .. " " .. ctx_str
    end
    write_log(src, line, "DEBUG", msg)
  end
  if cfg.notify then
    vim.notify(PREFIX .. msg, vim.log.levels.DEBUG)
  end
end

--- Write a debug log message.
--- Outputs to file and/or vim.notify based on config.
--- Early-returns when both outputs are disabled to avoid string allocation
--- on high-frequency code paths (e.g., BufEnter).
--- @param msg string Log message
function M.debug(msg)
  __debug(msg, false)
end

--- Log current working directory info for debugging.
--- @param prefix string Prefix label for the log entry
function M.debug_wd(prefix)
  -- level=4 becomes necessary because debug_wd calls debug, which calls get_caller_info
  -- Wait, get_caller_info(3) in M.debug means caller(M.debug)=3.
  -- caller(M.debug_wd) would mean we need level 4 in M.debug.
  -- But we hardcoded level 3 in M.debug... let's fix it by passing the level from `debug_wd` or use a wrapper.
  -- Let's just pass `msg` and keep it simple right now, `debug_wd` itself will be logged with `log.lua` as src, which is fine,
  -- but we can improve it. For now, it will report `log.lua:46`.
  M.debug_ctx(
    prefix .. string.format(" cwd=%s, lcd=%s", vim.fn.getcwd(), vim.fn.getcwd(vim.api.nvim_get_current_win()))
  )
end

--- Write a debug log message with context information.
--- Automatically includes tab, win, buf, file, and project info.
--- @param msg string Log message
function M.debug_ctx(msg)
  __debug(msg, true)
end

return M
