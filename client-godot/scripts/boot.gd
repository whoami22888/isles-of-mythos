extends Control
## Title card, then the existing player registration, player login, and isolated admin login.
## The backend issues JWTs. Players never paste a token.
## Remember password is an explicit opt-in and stays in the app-private user:// file.
## Administrator passwords and tokens are never written there.

const Adapter = preload("res://scripts/network/authoritative_command_gateway.gd")
const CARVED_SHADER = preload("res://shaders/carved_gold.gdshader")
const GLOW_SHADER = preload("res://shaders/gold_glow.gdshader")
const AUTH_REQUEST_TIMEOUT_SECONDS := 15.0
## Below this viewport height (short landscape phones, keyboard up) the sign-in form switches to a compact layout so
## every control stays on screen at the 44 px minimum touch size.
const COMPACT_HEIGHT := 640.0
const TOUCH_MIN_HEIGHT := 44.0
const INTRO_VIDEO := "res://assets/video/intro_cinematic.ogv"
const TITLE_VIDEO := "res://assets/video/title_loop.ogv"
const BOOM_AUDIO := "res://assets/audio/cannon_boom.wav"
const BED_AUDIO := "res://assets/audio/shanty_bed.ogg"
const DISPLAY_FONT := "res://assets/fonts/PirataOne-Regular.ttf"
const UI_FONT := "res://assets/fonts/IMFeENrm28P.ttf"
const SESSION_PATH := "user://iom_login_session.cfg"
const LIVE_SERVER_URL := "wss://isles-of-mythos.onrender.com/ws"
const INTRO_HINT_AT := 1.0
const INTRO_TIMEOUT := 12.0
const MUSIC_DB := -9.0

enum Phase { INTRO, BOOM, TITLE, LOGIN }

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

var _phase := Phase.INTRO
var _intro_time := 0.0
var _prompt_time := 0.0
var _shake_left := 0.0
var _user_muted := false
var _burst_origin := Vector2.ZERO
var _display_font: Font
var _ui_font: Font
var _backdrop: ColorRect
var _shake: Control
var _intro_video: VideoStreamPlayer
var _title_video: VideoStreamPlayer
var _logo: Control
var _logo_glow: ColorRect
var _logo_isles: Label
var _logo_mythos: Label
var _logo_shadow_isles: Label
var _logo_shadow_mythos: Label
var _wheel: Node2D
var _flash: ColorRect
var _debris: CPUParticles2D
var _spray: CPUParticles2D
var _skip_hint: Label
var _prompt: Label
var _mute: Button
var _advanced: Button
var _boom: AudioStreamPlayer
var _music: AudioStreamPlayer
var _flash_tween: Tween
var _logo_tween: Tween
var _panel_tween: Tween
var _session := ConfigFile.new()
var _loading_session := false
var _laying_out := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
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

    _build_title_presentation()
    var endpoint := OS.get_environment("IOM_WS_URL")
    if endpoint.is_empty():
        endpoint = str(ProjectSettings.get_setting("application/config/default_ws_url", ""))
    if endpoint.is_empty():
        endpoint = LIVE_SERVER_URL
    _endpoint.text = endpoint
    _switch_mode("player")
    get_viewport().size_changed.connect(_apply_responsive_layout)
    _apply_responsive_layout()
    _load_saved_session()
    _start_intro()
    if endpoint.is_empty():
        _status.text = "Server not configured. Enter the game's WSS address."

func _process(delta: float) -> void:
    if _phase == Phase.INTRO:
        _intro_time += delta
        if _intro_time >= INTRO_HINT_AT:
            _skip_hint.visible = true
            _skip_hint.modulate.a = minf(1.0, _skip_hint.modulate.a + delta * 3.0)
        if _intro_time >= INTRO_TIMEOUT:
            _begin_boom()
    elif _phase == Phase.BOOM:
        _apply_shake()
    elif _phase == Phase.TITLE:
        _animate_prompt(delta)
        _pulse_logo(delta)
    elif _shake.position != Vector2.ZERO:
        _shake.position = Vector2.ZERO
        _flash.position = Vector2.ZERO

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        _set_media_paused(true)
    elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
        _set_media_paused(false)

func _unhandled_input(event: InputEvent) -> void:
    var pressed := false
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed = true
    elif event is InputEventScreenTouch and event.pressed:
        pressed = true
    elif event.is_action_pressed("ui_accept"):
        pressed = true
    if not pressed or _busy:
        return
    if _phase == Phase.INTRO:
        _begin_boom()
        get_viewport().set_input_as_handled()
    elif _phase == Phase.TITLE:
        if _has_saved_session():
            _auto_sign_in()
        else:
            _open_login(true)
        get_viewport().set_input_as_handled()

