local config = require("udebugtool.config")
local project = require("udebugtool.project")

local M = {}

local ns = vim.api.nvim_create_namespace("udebugtool_debug_ui")

local state = {
	left = { win = nil, buf = nil, items = {} },
	right = { win = nil, buf = nil, items = {} },
	bottom = { win = nil, buf = nil, items = {} },
	session = nil,
	running = false,
	watches = {},
	watch_root = nil,
	watch_values = {},
	children_cache = {},
	expanded = {},
	selected_watch = nil,
	stop_event = nil,
}

local truncate

local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

local function path_join(...)
	local parts = {}
	for _, part in ipairs({ ... }) do
		part = tostring(part or "")
		if part ~= "" then
			table.insert(parts, part)
		end
	end
	return normalize(table.concat(parts, "/"))
end

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function current_session()
	local ok, dap = pcall(require, "dap")
	if ok and dap then
		return dap.session() or state.session
	end
	return state.session
end

local function is_ui_win(win)
	return win == state.left.win or win == state.right.win or win == state.bottom.win
end

local function close_win(win)
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function find_anchor_win()
	local current = vim.api.nvim_get_current_win()
	if valid_win(current) and not is_ui_win(current) then
		return current
	end

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if valid_win(win) and not is_ui_win(win) then
			return win
		end
	end

	return current
end

local function ui_layout()
	local ui = ((config.values.debug or {}).ui or {})
	local cols = vim.o.columns
	local rows = vim.o.lines - vim.o.cmdheight
	return {
		sidebar_width = math.max(30, math.min(46, tonumber(ui.sidebar_width) or math.floor(cols * 0.25))),
		inspect_width = math.max(38, math.min(70, tonumber(ui.inspect_width) or math.floor(cols * 0.33))),
		tray_height = math.max(7, math.min(14, tonumber(ui.tray_height) or math.floor(rows * 0.18))),
		persist_watches = ui.persist_watches ~= false,
	}
end

local function ensure_buf(slot, name, filetype)
	if valid_buf(slot.buf) then
		return slot.buf
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = filetype
	pcall(vim.api.nvim_buf_set_name, buf, name)
	slot.buf = buf
	slot.items = {}
	return buf
end

local function setup_window(win, opts)
	if not valid_win(win) then
		return
	end

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].spell = false
	vim.wo[win].wrap = opts.wrap == true
	vim.wo[win].cursorline = opts.cursorline ~= false
	vim.wo[win].winfixwidth = opts.winfixwidth == true
	vim.wo[win].winfixheight = opts.winfixheight == true
	vim.wo[win].list = false
	vim.wo[win].conceallevel = 0
end

local function apply_buffer_keymaps(slot_name, buf)
	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, {
			buffer = buf,
			silent = true,
			nowait = true,
			desc = desc,
		})
	end

	map("<CR>", function()
		M.activate_current_item(slot_name)
	end, "UDebugTool activate item")
	map("q", M.close, "UDebugTool close ui")
	map("r", function()
		M.refresh(current_session())
	end, "UDebugTool refresh ui")
	map("R", function()
		M.refresh(current_session())
	end, "UDebugTool refresh ui")
	map("a", M.prompt_watch, "UDebugTool add watch")
	map("d", M.delete_selected_watch, "UDebugTool delete watch")
	map("c", function()
		require("udebugtool.debug").continue()
	end, "UDebugTool continue")
	map("o", function()
		require("udebugtool.debug").step_over()
	end, "UDebugTool step over")
	map("i", function()
		require("udebugtool.debug").step_into()
	end, "UDebugTool step into")
	map("u", function()
		require("udebugtool.debug").step_out()
	end, "UDebugTool step out")
	map("s", function()
		require("udebugtool.debug").stop()
	end, "UDebugTool stop")
end

