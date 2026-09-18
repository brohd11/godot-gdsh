extends RichTextEffect
## Observe actual shaped glyph positions; the caret itself is drawn outside the text.
signal positioned(rect:Rect2)
var bbcode = "gdsh_caret"
var character:int = -1
var font_size:int = 16


func _process_custom_fx(fx:CharFXTransform) -> bool:
	if fx.outline or character < fx.range.x or character > fx.range.y:
		return true
	var server = TextServerManager.get_primary_interface()
	var origin = fx.transform.origin
	if character == fx.range.y:
		origin.x += server.font_get_glyph_advance(fx.font, font_size, fx.glyph_index).x
	var ascent = server.font_get_ascent(fx.font, font_size)
	var descent = server.font_get_descent(fx.font, font_size)
	positioned.emit(Rect2(origin - Vector2(0, ascent), Vector2(2, ascent + descent)))
	return true
