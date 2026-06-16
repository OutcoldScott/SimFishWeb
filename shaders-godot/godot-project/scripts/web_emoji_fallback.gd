# Registers bundled emoji + symbol fonts as global glyph fallbacks.
#
# The web export uses emoji and symbol glyphs as UI icons (creature chips,
# mood faces, toolbar buttons). On desktop Godot borrows macOS/Windows
# system fonts to cover those; the web/WASM runtime has no system fonts, so
# missing glyphs render as .notdef tofu boxes with the codepoint inside.
#
# The container build's font-builder stage downloads + subsets Noto Color
# Emoji and Noto Sans Symbols2 to the handful of glyphs actually used, drops
# them in res://fonts/, and Godot packs them during --export-debug Web. This
# autoload then chains them onto ThemeDB.fallback_font so every Control that
# uses the default theme font picks them up.
#
# When the fonts are absent (local checkout, desktop export) this no-ops, so
# the project still opens and builds without them.

extends Node

# No single OFL font covers the whole glyph set, so the subset step (see
# container/subset-fonts.py) splits the monochrome symbols across three Noto
# sources. The chain tries each in order until a glyph is found.
const FONT_PATHS := [
	"res://fonts/web_fallback_symbols2.ttf",
	"res://fonts/web_fallback_math.ttf",
	"res://fonts/web_fallback_symbols1.ttf",
	"res://fonts/web_fallback_text.ttf",
	"res://fonts/web_fallback_emoji.ttf",
]


func _ready() -> void:
	var extra: Array[Font] = []
	for path in FONT_PATHS:
		if ResourceLoader.exists(path):
			var f := load(path)
			if f is Font:
				extra.append(f)
	# Absent on local/desktop builds: no fonts subset in, so this no-ops and
	# the project still opens (system fonts cover the glyphs there anyway).
	if extra.is_empty():
		return
	# 1) Engine last-resort font, used by any Control with no theme font.
	_chain_fallbacks(ThemeDB.fallback_font, extra)
	# 2) The project theme's fonts. The custom theme's default_font chains a
	#    SystemFont ("Apple Color Emoji", "Noto Color Emoji", ...) for its emoji
	#    fallback, but the WASM runtime has NO system fonts, so that link
	#    resolves to nothing and every themed Control would tofu. Append the
	#    bundled fonts after it: on web they do the work; on desktop the system
	#    emoji still win since they come first.
	var theme: Theme = ThemeDB.get_project_theme()
	if theme != null:
		_chain_fallbacks(theme.default_font, extra)
		for type_name in theme.get_font_type_list():
			for font_name in theme.get_font_list(type_name):
				_chain_fallbacks(theme.get_font(font_name, type_name), extra)


# Append `extra` to a font's fallback chain (dedup, preserving existing entries).
# fallbacks returns a copy, so we reassign after editing.
func _chain_fallbacks(base: Font, extra: Array[Font]) -> void:
	if base == null:
		return
	var chain: Array[Font] = base.fallbacks
	var changed: bool = false
	for f in extra:
		if not chain.has(f):
			chain.append(f)
			changed = true
	if changed:
		base.fallbacks = chain
