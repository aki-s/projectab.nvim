# ProjecTab.nvim

[![CI](https://github.com/aki-s/ProjecTab.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/aki-s/ProjecTab.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Neovim plugin to manage projects via tabs efficiently.

**"1 project = 1 tab"** — Automatically routes buffers to their project's dedicated tab,
with the tab's working directory (`tcd`) set to the project root.

## Features

- Automatic buffer routing: opening any file lands you in the correct project tab
- Native `tcd` integration — no global `cd`, no LSP/picker disruption
- Session save/restore: project tabs and buffers survive Neovim restarts
- Root detection cache (O(1) on hot path, `BufEnter` safe)
- Optional integrations: snacks.nvim picker, bufferline.nvim groups, project.nvim detection
- Built-in tabline (falls back when bufferline is not in use)
- `:checkhealth projectab` support

## Requirements

- Neovim >= v0.11.6

## Installation

### lazy.nvim

```lua
{
  "aki-s/ProjecTab.nvim",
  event = "VeryLazy",
  opts = {
    -- Optional: override default project root markers
    project = {
      root_markers = {
        ".git", ".hg", ".jj",
        "go.mod", "package.json", "pyproject.toml", "Cargo.toml",
      },
      persistence = {
        enabled = true, -- save/restore project sessions
      },
    },

    -- Optional integrations (all disabled by default)
    integrations = {
      snacks = { enabled = false },   -- use snacks.picker.projects for project picking
      bufferline = false,             -- update bufferline groups on TabEnter
      project_nvim = false,           -- use project.nvim for root detection
    },
  },
}
```

### Minimal (no persistence, no integrations)

```lua
{
  "aki-s/ProjecTab.nvim",
  event = "VeryLazy",
  opts = {},
}
```

## Optional Dependencies

All integrations are opt-in and gracefully disabled when the plugin is not installed:

| Plugin | Purpose |
|--------|---------|
| [folke/snacks.nvim](https://github.com/folke/snacks.nvim) | `snacks.picker.projects` for project selection |
| [folke/persistence.nvim](https://github.com/folke/persistence.nvim) | Session restore compatible (listens to `SessionLoadPost`) |
| [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | Per-project buffer grouping in the tabline |
| [ahmedkhalf/project.nvim](https://github.com/ahmedkhalf/project.nvim) | Alternative project root detection |

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:ProjecTab open <path>` | Open a project in its own tab (or switch to it) |
| `:ProjecTab pick` | Interactive project picker |
| `:ProjecTab list` | List all registered projects and their tab IDs |
| `:ProjecTab save` | Save all project sessions |
| `:ProjecTab restore` | Restore all project sessions |
| `:ProjecTab cache-clear` | Clear the root detection cache |
| `:ProjecTab reorganize` | Consolidate duplicate tabs, move misplaced buffers |
| `:checkhealth projectab` | Verify installation and integration status |

### Default Keymaps

| Key | Description |
|-----|-------------|
| `<leader><TAB>p` | Pick project |
| `<leader><TAB>S` | Save all projects |
| `<leader><TAB>R` | Restore all projects |
| `<leader><TAB>s` | Save current project |
| `<leader><TAB>r` | Restore a project |
| `<leader><TAB>c` | Clear root detection cache |
| `<leader><TAB>[` | Previous buffer in project |
| `<leader><TAB>]` | Next buffer in project |

Default keymaps are only set if not already mapped. All actions are also available
as `<Plug>` mappings for framework users (LazyVim, etc.).

### Public API

```lua
local projectab = require("projectab")

-- Open or switch to a project tab
projectab.open_project("/path/to/project")

-- Open project with a callback
require("projectab.session").open_project("/path/to/project", {
  callback = function(tab_id)
    -- runs after the tab is ready
  end,
})

-- Suspend routing during bulk buffer operations (e.g., custom session restore)
projectab.suspend()
-- ... bulk operations ...
projectab.resume()

-- Pick a project interactively
projectab.pick_project()

-- Inspect internal state (for debugging)
projectab._get_state()
```

## Health Check

```
:checkhealth projectab
```

Verifies Neovim version, configuration, integrations, and persistence directory.

## Development

### Run tests

```sh
make test
```

### Format code

```sh
make lint-fix
```

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for full development setup instructions.
