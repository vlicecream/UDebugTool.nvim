local M = {}

local spinner_frames = { "⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽" }
local spinner_index = 1
local spinner_scheduled = false
local render_scheduled = false
local highlight_ns = vim.api.nvim_create_namespace("udebugtool.status.float")

local panel = {
	title = "UDebugTool Init",
	notify_id = "udebugtool.status.debug",
	items = {},
	ordered_keys = {},
	spinner_active_keys = {},
	notify_handle = nil,
	state = "running",
	dismiss_version = 0,
}

local float_state = {
	buf = nil,
	win = nil,
}

local function uses_builtin_notify()
	local info = debug.getinfo(vim.notify, "S")
	local source = tostring(info and info.source or "")
	return source:find("vim/_core/editor.lua", 1, true) ~= nil
end

local function panel_has_spinner_items()
	for key, active in pairs(panel.spinner_active_keys) do
		if active and panel.items[key] then
			return true
		end
	end
	return false
end

local function spinner_frame()
	return spinner_frames[spinner_index] or spinner_frames[1]
end

local function render_line(key, message)
	if panel.spinner_active_keys[key] and message and message ~= "" then
		return string.format("%s %s", message, spinner_frame())
	end
	return tostring(message or "")
end

local function panel_lines()
	local lines = {}
	local seen = {}

	for _, key in ipairs(panel.ordered_keys) do
		if panel.items[key] then
			lines[#lines + 1] = render_line(key, panel.items[key])
			seen[key] = true
		end
	end

	for key, line in pairs(panel.items) do
		if not seen[key] then
			lines[#lines + 1] = render_line(key, line)
		end
	end

	return lines
end

local function close_float()
	if float_state.win and vim.api.nvim_win_is_valid(float_state.win) then
		pcall(vim.api.nvim_win_close, float_state.win, true)
	end
	float_state.win = nil

	if float_state.buf and vim.api.nvim_buf_is_valid(float_state.buf) then
		pcall(vim.api.nvim_buf_delete, float_state.buf, { force = true })
	end
	float_state.buf = nil
end

local function ensure_float_buf()
	if float_state.buf and vim.api.nvim_buf_is_valid(float_state.buf) then
		return float_state.buf
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	float_state.buf = buf
	return buf
end

local function float_text_width(lines)
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	return math.max(width, 1)
end

local function float_display_lines()
	local lines = panel_lines()
	if #lines == 0 then
		return lines
	end

	lines[1] = string.format("%s: %s", panel.title, lines[1])
	for index = 2, #lines do
		lines[index] = string.format("%s  %s", panel.title, lines[index])
	end
	return lines
end

local function render_float()
	local lines = float_display_lines()
	if #lines == 0 then
		close_float()
		panel.notify_handle = nil
		return
	end

	local width = math.min(float_text_width(lines), math.max(vim.o.columns - 4, 1))
	local height = #lines
	local buf = ensure_float_buf()
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
	vim.bo[buf].modifiable = false

	local config = {
		relative = "editor",
		anchor = "NE",
		row = 1,
		col = vim.o.columns - 1,
		width = width,
		height = height,
		style = "minimal",
		focusable = false,
		noautocmd = true,
		zindex = 250,
	}

	if float_state.win and vim.api.nvim_win_is_valid(float_state.win) then
		pcall(vim.api.nvim_win_set_config, float_state.win, config)
	else
		float_state.win = vim.api.nvim_open_win(buf, false, config)
		vim.wo[float_state.win].winblend = 0
		vim.wo[float_state.win].wrap = false
		vim.wo[float_state.win].cursorline = false
	end

	local highlight = panel.state == "failed" and "DiagnosticError" or "Comment"
	for index, _ in ipairs(lines) do
		local prefix = panel.title .. ":"
		pcall(vim.api.nvim_buf_add_highlight, buf, highlight_ns, highlight, index - 1, 0, #prefix)
	end
end

local function render_notify()
	local lines = panel_lines()
	if #lines == 0 then
		if panel.notify_handle then
			pcall(vim.notify, "", vim.log.levels.INFO, {
				id = panel.notify_id,
				title = panel.title,
				replace = panel.notify_handle,
				timeout = 1,
			})
		end
		panel.notify_handle = nil
		return
	end

	local level = panel.state == "failed" and vim.log.levels.ERROR or vim.log.levels.INFO
	local ok, handle = pcall(vim.notify, table.concat(lines, "\n"), level, {
		id = panel.notify_id,
		title = panel.title,
		replace = panel.notify_handle,
		timeout = false,
	})
	if ok and handle then
		panel.notify_handle = handle
	end
end

local function render_now()
	if uses_builtin_notify() then
		render_float()
		panel.notify_handle = nil
		return
	end

	close_float()
	render_notify()
end

local function render()
	if vim.in_fast_event() then
		if render_scheduled then
			return
		end
		render_scheduled = true
		vim.schedule(function()
			render_scheduled = false
			render_now()
		end)
		return
	end

	render_now()
end

local function bump_dismiss_version()
	panel.dismiss_version = (panel.dismiss_version or 0) + 1
end

local function schedule_dismiss(delay_ms)
	local version = panel.dismiss_version
	vim.defer_fn(function()
		if panel.dismiss_version ~= version then
			return
		end
		if panel.state == "failed" or panel_has_spinner_items() or next(panel.items) ~= nil then
			return
		end
		render()
	end, delay_ms or 5000)
end

local function schedule_spinner()
	if spinner_scheduled or not panel_has_spinner_items() then
		return
	end

	spinner_scheduled = true
	vim.defer_fn(function()
		spinner_scheduled = false
		if not panel_has_spinner_items() then
			return
		end

		spinner_index = (spinner_index % #spinner_frames) + 1
		render()
		schedule_spinner()
	end, 120)
end

local function ensure_key(title)
	local key = "progress:" .. tostring(title or "progress")
	for _, existing in ipairs(panel.ordered_keys) do
		if existing == key then
			return key
		end
	end
	panel.ordered_keys[#panel.ordered_keys + 1] = key
	return key
end

local function remove_key(key)
	for index = #panel.ordered_keys, 1, -1 do
		if panel.ordered_keys[index] == key then
			table.remove(panel.ordered_keys, index)
		end
	end
	panel.items[key] = nil
	panel.spinner_active_keys[key] = nil
end

function M.progress(title, message)
	local key = ensure_key(title)
	panel.items[key] = tostring(message or "")
	panel.spinner_active_keys[key] = true
	panel.state = "running"
	bump_dismiss_version()
	render()
	schedule_spinner()
end

function M.progress_finish(title, message)
	local key = ensure_key(title)
	panel.spinner_active_keys[key] = nil
	panel.items[key] = tostring(message or "")
	panel.state = "complete"
	bump_dismiss_version()
	render()

	vim.defer_fn(function()
		remove_key(key)
		bump_dismiss_version()
		render()
		schedule_dismiss(1)
	end, 5000)
end

function M.progress_fail(title, message)
	local key = ensure_key(title)
	panel.spinner_active_keys[key] = nil
	panel.items[key] = tostring(message or "")
	panel.state = "failed"
	bump_dismiss_version()
	render()
end

return M
