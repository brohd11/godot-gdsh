# Writing TUI commands

A TUI command temporarily takes over a console's display and input. Extend
`GDSh.TUICommand`, keep application state on the command, and implement two methods:

- `update(message: TUIMsg)` changes state in response to input or application events.
- `view() -> String` returns the current screen as BBCode without changing state.

The base handles session acquisition, input capture, redraws, and cleanup. The prompt
and transcript return when the command calls `quit()`. Drawing does not enter stdout;
use `context.append_output()` only for results that should remain after the TUI exits.

## A selectable list

Save this example as `res://commands/choose_item.gd`. It displays 100 items, highlights
the selection, and draws only the rows that fit. This is an example to register in your
own project; GDSh does not install a demo command.

```gdscript
extends GDSh.TUICommand
## A small program-owned viewport: the label itself never scrolls.
var _selected:=0
var _first:=0
var _scroll_remainder:=0.0
var _items:Array[String] = []


static func get_command_name() -> String:
	return "choose_item"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": "Open a selectable list in an interactive console.\nArrows/Page Up/Page Down/Home/End navigate; Enter selects; Escape/Ctrl+C cancel."})


func update(message:TUIMsg) -> void:
	match message.type:
		TUIMsg.Type.INIT:
			_items.clear()
			for index in 100:
				_items.append("Item %03d" % (index + 1))
			_selected = 0
			_first = 0
			_scroll_remainder = 0
			hint = "↑↓ Move · PgUp/Dn · Home/End · Enter Select · Esc/^C Cancel"
		TUIMsg.Type.RESIZE:
			_reveal_selected()
		TUIMsg.Type.MOUSE:
			var event = message.payload
			var delta:=0.0
			if event is InputEventPanGesture:
				delta = event.delta.y * 3
			elif event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: delta = event.factor * 3
				elif event.button_index == MOUSE_BUTTON_WHEEL_UP: delta = -event.factor * 3
			_scroll_remainder += delta
			var steps = int(_scroll_remainder)
			_scroll_remainder -= steps
			_first = clampi(_first + steps, 0, maxi(0, _items.size() - _page_size()))
		TUIMsg.Type.KEY:
			var event:InputEventKey = message.payload
			if not event.pressed:
				return
			match event.keycode:
				KEY_ESCAPE: quit(ExitCode.FAIL)
				KEY_ENTER, KEY_KP_ENTER:
					if not event.echo:
						context.append_output(_items[_selected])
						quit()
				KEY_UP: _selected -= 1
				KEY_DOWN: _selected += 1
				KEY_PAGEUP: _selected -= _page_size()
				KEY_PAGEDOWN: _selected += _page_size()
				KEY_HOME: _selected = 0
				KEY_END: _selected = _items.size() - 1
				_: return
			_selected = clampi(_selected, 0, _items.size() - 1)
			_reveal_selected()


func _page_size() -> int:
	return maxi(1, viewport_size.y)


func _reveal_selected() -> void:
	_first = clampi(_first, maxi(0, _selected - _page_size() + 1), _selected)
	_first = mini(_first, maxi(0, _items.size() - _page_size()))


func view() -> String:
	var lines:PackedStringArray = []
	for index in range(_first, mini(_items.size(), _first + viewport_size.y)):
		var label = _items[index].replace("[", "[lb]")
		lines.append("[bgcolor=#38577a][color=#ffffff]> %s[/color][/bgcolor]" % label
				if index == _selected else "  " + label)
	return "\n".join(lines)
```

`INIT` resets the list for each run. Arrow keys and Page Up/Down move the selection;
Home/End jump to either end. Wheel and trackpad input move the visible slice without
changing selection. Enter emits the selected item and exits successfully. Escape and
the base's Ctrl+C handling cancel with status 1.

`_first` is the first visible item, while `_selected` is the selected item. Keeping
them separate allows scrolling without changing the selection. `_reveal_selected()`
brings selection back into view after keyboard navigation or resizing. The page step
stays at least one even when no rows fit; `view()` then returns an empty screen.

## Load and run it

Load the command into a visible console with an output area, inside a `Control` script:

