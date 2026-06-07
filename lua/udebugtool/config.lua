-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/udebugtool/config.lua
-- Purpose: Store defaults and merge user configuration for UDebugTool.
-- License: MIT

local M = {}

local defaults = {
	cache_dir = vim.fn.stdpath("cache") .. "/udebugtool",
	engine_roots = {},
	startup = {
		mode = "editor",
		configuration = "Development",
		platform = "Win64",
		editor_target = nil,
		game_target = nil,
	},
	keymaps = {
		enable = true,
		attach = "<leader>da",
		editor = "<leader>de",
		breakpoint = "<leader>db",
		breakpoint_mute = "<leader>dn",
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
		prefer_configuration_executable = true,
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

-- Set up the requested state.
-- 设置所需状态。
function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.values
end

return M
