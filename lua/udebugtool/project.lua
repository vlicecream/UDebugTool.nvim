local config = require("udebugtool.config")

local M = {}

local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

local function readable(path)
	return path and vim.fn.filereadable(path) == 1
end

local function path_exists(path)
	return readable(path) or vim.fn.isdirectory(path) == 1
end

local function path_join(...)
	return normalize(table.concat({ ... }, "/"):gsub("//+", "/"))
end

local function project_cache_name(project_root)
	local normalized = normalize(project_root)
	local name = vim.fn.fnamemodify(normalized, ":t")
	local hash = vim.fn.sha256(normalized):sub(1, 12)
	if name == "" then
		return hash
	end
	return name .. "-" .. hash
end

local function read_json_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local ok_decode, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_decode then
		return nil
	end
	return data
end

local function engine_association_candidates(association)
	if not association or association == "" then
		return {}
	end
	local items = { association }
	if not association:match("^UE_") then
		table.insert(items, "UE_" .. association)
	end
	if association:match("^UE_") then
		table.insert(items, association:gsub("^UE_", ""))
	end
	return items
end

function M.find_project_file(start_path)
	start_path = start_path or vim.api.nvim_buf_get_name(0)
	if start_path == "" then
		start_path = vim.loop.cwd()
	end
	if start_path == "" then
		return nil
	end

	local dir
	if vim.fn.isdirectory(start_path) == 1 then
		dir = start_path
	else
		dir = vim.fn.fnamemodify(start_path, ":p:h")
	end

	local found = vim.fs.find(function(name)
		return name:match("%.uproject$")
	end, {
		path = dir,
		upward = true,
		type = "file",
		limit = 1,
	})[1]

	return found and normalize(found) or nil
end

function M.find_project_root(start_path)
	local project_file = M.find_project_file(start_path)
	if not project_file then
		return nil
	end
	return normalize(vim.fn.fnamemodify(project_file, ":p:h"))
end

function M.find_project_root_from_context()
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path and buf_path ~= "" then
		local root = M.find_project_root(buf_path)
		if root then
			return root
		end
	end

	local cwd = vim.loop.cwd()
	if cwd then
		local root = M.find_project_root(cwd)
		if root then
			return root
		end
	end

	local alt = vim.fn.bufnr("#")
	if alt and alt > 0 then
		local alt_path = vim.api.nvim_buf_get_name(alt)
		if alt_path and alt_path ~= "" then
			local root = M.find_project_root(alt_path)
			if root then
				return root
			end
		end
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local bo = vim.bo[bufnr]
		if bo.buflisted and bo.buftype == "" and bo.modifiable then
			local path = vim.api.nvim_buf_get_name(bufnr)
			if path and path ~= "" then
				local root = M.find_project_root(path)
				if root then
					return root
				end
			end
		end
	end

	return nil
end

function M.find_project_file_in_root(project_root)
	local files = vim.fn.glob(project_root .. "/*.uproject", false, true)
	return files[1] and normalize(files[1]) or nil
end

function M.read_engine_association(uproject_path)
	if not uproject_path or vim.fn.filereadable(uproject_path) ~= 1 then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, uproject_path)
	if not ok then
		return nil
	end
	local ok_decode, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_decode or type(data) ~= "table" then
		return nil
	end
	return data.EngineAssociation
end

function M.is_engine_root(path)
	if not path or path == "" then
		return false
	end
	path = normalize(path)
	return vim.fn.isdirectory(path .. "/Engine/Source") == 1
		or vim.fn.filereadable(path .. "/Engine/Build/Build.version") == 1
end

function M.find_engine_root_from_config(association)
	for _, key in ipairs(engine_association_candidates(association)) do
		local root = config.values.engine_roots and config.values.engine_roots[key]
		if M.is_engine_root(root) then
			return normalize(root)
		end
	end
	return nil
end

