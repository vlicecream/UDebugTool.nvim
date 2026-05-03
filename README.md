# UDebugTool.nvim

Standalone Unreal Engine debugging for Neovim.

`UDebugTool.nvim` is the split-out Unreal debug layer from `UCore.nvim`. It focuses on:

- `nvim-dap` wiring for Unreal on Windows
- `cppvsdbg` adapter auto-detection
- automatic `vsda.node` signer provisioning
- Mason-based `cpptools` install fallback when available
- attach to running Unreal processes
- build + launch Unreal Editor under debugger
- breakpoint persistence per project
- header declaration breakpoint redirection to `.cpp`
- a built-in multi-pane debug workspace

## Install

```lua
{
  "vlicecream/UDebugTool.nvim",
  main = "udebugtool",
  lazy = false,
  dependencies = {
    {
      "mfussenegger/nvim-dap",
      lazy = false,
    },
  },
  opts = {},
}
```

Optional but recommended:

- `williamboman/mason.nvim` for automatic `cpptools` adapter install
- a local VS Code / Cursor C/C++ extension install also works, because `UDebugTool` searches common extension directories for `vsdbg.exe`
- `node` on `PATH`, required for the `cppvsdbg` handshake signer

## Commands

```vim
:UDebugTool
:UDebugTool attach
:UDebugTool breakpoint
:UDebugTool condition
:UDebugTool logpoint
:UDebugTool clear
:UDebugTool editor
:UDebugTool continue
:UDebugTool stop
:UDebugTool restart
:UDebugTool breakpoints
:UDebugTool processes
:UDebugTool ui
:UDebugTool hover
:UDebugTool step-over
:UDebugTool step-into
:UDebugTool step-out
:UDebugTool prewarm
:UDebugTool status
:checkhealth udebugtool
```

## Default Keymaps

```text
<leader>db  toggle breakpoint
<leader>dc  continue / attach / launch
<leader>da  attach
<leader>de  build + launch Unreal Editor under debugger
<leader>dr  restart
<leader>ds  stop
<leader>do  step over
<leader>di  step into
<leader>du  step out
<leader>dh  hover
<leader>dp  pick process
<leader>dl  list breakpoints
<leader>dt  toggle debug workspace
```

## Debug Workspace

`:UDebugTool ui` opens a three-pane debug workspace:

- left: session state, threads, call stack, breakpoints, watches
- right: current stop, scope variables, expandable watch values
- bottom: controls and current session summary

Inside any debug UI pane:

```text
<CR>  jump to frame / breakpoint, or expand variables
a     add watch expression
d     delete selected watch
r     refresh panes
c     continue
o     step over
i     step into
u     step out
s     stop
q     close the debug workspace
```

## Defaults

```lua
require("udebugtool").setup({
  cache_dir = vim.fn.stdpath("cache") .. "/udebugtool",
  engine_roots = {},
  debug = {
    enable = true,
    autosave_before_launch = true,
    build_before_launch = true,
    redirect_header_breakpoints = true,
    adapter = {
      auto_install = true,
      package = "cpptools",
      command = nil,
      signer = nil,
      node_command = "node",
      args = {},
    },
    ui = {
      auto_open = true,
      auto_close = true,
      sidebar_width = 38,
      inspect_width = 52,
      tray_height = 9,
      persist_watches = true,
    },
  },
})
```

## Notes

- Windows is the primary target.
- Breakpoints are stored under `stdpath("cache")/udebugtool/projects/<project-hash>/breakpoints.json`.
- Watch expressions are stored per project under `stdpath("cache")/udebugtool/projects/<project-hash>/watches.json`.
- `editor` builds the current Unreal Editor target first, then launches and attaches.
- `prewarm` is best-effort. It prepares signer / adapter prerequisites before the first debug session.
