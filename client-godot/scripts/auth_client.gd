class_name IslesAuthClient
extends RefCounted

# Pure helpers for the register/login flow. Rules mirror server/src/auth.ts:
# register: username 3-32 [A-Za-z0-9_], email <=254, password 12-128.
# login: identifier 3-254 (username or email), password 1-128.

const USERNAME_PATTERN := "^[A-Za-z0-9_]{3,32}$"
const EMAIL_PATTERN := "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
const PASSWORD_MIN := 12
const PASSWORD_MAX := 128

static func api_base_from_ws(ws_url: String) -> String:
	var url := ws_url.strip_edges()
	if url.begins_with("wss://"):
		url = "https://" + url.substr(6)
	elif url.begins_with("ws://"):
		url = "http://" + url.substr(5)
	else:
		return ""
	var scheme_end := url.find("://") + 3
	var path_start := url.find("/", scheme_end)
	if path_start != -1:
		url = url.substr(0, path_start)
	return url

static func validate(mode: String, username: String, email: String, password: String) -> String:
	var user := username.strip_edges()
	if mode == "register":
		if not _matches(user, USERNAME_PATTERN):
			return "Username must be 3–32 letters, digits or _"
		var mail := email.strip_edges()
		if mail.length() > 254 or not _matches(mail, EMAIL_PATTERN):
			return "Enter a valid email address"
		if password.length() < PASSWORD_MIN or password.length() > PASSWORD_MAX:
			return "Password must be 12–128 characters"
		return ""
	if user.length() < 3 or user.length() > 254:
		return "Enter your username or email"
	if password.is_empty() or password.length() > PASSWORD_MAX:
		return "Enter your password"
	return ""

static func build_request(mode: String, username: String, email: String, password: String) -> Dictionary:
	if mode == "register":
		return {
			"path": "/auth/register",
			"body": {"username": username.strip_edges(), "email": email.strip_edges(), "password": password},
		}
	return {"path": "/auth/login", "body": {"identifier": username.strip_edges(), "password": password}}

static func message_for_result(mode: String, result: int, code: int) -> String:
	# HTTPRequest.RESULT_SUCCESS == 0. Any transport failure is reported as unreachable.
	if result != 0:
		return "Server unreachable. Check the server URL."
	match code:
		200, 201:
			return ""
		400:
			return "Check the details: username, email and a 12+ character password" if mode == "register" else "Check your username and password"
		401:
			return "Invalid username or password"
		409:
			return "That username or email is already registered"
		429:
			return "Too many attempts. Wait a minute and try again"
		_:
			return "Server error (%d). Try again" % code

static func token_from_body(body: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		var token: Variant = parsed.get("accessToken", "")
		if token is String:
			return token
	return ""

static func _matches(text: String, pattern: String) -> bool:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.search(text) != null
