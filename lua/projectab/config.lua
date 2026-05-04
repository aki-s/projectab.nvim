--- Configuration module for projectab.nvim
--- Defines defaults and merges user options.
--- @class ProjectabConfigModule
--- @field values ProjectabConfig
local M = {}

--- @class ProjectabConfigDebug
--- @field file boolean Write debug logs to stdpath("cache")/projectab/projectab.log (symlink)
--- @field notify boolean Show debug logs via vim.notify

--- @class ProjectabConfigPersistence
--- @field dir string|nil Override data directory (default: stdpath("data") .. "/projectab")
--- @field enabled boolean Enable persistence (save/restore project states)

--- @class ProjectabConfigDashboard
--- @field enabled boolean Enable the standalone startup dashboard
--- @field header string[] Lines of text for the header

--- @class ProjectabConfigUi
--- @field dashboard ProjectabConfigDashboard

--- @class ProjectabConfigProject
--- @field root_markers string[] Patterns to detect project root directories
--- @field excluded_root_dirs string[] Directory paths to exclude from detection
--- @field persistence ProjectabConfigPersistence
--- @field directory_picker_func fun(opts: {prompt: string, default?: string, completion?: string | (fun(input: string): string[])}, callback: fun(input: string?))
-- https://neovim.io/doc/user/lua/#vim.ui.input()

--- @class ProjectabConfigSnacks
--- @field enabled boolean Use snacks.nvim for project picking integration
--- @field pickerProjectsOpts table|nil Extra options forwarded to snacks.picker.projects() (e.g. recent, max_depth, dev)

--- @class ProjectabConfigBufferline
--- @field enabled boolean Update bufferline.nvim groups on tab enter-

--- @class ProjectabConfigIntegrations
--- @field bufferline ProjectabConfigBufferline
--- @field project_nvim boolean Use project.nvim API for root detection (fallback)
--- @field snacks ProjectabConfigSnacks

--- @class ProjectabConfig
--- @field ui ProjectabConfigUi
--- @field project ProjectabConfigProject
--- @field debug ProjectabConfigDebug
--- @field integrations ProjectabConfigIntegrations

--- @type ProjectabConfig
local defaults = {
  ui = {
    dashboard = {
      enabled = false,
      header = { "Projectab" },
    },
  },
  project = {
    root_markers = {
      -- VCS
      ".bzr",
      ".git",
      ".hg",
      ".jj",
      ".svn",
      "_darcs",
      -- tool
      ".mise",
      ".mise.toml",
      ".python-version",
      ".tool-versions",
      "mise.toml",
      -- Golang
      "go.mod",
      -- Java
      "build.gradle",
      "build.xml", -- Ant
      "pom.xml", -- Maven
      -- NodeJS
      "package.json",
      -- Python
      "pyproject.toml",
      "uv.toml",
      -- Ruby
      "Gemfile",
      -- Rust
      "Cargo.toml",
    },
    excluded_root_dirs = {},
    persistence = {
      enabled = true,
      dir = nil, -- defaults to stdpath("data") .. "/projectab"
    },
    directory_picker_func = vim.ui.input,
  },
  debug = {
    file = false,
    notify = false,
  },
  integrations = {
    project_nvim = false,
    bufferline = {
      enabled = false,
    },
    snacks = {
      enabled = false,
      pickerProjectsOpts = {},
    },
  },
}

--- @type ProjectabConfig
M.values = vim.deepcopy(defaults)

--- Merge user options into config.
--- @param opts table|nil User-provided options
function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- Reset config to defaults (for testing).
function M._reset()
  M.values = vim.deepcopy(defaults)
end

return M
