--- Keymap setup for projectab.nvim
--- @class ProjectabInitKeymap
local M = {}

--- Register keymaps
---
--- keys are bound in ASCII code table.
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
    "<Plug>(projectab-ps-clear-root-cache)",
    "<Cmd>Projectab ps-clear-root-cache<CR>",
    { desc = "Projectab: Clear cache" }
  )
  safe_map("n", "<leader><TAB>c", "<Plug>(projectab-ps-clear-root-cache)", { desc = "Projectab: Clear cache" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-ps-dump)",
    "<Cmd>Projectab ps-dump<CR>",
    { desc = "Projectab: Dump internal state for debugging" }
  )
  safe_map(
    "n",
    "<leader><TAB>D",
    "<Plug>(projectab-ps-dump)",
    { desc = "Projectab: Dump internal state for debugging" }
  )

  vim.keymap.set(
    "n",
    "<Plug>(projectab-ps-quit)",
    "<Cmd>Projectab ps-quit<CR>",
    { desc = "Projectab: Save all projects and quit" }
  )
  safe_map("n", "<leader><TAB>Q", "<Plug>(projectab-ps-quit)", { desc = "Projectab: Save all projects and quit" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-ps-reorganize)",
    "<Cmd>Projectab ps-reorganize<CR>",
    { desc = "Projectab: Reorganize tabs and buffers" }
  )
  safe_map(
    "n",
    "<leader><TAB>F",
    "<Plug>(projectab-ps-reorganize)",
    { desc = "Projectab: Reorganize tabs and buffers" }
  )

  vim.keymap.set(
    "n",
    "<Plug>(projectab-ps-restore)",
    "<Cmd>Projectab ps-restore<CR>",
    { desc = "Projectab: Restore all projects" }
  )
  safe_map("n", "<leader><TAB>R", "<Plug>(projectab-ps-restore)", { desc = "Projectab: Restore all projects" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-ps-save)",
    "<Cmd>Projectab ps-save<CR>",
    { desc = "Projectab: Save all projects" }
  )
  safe_map("n", "<leader><TAB>S", "<Plug>(projectab-ps-save)", { desc = "Projectab: Save all projects" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-p-bnext)",
    "<Cmd>Projectab p-bnext<CR>",
    { desc = "Projectab: Next buffer in project" }
  )
  safe_map("n", "<leader><TAB>]", "<Plug>(projectab-p-bnext)", { desc = "Projectab: Next buffer in project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-p-bprev)",
    "<Cmd>Projectab p-bprev<CR>",
    { desc = "Projectab: Previous buffer in project" }
  )
  safe_map("n", "<leader><TAB>[", "<Plug>(projectab-p-bprev)", { desc = "Projectab: Previous buffer in project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-p-clone-wins)",
    "<Cmd>Projectab p-clone-wins<CR>",
    { desc = "Projectab: Clone windows in new Neovide" }
  )
  safe_map("n", "<leader><TAB>W", "<Plug>(projectab-p-clone-wins", { desc = "Projectab: Clone windows in new Neovide" })

  vim.keymap.set("n", "<Plug>(projectab-ps-list)", "<Cmd>Projectab ps-list<CR>", { desc = "Projectab: List projects" })
  safe_map("n", "<leader><TAB>l", "<Plug>(projectab-ps-list)", { desc = "Projectab: List projects" })

  vim.keymap.set("n", "<Plug>(projectab-p-pick)", "<Cmd>Projectab p-pick<CR>", { desc = "Projectab: Pick project" })
  safe_map("n", "<leader><TAB>p", "<Plug>(projectab-p-pick)", { desc = "Projectab: Pick project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-p-save)",
    "<Cmd>Projectab p-save<CR>",
    { desc = "Projectab: Save current project" }
  )
  safe_map("n", "<leader><TAB>s", "<Plug>(projectab-p-save)", { desc = "Projectab: Save current project" })
end

return M
