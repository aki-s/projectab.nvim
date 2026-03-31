# Contributing to projectab.nvim

Thank you for your interest in contributing!

## Development Environment

**Requirements:**

- **Neovim** >= 0.11.6
- **stylua** 2.3.1+ (Lua formatter) — installed via `mise` (see `mise.toml`)
- **Git**

**Setup with mise:**

```sh
mise install
```

This installs all tools declared in `mise.toml` (including stylua).

## Running Tests

```sh
make test
```

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s `busted` runner.
The first run will automatically download `plenary.nvim` into Neovim's cache directory.

To run a single spec file:

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/projectab/buffer_spec.lua { minimal_init = 'tests/minimal_init.lua' }"
```

## Formatting Code

```sh
make lint-fix   # auto-format
make lint       # check only (used in CI)
```

## Submitting a Pull Request

1. Fork the repository and create a feature branch.
2. Make your changes, following the conventions below.
3. Run `make lint-fix` to format your code.
4. Run `make test` to ensure all tests pass.
5. Add or update tests for new functionality.
6. Open a PR against `main`.

## Code Conventions

- **Language**: All code and comments must be in English.
- **Modules**: Every Lua file exports a single `local M = {}` table and ends with `return M`.
- **Type annotations**: Use [LuaLS](https://luals.github.io/) annotations (`@param`, `@return`, `@class`, `@field`) on all public functions. See `AGENTS.md` for details.
- **Formatting**: 2-space indentation, enforced by stylua.
- **Module boundaries**: Respect the separation of concerns documented in `AGENTS.md`.
- **Tests**: Add a `*_spec.lua` under `tests/projectab/` for any new module or function.
