local debug = require("udebugtool.debug")

local M = {}

function M.attach()
	debug.attach()
end

function M.breakpoint()
	debug.toggle_breakpoint()
end

function M.condition()
	debug.conditional_breakpoint()
end

function M.logpoint()
	debug.logpoint()
end

function M.clear()
	debug.clear_breakpoints()
end

function M.editor()
	debug.launch_editor()
end

function M.continue_()
	debug.continue()
end

function M.stop()
	debug.stop()
end

function M.restart()
	debug.restart()
end

function M.breakpoints()
	debug.list_breakpoints()
end

function M.processes()
	debug.pick_process()
end

function M.ui()
	debug.toggle_ui()
end

function M.hover()
	debug.hover()
end

function M.step_over()
	debug.step_over()
end

function M.step_into()
	debug.step_into()
end

function M.step_out()
	debug.step_out()
end

function M.prewarm()
	debug.prewarm()
end

function M.status()
	print(vim.inspect(debug.status()))
end

function M.help()
	print([[
UDebugTool commands:

  :UDebugTool attach       Attach to the current Unreal process
  :UDebugTool breakpoint   Toggle a breakpoint at the cursor
  :UDebugTool condition    Set a conditional breakpoint
  :UDebugTool logpoint     Set a logpoint
  :UDebugTool clear        Clear all current breakpoints
  :UDebugTool editor       Build and launch Unreal Editor under debugger
  :UDebugTool continue     Continue session, or attach / launch if none
  :UDebugTool stop         Stop the active debug session
  :UDebugTool restart      Restart the active debug session
  :UDebugTool breakpoints  List current breakpoints
  :UDebugTool processes    Pick a process to attach
  :UDebugTool ui           Toggle the built-in debug workspace
  :UDebugTool hover        Show debug hover
  :UDebugTool step-over    Step over
  :UDebugTool step-into    Step into
  :UDebugTool step-out     Step out
  :UDebugTool prewarm      Prepare adapter prerequisites
  :UDebugTool status       Print adapter status
  :UDebugTool help         Show this help
]])
end

return M
