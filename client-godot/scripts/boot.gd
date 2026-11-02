extends Control
## Native player registration, player login, and isolated admin login.
## The backend issues JWTs. Never store passwords or require users to paste JWTs.

const Adapter = preload("res://scripts/network/authoritative_command_gateway.gd")
const Backdrop = preload("res://scripts/login_ocean_backdrop.gd")
const AUTH_REQUEST_TIMEOUT_SECONDS := 15.0
## Below this viewport height (short landscape phones, keyboard up) the sign-in form switches to a compact layout so
## every control stays on screen at the 44 px minimum touch size.
const COMPACT_HEIGHT := 640.0
const TOUCH_MIN_HEIGHT := 44.0
const LIVE_SERVER_URL := "wss://isles-of-mythos.onrender.com/ws"
const SESSION_PATH := "user://iom_login_session.cfg"

@onready var _status: Label = $Panel/Margin/Content/Status
@onready var _endpoint: LineEdit = $Panel/Margin/Content/Endpoint
@onready var _identifier: LineEdit = $Panel/Margin/Content/Identifier
@onready var _email: LineEdit = $Panel/Margin/Content/Email
@onready var _password: LineEdit = $Panel/Margin/Content/Password
@onready var _connect: Button = $Panel/Margin/Content/Connect
@onready var _player_button: Button = $Panel/Margin/Content/Modes/PlayerLogin
@onready var _register_button: Button = $Panel/Margin/Content/Modes/RegisterPlayer
@onready var _admin_button: Button = $Panel/Margin/Content/Modes/AdminLogin
@onready var _panel: PanelContainer = $Panel
@onready var _margin: MarginContainer = $Panel/Margin
@onready var _content: VBoxContainer = $Panel/Margin/Content
@onready var _title: Label = $Panel/Margin/Content/Title
@onready var _remember_me: CheckButton = $Panel/Margin/Content/Remember/RememberMe
@onready var _remember_password: CheckButton = $Panel/Margin/Content/Remember/RememberPassword
@onready var _sign_out: Button = $Panel/Margin/Content/Remember/SignOut

var _adapter: Node
var _http: HTTPRequest
var _refresh_token := ""
var _mode := "player"
var _busy := false
var _pending_auth_endpoint := ""
var _pending_kind := ""
var _session := ConfigFile.new()
var _loading_session := false
var _glow := 0.0

func _ready() -> void:
    var backdrop: Control = Backdrop.new()
    backdrop.name = "OceanBackdrop"
    backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    backdrop.offset_left = 0.0
    backdrop.offset_top = 0.0
    backdrop.offset_right = 0.0
    backdrop.offset_bottom = 0.0
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)
    move_child(backdrop, 0)
    _style_login_card()

    _adapter = Adapter.new()
    add_child(_adapter)
    _adapter.status_changed.connect(_on_status_changed)
    _adapter.message_received.connect(_on_message)
    _adapter.auth_failed.connect(_on_auth_failed)
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
    _remember_me.toggled.connect(_on_remember_me_toggled)
    _remember_password.toggled.connect(_on_remember_password_toggled)
    _sign_out.pressed.connect(_on_sign_out_pressed)
    _polish_button(_player_button, false)
    _polish_button(_register_button, false)
    _polish_button(_admin_button, false)
    _polish_button(_connect, true)
    _polish_button(_sign_out, false)

    var endpoint := OS.get_environment("IOM_WS_URL")
    if endpoint.is_empty():
        endpoint = str(ProjectSettings.get_setting("application/config/default_ws_url", ""))
    if endpoint.is_empty():
        endpoint = LIVE_SERVER_URL
    _endpoint.text = endpoint
    _switch_mode("player", false)
    get_viewport().size_changed.connect(_apply_responsive_layout)
    _apply_responsive_layout()
    _load_saved_session()
    if _endpoint.text.is_empty():
        _status.text = "Server not configured. Enter the game's WSS address."

