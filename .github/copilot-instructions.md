# Copilot Instructions for projectab.nvim

## Overview

**projectab.nvim** is a Neovim plugin that manages projects via tabs efficiently. Each project gets its own dedicated tab with its working directory set to the project root.

## Build, Test, and Lint

### Prerequisites

- **Lua 5.1** (installed via `mise` – configured in `mise.toml`)
- **stylua** 2.3.1+ (Lua code formatter)
- **Neovim** (for testing via plenary.busted)

### Run all tests

```bash
make test
```

This runs the full test suite using `plenary.busted` via a headless Neovim instance.

### Run a single test file

```bash
nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/buffer_spec.lua { minimal_init = 'tests/minimal_init.lua' }"
```

### Format code

```bash
stylua .
```

Check formatting (lint mode):

```bash
stylua --check .
```

### CI/CD

The repo uses GitHub Actions for linting on push and pull requests (see `.github/workflows/lint.yml`).

## Architecture

### Module Structure

The plugin is organized as a collection of focused modules in `lua/projectab/`:

- **`init.lua`** – Plugin entry point; exports the public API (`open_project`, `pick_project`, `setup`)
- **`state.lua`** – Bidirectional O(1) state management (project root ↔ tab ID mapping)
- **`buffer.lua`** – Core allocation logic; routes buffers to their project's tab
- **`detect.lua`** – Project root detection via configurable patterns
- **`config.lua`** – Configuration defaults and merging
- **`log.lua`** – Debug logging utilities
- **`integrations/`** – Optional integrations (e.g., `project_nvim.lua`, `bufferline.lua`)

### Core Flow

1. **Detection**: When a buffer is created, `buffer.lua` detects its project root using `detect.lua`
2. **Allocation**: The buffer is routed to an existing or new tab for that project
3. **State**: `state.lua` maintains the bidirectional project-to-tab mapping

### Configuration

Configuration is defined in `config.lua` with these main sections:

- **`debug`** – Control logging behavior (file + vim.notify)
- **`patterns`** – Markers to detect project roots (VCS, tool config, build files)
- **`exclude_dirs`** – Directories to skip during traversal
- **`integrations`** – Optional plugin integrations (project.nvim, bufferline.nvim)

## Key Conventions

### Lua Module Pattern

All modules export a single `M = {}` table and use LuaCAD-style type annotations in comments:

```lua
--- Brief description of function
--- @param arg1 type
--- @return type
function M.function_name(arg1)
```

### Test Organization

Tests are in `tests/` using **plenary.busted**:

- **`buffer_spec.lua`** – Tests for buffer dispatch and allocation logic
- **`state_spec.lua`** – Tests for state management
- **`detect_spec.lua`** – Tests for project detection
- **`integration_spec.lua`** – End-to-end integration tests
- **`minimal_init.lua`** – Minimal Neovim config for test environment

Test utilities (e.g., `create_temp_tree`) help simulate filesystem structures for isolated testing.

### Code Style

- **Indentation**: 2 spaces (enforced by stylua)
- **String quotes**: Auto-prefer double quotes (stylua config)
- **require() sorting**: Disabled in stylua config
- **Comments**: Only in code that needs clarification; avoid over-commenting

### Error Handling

Modules use `pcall()` for optional integrations (e.g., trying to load `snacks.nvim` or `project.nvim`). Failures fall back gracefully with warning logs.

### Naming Conventions

- **Function parameters**: Use full words (`project_root` not `root`, `tab_id` not `tid`)
- **Local variables**: Descriptive names for clarity (`existing_tab`, `new_tab_id`)
