local debug = require("udebugtool.debug")

local M = {}

function M.attach()
	debug.attach()
end

function M.dashboard()
	debug.dashboard()
end

function M.launch()
	debug.launch()
end

function M.editor()
	debug.launch_editor()
end

function M.game()
	debug.launch_game()
end

function M.breakpoint()
	debug.toggle_breakpoint()
end

function M.breakpoint_mute()
	debug.toggle_breakpoint_mute()
end

function M.breakpoints_toggle()
	debug.toggle_breakpoints_enabled()
end

function M.continue_()
	debug.continue()
end

function M.stop()
	debug.stop()
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

function M.help()
	print([[
UDebugTool commands:

  :UDebugTool dashboard    Open / focus the debug dashboard
  :UDebugTool launch       Launch the configured startup target under debugger
  :UDebugTool attach       Attach to the current Unreal process
  :UDebugTool editor       Build and launch Unreal Editor under debugger
  :UDebugTool game         Build and launch Unreal Game under debugger
  :UDebugTool breakpoint   Toggle a breakpoint at the cursor
  :UDebugTool breakpoint-mute   Toggle current breakpoint on / off
  :UDebugTool breakpoints-toggle   Toggle all breakpoints on / off
  :UDebugTool continue     Continue session, or attach / launch if none
  :UDebugTool stop         Stop the active debug session
  :UDebugTool step-over    Step over
  :UDebugTool step-into    Step into
  :UDebugTool step-out     Step out
]])
end

return M
