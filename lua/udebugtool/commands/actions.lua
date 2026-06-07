-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/udebugtool/commands/actions.lua
-- Purpose: Expose command handlers that forward to debug actions.
-- License: MIT

local debug = require("udebugtool.debug")

local M = {}

-- Attach the requested state.
-- 附加所需状态。
function M.attach()
	debug.attach()
end

-- Return the dashboard.
-- 返回dashboard。
function M.dashboard()
	debug.dashboard()
end

-- Launch the requested state.
-- 启动所需状态。
function M.launch()
	debug.launch()
end

-- Return the editor.
-- 返回编辑器。
function M.editor()
	debug.launch_editor()
end

-- Return the game.
-- 返回游戏。
function M.game()
	debug.launch_game()
end

-- Return the breakpoint.
-- 返回断点。
function M.breakpoint()
	debug.toggle_breakpoint()
end

-- Return the breakpoint mute.
-- 返回断点mute。
function M.breakpoint_mute()
	debug.toggle_breakpoint_mute()
end

-- Return the breakpoints toggle.
-- 返回断点toggle。
function M.breakpoints_toggle()
	debug.toggle_breakpoints_enabled()
end

-- Continue the requested state.
-- 继续所需状态。
function M.continue_()
	debug.continue()
end

-- Stop the requested state.
-- 停止所需状态。
function M.stop()
	debug.stop()
end

-- Return the step over.
-- 返回stepover。
function M.step_over()
	debug.step_over()
end

-- Return the step into.
-- 返回stepinto。
function M.step_into()
	debug.step_into()
end

-- Return the step out.
-- 返回stepout。
function M.step_out()
	debug.step_out()
end

-- Return the help.
-- 返回help。
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
