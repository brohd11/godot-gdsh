# Command packages

A command package is a folder of gdsh commands that any host can load the same way: the
mcp-sh-godot bridge, Editor Console, a runtime console or a CLI. The `gdsh_lib` libraries
([utils](https://github.com/brohd11/godot-gdsh-lib-utils),
[tree](https://github.com/brohd11/godot-gdsh-lib-tree),
[editor](https://github.com/brohd11/godot-gdsh-lib-editor), level, terrain3d) are packages.

## Install

There are two places to install a package. Use the one that matches how you use it.

### Editor tooling: shared folders

The editor hosts (mcp-sh-godot, Editor Console) read packages from shared dot folders, with no config:

```
~/.gdsh/                    user folder ($GDSH_HOME overrides)
res://.gdsh/                this project; wins over the user folder on a name clash
  commands/                 loose commands: name.gd or name/name.gd
  packages/<name>/          command packages, each with a cmd/ dir
```

```sh
mcp_sh_godot gdsh search             # reviewed packages (godot-gdsh-lib-manifest)
mcp_sh_godot gdsh install terrain3d  # with level beside it, at the reviewed commits
```

- The installer writes to the root `mcp_sh_godot gdsh target` picks (`~/.mcp-sh/godot` or
  `~/.gdsh`; `--project`, `--dir ROOT`). It installs only listed packages, at the commit the
  index pins.
- Manual installs work too. Clone or copy a package
  (`git clone https://github.com/brohd11/godot-gdsh-lib-level ~/.gdsh/packages/level`), add it
  as a submodule, or keep `~/.gdsh` as its own repo.
- Name each folder after the package's `path` basename in `package.cfg` (`level`, `terrain3d`).
- Put the gdsh packages it depends on beside it, because packages find each other as sibling
  folders. For example, terrain3d needs `packages/level`.
- gdsh itself is not needed. Commands here are rebuilt against the host's copy of gdsh.
  The editor never scans dot folders, so it shows no compile errors either.
- Only gdsh and other gdsh packages are resolved here. If a package `require`s anything else
  (utils' `check` uses util_r), that code must be in the project, so install the package
  in the project instead, or install its dependency there.
- A package cloned in later shows up on the next request, without a restart.

mcp-sh-godot also reads `~/.mcp-sh/godot/` and `res://.mcp-sh/godot/` the same way
(`commands/` + `packages/<name>/cmd`), for setups without Editor Console. Only the MCP
bridge reads those folders. The interactive console reads only `.gdsh`.

### In the project: `res://addons/_lib/gdsh_lib/`

Use this for a game export or GDPackage, which only pick up non-hidden project files. Install gdsh
alongside it:

```sh
gdaddon install brohd11/godot-gdsh
gdaddon install brohd11/godot-gdsh-lib-level
```

Then register the package with the host: `config scope reg --package level` in Editor
Console, `host.add_package(path)`, or its `cmd/` dir in mcp-sh-godot's `bridge.json` `commandDirs`.

## Layout

```
<package>/
  package.cfg               name, version, path, require
  cmd/                      what hosts load
    manifest.gd             preloads every command for exporters; never loaded as a command
    level/level.gd          a namespace; its subcommands in level/<sub>/<sub>.gd
  src/                      plain GDScript, no gdsh dependency
```

- **No loose commands in `cmd/`.** A loose command owns every sibling `name/name.gd` dir as
  a subcommand, so two of them would share the same children. Give each namespace its own
  `name/name.gd` dir. A package of top-level commands (utils) can add a discovery namespace in
  its own dir that overrides `_get_commands()` to list `../`.
- **`src/` doesn't depend on gdsh.** Commands load it relative to their own file, so the package
  works wherever it is installed:
  ```gdscript
  func _src(file: String):
      var pkg := ProjectSettings.localize_path(get_script().resource_path).get_base_dir().get_base_dir().get_base_dir().get_base_dir()
      return ResourceLoader.load(pkg.path_join("src").path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
  ```
- **Dependencies are siblings.** A package that uses another reaches it at `../<name>/` from its
  own root, never through an absolute `res://` path.
- **Commands extend** `"res://addons/_lib/gdsh/src/core/command_base.gd"`. Outside the project
  and in `res://.gdsh/`, that line is swapped for the running gdsh's copy.

## Loading

```gdscript
context.load_package("res://addons/my_package")   # loads res://addons/my_package/cmd
host.add_package("res://addons/my_package")
GDSh.Load.load_package("res://addons/my_package")  # the scope dictionary
```

`GDSh.Load.default_dirs()` lists the shared-folder dirs in load order: the user folder, then
`res://.gdsh`, each giving its `commands/` and then every `packages/<name>/cmd`.
`host.add_default_dirs()` (or `Host.new({"default_dirs": true})`) adds them and lists them again
on each request. `GDSh.Load.root_dirs(root)` and `host.add_command_root(root)` do the same for
any one folder laid out that way. The root doesn't have to exist yet. They are user paths (`GDSh.Load.is_user_path`), so their commands are compiled
against the running gdsh, and edits apply without a restart.
