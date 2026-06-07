-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/udebugtool/health.lua
-- Purpose: Report health checks for required tools and runtime dependencies.
-- License: MIT

local debug = require("udebugtool.debug")
local project = require("udebugtool.project")

local M = {}

local health = vim.health or {}
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

-- Check whether dir.
-- 检查是否目录。
local function is_dir(path)
	return path and vim.fn.isdirectory(path) == 1
end

-- Check the requested state.
-- 检查所需状态。
function M.check()
	start("UDebugTool.nvim")

	local cfg = require("udebugtool.config").values
	info("cache dir: " .. tostring(cfg.cache_dir))
	if is_dir(cfg.cache_dir) then
		ok("cache dir exists")
	else
		info("cache dir does not exist yet")
	end

	local root = project.find_project_root_from_context()
	if not root then
		warn("No Unreal project detected from current context", {
			"Open a file inside an Unreal project, then run :checkhealth udebugtool again.",
		})
	else
		ok("project root: " .. root)
		local uproject = project.find_project_file_in_root(root)
		if uproject then
			ok(".uproject: " .. uproject)
		end

		local engine, engine_err = project.engine_metadata(root)
		if engine then
			ok("engine root: " .. tostring(engine.engine_root))
		else
			warn("failed to resolve Unreal Engine root", { tostring(engine_err) })
		end
	end

	local status = debug.status(root)
	if status.dap_available then
		ok("nvim-dap available")
	else
		warn("nvim-dap not available", {
			"Install mfussenegger/nvim-dap to enable UDebugTool.",
		})
	end

	if status.windows then
		ok("Windows environment detected")
	else
		warn("UDebugTool currently targets Windows Unreal debugging")
	end

	if status.adapter_command then
		ok("debug adapter found: " .. status.adapter_command)
	else
		warn("vsdbg.exe not found yet", {
			"Install cpptools via mason.nvim or a VS Code C/C++ extension, or let UDebugTool prewarm auto-install it when Mason is available.",
		})
	end

	if status.adapter_signer then
		ok("handshake signer found: " .. status.adapter_signer)
	else
		warn("vsda.node signer not found yet", {
			"UDebugTool can provision it automatically from the official VS Code archive.",
		})
	end

	if status.adapter_node_command then
		ok("Node.js found: " .. status.adapter_node_command)
	else
		warn("Node.js not found on PATH", {
			"Required for cppvsdbg handshake signing.",
		})
	end

	if status.adapter_ext_config_dir then
		info("cppvsdbg ext config dir: " .. status.adapter_ext_config_dir)
	end

	if status.visualizer_file then
		ok("Unreal natvis: " .. status.visualizer_file)
	else
		warn("Unreal natvis not found", {
			"Expected under Engine/Extras/VisualStudioDebugging/Unreal.natvis for proper Unreal type visualization.",
		})
	end

	info("breakpoint store: " .. tostring(status.breakpoint_store))
end

return M
