--- @class ProjectabUiWinbarModule
local M = {}

local buffer = require("projectab.buffer")
local log = require("projectab.log")

--- Update winbar for the current buffer
--TODO:: add more detailed doc about why this method is required and what is done by this method.
--TODO:: enable to work well with "bufferline.nvim"
function M.update()
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname ~= "" then
    vim.wo.winbar = ""
    return
  end

  local project_root = buffer.resolve_project_root(bufnr)
  log.debug_ctx(string.format("project_root=%s, cwd=%s", project_root, vim.fn.getcwd()))
  if project_root then
    vim.wo.winbar = "[projectab]" .. project_root
    return
  end
  local display = project_root or vim.fn.getcwd()
  vim.wo.winbar = display .. "/"
end

return M
