local M = {}

local state = {}

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
	echo(message, "ModeMsg")
end

function M.progress_finish(title, message)
	state[title] = nil
	vim.schedule(function()
		vim.notify(message, vim.log.levels.INFO)
	end)
end

function M.progress_fail(title, message)
	state[title] = nil
	vim.schedule(function()
		vim.notify(message, vim.log.levels.ERROR)
	end)
end

return M
