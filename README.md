# GDSh

GDSh is a runtime shell and command engine for Godot games and application
consoles. It requires Godot 4.6 or newer and has no editor plugin, autoload,
editor-only UI, or Editor Console dependency.

## Install

Download the release and place the contents in the addons folder.

You can also use [gdaddon](https://github.com/brohd11/gdaddon) to manage the addon.
It is a TUI package/repo manager that can install and update addons for you.

Linux, Mac:
```bash
curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh
```
Windows:
```powershell
irm https://raw.githubusercontent.com/brohd11/gdaddon/main/install.ps1 | iex
```

Then, you can add the addon and install, this would install gdsh plus the optional libraries:
```sh
cd ~/your/project/
gdaddon install brohd11/godot-gdsh
gdaddon install brohd11/godot-gdsh-lib-utils
gdaddon install brohd11/godot-gdsh-lib-tree
```

## Execute scripts

```gdscript
var context = GDSh.Context.new()
GDSh.Execute.execute_command_multiline("""
name = player
echo Hello $name
for item in sword shield {
    echo $item
}
""", context)

print(context.stdout)
print(context.stderr)
print(context.exit_code)
```

Reuse the context to keep variables, aliases, functions, commands, and the
working directory between executions. See [Execution](export_ignore/docs/execution.md).

## Add a runtime console

```gdscript
var console = GDSh.Console.new()
console.load("res://commands")
add_child(console)

# Create an output log above the prompt
console.create_output()
```

See [Console](export_ignore/docs/console.md) for signals, prompt customization,
history, completion, output, and styling.

## Commands

There are a handful of commands that come builtin, they are mostly for the inner working of the gdsh, enabling functions, loops, etc.
Currently, indivual libraries are being published for use in separate libraries. These can be used in addition to your own.

Current libs:
- [utils](https://github.com/brohd11/godot-gdsh-lib-utils) - assorted unix like utils to help parsing command output
- [tree](https://github.com/brohd11/godot-gdsh-lib-tree) - tree operations, add, remove, inspect nodes

See [Commands and completion](export_ignore/docs/commands.md) for command trees,
hidden scopes, help metadata, and custom completions.

### Command template

```gdscript
# res://commands/greet.gd
extends GDSh.CommandBase

static func get_command_name() -> String:
    return "greet"

static func get_self_command_data() -> Dictionary:
    return _command_data({&"help": "Greet the player"})

func _execute(ctx: GDSh.Context):
    ctx.append_output("Hello!")
    return ExitCode.OK
```

## Reference

- [Execution and contexts](export_ignore/docs/execution.md)
- [Runtime console](export_ignore/docs/console.md)
- [Language](export_ignore/docs/language.md)
- [Redirection](export_ignore/docs/redirection.md)
- [Commands and completion](export_ignore/docs/commands.md)
- [Distribution and validation](export_ignore/docs/distribution.md)
