local M = {}

local defaults = {
	cache_dir = vim.fn.stdpath("cache") .. "/udebugtool",
	engine_roots = {},
	keymaps = {
		enable = true,
		attach = "<leader>da",
		editor = "<leader>de",
		breakpoint = "<leader>db",
		breakpoints_toggle = "<leader>dm",
		continue = "<leader>dc",
		stop = "<leader>ds",
		step_over = "<leader>do",
		step_into = "<leader>di",
		step_out = "<leader>du",
	},
	build = {
		open_quickfix_on_error = true,
		include_warnings = true,
		color_log = true,
		autosave = true,
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
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.values
end

return M