func _build_title_presentation() -> void:
    _display_font = _load_font(DISPLAY_FONT)
    _ui_font = _load_font(UI_FONT)
    _backdrop = ColorRect.new()
    _backdrop.name = "Backdrop"
    _backdrop.color = Color(0.015, 0.045, 0.07)
    _backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_backdrop)
    move_child(_backdrop, 0)
    _fill(_backdrop)

    _shake = Control.new()
    _shake.name = "ShakeRoot"
    _shake.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _shake.clip_contents = true
    add_child(_shake)
    move_child(_shake, 1)
    _fill(_shake)

    _title_video = _make_video("TitleVideo")
    _intro_video = _make_video("IntroVideo")
    _shake.add_child(_title_video)
    _shake.add_child(_intro_video)
    _fill(_title_video)
    _fill(_intro_video)

    _logo = Control.new()
    _logo.name = "TitleLogo"
    _logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _shake.add_child(_logo)
    _logo_glow = ColorRect.new()
    _logo_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _logo_glow.material = _shader_material(GLOW_SHADER)
    _logo_glow.color = Color(1, 1, 1, 1)
    _logo.add_child(_logo_glow)
    _logo_shadow_isles = _make_logo_line("ISLES OF", true)
    _logo_shadow_mythos = _make_logo_line("MYTHOS", true)
    _logo_isles = _make_logo_line("ISLES OF", false)
    _logo_mythos = _make_logo_line("MYTHOS", false)
    _logo.add_child(_logo_shadow_isles)
    _logo.add_child(_logo_shadow_mythos)
    _logo.add_child(_logo_isles)
    _logo.add_child(_logo_mythos)
    _wheel = Node2D.new()
    _wheel.name = "ShipWheel"
    _logo.add_child(_wheel)
    _build_wheel(_wheel)
    _logo.visible = false

    _flash = ColorRect.new()
    _flash.name = "ImpactFlash"
    _flash.color = Color(1, 1, 1, 1)
    _flash.modulate.a = 0.0
    _flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _flash.z_index = 7
    add_child(_flash)
    _fill(_flash)

    var blob := _soft_blob()
    _debris = _make_burst("Debris", blob, Color(0.62, 0.36, 0.14), 76, 0.95, 320.0, 880.0, 760.0, 4.0, 11.0)
    _spray = _make_burst("Spray", blob, Color(0.82, 0.95, 1.0), 120, 0.72, 220.0, 740.0, 180.0, 2.0, 6.0)
    _debris.z_index = 8
    _spray.z_index = 8

    _skip_hint = Label.new()
    _skip_hint.name = "SkipHint"
    _skip_hint.text = "Tap to skip"
    _skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _skip_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _skip_hint.visible = false
    _skip_hint.modulate.a = 0.0
    _skip_hint.z_index = 12
    add_child(_skip_hint)
    _style_overlay_label(_skip_hint, 22)

    _prompt = Label.new()
    _prompt.name = "SailPrompt"
    _prompt.text = "TAP TO SET SAIL"
    _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _prompt.visible = false
    _prompt.z_index = 12
    add_child(_prompt)
    _style_overlay_label(_prompt, 48)

    _mute = Button.new()
    _mute.name = "MuteAudio"
    _mute.focus_mode = Control.FOCUS_ALL
    _mute.z_index = 20
    _mute.pressed.connect(_on_mute_pressed)
    add_child(_mute)
    _set_access_name(_mute, "Mute title audio")
    _style_mute_button()

    _remember_me.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _remember_password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _sign_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _advanced = Button.new()
    _advanced.name = "Advanced"
    _advanced.text = "Advanced"
    _advanced.tooltip_text = "Show the game server address"
    _advanced.pressed.connect(_on_advanced_pressed)
    _content.add_child(_advanced)
    _content.move_child(_advanced, _endpoint.get_index())
    _endpoint.visible = false
    _set_access_name(_advanced, "Advanced server settings")
    _set_access_name(_remember_me, "Remember me")
    _set_access_name(_remember_password, "Remember password")
    _set_access_name(_sign_out, "Sign out")

    _boom = AudioStreamPlayer.new()
    _boom.name = "Boom"
    _boom.stream = load(BOOM_AUDIO)
    add_child(_boom)
    _music = AudioStreamPlayer.new()
    _music.name = "ShantyBed"
    _music.stream = _looping_stream(BED_AUDIO)
    _music.finished.connect(_on_music_finished)
    add_child(_music)
    _apply_mute()
    _style_login_panel()
    _panel.z_index = 10
    _panel.visible = false

func _make_video(node_name: String) -> VideoStreamPlayer:
    var player := VideoStreamPlayer.new()
    player.name = node_name
    player.mouse_filter = Control.MOUSE_FILTER_IGNORE
    player.volume_db = -80.0
    return player

func _load_font(path: String) -> Font:
    var loaded = load(path)
    if not (loaded is Font):
        return ThemeDB.fallback_font
    var font := (loaded as Font).duplicate() as Font
    if font == null:
        font = loaded
    if font is FontFile:
        var file := font as FontFile
        var fallback := ThemeDB.fallback_font
        if fallback:
            file.fallbacks = [fallback]
    return font

func _shader_material(shader: Shader) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _make_logo_line(text: String, shadow: bool) -> Label:
    var label := Label.new()
    label.text = text
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if _display_font:
        label.add_theme_font_override("font", _display_font)
    if shadow:
        label.add_theme_color_override("font_color", Color(0, 0, 0, 0.88))
        label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
    else:
        label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.34))
        label.add_theme_color_override("font_outline_color", Color(0.16, 0.07, 0.02))
        label.material = _shader_material(CARVED_SHADER)
    return label

func _build_wheel(host: Node2D) -> void:
    var gold := Color(0.95, 0.74, 0.28)
    var dark := Color(0.28, 0.13, 0.04)
    host.add_child(_ring(86.0, 12.0, dark))
    host.add_child(_ring(76.0, 9.0, gold))
    for spoke in 8:
        var arm := Polygon2D.new()
        arm.polygon = PackedVector2Array([Vector2(-5, 18), Vector2(5, 18), Vector2(4, 74), Vector2(-4, 74)])
        arm.color = gold
        arm.rotation = spoke * TAU / 8.0
        host.add_child(arm)
        var handle := _disc(10.0, dark)
        handle.position = Vector2(cos(arm.rotation - PI * 0.5), sin(arm.rotation - PI * 0.5)) * 78.0
        host.add_child(handle)
    host.add_child(_disc(18.0, dark))
    host.add_child(_disc(9.0, gold))

func _ring(radius: float, thickness: float, color: Color) -> Polygon2D:
    var poly := Polygon2D.new()
    var points := PackedVector2Array()
    var segments := 28
    for index in segments + 1:
        var angle := TAU * float(index) / float(segments)
        points.append(Vector2(cos(angle), sin(angle)) * radius)
    for index in range(segments, -1, -1):
        var angle := TAU * float(index) / float(segments)
        points.append(Vector2(cos(angle), sin(angle)) * (radius - thickness))
    poly.polygon = points
    poly.color = color
    return poly

