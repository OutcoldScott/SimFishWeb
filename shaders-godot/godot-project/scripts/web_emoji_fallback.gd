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
	var base: Font = ThemeDB.fallback_font
	if base == null:
		return
	var extra: Array[Font] = []
	for path in FONT_PATHS:
		if ResourceLoader.exists(path):
			var f := load(path)
			if f is Font:
				extra.append(f)
	if extra.is_empty():
		return
	# Append rather than replace so we don't drop any fallbacks the engine
	# already configured. fallbacks returns a copy, so reassign after editing.
	var chain: Array[Font] = base.fallbacks
	for f in extra:
		if not chain.has(f):
			chain.append(f)
	base.fallbacks = chain
