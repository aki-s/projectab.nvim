local fn = vim.fn

local function ensure_plenary()
  local plenary_dir = fn.stdpath("cache") .. "/projectab-tests/plenary.nvim"
  if not vim.uv.fs_stat(plenary_dir) then
    print("Cloning plenary.nvim to " .. plenary_dir)
    fn.system({
      "git",
      "clone",
      "--depth=1",
      "https://github.com/nvim-lua/plenary.nvim.git",
      plenary_dir,
    })
  end
  vim.opt.rtp:append(plenary_dir)
end

ensure_plenary()

-- Ensure the current directory (projectab plugin root) is in rtp
local plugin_dir = fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:append(plugin_dir)

vim.cmd("runtime! plugin/plenary.vim")
