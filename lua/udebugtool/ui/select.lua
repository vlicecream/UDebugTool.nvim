-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/udebugtool/ui/select.lua
-- Purpose: Wrap selection prompts with a lightweight helper for UDebugTool.
-- License: MIT

local M = {}

-- Show a selection prompt for the provided items.
-- 为提供的条目显示一个选择提示。
function M.items(prompt, items, opts)
	opts = opts or {}
	vim.ui.select(items, {
		prompt = prompt,
		format_item = opts.format_item,
	}, function(choice)
		if choice and opts.on_choice then
			opts.on_choice(choice)
		end
	end)
end

return M
