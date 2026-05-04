local config = require("udebugtool.config")
local project = require("udebugtool.project")

local M = {}

local ns = vim.api.nvim_create_namespace("udebugtool_debug_ui")

local state = {
	left = { win = nil, buf = nil, items = {} },
	right = { win = nil, buf = nil, items = {} },
	bottom = { win = nil, buf = nil, items = {} },
	scopes = { win = nil, buf = nil, items = {} },
	breakpoints = { win = nil, buf = nil, items = {} },
	stacks = { win = nil, buf = nil, items = {} },
	watches_panel = { win = nil, buf = nil, items = {} },
	controls = { win = nil, buf = nil, items = {} },
	console = { win = nil, buf = nil, items = {} },
	toolbar = { win = nil, buf = nil, items = {} },
	hover = { win = nil, buf = nil },
	session = nil,
	running = false,
	watches = {},
	watch_root = nil,
	watch_values = {},
	children_cache = {},
	expanded = {},
	breakpoints_muted = false,
	selected_watch = nil,
	selected_item = nil,
	stop_event = nil,
	console_lines = {},
	console_groups = {},
}

local truncate

local function shared_output_panel()
	local panel = rawget(_G, "__ucore_output_panel_api")
	if type(panel) == "table" and type(panel.open_tab) == "function" then
		return panel
	end
	return nil
end

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
	return win == state.left.win
		or win == state.right.win
		or win == state.bottom.win
		or win == state.scopes.win
		or win == state.breakpoints.win
		or win == state.stacks.win
		or win == state.watches_panel.win
		or win == state.controls.win
		or win == state.console.win
		or win == state.toolbar.win
end

local function close_win(win)
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function close_hover()
	if valid_win(state.hover.win) then
		pcall(vim.api.nvim_win_close, state.hover.win, true)
	end
	state.hover.win = nil
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

local function open_split_from_anchor(anchor, cmd)
	local current = vim.api.nvim_get_current_win()
	local before = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		before[win] = true
	end

	pcall(vim.api.nvim_set_current_win, anchor)
	vim.cmd(cmd)

	local created = nil
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if not before[win] then
			created = win
			break
		end
	end
	pcall(vim.api.nvim_set_current_win, current)
	return created or anchor
end

local function ui_layout()
	local ui = ((config.values.debug or {}).ui or {})
	local cols = vim.o.columns
	local rows = vim.o.lines - vim.o.cmdheight
	local output_panel = shared_output_panel()
	local output_offset = output_panel and output_panel.is_open and output_panel.is_open() and 13 or 0
	local usable_rows = math.max(24, rows - output_offset - 2)
	local sidebar_width = math.max(30, math.min(46, tonumber(ui.sidebar_width) or math.floor(cols * 0.24)))
	local tray_height = math.max(8, math.min(16, tonumber(ui.tray_height) or math.floor(usable_rows * 0.22)))
	return {
		sidebar_width = sidebar_width,
		locals_height = tonumber(ui.locals_height) or 0.42,
		breakpoints_height = tonumber(ui.breakpoints_height) or 0.23,
		stacks_height = tonumber(ui.stacks_height) or 0.35,
		tray_height = tray_height,
		stack_height = tray_height,
		inspect_height = tray_height,
		watches_width = tonumber(ui.watches_width) or 0.34,
		controls_width = tonumber(ui.controls_width) or 0.22,
		console_width = tonumber(ui.console_width) or 0.44,
		toolbar_width = math.max(56, math.min(84, tonumber(ui.toolbar_width) or 74)),
		toolbar_height = 3,
		output_offset = output_offset,
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

local function ensure_hover_buf()
	if valid_buf(state.hover.buf) then
		return state.hover.buf
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "udebugtool-hover"
	pcall(vim.api.nvim_buf_set_name, buf, "UDebugToolHover")
	state.hover.buf = buf
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
	map("x", M.delete_selected_watch, "UDebugTool delete watch")
end

local function hover_float_opts(width, height, position, title)
	local max_height = math.max(8, math.floor((vim.o.lines - vim.o.cmdheight) * 0.45))
	local max_width = math.max(36, math.floor(vim.o.columns * 0.35))
	width = math.min(width, max_width)
	height = math.min(height, max_height)
	local row = position.line + math.min(0, vim.o.lines - (height + position.line + 3))
	local col = position.col + math.min(0, vim.o.columns - (width + position.col + 3))
	return {
		relative = "editor",
		row = row,
		col = col,
		anchor = "NW",
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = title and "center" or nil,
	}
end

local function open_hover_lines(lines, position, title)
	close_hover()
	local buf = ensure_hover_buf()
	local width = 1
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(tostring(line)))
	end
	local opts = hover_float_opts(width + 2, #lines, position, title)
	vim.bo[buf].modifiable = true
	vim.bo[buf].readonly = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	local win = vim.api.nvim_open_win(buf, false, opts)
	state.hover.win = win
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = false
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"

	local group = vim.api.nvim_create_augroup("UDebugToolHover", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter", "WinLeave" }, {
		group = group,
		once = true,
		callback = function()
			close_hover()
		end,
	})
end

local function open_left()
	local buf = ensure_buf(state.left, "UDebugToolLocals", "udebugtool-debug-locals")
	if valid_win(state.left.win) then
		vim.api.nvim_win_set_width(state.left.win, ui_layout().sidebar_width)
		return state.left.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = find_anchor_win()
	local win = open_split_from_anchor(anchor, "topleft vsplit")
	vim.api.nvim_win_set_buf(win, buf)

	state.left.win = win
	setup_window(win, { cursorline = true, winfixwidth = true, winfixheight = false })
	vim.api.nvim_win_set_width(win, ui_layout().sidebar_width)
	apply_buffer_keymaps("left", buf)
	return win, buf