local function open_left()
	local buf = ensure_buf(state.left, "UDebugToolSidebar", "udebugtool-debug-sidebar")
	if valid_win(state.left.win) then
		vim.api.nvim_win_set_width(state.left.win, ui_layout().sidebar_width)
		return state.left.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = find_anchor_win()
	pcall(vim.api.nvim_set_current_win, anchor)
	vim.cmd("topleft vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	pcall(vim.api.nvim_set_current_win, current)

	state.left.win = win
	setup_window(win, { cursorline = true, winfixwidth = true })
	vim.api.nvim_win_set_width(win, ui_layout().sidebar_width)
	apply_buffer_keymaps("left", buf)
	return win, buf
end

local function open_right()
	local buf = ensure_buf(state.right, "UDebugToolInspect", "udebugtool-debug-inspect")
	if valid_win(state.right.win) then
		vim.api.nvim_win_set_width(state.right.win, ui_layout().inspect_width)
		return state.right.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = find_anchor_win()
	pcall(vim.api.nvim_set_current_win, anchor)
	vim.cmd("botright vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	pcall(vim.api.nvim_set_current_win, current)

	state.right.win = win
	setup_window(win, { cursorline = true, winfixwidth = true })
	vim.api.nvim_win_set_width(win, ui_layout().inspect_width)
	apply_buffer_keymaps("right", buf)
	return win, buf
end

local function open_bottom()
	local buf = ensure_buf(state.bottom, "UDebugToolControls", "udebugtool-debug-controls")
	if valid_win(state.bottom.win) then
		vim.api.nvim_win_set_height(state.bottom.win, ui_layout().tray_height)
		return state.bottom.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = find_anchor_win()
	pcall(vim.api.nvim_set_current_win, anchor)
	vim.cmd("botright split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	pcall(vim.api.nvim_set_current_win, current)

	state.bottom.win = win
	setup_window(win, { cursorline = false, winfixheight = true, wrap = false })
	vim.api.nvim_win_set_height(win, ui_layout().tray_height)
	apply_buffer_keymaps("bottom", buf)
	return win, buf
end

local function set_lines(slot, lines, items, highlights)
	local buf = slot.buf
	if not valid_buf(buf) then
		return
	end

	vim.bo[buf].modifiable = true
	vim.bo[buf].readonly = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	slot.items = items or {}
	for _, hl in ipairs(highlights or {}) do
		pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.group, hl.line, hl.start_col or 0, hl.end_col or -1)
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
end

local function add_hl(highlights, group, line, start_col, end_col)
	table.insert(highlights, {
		group = group,
		line = line,
		start_col = start_col or 0,
		end_col = end_col or -1,
	})
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "UDebugToolTitle", { fg = "#E5EFFF", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolSection", { fg = "#93C5FD", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolLabel", { fg = "#7C8FB8" })
	vim.api.nvim_set_hl(0, "UDebugToolValue", { fg = "#DBE7FF" })
	vim.api.nvim_set_hl(0, "UDebugToolAccent", { fg = "#86EFAC" })
	vim.api.nvim_set_hl(0, "UDebugToolMuted", { fg = "#64748B" })
	vim.api.nvim_set_hl(0, "UDebugToolCurrent", { fg = "#38BDF8", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolCurrentStop", { fg = "#FBBF24", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolWarn", { fg = "#FBBF24", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolDanger", { fg = "#F87171", bold = true })
end

local function short_path(path)
	path = normalize(path or "")
	if path == "" then
		return "<unknown>"
	end

	local root = normalize(state.watch_root)
	if root and path:sub(1, #root):lower() == root:lower() then
		return path:sub(#root + 2)
	end

	local cwd = normalize(vim.loop.cwd())
	if cwd and path:sub(1, #cwd):lower() == cwd:lower() then
		return path:sub(#cwd + 2)
	end

	return path
end

local function frame_location(frame)
	local source = frame and frame.source or {}
	local path = source.path or source.name or "<unknown>"
	local line = tonumber(frame and frame.line or 0) or 0
	return string.format("%s:%d", short_path(path), line)
end

truncate = function(text, max_len)
	text = tostring(text or ""):gsub("\r\n", " "):gsub("[\r\n]", " ")
	max_len = max_len or 80
	if #text <= max_len then
		return text
	end
	return text:sub(1, math.max(0, max_len - 3)) .. "..."
end

local function watch_store_path(root)
	if not root then
		return nil
	end
	return path_join(project.build_paths(root).cache_dir, "watches.json")
end

local function read_json(path)
	if not path or vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_decode then
		return nil
	end
	return decoded
end

local function write_json(path, value)
	if not path then
		return false
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":p:h"), "p")
	return pcall(vim.fn.writefile, vim.split(vim.json.encode(value), "\n", { plain = true }), path)
end

local function active_project_root()
	local frame = state.session and state.session.current_frame or nil
	local source_path = frame and frame.source and frame.source.path or nil
	if source_path and source_path ~= "" then
		local root = project.find_project_root(source_path)
		if root then
			return normalize(root)
		end
	end
	return normalize(project.find_project_root_from_context())
end

local function load_watches(root)
	if not root or ui_layout().persist_watches == false then
		return {}
	end
	local data = read_json(watch_store_path(root))
	if type(data) ~= "table" then
		return {}
	end

	local items = {}
	for _, value in ipairs(data) do
		if type(value) == "string" and vim.trim(value) ~= "" then
			table.insert(items, value)
		end
	end
	return items
end

local function save_watches()
	if ui_layout().persist_watches == false or not state.watch_root then
		return
	end
	write_json(watch_store_path(state.watch_root), state.watches)
end

local function sync_watches()
	local root = active_project_root()
	if not root or state.watch_root == root then
		return
	end

	state.watch_root = root
	state.watches = load_watches(root)
	state.watch_values = {}
	state.children_cache = {}
	if not vim.tbl_contains(state.watches, state.selected_watch) then
		state.selected_watch = state.watches[1]
	end
end

local function stop_reason_text()
	local stopped = state.stop_event or {}
	local reason = tostring(stopped.reason or "")
	if reason == "" then
		return nil
	end

	local labels = {
		breakpoint = "Breakpoint",
		exception = "Exception",
		pause = "Pause",
		step = "Step",
		entry = "Entry",
		goto = "Goto",
		["function breakpoint"] = "Function Breakpoint",
		["data breakpoint"] = "Data Breakpoint",
		["instruction breakpoint"] = "Instruction Breakpoint",
	}

	local label = labels[reason] or (reason:gsub("^%l", string.upper))
	local detail = stopped.text or stopped.description
	if detail and tostring(detail) ~= "" then
		return label .. " - " .. truncate(detail, 52)
	end
	return label
end

local function sorted_thread_ids(session)
	local ids = {}
	for id, _ in pairs(session and session.threads or {}) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function sorted_breakpoints()
	local ok, dap_breakpoints = pcall(require, "dap.breakpoints")
	if not ok then
		return {}
	end

	local items = {}
	for bufnr, points in pairs(dap_breakpoints.get()) do
		local path = normalize(vim.api.nvim_buf_get_name(bufnr))
		for _, bp in ipairs(points) do
			table.insert(items, {
				path = path,
				line = tonumber(bp.line or 0) or 0,
				condition = bp.condition,
				log_message = bp.log_message or bp.logMessage,
			})
		end
	end

	table.sort(items, function(a, b)
		if (a.path or "") == (b.path or "") then
			return (a.line or 0) < (b.line or 0)
		end
		return (a.path or "") < (b.path or "")
	end)

	return items
end

local function thread_expanded(thread_id, stopped)
	local key = "thread:" .. tostring(thread_id)
	local value = state.expanded[key]
	if value == nil then
		return stopped
	end
	return value
end

local function variable_has_children(variable)
	local ref = tonumber(variable and variable.variablesReference or 0) or 0
	local named = tonumber(variable and variable.namedVariables or 0) or 0
	local indexed = tonumber(variable and variable.indexedVariables or 0) or 0
	return ref > 0 or named > 0 or indexed > 0, ref
end

local function get_children_cache(ref)
	return state.children_cache[tostring(ref)]
end

local function fetch_children(session, ref, callback)
	ref = tonumber(ref or 0) or 0
	if ref <= 0 or not session then
		return callback({}, nil)
	end

	local key = tostring(ref)
	local cache = state.children_cache[key]
	if cache and cache.loaded then
		return callback(cache.variables or {}, cache.error)
	end
	if cache and cache.pending then
		table.insert(cache.waiters, callback)
		return
	end

	cache = {
		pending = true,
		loaded = false,
		variables = {},
		waiters = { callback },
	}
	state.children_cache[key] = cache

	session:request("variables", { variablesReference = ref }, function(err, response)
		cache.pending = false
		cache.loaded = true
		cache.error = err
		cache.variables = response and response.variables or {}
		local waiters = cache.waiters or {}
		cache.waiters = {}
		for _, waiter in ipairs(waiters) do
			waiter(cache.variables, err)
		end
	end)
end

local function fetch_frame_scopes(session, frame, callback)
	if not frame or not session then
		return callback()
	end

	local scopes = frame.scopes
	if scopes and #scopes > 0 then
		local complete = true
		for _, scope in ipairs(scopes) do
			if scope.variables == nil then
				complete = false
				break
			end
		end
		if complete then
			return callback()
		end
	end

	session:request("scopes", { frameId = frame.id }, function(err, response)
		if err then
			frame.scopes = {}
			return callback()
		end

		local fetched_scopes = response and response.scopes or {}
		if vim.tbl_isempty(fetched_scopes) then
			frame.scopes = {}
			return callback()
		end

		local remaining = #fetched_scopes
		for _, scope in ipairs(fetched_scopes) do
			local ref = tonumber(scope.variablesReference or 0) or 0
			if ref > 0 then
				session:request("variables", { variablesReference = ref }, function(_, resp)
					scope.variables = resp and resp.variables or {}
					remaining = remaining - 1
					if remaining == 0 then
						frame.scopes = fetched_scopes
						callback()
					end
				end)
			else
				scope.variables = {}
				remaining = remaining - 1
				if remaining == 0 then
					frame.scopes = fetched_scopes
					callback()
				end
			end
		end
	end)
end

local function ensure_stack(session, callback)
	if not session or not session.stopped_thread_id then
		return callback()
	end

	session:update_threads(function()
		local thread = session.threads and session.threads[session.stopped_thread_id]
		if not thread then
			return callback()
		end

		if thread.frames and #thread.frames > 0 then
			if not session.current_frame then
				session.current_frame = thread.frames[1]
			end
			return callback()
		end

		session:request("stackTrace", {
			threadId = session.stopped_thread_id,
			startFrame = 0,
			levels = 30,
		}, function(_, response)
			thread.frames = response and response.stackFrames or {}
			if not session.current_frame and thread.frames[1] then
				session.current_frame = thread.frames[1]
			end
			callback()
		end)
	end)
end

local function evaluate_watches(session, callback)
	if vim.tbl_isempty(state.watches) then
		return callback()
	end
	if not session or state.running or not session.current_frame then
		state.watch_values = {}
		return callback()
	end

	local remaining = #state.watches
	for _, expression in ipairs(state.watches) do
		session:evaluate({
			expression = expression,
			context = "watch",
			frameId = session.current_frame.id,
		}, function(err, response)
			if err then
				state.watch_values[expression] = {
					error = tostring(err),
					result = "",
					variablesReference = 0,
				}
			else
				state.watch_values[expression] = {
					result = tostring((response and response.result) or ""),
					type = response and response.type or nil,
					variablesReference = tonumber(response and response.variablesReference or 0) or 0,
					namedVariables = tonumber(response and response.namedVariables or 0) or 0,
					indexedVariables = tonumber(response and response.indexedVariables or 0) or 0,
					presentationHint = response and response.presentationHint or nil,
				}
			end

			remaining = remaining - 1
			if remaining == 0 then
				callback()
			end
		end)
	end
end

local function new_builder()
	return {
		lines = {},
		items = {},
		highlights = {},
	}
end

local function push_line(builder, text, opts)
	opts = opts or {}
	table.insert(builder.lines, text)
	local row = #builder.lines
	if opts.item then
		builder.items[row] = opts.item
	end
	if opts.group then
		add_hl(builder.highlights, opts.group, row - 1, 0, -1)
	end
	for _, span in ipairs(opts.spans or {}) do
		add_hl(builder.highlights, span.group, row - 1, span.start_col or 0, span.end_col or -1)
	end
	return row
end

local function render_variable_tree(builder, session, entry, depth, item_kind, item_payload)
	local has_children, ref = variable_has_children(entry)
	local key = ref > 0 and ("ref:" .. tostring(ref)) or nil
	local expanded = key and state.expanded[key] == true or false
	local prefix = has_children and (expanded and "[-]" or "[+]") or "   "
	local indent = string.rep("  ", depth)
	local name = tostring(entry.name or entry.expression or entry.label or "?")
	local value = truncate(entry.value or entry.result or "", 72)
	local text = string.format("%s%s %s", indent, prefix, name)
	if value ~= "" then
		text = text .. " = " .. value
	end

	push_line(builder, text, {
		item = item_kind and vim.tbl_extend("force", {
			kind = item_kind,
			key = key,
			ref = ref,
		}, item_payload or {}) or nil,
		spans = {
			{ group = "UDebugToolLabel", start_col = #indent + #prefix + 1, end_col = #indent + #prefix + 2 + #name },
			{ group = "UDebugToolValue", start_col = #indent + #prefix + 2 + #name, end_col = -1 },
		},
	})

	if not (expanded and ref > 0) then
		return
	end

	local cache = get_children_cache(ref)
	if not cache then
		push_line(builder, indent .. "  loading...", { group = "UDebugToolMuted" })
		fetch_children(session, ref, function()
			vim.schedule(function()
				if M.is_open() then
					M.refresh(current_session())
				end
			end)
		end)
		return
	end

	if cache.pending then
		push_line(builder, indent .. "  loading...", { group = "UDebugToolMuted" })
		return
	end

	if cache.error then
		push_line(builder, indent .. "  " .. truncate(cache.error, 70), { group = "UDebugToolDanger" })
		return
	end

	if vim.tbl_isempty(cache.variables or {}) then
		push_line(builder, indent .. "  (empty)", { group = "UDebugToolMuted" })
		return
	end

	for _, child in ipairs(cache.variables or {}) do
		render_variable_tree(builder, session, child, depth + 1, "variable", {})
	end
end

local function render_left(session)
	local _, buf = open_left()
	local builder = new_builder()

	push_line(builder, "UDebugTool Debug", { group = "UDebugToolTitle" })
	push_line(builder, "")

	local state_text = "Idle"
	local state_group = "UDebugToolMuted"
	if session and state.running then
		state_text = "Running"
		state_group = "UDebugToolAccent"
	elseif session and session.current_frame then
		state_text = "Stopped"
		state_group = "UDebugToolWarn"
	elseif session then
		state_text = "Attached"
		state_group = "UDebugToolAccent"
	end

	push_line(builder, "Session", { group = "UDebugToolSection" })
	push_line(builder, "  State   " .. state_text, {
		spans = {
			{ group = "UDebugToolLabel", start_col = 2, end_col = 9 },
			{ group = state_group, start_col = 10, end_col = -1 },
		},
	})
	push_line(builder, "  Config  " .. tostring(session and session.config and session.config.name or "No active session"), {
		spans = {
			{ group = "UDebugToolLabel", start_col = 2, end_col = 9 },
			{ group = "UDebugToolValue", start_col = 10, end_col = -1 },
		},
	})
	if session and session.current_frame then
		push_line(builder, "  Stop    " .. frame_location(session.current_frame), {
			spans = {
				{ group = "UDebugToolLabel", start_col = 2, end_col = 9 },
				{ group = "UDebugToolValue", start_col = 10, end_col = -1 },
			},
		})
	end
	if state.stop_event then
		local why = stop_reason_text()
		if why then
			push_line(builder, "  Why     " .. why, {
				spans = {
					{ group = "UDebugToolLabel", start_col = 2, end_col = 9 },
					{ group = "UDebugToolDanger", start_col = 10, end_col = -1 },
				},
			})
		end
	end
	push_line(builder, "")

	push_line(builder, "Threads", { group = "UDebugToolSection" })
	if not session then
		push_line(builder, "  No active session", { group = "UDebugToolMuted" })
	else
		local thread_ids = sorted_thread_ids(session)
		if vim.tbl_isempty(thread_ids) then
			push_line(builder, "  Threads are loading...", { group = "UDebugToolMuted" })
		else
			for _, thread_id in ipairs(thread_ids) do
				local thread = session.threads[thread_id]
				local stopped = session.stopped_thread_id == thread_id
				local thread_key = "thread:" .. tostring(thread_id)
				local expanded = thread_expanded(thread_id, stopped)
				local prefix = stopped and "*" or "-"
				local marker = expanded and "[-]" or "[+]"
				push_line(builder, string.format("  %s %s Thread %s  %s", prefix, marker, tostring(thread_id), tostring(thread and thread.name or "")), {
					group = stopped and "UDebugToolCurrentStop" or "UDebugToolLabel",
					item = {
						kind = "thread",
						thread_id = thread_id,
						key = thread_key,
					},
				})

				if expanded then
					local frames = thread and thread.frames or {}
					if stopped and vim.tbl_isempty(frames) then
						push_line(builder, "      loading frames...", { group = "UDebugToolMuted" })
					end
					for index, frame in ipairs(frames) do
						local current = session.current_frame and session.current_frame.id == frame.id
						local frame_marker = current and ">" or " "
						push_line(builder, string.format("    %s %02d %s", frame_marker, index, truncate(frame.name or "<frame>", 28)), {
							group = current and "UDebugToolCurrentStop" or "UDebugToolValue",
							item = {
								kind = "frame",
								thread_id = thread_id,
								frame = frame,
							},
						})
						push_line(builder, "        " .. frame_location(frame), { group = "UDebugToolMuted" })
					end
				end
			end
		end
	end

	push_line(builder, "")
	push_line(builder, "Breakpoints", { group = "UDebugToolSection" })
	local breakpoints = sorted_breakpoints()
	if vim.tbl_isempty(breakpoints) then
		push_line(builder, "  none", { group = "UDebugToolMuted" })
	else
		for _, bp in ipairs(breakpoints) do
			push_line(builder, string.format("  %s:%d", short_path(bp.path), bp.line), {
				group = "UDebugToolValue",
				item = {
					kind = "breakpoint",
					path = bp.path,
					line = bp.line,
				},
			})
		end
	end

	push_line(builder, "")
	push_line(builder, "Watches", { group = "UDebugToolSection" })
	if vim.tbl_isempty(state.watches) then
		push_line(builder, "  none", { group = "UDebugToolMuted" })
	else
		for _, expression in ipairs(state.watches) do
			local watch = state.watch_values[expression] or {}
			local summary
			if state.running then
				summary = "<running>"
			elseif not session or not session.current_frame then
				summary = "<no frame>"
			elseif watch.error then
				summary = "Error"
			elseif watch.result and watch.result ~= "" then
				summary = truncate(watch.result, 24)
			else
				summary = "..."
			end

			push_line(builder, string.format("  %s = %s", expression, summary), {
				group = state.selected_watch == expression and "UDebugToolCurrent" or "UDebugToolValue",
				item = {
					kind = "watch",
					expression = expression,
					key = "watch:" .. expression,
					ref = tonumber(watch.variablesReference or 0) or 0,
				},
			})
		end
	end

	set_lines(state.left, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_right(session)
	local _, buf = open_right()
	local builder = new_builder()

	push_line(builder, "UDebugTool Inspect", { group = "UDebugToolTitle" })
	push_line(builder, "")

	if not session then
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		set_lines(state.right, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	if state.running or not session.current_frame then
		push_line(builder, "Program is running", { group = "UDebugToolAccent" })
		set_lines(state.right, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	local frame = session.current_frame
	push_line(builder, "Current Stop", { group = "UDebugToolSection" })
	push_line(builder, "  Function  " .. tostring(frame.name or "<frame>"), {
		spans = {
			{ group = "UDebugToolLabel", start_col = 2, end_col = 12 },
			{ group = "UDebugToolValue", start_col = 13, end_col = -1 },
		},
	})
	push_line(builder, "  Location  " .. frame_location(frame), {
		spans = {
			{ group = "UDebugToolLabel", start_col = 2, end_col = 12 },
			{ group = "UDebugToolValue", start_col = 13, end_col = -1 },
		},
	})
	push_line(builder, "  Thread    " .. tostring(session.stopped_thread_id or "?"), {
		spans = {
			{ group = "UDebugToolLabel", start_col = 2, end_col = 12 },
			{ group = "UDebugToolValue", start_col = 13, end_col = -1 },
		},
	})
	local stop_reason = stop_reason_text()
	if stop_reason then
		push_line(builder, "  Reason    " .. stop_reason, {
			spans = {
				{ group = "UDebugToolLabel", start_col = 2, end_col = 12 },
				{ group = "UDebugToolDanger", start_col = 13, end_col = -1 },
			},
		})
	end
	push_line(builder, "")

	push_line(builder, "Variables", { group = "UDebugToolSection" })
	local scopes = frame.scopes or {}
	if vim.tbl_isempty(scopes) then
		push_line(builder, "  Loading scopes...", { group = "UDebugToolMuted" })
	else
		for _, scope in ipairs(scopes) do
			local scope_key = string.format("scope:%s:%s", tostring(frame.id), tostring(scope.name or "Scope"))
			local expanded = state.expanded[scope_key]
			if expanded == nil then
				expanded = true
			end
			local prefix = expanded and "[-]" or "[+]"
			push_line(builder, string.format("%s %s", prefix, tostring(scope.name or "Scope")), {
				group = "UDebugToolLabel",
				item = {
					kind = "scope",
					key = scope_key,
				},
			})
			if expanded then
				for _, variable in ipairs(scope.variables or {}) do
					render_variable_tree(builder, session, variable, 1, "variable", {})
				end
			end
			push_line(builder, "")
		end
	end

	push_line(builder, "Watches", { group = "UDebugToolSection" })
	if vim.tbl_isempty(state.watches) then
		push_line(builder, "  none", { group = "UDebugToolMuted" })
	else
		for _, expression in ipairs(state.watches) do
			local watch = state.watch_values[expression] or {}
			local has_children, ref = variable_has_children(watch)
			local key = "watch:" .. expression
			local expanded = state.expanded[key] == true
			local prefix = has_children and (expanded and "[-]" or "[+]") or "   "
			local value
			local value_group = "UDebugToolValue"

			if state.running then
				value = "<running>"
				value_group = "UDebugToolMuted"
			elseif not session.current_frame then
				value = "<no frame>"
				value_group = "UDebugToolMuted"
			elseif watch.error then
				value = watch.error
				value_group = "UDebugToolDanger"
			else
				value = watch.result or ""
			end

			local text = string.format("%s %s", prefix, expression)
			if value ~= "" then
				text = text .. " = " .. truncate(value, 72)
			end

			push_line(builder, text, {
				group = state.selected_watch == expression and "UDebugToolCurrent" or nil,
				item = {
					kind = "watch",
					expression = expression,
					key = key,
					ref = ref,
				},
				spans = {
					{ group = state.selected_watch == expression and "UDebugToolCurrent" or "UDebugToolLabel", start_col = #prefix + 1, end_col = #prefix + 2 + #expression },
					{ group = value_group, start_col = #prefix + 2 + #expression, end_col = -1 },
				},
			})

			if expanded and ref > 0 then
				local cache = get_children_cache(ref)
				if not cache then
					push_line(builder, "  loading...", { group = "UDebugToolMuted" })
					fetch_children(session, ref, function()
						vim.schedule(function()
							if M.is_open() then
								M.refresh(current_session())
							end
						end)
					end)
				elseif cache.pending then
					push_line(builder, "  loading...", { group = "UDebugToolMuted" })
				elseif cache.error then
					push_line(builder, "  " .. truncate(cache.error, 70), { group = "UDebugToolDanger" })
				elseif vim.tbl_isempty(cache.variables or {}) then
					push_line(builder, "  (empty)", { group = "UDebugToolMuted" })
				else
					for _, variable in ipairs(cache.variables or {}) do
						render_variable_tree(builder, session, variable, 1, "variable", {})
					end
				end
			end
		end
	end

	set_lines(state.right, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_bottom(session)
	local _, buf = open_bottom()
	local builder = new_builder()

	push_line(builder, "UDebugTool Controls", { group = "UDebugToolTitle" })

	local summary
	if not session then
		summary = "State: Idle"
	elseif state.running then
		summary = "State: Running"
	elseif session.current_frame then
		summary = "State: Stopped  |  " .. tostring(session.current_frame.name or "<frame>") .. "  |  " .. frame_location(session.current_frame)
	else
		summary = "State: Attached"
	end
	push_line(builder, summary, { group = session and (state.running and "UDebugToolAccent" or "UDebugToolWarn") or "UDebugToolMuted" })
	if state.stop_event and state.stop_event.reason then
		push_line(builder, "Stop Reason: " .. truncate(stop_reason_text() or state.stop_event.reason, 80), {
			group = "UDebugToolDanger",
		})
	end
	push_line(builder, "")
	push_line(builder, "[c] Continue   [o] Step Over   [i] Step Into   [u] Step Out   [s] Stop", {
		group = "UDebugToolValue",
	})
	push_line(builder, "[CR] Jump / Expand   [a] Add Watch   [d] Delete Watch   [r] Refresh   [q] Close", {
		group = "UDebugToolValue",
	})
	if state.selected_watch and state.selected_watch ~= "" then
		push_line(builder, "Selected Watch: " .. state.selected_watch, {
			spans = {
				{ group = "UDebugToolLabel", start_col = 0, end_col = 14 },
				{ group = "UDebugToolCurrent", start_col = 15, end_col = -1 },
			},
		})
	end

	set_lines(state.bottom, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_all(session)
	render_left(session)
	render_right(session)
	render_bottom(session)
end

local function jump_to_breakpoint(path, line)
	if not path or path == "" then
		return
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
	pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(line or 1), 0 })
	vim.cmd("normal! zz")
end

local function toggle_item(item)
	if not item then
		return
	end
	if item.key then
		state.expanded[item.key] = not state.expanded[item.key]
	end
	if item.ref and item.ref > 0 and state.expanded[item.key] and state.session then
		return fetch_children(state.session, item.ref, function()
			vim.schedule(function()
				render_all(state.session)
			end)
		end)
	end
	render_all(state.session)
end

local function focus_thread(session, thread_id)
	if not session or not thread_id then
		return
	end

	session.stopped_thread_id = thread_id
	local thread = session.threads and session.threads[thread_id]
	if thread and thread.frames and thread.frames[1] then
		session:_frame_set(thread.frames[1])
		return vim.defer_fn(function()
			M.refresh(session)
		end, 80)
	end

	session:request("stackTrace", {
		threadId = thread_id,
		startFrame = 0,
		levels = 30,
	}, function(_, response)
		thread = session.threads and session.threads[thread_id] or thread or {}
		thread.frames = response and response.stackFrames or {}
		if session.threads then
			session.threads[thread_id] = thread
		end
		if thread.frames[1] then
			session:_frame_set(thread.frames[1])
		end
		vim.schedule(function()
			M.refresh(session)
		end)
	end)
end

local function current_item(slot_name)
	local slot = state[slot_name]
	if not slot or not valid_win(slot.win) then
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(slot.win)[1]
	return slot.items[row]
end

local function current_slot_name()
	local win = vim.api.nvim_get_current_win()
	if win == state.left.win then
		return "left"
	end
	if win == state.right.win then
		return "right"
	end
	if win == state.bottom.win then
		return "bottom"
	end
	return nil
end

function M.open()
	setup_highlights()
	sync_watches()
	open_left()
	open_right()
	open_bottom()
end

function M.close()
	close_win(state.left.win)
	close_win(state.right.win)
	close_win(state.bottom.win)
	state.left.win = nil
	state.right.win = nil
	state.bottom.win = nil
	state.left.buf = nil
	state.right.buf = nil
	state.bottom.buf = nil
	state.left.items = {}
	state.right.items = {}
	state.bottom.items = {}
end

function M.is_open()
	return valid_win(state.left.win) or valid_win(state.right.win) or valid_win(state.bottom.win)
end

function M.mark_running(session)
	state.session = session
	state.running = true
	state.stop_event = nil
	sync_watches()
	M.open()
	render_all(session)
end

function M.refresh(session)
	state.session = session
	state.running = false
	sync_watches()
	M.open()

	if not session then
		render_all(nil)
		return
	end

	ensure_stack(session, function()
		fetch_frame_scopes(session, session.current_frame, function()
			evaluate_watches(session, function()
				vim.schedule(function()
					render_all(session)
				end)
			end)
		end)
	end)
end

function M.activate_current_item(slot_name)
	slot_name = slot_name or current_slot_name()
	if not slot_name then
		return
	end

	local item = current_item(slot_name)
	if not item then
		return
	end

	if item.kind == "frame" and item.frame and state.session then
		state.session.stopped_thread_id = item.thread_id
		state.session:_frame_set(item.frame)
		return vim.defer_fn(function()
			M.refresh(state.session)
		end, 80)
	end

	if item.kind == "thread" and state.session then
		if item.key then
			local stopped = state.session.stopped_thread_id == item.thread_id
			local expanded = thread_expanded(item.thread_id, stopped)
			state.expanded[item.key] = not expanded
			if state.expanded[item.key] and stopped then
				return focus_thread(state.session, item.thread_id)
			end
			render_all(state.session)
			return
		end
		return focus_thread(state.session, item.thread_id)
	end

	if item.kind == "breakpoint" then
		return jump_to_breakpoint(item.path, item.line)
	end

	if item.kind == "watch" then
		state.selected_watch = item.expression
		if item.ref and item.ref > 0 then
			return toggle_item(item)
		end
		render_all(state.session)
		return
	end

	if item.kind == "scope" or item.kind == "variable" then
		return toggle_item(item)
	end
end

function M.set_stop_event(body)
	state.stop_event = body or nil
end

function M.prompt_watch()
	sync_watches()
	vim.ui.input({ prompt = "UDebugTool watch expression: " }, function(input)
		local expression = vim.trim(tostring(input or ""))
		if expression == "" then
			return
		end
		if not vim.tbl_contains(state.watches, expression) then
			table.insert(state.watches, expression)
		end
		state.selected_watch = expression
		save_watches()
		M.refresh(current_session())
	end)
end

function M.delete_selected_watch()
	local slot_name = current_slot_name()
	local item = slot_name and current_item(slot_name) or nil
	local expression = item and item.kind == "watch" and item.expression or state.selected_watch
	if not expression or expression == "" then
		return vim.notify("UDebugTool: no watch selected", vim.log.levels.INFO)
	end

	for index = #state.watches, 1, -1 do
		if state.watches[index] == expression then
			table.remove(state.watches, index)
		end
	end
	state.watch_values[expression] = nil
	state.expanded["watch:" .. expression] = nil
	if state.selected_watch == expression then
		state.selected_watch = state.watches[1]
	end
	save_watches()
	M.refresh(current_session())
end

function M.reset()
	M.close()
	state.session = nil
	state.running = false
	state.stop_event = nil
	state.watches = {}
	state.watch_root = nil
	state.watch_values = {}
	state.children_cache = {}
	state.expanded = {}
	state.selected_watch = nil
end

return M
