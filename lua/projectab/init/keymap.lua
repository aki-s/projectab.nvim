--- Keymap setup for projectab.nvim
--- @class ProjectabInitKeymap
local M = {}

--- Register keymaps
function M.setup()
  -- Helper to set keymaps only if not already mapped by the user
  local function safe_map(mode, lhs, rhs, map_opts)
    local existing = vim.fn.maparg(lhs, mode)
    if existing == "" then
      vim.keymap.set(mode, lhs, rhs, map_opts)
    end
  end

  -- <Plug> mappings for LazyVim or other framework users
  -- Default mapped to <Plug> so users can just disable it by unmapping or mapping something else
  vim.keymap.set(
    "n",
    "<Plug>(projectab-reorganize)",
    "<Cmd>Projectab ps-reorganize<CR>",
    { desc = "Projectab: Reorganize tabs and buffers" }
  )
  safe_map("n", "<leader><TAB>F", "<Plug>(projectab-reorganize)", { desc = "Projectab: Reorganize tabs and buffers" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-restore)",
    "<Cmd>Projectab ps-restore<CR>",
    { desc = "Projectab: Restore all projects" }
  )
  safe_map("n", "<leader><TAB>R", "<Plug>(projectab-restore)", { desc = "Projectab: Restore all projects" })

  vim.keymap.set("n", "<Plug>(projectab-save)", "<Cmd>Projectab ps-save<CR>", { desc = "Projectab: Save all projects" })
  safe_map("n", "<leader><TAB>S", "<Plug>(projectab-save)", { desc = "Projectab: Save all projects" })

  vim.keymap.set("n", "<Plug>(projectab-quit)", "<Cmd>Projectab ps-quit<CR>", { desc = "Projectab: Save all projects and quit" })
  safe_map("n", "<leader><TAB>q", "<Plug>(projectab-quit)", { desc = "Projectab: Save all projects and quit" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-cache-clear)",
    "<Cmd>Projectab ps-clear-root-cache<CR>",
    { desc = "Projectab: Clear cache" }
  )
  safe_map("n", "<leader><TAB>c", "<Plug>(projectab-cache-clear)", { desc = "Projectab: Clear cache" })

  vim.keymap.set("n", "<Plug>(projectab-list)", "<Cmd>Projectab ps-list<CR>", { desc = "Projectab: List projects" })
  safe_map("n", "<leader><TAB>l", "<Plug>(projectab-list)", { desc = "Projectab: List projects" })

  vim.keymap.set("n", "<Plug>(projectab-pick)", "<Cmd>Projectab p-pick<CR>", { desc = "Projectab: Pick project" })
  safe_map("n", "<leader><TAB>p", "<Plug>(projectab-pick)", { desc = "Projectab: Pick project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-save-project)",
    "<Cmd>Projectab p-save<CR>",
    { desc = "Projectab: Save current project" }
  )
  safe_map("n", "<leader><TAB>s", "<Plug>(projectab-save-project)", { desc = "Projectab: Save current project" })

  -- Navigation commands
  vim.keymap.set(
    "n",
    "<Plug>(projectab-bnext)",
    "<Cmd>Projectab p-bnext<CR>",
    { desc = "Projectab: Next buffer in project" }
  )
  safe_map("n", "<leader><TAB>]", "<Plug>(projectab-bnext)", { desc = "Projectab: Next buffer in project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-bprevious)",
    "<Cmd>Projectab p-bprev<CR>",
    { desc = "Projectab: Previous buffer in project" }
  )
  safe_map("n", "<leader><TAB>[", "<Plug>(projectab-bprevious)", { desc = "Projectab: Previous buffer in project" })
end

return M
