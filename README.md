# GDSh

A runtime shell and command engine for Godot 4.6+.

## Install

Place the release contents in `res://addons/addon_lib/gdsh/`, or install with
[gdaddon](https://github.com/brohd11/gdaddon):

In your project:
```sh
gdaddon install brohd11/godot-gdsh
gdaddon install brohd11/godot-gdsh-lib-utils
gdaddon install brohd11/godot-gdsh-lib-tree
```

Optional command libraries install under `res://addons/addon_lib/gdsh_lib/`:

- [utils](https://github.com/brohd11/godot-gdsh-lib-utils): Unix-style text utilities.
- [tree](https://github.com/brohd11/godot-gdsh-lib-tree): Add, remove, and inspect nodes.

## Run a script

```gdscript
var context = GDSh.Context.new()
await GDSh.Execute.execute_command_multiline("""
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

Reuse the context to keep session state (variables, functions, etc.) between executions.
To run a file in its own subshell, use `gdsh` or put its `.gdsh` path in command position:

```gdscript
await GDSh.Execute.execute_command_multiline("gdsh res://scripts/boot.gdsh first second", context)
```

The file receives `$0`, `$1`, `$#`, and `$@`; it does not need a `#!gdsh` header.
Use `source` with a `#!gdsh` file to apply changes to the current session.

Scripts and live nodes are also command targets:

```sh
MyGlobalClass call greeting -- world
script res://scripts/player.gd list --methods
res://scripts/player.gd.Inner call answer
script list_global --name=Player*
cn /root/Main
pwn
Player call damage -- 5
node /root/Main get_path
```

Both `script` and `node` offer `call`, `args`, `list`, and `get_path`. Use
`--inherited` for base-script members, `--engine` for native members, and
`--private` for underscore-prefixed members. Script calls are static-only;
node calls use the live instance.

## Add a console

```gdscript
var console = GDSh.Console.new()
console.load("res://commands")
add_child(console)
console.create_output() # Optional output log above the prompt.
```

## Write a command

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

- [Execution and contexts](_export_ignore/docs/execution.md)
- [Runtime console](_export_ignore/docs/console.md)
- [Language](_export_ignore/docs/language.md)
- [Redirection](_export_ignore/docs/redirection.md)
- [Commands and completion](_export_ignore/docs/commands.md)
- [Distribution and validation](_export_ignore/docs/distribution.md)
