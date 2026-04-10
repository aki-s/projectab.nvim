```markdown
# AGENTS.md

## Terminology

- `<TMP>` is a temporary rule which may precede each order. If set, it might be deleted in the near future.

## General Rules

- Answer and judge based on facts (source code, official documentation). Do not estimate — verify before acting.
  - Always state the grounds for your actions.
- Before performing dangerous actions
  (e.g., loss of data by deleting a file which contains uncommitted changes, reading credential files), ask for permission.
- Be aware that files may be edited by others while you are working.
- If you generated a file and it should be distributed to other remote developers, add only what you have modified to VCS.
  - MUST: This repository is public. Never disclose private or security information to public sites or VCS.
  - When you need a concrete value such as an absolute path, replace it with a dummy value before disclosing to public sites or VCS.
- Ask if there is any unclear point.
- Do not flatter.
  - If there is any problem with an instruction, argue with a reason.
  - If there is a better approach (more concise, cleaner, best practice) than the one given, propose it.
- Before starting any task, tell me which `md` files you read to share context.
- Report inconsistency if any.

## Documentation

- Write all documents in English.
- Use Mermaid to make dependencies or architecture clear for humans.
- Don't forget to update `./doc/projectab.md` and `./doc/projectab.txt` to be consistent with the source code.
  - You are allowed to update docs at the last phase of a task, because the change policy could change during the task.

## Code

- Do not write code without an agreed plan.
- While you are editing code, others may change some code. Ask if an edit conflict has occurred.
- To understand [neovim](https://github.com/neovim/neovim):
  - Read [neovim.github.io](https://github.com/neovim/neovim.github.io/).
  - Read files under `:echo $VIMRUNTIME/doc/`
- Run `make lint-fix` to format code after all edits are finished.
- Extend existing functions when appropriate. If any existing function provides no value (e.g., a non-working utility function or an unused extension point for clients of this extension), you can delete it.
- A variable not expected to be exposed via `require` MUST be declared with `local`.
- A module variable (non-`local`) name starting with `_` is expected to be used by this plugin internally.
- A function not expected to be exposed to plugin users MUST begin with `_` (Python-like convention).
  - A function name starting with `_` is expected to be used by this plugin itself.
  - A function name starting with `__` is expected to be used only within the file containing the function.

### Unittest

- Add unittests for every module function you create.
- Check unittests ends successfully.
- When a test requires a helper function only used in unittests but placed at module level, prefix the name with `_`.

### Architecture & Design

- **Separation of Concerns**: Each module should have a single, well-defined responsibility.
  - Don't add ad-hoc fixes. Think about which module should own the functionality.
  - Before implementing, consider: "Does this belong in this module, or should it be in a separate module?"
- **Module Boundaries**: Respect module boundaries and avoid mixing concerns.
  - `buffer.lua` — buffer routing logic only
  - `detect.lua` — project root detection only
  - `init.lua` — plugin setup, autocmds, and user commands only
  - `session.lua` — session persistence only
  - `state.lua` — project-to-tab mapping state management only

### Type Annotations (LuaLS)

All Lua source files must include [LuaLS](https://luals.github.io/) type annotations for IDE support (completion, hover, diagnostics).

- **Module table (`M`)**: Every module must declare a `@class` annotation on `local M = {}`.
  The class name follows the pattern `Projectab<Name>Module` (e.g., `ProjectabStateModule`).

  ```lua
  --- @class ProjectabStateModule
  local M = {}
  ```

- **Functions**: Every public function (`M.xxx`) must have `@param` and `@return` annotations.
  Private/local functions should also have them when their signatures are non-trivial.
- **`pcall(require, ...)`**: When the loaded module is **internal** (i.e., under `projectab.*`),
  add `---@cast` on the line immediately after `pcall` to type the second return value.

  ```lua
  local ok, snacks_int = pcall(require, "projectab.integrations.snacks")
  ---@cast snacks_int ProjectabSnacksIntegration
  ```

  Do **NOT** add `@cast` for **external** plugin modules (e.g., `bufferline`, `snacks`, `project_nvim`)
  because their type definitions are outside this project.
- **`@class` for data structures**: Define `@class` + `@field` for non-trivial table shapes
  (e.g., `ProjectabState`, `ProjectabConfig`). Place the definition close to where the table is created.
  - `@field` should be sorted in alphabetical order if there is no specific reason otherwise.
- **`.luarc.json`**: The project root contains `.luarc.json` for LuaLS workspace settings.
  Keep `diagnostics.globals` updated when new test helpers or globals are introduced.
