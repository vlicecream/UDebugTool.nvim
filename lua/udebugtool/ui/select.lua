local M = {}

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
