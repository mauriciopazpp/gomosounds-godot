@tool
extends RefCounted

## The Gomo Sounds brand inside Godot: the site's colors and the icon (the cut tangerine with its
## segments, the little leaf and the sound waves). The icon is drawn from the SVG on the fly, at the editor's
## scale: sharp on any screen and with no image file to import (the plugin works
## even before Godot finishes its first import).

const ORANGE := Color("#ff8a1f")
const ORANGE_LIGHT := Color("#ffb347")
## Text on top of the orange (the same as the site's button).
const ON_ORANGE := Color("#1a1206")

const _SVG_SIZE := 72.0
const _SVG := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
<defs>
<radialGradient id="peel" cx="40%" cy="38%" r="70%"><stop offset="0%" stop-color="#ffb347"/><stop offset="100%" stop-color="#e8680f"/></radialGradient>
<radialGradient id="flesh" cx="50%" cy="50%" r="55%"><stop offset="0%" stop-color="#ffd27a"/><stop offset="100%" stop-color="#ffa22e"/></radialGradient>
</defs>
<g transform="translate(3.96 11.88) scale(0.81)">
<circle cx="32" cy="32" r="31" fill="url(#peel)"/>
<circle cx="32" cy="32" r="26.5" fill="#fff4e2"/>
<g fill="url(#flesh)" stroke="#fff4e2" stroke-width="1.6" stroke-linejoin="round">{wedges}</g>
<circle cx="32" cy="32" r="2.4" fill="#fff4e2"/>
</g>
<g transform="translate(33.12 3.96) scale(0.672 0.684)">
<path d="M1 17C5 5 15 1 29 3 25 14 14 20 1 17z" fill="#5cbf3a"/>
<path d="M3 16C10 11 17 7 26 4.5" stroke="#3f8f24" stroke-width="1.6" stroke-linecap="round" fill="none"/>
</g>
<g stroke="#ffbe55" stroke-width="3.4" stroke-linecap="round" fill="none">
<path d="M60 30c2.8 3 2.8 13 0 16"/>
<path d="M66 25.5c4.4 5.2 4.4 19.8 0 25" opacity=".55"/>
</g>
</svg>"""

static var _cache := {}


## The icon at `px` pixels per side (already multiplied by the editor scale by the caller).
static func icon(px: int) -> Texture2D:
	if _cache.has(px):
		return _cache[px]
	var wedges := ""
	for i in 8:
		wedges += '<path d="M32 30.5 L32.9 8.2 A24 24 0 0 1 47.7 14.6 Z" transform="rotate(%d 32 32)"/>' % (i * 45)
	var img := Image.new()
	if img.load_svg_from_string(_SVG.replace("{wedges}", wedges), px / _SVG_SIZE) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[px] = tex
	return tex
