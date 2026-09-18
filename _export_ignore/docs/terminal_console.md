# Terminal console

`GDSh.TerminalConsole` displays scrollback, the prompt, and the current command in
one selectable RichTextLabel. Editing uses a separate command buffer; selecting
text never moves the editing caret or makes the transcript editable.

```gdscript
var console = GDSh.TerminalConsole.new() # Optionally pass a Context.
add_child(console)
console.load("res://commands")
console.focus_input()
console.set_input_text("echo hello")
```

The transcript is created automatically and exposed as `output`. The session APIs
from [Console](console.md) also apply: `execute()`, `context`, `context_factory`,
`execution_handler`, `last_result`, command signals, `is_busy`, `stream_output`,
`clear_output()`, `clear_history()`, `reset_context()`, prompt formatters, and font
overrides. Use `set_input_text()`, `get_input_text()`, and `focus_input()` for input;
there is no CodeEdit or `get_text_edit()`.

## Editing and copying

- Enter submits; Up/Down browse history; Tab opens or accepts completion.
- Left/Right move the caret; Home/End move to the buffer boundaries.
- Ctrl/Alt+Left/Right move by word; Ctrl/Alt+Backspace/Delete delete by word.
  On macOS, Cmd+Left/Right also move to the buffer boundaries.
- Backspace/Delete edit only the buffer. Wrapped commands remain one logical line.
- Ctrl/Cmd+V pastes. Newlines become `; `; tabs become spaces.
- Drag or double-click to select text anywhere in the label. Ctrl/Cmd+A selects
  the whole display, and Ctrl/Cmd+C copies the selection. The context menu also
  provides Copy and Select All.
- With no selection, Ctrl/Cmd+C clears an idle command. In a TUI, Ctrl+C retains
  the TUI's exit behavior. Ordinary running commands are not interrupted.

Editing clears the copy selection and brings the caret into view. Blinking does
not change the label text or selection, and the copied text contains no synthetic
cursor character. Mouse selection is copy-only, including within the current command.
Scrolling back pauses following output; returning to the bottom resumes it.

Commands are highlighted using GDSh's BBCode highlighter. The input buffer always
contains literal text: typing BBCode does not apply formatting. Value previews,
when `echo_values` is enabled, appear only in submitted commands.

Output is literal by default, like `GDSh.Console`. Set `output_bbcode = true` to
render command-produced BBCode; the editor adapter enables this. Avoid directly
editing `output` while the prompt is present: its trailing paragraph belongs to
the console. Use the execution output sink and `clear_output()`.

## TUI and editor use

Existing [TUI commands](tui.md) take over the terminal through the same host
protocol. Their view temporarily replaces the transcript; exit restores the
transcript, prompt, and input focus.

With Editor Console enabled, run `editor_console terminal` (or `terminal`) to open
a separate floating window. Code can call
`EditorConsoleSingleton.new_terminal_console()`. The original floating console
and docked prompt remain available. The new window uses GDSh commands and the
editor's serialized execution queue; `os <command>` is still available, but it
does not have the older console's persistent OS-mode toggle.

This prototype supports single-line, codepoint-based editing with visual wrapping.
Undo/redo, brace pairing, IME composition, grapheme-aware editing, and mouse caret
placement are not implemented. It is a GDSh console, not an ANSI/PTY emulator.
