--- Keymap setup for projectab.nvim
--- @class ProjectabInitKeymap
local M = {}

--- @param cfg ProjectabConfigKeymapConfig
function M.setup(cfg)
  -- Declare <Plug> mappings for LazyVim or other framework users
  -- Default mapped to <Plug> so users can just disable it by unmapping or mapping something else
  local presetDefs = M.presetKeyDefs()
  for _, d in pairs(presetDefs) do
    vim.keymap.set("n", d.plug, d.cmd, d.opts)
  end

  -- NOTE:
  -- keymap defined at the end wins.
  -- This fact means declaring 'nifty' mapping at each plugin side
  -- is not handy for user if each plugin declare by itself.
  -- To resolve this problem, defining all keymaps at single point is necessary.
  --
  -- Define keymap for consolation below.
  if cfg.try_preset then
    for _, d in pairs(presetDefs) do
      vim.keymap.set("n", d.key, d.plug, d.opts)
    end
  end
end

---@class ProjectabWhichKeyOpts: vim.keymap.set.Opts
---@field desc? string

--- @class ProjectabPresetKeyDef
--- @field key string
--- @field plug string
--- @field cmd string
--- @field opts ProjectabWhichKeyOpts

--- master table of preset key definitions
--- @return ProjectabPresetKeyDef[] defs
function M.presetKeyDefs()
  -- NOTE:
  -- Some keymaps such as "<leader><Tab>l"" is set by
  -- defined LazyVim/lua/lazyvim/config/keymaps.lua@v15.15.0
  -- This means if you are using LazyVim, then those keys could be overridden by LazyVim.
  --
  -- mappings are declared in the asc order of 'plug'.
  return {
    {
      key = "<leader><Tab>]",
      plug = "<Plug>(projectab-p-bnext)",
      cmd = "<Cmd>Projectab p-bnext<CR>",
      opts = { desc = "Projectab: Next buffer in project" },
    },
    {
      key = "<leader><Tab>[",
      plug = "<Plug>(projectab-p-bprev)",
      cmd = "<Cmd>Projectab p-bprev<CR>",
      opts = { desc = "Projectab: Previous buffer in project" },
    },
    {
      key = "<leader><Tab>W",
      plug = "<Plug>(projectab-p-clone-wins)",
      cmd = "<Cmd>Projectab p-clone-wins<CR>",
      opts = { desc = "Projectab: Clone windows in new Neovide" },
    },
    {
      key = "<leader><Tab>p",
      plug = "<Plug>(projectab-p-pick)",
      cmd = "<Cmd>Projectab p-pick<CR>",
      opts = { desc = "Projectab: Pick project" },
    },
    {
      key = "<leader><Tab>s",
      plug = "<Plug>(projectab-p-save)",
      cmd = "<Cmd>Projectab p-save<CR>",
      opts = { desc = "Projectab: Save current project" },
    },
    {
      key = "<leader><Tab>c",
      plug = "<Plug>(projectab-ps-clear-root-cache)",
      cmd = "<Cmd>Projectab ps-clear-root-cache<CR>",
      opts = { desc = "Projectab: Clear cache" },
    },
    {
      key = "<leader><Tab>D",
      plug = "<Plug>(projectab-ps-dump)",
      cmd = "<Cmd>Projectab ps-dump<CR>",
      opts = { desc = "Projectab: Dump internal state for debugging" },
    },
    {
      key = "<leader><Tab>l",
      plug = "<Plug>(projectab-ps-list)",
      cmd = "<Cmd>Projectab ps-list<CR>",
      opts = { desc = "Projectab: List projects" },
    },
    {
      key = "<leader><Tab>Q",
      plug = "<Plug>(projectab-ps-quit)",
      cmd = "<Cmd>Projectab ps-quit<CR>",
      opts = { desc = "Projectab: Save all projects and quit" },
    },
    {
      key = "<leader><Tab>O",
      plug = "<Plug>(projectab-ps-reorganize)",
      cmd = "<Cmd>Projectab ps-reorganize<CR>",
      opts = { desc = "Projectab: Reorganize tabs and buffers" },
    },
    {
      key = "<leader><Tab>R",
      plug = "<Plug>(projectab-ps-restore)",
      cmd = "<Cmd>Projectab ps-restore<CR>",
      opts = { desc = "Projectab: Restore all projects" },
    },
    {
      key = "<leader><Tab>S",
      plug = "<Plug>(projectab-ps-save)",
      cmd = "<Cmd>Projectab ps-save<CR>",
      opts = { desc = "Projectab: Save all projects" },
    },
  }
end

return M