func _disc(radius: float, color: Color) -> Polygon2D:
    var poly := Polygon2D.new()
    var points := PackedVector2Array()
    for index in 18:
        var angle := TAU * float(index) / 18.0
        points.append(Vector2(cos(angle), sin(angle)) * radius)
    poly.polygon = points
    poly.color = color
    return poly

func _soft_blob() -> Texture2D:
    var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    for y in 32:
        for x in 32:
            var distance := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) / 16.0
            var alpha := clampf(1.0 - distance, 0.0, 1.0)
            image.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
    return ImageTexture.create_from_image(image)

func _make_burst(node_name: String, texture: Texture2D, color: Color, amount: int, life: float, speed_min: float, speed_max: float, gravity: float, scale_min: float, scale_max: float) -> CPUParticles2D:
    var particles := CPUParticles2D.new()
    particles.name = node_name
    particles.texture = texture
    particles.amount = amount
    particles.lifetime = life
    particles.one_shot = true
    particles.explosiveness = 0.94
    particles.randomness = 0.35
    particles.direction = Vector2(0, -1)
    particles.spread = 180.0
    particles.gravity = Vector2(0, gravity)
    particles.initial_velocity_min = speed_min
    particles.initial_velocity_max = speed_max
    particles.scale_amount_min = scale_min
    particles.scale_amount_max = scale_max
    particles.damping_min = 40.0
    particles.damping_max = 120.0
    particles.color = color
    particles.emitting = false
    add_child(particles)
    return particles

func _style_overlay_label(label: Label, size: int) -> void:
    if _display_font:
        label.add_theme_font_override("font", _display_font)
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.5))
    label.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.01, 0.92))
    label.add_theme_constant_override("outline_size", 8 if size > 30 else 4)

func _style_mute_button() -> void:
    var box := _flat_box(Color(0.28, 0.15, 0.06, 0.92), Color(0.86, 0.66, 0.28), 2)
    _mute.add_theme_stylebox_override("normal", box)
    _mute.add_theme_stylebox_override("hover", _flat_box(Color(0.4, 0.24, 0.08, 0.96), Color(0.95, 0.78, 0.36), 2))
    _mute.add_theme_stylebox_override("pressed", box)
    _mute.add_theme_stylebox_override("focus", _flat_box(Color(0.4, 0.24, 0.08, 0.96), Color(1.0, 0.9, 0.55), 3))
    if _ui_font:
        _mute.add_theme_font_override("font", _ui_font)
    _mute.add_theme_font_size_override("font_size", 16)
    _mute.add_theme_color_override("font_color", Color(0.98, 0.9, 0.7))
    _mute.custom_minimum_size = Vector2(96, TOUCH_MIN_HEIGHT)

func _style_login_panel() -> void:
    var wood := _flat_box(Color(0.23, 0.12, 0.05, 0.97), Color(0.8, 0.58, 0.22), 5)
    wood.corner_radius_top_left = 14
    wood.corner_radius_top_right = 14
    wood.corner_radius_bottom_right = 14
    wood.corner_radius_bottom_left = 14
    wood.shadow_color = Color(0, 0, 0, 0.55)
    wood.shadow_size = 18
    _panel.add_theme_stylebox_override("panel", wood)
    var parchment := _flat_box(Color(0.95, 0.89, 0.74), Color(0.46, 0.3, 0.12), 2)
    parchment.content_margin_left = 10
    parchment.content_margin_right = 10
    parchment.content_margin_top = 6
    parchment.content_margin_bottom = 6
    var parchment_focus := parchment.duplicate() as StyleBoxFlat
    parchment_focus.border_color = Color(0.78, 0.55, 0.16)
    parchment_focus.set_border_width_all(3)
    for field in [_endpoint, _identifier, _email, _password]:
        field.add_theme_stylebox_override("normal", parchment)
        field.add_theme_stylebox_override("focus", parchment_focus)
        field.add_theme_color_override("font_color", Color(0.2, 0.1, 0.04))
        field.add_theme_color_override("font_placeholder_color", Color(0.4, 0.26, 0.12, 0.8))
        field.add_theme_color_override("caret_color", Color(0.35, 0.18, 0.05))
        if _ui_font:
            field.add_theme_font_override("font", _ui_font)
    var hero := _flat_box(Color(0.72, 0.46, 0.12), Color(0.95, 0.78, 0.34), 2)
    var hero_focus := _flat_box(Color(0.8, 0.54, 0.16), Color(1.0, 0.92, 0.6), 3)
    _connect.add_theme_stylebox_override("normal", hero)
    _connect.add_theme_stylebox_override("hover", _flat_box(Color(0.82, 0.56, 0.18), Color(1.0, 0.88, 0.5), 2))
    _connect.add_theme_stylebox_override("pressed", _flat_box(Color(0.55, 0.32, 0.08), Color(0.9, 0.7, 0.28), 2))
    _connect.add_theme_stylebox_override("disabled", _flat_box(Color(0.4, 0.26, 0.1), Color(0.6, 0.44, 0.18), 2))
    _connect.add_theme_stylebox_override("focus", hero_focus)
    _connect.add_theme_color_override("font_color", Color(0.16, 0.07, 0.02))
    _connect.add_theme_color_override("font_hover_color", Color(0.16, 0.07, 0.02))
    _connect.add_theme_color_override("font_pressed_color", Color(0.16, 0.07, 0.02))
    _connect.add_theme_color_override("font_disabled_color", Color(0.35, 0.22, 0.1))
    if _display_font:
        _connect.add_theme_font_override("font", _display_font)
    for button in [_advanced, _sign_out]:
        _paint_wood_button(button, false)
    var plain := _flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
    var toggle_focus := _flat_box(Color(0, 0, 0, 0), Color(0.95, 0.78, 0.36), 2)
    for toggle in [_remember_me, _remember_password]:
        if _ui_font:
            toggle.add_theme_font_override("font", _ui_font)
        toggle.add_theme_color_override("font_color", Color(0.97, 0.9, 0.74))
        toggle.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
        toggle.add_theme_color_override("font_pressed_color", Color(0.97, 0.9, 0.74))
        toggle.add_theme_color_override("font_disabled_color", Color(0.7, 0.6, 0.42))
        for state in ["normal", "hover", "pressed", "disabled"]:
            toggle.add_theme_stylebox_override(state, plain)
        toggle.add_theme_stylebox_override("focus", toggle_focus)
    if _display_font:
        var title: Label = _content.get_node("Title")
        title.add_theme_font_override("font", _display_font)
        title.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.01))
        title.add_theme_constant_override("outline_size", 2)
    if _ui_font:
        for node_name in ["Subtitle", "Status", "Hint"]:
            var label: Label = _content.get_node(node_name)
            label.add_theme_font_override("font", _ui_font)
        _status.add_theme_color_override("font_color", Color(0.98, 0.91, 0.76))
        _status.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
    _paint_mode_buttons()

