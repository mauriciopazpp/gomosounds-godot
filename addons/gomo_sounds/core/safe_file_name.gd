@tool
extends RefCounted

## File/folder name that works on ANY system (Windows, macOS, Linux, console, git):
## lowercase, no accents, only [a-z0-9_], short, never a Windows reserved name. Lowercase on
## purpose: Windows and macOS don't tell "Attack.wav" from "attack.wav", and two sounds like that
## would collapse into one.

const MAX_LEN := 48
const RESERVED := ["con", "prn", "aux", "nul",
	"com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
	"lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]
const ACCENTS := {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "å": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i",
	"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "ñ": "n", "ý": "y", "ÿ": "y", "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o",
}


static func slug(text: String, fallback := "sound") -> String:
	var out := ""
	var last_sep := true
	for ch in text.to_lower():
		var c: String = ACCENTS.get(ch, ch)
		if _is_plain(c):
			out += c
			last_sep = false
		elif not last_sep:
			out += "_"
			last_sep = true
	out = out.trim_suffix("_").substr(0, MAX_LEN).trim_suffix("_")
	if out == "":
		# No Latin letter at all (剣士, воин): a slice of the name's hash, so two different names
		# don't land in the same folder. Truly empty: the default.
		var stripped := text.strip_edges()
		out = fallback + ("_" + stripped.md5_text().substr(0, 6) if stripped != "" else "")
	if out in RESERVED:
		out += "_"
	return out


static func _is_plain(c: String) -> bool:
	if c.length() != 1:
		return c.to_lower() == c and c.is_valid_identifier()
	var code := c.unicode_at(0)
	return (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
