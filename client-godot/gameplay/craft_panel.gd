# Crafting HUD. Presentation only: the server (WebSocket `craft` action,
# server/src/app.ts + crafting.ts) decides whether a craft succeeds and what the
# inventory becomes. The client displays the server-reported inventory, sends
# one `craft` intent at a time and never mutates inventory locally.
extends VBoxContainer

signal craft_succeeded(recipe_id: String)

# Display mirror of server RECIPE_CATALOGUE (server/src/recipe.ts). There is no
# recipe-list message, so this is a presentation hint only; the server validates
# every recipeId and replies RECIPE_NOT_FOUND for anything it does not accept.
const RECIPES := [
	{"id": "tool.wooden-club", "name": "Wooden Club", "ingredients": [["resource.wood", 8]]},
	{"id": "tool.stone-axe", "name": "Stone Axe", "ingredients": [["resource.wood", 6], ["resource.stone", 4]]},
	{"id": "tool.stone-pickaxe", "name": "Stone Pickaxe", "ingredients": [["resource.wood", 6], ["resource.stone", 5]]},
	{"id": "structure.campfire", "name": "Campfire", "ingredients": [["resource.wood", 8], ["resource.stone", 4]]},
	{"id": "structure.wooden-wall", "name": "Wooden Wall", "ingredients": [["resource.wood", 10]]},
	{"id": "consumable.herb-bandage", "name": "Herb Bandage", "ingredients": [["resource.herb", 3]]},
]
# Error codes the server craft handler returns without a requestId (app.ts).
const CRAFT_ERROR_TEXT := {
	"RECIPE_NOT_FOUND": "Server does not know that recipe",
	"INSUFFICIENT_INVENTORY": "Server: not enough materials",
	"INVENTORY_LIMIT": "Server: inventory is full",
}

# (recipe_id: String) -> request_id String ("" when the command could not be sent).
var craft_sender: Callable
var _inventory: Dictionary = {}
var _rows: Dictionary = {}
var _in_flight_request := ""
var _in_flight_recipe := ""
var _title: Label
var _message: Label

func _ready() -> void:
	_title = Label.new()
	_title.text = "Crafting"
	add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)
	for recipe in RECIPES:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button := Button.new()
		button.text = "Craft"
		button.custom_minimum_size = Vector2(96, 48)
		button.pressed.connect(craft.bind(recipe["id"]))
		line.add_child(label)
		line.add_child(button)
		add_child(line)
		_rows[recipe["id"]] = {"label": label, "button": button, "recipe": recipe}
	_render()

func is_busy() -> bool:
	return not _in_flight_request.is_empty()

func craft(recipe_id: String) -> bool:
	if is_busy() or not _rows.has(recipe_id) or not craft_sender.is_valid():
		return false
	var request_id = craft_sender.call(recipe_id)
	if not (request_id is String) or request_id.is_empty():
		_set_message("Command window unavailable")
		return false
	_in_flight_request = request_id
	_in_flight_recipe = recipe_id
	_set_message("Awaiting server craft ACK")
	_render()
	return true

## Server-reported inventory (player_state / ACK `state.inventory`). Ignored if malformed.
func set_inventory(inventory: Variant) -> void:
	if not (inventory is Dictionary):
		return
	_inventory = {}
	for key in inventory:
		var amount = inventory[key]
		if key is String and (amount is int or amount is float):
			_inventory[key] = int(amount)
	_render()

func inventory_count(item_id: String) -> int:
	return int(_inventory.get(item_id, 0))

## `craft_result` ACK. Only the correlated in-flight request is accepted.
func on_craft_ack(request_id: String, message: Dictionary) -> void:
	if request_id.is_empty() or request_id != _in_flight_request:
		return
	var recipe_id := _in_flight_recipe
	if message.get("recipeId") != recipe_id:
		return
	var state = message.get("state")
	if not (state is Dictionary) or not (state.get("inventory") is Dictionary):
		return
	_clear_flight()
	set_inventory(state["inventory"])
	_set_message("Crafted %s" % str((_rows[recipe_id]["recipe"] as Dictionary)["name"]))
	craft_succeeded.emit(recipe_id)

## Server error (carries no requestId). Attributed to the in-flight craft only for
## the codes the craft handler itself returns; local inventory is left untouched.
func on_server_error(code: String) -> void:
	if not is_busy():
		return
	if CRAFT_ERROR_TEXT.has(code):
		_clear_flight()
		_set_message(CRAFT_ERROR_TEXT[code])
		_render()
	else:
		# Ambiguous: keep the request pending until the transport reports its outcome.
		_set_message("Server error: %s" % code)

func on_outcome_unknown(request_id: String) -> void:
	if request_id.is_empty() or request_id != _in_flight_request:
		return
	_clear_flight()
	_set_message("Craft outcome unknown; check inventory before retrying")
	_render()

func message_text() -> String:
	return "" if _message == null else _message.text

func row_text(recipe_id: String) -> String:
	var row = _rows.get(recipe_id)
	return "" if row == null else (row["label"] as Label).text

func craft_enabled(recipe_id: String) -> bool:
	var row = _rows.get(recipe_id)
	return row != null and not (row["button"] as Button).disabled

func _clear_flight() -> void:
	_in_flight_request = ""
	_in_flight_recipe = ""

func _set_message(text: String) -> void:
	if _message != null:
		_message.text = text

func _render() -> void:
	for recipe_id in _rows:
		var row: Dictionary = _rows[recipe_id]
		var parts: Array[String] = []
		for ingredient in (row["recipe"] as Dictionary)["ingredients"]:
			parts.append("%s %d/%d" % [str(ingredient[0]).trim_prefix("resource."), inventory_count(ingredient[0]), ingredient[1]])
		(row["label"] as Label).text = "%s: %s" % [(row["recipe"] as Dictionary)["name"], ", ".join(parts)]
		(row["button"] as Button).disabled = is_busy()
