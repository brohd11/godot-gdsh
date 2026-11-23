extends SceneTree
## Installs the `gdsh` command and registers the running Godot binary in ~/.gdsh/executables under its
## version. The wrapper picks the registered binary matching each project's engine version.
##     <godot> --headless --path . --script res://addons/_lib/gdsh/src/cli/install.gd [-- <flags>]
## Run it once per Godot binary; the wrapper is the same for every version.

## Every wrapper carries this, so reinstall/uninstall only ever touch files this script wrote.
const MARKER = "gdsh-cli wrapper"
const REGISTRY_FILE = "executables"

const _USAGE = \
"Usage: install.gd [-- --dir <abs path> --force --uninstall]
  --dir        install the wrapper here instead of ~/.local/bin
  --force      overwrite a file of the same name that this script didn't write
  --uninstall  remove the wrapper (the ~/.gdsh/executables registry is kept)"

const _BASH = r"""#!/usr/bin/env bash
# gdsh-cli wrapper: runs gdsh headless in the enclosing Godot project. Written by gdsh's
# src/cli/install.gd, which also registers Godot binaries in ~/.gdsh/executables. $GODOT overrides.
set -o pipefail
usage="Usage: gdsh '<line>' | gdsh -f <file.gdsh>"
[[ $# -gt 0 ]] || { echo "$usage" >&2; exit 1; }

proj=$PWD
while [[ $proj != / && ! -f $proj/project.godot ]]; do proj=$(dirname "$proj"); done
[[ -f $proj/project.godot ]] || { echo "gdsh: no project.godot above $PWD" >&2; exit 1; }

godot=$GODOT
if [[ -z $godot ]]; then
	registry=${GDSH_HOME:-$HOME/.gdsh}/executables
	ver=$(sed -n 's/^config\/features=PackedStringArray("\([0-9.]*\)".*/\1/p' "$proj/project.godot")
	want=""; grep -q '^config/features=.*"C#"' "$proj/project.godot" && want=-mono
	exact=""; other=""
	if [[ -n $ver && -f $registry ]]; then
		while IFS= read -r line || [[ -n $line ]]; do
			key=${line%%: *}; path=${line#*: }
			[[ $key == "godot-$ver."* && $path != "$line" ]] || continue
			mono=""; [[ $key == *-mono ]] && mono=-mono
			if [[ $mono == "$want" ]]; then exact=$path; else other=$path; fi
		done < "$registry"
	fi
	godot=${exact:-$other}
	if [[ -z $godot ]]; then
		echo "gdsh: no Godot ${ver:-(unknown version)} registered in $registry" >&2
		echo "  register one: <godot> --headless --path <project> --script res://addons/_lib/gdsh/src/cli/install.gd" >&2
		exit 1
	fi
fi

runner=addons/_lib/gdsh/src/cli/run.gd
if [[ ! -f $proj/$runner ]]; then
	runner=$(cd "$proj" && find addons -path '*/gdsh/src/cli/run.gd' -print -quit 2>/dev/null)
	[[ -n $runner ]] || { echo "gdsh: gdsh isn't in $proj" >&2; exit 1; }
fi

if [[ $1 == -f ]]; then
	[[ -f $2 ]] || { echo "gdsh: no such file: $2" >&2; exit 1; }
	args=(-f "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")")
else
	args=(-c "$*")
fi

# Drop Godot's banner and the blank line after it; pipefail keeps Godot's exit code.
"$godot" --headless --path "$proj" --script "res://$runner" -- "${args[@]}" \
	| sed '1{/^Godot Engine v/{N;d;};}'
"""

# Named gdsh.cmd so `gdsh` resolves to it from both cmd and PowerShell, whatever the
# execution policy; the .ps1 has a different name so PowerShell never picks it directly.
const _CMD = r"""@echo off
rem gdsh-cli wrapper: forwards to gdsh-cli.ps1 next to it. Written by gdsh's src/cli/install.gd.
where pwsh >nul 2>nul
if %errorlevel% equ 0 (
	pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdsh-cli.ps1" %*
) else (
	powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdsh-cli.ps1" %*
)
exit /b %errorlevel%
"""