func _paint_wood_button(button: Button, selected: bool) -> void:
    var fill := Color(0.62, 0.42, 0.14) if selected else Color(0.33, 0.18, 0.07)
    var font := Color(0.16, 0.07, 0.02) if selected else Color(0.97, 0.88, 0.66)
    button.add_theme_stylebox_override("normal", _flat_box(fill, Color(0.82, 0.62, 0.24), 2))
    button.add_theme_stylebox_override("hover", _flat_box(fill.lightened(0.08), Color(0.95, 0.78, 0.36), 2))
    button.add_theme_stylebox_override("pressed", _flat_box(fill.darkened(0.08), Color(0.75, 0.54, 0.2), 2))
    button.add_theme_stylebox_override("disabled", _flat_box(fill if selected else fill.darkened(0.12), Color(0.7, 0.52, 0.2), 2))
    button.add_theme_stylebox_override("focus", _flat_box(fill.lightened(0.05), Color(1.0, 0.9, 0.55), 3))
    button.add_theme_color_override("font_color", font)
    button.add_theme_color_override("font_hover_color", font)
    button.add_theme_color_override("font_pressed_color", font)
    button.add_theme_color_override("font_disabled_color", font)
    if _ui_font:
        button.add_theme_font_override("font", _ui_font)

func _paint_mode_buttons() -> void:
    _paint_wood_button(_player_button, _mode == "player")
    _paint_wood_button(_register_button, _mode == "register")
    _paint_wood_button(_admin_button, _mode == "admin")

func _flat_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(width)
    box.set_corner_radius_all(6)
    box.content_margin_left = 8
    box.content_margin_right = 8
    box.content_margin_top = 4
    box.content_margin_bottom = 4
    return box

