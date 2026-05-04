local actions = require("udebugtool.commands.actions")

local M = {}

local function normalize_subcommand(args)
	local sub = (args.args or ""):match("^%s*(%S+)")
	return sub and sub:lower() or "help"
end

function M.dispatch(args)
	local sub = normalize_subcommand(args)
	local handlers = {
		attach = actions.attach,
		editor = actions.editor,
		breakpoint = actions.breakpoint,
		["breakpoints-toggle"] = actions.breakpoints_toggle,
		["continue"] = actions.continue_,
		stop = actions.stop,
		["step-over"] = actions.step_over,
		["step-into"] = actions.step_into,
		["step-out"] = actions.step_out,
	}

	local handler = handlers[sub]
	if not handler then
		if sub ~= "help" then
			vim.notify("Unknown UDebugTool command: " .. sub, vim.log.levels.ERROR)
		end
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
				"editor",
				"breakpoint",
				"breakpoints-toggle",
				"continue",
				"stop",
				"step-over",
				"step-into",
				"step-out",
			}
			local needle = (arglead or ""):lower()
			return vim.tbl_filter(function(item)
				return item:find(needle, 1, true) == 1
			end, items)
		end,
	})
end

return M