const _PS1 = r"""# gdsh-cli wrapper: runs gdsh headless in the enclosing Godot project. Written by gdsh's
# src/cli/install.gd, which also registers Godot binaries in ~/.gdsh/executables. $env:GODOT overrides.
$usage = "Usage: gdsh '<line>' | gdsh -f <file.gdsh>"
if ($args.Count -eq 0) { [Console]::Error.WriteLine($usage); exit 1 }

$proj = (Get-Location).ProviderPath
while ($proj -and -not (Test-Path -LiteralPath (Join-Path $proj 'project.godot'))) {
	$proj = Split-Path -Parent $proj
}
if (-not $proj) { [Console]::Error.WriteLine("gdsh: no project.godot above $(Get-Location)"); exit 1 }

$godot = $env:GODOT
if (-not $godot) {
	$gdsh_home = if ($env:GDSH_HOME) { $env:GDSH_HOME } else { Join-Path $HOME '.gdsh' }
	$registry = Join-Path $gdsh_home 'executables'
	$features = Select-String -LiteralPath (Join-Path $proj 'project.godot') -Pattern '^config/features=' |
		Select-Object -First 1
	$ver = ''; $want = ''
	if ($features) {
		if ($features.Line -match 'PackedStringArray\("([0-9.]+)"') { $ver = $Matches[1] }
		if ($features.Line -match '"C#"') { $want = '-mono' }
	}
	$exact = ''; $other = ''
	if ($ver -and (Test-Path -LiteralPath $registry)) {
		foreach ($line in Get-Content -LiteralPath $registry) {
			$key, $path = $line -split ': ', 2
			if (-not $path -or -not $key.StartsWith("godot-$ver.")) { continue }
			$mono = if ($key.EndsWith('-mono')) { '-mono' } else { '' }
			if ($mono -eq $want) { $exact = $path } else { $other = $path }
		}
	}
	$godot = if ($exact) { $exact } else { $other }
	if (-not $godot) {
		$shown = if ($ver) { $ver } else { '(unknown version)' }
		[Console]::Error.WriteLine("gdsh: no Godot $shown registered in $registry")
		[Console]::Error.WriteLine("  register one: <godot> --headless --path <project> --script res://addons/_lib/gdsh/src/cli/install.gd")
		exit 1
	}
}

$runner = 'addons/_lib/gdsh/src/cli/run.gd'
if (-not (Test-Path -LiteralPath (Join-Path $proj $runner))) {
	$found = Get-ChildItem -LiteralPath (Join-Path $proj 'addons') -Recurse -Filter run.gd -File -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName.Replace('\', '/') -like '*/gdsh/src/cli/run.gd' } | Select-Object -First 1
	if (-not $found) { [Console]::Error.WriteLine("gdsh: gdsh isn't in $proj"); exit 1 }
	$runner = $found.FullName.Substring($proj.Length).TrimStart('\', '/').Replace('\', '/')
}

if ($args[0] -eq '-f') {
	if ($args.Count -lt 2 -or -not (Test-Path -LiteralPath $args[1] -PathType Leaf)) {
		[Console]::Error.WriteLine("gdsh: no such file: $($args[1])"); exit 1
	}
	$run_args = @('-f', (Resolve-Path -LiteralPath $args[1]).ProviderPath)
} else {
	$run_args = @('-c', ($args -join ' '))
}

# Drop Godot's banner and the blank line after it.
$state = 0
& $godot --headless --path $proj --script "res://$runner" -- @run_args | ForEach-Object {
	if ($state -eq 0) { $state = 1; if ($_ -like 'Godot Engine v*') { return } else { $state = 2 } }
	if ($state -eq 1) { $state = 2; if ($_ -eq '') { return } }
	$_
}
exit $LASTEXITCODE
"""


func _initialize() -> void:
	var opts = _parse_args(OS.get_cmdline_user_args())
	if opts.is_empty():
		printerr(_USAGE)
		quit(1)
		return

	var windows = OS.get_name() == "Windows"
	var bin_dir:String = opts.dir if opts.dir != "" else _home().path_join(".local/bin")
	var wrappers = {"gdsh.cmd": _CMD, "gdsh-cli.ps1": _PS1} if windows else {"gdsh": _BASH}
	if opts.uninstall:
		quit(0 if _uninstall(bin_dir, wrappers.keys()) else 1)
		return
	# Refuse before registering, so a refusal changes nothing.
	if not opts.force and not _can_replace(bin_dir, wrappers.keys()):
		quit(1)
		return
	if not _register() or not _write_wrappers(bin_dir, wrappers, windows):
		quit(1)
		return
	_path_hint(bin_dir, windows)
	quit(0)