func _process(delta: float) -> void:
    _glow += delta
    var pulse := 0.55 + 0.45 * sin(_glow * 2.2)
    _title.add_theme_color_override("font_shadow_color", Color(1.0, 0.72, 0.28, 0.35 + 0.45 * pulse))

func _style_login_card() -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(0.04, 0.11, 0.16, 0.9)
    box.border_color = Color("#f0d48a")
    box.set_border_width_all(2)
    box.set_corner_radius_all(18)
    box.shadow_color = Color(0.02, 0.05, 0.08, 0.35)
    box.shadow_size = 0
    _panel.add_theme_stylebox_override("panel", box)

func _polish_button(button: Button, hero: bool) -> void:
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("#e0a045") if hero else Color("#14606a")
    normal.border_color = Color("#fff1cc") if hero else Color("#f0d48a")
    normal.set_border_width_all(2 if hero else 1)
    normal.set_corner_radius_all(14)
    normal.content_margin_left = 8
    normal.content_margin_right = 8
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color("#f0b45a") if hero else Color("#1d7c88")
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color("#c9842a") if hero else Color("#0e4c54")
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("focus", hover)
    button.add_theme_color_override("font_color", Color("#fff8ea"))

func _apply_responsive_layout() -> void:
    var height := get_viewport().get_visible_rect().size.y
    var compact := height < COMPACT_HEIGHT
    _content.add_theme_constant_override("separation", 4 if compact else 8)
    for side in ["left", "right"]:
        _margin.add_theme_constant_override("margin_" + side, 16 if compact else 32)
    for side in ["top", "bottom"]:
        _margin.add_theme_constant_override("margin_" + side, 8 if compact else 26)
    # Compact: fill the viewport height (small gap) instead of the fixed 540 px card.
    var half_height := (height * 0.5 - 8.0) if compact else 330.0
    _panel.offset_top = -half_height
    _panel.offset_bottom = half_height
    var sizes := {"Title": 30, "Subtitle": 14, "Status": 14}
    for node_name in sizes:
        var label: Label = _content.get_node(node_name)
        if compact:
            label.add_theme_font_size_override("font_size", sizes[node_name])
        else:
            label.remove_theme_font_size_override("font_size")
    _title.add_theme_font_size_override("font_size", 24 if compact else 40)
    _title.add_theme_color_override("font_color", Color("#fff6df"))
    _title.add_theme_constant_override("shadow_offset_x", 0)
    _title.add_theme_constant_override("shadow_offset_y", 0)
    _title.add_theme_constant_override("shadow_outline_size", 8 if compact else 12)
    var hint: Label = _content.get_node("Hint")
    if compact:
        hint.add_theme_font_size_override("font_size", 11)
    else:
        hint.remove_theme_font_size_override("font_size")
    var touch_height := TOUCH_MIN_HEIGHT if compact else 48.0
    for control: Control in [_endpoint, _identifier, _email, _password, _player_button, _register_button, _admin_button, _remember_me, _remember_password, _sign_out]:
        control.custom_minimum_size.y = touch_height
    _connect.custom_minimum_size.y = touch_height if compact else 56.0

func _switch_mode(mode: String, animate := true) -> void:
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
    if animate and is_inside_tree():
        _panel.modulate.a = 0.72
        var tween := create_tween()
        tween.tween_property(_panel, "modulate:a", 1.0, 0.18)

func _auth_api_path(mode: String) -> String:
    if mode == "register":
        return "/auth/register"
    if mode == "admin":
        return "/auth/admin/login"
    if mode == "refresh":
        return "/auth/refresh"
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
    _sign_out.disabled = value

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
    _pending_kind = "password"
    _pending_auth_endpoint = endpoint
    _set_busy(true)
    _status.text = "Creating account…" if _mode == "register" else "Checking credentials…"
    var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
    var error := _http.request(base + _auth_api_path(_mode), headers, HTTPClient.METHOD_POST, body)
    if error != OK:
        _pending_kind = ""
        _pending_auth_endpoint = ""
        _password.clear()
        _set_busy(false)
        _status.text = "Cannot reach the authentication service. Check server configuration."

