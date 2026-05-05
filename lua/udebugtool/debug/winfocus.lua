local M = {}

local function focus_config()
	return (((require("udebugtool.config").values or {}).debug or {}).focus or {})
end

local function powershell_command()
	if vim.fn.executable("powershell.exe") == 1 then
		return "powershell.exe"
	end
	if vim.fn.executable("pwsh.exe") == 1 then
		return "pwsh.exe"
	end
	if vim.fn.executable("powershell") == 1 then
		return "powershell"
	end
	if vim.fn.executable("pwsh") == 1 then
		return "pwsh"
	end
	return nil
end

local function script()
	return table.concat({
		"$ErrorActionPreference = 'SilentlyContinue'",
		"$pidToCheck = [int]$args[0]",
		"$restore = [int]$args[1]",
		"Add-Type -Namespace UDebugTool -Name Win32 -MemberDefinition @'",
		"[System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern bool IsIconic(System.IntPtr hWnd);",
		"[System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);",
		"[System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);",
		"[System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);",
		"'@",
		"$handle = [IntPtr]::Zero",
		"$topmostMs = [int]$args[2]",
		"for ($i = 0; $i -lt 8 -and $pidToCheck -gt 0; $i++) {",
		"  $proc = Get-Process -Id $pidToCheck -ErrorAction SilentlyContinue",
		"  if ($proc -and $proc.MainWindowHandle -ne 0) { $handle = $proc.MainWindowHandle; break }",
		"  $cim = Get-CimInstance Win32_Process -Filter \"ProcessId=$pidToCheck\"",
		"  if (-not $cim) { break }",
		"  $pidToCheck = [int]$cim.ParentProcessId",
		"}",
		"if ($handle -eq [IntPtr]::Zero) { exit 0 }",
		"if ($restore -eq 1 -and [UDebugTool.Win32]::IsIconic($handle)) { [void][UDebugTool.Win32]::ShowWindow($handle, 9) }",
		"if ($topmostMs -gt 0) { [void][UDebugTool.Win32]::SetWindowPos($handle, [IntPtr](-1), 0, 0, 0, 0, 0x0043) }",
		"[void][UDebugTool.Win32]::SetForegroundWindow($handle)",
		"if ($topmostMs -gt 0) { Start-Sleep -Milliseconds $topmostMs; [void][UDebugTool.Win32]::SetWindowPos($handle, [IntPtr](-2), 0, 0, 0, 0, 0x0043) }",
	}, "\n")
end

function M.bring_to_front()
	local cfg = focus_config()
	if cfg.on_stopped == false or cfg.bring_to_front == false then
		return
	end
	if vim.fn.has("win32") ~= 1 then
		return
	end

	local shell = powershell_command()
	if not shell then
		return
	end

	pcall(vim.system, {
		shell,
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-Command",
		script(),
		tostring(vim.fn.getpid()),
		cfg.restore_minimized == false and "0" or "1",
		tostring(tonumber(cfg.topmost_ms) or 0),
	}, {
		text = true,
		detached = true,
	})
end

return M
