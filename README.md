# Projectab.nvim

[![CI](https://github.com/aki-s/Projectab.nvim/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/aki-s/Projectab.nvim/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Neovim plugin to manage each project per tab.

A project is default to a Git root, but you can configure as you like.

## Key ideas (restraints to achieve `Projectab`)

- **"1 project = 1 tab"**
  - Each tab's root is defined with `tcd` (tab-local working directory).
- Each project lists only buffers belonging to the project.
  - Automatic buffer routing: opening any file lands you in the correct project tab

## Features

- Session save/restore: project tabs and buffers survive Neovim restarts
- Optional integrations:
  - [snacks.nvim](https://github.com/folke/snacks.nvim) picker
  - snacks.nvim dashboard
  - Experimental
    - [bufferline.nvim](https://github.com/akinsho/bufferline.nvim/) groups
    - [project.nvim](https://github.com/ahmedkhalf/project.nvim) detection
- Other plugins which co-exists:
  - [folke/persistence.nvim](https://github.com/folke/persistence.nvim) (Automatic buffer routing handles this natively without explicit dependency)
- Built-in tabline (falls back when bufferline is not in use)
- `:checkhealth projectab` support

## Requirements

- Neovim >= v0.11.6

## Installation

### Minimal (no persistence, no integrations)

```lua
{
  "aki-s/projectab.nvim",
  event = "VeryLazy",
  opts = {},
}
```

### lazy.nvim

```lua
{
  "aki-s/projectab.nvim",
  event = "VeryLazy",
  dependencies = {
    {
      "folke/snacks.nvim",
      optional = true,
    },
    {
      "akinsho/bufferline.nvim",
      optional = true,
    },
    {
      "ahmedkhalf/project.nvim",
      optional = true,
    },
  },
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
      snacks     = { enabled = false },  -- use snacks.picker.projects for project picking
      bufferline = { enabled = false },  -- update bufferline groups on TabEnter
      project_nvim = false,              -- use project.nvim for root detection
    },
  },
}
```

## Optional Dependencies

All integrations are opt-in and gracefully disabled when the plugin is not installed:

| Plugin | Purpose |
|--------|---------|
| [folke/snacks.nvim](https://github.com/folke/snacks.nvim) | `snacks.picker.projects` for project selection + dashboard section |
| [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | Per-project buffer grouping in the tabline |
| [ahmedkhalf/project.nvim](https://github.com/ahmedkhalf/project.nvim) | Alternative project root detection |

## Usage

### Commands

All commands are subcommands of `:Projectab`. Tab completion is supported.

**Single-project (`p-` prefix):**

| Command | Description |
|---------|-------------|
| `:Projectab p-open <path>` | Open a project in its own tab (or switch to it) |
| `:Projectab p-pick` | Interactive project picker |
| `:Projectab p-close` | Save and close the current project tab |
| `:Projectab p-save` | Save the current project session |
| `:Projectab p-restore <path>` | Restore a single project from its saved state |
| `:Projectab p-bnext` | Next buffer in the current project |
| `:Projectab p-bprev` | Previous buffer in the current project |

**Multi-project (`ps-` prefix):**

| Command | Description |
|---------|-------------|
| `:Projectab ps-list` | List all registered projects and their tab IDs |
| `:Projectab ps-save` | Save all project sessions |
| `:Projectab ps-restore` | Restore all project sessions |
| `:Projectab ps-clear-root-cache` | Clear the root detection cache |
| `:Projectab ps-reorganize` | Consolidate duplicate tabs, move misplaced buffers |
| `:Projectab ps-close-empty-tab` | Close tabs with only unnamed/empty buffers |
| `:Projectab ps-toggle-routing` | Toggle automatic buffer routing on/off |
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
| `<leader><TAB>F` | Reorganize tabs and buffers (move a buffer if it is displayed in the other project. Unify duplicate project split across tabs if it exists) |
| `<leader><TAB>l` | List projects |
| `<leader><TAB>[` | Previous buffer in project |
| `<leader><TAB>]` | Next buffer in project |

Default keymaps are only set if not already mapped. All actions are also available
as `<Plug>` mappings for framework users (LazyVim, etc.).

### Public API

```lua
local projectab = require("projectab")

-- Open or switch to a project tab
require("projectab.session").project_open("/path/to/project")

-- Open project with a callback (runs after the tab is ready)
require("projectab.session").project_open("/path/to/project", {
  callback = function(tab_id) end,
})

-- Suspend routing during bulk buffer operations (e.g., custom session restore)
projectab.suspend()
-- ... bulk operations ...
projectab.resume()

-- Pick a project interactively
require("projectab.ui.pick").project_pick()

-- Inspect internal state (for debugging)
projectab._get_state()
```

## snacks.nvim Integration

Projectab integrates with [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
for two features: a **project picker** and a **dashboard section**.

### Project Picker

Enable `integrations.snacks.enabled = true` to add a snacks-powered option to
the `:Projectab p-pick` menu. It opens
[`snacks.picker.projects`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#projects),
selects a project, calls `project_open()`, and then launches `snacks.picker.files()`
in the new project tab.

```lua
{
  "aki-s/projectab.nvim",
  dependencies = { { "folke/snacks.nvim", optional = true } },
  opts = {
    integrations = {
      snacks = {
        enabled = true,
        -- Forwarded to snacks.picker.projects()
        -- ref. https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#projects
        pickerProjectsOpts = {
          recent    = true,
          max_depth = 3,
          dev = {
            "~/`<your-path-to-repo-root>`/github.com/",
            "~/`<your-path-to-repo-root>`/gitlab.com/",
          },
        },
      },
    },
  },
}
```

### Dashboard Section

`require("projectab.integrations.snacks").dashboard_section(opts)` returns a
generator function compatible with the
[snacks.nvim dashboard](https://github.com/folke/snacks.nvim/blob/main/docs/dashboard.md)
`sections` list. It renders Projectab's project sessions as selectable items;
selecting one calls `session.project_restore()`.

```lua
-- Inside your snacks.nvim opts:
{
  "folke/snacks.nvim",
  dependencies = { { "aki-s/projectab.nvim" } },
  opts = {
    dashboard = {
      sections = {
        -- ... other sections ...
        {
          pane    = 1,
          height  = 10,
          indent  = 2,
          padding = 1,
          title   = "Projectab",
          -- Generator: returns snacks.dashboard.Item[] from Projectab session
          require("projectab.integrations.snacks").dashboard_section({ limit = 10 }),
        },
        -- Optional: keyed action to restore all recent projects
        {
          pane   = 1,
          key    = "R",
          title  = "Projectab: restore all projects (up to 12)",
          action = function()
            require("projectab.session").projects_restore({ limit = 12 })
          end,
        },
      },
    },
  },
}
```

`dashboard_section` options:

| Field    | Type               | Default | Description                                       |
|----------|--------------------|---------|---------------------------------------------------|
| `limit`  | `number`           | `5`     | Maximum number of projects to show                |
| `action` | `fun(dir: string)` | `nil`   | Override item action (default: `project_restore`) |

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
