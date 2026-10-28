extends SceneTree

# Unit checks for the register/login helpers, joystick maths, token sizing and scene wiring.
const Auth = preload("res://scripts/auth_client.gd")
const Joystick = preload("res://scripts/touch_joystick.gd")

var _failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_check_base_url()
	_check_validation()
	_check_requests_and_messages()
	_check_joystick_maths()
	_check_joystick_input()
	_check_scenes()
	print("AUTH/INPUT checks: %s failures" % _failures)
	quit(1 if _failures else 0)

func _check_base_url() -> void:
	check(Auth.api_base_from_ws("ws://127.0.0.1:3000/ws") == "http://127.0.0.1:3000", "loopback ws maps to http with port")
	check(Auth.api_base_from_ws("wss://game.example.com/ws") == "https://game.example.com", "wss maps to https")
	check(Auth.api_base_from_ws("wss://game.example.com") == "https://game.example.com", "endpoint without path")
	check(Auth.api_base_from_ws("ws://localhost:3000/ws?x=1") == "http://localhost:3000", "query string removed")
	check(Auth.api_base_from_ws("https://example.com/ws") == "", "non-websocket scheme rejected")
	check(Auth.api_base_from_ws("") == "", "empty endpoint rejected")

func _check_validation() -> void:
	check(Auth.validate("register", "ab", "a@b.co", "Correct-Horse-9x") != "", "short username rejected")
	check(Auth.validate("register", "bad name", "a@b.co", "Correct-Horse-9x") != "", "space in username rejected")
	check(Auth.validate("register", "good_user", "not-an-email", "Correct-Horse-9x") != "", "malformed email rejected")
	check(Auth.validate("register", "good_user", "a@b.co", "short") != "", "password under 12 characters rejected")
	check(Auth.validate("register", "good_user", "a@b.co", "x".repeat(129)) != "", "password over 128 characters rejected")
	check(Auth.validate("register", "good_user", "a@b.co", "Correct-Horse-9x") == "", "valid registration accepted")
	check(Auth.validate("login", "good_user", "", "anything") == "", "login accepts any non-empty password")
	check(Auth.validate("login", "ab", "", "pw") != "", "login identifier under 3 characters rejected")
	check(Auth.validate("login", "good_user", "", "") != "", "login requires a password")

func _check_requests_and_messages() -> void:
	var register := Auth.build_request("register", " good_user ", " a@b.co ", "Correct-Horse-9x")
	check(register["path"] == "/auth/register", "register path")
	check(register["body"] == {"username": "good_user", "email": "a@b.co", "password": "Correct-Horse-9x"}, "register body trimmed")
	var login := Auth.build_request("login", "good_user", "", "pw")
	check(login["path"] == "/auth/login", "login path")
	check(login["body"] == {"identifier": "good_user", "password": "pw"}, "login body uses identifier")
	check(Auth.message_for_result("login", 0, 200) == "", "200 is success")
	check(Auth.message_for_result("register", 0, 201) == "", "201 is success")
	check(Auth.message_for_result("login", 0, 401) == "Invalid username or password", "401 message")
	check(Auth.message_for_result("register", 0, 409) == "That username or email is already registered", "409 message")
	check(Auth.message_for_result("login", 0, 429).begins_with("Too many attempts"), "429 message")
	check(Auth.message_for_result("login", 0, 500) == "Server error (500). Try again", "5xx message")
	check(Auth.message_for_result("login", 4, 0).begins_with("Server unreachable"), "transport failure message")
	check(Auth.token_from_body("{\"accessToken\":\"abc\"}".to_utf8_buffer()) == "abc", "token parsed from body")
	check(Auth.token_from_body("{}".to_utf8_buffer()) == "", "missing token yields empty string")
	check(Auth.token_from_body("not json".to_utf8_buffer()) == "", "malformed body yields empty string")