func _looping_stream(path: String) -> AudioStream:
    var loaded = load(path)
    if loaded is AudioStreamOggVorbis:
        var music := (loaded as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
        if music == null:
            return loaded
        music.loop = true
        return music
    if not (loaded is AudioStreamWAV):
        return null
    var loop := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
    if loop == null:
        return loaded
    loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
    loop.loop_begin = 0
    var frames := int(round(loop.get_length() * float(loop.mix_rate)))
    loop.loop_end = maxi(frames, 1)
    return loop

func _apply_responsive_layout() -> void:
    if _laying_out:
        return
    _laying_out = true
    _apply_responsive_layout_body()
    _laying_out = false

func _apply_responsive_layout_body() -> void:
    var view := get_viewport().get_visible_rect().size
    if view.x < 2.0 or view.y < 2.0:
        return
    var insets := _safe_insets(view)
    var compact := view.y < COMPACT_HEIGHT
    var separation := 4 if compact else 8
    var margin_v := 6 if compact else 14
    var margin_h := 12 if compact else 20
    var title_size := 28 if compact else 36
    var touch := TOUCH_MIN_HEIGHT
    var panel_cap := _panel_width(view, insets, compact)
    var content_width := panel_cap - float(margin_h * 2)
    content_width = maxf(220.0, content_width)
    title_size = _fit_font_size(_display_font if _display_font else ThemeDB.fallback_font, "ISLES OF MYTHOS", content_width, title_size, 16)
    var avail_h := view.y - insets.y - insets.w - 4.0
    while true:
        _content.add_theme_constant_override("separation", separation)
        for side in ["left", "right"]:
            _margin.add_theme_constant_override("margin_" + side, margin_h)
        for side in ["top", "bottom"]:
            _margin.add_theme_constant_override("margin_" + side, margin_v)
        _apply_form_metrics(title_size, touch, compact)
        var needed := _stack_height() + float(margin_v * 2)
        if needed <= avail_h or (title_size <= 16 and separation <= 2 and margin_v <= 4):
            break
        if title_size > 16:
            title_size -= 2
        elif separation > 2:
            separation -= 1
        elif margin_v > 4:
            margin_v -= 1
    var panel_w := panel_cap
    var panel_h := minf(avail_h, _stack_height() + float(margin_v * 2))
    _panel.anchor_left = 0.5
    _panel.anchor_right = 0.5
    _panel.anchor_top = 0.5
    _panel.anchor_bottom = 0.5
    _panel.offset_left = -panel_w * 0.5
    _panel.offset_right = panel_w * 0.5
    _panel.offset_top = -panel_h * 0.5
    _panel.offset_bottom = panel_h * 0.5
    _place_chrome(view, insets)
    _place_logo(view, insets)
    _fit_videos(view)

func _panel_width(view: Vector2, insets: Vector4, compact: bool) -> float:
    # Stay clear of the corner mute control, including when the panel is centered.
    var mute_block := 116.0
    var half_limit := view.x * 0.5 - insets.z - mute_block
    return minf(620.0 if compact else 680.0, maxf(420.0, half_limit * 2.0))

func _fill(node: Control) -> void:
    node.layout_mode = 1
    node.anchor_left = 0.0
    node.anchor_top = 0.0
    node.anchor_right = 1.0
    node.anchor_bottom = 1.0
    node.offset_left = 0.0
    node.offset_top = 0.0
    node.offset_right = 0.0
    node.offset_bottom = 0.0
    node.grow_horizontal = Control.GROW_DIRECTION_BOTH
    node.grow_vertical = Control.GROW_DIRECTION_BOTH

func _apply_form_metrics(title_size: int, touch: float, compact: bool) -> void:
    var title: Label = _content.get_node("Title")
    var subtitle: Label = _content.get_node("Subtitle")
    var hint: Label = _content.get_node("Hint")
    title.add_theme_font_size_override("font_size", title_size)
    title.custom_minimum_size.y = title_size + 4
    subtitle.add_theme_font_size_override("font_size", 16 if compact else 18)
    subtitle.custom_minimum_size.y = 20
    _status.add_theme_font_size_override("font_size", 14 if compact else 15)
    _status.custom_minimum_size.y = 28 if compact else 32
    hint.add_theme_font_size_override("font_size", 12 if compact else 14)
    hint.custom_minimum_size.y = 28 if compact else 34
    for control in [_endpoint, _identifier, _email, _password, _player_button, _register_button, _admin_button, _remember_me, _remember_password, _advanced, _sign_out]:
        control.custom_minimum_size.y = touch
    _connect.custom_minimum_size.y = touch if compact else 52.0
    _content.get_node("Remember").custom_minimum_size.y = touch
    _content.get_node("Modes").custom_minimum_size.y = touch

func _stack_height() -> float:
    var total := 0.0
    var seen := 0
    var separation := float(_content.get_theme_constant("separation"))
    for child in _content.get_children():
        var control := child as Control
        if control == null or not control.visible:
            continue
        var height := control.get_combined_minimum_size().y
        if height < control.custom_minimum_size.y:
            height = control.custom_minimum_size.y
        if height < 12.0:
            height = 18.0
        total += height
        seen += 1
    if seen > 1:
        total += separation * float(seen - 1)
    return total

func _fit_font_size(font: Font, text: String, max_width: float, start: int, floor_size: int) -> int:
    var size := start
    if font == null:
        return size
    while size > floor_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
        size -= 1
    return size

func _safe_insets(view: Vector2) -> Vector4:
    var screen := DisplayServer.screen_get_size()
    var safe := DisplayServer.get_display_safe_area()
    var floor_x := 10.0 if view.y < COMPACT_HEIGHT else 16.0
    var floor_y := 6.0 if view.y < COMPACT_HEIGHT else 12.0
    if screen.x < 2 or screen.y < 2:
        return Vector4(floor_x, floor_y, floor_x, floor_y)
    var scale_x := view.x / float(screen.x)
    var scale_y := view.y / float(screen.y)
    var left := safe.position.x * scale_x
    var top := safe.position.y * scale_y
    var right := (float(screen.x) - safe.end.x) * scale_x
    var bottom := (float(screen.y) - safe.end.y) * scale_y
    return Vector4(maxf(left, floor_x), maxf(top, floor_y), maxf(right, floor_x), maxf(bottom, floor_y))

func _place_chrome(view: Vector2, insets: Vector4) -> void:
    _mute.layout_mode = 1
    _mute.anchor_left = 1.0
    _mute.anchor_right = 1.0
    _mute.anchor_top = 0.0
    _mute.anchor_bottom = 0.0
    _mute.offset_right = -insets.z
    _mute.offset_left = -insets.z - 104.0
    _mute.offset_top = insets.y
    _mute.offset_bottom = insets.y + TOUCH_MIN_HEIGHT
    var prompt_w := minf(view.x * 0.72, 860.0)
    var prompt_size := _fit_font_size(_display_font if _display_font else ThemeDB.fallback_font, _prompt.text, prompt_w - 24.0, 52, 28)
    _prompt.add_theme_font_size_override("font_size", prompt_size)
    _prompt.layout_mode = 1
    _prompt.anchor_left = 0.5
    _prompt.anchor_right = 0.5
    _prompt.anchor_top = 1.0
    _prompt.anchor_bottom = 1.0
    _prompt.offset_left = -prompt_w * 0.5
    _prompt.offset_right = prompt_w * 0.5
    _prompt.offset_bottom = -insets.w - 10.0
    _prompt.offset_top = _prompt.offset_bottom - maxf(64.0, float(prompt_size) + 16.0)
    _prompt.pivot_offset = Vector2(prompt_w * 0.5, (_prompt.offset_bottom - _prompt.offset_top) * 0.5)
    _skip_hint.layout_mode = 1
    _skip_hint.anchor_left = 0.5
    _skip_hint.anchor_right = 0.5
    _skip_hint.anchor_top = 1.0
    _skip_hint.anchor_bottom = 1.0
    _skip_hint.offset_left = -220.0
    _skip_hint.offset_right = 220.0
    _skip_hint.offset_bottom = -insets.w - 16.0
    _skip_hint.offset_top = _skip_hint.offset_bottom - 40.0
    _burst_origin = view * 0.5

func _place_logo(view: Vector2, insets: Vector4) -> void:
    if _display_font == null:
        return
    var target_w := (view.x - insets.x - insets.z) * 0.70
    var font_size := _fit_font_size(_display_font, "ISLES OF", target_w, 220, 48)
    var line_h := _display_font.get_height(font_size)
    var isles_w := _display_font.get_string_size("ISLES OF", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var myth_w := _display_font.get_string_size("MYTHOS", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var block_w := maxf(isles_w, myth_w)
    var block_h := line_h * 2.0 + 6.0
    _logo.layout_mode = 1
    _logo.anchor_left = 0.5
    _logo.anchor_right = 0.5
    _logo.anchor_top = 0.46
    _logo.anchor_bottom = 0.46
    _logo.offset_left = -block_w * 0.5
    _logo.offset_right = block_w * 0.5
    _logo.offset_top = -block_h * 0.5
    _logo.offset_bottom = block_h * 0.5
    _logo.pivot_offset = Vector2(block_w * 0.5, block_h * 0.5)
    _layout_logo_line(_logo_shadow_isles, font_size, Vector2(7, 9), 0.0, block_w, line_h)
    _layout_logo_line(_logo_shadow_mythos, font_size, Vector2(7, 9), line_h + 4.0, block_w, line_h)
    _layout_logo_line(_logo_isles, font_size, Vector2.ZERO, 0.0, block_w, line_h)
    _layout_logo_line(_logo_mythos, font_size, Vector2.ZERO, line_h + 4.0, block_w, line_h)
    var outline := maxi(4, int(font_size / 16.0))
    _logo_isles.add_theme_constant_override("outline_size", outline)
    _logo_mythos.add_theme_constant_override("outline_size", outline)
    _logo_shadow_isles.add_theme_constant_override("outline_size", outline + 6)
    _logo_shadow_mythos.add_theme_constant_override("outline_size", outline + 6)
    _logo_glow.position = Vector2(-block_w * 0.08, -line_h * 0.25)
    _logo_glow.size = Vector2(block_w * 1.16, block_h * 1.35)
    var before := _display_font.get_string_size("MYTH", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var letter := _display_font.get_string_size("O", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var text_left := (block_w - myth_w) * 0.5
    _wheel.position = Vector2(text_left + before + letter * 0.5, line_h + 4.0 + line_h * 0.48)
    # The drawn wheel is about 172 px across before scaling. Keep it inside the O.
    _wheel.scale = Vector2.ONE * maxf(0.15, (letter * 0.9) / 172.0)

func _layout_logo_line(label: Label, font_size: int, shift: Vector2, top: float, width: float, height: float) -> void:
    label.add_theme_font_size_override("font_size", font_size)
    label.position = Vector2(shift.x, top + shift.y)
    label.size = Vector2(width, height)

func _fit_videos(view: Vector2) -> void:
    var cover := maxf(view.x / 1280.0, view.y / 720.0)
    var size := Vector2(1280.0, 720.0) * cover
    for player in [_intro_video, _title_video]:
        player.layout_mode = 1
        player.anchor_left = 0.5
        player.anchor_right = 0.5
        player.anchor_top = 0.5
        player.anchor_bottom = 0.5
        player.offset_left = -size.x * 0.5
        player.offset_right = size.x * 0.5
        player.offset_top = -size.y * 0.5
        player.offset_bottom = size.y * 0.5

func _start_intro() -> void:
    var stream = load(INTRO_VIDEO)
    var title_stream = load(TITLE_VIDEO)
    if title_stream != null:
        _title_video.stream = title_stream
        _title_video.loop = true
    if stream == null:
        _begin_boom()
        return
    _intro_video.stream = stream
    _intro_video.loop = false
    # Headless smoke tests have no presentation clock. Bind the stream, then hit the title
    # so authentication checks are not stuck behind the 10 second clip.
    if DisplayServer.get_name() == "headless":
        _begin_boom()
        return
    _apply_mute()
    if not _intro_video.finished.is_connected(_on_intro_finished):
        _intro_video.finished.connect(_on_intro_finished)
    _intro_video.play()

func _on_intro_finished() -> void:
    _begin_boom()

func _begin_boom() -> void:
    if _phase != Phase.INTRO:
        return
    _phase = Phase.BOOM
    _skip_hint.visible = false
    if _intro_video.finished.is_connected(_on_intro_finished):
        _intro_video.finished.disconnect(_on_intro_finished)
    _intro_video.stop()
    _intro_video.visible = false
    _title_video.visible = true
    _title_video.volume_db = -80.0
    if DisplayServer.get_name() != "headless" and _title_video.stream != null and not _title_video.is_playing():
        _title_video.play()
    _flash.modulate.a = 0.0
    _flash_tween = create_tween()
    _flash_tween.tween_property(_flash, "modulate:a", 1.0, 0.15)
    _flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.6)
    _shake_left = 0.5
    _logo.visible = true
    _logo.scale = Vector2(2.45, 2.45)
    _logo.modulate.a = 1.0
    _logo_tween = create_tween()
    _logo_tween.tween_property(_logo, "scale", Vector2.ONE, 0.82).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _logo_tween.tween_callback(_show_title_if_booming)
    _debris.position = _burst_origin
    _spray.position = _burst_origin + Vector2(0, 12)
    _debris.restart()
    _spray.restart()
    _apply_mute()
    if _boom.stream != null and not _user_muted:
        _boom.play()

func _show_title_if_booming() -> void:
    if not is_inside_tree() or _phase != Phase.BOOM:
        return
    _phase = Phase.TITLE
    _prompt.visible = true
    _prompt.text = "TAP TO SET SAIL"
    _prompt.scale = Vector2.ONE
    _apply_mute()
    if _music.stream != null and not _music.playing:
        _music.play()
    if _has_saved_session():
        get_tree().create_timer(0.9).timeout.connect(_auto_sign_in_if_waiting, CONNECT_ONE_SHOT)

func _auto_sign_in_if_waiting() -> void:
    if is_inside_tree() and _phase == Phase.TITLE and not _busy:
        _auto_sign_in()

func _animate_prompt(delta: float) -> void:
    _prompt_time += delta
    var pulse := 0.5 + 0.5 * sin(_prompt_time * 3.4)
    _prompt.scale = Vector2.ONE * lerpf(1.0, 1.06, pulse)
    _prompt.modulate = Color(1.0, 0.84 + 0.12 * pulse, 0.42 + 0.18 * pulse, 1.0)

func _pulse_logo(_delta: float) -> void:
    var pulse := 0.5 + 0.5 * sin(_prompt_time * 2.4)
    _logo_glow.modulate.a = lerpf(0.45, 1.0, pulse)

func _apply_shake() -> void:
    _shake_left = maxf(0.0, _shake_left - get_process_delta_time())
    if _shake_left <= 0.0:
        _shake.position = Vector2.ZERO
        _flash.position = Vector2.ZERO
        _debris.position = _burst_origin
        _spray.position = _burst_origin
        return
    var magnitude := 26.0 * (_shake_left / 0.5)
    var kick := Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))
    _shake.position = kick
    _flash.position = kick
    _debris.position = _burst_origin + kick
    _spray.position = _burst_origin + kick * 0.65

func _on_mute_pressed() -> void:
    _user_muted = not _user_muted
    _apply_mute()

func _apply_mute() -> void:
    var silenced := -80.0
    _mute.text = "Muted" if _user_muted else "Sound"
    _mute.tooltip_text = "Unmute title audio" if _user_muted else "Mute title audio"
    if _intro_video:
        _intro_video.volume_db = silenced if _user_muted else 0.0
    if _title_video:
        _title_video.volume_db = silenced
    if _boom:
        _boom.volume_db = silenced if _user_muted else 0.0
    if _music:
        _music.volume_db = silenced if _user_muted else MUSIC_DB

func _on_music_finished() -> void:
    if _user_muted or _music.stream == null:
        return
    if _phase == Phase.TITLE or _phase == Phase.LOGIN:
        _music.play()

func _set_media_paused(paused: bool) -> void:
    if _intro_video:
        _intro_video.paused = paused or _phase != Phase.INTRO
    if _title_video:
        var play_title := _phase == Phase.BOOM or _phase == Phase.TITLE or _phase == Phase.LOGIN
        _title_video.paused = paused or not play_title
    if _music:
        _music.stream_paused = paused

func _on_advanced_pressed() -> void:
    _endpoint.visible = not _endpoint.visible
    _apply_responsive_layout()

func present_login_panel() -> void:
    _open_login(false, false)

func _open_login(animated: bool, prefill := true) -> void:
    if _phase == Phase.LOGIN and _panel.visible and not animated:
        if prefill:
            _prefill_saved_fields()
        _apply_responsive_layout()
        return
    _stop_cinematic_motion()
    _phase = Phase.LOGIN
    _skip_hint.visible = false
    _prompt.visible = false
    _logo.visible = false
    _flash.modulate.a = 0.0
    _debris.emitting = false
    _spray.emitting = false
    _shake.position = Vector2.ZERO
    _flash.position = Vector2.ZERO
    if _intro_video:
        _intro_video.stop()
        _intro_video.visible = false
    if _title_video and _title_video.stream != null and not _title_video.is_playing() and DisplayServer.get_name() != "headless":
        _title_video.play()
    if _music.stream != null and not _music.playing and _phase == Phase.LOGIN and DisplayServer.get_name() != "headless":
        _music.play()
    _panel.visible = true
    if prefill:
        _prefill_saved_fields()
    _apply_responsive_layout()
    if not animated:
        return
    var left := _panel.offset_left
    var right := _panel.offset_right
    var travel := get_viewport().get_visible_rect().size.x
    _panel.offset_left = left + travel
    _panel.offset_right = right + travel
    _panel_tween = create_tween()
    _panel_tween.tween_property(_panel, "offset_left", left, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _panel_tween.parallel().tween_property(_panel, "offset_right", right, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _stop_cinematic_motion() -> void:
    if _flash_tween and _flash_tween.is_valid():
        _flash_tween.kill()
    if _logo_tween and _logo_tween.is_valid():
        _logo_tween.kill()
    if _panel_tween and _panel_tween.is_valid():
        _panel_tween.kill()
    if _intro_video and _intro_video.finished.is_connected(_on_intro_finished):
        _intro_video.finished.disconnect(_on_intro_finished)

func _prefill_saved_fields() -> void:
    var username := str(_session.get_value("session", "username", ""))
    var password := str(_session.get_value("session", "password", ""))
    var endpoint := str(_session.get_value("session", "endpoint", ""))
    if _identifier.text.is_empty() and not username.is_empty():
        _identifier.text = username
    if _password.text.is_empty() and not password.is_empty():
        _password.text = password
    if not endpoint.is_empty():
        _endpoint.text = endpoint

func _has_saved_session() -> bool:
    return not str(_session.get_value("session", "refresh_token", "")).is_empty()

func _auto_sign_in() -> void:
    var refresh := str(_session.get_value("session", "refresh_token", ""))
    if _busy or refresh.is_empty():
        return
    _prompt.text = "SETTING SAIL…"
    _auto_login(refresh)

func _auto_login(refresh: String) -> void:
    var endpoint := _endpoint.text.strip_edges()
    var base := _auth_base_url_for_endpoint(endpoint)
    if base.is_empty():
        _status.text = "Saved session needs a valid server URL."
        _open_login(false)
        return
    _pending_kind = "refresh"
    _pending_auth_endpoint = endpoint
    _set_busy(true)
    _status.text = "Signing in…"
    var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
    var error := _http.request(base + "/auth/refresh", headers, HTTPClient.METHOD_POST, JSON.stringify({"refreshToken": refresh}))
    if error != OK:
        _pending_kind = ""
        _pending_auth_endpoint = ""
        _set_busy(false)
        _status.text = "Could not reuse the saved session."
        _open_login(false)

func _load_saved_session() -> void:
    _session = _read_session()
    var refresh := str(_session.get_value("session", "refresh_token", ""))
    var password := str(_session.get_value("session", "password", ""))
    _loading_session = true
    _remember_me.button_pressed = not refresh.is_empty()
    _remember_password.button_pressed = not password.is_empty()
    _loading_session = false

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
    _http.cancel_request()
    _pending_auth_endpoint = ""
    _pending_kind = ""
    _refresh_token = ""
    _set_busy(false)
    if _adapter:
        _adapter.disconnect_from_server()
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

func _release_title_media() -> void:
    _stop_cinematic_motion()
    if _title_video:
        _title_video.paused = true
        _title_video.stop()
    if _intro_video:
        _intro_video.paused = true
        _intro_video.stop()
    if _music:
        _music.stop()
    if _boom:
        _boom.stop()
    if _debris:
        _debris.emitting = false
    if _spray:
        _spray.emitting = false

func _set_access_name(node: Control, value: String) -> void:
    if "accessibility_name" in node:
        node.accessibility_name = value

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
    if _player_button:
        _paint_mode_buttons()
    if is_inside_tree() and _logo:
        _apply_responsive_layout()

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
    if _sign_out:
        _sign_out.disabled = value
    if _player_button and is_inside_tree():
        _paint_mode_buttons()

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
    _pending_kind = "login"
    _set_busy(true)
    _status.text = "Creating account…" if _mode == "register" else "Checking credentials…"
    var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
    var error := _http.request(base + _auth_api_path(_mode), headers, HTTPClient.METHOD_POST, body)
    if error != OK:
        _pending_auth_endpoint = ""
        _pending_kind = ""
        _password.clear()
        _set_busy(false)
        _status.text = "Cannot reach the authentication service. Check server configuration."

func _on_auth_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    var kind := _pending_kind
    _pending_kind = ""
    var authenticated_endpoint := _pending_auth_endpoint
    _pending_auth_endpoint = ""
    if kind == "refresh":
        _finish_refresh(result, response_code, body, authenticated_endpoint)
        return
    var typed_password := _password.text
    _password.clear()
    _set_busy(false)
    if result != HTTPRequest.RESULT_SUCCESS:
        _status.text = "Cannot contact authentication server. Check WSS address and connection."
        if _phase != Phase.LOGIN:
            _open_login(false, false)
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
        if _phase != Phase.LOGIN:
            _open_login(false, false)
        return
    if not (decoded is Dictionary):
        _status.text = "Unexpected authentication response from server."
        if _phase != Phase.LOGIN:
            _open_login(false, false)
        return
    var token = decoded.get("accessToken", "")
    if not (token is String) or token.is_empty():
        _status.text = "Server returned no valid player session."
        if _phase != Phase.LOGIN:
            _open_login(false, false)
        return
    var refresh = decoded.get("refreshToken", "")
    _refresh_token = refresh if refresh is String else ""

    if _mode == "admin":
        if decoded.get("role", "") != "admin":
            _status.text = "Administrator access denied."
            return
        # No admin gameplay or privileged actions are exposed by this screen.
        # An admin refresh token is never stored. A password is stored only when Remember password is on.
        _store_secrets(authenticated_endpoint, "", typed_password)
        _status.text = "Administrator authenticated. Management console is not enabled in this build."
        return

    _store_secrets(authenticated_endpoint, _refresh_token, typed_password)
    _status.text = "Authenticated. Connecting to game server…"
    if authenticated_endpoint.is_empty():
        _status.text = "Authentication response had no matching server. Sign in again."
        return
    _adapter.configure(authenticated_endpoint, token)
    _adapter.connect_to_server()

func _finish_refresh(result: int, response_code: int, body: PackedByteArray, endpoint: String) -> void:
    _set_busy(false)
    var decoded = JSON.parse_string(body.get_string_from_utf8())
    var access = ""
    var refresh = ""
    if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and decoded is Dictionary:
        var raw_access = decoded.get("accessToken", "")
        var raw_refresh = decoded.get("refreshToken", "")
        if raw_access is String:
            access = raw_access
        if raw_refresh is String:
            refresh = raw_refresh
    if not access.is_empty():
        _refresh_token = refresh if not refresh.is_empty() else str(_session.get_value("session", "refresh_token", ""))
        if _remember_me.button_pressed and not _refresh_token.is_empty():
            _session.set_value("session", "refresh_token", _refresh_token)
            if not endpoint.is_empty():
                _session.set_value("session", "endpoint", endpoint)
            _write_session()
        _status.text = "Authenticated. Connecting to game server…"
        _adapter.configure(endpoint, access)
        _adapter.connect_to_server()
        return
    _drop_refresh_token()
    _status.text = "Saved session expired. Sign in again."
    _open_login(false)

func _on_status_changed(status: String) -> void:
    _status.text = status

func _on_message(message: Dictionary) -> void:
    if message.get("type", "") == "auth_ok":
        _status.text = "Ready · player authenticated by server"
        if bool(ProjectSettings.get_setting("application/config/internal_gameplay_handoff", true)):
            _launch_internal_gameplay(message)
        elif _phase != Phase.LOGIN:
            _open_login(false, false)

func show_signed_out(reason: String) -> void:
    _status.text = "Session ended (%s). Sign in again." % reason
    _open_login(false, false)

func _on_auth_failed(reason: String) -> void:
    _status.text = "Sign-in rejected (%s). Sign in again." % reason
    if _phase != Phase.LOGIN:
        _open_login(false, false)

func _launch_internal_gameplay(message: Dictionary) -> void:
    var user_id = message.get("userId")
    if not (user_id is String) or user_id.is_empty() or not _adapter._attempt_active or not _adapter._auth_sent:
        return
    if _adapter._url.is_empty() or _adapter._token.is_empty():
        return
    _release_title_media()
    var scene_path := "res://gameplay/ashore/washed_ashore.tscn"
    if not _opening_battle_done():
        scene_path = "res://gameplay/opening_battle.tscn"
    var gameplay = load(scene_path).instantiate()
    gameplay.begin_authenticated_session(_adapter._url, _adapter._token, _refresh_token)
    get_tree().root.add_child(gameplay)
    get_tree().current_scene = gameplay
    queue_free()

func _opening_battle_done() -> bool:
    var cfg := ConfigFile.new()
    if cfg.load("user://opening_battle.cfg") != OK:
        return false
    return bool(cfg.get_value("opening", "completed", false))