func _on_auth_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var kind := _pending_kind
    var authenticated_endpoint := _pending_auth_endpoint
    _pending_kind = ""
    _pending_auth_endpoint = ""
    var typed_password := _password.text
    if kind != "refresh":
        _password.clear()
    _set_busy(false)
    if result != HTTPRequest.RESULT_SUCCESS:
        if kind == "refresh":
            _drop_refresh_token()
            _status.text = "Saved session expired. Sign in again."
        else:
            _status.text = "Cannot contact authentication server. Check WSS address and connection."
        return
    var decoded = JSON.parse_string(body.get_string_from_utf8())
    if response_code < 200 or response_code >= 300:
        if kind == "refresh":
            _drop_refresh_token()
            _status.text = "Saved session expired. Sign in again."
            return
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
    var refresh = decoded.get("refreshToken", "")
    _refresh_token = refresh if refresh is String else ""

    if _mode == "admin" and kind != "refresh":
        if decoded.get("role", "") != "admin":
            _status.text = "Administrator access denied."
            return
        _store_secrets(authenticated_endpoint, "", typed_password)
        # No admin gameplay or privileged actions are exposed by this screen.
        # No admin token or password is persisted on the device unless Remember password is on.
        _status.text = "Administrator authenticated. Management console is not enabled in this build."
        return

    _store_secrets(authenticated_endpoint, refresh if refresh is String else "", typed_password)
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
        if bool(ProjectSettings.get_setting("application/config/internal_gameplay_handoff", true)):
            _launch_internal_gameplay(message)

func show_signed_out(reason: String) -> void:
    _status.text = "Session ended (%s). Sign in again." % reason

func _on_auth_failed(reason: String) -> void:
    _status.text = "Sign-in rejected (%s). Sign in again." % reason

func _launch_internal_gameplay(message: Dictionary) -> void:
    var user_id = message.get("userId")
    if not (user_id is String) or user_id.is_empty() or not _adapter._attempt_active or not _adapter._auth_sent:
        return
    if _adapter._url.is_empty() or _adapter._token.is_empty():
        return
    var gameplay = load("res://gameplay/vertical_slice.tscn").instantiate()
    gameplay.begin_authenticated_session(_adapter._url, _adapter._token, _refresh_token)
    get_tree().root.add_child(gameplay)
    get_tree().current_scene = gameplay
    queue_free()

func _passphrase() -> String:
    return OS.get_unique_id()

func _config_text(cfg: ConfigFile) -> String:
    var lines := PackedStringArray(["[session]"])
    for key in ["username", "refresh_token", "password", "endpoint"]:
        if not cfg.has_section_key("session", key):
            continue
        var raw := str(cfg.get_value("session", key))
        raw = raw.replace("\\", "\\\\").replace("\"", "\\\"")
        lines.append("%s=\"%s\"" % [key, raw])
    return "\n".join(lines) + "\n"

func _parse_config_text(cfg: ConfigFile, text: String) -> void:
    var section := ""
    for line in text.split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with("[") and trimmed.ends_with("]"):
            section = trimmed.substr(1, trimmed.length() - 2)
            continue
        var eq := trimmed.find("=")
        if eq <= 0 or section.is_empty():
            continue
        var key := trimmed.substr(0, eq).strip_edges()
        var raw := trimmed.substr(eq + 1).strip_edges()
        if raw.begins_with("\"") and raw.ends_with("\"") and raw.length() >= 2:
            raw = raw.substr(1, raw.length() - 2).replace("\\\"", "\"").replace("\\\\", "\\")
        cfg.set_value(section, key, raw)

func _write_session() -> void:
    var passphrase := _passphrase()
    if passphrase.is_empty():
        return
    if not _session.has_section_key("session", "username") and not _session.has_section_key("session", "refresh_token") and not _session.has_section_key("session", "password"):
        _erase_session_file()
        return
    var file := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.WRITE, passphrase)
    if file == null:
        return
    file.store_string(_config_text(_session))
    file.close()