end

local function open_right()
	local buf = ensure_buf(state.right, "UDebugToolInspect", "udebugtool-debug-inspect")
	if valid_win(state.right.win) then
		vim.api.nvim_win_set_width(state.right.win, ui_layout().sidebar_width)
		vim.api.nvim_win_set_height(state.right.win, ui_layout().inspect_height)
		return state.right.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = valid_win(state.bottom.win) and state.bottom.win or select(1, open_bottom())
	local win = open_split_from_anchor(anchor, "botright split")
	vim.api.nvim_win_set_buf(win, buf)

	state.right.win = win
	setup_window(win, { cursorline = true, winfixwidth = true, winfixheight = true })
	vim.api.nvim_win_set_width(win, ui_layout().sidebar_width)
	vim.api.nvim_win_set_height(win, ui_layout().inspect_height)
	apply_buffer_keymaps("right", buf)
	return win, buf
end

local function open_bottom()
	local buf = ensure_buf(state.bottom, "UDebugToolStack", "udebugtool-debug-stack")
	if valid_win(state.bottom.win) then
		vim.api.nvim_win_set_width(state.bottom.win, ui_layout().sidebar_width)
		vim.api.nvim_win_set_height(state.bottom.win, ui_layout().stack_height)
		return state.bottom.win, buf
	end

	local current = vim.api.nvim_get_current_win()
	local anchor = valid_win(state.left.win) and state.left.win or select(1, open_left())
	local win = open_split_from_anchor(anchor, "botright split")
	vim.api.nvim_win_set_buf(win, buf)

	state.bottom.win = win
	setup_window(win, { cursorline = true, winfixheight = true, winfixwidth = true, wrap = false })
	vim.api.nvim_win_set_width(win, ui_layout().sidebar_width)
	vim.api.nvim_win_set_height(win, ui_layout().stack_height)
	apply_buffer_keymaps("bottom", buf)
	return win, buf
end

local function open_toolbar()
	local buf = ensure_buf(state.toolbar, "UDebugToolToolbar", "udebugtool-debug-toolbar")
	local layout = ui_layout()
	local width = math.min(layout.toolbar_width, math.max(52, vim.o.columns - layout.sidebar_width - 8))
	local row = math.max(1, vim.o.lines - vim.o.cmdheight - layout.output_offset - layout.toolbar_height - 3)
	local col = math.max(layout.sidebar_width + 3, math.floor((vim.o.columns - width) / 2))
	local win_config = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = layout.toolbar_height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 70,
		noautocmd = true,
	}

	if valid_win(state.toolbar.win) then
		vim.api.nvim_win_set_config(state.toolbar.win, win_config)
		if vim.api.nvim_win_get_buf(state.toolbar.win) ~= buf then
			vim.api.nvim_win_set_buf(state.toolbar.win, buf)
		end
		return state.toolbar.win, buf
	end

	local win = vim.api.nvim_open_win(buf, false, win_config)
	state.toolbar.win = win
	setup_window(win, { cursorline = false, winfixheight = true, wrap = false })
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"
	return win, buf
end

local function resize_sidebar_layout()
	local layout = ui_layout()
	local wins = { state.scopes.win, state.breakpoints.win, state.stacks.win }
	local valid = {}
	for _, win in ipairs(wins) do
		if valid_win(win) then
			table.insert(valid, win)
			vim.api.nvim_win_set_width(win, layout.sidebar_width)
		end
	end
	if #valid == 0 then
		return
	end

	local total = 0
	for _, win in ipairs(valid) do
		total = total + vim.api.nvim_win_get_height(win)
	end
	if total <= 0 then
		return
	end

	local ratios = {
		layout.locals_height,
		layout.breakpoints_height,
		layout.stacks_height,
	}
	local assigned = 0
	for index, win in ipairs(valid) do
		local target
		if index == #valid then
			target = math.max(1, total - assigned)
		else
			target = math.max(1, math.floor(total * (ratios[index] or 0.25)))
			assigned = assigned + target
		end
		pcall(vim.api.nvim_win_set_height, win, target)
	end
end

