-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: plugin/UDebugTool.lua
-- Purpose: Bootstrap the plugin lifecycle and reload guard for UDebugTool.
-- License: MIT

-- Unload the current UDebugTool module graph before reloading.
-- 在重新加载前卸载当前 UDebugTool 模块图。
local function unload_udebugtool()
	local ok, existing = pcall(require, "udebugtool")
	if ok and type(existing) == "table" and type(existing.reset) == "function" then
		pcall(existing.reset)
	end

	for name, _ in pairs(package.loaded) do
		if name == "udebugtool" or name:match("^udebugtool%.") then
			package.loaded[name] = nil
		end
	end
end

if vim.g.loaded_udebugtool == 1 then
	unload_udebugtool()
else
	vim.g.loaded_udebugtool = 1
end

require("udebugtool").setup()
