extends RefCounted
## Building visuals for the outpost, composed from the CC0 library pieces the
## island already ships (Hunyuan hut, Poly Haven crates/barrels/stone, the
## procedural plank pile and rope, driftwood). No new meshes, no glow.

const Art := preload("res://gameplay/opening/opening_art.gd")
const HUT := preload("res://assets/ashore/library/hut_hy3d/hut_hy3d.glb")
const FIRE_PIT := preload("res://assets/ashore/library/stone_fire_pit/stone_fire_pit.glb")
const STONE := preload("res://assets/ashore/library/stone_01/stone_01.glb")
const LOG := preload("res://assets/ashore/library/log_dead_trunk_02/log_dead_trunk_02.glb")
const DIRT_ALBEDO := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_diff_1k.jpg")
const DIRT_NORMAL := preload("res://assets/external/polyhaven/coast_sand_rocks_02/coast_sand_rocks_02_nor_gl_1k.jpg")

static var _dirt_mat: StandardMaterial3D
static var _rope_mat: StandardMaterial3D

## ground: Callable(x, z) -> float world height.
var ground: Callable


func _piece(parent: Node3D, scene: PackedScene, local: Vector3, yaw: float, height: float) -> Node3D:
	var n := Art.spawn(scene)
	parent.add_child(n)
	n.rotation_degrees.y = yaw
	Art.fit_height(n, height)
	n.position = local
	_settle(n)
	return n


## Drop a piece onto the terrain under its own xz (parent may be scaled).
func _settle(n: Node3D) -> void:
	if not ground.is_valid() or not n.is_inside_tree():
		return
	var gp := n.global_position
	var box := Art.world_aabb(n)
	var floor_y := float(ground.call(gp.x, gp.z))
	n.global_position.y += floor_y - box.position.y - 0.04


## A driftwood trunk stood upright (longest axis to +Y) as a post or stake.
func post(parent: Node3D, local: Vector3, height: float, lean: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = local
	var n := Art.spawn(Art.DRIFT_TRUNK)
	holder.add_child(n)
	var box := Art.world_aabb(n)
	if box.size.x >= box.size.y and box.size.x >= box.size.z:
		n.rotation_degrees.z = 90
	elif box.size.z >= box.size.y:
		n.rotation_degrees.x = 90
	Art.fit_height(n, height)
	var b2 := Art.world_aabb(n)
	n.position -= (b2.get_center() - holder.global_position) * Vector3(1, 0, 1)
	holder.rotation_degrees.z = lean
	_settle(holder)
	return holder


func label(parent: Node3D, text: String, y: float, font: Font) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.font = font
	lab.font_size = 64
	lab.pixel_size = 0.0008
	lab.fixed_size = true
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.outline_size = 10
	lab.outline_modulate = Color(0.08, 0.06, 0.04, 0.85)
	lab.modulate = Color(0.98, 0.93, 0.8)
	lab.position = Vector3(0, y, 0)
	parent.add_child(lab)
	return lab


func _dirt() -> StandardMaterial3D:
	if _dirt_mat == null:
		_dirt_mat = StandardMaterial3D.new()
		_dirt_mat.albedo_texture = DIRT_ALBEDO
		_dirt_mat.normal_enabled = true
		_dirt_mat.normal_texture = DIRT_NORMAL
		_dirt_mat.albedo_color = Color(0.62, 0.5, 0.38)
		_dirt_mat.roughness = 0.95
		_dirt_mat.vertex_color_use_as_albedo = false
		_dirt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_dirt_mat.uv1_scale = Vector3(0.45, 0.45, 1)
		_dirt_mat.uv1_world_triplanar = true
		_dirt_mat.uv1_triplanar = true
	return _dirt_mat


## Trampled-earth patch draped over the terrain, soft at the edge.
func dirt_patch(parent: Node3D, radius: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var segs := 24
	var c := parent.global_position
	var pts: Array = []
	for ri in rings + 1:
		var row: Array = []
		for si in segs:
			var rr := radius * float(ri) / rings
			var a := TAU * si / segs
			var wob := 1.0 + 0.12 * sin(a * 3.0 + c.x) if ri == rings else 1.0
			var wx := c.x + cos(a) * rr * wob
			var wz := c.z + sin(a) * rr * wob
			var wy := float(ground.call(wx, wz)) + 0.05 if ground.is_valid() else c.y
			row.append([Vector3(wx, wy, wz) - c, 1.0 if ri < rings - 1 else (0.55 if ri == rings - 1 else 0.0)])
		pts.append(row)
	var col := func(alpha: float) -> Color: return Color(1, 1, 1, alpha)
	for ri in rings:
		for si in segs:
			var a0: Array = pts[ri][si]
			var a1: Array = pts[ri][(si + 1) % segs]
			var b0: Array = pts[ri + 1][si]
			var b1: Array = pts[ri + 1][(si + 1) % segs]
			for v in [a0, b0, b1, a0, b1, a1]:
				st.set_color(col.call(float(v[1])))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	var mesh := MeshInstance3D.new()
	mesh.name = "Dirt"
	mesh.mesh = st.commit()
	var mat := _dirt().duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	# Undo the site's yaw so the draped mesh lines up with the world terrain.
	mesh.global_transform = Transform3D(Basis(), c)
	return mesh


func _rope_between(parent: Node3D, a: Vector3, b: Vector3) -> void:
	if _rope_mat == null:
		_rope_mat = StandardMaterial3D.new()
		_rope_mat.albedo_color = Color(0.36, 0.29, 0.2)
		_rope_mat.roughness = 1.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.016
	cyl.bottom_radius = 0.016
	cyl.radial_segments = 6
	cyl.height = a.distance_to(b)
	var m := MeshInstance3D.new()
	m.mesh = cyl
	m.material_override = _rope_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	var mid := (a + b) * 0.5 - Vector3.UP * 0.06
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	m.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), mid)


