if vim.g.loaded_udebugtool == 1 then
	return
end

vim.g.loaded_udebugtool = 1

require("udebugtool").setup()
