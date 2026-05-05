local config = require("udebugtool.config")
local project = require("udebugtool.project")

local M = {}

local build_job = nil
local build_buf = nil
local build_cancelled = false
local build_pid = nil

local build_diagnostics = {}
local build_error_count = 0
local build_warning_count = 0

local build_ns = vim.api.nvim_create_namespace("udebugtool_build_log")
local highlights_setup = false
local build_output = nil
local on_build_line
local current_context

local function shared_output_panel()
	local panel = rawget(_G, "__ucore_output_panel_api")
	if type(panel) == "table" and type(panel.open_tab) == "function" then
		return panel
	end
	return nil
end

local function setup_highlights()
	if highlights_setup then
		return
	end
	highlights_setup = true
	vim.api.nvim_set_hl(0, "UDebugToolBuildError", { fg = "#F44747", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolBuildWarning", { fg = "#FFCC66" })
	vim.api.nvim_set_hl(0, "UDebugToolBuildSuccess", { fg = "#89D185", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolBuildCommand", { fg = "#4FC1FF" })
end

local function build_line_group(text)
	text = tostring(text or "")
	local lower = text:lower()

	if text:match("^Project:") or text:match("^Engine:") or text:match("^Command:") then
		return "UCoreOutputCommand"
	end
	if text:match("error%s+C%d+:")
		or lower:find("fatal error", 1, true)
		or text:match("fatal error%s+LNK%d+")
		or text:match("%f[%a]LNK%d+%f[%A]")
		or lower:find("ubt error", 1, true)
		or lower:find("error:", 1, true)
	then
		return "UCoreOutputError"
	end
	if text:match("warning%s+C%d+:")
		or lower:find(": warning ", 1, true)
		or lower:find("warning:", 1, true)
	then
		return "UCoreOutputWarning"
	end
	if lower:find("succeeded", 1, true) or lower:find("finished with exit code 0", 1, true) then
		return "UCoreOutputSuccess"
	end

	return nil
end

local function local_build_group(group)
	if group == "UCoreOutputCommand" then
		return "UDebugToolBuildCommand"
	end
	if group == "UCoreOutputError" then
		return "UDebugToolBuildError"
	end
	if group == "UCoreOutputWarning" then
		return "UDebugToolBuildWarning"
	end
	if group == "UCoreOutputSuccess" then
		return "UDebugToolBuildSuccess"
	end
	return group
end

local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

local function readable(path)
	return path and vim.fn.filereadable(path) == 1
end

local function executable(path)
	return path and (vim.fn.executable(path) == 1 or readable(path))
end

local function powershell()
	return vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
end

local function ps_quote(text)
	return "'" .. tostring(text):gsub("'", "''") .. "'"
end

local function build_bat(engine_root)
	return normalize(engine_root .. "/Engine/Build/BatchFiles/Build.bat")
end

local function editor_exe(engine_root)
	local candidates = {
		normalize(engine_root .. "/Engine/Binaries/Win64/UnrealEditor.exe"),
		normalize(engine_root .. "/Engine/Binaries/Win64/UE4Editor.exe"),
	}

	for _, path in ipairs(candidates) do
		if executable(path) then
			return path
		end
	end

	return nil
end

function M.editor_executable(engine_root)
	return editor_exe(engine_root)
end

local function normalize_startup_mode(mode)
	mode = tostring(mode or ""):lower()
	if mode == "game" then
		return "game"
	end
	return "editor"
end

local function startup_defaults(ctx, mode_override)
	local startup = config.values.startup or {}
	local mode = normalize_startup_mode(mode_override or startup.mode)
	local target

	if mode == "game" then
		target = startup.game_target or project.game_target_name(ctx.root)
	else
		target = startup.editor_target or project.editor_target_name(ctx.root)
	end

	return {
		mode = mode,
		configuration = startup.configuration or "Development",
		platform = startup.platform or "Win64",
		target = target,
	}
end

function M.startup_profile(root, mode_override)
	local ctx, err = current_context(root)
	if not ctx then
		return nil, err
	end

	local defaults = startup_defaults(ctx, mode_override)
	return vim.tbl_extend("force", ctx, defaults), nil
end

local function game_exe_candidates(root, target, platform, configuration, project_name)
	local base = normalize(root .. "/Binaries/" .. tostring(platform))
	local items = {
		normalize(base .. "/" .. tostring(target) .. ".exe"),
		normalize(base .. "/" .. tostring(target) .. "-" .. tostring(platform) .. "-" .. tostring(configuration) .. ".exe"),
	}

	if project_name and project_name ~= "" and project_name ~= target then
		table.insert(items, normalize(base .. "/" .. tostring(project_name) .. ".exe"))
		table.insert(items, normalize(base .. "/" .. tostring(project_name) .. "-" .. tostring(platform) .. "-" .. tostring(configuration) .. ".exe"))
	end

	return items
end

function M.game_executable(root, opts)
	opts = opts or {}
	local target = opts.target or project.game_target_name(root)
	local platform = opts.platform or "Win64"
	local configuration = opts.configuration or "Development"
	local project_name = opts.project_name or project.project_name(root)

	for _, path in ipairs(game_exe_candidates(root, target, platform, configuration, project_name)) do
		if executable(path) then
			return path
		end
	end

	return nil
end

function M.launch_profile(root, mode_override)
	local profile, err = M.startup_profile(root, mode_override)
	if not profile then
		return nil, err
	end

	if profile.mode == "game" then
		local game_exe = M.game_executable(profile.root, profile)
		if game_exe then
			profile.program = game_exe
			profile.program_args = {}
			profile.display_name = "Unreal Game"
			return profile, nil
		end

		local editor = editor_exe(profile.engine_root)
		if not editor then
			return nil, "Unreal game executable was not found and UnrealEditor.exe fallback is unavailable"
		end

		profile.program = editor
		profile.program_args = { profile.uproject, "-game" }
		profile.display_name = "Unreal Game"
		profile.uses_editor_fallback = true
		return profile, nil
	end

	local editor = editor_exe(profile.engine_root)
	if not editor then
		return nil, "UnrealEditor.exe was not found"
	end

	profile.program = editor
	profile.program_args = { profile.uproject }
	profile.display_name = "Unreal Editor"
	return profile, nil
end

function current_context(root)
	root = root or project.find_project_root_from_context()
	if not root then
		return nil, "Could not find .uproject"
	end

	local uproject = project.find_project_file_in_root(root)
	if not uproject then
		return nil, "Could not find .uproject under project root: " .. root
	end

	local engine, engine_err = project.engine_metadata(root)
	if not engine then
		return nil, engine_err
	end

	return {
		root = root,
		uproject = uproject,
		project_name = project.project_name(root),
		engine_root = engine.engine_root,
		engine_association = engine.engine_association,
	}, nil
end

function M.current_context(root)
	return current_context(root)
end

local function save_modified_project_buffers(root)
	root = normalize(root)
	if not root or root == "" then
		return
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
			local path = normalize(vim.api.nvim_buf_get_name(bufnr))
			if path and path:sub(1, #root) == root then
				pcall(vim.api.nvim_buf_call, bufnr, function()
					vim.cmd("silent write")
				end)
			end
		end
	end
end

local function build_command(ctx, opts)
	local bat = build_bat(ctx.engine_root)
	if not readable(bat) then
		return nil, "Build.bat not found: " .. tostring(bat)
	end

	local target = opts.target or project.editor_target_name(ctx.root)
	local platform = opts.platform or "Win64"
	local configuration = opts.configuration or "Development"
	local script = table.concat({
		"&",
		ps_quote(bat),
		ps_quote(target),
		ps_quote(platform),
		ps_quote(configuration),
		ps_quote("-Project=" .. ctx.uproject),
		ps_quote("-WaitMutex"),
	}, " ")

	return { powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script }, nil
end

local function parse_build_args(args, ctx, mode_override)
	args = vim.trim(args or "")
	local tokens = {}
	for token in args:gmatch("%S+") do
		table.insert(tokens, token)
	end
	local defaults = startup_defaults(ctx, mode_override)
	return {
		mode = defaults.mode,
		configuration = tokens[1] or defaults.configuration,
		platform = tokens[2] or defaults.platform,
		target = tokens[3] or defaults.target,
	}
end

local function create_log_buffer(title)
	local previous_win = vim.api.nvim_get_current_win()
	vim.cmd("botright 15new")
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "udebugtool-build"
	local name = title:gsub("^UDebugTool build:%s*", "UDebugTool build - ") .. " #" .. tostring(buf)
	pcall(vim.api.nvim_buf_set_name, buf, name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		title,
		string.rep("=", vim.fn.strdisplaywidth(title)),
		"",
	})
	vim.bo[buf].modified = false

	if vim.api.nvim_win_is_valid(previous_win) then
		vim.api.nvim_set_current_win(previous_win)
	end

	return buf
end

local function scroll_to_bottom(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local line_count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_win_set_cursor(win, { line_count, 0 })
	end
end

local function append_lines(buf, data, on_line)
	if not data or data == "" then
		return
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
		local lines = vim.split(data, "\n", { plain = true })
		if lines[#lines] == "" then
			table.remove(lines, #lines)
		end
		if vim.tbl_isempty(lines) then
			return
		end

		local start_line = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
		vim.bo[buf].modified = false
		scroll_to_bottom(buf)

		if on_line then
			for i, line_text in ipairs(lines) do
				on_line(buf, start_line + i - 1, line_text)
			end
		end
	end)
end

local function parse_diagnostic_line(line, project_root)
	local path, lnum, col, kind, msg = line:match(
		"^(.-)%((%d+)(?:,(%d+))?%)%s*:%s*(error|warning)%s+(.+)$"
	)
	if path then
		lnum = tonumber(lnum)
		col = tonumber(col or 0)
		kind = (kind == "error") and "E" or "W"
		if not readable(path) and project_root then
			local abs = normalize(project_root .. "/" .. path)
			if readable(abs) then
				path = abs
			end
		end
		return { filename = path, lnum = lnum, col = col, type = kind, text = msg }
	end

	local path2, lnum2, col2, kind2, msg2 = line:match(
		"^([A-Za-z]:[^:]+):(%d+):(%d+):%s*(error|warning):%s*(.+)$"
	)
	if path2 then
		return {
			filename = path2,
			lnum = tonumber(lnum2),
			col = tonumber(col2),
			type = (kind2 == "error") and "E" or "W",
			text = msg2,
		}
	end

	if line:find("fatal error LNK", 1, true) then
		local msg3 = line:match("fatal error LNK%d+%s*:.*$") or line
		return { type = "E", text = msg3 }
	end

	if line:find("Error:", 1, true) and (line:match("^LogCompile") or line:match("^LogLinker")) then
		return { type = "E", text = line }
	end

	return nil
end

local function color_build_line(buf, line_num, text)
	if not config.values.build.color_log then
		return
	end

	local group = local_build_group(build_line_group(text))

	if group then
		local end_col = math.max(0, vim.fn.strchars(text))
		vim.api.nvim_buf_set_extmark(buf, build_ns, line_num, 0, {
			hl_group = group,
			end_row = line_num,
			end_col = end_col,
		})
	end
end

local function split_lines(data)
	if not data or data == "" then
		return {}
	end

	data = tostring(data):gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = vim.split(data, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines, #lines)
	end
	return lines
end

local function build_output_sink(title)
	local panel = shared_output_panel()
	if panel then
		return {
			kind = "panel",
			panel = panel,
			key = panel.open_tab({
				key = "workspace:build",
				title = "Build",
				kind = "build",
				focus = true,
			}),
		}
	end

	return {
		kind = "buffer",
		buf = create_log_buffer(title),
	}
end

local function append_build_chunk(sink, project_root, data, no_parse)
	if not data or data == "" then
		return
	end

	if sink.kind == "panel" then
		local lines = split_lines(data)
		if vim.tbl_isempty(lines) then
			return
		end

		local groups = {}
		for i, line_text in ipairs(lines) do
			if not no_parse then
				local item = parse_diagnostic_line(line_text, project_root)
				if item then
					table.insert(build_diagnostics, item)
					if item.type == "E" then
						build_error_count = build_error_count + 1
					elseif item.type == "W" then
						build_warning_count = build_warning_count + 1
					end
				end
			end
			groups[i] = build_line_group(line_text)
		end

		sink.panel.append(sink.key, lines, {
			focus = false,
			line_groups = groups,
		})
		return
	end

	append_lines(sink.buf, data, function(b, ln, t)
		on_build_line(project_root, b, ln, t, no_parse)
	end)
end

local function fill_quickfix()
	if vim.tbl_isempty(build_diagnostics) then
		return
	end

	local items = {}
	for _, item in ipairs(build_diagnostics) do
		if config.values.build.include_warnings ~= false or item.type == "E" then
			table.insert(items, item)
		end
	end

	vim.fn.setqflist(items, "r")
	if config.values.build.open_quickfix_on_error and build_error_count > 0 then
		vim.cmd("botright copen")
		vim.cmd("wincmd p")
	end
end

local function build_summary(ok, exit_code)
	local parts = {}
	table.insert(parts, ok and "Build succeeded" or "Build failed")
	if build_error_count > 0 then
		table.insert(parts, build_error_count .. " error" .. (build_error_count > 1 and "s" or ""))
	end
	if build_warning_count > 0 then
		table.insert(parts, build_warning_count .. " warning" .. (build_warning_count > 1 and "s" or ""))
	end
	if exit_code ~= nil then
		table.insert(parts, "exit " .. exit_code)
	end
	return table.concat(parts, ", ")
end

on_build_line = function(project_root, buf, line_num, text, no_parse)
	if not no_parse then
		local item = parse_diagnostic_line(text, project_root)
		if item then
			table.insert(build_diagnostics, item)
			if item.type == "E" then
				build_error_count = build_error_count + 1
			elseif item.type == "W" then
				build_warning_count = build_warning_count + 1
			end
		end
	end
	color_build_line(buf, line_num, text)
end

local function reset_diagnostics()
	build_diagnostics = {}
	build_error_count = 0
	build_warning_count = 0
	build_cancelled = false
end

local function start_build(args, callback, mode_override)
	callback = callback or function() end

	if build_job then
		vim.notify("UDebugTool build is already running", vim.log.levels.WARN)
		return callback(false, "build already running")
	end

	local ctx, err = current_context()
	if not ctx then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return callback(false, err)
	end

	if config.values.build.autosave ~= false then
		save_modified_project_buffers(ctx.root)
	end

	local opts = parse_build_args(args, ctx, mode_override)
	local cmd, cmd_err = build_command(ctx, opts)
	if not cmd then
		vim.notify(tostring(cmd_err), vim.log.levels.ERROR)
		return callback(false, cmd_err)
	end

	reset_diagnostics()
	setup_highlights()

	local title = string.format("UDebugTool build: %s %s %s", opts.target, opts.platform, opts.configuration)
	local sink = build_output_sink(title)
	build_output = sink
	if sink.kind == "buffer" then
		build_buf = sink.buf
	end

	if sink.kind == "panel" then
		sink.panel.replace(sink.key, {
			"Project: " .. ctx.uproject,
			"Engine:  " .. ctx.engine_root,
			"Command: " .. table.concat(cmd, " "),
			"",
		}, {
			title = "Build",
			kind = "build",
			focus = true,
			line_groups = {
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
			},
		})
	else
		append_build_chunk(sink, ctx.root, "Project: " .. ctx.uproject .. "\nEngine:  " .. ctx.engine_root .. "\nCommand: " .. table.concat(cmd, " ") .. "\n", true)
	end

	local project_root = ctx.root
	build_job = vim.system(cmd, {
		cwd = ctx.root,
		text = true,
		stdout = function(_, data)
			append_build_chunk(sink, project_root, data, false)
		end,
		stderr = function(_, data)
			append_build_chunk(sink, project_root, data, true)
		end,
	}, function(result)
		build_job = nil
		build_pid = nil
		local this_buf = build_buf
		local this_output = build_output
		build_buf = nil
		build_output = nil
		local was_cancelled = build_cancelled

		vim.schedule(function()
			if not was_cancelled then
				local ok = result.code == 0
				local summary = build_summary(ok, result.code)
				local level = ok and vim.log.levels.INFO or vim.log.levels.ERROR

				if this_output and this_output.kind == "panel" then
					this_output.panel.append(this_output.key, {"", summary}, {
						focus = false,
						line_groups = { nil, ok and "UCoreOutputSuccess" or "UCoreOutputError" },
					})
					if ok then
						this_output.panel.finish(this_output.key, nil, { open = true })
					else
						this_output.panel.fail(this_output.key, nil, { open = true, focus = false })
					end
				elseif this_buf and vim.api.nvim_buf_is_valid(this_buf) then
					append_lines(this_buf, "")
					append_lines(this_buf, summary)
				end

				vim.notify(summary, level)
				fill_quickfix()
				callback(ok, result, ctx)
			else
				vim.notify("UDebugTool build stopped", vim.log.levels.WARN)
				callback(false, "cancelled")
			end
		end)
	end)
	build_pid = build_job and build_job.pid or nil
end

local function is_windows()
	return package.config:sub(1, 1) == "\\"
end

local function kill_process_tree(pid)
	if not pid then
		return false
	end
	if is_windows() then
		vim.system({ "taskkill", "/PID", tostring(pid), "/T", "/F" }, { text = true }, function() end)
		return true
	end
	if build_job then
		return pcall(function()
			build_job:kill(15)
		end)
	end
	return false
end

function M.build(args)
	start_build(args)
end

function M.build_async(args, callback, mode_override)
	start_build(args, callback, mode_override)
end

function M.cancel_build()
	if not build_job then
		return vim.notify("No UDebugTool build is running", vim.log.levels.INFO)
	end

	build_cancelled = true
	local buf = build_buf
	local sink = build_output
	local pid = build_pid or (build_job and build_job.pid) or nil
	kill_process_tree(pid)
	build_job = nil
	build_pid = nil
	build_buf = nil
	build_output = nil

	if sink and sink.kind == "panel" then
		sink.panel.append(sink.key, {"", "UDebugTool build stopped"}, {
			focus = false,
			line_groups = { nil, "UCoreOutputWarning" },
		})
		sink.panel.finish(sink.key, nil, { open = true, status = "success" })
	elseif buf and vim.api.nvim_buf_is_valid(buf) then
		append_lines(buf, "")
		append_lines(buf, "UDebugTool build stopped")
	end
end

return M