```gdscript
func _ready() -> void:
    var console = GDSh.Console.new()
    console.create_output()
    console.load("res://commands")
    add_child(console)
    console.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Allow container layout to settle before launching the command.
    await get_tree().process_frame
    var result = await console.execute("choose_item")
    print(result.stdout) # Selected label, or empty on cancellation.
```

In Editor Console, register the script through its normal custom-command setup and
run `choose_item` in a docked or floating console. The shipped `editor plugin` command
is another TUI example: Enter toggles an addon without closing its list.

The command stays busy until the view closes. Editor Console holds its serialized
execution slot during that time, so other console and bridge requests wait.

## Base API

The base provides `context`, `viewport_size: Vector2i` (usable columns/rows, excluding
the hint), `hint: String`, `post_message(message)`, `quit(exit_code = ExitCode.OK)`,
and an optional synchronous `finish()` cleanup hook. Keep `update()` synchronous;
asynchronous work posts its results back on the main thread.

## Commands with ordinary and interactive modes

The default `_execute(ctx)` enters the TUI through `await run()`. For commands with
multiple modes, override `_execute(ctx)` and call `await run()` only when needed:

```gdscript
static func get_self_command_data() -> Dictionary:
    return _command_data({&"positional_count": "min:0,max:1"})

func _execute(ctx: Context):
    if "plain" in positional_args:
        ctx.append_output("Ordinary command output")
        return ExitCode.OK
    return await run()
```

`run() -> int` uses the context supplied by normal command dispatch, waits for closure,
and returns the exit code. A second overlapping run is rejected without closing the
active session. Each successful acquisition gets its own INIT and finish lifecycle.

## Messages and cleanup

`GDSh.TUIMsg.new(type, payload = null)` has a `Type` enum:

| Type | Payload |
| --- | --- |
| `INIT` | null; dimensions are already available |
| `RESIZE` | new `Vector2i(columns, rows)`, also reflected in `viewport_size` |
| `KEY` | `InputEventKey`, including releases and repeats |
| `MOUSE` | mouse button/motion or pan event, with display-local coordinates |
| `USER` | application-defined Variant |
| `SIGNAL` | application-defined Variant posted by a signal callback |

Initialization precedes queued input. Updates run in queue order, followed by one
render per batch. Messages posted inside an update wait until the next frame.
Unchanged BBCode is not reassigned, and idle programs do not redraw. Ctrl+C is reserved
for cancellation (status 1); Escape/Enter behavior belongs to the program.
`finish()` runs once after an acquired session closes, including host teardown; disconnect
application signal subscriptions there. Pending and late messages are discarded after closure.

## Drawing and scrolling

The display has no native scrollbar or scrolling. Draw only the visible slice of your
content using `viewport_size`, and maintain selection/viewport offsets in your program.
Wheel and pan gestures arrive as `MOUSE` messages; the base does not choose what they mean.
Use flat, unwrapped rows at the normal font size for accurate row budgeting. Column counts
use the current font's M advance and are intended for monospace layouts. Escape untrusted
text with `text.replace("[", "[lb]")` before embedding it in BBCode.

## Host integration

The base acquires a session through `ctx.host_data["tui_begin"]: Callable(ctx) -> session`.
Only the console's active submission can acquire it. Non-UI contexts, captured stdout
(redirection, non-final pipeline stages and command substitution), and concurrent views
are rejected with diagnostics.

Console subclasses can override `_get_tui_parent() -> Control` and
`_get_tui_controls_to_hide(parent: Control) -> Array[Control]`. Editor Console uses
these hooks to attach the session to EditorLog and hide its existing content controls,
including the filter, prompt and side buttons. Their prior visibility is restored on
exit or prompt teardown; the editor transcript continues to receive logs while hidden.

The lower-level session remains available to custom hosts: `display: RichTextLabel`,
`hint: Label`, `input_event(event)`, `closed(value)`, `close(value = null)`, `is_closed`,
`request_frame()`, `frame_requested`, and `get_viewport_size_in_cells()`. Its input signal
forwards mouse/pan events instead of scrolling. `TUICommand` uses the close value as
an exit code; a null close value means cancellation. Display frames must never be written
through `context.append_output()`; use that method only for actual command output.
