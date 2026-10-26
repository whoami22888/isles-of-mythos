extends Control
## Native player registration, player login, and isolated admin login.
## The backend issues JWTs. Never store passwords or require users to paste JWTs.

const Adapter = preload("res://scripts/websocket_adapter.gd")
const AUTH_REQUEST_TIMEOUT_SECONDS := 15.0

@onready var _status: Label = $Panel/Margin/Content/Status
@onready var _endpoint: LineEdit = $Panel/Margin/Content/Endpoint
@onready var _identifier: LineEdit = $Panel/Margin/Content/Identifier
@onready var _email: LineEdit = $Panel/Margin/Content/Email
@onready var _password: LineEdit = $Panel/Margin/Content/Password
@onready var _connect: Button = $Panel/Margin/Content/Connect
@onready var _player_button: Button = $Panel/Margin/Content/Modes/PlayerLogin
@onready var _register_button: Button = $Panel/Margin/Content/Modes/RegisterPlayer
@onready var _admin_button: Button = $Panel/Margin/Content/Modes/AdminLogin

var _adapter: Node
var _http: HTTPRequest
var _mode := "player"
var _busy := false
var _pending_auth_endpoint := ""

func _ready() -> void:
    _adapter = Adapter.new()
    add_child(_adapter)
    _adapter.status_changed.connect(_on_status_changed)
    _adapter.message_received.connect(_on_message)
    _http = HTTPRequest.new()
    # Credentials must never be forwarded to a different origin by a 3xx.
    _http.max_redirects = 0
    _http.timeout = AUTH_REQUEST_TIMEOUT_SECONDS
    add_child(_http)
    _http.request_completed.connect(_on_auth_completed)

    _connect.pressed.connect(_connect_from_form)
    _player_button.pressed.connect(func() -> void: _switch_mode("player"))
    _register_button.pressed.connect(func() -> void: _switch_mode("register"))
    _admin_button.pressed.connect(func() -> void: _switch_mode("admin"))

    var endpoint := OS.get_environment("IOM_WS_URL")
    if endpoint.is_empty():
        endpoint = str(ProjectSettings.get_setting("application/config/default_ws_url", ""))
    _endpoint.text = endpoint
    _switch_mode("player")
    if endpoint.is_empty():
        _status.text = "Server not configured. Enter the game's WSS address."

func _switch_mode(mode: String) -> void:
    if _busy or not mode in ["player", "register", "admin"]:
        return
    _mode = mode
    _email.visible = mode == "register"
    _identifier.placeholder_text = "Username" if mode == "register" else "Username or email"
    _connect.text = "Create player account" if mode == "register" else ("Administrator sign in" if mode == "admin" else "Player sign in")
    _status.text = "Admin access requires an approved account." if mode == "admin" else ("Create a new player account." if mode == "register" else "Sign in with your player account.")
    _player_button.disabled = mode == "player"
    _register_button.disabled = mode == "register"
    _admin_button.disabled = mode == "admin"

func _auth_api_path(mode: String) -> String:
    if mode == "register":
        return "/auth/register"
    if mode == "admin":
        return "/auth/admin/login"
    return "/auth/login"

func _auth_base_url_for_endpoint(endpoint: String) -> String:
    var url := endpoint.strip_edges()
    if not url.ends_with("/ws") or url.contains("?") or url.contains("#"):
        return ""
    if not _adapter._is_safe_authenticated_url(url):
        return ""
    if url.begins_with("wss://"):
        return "https://" + url.substr(6).trim_suffix("/ws")
    if url.begins_with("ws://"):
        return "http://" + url.substr(5).trim_suffix("/ws")
    return ""

func _auth_payload(identifier: String, password: String, email: String, mode: String) -> Dictionary:
    if mode == "register":
        return {"username": identifier, "email": email, "password": password}
    return {"identifier": identifier, "password": password}

