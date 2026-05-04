local M = {}

local initialized = false
local registered_keymaps = {}

local function register_default_keymaps()
	local cfg = require("udebugtool.config").values
	local keymaps = cfg.keymaps or {}
	if keymaps.enable == false then
		return
	end

	local debug = require("udebugtool.debug")
	local mappings = {
		{ keymaps.attach, debug.attach, "UDebugTool attach" },
		{ keymaps.editor, debug.launch_editor, "UDebugTool debug editor" },
		{ keymaps.breakpoint, debug.toggle_breakpoint, "UDebugTool breakpoint" },
		{ keymaps.breakpoints_toggle, debug.toggle_breakpoints_enabled, "UDebugTool toggle breakpoints" },
		{ keymaps.continue, debug.continue, "UDebugTool continue" },
		{ keymaps.stop, debug.stop, "UDebugTool stop" },
		{ keymaps.step_over, debug.step_over, "UDebugTool step over" },
		{ keymaps.step_into, debug.step_into, "UDebugTool step into" },
		{ keymaps.step_out, debug.step_out, "UDebugTool step out" },
	}

	for _, item in ipairs(mappings) do
		if item[1] and item[1] ~= "" then
			vim.keymap.set("n", item[1], item[2], {
				silent = true,
				desc = item[3],
			})
			table.insert(registered_keymaps, item[1])
		end
	end
end

local function unregister_default_keymaps()
	for _, lhs in ipairs(registered_keymaps) do
		local info = vim.fn.maparg(lhs, "n", false, true)
		if type(info) == "table" and tostring(info.desc or ""):find("^UDebugTool ") then
			pcall(vim.keymap.del, "n", lhs)
		end
	end
	registered_keymaps = {}
end

function M.reset()
	pcall(function()
		require("udebugtool.debug").reset()
	end)
	unregister_default_keymaps()
	pcall(vim.api.nvim_del_user_command, "UDebugTool")
	initialized = false
end

function M.setup(opts)
	if initialized then
		M.reset()
	end

	initialized = true
	require("udebugtool.config").setup(opts)
	require("udebugtool.commands").register()
	register_default_keymaps()
	require("udebugtool.debug").setup()
end

return M
