extends SceneTree

const SAIL_SCRIPT := preload("res://scripts/realistic_coastal_slice.gd")

func _init() -> void:
	var mask := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	for y in range(8, 20):
		for x in range(8, 24):
			mask.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
	var dark := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.65, 0.85, 1.0, 1.0)) # bright sky everywhere else
	for y in range(8, 20):
		for x in range(8, 24):
			dark.set_pixel(x, y, Color(0.01, 0.01, 0.01, 1.0)) # dark sail output
	var dark_result: Dictionary = SAIL_SCRIPT.evaluate_sail_pixel_mask(dark, mask)
	var red: bool = dark_result["mask_pixels"] >= 150 and dark_result["lit_fraction"] < 0.45
	var lit := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	lit.fill(Color(0.65, 0.85, 1.0, 1.0))
	for y in range(8, 20):
		for x in range(8, 24):
			lit.set_pixel(x, y, Color(0.82, 0.78, 0.62, 1.0))
	var green_result: Dictionary = SAIL_SCRIPT.evaluate_sail_pixel_mask(lit, mask)
	var green: bool = green_result["mask_pixels"] >= 150 and green_result["lit_fraction"] >= 0.45
	var empty_result: Dictionary = SAIL_SCRIPT.evaluate_sail_pixel_mask(lit, Image.create(32, 24, false, Image.FORMAT_RGBA8))
	var offscreen: bool = empty_result["mask_pixels"] == 0 and empty_result["lit_fraction"] == 0.0
	var ok: bool = red and green and offscreen
	print("Sail pixel mask regression: %s (red=%s green=%s offscreen=%s dark=%s green_result=%s)" % ["PASS" if ok else "FAIL", red, green, offscreen, dark_result, green_result])
	quit(0 if ok else 1)
