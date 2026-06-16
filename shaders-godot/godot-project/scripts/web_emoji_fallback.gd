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

# Holds strong references to every font we load/patch for the app's lifetime.
# Without this, an unreferenced FontFile we patch is freed as soon as _ready
# returns, and PanelTheme's later preload() of the same path gets a fresh,
# UNpatched instance from a cold cache - so its glyphs tofu again. Keeping the
# refs alive makes the resource cache hand PanelTheme our patched instances.
var _retained: Array[Font] = []

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

# UI fonts the panels apply directly via add_theme_font_override (see
# PanelTheme.FONT_*). These bypass the theme's default_font, so glyphs they
# lack - e.g. the subscript two in "O₂", or symbols in serif section headers -
# tofu without their own fallback chain. Resources are cached by path, so
# patching the loaded instance covers every control that uses it. Keep in sync
# with the preloads in panel_theme.gd.
const UI_FONT_PATHS := [
	"res://assets/fonts/IBMPlexSans-Regular.woff2",
	"res://assets/fonts/IBMPlexSans-Medium.woff2",
	"res://assets/fonts/IBMPlexSerif-Regular.woff2",
	"res://assets/fonts/IBMPlexSerif-Medium.woff2",
	"res://assets/fonts/IBMPlexSerif-Italic.woff2",
	"res://assets/fonts/IBMPlexMono-Regular.woff2",
	"res://assets/fonts/IBMPlexMono-Medium.woff2",
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
	_retained.append_array(extra)
	# On web the WASM runtime has NO system fonts. A SystemFont with
	# allow_system_fallback left in a fallback chain sends the web TextServer
	# into unbounded recursion when it tries (and fails) to resolve a glyph
	# through the system ("Maximum call stack size exceeded" at startup). Strip
	# those entries here; the bundled fonts below cover the glyphs instead.
	var on_web: bool = OS.has_feature("web")
	# 1) Engine last-resort font, used by any Control with no theme font.
	_chain_fallbacks(ThemeDB.fallback_font, extra, on_web)
	# 2) The project theme's fonts. The custom theme's default_font chains a
	#    SystemFont ("Apple Color Emoji", "Noto Color Emoji", ...) for its emoji
	#    fallback, useless on web; the bundled fonts take over there. On desktop
	#    the SystemFont is kept and the system emoji still win (appended after).
	var theme: Theme = ThemeDB.get_project_theme()
	if theme != null:
		_chain_fallbacks(theme.default_font, extra, on_web)
		for type_name in theme.get_font_type_list():
			for font_name in theme.get_font_list(type_name):
				_chain_fallbacks(theme.get_font(font_name, type_name), extra, on_web)
	# 3) Fonts panels apply directly as per-control overrides (PanelTheme).
	for path in UI_FONT_PATHS:
		if ResourceLoader.exists(path):
			var uf := load(path)
			if uf is Font:
				_retained.append(uf)
				_chain_fallbacks(uf, extra, on_web)


# Append `extra` to a font's fallback chain (dedup, preserving existing entries).
# When drop_system is true, SystemFont entries are removed first (see _ready).
# fallbacks returns a copy, so we reassign after editing.
func _chain_fallbacks(base: Font, extra: Array[Font], drop_system: bool) -> void:
	if base == null:
		return
	var chain: Array[Font] = base.fallbacks
	var changed: bool = false
	if drop_system:
		var filtered: Array[Font] = chain.filter(func(f: Font) -> bool: return not (f is SystemFont))
		if filtered.size() != chain.size():
			chain = filtered
			changed = true
	for f in extra:
		if not chain.has(f):
			chain.append(f)
			changed = true
	if changed:
		base.fallbacks = chain