function M.find_engine_root_from_launcher(association)
	local data = read_json_file("C:/ProgramData/Epic/UnrealEngineLauncher/LauncherInstalled.dat")
	if type(data) ~= "table" or type(data.InstallationList) ~= "table" then
		return nil
	end

	local candidates = {}
	for _, key in ipairs(engine_association_candidates(association)) do
		candidates[key] = true
	end

	for _, item in ipairs(data.InstallationList) do
		if candidates[item.AppName] and M.is_engine_root(item.InstallLocation) then
			return normalize(item.InstallLocation)
		end
	end
	return nil
end

function M.find_engine_root_from_registry(association)
	if vim.fn.has("win32") ~= 1 then
		return nil
	end

	local output = vim.fn.systemlist({
		"reg",
		"query",
		"HKCU\\Software\\Epic Games\\Unreal Engine\\Builds",
	})
	if vim.v.shell_error ~= 0 then
		return nil
	end

	local candidates = {}
	for _, key in ipairs(engine_association_candidates(association)) do
		candidates[key] = true
	end

	for _, line in ipairs(output) do
		line = vim.trim(line)
		local name, path = line:match("^(%S+)%s+REG_SZ%s+(.+)$")
		path = path and vim.trim(path)
		if name and path and candidates[name] and M.is_engine_root(path) then
			return normalize(path)
		end
	end

	return nil
end

function M.resolve_engine_root(project_root)
	project_root = normalize(project_root)
	local uproject_path = M.find_project_file_in_root(project_root)
	local association = M.read_engine_association(uproject_path)
	if not association or association == "" then
		return nil, "No EngineAssociation in .uproject"
	end
	if M.is_engine_root(association) then
		return normalize(association), association
	end

	local root = M.find_engine_root_from_config(association)
		or M.find_engine_root_from_launcher(association)
		or M.find_engine_root_from_registry(association)
	if root then
		return root, association
	end
	return nil, "Could not resolve Unreal Engine root for EngineAssociation: " .. tostring(association)
end

function M.engine_metadata(project_root)
	local engine_root, association_or_err = M.resolve_engine_root(project_root)
	if not engine_root then
		return nil, association_or_err
	end
	local uproject_path = M.find_project_file_in_root(project_root)
	local association = M.read_engine_association(uproject_path)
	return {
		engine_association = association,
		engine_root = engine_root,
	}
end

function M.project_name(root)
	local project_file = M.find_project_file_in_root(root)
	if not project_file then
		return vim.fn.fnamemodify(root, ":t")
	end
	return vim.fn.fnamemodify(project_file, ":t:r")
end

function M.editor_target_name(root)
	local base_name = M.project_name(root)
	local preferred = base_name .. "Editor"
	local candidates = vim.fn.glob(path_join(root, "Source/*.Target.cs"), false, true)
	local fallback = nil

	for _, path in ipairs(candidates) do
		local name = tostring(path):match("([^/\\]+)%.Target%.cs$")
		if name then
			if name == preferred then
				return preferred
			end
			if name:match("Editor$") and not fallback then
				fallback = name
			end
		end
	end

	return fallback or preferred
end

function M.game_target_name(root)
	local base_name = M.project_name(root)
	local candidates = vim.fn.glob(path_join(root, "Source/*.Target.cs"), false, true)
	local fallback = nil

	for _, path in ipairs(candidates) do
		local name = tostring(path):match("([^/\\]+)%.Target%.cs$")
		if name then
			if name == base_name then
				return base_name
			end
			if not name:match("Editor$") and not name:match("Server$") and not name:match("Client$") and not fallback then
				fallback = name
			end
		end
	end

	return fallback or base_name
end

function M.build_paths(project_root)
	local cache_dir = normalize(config.values.cache_dir)
	local project_cache_dir = path_join(cache_dir, "projects", project_cache_name(project_root))
	vim.fn.mkdir(project_cache_dir, "p")
	return {
		project_root = normalize(project_root),
		cache_dir = project_cache_dir,
	}
end

return M