func _set_busy(value: bool) -> void:
    _busy = value
    _endpoint.editable = not value
    _connect.disabled = value
    _player_button.disabled = value or _mode == "player"
    _register_button.disabled = value or _mode == "register"
    _admin_button.disabled = value or _mode == "admin"

func _connect_from_form() -> void:
    if _busy:
        return
    var endpoint := _endpoint.text.strip_edges()
    var base := _auth_base_url_for_endpoint(endpoint)
    if base.is_empty():
        _status.text = "Enter a valid wss://server.example/ws (local ws://127.0.0.1 only for development)."
        return
    var identifier := _identifier.text.strip_edges()
    var password := _password.text
    if identifier.is_empty() or password.is_empty():
        _status.text = "Enter your username and password."
        return
    if _mode == "register" and (identifier.length() < 3 or password.length() < 12 or not _email.text.contains("@")):
        _status.text = "Registration needs a 3+ character username, email and 12+ character password."
        return

    var body := JSON.stringify(_auth_payload(identifier, password, _email.text.strip_edges(), _mode))
    _pending_auth_endpoint = endpoint
    _set_busy(true)
    _status.text = "Creating account…" if _mode == "register" else "Checking credentials…"
    var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
    var error := _http.request(base + _auth_api_path(_mode), headers, HTTPClient.METHOD_POST, body)
    if error != OK:
        _pending_auth_endpoint = ""
        _password.clear()
        _set_busy(false)
        _status.text = "Cannot reach the authentication service. Check server configuration."

func _on_auth_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var authenticated_endpoint := _pending_auth_endpoint
    _pending_auth_endpoint = ""
    _password.clear()
    _set_busy(false)
    if result != HTTPRequest.RESULT_SUCCESS:
        _status.text = "Cannot contact authentication server. Check WSS address and connection."
        return
    var decoded = JSON.parse_string(body.get_string_from_utf8())
    if response_code < 200 or response_code >= 300:
        if response_code == 401:
            _status.text = "Invalid credentials or administrator not provisioned."
        elif response_code == 409:
            _status.text = "Username or email is already registered."
        elif response_code == 429:
            _status.text = "Too many attempts. Try again later."
        else:
            _status.text = "Authentication failed (HTTP %d)." % response_code
        return
    if not (decoded is Dictionary):
        _status.text = "Unexpected authentication response from server."
        return
    var token = decoded.get("accessToken", "")
    if not (token is String) or token.is_empty():
        _status.text = "Server returned no valid player session."
        return

    if _mode == "admin":
        if decoded.get("role", "") != "admin":
            _status.text = "Administrator access denied."
            return
        # No admin gameplay or privileged actions are exposed by this screen.
        # No admin token or password is persisted on the device.
        _status.text = "Administrator authenticated. Management console is not enabled in this build."
        return

    _status.text = "Authenticated. Connecting to game server…"
    if authenticated_endpoint.is_empty():
        _status.text = "Authentication response had no matching server. Sign in again."
        return
    _adapter.configure(authenticated_endpoint, token)
    _adapter.connect_to_server()

func _on_status_changed(status: String) -> void:
    _status.text = status

func _on_message(message: Dictionary) -> void:
    if message.get("type", "") == "auth_ok":
        _status.text = "Ready · player authenticated by server"
        if ProjectSettings.get_setting("application/config/internal_gameplay_handoff", false):
            _launch_internal_gameplay(message)

func _launch_internal_gameplay(message: Dictionary) -> void:
    var user_id = message.get("userId")
    if not (user_id is String) or user_id.is_empty() or not _adapter._attempt_active or not _adapter._auth_sent:
        return
    if _adapter._url.is_empty() or _adapter._token.is_empty():
        return
    var gameplay = load("res://gameplay/vertical_slice.tscn").instantiate()
    gameplay.begin_authenticated_session(_adapter._url, _adapter._token)
    get_tree().root.add_child(gameplay)
    get_tree().current_scene = gameplay
    queue_free()