## Empty plot: cleared dirt, four stakes and a rope boundary.
func plot_marker(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Marker"
	parent.add_child(root)
	dirt_patch(root, 3.4)
	var tops: Array = []
	var corners := [Vector3(-2.3, 0, -2.3), Vector3(2.3, 0, -2.3), Vector3(2.3, 0, 2.3), Vector3(-2.3, 0, 2.3)]
	for k in corners.size():
		var stake := post(root, corners[k], 1.05, (k % 2) * 3.0 - 1.5)
		tops.append(stake.global_position + Vector3.UP * 0.85)
	for k in tops.size():
		_rope_between(root, tops[k], tops[(k + 1) % tops.size()])
	_piece(root, Art.PLANKS, Vector3(1.2, 0, 2.9), 25, 0.3)
	return root


## Scaffold of lashed driftwood poles shown while a building rises.
func scaffold(parent: Node3D, r: float, h: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Scaffold"
	parent.add_child(root)
	for c in [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]:
		post(root, c, h, 0.0)
	_piece(root, Art.PLANKS, Vector3(r * 0.4, 0, r + 0.8), 20, 0.45)
	_piece(root, Art.ROPE, Vector3(-r - 0.5, 0, r * 0.3), 0, 0.25)
	return root


## The finished building for `id` at `level` (1..3). Higher levels add props
## and grow the footprint a little.
func building(parent: Node3D, id: String, level: int, wrecked: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	parent.add_child(root)
	if id != "dock":
		dirt_patch(root, 4.2 if id != "camp" else 5.5)
	var s := 1.0 + 0.1 * (level - 1)
	match id:
		"camp":
			_piece(root, HUT, Vector3(0, 0, 0), 0, 3.0 * s)
			_piece(root, FIRE_PIT, Vector3(1.6, 0, 3.0), 0, 0.5)
			_piece(root, Art.CRATE_A, Vector3(-2.2, 0, 1.6), 25, 0.7)
			_piece(root, Art.BARRELS, Vector3(2.6, 0, 0.6), 0, 1.0)
			if level >= 2:
				_piece(root, HUT, Vector3(-4.2, 0, -1.0), 35, 2.4)
				_piece(root, Art.CHEST, Vector3(-1.0, 0, 2.6), 10, 0.55)
			if level >= 3:
				_piece(root, HUT, Vector3(4.4, 0, -1.4), -30, 2.6)
		"mill":
			_piece(root, HUT, Vector3(0, 0, 0), 0, 2.7 * s)
			_piece(root, Art.PLANKS, Vector3(2.4, 0, 1.4), 15, 0.6)
			_piece(root, LOG, Vector3(-2.3, 0, 1.8), 80, 0.6)
			_piece(root, Art.DRIFT_TRUNK, Vector3(0.4, 0, 2.8), 5, 0.5)
			if level >= 2:
				_piece(root, Art.PLANKS, Vector3(3.0, 0, -0.6), 60, 0.7)
			if level >= 3:
				_piece(root, LOG, Vector3(-3.0, 0, -0.8), 10, 0.7)
		"dock":
			# A short jetty: plank deck on driftwood piles, pointing seaward (-z).
			for i in 4:
				_piece(root, Art.PLANKS, Vector3(0, 0, -i * 1.5), 90, 0.35)
				post(root, Vector3(-0.9, 0, -i * 1.5), 1.2)
				post(root, Vector3(0.9, 0, -i * 1.5), 1.2)
			_piece(root, Art.BARRELS, Vector3(1.8, 0, 1.2), 0, 0.9)
			_piece(root, Art.ROPE, Vector3(-1.4, 0, 1.0), 0, 0.3)
			if level >= 2:
				_piece(root, Art.CRATE_B, Vector3(-2.2, 0, 1.8), 30, 0.6)
				_piece(root, Art.TORN_SAIL, Vector3(2.6, 0, -1.0), 0, 1.0)
			if level >= 3:
				_piece(root, Art.WINE_BARREL, Vector3(1.0, 0, 2.4), 0, 0.7)
		"forge":
			_piece(root, FIRE_PIT, Vector3(0, 0, 0.6), 0, 0.8 * s)
			for i in 5:
				var a := PI + i * 0.5
				_piece(root, STONE, Vector3(cos(a) * 1.4, 0, 0.6 + sin(a) * 1.4), i * 61.0, 0.7)
			_piece(root, Art.CANNON, Vector3(2.2, 0, 1.4), 70, 0.8)
			_piece(root, Art.WINE_BARREL, Vector3(-2.0, 0, 1.6), 0, 0.8)
			_piece(root, HUT, Vector3(0, 0, -2.2), 0, 2.2 * s)
			if level >= 2:
				_piece(root, Art.CRATE_A, Vector3(2.6, 0, -0.6), 15, 0.6)
			if level >= 3:
				_piece(root, Art.COAST_ROCKS_01, Vector3(-2.6, 0, -0.8), 0, 0.9)
		"barracks":
			_piece(root, HUT, Vector3(-1.8, 0, 0), 10, 2.8 * s)
			_piece(root, HUT, Vector3(1.9, 0, -0.3), -12, 2.6 * s)
			_piece(root, Art.CRATE_A, Vector3(0, 0, 2.4), 0, 0.6)
			_piece(root, Art.CRATE_B, Vector3(0.7, 0, 2.6), 40, 0.5)
			post(root, Vector3(3.4, 0, 2.2), 2.2)
			if level >= 3:
				_piece(root, Art.CHEST, Vector3(-1.0, 0, 2.8), 0, 0.5)
		"watchtower":
			var h := 5.0 + level
			for c in [Vector3(-0.9, 0, -0.9), Vector3(0.9, 0, -0.9), Vector3(0.9, 0, 0.9), Vector3(-0.9, 0, 0.9)]:
				post(root, c, h)
			var deck := Art.spawn(Art.PLANKS)
			root.add_child(deck)
			Art.fit_height(deck, 0.35)
			deck.position = Vector3(0, h - 0.6, 0)
			var deck_top := Node3D.new()
			deck_top.name = "Lookout"
			deck_top.position = Vector3(0, h, 0)
			root.add_child(deck_top)
			if level >= 2:
				var sail := Art.spawn(Art.TORN_SAIL)
				root.add_child(sail)
				Art.fit_height(sail, 1.0)
				sail.position = Vector3(0, h + 0.2, 0)
		"training_post":
			post(root, Vector3(-0.9, 0, 0), 1.7, 0.0)
			post(root, Vector3(0.9, 0, 0), 1.7, 0.0)
			var bar := post(root, Vector3(-0.9, 1.6, 0), 1.8, 0.0)
			bar.rotation_degrees.z = -90.0
			_piece(root, Art.CRATE_A, Vector3(1.6, 0, 0.9), 20, 0.45)
			_piece(root, Art.BARRELS, Vector3(-1.7, 0, 0.8), 0, 0.7)
		"palisade":
			# Spans the whole beach approach (raiders must breach it).
			var n := 20
			for i in n:
				var x := (i - (n - 1) * 0.5) * 0.72
				var tall := 1.6 + 0.2 * level + (0.18 if i % 2 == 0 else 0.0)
				var lean := (i % 3 - 1) * 2.5
				if wrecked and i % 3 != 0:
					tall *= 0.35
					lean = (i % 2 * 2 - 1) * 35.0
				var stake := post(root, Vector3(x, 0, absf(x) * 0.04), tall, lean)
				stake.scale = Vector3(0.6, 1.0, 0.6)
	return root