## {dir, force, uninstall}, or {} on a bad argument.
func _parse_args(args:PackedStringArray) -> Dictionary:
	var opts = {"dir": "", "force": false, "uninstall": false}
	var i = 0
	while i < args.size():
		match args[i]:
			"--force": opts.force = true
			"--uninstall": opts.uninstall = true
			"--dir":
				i += 1
				if i >= args.size() or not args[i].is_absolute_path():
					printerr("--dir needs an absolute path")
					return {}
				opts.dir = args[i].simplify_path()
			_:
				printerr("Unknown argument: " + args[i])
				return {}
		i += 1
	return opts


func _home() -> String:
	return OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")


func _gdsh_home() -> String:
	var dir = OS.get_environment("GDSH_HOME")
	return dir if dir != "" else _home().path_join(".gdsh")


## Upserts `godot-<ver>[-mono]: <exe>` in the registry; one line per key.
func _register() -> bool:
	var info = Engine.get_version_info()
	var key = "godot-%d.%d.%d" % [info.major, info.minor, info.patch]
	if ClassDB.class_exists("CSharpScript"):
		key += "-mono"
	var exe = OS.get_executable_path()
	# The GUI exe doesn't hand a terminal its stdout; its _console sibling does.
	var console_exe = exe.get_basename() + "_console.exe"
	if OS.get_name() == "Windows" and not exe.ends_with("_console.exe") and FileAccess.file_exists(console_exe):
		exe = console_exe

	var home = _gdsh_home()
	var registry = home.path_join(REGISTRY_FILE)
	var lines:PackedStringArray = []
	if FileAccess.file_exists(registry):
		for line in FileAccess.get_file_as_string(registry).split("\n"):
			line = line.strip_edges()
			if line != "" and not line.begins_with(key + ": "):
				lines.append(line)
	lines.append(key + ": " + exe)
	if not _write_file(home, REGISTRY_FILE, "\n".join(lines) + "\n"):
		return false
	print("Registered %s: %s\n  in %s" % [key, exe, registry])
	return true


func _can_replace(dir:String, names:Array) -> bool:
	for file_name in names:
		var path = dir.path_join(file_name)
		if FileAccess.file_exists(path) and not _is_ours(path):
			printerr("%s exists and wasn't written by this script; rerun with --force to replace it." % path)
			return false
	return true


func _write_wrappers(dir:String, wrappers:Dictionary, windows:bool) -> bool:
	for file_name in wrappers:
		var text:String = wrappers[file_name]
		if windows:
			text = text.replace("\n", "\r\n")
		if not _write_file(dir, file_name, text):
			return false
		var path = dir.path_join(file_name)
		if not windows:
			FileAccess.set_unix_permissions(path, 0b111_101_101) # 0755
		print("Installed " + path)
	return true


func _uninstall(dir:String, names:Array) -> bool:
	var ok = true
	for file_name in names:
		var path = dir.path_join(file_name)
		if not FileAccess.file_exists(path):
			continue
		if not _is_ours(path):
			printerr("Left %s: it wasn't written by this script." % path)
			ok = false
			continue
		var err = DirAccess.remove_absolute(path)
		if err != OK:
			printerr("Can't remove %s: %s" % [path, error_string(err)])
			ok = false
		else:
			print("Removed " + path)
	return ok


func _is_ours(path:String) -> bool:
	return FileAccess.get_file_as_string(path).contains(MARKER)


func _write_file(dir:String, file_name:String, text:String) -> bool:
	var err = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		printerr("Can't create %s: %s" % [dir, error_string(err)])
		return false
	var path = dir.path_join(file_name)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	return true


func _path_hint(dir:String, windows:bool) -> void:
	var sep = ";" if windows else ":"
	for entry in OS.get_environment("PATH").split(sep):
		if entry.replace("\\", "/").trim_suffix("/") == dir.replace("\\", "/").trim_suffix("/"):
			return
	print("\n%s isn't on PATH. Add it:" % dir)
	if windows:
		print("  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';%s', 'User')" % dir)
	else:
		print("  export PATH=\"%s:$PATH\"   # in your shell profile" % dir)