func _read_session() -> ConfigFile:
    var cfg := ConfigFile.new()
    var passphrase := _passphrase()
    if passphrase.is_empty():
        return cfg
    var file := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.READ, passphrase)
    if file == null:
        return cfg
    var text := file.get_as_text()
    file.close()
    _parse_config_text(cfg, text)
    return cfg

func _erase_session_file() -> void:
    if FileAccess.file_exists(SESSION_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))

func _load_saved_session() -> void:
    _session = _read_session()
    var username := str(_session.get_value("session", "username", ""))
    var refresh := str(_session.get_value("session", "refresh_token", ""))
    var password := str(_session.get_value("session", "password", ""))
    var endpoint := str(_session.get_value("session", "endpoint", ""))
    _loading_session = true
    _remember_me.button_pressed = not refresh.is_empty()
    _remember_password.button_pressed = not password.is_empty()
    _loading_session = false
    if not username.is_empty():
        _identifier.text = username
    if not password.is_empty():
        _password.text = password
    if not endpoint.is_empty():
        _endpoint.text = endpoint
    if not refresh.is_empty():
        _auto_login(refresh)

func _auto_login(refresh: String) -> void:
    var endpoint := _endpoint.text.strip_edges()
    var base := _auth_base_url_for_endpoint(endpoint)
    if base.is_empty():
        _status.text = "Saved session needs a valid server URL."
        return
    _pending_kind = "refresh"
    _pending_auth_endpoint = endpoint
    _set_busy(true)
    _status.text = "Signing in…"
    var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
    var error := _http.request(base + _auth_api_path("refresh"), headers, HTTPClient.METHOD_POST, JSON.stringify({"refreshToken": refresh}))
    if error != OK:
        _pending_kind = ""
        _pending_auth_endpoint = ""
        _set_busy(false)
        _status.text = "Could not reuse the saved session."

func _store_secrets(endpoint: String, refresh: String, typed_password: String) -> void:
    var keep_refresh := _remember_me.button_pressed and _mode != "admin" and not refresh.is_empty()
    var keep_password := _remember_password.button_pressed and not typed_password.is_empty()
    if not keep_refresh and not keep_password:
        _session = ConfigFile.new()
        _erase_session_file()
        return
    if keep_refresh:
        _session.set_value("session", "refresh_token", refresh)
        _session.set_value("session", "username", _identifier.text.strip_edges())
    else:
        _session.erase_section_key("session", "refresh_token")
    if keep_password:
        _session.set_value("session", "username", _identifier.text.strip_edges())
        _session.set_value("session", "password", typed_password)
        _password.text = typed_password
    else:
        _session.erase_section_key("session", "password")
    if not endpoint.is_empty():
        _session.set_value("session", "endpoint", endpoint)
    _write_session()

func _drop_refresh_token() -> void:
    _session.erase_section_key("session", "refresh_token")
    _loading_session = true
    _remember_me.button_pressed = false
    _loading_session = false
    _write_session()

func _on_remember_me_toggled(on: bool) -> void:
    if _loading_session:
        return
    if on:
        return
    _session.erase_section_key("session", "refresh_token")
    if not _remember_password.button_pressed:
        _session.erase_section_key("session", "username")
    _write_session()

func _on_remember_password_toggled(on: bool) -> void:
    if _loading_session:
        return
    if on:
        return
    _password.clear()
    _session.erase_section_key("session", "password")
    _write_session()

func _on_sign_out_pressed() -> void:
    _loading_session = true
    _remember_me.button_pressed = false
    _remember_password.button_pressed = false
    _loading_session = false
    _identifier.clear()
    _password.clear()
    _email.clear()
    _session = ConfigFile.new()
    _erase_session_file()
    _status.text = "Signed out on this device."
