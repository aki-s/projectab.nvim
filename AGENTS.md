## Agents

### Terminology

- `<TMP>` is a temporary rule which could proceed each order. If set, then it might be deleted in near future.

### Overall

- You must answer and judge based on facts (source code, official document).
- Don't estimate, but check facts (source code, official document) before action.
  - Tell me the grounds for your action.
- Before doing dangerous actions
  (e.x. loss of data by deleting a file which contains uncommitted changes.
   reading credential files), ask permission.
- File editor is not limited to you. You could observe any changes while you are working.
- If you generated a file and it should be distributed for the other remote developers, add only what you have modified to VCS.
  - MUST: This repository is disclosed to public. So don't disclose any private or security information to public sites or VCS.
  - When you need concrete value such as absolute path, replace with dummy value
    when you disclose to public sites or VCS.
- Ask me there is any unclear point.
- Don't flatter to my order. If there's any problem in my order argue with a reason.
- Before doing your task, tell me what `md` files you read to share the context.

### Documentation

- Write documents in English.
- Use Mermaid to make dependency or architecture clear for human.
- Don't forget to update ./doc/projectab.md and ./doc/projectab.txt to be consistent with source code.

### Code

- Don't go ahead to writing code without agreed plan.
- To understand [neovim](https://github.com/neovim/neovim),
  - Read [neovim.github.io](https://github.com/neovim/neovim.github.io/).
  - Read files under `:echo $VIMRUNTIME/doc/`
- Run `make lint-fix` to format code after all edit has finished.
- Extend existing method if it is appropriate. If any existing method provides no value (a.k.a not working for utility method or extension point
  for client of this extension), you can delete it.

#### Unittest

- Add unittest for the function you created.
- When test requires function as a helper only to be used in unittest and it need to be at module, proceed the name with `_`.

#### Architecture & Design

- **Separation of Concerns**: Each module should have a single, well-defined responsibility.
  - Don't add ad-hoc fixes. Think about which module should own the functionality.
  - Before implementing, consider: "Does this belong in this module, or should it be in a separate module?"
- **Module Boundaries**: Respect module boundaries and avoid mixing concerns.
  - `state.lua`: Project-to-tab mapping state management only
  - `buffer.lua`: Buffer routing logic only
  - `session.lua`: Session persistence only
  - `detect.lua`: Project root detection only
  - `init.lua`: Plugin setup, autocmds, and user commands only

#### Type Annotations (LuaLS)

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
  - `@field` should be sorted in alphabetical order if there's no specific reason.

- **`.luarc.json`**: The project root contains `.luarc.json` for LuaLS workspace settings.
  Keep `diagnostics.globals` updated when new test helpers or globals are introduced.
