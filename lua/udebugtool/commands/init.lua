local actions = require("udebugtool.commands.actions")

local M = {}

local function normalize_subcommand(args)
	local sub = (args.args or ""):match("^%s*(%S+)")
	return sub and sub:lower() or "help"
end

function M.dispatch(args)
	local sub = normalize_subcommand(args)
	local handlers = {
		help = actions.help,
		attach = actions.attach,
		breakpoint = actions.breakpoint,
		condition = actions.condition,
		logpoint = actions.logpoint,
		clear = actions.clear,
		editor = actions.editor,
		["continue"] = actions.continue_,
		stop = actions.stop,
		restart = actions.restart,
		breakpoints = actions.breakpoints,
		processes = actions.processes,
		ui = actions.ui,
		hover = actions.hover,
		["step-over"] = actions.step_over,
		["step-into"] = actions.step_into,
		["step-out"] = actions.step_out,
		prewarm = actions.prewarm,
		status = actions.status,
	}

	local handler = handlers[sub]
	if not handler then
		vim.notify("Unknown UDebugTool command: " .. sub, vim.log.levels.ERROR)
		return actions.help()
	end

	handler()
end

function M.register()
	pcall(vim.api.nvim_del_user_command, "UDebugTool")

	vim.api.nvim_create_user_command("UDebugTool", M.dispatch, {
		nargs = "*",
		complete = function(arglead)
			local items = {
				"attach",
				"breakpoint",
				"condition",
				"logpoint",
				"clear",
				"editor",
				"continue",
				"stop",
				"restart",
				"breakpoints",
				"processes",
				"ui",
				"hover",
				"step-over",
				"step-into",
				"step-out",
				"prewarm",
				"status",
				"help",
			}
			local needle = (arglead or ""):lower()
			return vim.tbl_filter(function(item)
				return item:find(needle, 1, true) == 1
			end, items)
		end,
	})
end

return M
