---
name: Bug Report
about: Report a bug or unexpected behavior
labels: bug
---

## Description

A clear and concise description of what the bug is.

## Steps to Reproduce

1. Go to '...'
2. Open a file from project '...'
3. See error

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened. Include error messages if any (`:messages`).

## Environment

- **Neovim version**: (output of `nvim --version`)
- **OS**: (e.g., macOS 14, Ubuntu 22.04)
- **projectab.nvim version/commit**:
- **Relevant plugins** (e.g. persistence.nvim, bufferline.nvim):

## Minimal Config to Reproduce

```lua
-- Paste a minimal `init.lua` that reproduces the issue
require("projectab").setup({})
```

## Debug Log

1. Enable debug logging, reproduce the bug and paste the output:

```lua
require("projectab").setup({
  debug = { file = true, notify = false },
})
```

`~/.cache/nvim/projectab.log` is written. Paste the content.

(`~/.cache` is `vim.fn.stdpath("cache")`)


2. `:Projectab ps-dump`

`~/.cache/nvim/projectab_dump.txt` is created. Paste the content.
