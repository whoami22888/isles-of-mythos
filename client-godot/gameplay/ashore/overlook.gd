extends Node
## Cliff overlook (DIGEST beat 16, World Reveal). A guided climb up an old
## Tideborn trail (cairns every few metres) to the ridge above the camp, then
## a crane-up reveal: the bay and the leviathan wreck offshore, survivor-camp
## smoke on a near island, Tideborn ruins, and the Leviathan's tempest on the
## horizon. The trail is a real walkable route found on the terrain (every
## 1 m step under the slope limit); within a metre of it the movement slope
## check is waived, so the cliff slope limit never blocks the trail while it
## still blocks every other cliff face. The castaway walks on the real terrain.
## Mobile budget: ~20 cairns from one 1K stone, 3 distant island meshes
## (32x32 heightfields), 6 pillars, 2 smoke emitters (24 quads each), 1 cone.

const ASHORE_STONE := preload("res://assets/ashore/library/stone_01/stone_01.glb")
const Art := preload("res://gameplay/opening/opening_art.gd")
const PALM := preload("res://assets/generated/palm_v2/palm_v2_mobile.glb")
## Reveal view: from the lookout south-west over open water (the slice's
## ridge rocks sit east of the lookout and stay out of frame).
const LOOK_FAR := Vector3(-150.0, 2.0, -200.0)
const TRAIL_HALF_WIDTH := 1.0
const TOP_RADIUS := 2.4
const REVEAL_SECONDS := 9.0
## Route found by a slope-limited search on the island heightfield (1 m grid,
## rise/run <= 0.62), from the beach camp to the ridge lookout at about 8 m.
const ROUTE := [
	Vector2(-8, 7), Vector2(-9, 8), Vector2(-10, 9), Vector2(-11, 10), Vector2(-11, 11), Vector2(-11, 12),
	Vector2(-12, 13), Vector2(-12, 14), Vector2(-12, 15), Vector2(-12, 16), Vector2(-12, 17), Vector2(-12, 18),
	Vector2(-11, 19), Vector2(-10, 20), Vector2(-9, 21), Vector2(-8, 22), Vector2(-7, 23), Vector2(-6, 23),
	Vector2(-5, 23), Vector2(-4, 23), Vector2(-3, 23), Vector2(-2, 23), Vector2(-1, 23), Vector2(0, 23),
	Vector2(1, 23), Vector2(2, 24), Vector2(3, 25), Vector2(4, 25), Vector2(5, 25), Vector2(6, 25),
	Vector2(7, 25), Vector2(8, 25), Vector2(9, 25), Vector2(10, 25), Vector2(11, 25), Vector2(10, 24),
	Vector2(11, 23), Vector2(10, 23), Vector2(9, 23), Vector2(8, 23), Vector2(7, 23), Vector2(6, 23),
	Vector2(5, 23), Vector2(4, 23), Vector2(3, 22), Vector2(2, 21), Vector2(1, 20), Vector2(0, 19),
	Vector2(-1, 18),
]

var host: Node3D
var active := false
var revealed := false
var progress := 0
var _pts: Array[Vector3] = []
var _box := Rect2()
var _ready_pts := false
var _vista: Node3D
var _cairns: Node3D
var _far_before := 420.0
var _fog_end := -1.0
var _hidden: Array[Node3D] = []


func setup() -> void:
	# Heights straight from the terrain before any override exists.
	_pts.clear()
	for p in ROUTE:
		var v: Vector2 = p
		_pts.append(Vector3(v.x, host._terrain_y(v.x, v.y), v.y))
	var minp := Vector2(1e9, 1e9)
	var maxp := Vector2(-1e9, -1e9)
	for p in _pts:
		minp = minp.min(Vector2(p.x, p.z))
		maxp = maxp.max(Vector2(p.x, p.z))
	_box = Rect2(minp - Vector2.ONE * 2.0, maxp - minp + Vector2.ONE * 4.0)
	_ready_pts = true
	_build_cairns()
	_build_vista()