local function resize_tray_layout()
	local layout = ui_layout()
	local wins = { state.watches_panel.win, state.controls.win, state.console.win }
	local valid = {}
	for _, win in ipairs(wins) do
		if valid_win(win) then
			table.insert(valid, win)
			pcall(vim.api.nvim_win_set_height, win, layout.tray_height)
		end
	end

	if #valid == 0 then
		return
	end

	local total = 0
	for _, win in ipairs(valid) do
		total = total + vim.api.nvim_win_get_width(win)
	end
	if total <= 0 then
		return
	end

	local targets = {
		math.max(24, math.floor(total * layout.watches_width)),
		math.max(20, math.floor(total * layout.controls_width)),
		math.max(28, math.floor(total * layout.console_width)),
	}
	local assigned = 0
	for index, win in ipairs(valid) do
		local width
		if index == #valid then
			width = math.max(20, total - assigned)
		else
			width = targets[index] or math.max(20, math.floor(total / #valid))
			assigned = assigned + width
		end
		pcall(vim.api.nvim_win_set_width, win, width)
	end
end

local function ensure_sidebar_layout()
	local scopes_buf = ensure_buf(state.scopes, "UDebugToolLocals", "udebugtool-debug-locals")
	local breakpoints_buf = ensure_buf(state.breakpoints, "UDebugToolBreakpoints", "udebugtool-debug-breakpoints")
	local stacks_buf = ensure_buf(state.stacks, "UDebugToolStacks", "udebugtool-debug-stacks")
	if valid_win(state.scopes.win) and valid_win(state.breakpoints.win) and valid_win(state.stacks.win) then
		resize_sidebar_layout()
		return
	end

	local anchor = find_anchor_win()
	local scopes_win = open_split_from_anchor(anchor, "topleft vsplit")
	local breakpoints_win = open_split_from_anchor(scopes_win, "split")
	local stacks_win = open_split_from_anchor(breakpoints_win, "split")

	state.scopes.win = scopes_win
	state.breakpoints.win = breakpoints_win
	state.stacks.win = stacks_win

	vim.api.nvim_win_set_buf(scopes_win, scopes_buf)
	vim.api.nvim_win_set_buf(breakpoints_win, breakpoints_buf)
	vim.api.nvim_win_set_buf(stacks_win, stacks_buf)

	setup_window(scopes_win, { cursorline = true, winfixwidth = true })
	setup_window(breakpoints_win, { cursorline = true, winfixwidth = true })
	setup_window(stacks_win, { cursorline = true, winfixwidth = true })
	apply_buffer_keymaps("scopes", scopes_buf)
	apply_buffer_keymaps("breakpoints", breakpoints_buf)
	apply_buffer_keymaps("stacks", stacks_buf)
	resize_sidebar_layout()
end

local function ensure_tray_layout()
	local watches_buf = ensure_buf(state.watches_panel, "UDebugToolWatches", "udebugtool-debug-watches")
	local controls_buf = ensure_buf(state.controls, "UDebugToolControls", "udebugtool-debug-controls")
	local console_buf = ensure_buf(state.console, "UDebugToolConsole", "udebugtool-debug-console")
	if valid_win(state.watches_panel.win) and valid_win(state.controls.win) and valid_win(state.console.win) then
		resize_tray_layout()
		return
	end

	local anchor = find_anchor_win()
	local watches_win = open_split_from_anchor(anchor, "botright split")
	local controls_win = open_split_from_anchor(watches_win, "vsplit")
	local console_win = open_split_from_anchor(controls_win, "vsplit")

	state.watches_panel.win = watches_win
	state.controls.win = controls_win
	state.console.win = console_win

	vim.api.nvim_win_set_buf(watches_win, watches_buf)
	vim.api.nvim_win_set_buf(controls_win, controls_buf)
	vim.api.nvim_win_set_buf(console_win, console_buf)
	setup_window(watches_win, { cursorline = true, winfixheight = true })
	setup_window(controls_win, { cursorline = false, winfixheight = true, wrap = false })
	setup_window(console_win, { cursorline = false, winfixheight = true, wrap = false })
	apply_buffer_keymaps("watches_panel", watches_buf)
	apply_buffer_keymaps("controls", controls_buf)
	apply_buffer_keymaps("console", console_buf)
	resize_tray_layout()
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
	vim.api.nvim_set_hl(0, "UDebugToolMarker", { fg = "#FBBF24" })
	vim.api.nvim_set_hl(0, "UDebugToolCurrent", { fg = "#38BDF8", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolCurrentStop", { fg = "#FBBF24", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolWarn", { fg = "#FBBF24", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolDanger", { fg = "#F87171", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolToolbarKey", { fg = "#E5EFFF", bold = true })
	vim.api.nvim_set_hl(0, "UDebugToolToolbarHot", { fg = "#4FC1FF", bold = true })
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

local function source_line_text(path, line)
	path = normalize(path or "")
	line = tonumber(line or 0) or 0
	if path == "" or line <= 0 then
		return nil
	end

	local bufnr = vim.fn.bufnr(path)
	if tonumber(bufnr or -1) >= 0 and vim.api.nvim_buf_is_loaded(bufnr) then
		local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)
		local text = lines and lines[1] or nil
		if text and vim.trim(text) ~= "" then
			return vim.trim(text)
		end
	end

	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or type(lines) ~= "table" then
		return nil
	end
	local text = lines[line]
	if text and vim.trim(text) ~= "" then
		return vim.trim(text)
	end
	return nil
end

local function console_highlight_group(text, explicit)
	if explicit and explicit ~= "" then
		return explicit
	end
	local lower = tostring(text or ""):lower()
	if lower:find("fatal error", 1, true)
		or lower:find(" error:", 1, true)
		or lower:find("exception", 1, true)
	then
		return "UDebugToolDanger"
	end
	if lower:find(" warning:", 1, true) or lower:find(": warning ", 1, true) then
		return "UDebugToolWarn"
	end
	if lower:find("breakpoint", 1, true) or lower:find("stopped", 1, true) then
		return "UDebugToolCurrentStop"
	end
	return "UDebugToolValue"
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
		["goto"] = "Goto",
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
			name = name,
			value = entry.value or entry.result or "",
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

	push_line(builder, "Locals", { group = "UDebugToolTitle" })

	if not session then
		push_line(builder, "")
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		push_line(builder, "")
		push_line(builder, "Stack", { group = "UDebugToolSection" })
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		push_line(builder, "")
		push_line(builder, "Inspect", { group = "UDebugToolSection" })
		push_line(builder, "Select a variable, scope, frame, or watch.", { group = "UDebugToolMuted" })
		set_lines(state.left, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	if state.running or not session.current_frame then
		push_line(builder, "")
		push_line(builder, "Program is running", { group = "UDebugToolAccent" })
	else
		push_line(builder, frame_location(session.current_frame), { group = "UDebugToolMuted" })
		push_line(builder, "")

		local scopes = session.current_frame.scopes or {}
		if vim.tbl_isempty(scopes) then
			push_line(builder, "Loading locals...", { group = "UDebugToolMuted" })
		else
			for _, scope in ipairs(scopes) do
				local scope_name = tostring(scope.name or "Scope")
				local scope_key = string.format("scope:%s:%s", tostring(session.current_frame.id or "?"), scope_name)
				local expanded = state.expanded[scope_key]
				if expanded == nil then
					local lower = scope_name:lower()
					expanded = lower:find("local", 1, true) ~= nil or lower:find("argument", 1, true) ~= nil or #scopes == 1
				end
				local prefix = expanded and "▾" or "▸"
				push_line(builder, string.format("%s %s", prefix, scope_name), {
					group = "UDebugToolSection",
					item = {
						kind = "scope",
						key = scope_key,
						scope = scope,
						name = scope_name,
					},
				})
				if expanded then
					for _, variable in ipairs(scope.variables or {}) do
						render_variable_tree(builder, session, variable, 1, "variable", {
							scope_name = scope_name,
						})
					end
				end
				push_line(builder, "")
			end
		end
	end

	push_line(builder, "")
	push_line(builder, "Stack", { group = "UDebugToolTitle" })
	if state.running then
		push_line(builder, "Running", { group = "UDebugToolAccent" })
	elseif stop_reason_text() then
		push_line(builder, stop_reason_text(), { group = "UDebugToolWarn" })
	end

	local ids = sorted_thread_ids(session)
	if vim.tbl_isempty(ids) then
		push_line(builder, "Waiting for threads...", { group = "UDebugToolMuted" })
	else
		for _, thread_id in ipairs(ids) do
			local thread = session.threads and session.threads[thread_id] or {}
			local stopped = session.stopped_thread_id == thread_id
			local expanded = thread_expanded(thread_id, stopped)
			local prefix = expanded and "▾" or "▸"
			local label = tostring(thread.name or ("Thread " .. tostring(thread_id)))
			push_line(builder, string.format("%s %s", prefix, label), {
				group = stopped and "UDebugToolCurrentStop" or "UDebugToolSection",
				item = {
					kind = "thread",
					key = "thread:" .. tostring(thread_id),
					thread_id = thread_id,
				},
			})
			if expanded then
				local frames = thread.frames or {}
				if vim.tbl_isempty(frames) then
					push_line(builder, "  loading...", { group = "UDebugToolMuted" })
				else
					for index, frame in ipairs(frames) do
						local current = session.current_frame and frame.id == session.current_frame.id
						push_line(builder, string.format("  %02d %s", index, tostring(frame.name or "<frame>")), {
							group = current and "UDebugToolCurrent" or "UDebugToolValue",
							item = {
								kind = "frame",
								frame = frame,
								thread_id = thread_id,
								name = frame.name or "<frame>",
								value = frame_location(frame),
							},
						})
						push_line(builder, "     " .. frame_location(frame), {
							group = current and "UDebugToolCurrent" or "UDebugToolMuted",
							item = {
								kind = "frame",
								frame = frame,
								thread_id = thread_id,
								name = frame.name or "<frame>",
								value = frame_location(frame),
							},
						})
					end
				end
			end
			push_line(builder, "")
		end
	end

	push_line(builder, "")
	push_line(builder, "Inspect", { group = "UDebugToolTitle" })
	local selected = state.selected_item
	if not selected and state.selected_watch and state.watch_values[state.selected_watch] then
		local watch = state.watch_values[state.selected_watch]
		selected = {
			kind = "watch",
			expression = state.selected_watch,
			name = state.selected_watch,
			value = watch.result or "",
			ref = tonumber(watch.variablesReference or 0) or 0,
			key = "watch:" .. state.selected_watch,
		}
	end

	if selected then
		local label = selected.expression or selected.name or selected.scope_name or "Selection"
		push_line(builder, tostring(label), { group = "UDebugToolSection" })
		if selected.value and tostring(selected.value) ~= "" then
			push_line(builder, "  " .. truncate(selected.value, 68), { group = "UDebugToolValue" })
		end
		if selected.kind == "scope" and selected.scope then
			for _, variable in ipairs(selected.scope.variables or {}) do
				render_variable_tree(builder, session, variable, 1, "variable", {})
			end
		elseif (tonumber(selected.ref or 0) or 0) > 0 then
			render_selected_children(builder, session, tonumber(selected.ref or 0) or 0, 1)
		elseif not selected.value or tostring(selected.value) == "" then
			push_line(builder, "  No children", { group = "UDebugToolMuted" })
		end
	else
		push_line(builder, "Select a variable, scope, frame, or watch.", { group = "UDebugToolMuted" })
	end

	push_line(builder, "")
	push_line(builder, "Watches", { group = "UDebugToolTitle" })
	if vim.tbl_isempty(state.watches) then
		push_line(builder, "  none", { group = "UDebugToolMuted" })
	else
		for _, expression in ipairs(state.watches) do
			local watch = state.watch_values[expression] or {}
			local summary = watch.error or watch.result or "<pending>"
			local ref = tonumber(watch.variablesReference or 0) or 0
			push_line(builder, string.format("  %s = %s", expression, truncate(summary, 52)), {
				group = state.selected_watch == expression and "UDebugToolCurrent" or "UDebugToolValue",
				item = {
					kind = "watch",
					expression = expression,
					key = "watch:" .. expression,
					ref = ref,
					name = expression,
					value = watch.result or watch.error or "",
				},
			})
		end
	end

	set_lines(state.left, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_stack_panel(session)
	local _, buf = open_bottom()
	local builder = new_builder()

	push_line(builder, "Stack", { group = "UDebugToolTitle" })

	if not session then
		push_line(builder, "")
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		set_lines(state.bottom, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	local ids = sorted_thread_ids(session)
	if vim.tbl_isempty(ids) then
		push_line(builder, "")
		push_line(builder, "Waiting for threads...", { group = "UDebugToolMuted" })
		set_lines(state.bottom, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	push_line(builder, stop_reason_text() or (state.running and "Running" or "Stopped"), {
		group = state.running and "UDebugToolAccent" or "UDebugToolWarn",
	})
	push_line(builder, "")

	for _, thread_id in ipairs(ids) do
		local thread = session.threads and session.threads[thread_id] or {}
		local stopped = session.stopped_thread_id == thread_id
		local expanded = thread_expanded(thread_id, stopped)
		local prefix = expanded and "▾" or "▸"
		local label = tostring(thread.name or ("Thread " .. tostring(thread_id)))
		push_line(builder, string.format("%s %s", prefix, label), {
			group = stopped and "UDebugToolCurrentStop" or "UDebugToolSection",
			item = {
				kind = "thread",
				key = "thread:" .. tostring(thread_id),
				thread_id = thread_id,
			},
		})

		if expanded then
			local frames = thread.frames or {}
			if vim.tbl_isempty(frames) then
				push_line(builder, "  loading...", { group = "UDebugToolMuted" })
			else
				for index, frame in ipairs(frames) do
					local current = session.current_frame and frame.id == session.current_frame.id
					push_line(builder, string.format("  %02d %s  %s", index, tostring(frame.name or "<frame>"), frame_location(frame)), {
						group = current and "UDebugToolCurrent" or "UDebugToolValue",
						item = {
							kind = "frame",
							frame = frame,
							thread_id = thread_id,
						},
					})
				end
			end
		end

		push_line(builder, "")
	end

	set_lines(state.bottom, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_selected_children(builder, session, ref, depth)
	local cache = get_children_cache(ref)
	if not cache then
		push_line(builder, string.rep("  ", depth) .. "loading...", { group = "UDebugToolMuted" })
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
		push_line(builder, string.rep("  ", depth) .. "loading...", { group = "UDebugToolMuted" })
		return
	end
	if cache.error then
		push_line(builder, string.rep("  ", depth) .. truncate(cache.error, 70), { group = "UDebugToolDanger" })
		return
	end
	if vim.tbl_isempty(cache.variables or {}) then
		push_line(builder, string.rep("  ", depth) .. "(empty)", { group = "UDebugToolMuted" })
		return
	end
	for _, variable in ipairs(cache.variables or {}) do
		render_variable_tree(builder, session, variable, depth, "variable", {})
	end
end

local function render_right(session)
	local _, buf = open_right()
	local builder = new_builder()

	push_line(builder, "Inspect", { group = "UDebugToolTitle" })

	if not session then
		push_line(builder, "")
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		set_lines(state.right, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	local selected = state.selected_item
	if not selected and state.selected_watch and state.watch_values[state.selected_watch] then
		local watch = state.watch_values[state.selected_watch]
		selected = {
			kind = "watch",
			expression = state.selected_watch,
			name = state.selected_watch,
			value = watch.result or "",
			ref = tonumber(watch.variablesReference or 0) or 0,
			key = "watch:" .. state.selected_watch,
		}
	end

	push_line(builder, session.current_frame and frame_location(session.current_frame) or "No frame", { group = "UDebugToolMuted" })
	push_line(builder, "")

	if selected then
		local label = selected.expression or selected.name or selected.scope_name or "Selection"
		push_line(builder, tostring(label), { group = "UDebugToolSection" })
		if selected.value and tostring(selected.value) ~= "" then
			push_line(builder, "  " .. truncate(selected.value, 80), { group = "UDebugToolValue" })
		end
		if selected.kind == "scope" and selected.scope then
			for _, variable in ipairs(selected.scope.variables or {}) do
				render_variable_tree(builder, session, variable, 1, "variable", {})
			end
		elseif (tonumber(selected.ref or 0) or 0) > 0 then
			render_selected_children(builder, session, tonumber(selected.ref or 0) or 0, 1)
		elseif not selected.value or tostring(selected.value) == "" then
			push_line(builder, "  No children", { group = "UDebugToolMuted" })
		end
	else
		push_line(builder, "Select a variable, scope, frame, or watch.", { group = "UDebugToolMuted" })
	end

	push_line(builder, "")
	push_line(builder, "Watches", { group = "UDebugToolSection" })
	if vim.tbl_isempty(state.watches) then
		push_line(builder, "  none", { group = "UDebugToolMuted" })
	else
		for _, expression in ipairs(state.watches) do
			local watch = state.watch_values[expression] or {}
			local summary = watch.error or watch.result or "<pending>"
			local ref = tonumber(watch.variablesReference or 0) or 0
			push_line(builder, string.format("  %s = %s", expression, truncate(summary, 52)), {
				group = state.selected_watch == expression and "UDebugToolCurrent" or "UDebugToolValue",
				item = {
					kind = "watch",
					expression = expression,
					key = "watch:" .. expression,
					ref = ref,
					name = expression,
					value = watch.result or watch.error or "",
				},
			})
		end
	end

	set_lines(state.right, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_toolbar(session)
	local _, buf = open_toolbar()
	local builder = new_builder()
	local icons = "  ▶ Continue   ■ Stop   ⤼ Over   ⤶ Into   ⤴ Out   ● Break   ◌ Mute"
	local keys = "   dc          ds         do        di        du       db       dn/dm"
	local summary

	if not session then
		summary = "Idle"
	elseif state.running then
		summary = "Running"
	elseif session.current_frame then
		summary = "Stopped  |  " .. truncate(tostring(session.current_frame.name or "<frame>"), 28)
	else
		summary = "Attached"
	end

	push_line(builder, icons, {
		group = "UDebugToolValue",
		spans = {
			{ group = "UDebugToolToolbarHot", start_col = 2, end_col = 3 },
			{ group = "UDebugToolToolbarHot", start_col = 15, end_col = 16 },
			{ group = "UDebugToolToolbarHot", start_col = 24, end_col = 25 },
			{ group = "UDebugToolToolbarHot", start_col = 34, end_col = 35 },
			{ group = "UDebugToolToolbarHot", start_col = 44, end_col = 45 },
			{ group = "UDebugToolDanger", start_col = 52, end_col = 53 },
			{ group = state.breakpoints_muted and "UDebugToolDanger" or "UDebugToolMuted", start_col = 62, end_col = 63 },
		},
	})
	push_line(builder, keys, { group = "UDebugToolMuted" })
	push_line(builder, "  " .. summary, {
		group = not session and "UDebugToolMuted" or (state.running and "UDebugToolAccent" or "UDebugToolWarn"),
	})

	set_lines(state.toolbar, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_scopes_panel(session)
	local buf = ensure_buf(state.scopes, "UDebugToolLocals", "udebugtool-debug-locals")
	local builder = new_builder()
	push_line(builder, "Locals", { group = "UDebugToolTitle" })

	if not session then
		push_line(builder, "")
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		set_lines(state.scopes, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	if state.running or not session.current_frame then
		push_line(builder, "")
		push_line(builder, "Program is running", { group = "UDebugToolAccent" })
		set_lines(state.scopes, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	push_line(builder, frame_location(session.current_frame), { group = "UDebugToolMuted" })
	push_line(builder, "")
	local scopes = session.current_frame.scopes or {}
	if vim.tbl_isempty(scopes) then
		push_line(builder, "Loading scopes...", { group = "UDebugToolMuted" })
	else
		for _, scope in ipairs(scopes) do
			local scope_name = tostring(scope.name or "Scope")
			local scope_key = string.format("scope:%s:%s", tostring(session.current_frame.id or "?"), scope_name)
			local expanded = state.expanded[scope_key]
			if expanded == nil then
				expanded = true
			end
			local prefix = expanded and "▾" or "▸"
			push_line(builder, string.format("%s %s", prefix, scope_name), {
				group = "UDebugToolSection",
				item = {
					kind = "scope",
					key = scope_key,
					scope = scope,
					name = scope_name,
				},
			})
			if expanded then
				for _, variable in ipairs(scope.variables or {}) do
					render_variable_tree(builder, session, variable, 1, "variable", {
						scope_name = scope_name,
					})
				end
			end
			push_line(builder, "")
		end
	end
	set_lines(state.scopes, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_breakpoints_panel()
	local buf = ensure_buf(state.breakpoints, "UDebugToolBreakpoints", "udebugtool-debug-breakpoints")
	local builder = new_builder()
	push_line(builder, "Breakpoints", { group = "UDebugToolTitle" })
	push_line(builder, state.breakpoints_muted and "Muted" or "Enabled", {
		group = state.breakpoints_muted and "UDebugToolDanger" or "UDebugToolAccent",
	})
	push_line(builder, "")
	local breakpoints = sorted_breakpoints()
	if vim.tbl_isempty(breakpoints) then
		push_line(builder, "No breakpoints", { group = "UDebugToolMuted" })
	else
		for _, bp in ipairs(breakpoints) do
			local location = string.format("%s:%d", short_path(bp.path), bp.line)
			local source_text = source_line_text(bp.path, bp.line)
			local item = {
				kind = "breakpoint",
				path = bp.path,
				line = bp.line,
				name = short_path(bp.path),
				value = tostring(bp.line),
			}
			push_line(builder, location, {
				group = "UDebugToolMarker",
				item = item,
			})
			if source_text then
				push_line(builder, "  " .. truncate(source_text, 60), {
					group = "UDebugToolValue",
					item = item,
				})
			end
			push_line(builder, "")
		end
	end
	set_lines(state.breakpoints, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_stacks_panel(session)
	local buf = ensure_buf(state.stacks, "UDebugToolStacks", "udebugtool-debug-stacks")
	local builder = new_builder()
	push_line(builder, "Stacks", { group = "UDebugToolTitle" })
	if not session then
		push_line(builder, "")
		push_line(builder, "No active session", { group = "UDebugToolMuted" })
		set_lines(state.stacks, builder.lines, builder.items, builder.highlights)
		vim.bo[buf].modifiable = false
		return
	end

	local reason = stop_reason_text()
	if reason then
		push_line(builder, reason, { group = "UDebugToolWarn" })
	elseif state.running then
		push_line(builder, "Running", { group = "UDebugToolAccent" })
	end
	push_line(builder, "")

	local ids = sorted_thread_ids(session)
	if vim.tbl_isempty(ids) then
		push_line(builder, "Waiting for threads...", { group = "UDebugToolMuted" })
	else
		for _, thread_id in ipairs(ids) do
			local thread = session.threads and session.threads[thread_id] or {}
			local stopped = session.stopped_thread_id == thread_id
			local expanded = thread_expanded(thread_id, stopped)
			local prefix = expanded and "▾" or "▸"
			local label = tostring(thread.name or ("Thread " .. tostring(thread_id)))
			push_line(builder, string.format("%s %s", prefix, label), {
				group = stopped and "UDebugToolCurrentStop" or "UDebugToolSection",
				item = {
					kind = "thread",
					key = "thread:" .. tostring(thread_id),
					thread_id = thread_id,
					name = label,
				},
			})
			if expanded then
				local frames = thread.frames or {}
				if vim.tbl_isempty(frames) then
					push_line(builder, "  loading...", { group = "UDebugToolMuted" })
				else
					for index, frame in ipairs(frames) do
						local current = session.current_frame and frame.id == session.current_frame.id
						push_line(builder, string.format("  %02d %s", index, tostring(frame.name or "<frame>")), {
							group = current and "UDebugToolCurrent" or "UDebugToolValue",
							item = {
								kind = "frame",
								frame = frame,
								thread_id = thread_id,
								name = frame.name or "<frame>",
								value = frame_location(frame),
							},
						})
						push_line(builder, "     " .. frame_location(frame), {
							group = current and "UDebugToolMarker" or "UDebugToolMuted",
							item = {
								kind = "frame",
								frame = frame,
								thread_id = thread_id,
								name = frame.name or "<frame>",
								value = frame_location(frame),
							},
						})
					end
				end
			end
			push_line(builder, "")
		end
	end
	set_lines(state.stacks, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_watches_panel(session)
	local buf = ensure_buf(state.watches_panel, "UDebugToolWatches", "udebugtool-debug-watches")
	local builder = new_builder()
	push_line(builder, "Watches", { group = "UDebugToolTitle" })
	push_line(builder, "[a] add   [x] remove", { group = "UDebugToolMuted" })
	push_line(builder, "")
	if vim.tbl_isempty(state.watches) then
		push_line(builder, "No watches", { group = "UDebugToolMuted" })
	else
		for _, expression in ipairs(state.watches) do
			local watch = state.watch_values[expression] or {}
			local summary
			if not session or state.running or not session.current_frame then
				summary = "<pending>"
			else
				summary = watch.error or watch.result or "<pending>"
			end
			local ref = tonumber(watch.variablesReference or 0) or 0
			local has_children = ref > 0
				or (tonumber(watch.namedVariables or 0) or 0) > 0
				or (tonumber(watch.indexedVariables or 0) or 0) > 0
			local key = "watch:" .. expression
			local expanded = state.expanded[key]
			if expanded == nil then
				expanded = true
			end
			local prefix = has_children and (expanded and "[-]" or "[+]") or "   "
			local item = {
				kind = "watch",
				expression = expression,
				key = key,
				ref = ref,
				name = expression,
				value = watch.result or watch.error or "",
			}
			push_line(builder, string.format("%s %s = %s", prefix, expression, truncate(summary, 44)), {
				group = state.selected_watch == expression and "UDebugToolCurrent" or "UDebugToolValue",
				item = item,
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
					push_line(builder, "  " .. truncate(cache.error, 60), { group = "UDebugToolDanger" })
				elseif vim.tbl_isempty(cache.variables or {}) then
					push_line(builder, "  (empty)", { group = "UDebugToolMuted" })
				else
					for _, variable in ipairs(cache.variables or {}) do
						render_variable_tree(builder, session, variable, 1, "variable", {})
					end
				end
			end
			push_line(builder, "")
		end
	end
	set_lines(state.watches_panel, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_controls_panel(session)
	local buf = ensure_buf(state.controls, "UDebugToolControls", "udebugtool-debug-controls")
	local builder = new_builder()
	push_line(builder, "Controls", { group = "UDebugToolTitle" })
	local summary
	if not session then
		summary = "Idle"
	elseif state.running then
		summary = "Running"
	elseif session.current_frame then
		summary = "Stopped"
	else
		summary = "Attached"
	end
	push_line(builder, summary, {
		group = not session and "UDebugToolMuted" or (state.running and "UDebugToolAccent" or "UDebugToolWarn"),
	})
	if state.stop_event and stop_reason_text() then
		push_line(builder, stop_reason_text(), { group = "UDebugToolDanger" })
	end
	push_line(builder, "")
	push_line(builder, "  ▶ Continue   ■ Stop   ⤼ Over   ⤶ Into   ⤴ Out   ● Break   ◌ Mute", {
		group = "UDebugToolValue",
		spans = {
			{ group = "UDebugToolToolbarHot", start_col = 2, end_col = 3 },
			{ group = "UDebugToolToolbarHot", start_col = 15, end_col = 16 },
			{ group = "UDebugToolToolbarHot", start_col = 24, end_col = 25 },
			{ group = "UDebugToolToolbarHot", start_col = 34, end_col = 35 },
			{ group = "UDebugToolToolbarHot", start_col = 44, end_col = 45 },
			{ group = "UDebugToolDanger", start_col = 52, end_col = 53 },
			{ group = state.breakpoints_muted and "UDebugToolDanger" or "UDebugToolMuted", start_col = 62, end_col = 63 },
		},
	})
	push_line(builder, "   dc          ds         do        di        du       db       dn/dm", {
		group = "UDebugToolMuted",
	})
	push_line(builder, "")
	push_line(builder, "Enter on stacks / breakpoints to jump", {
		group = "UDebugToolMuted",
	})
	set_lines(state.controls, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_console_panel()
	local buf = ensure_buf(state.console, "UDebugToolConsole", "udebugtool-debug-console")
	local builder = new_builder()
	push_line(builder, "Console", { group = "UDebugToolTitle" })
	if vim.tbl_isempty(state.console_lines) then
		push_line(builder, "")
		push_line(builder, "No output yet", { group = "UDebugToolMuted" })
	else
		for index, line in ipairs(state.console_lines) do
			push_line(builder, tostring(line), {
				group = state.console_groups[index] or "UDebugToolValue",
			})
		end
	end
	set_lines(state.console, builder.lines, builder.items, builder.highlights)
	vim.bo[buf].modifiable = false
end

local function render_all(session)
	ensure_sidebar_layout()
	ensure_tray_layout()
	render_scopes_panel(session)
	render_breakpoints_panel()
	render_stacks_panel(session)
	render_watches_panel(session)
	render_controls_panel(session)
	render_console_panel()
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
	if win == state.scopes.win then
		return "scopes"
	end
	if win == state.breakpoints.win then
		return "breakpoints"
	end
	if win == state.stacks.win then
		return "stacks"
	end
	if win == state.watches_panel.win then
		return "watches_panel"
	end
	if win == state.controls.win then
		return "controls"
	end
	if win == state.console.win then
		return "console"
	end
	return nil
end

function M.open()
	setup_highlights()
	sync_watches()
	close_win(state.left.win)
	close_win(state.right.win)
	close_win(state.bottom.win)
	close_win(state.toolbar.win)
	state.left.win = nil
	state.right.win = nil
	state.bottom.win = nil
	state.toolbar.win = nil
	ensure_sidebar_layout()
	ensure_tray_layout()
end

function M.hover_under_cursor()
	local session = current_session()
	if not session or not session.current_frame then
		return vim.notify("UDebugTool: no active stopped frame", vim.log.levels.INFO)
	end

	local expr = vim.fn.expand("<cword>")
	if not expr or expr == "" then
		return
	end

	local win_pos = vim.api.nvim_win_get_position(0)
	local position = {
		line = win_pos[1] + vim.fn.winline(),
		col = win_pos[2] + vim.fn.wincol() - 1,
	}

	session:evaluate({
		expression = expr,
		context = "hover",
		frameId = session.current_frame.id,
	}, function(err, response)
		vim.schedule(function()
			if err then
				return open_hover_lines({ expr, "", tostring(err) }, position, "Debug Hover")
			end

			local lines = {
				string.format("%s = %s", expr, tostring((response and response.result) or "")),
			}
			local ref = tonumber(response and response.variablesReference or 0) or 0
			if ref <= 0 then
				return open_hover_lines(lines, position, "Debug Hover")
			end

			fetch_children(session, ref, function(variables, child_err)
				vim.schedule(function()
					if child_err then
						lines[#lines + 1] = ""
						lines[#lines + 1] = tostring(child_err)
						return open_hover_lines(lines, position, "Debug Hover")
					end
					for _, variable in ipairs(variables or {}) do
						lines[#lines + 1] = string.format("  %s = %s", tostring(variable.name or "?"), tostring(variable.value or ""))
					end
					open_hover_lines(lines, position, "Debug Hover")
				end)
			end)
		end)
	end)
end

function M.close()
	close_hover()
	close_win(state.left.win)
	close_win(state.right.win)
	close_win(state.bottom.win)
	close_win(state.scopes.win)
	close_win(state.breakpoints.win)
	close_win(state.stacks.win)
	close_win(state.watches_panel.win)
	close_win(state.controls.win)
	close_win(state.console.win)
	close_win(state.toolbar.win)
	state.scopes.win = nil
	state.breakpoints.win = nil
	state.stacks.win = nil
	state.watches_panel.win = nil
	state.controls.win = nil
	state.console.win = nil
	state.toolbar.win = nil
	state.scopes.buf = nil
	state.breakpoints.buf = nil
	state.stacks.buf = nil
	state.watches_panel.buf = nil
	state.controls.buf = nil
	state.console.buf = nil
	state.toolbar.buf = nil
	state.scopes.items = {}
	state.breakpoints.items = {}
	state.stacks.items = {}
	state.watches_panel.items = {}
	state.controls.items = {}
	state.console.items = {}
	state.toolbar.items = {}
end

function M.is_open()
	return valid_win(state.scopes.win) or valid_win(state.watches_panel.win) or valid_win(state.controls.win) or valid_win(state.console.win)
end

function M.mark_running(session)
	state.session = session
	state.running = true
	state.stop_event = nil
	state.selected_item = nil
	sync_watches()
	M.open()
	render_all(session)
end

function M.set_breakpoints_muted(muted)
	state.breakpoints_muted = muted == true
end

function M.refresh(session)
	state.session = session
	state.running = false
	sync_watches()
	M.open()

	if not session then
		state.selected_item = nil
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
		state.selected_item = {
			kind = "frame",
			name = item.frame.name or "<frame>",
			value = frame_location(item.frame),
			frame = item.frame,
		}
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
		state.selected_item = {
			kind = "watch",
			expression = item.expression,
			name = item.name or item.expression,
			value = item.value or "",
			ref = item.ref,
			key = item.key,
		}
		return toggle_item(item)
	end

	if item.kind == "scope" then
		state.selected_item = {
			kind = "scope",
			key = item.key,
			scope = item.scope,
			name = item.name or item.scope_name or "Scope",
			ref = item.ref,
			value = item.value or "",
		}
		return toggle_item(item)
	end

	if item.kind == "variable" then
		state.selected_item = {
			kind = "variable",
			key = item.key,
			name = item.name or "?",
			ref = item.ref,
			value = item.value or "",
		}
		if item.ref and item.ref > 0 then
			return toggle_item(item)
		end
		render_all(state.session)
		return
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

function M.clear_console()
	state.console_lines = {}
	state.console_groups = {}
	if M.is_open() then
		render_console_panel()
	end
end

function M.append_console(data, opts)
	opts = opts or {}
	local lines = type(data) == "table" and data or { tostring(data or "") }
	for _, line in ipairs(lines) do
		local text = tostring(line or "")
		if text ~= "" then
			state.console_lines[#state.console_lines + 1] = text
			state.console_groups[#state.console_groups + 1] = console_highlight_group(text, opts.group)
		end
	end

	local max_lines = 400
	while #state.console_lines > max_lines do
		table.remove(state.console_lines, 1)
		table.remove(state.console_groups, 1)
	end

	if M.is_open() then
		if vim.in_fast_event() then
			vim.schedule(render_console_panel)
		else
			render_console_panel()
		end
	end
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
	state.selected_item = nil
	state.console_lines = {}
	state.console_groups = {}
end

return M
