local M = {}

local state = {}
local progress_ids = {}

local function shared_output_panel()
	local panel = rawget(_G, "__ucore_output_panel_api")
	if type(panel) == "table" and type(panel.replace) == "function" then
		return panel
	end
	return nil
end

local function progress_key(title)
	return "udebugtool:progress:" .. tostring(title or "progress")
end

local function uses_builtin_notify()
	local info = debug.getinfo(vim.notify, "S")
	local source = tostring(info and info.source or "")
	return source:find("vim/_core/editor.lua", 1, true) ~= nil
end

local function parse_percent(text)
	local best = nil
	for token in tostring(text or ""):gmatch("(%d?%d?%d)%%") do
		local value = tonumber(token)
		if value and value >= 0 and value <= 100 then
			best = best and math.max(best, value) or value
		end
	end
	return best
end

local function echo(message, hl)
	if #vim.api.nvim_list_uis() == 0 then
		return
	end

	vim.schedule(function()
		pcall(vim.api.nvim_echo, { { tostring(message), hl or "Normal" } }, false, {})
	end)
end

function M.progress(title, message)
	local panel = shared_output_panel()
	local first = state[title] == nil
	state[title] = message
	if panel then
		panel.replace(progress_key(title), { tostring(message) }, {
			title = title,
			kind = "debug",
			focus = first,
			status = "running",
			line_groups = { "UCoreOutputInfo" },
		})
		return
	end
	if uses_builtin_notify() then
		local ok, id = pcall(vim.api.nvim_echo, {
			{ tostring(message), "Normal" },
		}, false, {
			id = progress_ids[title],
			kind = "progress",
			title = title,
			status = "running",
			percent = parse_percent(message),
			source = "udebugtool.status",
		})
		if ok and id then
			progress_ids[title] = id
		end
		return
	end
	echo(message, "ModeMsg")
end

function M.progress_finish(title, message)
	local panel = shared_output_panel()
	state[title] = nil
	if panel then
		panel.replace(progress_key(title), { tostring(message) }, {
			title = title,
			kind = "debug",
			focus = false,
			status = "success",
			line_groups = { "UCoreOutputSuccess" },
		})
		panel.finish(progress_key(title), nil, { open = true, focus = false })
		return
	end
	if uses_builtin_notify() then
		local ok, id = pcall(vim.api.nvim_echo, {
			{ tostring(message), "Normal" },
		}, false, {
			id = progress_ids[title],
			kind = "progress",
			title = title,
			status = "success",
			percent = parse_percent(message) or 100,
			source = "udebugtool.status",
		})
		if ok and id then
			progress_ids[title] = id
		end
		return
	end
	vim.schedule(function()
		vim.notify(message, vim.log.levels.INFO)
	end)
end

function M.progress_fail(title, message)
	local panel = shared_output_panel()
	state[title] = nil
	if panel then
		panel.replace(progress_key(title), { tostring(message) }, {
			title = title,
			kind = "debug",
			focus = true,
			status = "failed",
			line_groups = { "UCoreOutputError" },
		})
		panel.fail(progress_key(title), nil, { open = true, focus = true })
		return
	end
	if uses_builtin_notify() then
		local ok, id = pcall(vim.api.nvim_echo, {
			{ tostring(message), "Normal" },
		}, false, {
			id = progress_ids[title],
			kind = "progress",
			title = title,
			status = "failed",
			percent = parse_percent(message) or 100,
			source = "udebugtool.status",
		})
		if ok and id then
			progress_ids[title] = id
		end
		return
	end
	vim.schedule(function()
		vim.notify(message, vim.log.levels.ERROR)
	end)
end

return M