## Smoothed trail height at (x, z), or NAN when off the trail.
func trail_y(x: float, z: float) -> float:
	if not _ready_pts or not _box.has_point(Vector2(x, z)):
		return NAN
	var best := TRAIL_HALF_WIDTH
	var y := NAN
	var q := Vector2(x, z)
	for i in _pts.size() - 1:
		var a := Vector2(_pts[i].x, _pts[i].z)
		var b := Vector2(_pts[i + 1].x, _pts[i + 1].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < best:
			best = d
			y = lerpf(_pts[i].y, _pts[i + 1].y, t)
	return y


func on_trail(x: float, z: float) -> bool:
	return not is_nan(trail_y(x, z))


func begin_climb() -> void:
	active = true
	progress = 0
	if _cairns:
		_cairns.visible = true


func top() -> Vector3:
	return _pts[_pts.size() - 1]


func at_top() -> bool:
	return host._step == "climb" and host._flat(host._player.global_position, top()) < TOP_RADIUS


## Pointer target: a few points ahead of the nearest route point.
func point() -> Vector3:
	if _cairns and not _cairns.visible:
		_cairns.visible = true
	var p: Vector3 = host._player.global_position
	var best := 0
	var bd := 1e9
	for i in range(progress, mini(progress + 12, _pts.size())):
		var d := Vector2(p.x - _pts[i].x, p.z - _pts[i].z).length()
		if d < bd:
			bd = d
			best = i
	if bd < 2.0:
		progress = maxi(progress, best)
	return _pts[mini(progress + 2, _pts.size() - 1)]


func metres_left() -> float:
	var m: float = host._flat(host._player.global_position, _pts[mini(progress, _pts.size() - 1)])
	for i in range(progress, _pts.size() - 1):
		m += Vector2(_pts[i + 1].x - _pts[i].x, _pts[i + 1].z - _pts[i].z).length()
	return m


func begin_reveal() -> void:
	revealed = true
	active = false
	_vista.visible = true
	_far_before = host._camera.far
	host._camera.far = 900.0
	var env: Environment = host._env
	if env:
		_fog_end = env.fog_depth_end
		env.fog_depth_end = 650.0
	host._play("res://assets/opening/audio/ocean.ogg", -8.0, 0.8)
	_clear_view()


## Ridge-top slice rocks right in front of the lookout would fill the reveal
## frame; hide those (only for the cinematic) so the view is open water.
func _clear_view() -> void:
	_hidden.clear()
	var slice: Node3D = host._slice
	if slice == null:
		return
	var pl: Vector3 = host._player.global_position
	var fwd := Vector3(LOOK_FAR.x - pl.x, 0, LOOK_FAR.z - pl.z).normalized()
	# Lower the grassy humps ahead of the lookout (terrain shader, render only).
	var terrain := slice.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D
	if terrain and terrain.material_override is ShaderMaterial:
		var m := terrain.material_override as ShaderMaterial
		m.set_shader_parameter("sink_origin", Vector3(pl.x, pl.y - 0.4, pl.z))
		m.set_shader_parameter("sink_dir", Vector2(fwd.x, fwd.z))
		m.set_shader_parameter("sink_on", 1.0)
	for gi in slice.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var n := str(g.name).to_lower()
		var plant := "palm" in n or "tree" in n or "grove" in n or "frond" in n or "fern" in n or "bush" in n or "grass" in n or "tuft" in n or "clump" in n
		if not ("cliff" in n or "rock" in n or "boulder" in n or "crag" in n or plant):
			continue
		if plant and g is MultiMeshInstance3D:
			# Bay-wide palm groves: their trunks fill the lookout frame.
			g.visible = false
			_hidden.append(g)
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var c := box.get_center()
		var to := Vector3(c.x - pl.x, 0, c.z - pl.z)
		if to.length() < 70.0 and box.end.y > pl.y - 4.0 and (to.length() < 8.0 or to.normalized().dot(fwd) > 0.2):
			g.visible = false
			_hidden.append(g)


func end_reveal() -> void:
	var slice: Node3D = host._slice
	var terrain := slice.get_node_or_null("IrregularCoastalTerrain") as MeshInstance3D if slice else null
	if terrain and terrain.material_override is ShaderMaterial:
		(terrain.material_override as ShaderMaterial).set_shader_parameter("sink_on", 0.0)
	for g in _hidden:
		if is_instance_valid(g):
			g.visible = true
	_hidden.clear()
	host._camera.far = maxf(_far_before, 420.0)
	var env: Environment = host._env
	if env and _fog_end > 0.0:
		env.fog_depth_end = _fog_end


## Crane up from behind the castaway: the castaway stays in the lower
## foreground while the view opens over the strait to the islands.
func reveal_camera(age: float) -> void:
	var cam: Camera3D = host._camera
	var pl: Vector3 = host._player.global_position
	var look_far := LOOK_FAR
	var k := smoothstep(0.0, 1.0, clampf(age / 6.5, 0.0, 1.0))
	var fwd := Vector3(look_far.x - pl.x, 0, look_far.z - pl.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var start := pl - fwd * 3.6 + side * 0.6 + Vector3.UP * 2.0
	# Lower, further back and pitched down so the castaway stands in the
	# lower foreground with the horizon in the upper third.
	# Swing the end view off the ridge hump toward the open strait.
	var fwd2 := fwd
	# Straight behind the castaway, looking out to sea over the islands.
	var finish := pl - fwd2 * 8.5 + Vector3.UP * 4.5
	# Raise the end eye until the line to the castaway's head clears the ridge.
	var head := pl + Vector3.UP * 1.6
	for _r in 12:
		var blocked := false
		for si in range(1, 10):
			var q := finish.lerp(head, float(si) / 10.0)
			if host._ground_y(q.x, q.z) > q.y - 0.3:
				blocked = true
				break
		if not blocked:
			break
		finish.y += 0.6
	cam.global_position = start.lerp(finish, k)
	var near_aim := pl + fwd * 6.0 + Vector3.UP * 1.2
	var pitch := deg_to_rad(9.0 + maxf(finish.y - pl.y - 4.5, 0.0) * 2.0)
	var far_aim := finish + (fwd2 * cos(pitch) - Vector3.UP * sin(pitch)) * 50.0
	var aim := near_aim.lerp(far_aim, k)
	cam.look_at(aim, Vector3.UP)
	cam.fov = lerpf(54.0, 60.0, k)
	if host._player:
		host._player.look_at(pl + fwd, Vector3.UP)
	var lines := [
		[0.6, "The ridge. The whole strait opens up."],
		[2.6, "Smoke... survivors on the next island."],
		[4.6, "Tideborn ruins, older than any chart."],
		[6.6, "And beyond, the Leviathan's tempest."],
	]
	for row in lines:
		if age >= float(row[0]) and age - float(row[0]) < 0.05:
			host._show_hint(str(row[1]))
			host._hint_t = 2.4


# --- build -----------------------------------------------------------------

func _build_cairns() -> void:
	_cairns = Node3D.new()
	_cairns.name = "TrailCairns"
	_cairns.visible = false
	host.add_child(_cairns)
	for i in range(2, _pts.size(), 3):
		var a := _pts[i]
		var b := _pts[mini(i + 1, _pts.size() - 1)]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		if dir.length() < 0.01:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(Vector3.UP) * 1.25
		var at := a + side
		at.y = host._terrain_y(at.x, at.z)
		for k in 3:
			var s := Art.put(_cairns, ASHORE_STONE, "Cairn%d_%d" % [i, k], at + Vector3(0, 0.02 + k * 0.17, 0), Vector3(0, i * 37 + k * 70, 0), 1.0)
			Art.fit_height(s, 0.22 - k * 0.04)


func _build_vista() -> void:
	_vista = Node3D.new()
	_vista.name = "Vista"
	_vista.visible = false
	host.add_child(_vista)
	var sea_y: float = host._water_y
	# Islands from the library: textured coastal cliffs (Hunyuan3D) with
	# palms on top. Survivor camp (W), Tideborn ruins (S), far island.
	var camp_top := _isle(Vector3(-175, sea_y, -120), 42.0, 11, 7)
	var ruin_top := _isle(Vector3(-60, sea_y, -230), 38.0, 23, 3)
	_isle(Vector3(-250, sea_y, -330), 44.0, 37, 0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.47, 0.42)
	stone.roughness = 0.9
	for i in 6:
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.6
		cyl.bottom_radius = 2.0
		cyl.height = 12.0 + float(i % 3) * 5.0
		cyl.radial_segments = 8
		cyl.material = stone
		pillar.mesh = cyl
		var a := float(i) / 6.0 * TAU
		pillar.position = ruin_top + Vector3(cos(a) * 9.0, cyl.height * 0.5 - 1.5, sin(a) * 6.0)
		pillar.rotation_degrees = Vector3(0, 0, -8.0 if i == 4 else 0.0)
		_vista.add_child(pillar)
	_smoke(camp_top + Vector3(-3, 0.5, 2))
	_smoke(camp_top + Vector3(4, 0.5, -3))
	# The Leviathan's tempest: a low, darker band of cloud on the horizon
	# (the old cone read as a floating trapezoid). A thin wide strip, fogged.
	var band := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(900.0, 26.0)
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = _band_tex()
	bm.albedo_color = Color(0.3, 0.32, 0.36, 0.8)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bq.material = bm
	band.mesh = bq
	band.position = Vector3(-60, sea_y + 12.0, -760)
	_vista.add_child(band)


## One island: two library cliffs back to back, plus palms on the crown.
## Returns a point on the crown (for ruins and smoke).
func _isle(at: Vector3, height: float, seed_i: int, palms: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var isle := Node3D.new()
	isle.name = "Isle%d" % seed_i
	isle.position = at
	_vista.add_child(isle)
	for c in 2:
		var cliff := Art.put(isle, Art.CLIFF, "Cliff%d" % c, Vector3((c * 2 - 1) * height * 0.16, -height * 0.12, rng.randf_range(-3, 3)), Vector3(0, c * 180.0 + rng.randf_range(-25, 25), 0), 1.0)
		Art.fit_height(cliff, height * (1.0 if c == 0 else 0.8))
	var box := Art.world_aabb(isle)
	var crown := Vector3(box.get_center().x, box.end.y - height * 0.14, box.get_center().z)
	for i in palms:
		var at_p := crown + Vector3(rng.randf_range(-0.3, 0.3) * box.size.x, -rng.randf_range(0.0, 0.08) * height, rng.randf_range(-0.25, 0.25) * box.size.z)
		var palm := Art.put(_vista, PALM, "Palm%d_%d" % [seed_i, i], at_p, Vector3(0, rng.randf_range(0, 360), 0), 1.0)
		Art.fit_height(palm, rng.randf_range(9.0, 13.0))
	for mi in Art.meshes(isle):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return crown


func _island(at: Vector3, radius: float, height: float, seed_i: int, mat: Material) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 0.08
	var n := 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / n * 2.0 - 1.0
			var v := float(j) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var h := maxf(0.0, 1.0 - r) 
			h = pow(h, 0.7) * height * (0.75 + 0.5 * noise.get_noise_2d(i, j))
			if r >= 1.0:
				h = -3.0
			verts.append(Vector3(u * radius, h, v * radius * 0.7))
			var green := clampf(h / height * 2.2 - 0.25, 0.0, 1.0)
			cols.append(Color(0.34, 0.31, 0.27).lerp(Color(0.16, 0.25, 0.12), green))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			for idx in [a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1]:
				st.set_color(cols[idx])
				st.add_vertex(verts[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vista.add_child(mi)


func _band_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 64
	return t


func _smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 8.0
	p.gravity = Vector3(0.6, 1.2, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 9.0
	p.scale_amount_max = 20.0
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.23, 0.22, 0.6)
	m.albedo_texture = Art.SOFT
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.mesh = q
	p.position = at
	_vista.add_child(p)
