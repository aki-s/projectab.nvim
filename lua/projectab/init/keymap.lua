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
    "<Cmd>ProjecTab reorganize<CR>",
    { desc = "ProjecTab: Reorganize tabs and buffers" }
  )
  safe_map("n", "<leader><TAB>F", "<Plug>(projectab-reorganize)", { desc = "ProjecTab: Reorganize tabs and buffers" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-restore)",
    "<Cmd>ProjecTab restore<CR>",
    { desc = "ProjecTab: Restore all projects" }
  )
  safe_map("n", "<leader><TAB>R", "<Plug>(projectab-restore)", { desc = "ProjecTab: Restore all projects" })

  vim.keymap.set("n", "<Plug>(projectab-save)", "<Cmd>ProjecTab save<CR>", { desc = "ProjecTab: Save all projects" })
  safe_map("n", "<leader><TAB>S", "<Plug>(projectab-save)", { desc = "ProjecTab: Save all projects" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-cache-clear)",
    "<Cmd>ProjecTab cache-clear<CR>",
    { desc = "ProjecTab: Clear cache" }
  )
  safe_map("n", "<leader><TAB>c", "<Plug>(projectab-cache-clear)", { desc = "ProjecTab: Clear cache" })

  -- TODO: delete keybinding for 'projectab-list'
  vim.keymap.set("n", "<Plug>(projectab-list)", "<Cmd>ProjecTab list<CR>", { desc = "ProjecTab: List projects" })
  safe_map("n", "<leader><TAB>l", "<Plug>(projectab-list)", { desc = "ProjecTab: List projects" })

  vim.keymap.set("n", "<Plug>(projectab-pick)", "<Cmd>ProjecTab pick_project<CR>", { desc = "ProjecTab: Pick project" })
  safe_map("n", "<leader><TAB>p", "<Plug>(projectab-pick)", { desc = "ProjecTab: Pick project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-restore-project)",
    "<Cmd>ProjecTab restore-project<CR>",
    { desc = "ProjecTab: Restore a project" }
  )
  safe_map("n", "<leader><TAB>r", "<Plug>(projectab-restore-project)", { desc = "ProjecTab: Restore a project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-save-project)",
    "<Cmd>ProjecTab save-project<CR>",
    { desc = "ProjecTab: Save current project" }
  )
  safe_map("n", "<leader><TAB>s", "<Plug>(projectab-save-project)", { desc = "ProjecTab: Save current project" })

  -- Navigation commands
  vim.keymap.set(
    "n",
    "<Plug>(projectab-bnext)",
    "<Cmd>ProjecTab bnext<CR>",
    { desc = "ProjecTab: Next buffer in project" }
  )
  safe_map("n", "<leader><TAB>]", "<Plug>(projectab-bnext)", { desc = "ProjecTab: Next buffer in project" })

  vim.keymap.set(
    "n",
    "<Plug>(projectab-bprevious)",
    "<Cmd>ProjecTab bprevious<CR>",
    { desc = "ProjecTab: Previous buffer in project" }
  )
  safe_map("n", "<leader><TAB>[", "<Plug>(projectab-bprevious)", { desc = "ProjecTab: Previous buffer in project" })
end

return M
