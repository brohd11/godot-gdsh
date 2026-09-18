extends ScrollContainer

const Options = preload("res://addons/addon_lib/gdsh/options.gd")
const SourceFont = preload("res://addons/addon_lib/gdsh/internal/source_font.tres")

signal choice_accepted(choice:String, data:Dictionary)

var _items = ItemList.new()
var _choices:Array = []
var _choices_hash:int
var _generation:int


func _init() -> void:
	visible = false
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_items.focus_mode = Control.FOCUS_NONE
	_items.auto_height = true
	_items.auto_width = true
	_items.max_columns = 1
	_items.add_theme_font_override("font", SourceFont)
	_items.item_activated.connect(_on_item_activated)
	add_child(_items)


func set_choices(choices:Dictionary, generation:int) -> bool:
	_generation = generation
	var new_hash = choices.hash()
	modulate.a = 0.0
	show() # Invisible but participating in layout while ItemList measures itself.
	if new_hash != _choices_hash:
		_choices_hash = new_hash
		custom_minimum_size = Vector2.ZERO
		size = Vector2.ZERO
		_items.custom_minimum_size = Vector2.ZERO
		_choices = choices.keys()
		_items.clear()
		for choice in _choices:
			var data:Dictionary = choices[choice]
			var separator = Options.Keys.get_seperator(str(choice))
			if separator != null:
				_items.add_item(separator)
				_items.set_item_disabled(_items.item_count - 1, true)
				_items.set_item_metadata(_items.item_count - 1, data)
				continue
			var icon = data.get(Options.Keys.ICON)
			if icon is Array and not icon.is_empty():
				icon = icon[0]
			_items.add_item(str(choice), icon if icon is Texture2D else null)
			_items.set_item_metadata(_items.item_count - 1, data)
		for index in _items.item_count:
			if not _items.is_item_disabled(index):
				_items.select(index)
				break
	await get_tree().process_frame
	if generation != _generation:
		return false
	var measured = _items.get_combined_minimum_size()
	# A ScrollContainer can clamp both the current rect and reported minimum to
	# its previous viewport. Measure each single-column row so growth and
	# shrinkage do not depend on a later container layout pass.
	var content_height = 0.0
	var font = _items.get_theme_font("font")
	var font_size = _items.get_theme_font_size("font_size")
	var minimum_row_height = maxf(24.0, font.get_height(font_size) \
			+ _items.get_theme_constant("v_separation"))
	for index in _items.item_count:
		var item_rect = _items.get_item_rect(index)
		measured.x = maxf(measured.x, item_rect.end.x)
		var item_height = maxf(item_rect.size.y, minimum_row_height)
		var icon = _items.get_item_icon(index)
		if icon != null:
			item_height = maxf(item_height, icon.get_height())
		content_height += item_height
	var panel = _items.get_theme_stylebox("panel")
	content_height += panel.get_margin(SIDE_TOP) + panel.get_margin(SIDE_BOTTOM)
	measured.y = maxf(measured.y, content_height)
	var max_height = get_window().size.y * 0.5
	_items.custom_minimum_size = measured
	custom_minimum_size = Vector2(measured.x, minf(measured.y, max_height))
	size = custom_minimum_size
	show()
	modulate.a = 1.0
	_scroll_to_selection_after_layout(generation)
	return true


func cancel_pending() -> void:
	_generation += 1
	hide()


func position_for_caret(edit:CodeEdit) -> void:
	var caret_pos = edit.get_pos_at_line_column(edit.get_caret_line(), edit.get_caret_column())
	var width = clampf(size.x, 180.0, maxf(180.0, edit.size.x))
	var height = maxf(size.y, 24.0)
	size = Vector2(width, height)
	position = Vector2(clampf(caret_pos.x, 0.0, maxf(0.0, edit.size.x - width)), -height)


func has_selection() -> bool:
	return not _items.get_selected_items().is_empty()


func accept_selected() -> void:
	var selected = _items.get_selected_items()
	if not selected.is_empty():
		_on_item_activated(selected[0])


func select_next() -> void:
	_select_offset(1)


func select_previous() -> void:
	_select_offset(-1)


func _select_offset(offset:int) -> void:
	if _items.item_count == 0:
		return
	var selected = _items.get_selected_items()
	var index = selected[0] if not selected.is_empty() else 0
	for unused in _items.item_count:
		index = posmod(index + offset, _items.item_count)
		if not _items.is_item_disabled(index):
			_items.select(index)
			_scroll_to_selection()
			return


func _scroll_to_selection_after_layout(generation:int) -> void:
	await get_tree().process_frame
	if generation == _generation:
		_scroll_to_selection()


func _scroll_to_selection() -> void:
	if not visible or not has_selection():
		return
	# The auto-height ItemList fills the content; the outer container scrolls it.
	# Its row bounds already include the list panel's margin and share the
	# container's unscrolled content origin, independent of pending layout.
	var row = _items.get_item_rect(_items.get_selected_items()[0])
	var bar = get_v_scroll_bar()
	var target = float(scroll_vertical)
	if row.position.y < target or row.size.y > bar.page:
		target = floorf(row.position.y)
	elif row.end.y > target + bar.page:
		target = ceilf(row.end.y - bar.page)
	scroll_vertical = int(clampf(target, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page)))


func _on_item_activated(index:int) -> void:
	choice_accepted.emit(str(_choices[index]), _items.get_item_metadata(index))


## Anchor is in this popup parent's coordinates. Keep the popup inside the view.
func position_for_rect(anchor:Rect2, bounds:Rect2) -> void:
	size.x = minf(maxf(size.x, 180.0), bounds.size.x)
	size.y = minf(size.y, bounds.size.y)
	var y = anchor.position.y - size.y
	if y < bounds.position.y:
		y = anchor.end.y
	position = Vector2(
		clampf(anchor.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x)),
		clampf(y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y)))
