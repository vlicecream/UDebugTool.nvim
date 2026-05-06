# UDebugTool.nvim

Standalone Unreal Engine debugging for Neovim.

`UDebugTool.nvim` is the split-out Unreal debug layer from `UCore.nvim`. It focuses on:

- `nvim-dap` wiring for Unreal on Windows
- `cppvsdbg` adapter auto-detection
- automatic `vsda.node` signer provisioning
- Mason-based `cpptools` install fallback when available
- attach to running Unreal processes
- build + launch Unreal Editor or Game under debugger
- breakpoint persistence per project
- header declaration breakpoint redirection to `.cpp`
- a built-in multi-pane debug workspace
- optional shared bottom output tabs when `UCore.nvim` is present

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
:UDebugTool launch
:UDebugTool attach
:UDebugTool editor
:UDebugTool game
:UDebugTool breakpoint
:UDebugTool continue
:UDebugTool stop
:UDebugTool step-over
:UDebugTool step-into
:UDebugTool step-out
:checkhealth udebugtool
```

## Default Keymaps

```text
ga          attach
ge          launch configured debug startup target
<leader>db  toggle breakpoint
<leader>dc  continue / attach / launch
<leader>ds  stop
<leader>do  step over
<leader>di  step into
<leader>du  step out
```

## Debug Workspace

The built-in debug workspace opens automatically when a session stops:

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
  startup = {
    mode = "editor", -- "editor" | "game"
    configuration = "Development", -- use "DebugGame" / "Debug" for debug-style builds
    platform = "Win64",
    editor_target = nil,
    game_target = nil,
  },
  build = {
    open_quickfix_on_error = true,
    include_warnings = true,
    color_log = true,
    autosave = true,
    use_target_arguments = true,
    build_shader_compile_worker = true,
    shader_compile_worker_target = "ShaderCompileWorker",
    shader_compile_worker_platform = "Win64",
    shader_compile_worker_configuration = "Development",
    shader_compile_worker_quiet = true,
    wait_mutex = true,
    from_msbuild = true,
    extra_args = {},
  },
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

`startup.mode` only controls whether debug launch opens `editor` or `game`.

If you want what you call "debug mode", set `startup.configuration` to `DebugGame` or `Debug`. Do not put that into `startup.mode`.

By default, debug launch builds use Rider-style Unreal Build Tool arguments:

```text
Build.bat -Target="<Project>Editor Win64 Development -Project=\"...\Project.uproject\"" -Target="ShaderCompileWorker Win64 Development -Project=\"...\Project.uproject\" -Quiet" -WaitMutex -FromMSBuild
```

Set `build.use_target_arguments = false` if you need the older positional `Build.bat <Target> <Platform> <Configuration> -Project=...` form.

## Notes

- Windows is the primary target.
- Breakpoints are stored under `stdpath("cache")/udebugtool/projects/<project-hash>/breakpoints.json`.
- Watch expressions are stored per project under `stdpath("cache")/udebugtool/projects/<project-hash>/watches.json`.
- `launch` uses this plugin's own debug startup config. It does not read `UBuildTool.nvim` config.
- `editor` always forces Unreal Editor launch under debugger, ignoring `startup.mode`.
- `game` always forces Unreal Game launch under debugger, ignoring `startup.mode`.
- `build` defaults used during debug launch come from `startup.configuration`, `startup.platform`, and the mode-specific target.
- `continue` attaches to an existing Unreal process when possible, otherwise it launches the configured debug startup target for the current project.
- when `UCore.nvim` is loaded, adapter install progress, build output, launch flow, and debug session state changes are mirrored into the shared bottom output workspace
