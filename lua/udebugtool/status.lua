local M = {}

local state = {}
local progress_ids = {}

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
	state[title] = message
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
	state[title] = nil
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
	state[title] = nil
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
