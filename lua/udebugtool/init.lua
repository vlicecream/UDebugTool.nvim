local M = {}

local initialized = false

local function register_default_keymaps()
	local cfg = require("udebugtool.config").values
	local keymaps = cfg.keymaps or {}
	if keymaps.enable == false then
		return
	end

	local debug = require("udebugtool.debug")
	local mappings = {
		{ keymaps.breakpoint, debug.toggle_breakpoint, "UDebugTool breakpoint" },
		{ keymaps.continue, debug.continue, "UDebugTool continue" },
		{ keymaps.attach, debug.attach, "UDebugTool attach" },
		{ keymaps.editor, debug.launch_editor, "UDebugTool debug editor" },
		{ keymaps.restart, debug.restart, "UDebugTool restart" },
		{ keymaps.stop, debug.stop, "UDebugTool stop" },
		{ keymaps.step_over, debug.step_over, "UDebugTool step over" },
		{ keymaps.step_into, debug.step_into, "UDebugTool step into" },
		{ keymaps.step_out, debug.step_out, "UDebugTool step out" },
		{ keymaps.hover, debug.hover, "UDebugTool hover" },
		{ keymaps.processes, debug.pick_process, "UDebugTool processes" },
		{ keymaps.breakpoints, debug.list_breakpoints, "UDebugTool breakpoints" },
		{ keymaps.ui, debug.toggle_ui, "UDebugTool UI" },
	}

	for _, item in ipairs(mappings) do
		if item[1] and item[1] ~= "" then
			vim.keymap.set("n", item[1], item[2], {
				silent = true,
				desc = item[3],
			})
		end
	end
end

function M.setup(opts)
	if initialized then
		require("udebugtool.config").setup(opts)
		return
	end

	initialized = true
	require("udebugtool.config").setup(opts)
	require("udebugtool.commands").register()
	register_default_keymaps()
	require("udebugtool.debug").setup()
end

return M
