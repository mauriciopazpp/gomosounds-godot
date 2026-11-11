@tool
extends Node

const T := preload("res://addons/gomo_sounds/core/i18n.gd")

const SfxSettings := preload("res://addons/gomo_sounds/core/sfx_settings.gd")

## Gomo Sounds client. Everything goes through the site's MCP (/mcp), with the same rules as the site and the AI
## (credits, limits, plan): `call_tool` calls a tool and returns its structured JSON. Outside the
## MCP there's only the code-based connect (before having the key) and downloading files via signed links.
## Each call creates its own HTTPRequest (several can run at once) and returns a Result via `await`.

class Result:
	var ok: bool = false
	var status: int = 0
	var data: Variant = null
	var bytes: PackedByteArray = PackedByteArray()
	var content_type: String = ""
	var error: String = ""
	## The tool's error code (not_found, credits, terms_required...), or "".
	var code: String = ""

const TIMEOUT_SEC := 120.0
## Generating waits for the sound to be ready on the server (up to 10 min, with progress notices).
const GENERATE_TIMEOUT_SEC := 700.0
const PROTOCOL_VERSION := "2025-06-18"

var _next_id := 0


## Calls an MCP tool. `data` = the tool's structured JSON. Tool error: ok=false, `error` with the
## ready-made sentence (in the account's language) and `code`; "not_found" becomes status 404 and a rejected key, 401.
func call_tool(tool: String, args: Dictionary = {}, timeout: float = TIMEOUT_SEC) -> Result:
	_next_id += 1
	var body := {"jsonrpc": "2.0", "id": _next_id, "method": "tools/call", "params": {"name": tool, "arguments": args}}
	var r := await _request(HTTPClient.METHOD_POST, "/mcp", body, false, timeout)
	if r.status == 401:
		return r
	var rpc: Variant = r.data
	if not rpc is Dictionary:
		r.ok = false
		if r.error.is_empty():
			r.error = T.t("offline")
		return r
	if (rpc as Dictionary).has("error"):
		r.ok = false
		var e: Variant = rpc["error"]
		r.error = str(e.get("message", "MCP")) if e is Dictionary else str(e)
		return r
	var result: Dictionary = rpc.get("result", {})
	var structured: Variant = result.get("structuredContent")
	if result.get("isError", false):
		r.ok = false
		r.code = str(structured.get("error", "")) if structured is Dictionary else ""
		r.error = _text_of(result)
		if r.code == "not_found":
			r.status = 404
		r.data = structured
		return r
	r.ok = true
	r.data = structured if structured != null else {"text": _text_of(result)}
	return r


## The plugin's current version on the site, the changelog and the download link (to warn "new version available").
func plugin_info() -> Result:
	return await _request(HTTPClient.METHOD_GET, "/plugin/godot/version", null, false, TIMEOUT_SEC)


## Code-based connect (/plugin/device/* routes): no key yet, outside the MCP.
func post_json(path: String, body: Variant) -> Result:
	return await _request(HTTPClient.METHOD_POST, path, body, false, TIMEOUT_SEC)


## Downloads bytes from a link on the same server (audio, image): the links the tools return are
## signed and valid for 24 h, no key needed.
func get_bytes(url: String) -> Result:
	var base := SfxSettings.api_url()
	if not url.begins_with(base + "/"):
		var r := Result.new()
		r.error = T.t("foreign_url")
		return r
	return await _request(HTTPClient.METHOD_GET, url.substr(base.length()), null, true, TIMEOUT_SEC)


func _request(method: int, path: String, body: Variant, raw: bool, timeout: float) -> Result:
	# Outside the tree (panel not mounted yet, editor exporting from the command line) an
	# HTTPRequest doesn't run: answer "no connection" instead of throwing an error in the console.
	if not is_inside_tree():
		var off := Result.new()
		off.error = T.t("offline")
		return off
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.use_threads = true
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json, text/event-stream",
		"Accept-Language: " + T.http_language(),
		"MCP-Protocol-Version: " + PROTOCOL_VERSION,
		# Who is calling and on which version: the site warns about new versions and blocks ones that are too old.
		"X-Gomo-Client: godot/" + SfxSettings.plugin_version(),
	])
	var key := SfxSettings.api_key()
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var payload := JSON.stringify(body) if body != null else ""
	var r := Result.new()
	var err := http.request(SfxSettings.api_url() + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		r.error = T.t("request_failed", error_string(err))
		return r
	var resp: Array = await http.request_completed
	http.queue_free()
	return _parse(resp, raw)


func _parse(resp: Array, raw: bool) -> Result:
	var r := Result.new()
	var net_result: int = resp[0]
	r.status = resp[1]
	for h: String in resp[2]:
		if h.to_lower().begins_with("content-type:"):
			r.content_type = h.substr(13).strip_edges()
	var body: PackedByteArray = resp[3]
	if net_result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[Gomo Sounds] no connection to %s (HTTPRequest result %d)" % [SfxSettings.api_url(), net_result])
		r.error = T.t("offline")
		return r
	r.ok = r.status >= 200 and r.status < 300
	if raw and r.ok:
		r.bytes = body
		return r
	var text := body.get_string_from_utf8()
	# The MCP answers in SSE when the tool waits (generating): the response is the "data:" that has the id.
	var parsed: Variant = sse_answer(text) if r.content_type.begins_with("text/event-stream") else JSON.parse_string(text)
	r.data = parsed
	if not r.ok:
		var msg := "HTTP %d" % r.status
		if parsed is Dictionary:
			var e: Variant = (parsed as Dictionary).get("error")
			if e is Dictionary:
				msg = str(e.get("message", msg))
		r.error = msg
	return r


## The response of an MCP SSE stream: the message with "id" (the others are progress notices).
static func sse_answer(text: String) -> Variant:
	var answer: Variant = null
	for line in text.split("\n"):
		if not line.begins_with("data:"):
			continue
		var msg: Variant = JSON.parse_string(line.substr(5).strip_edges())
		if msg is Dictionary and (msg as Dictionary).has("id"):
			answer = msg
	return answer


static func _text_of(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for c: Variant in result.get("content", []):
		if c is Dictionary and str(c.get("type", "")) == "text":
			parts.append(str(c.get("text", "")))
	return "\n".join(parts)
