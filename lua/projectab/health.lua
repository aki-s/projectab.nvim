--- @class ProjectabHealthModule
local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local info = health.info or health.report_info
local warn = health.warn or health.report_warn
local err = health.error or health.report_error

-- Endpoint for standard Neovim plugin, to be called as `:checkhealth projectab`.
function M.check()
  start("projectab.nvim Environment")
  if vim.fn.has("nvim-0.11.6") == 1 then
    ok("Neovim version is >= 0.11.6")
  else
    err("Neovim version must be >= 0.11.6")
  end

  local has_config, config_mod = pcall(require, "projectab.config")
  ---@cast config_mod ProjectabConfigModule
  if not has_config then
    err("Failed to load projectab.config")
    return
  else
    ok("Configuration loaded successfully.")
  end

  local config = config_mod.values

  start("projectab.nvim Integrations")
  if config.integrations.project_nvim then
    local has_plugin, _ = pcall(require, "project_nvim")
    if has_plugin then
      ok("`project.nvim` is installed and loaded")
    else
      warn("`integrations.project_nvim` is enabled but `project.nvim` cannot be loaded")
    end
  else
    info("`project_nvim` integration is disabled")
  end

  if config.integrations.bufferline.enabled then
    local has_plugin, _ = pcall(require, "bufferline")
    if has_plugin then
      ok("`bufferline.nvim` is installed and loaded")
    else
      warn("`integrations.bufferline` is enabled but `bufferline.nvim` cannot be loaded")
    end
  else
    info("`bufferline` integration is disabled")
  end

  if config.integrations.snacks.enabled then
    local has_plugin, _ = pcall(require, "snacks")
    if has_plugin then
      ok("`snacks` is installed and loaded")
    else
      warn("`integrations.snacks.enabled` is enabled but `snacks` cannot be loaded")
    end
  else
    info("`snacks` integration is disabled")
  end

  start("projectab.nvim Persistence")
  if config.project.persistence.enabled then
    local persistence = require("projectab.persistence")
    local data_dir = persistence.get_data_dir()
    if vim.fn.isdirectory(data_dir) == 1 then
      ok(string.format("Persistence directory exists: `%s`", data_dir))
      local file = io.open(data_dir .. "/.health_check", "w")
      if file then
        file:write("test")
        file:close()
        os.remove(data_dir .. "/.health_check")
        ok(string.format("Persistence directory is writable: `%s`", data_dir))
      else
        err(string.format("Persistence directory is NOT writable: `%s`", data_dir))
      end
    else
      err(string.format("Persistence directory does NOT exist: `%s`", data_dir))
      -- Check if we can create it
      local ok_mkdir, _ = pcall(vim.fn.mkdir, data_dir, "p")
      if ok_mkdir then
        warn("Persistence directory could be successfully created but didn't exist yet.")
      else
        err("Cannot create persistence directory!")
      end
    end
  else
    info("Persistence is disabled")
  end
end

return M