func _check_joystick_maths() -> void:
	var radius := 68.0
	check(Joystick.stick_vector(Vector2.ZERO, radius) == Vector2.ZERO, "centre gives zero")
	check(Joystick.stick_vector(Vector2(radius * 0.05, 0.0), radius) == Vector2.ZERO, "inside dead zone gives zero")
	var rim := Joystick.stick_vector(Vector2(radius, 0.0), radius)
	check(is_equal_approx(rim.x, 1.0) and is_equal_approx(rim.y, 0.0), "rim gives unit vector")
	var beyond := Joystick.stick_vector(Vector2(radius * 3.0, 0.0), radius)
	check(is_equal_approx(beyond.length(), 1.0), "beyond the rim clamps to length 1")
	var diagonal := Joystick.stick_vector(Vector2(radius, radius), radius)
	check(is_equal_approx(diagonal.length(), 1.0) and diagonal.x > 0.0 and diagonal.y > 0.0, "diagonal is normalised")
	var half := Joystick.stick_vector(Vector2(radius * 0.5, 0.0), radius)
	check(half.x > 0.0 and half.x < 1.0 and half.y == 0.0, "half deflection is between zero and one")
	check(Joystick.stick_vector(Vector2(-radius, 0.0), radius).x < -0.99, "left deflection is negative")
	check(Joystick.stick_vector(Vector2(radius, 0.0), 0.0) == Vector2.ZERO, "zero radius is safe")
	var worst := 0.0
	for i in range(200):
		var offset := Vector2(randf_range(-300.0, 300.0), randf_range(-300.0, 300.0))
		worst = maxf(worst, Joystick.stick_vector(offset, radius).length())
	check(worst <= 1.0 + 1e-5, "no sample exceeds unit length")
	check(is_equal_approx(Joystick.radius_for_viewport(Vector2(1920.0, 1080.0)), 82.0), "large landscape radius capped at max")
	check(is_equal_approx(Joystick.radius_for_viewport(Vector2(360.0, 640.0)), 48.0), "small phone radius at minimum")
	check(is_equal_approx(Joystick.radius_for_viewport(Vector2(700.0, 900.0)), 68.0), "compact width caps radius")
	check(is_equal_approx(Joystick.margin_for_viewport(Vector2(1920.0, 1080.0)), 44.0), "large margin capped")
	check(is_equal_approx(Joystick.margin_for_viewport(Vector2(360.0, 640.0)), 18.0), "small margin at minimum")

func _check_joystick_input() -> void:
	var stick := IslesTouchJoystick.new()
	stick.size = Vector2(136.0, 136.0)
	root.add_child(stick)
	var emitted: Array = []
	stick.vector_changed.connect(func(vector: Vector2) -> void: emitted.append(vector))
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(68.0, 68.0)
	stick._gui_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(68.0 + 60.0, 68.0)
	stick._gui_input(drag)
	check(emitted.size() >= 2 and emitted[emitted.size() - 1].x > 0.5, "dragging right emits a positive x vector")
	var other := InputEventScreenTouch.new()
	other.index = 1
	other.pressed = true
	other.position = Vector2(10.0, 10.0)
	var before := emitted.size()
	stick._gui_input(other)
	check(emitted.size() == before, "a second finger does not take over the stick")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	stick._gui_input(release)
	check(emitted[emitted.size() - 1] == Vector2.ZERO, "release returns the stick to zero")
	stick.queue_free()

func _check_scenes() -> void:
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	check(boot.get_node("Panel/Margin/Content/Password").secret, "password entry is masked")
	check(not boot.get_node("Panel/Margin/Content/Email").visible, "email hidden in login mode")
	check(boot.get_node("Panel/Margin/Content/Submit").pressed.is_connected(boot._on_submit), "submit is wired")
	check(boot.get_node("Panel/Margin/Content/Title").text == "ISLES OF MYTHOS", "title reads exactly ISLES OF MYTHOS")
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	check(world.get_node("Joystick") is IslesTouchJoystick, "world joystick uses the touch joystick script")
	check(world.get_node("StatusChip") is Label, "world status chip is a label")
	world.queue_free()
	boot.queue_free()
