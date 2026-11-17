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


func end_reveal() -> void:
	host._camera.far = maxf(_far_before, 420.0)
	var env: Environment = host._env
	if env and _fog_end > 0.0:
		env.fog_depth_end = _fog_end


## Crane up from behind the castaway to a high wide view south over the bay.
func reveal_camera(age: float) -> void:
	var cam: Camera3D = host._camera
	var pl: Vector3 = host._player.global_position
	var look_far := Vector3(-30.0, -4.0, -240.0)
	var k := smoothstep(0.0, 1.0, clampf(age / 6.5, 0.0, 1.0))
	var start := pl + Vector3(0.6, 2.0, 4.2)
	var finish := pl + Vector3(3.5, 9.0, 11.0)
	cam.global_position = start.lerp(finish, k)
	var aim := (pl + Vector3(0, 1.2, -6.0)).lerp(look_far, k)
	cam.look_at(aim, Vector3.UP)
	cam.fov = lerpf(54.0, 62.0, k)
	if host._player:
		var f := Vector3(look_far.x - pl.x, 0, look_far.z - pl.z).normalized()
		host._player.look_at(pl + f, Vector3.UP)
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
	var rock := StandardMaterial3D.new()
	rock.vertex_color_use_as_albedo = true
	rock.roughness = 0.95
	var sea_y: float = host._water_y
	# Survivor-camp island (SW), Tideborn ruins island (SE), far island (S).
	_island(Vector3(-120, sea_y, -170), 70.0, 26.0, 11, rock)
	_island(Vector3(95, sea_y, -210), 60.0, 34.0, 23, rock)
	_island(Vector3(-15, sea_y, -340), 110.0, 30.0, 37, rock)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.44, 0.4)
	stone.roughness = 0.9
	for i in 6:
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.3
		cyl.bottom_radius = 1.6
		cyl.height = 10.0 + float(i % 3) * 4.0
		cyl.radial_segments = 8
		cyl.material = stone
		pillar.mesh = cyl
		pillar.position = Vector3(82 + i * 5.5, sea_y + 14.0 + cyl.height * 0.5, -205 + (i % 2) * 6.0)
		pillar.rotation_degrees = Vector3(0, 0, -6.0 if i == 4 else 0.0)
		_vista.add_child(pillar)
	_smoke(Vector3(-128, sea_y + 14.0, -165))
	_smoke(Vector3(-110, sea_y + 12.0, -178))
	# The Leviathan's tempest: a dark wall of cloud on the horizon beyond the wreck.
	var storm := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 150.0
	cone.bottom_radius = 70.0
	cone.height = 220.0
	cone.radial_segments = 16
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.16, 0.18, 0.22, 0.86)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.roughness = 1.0
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.disable_fog = false
	cone.material = cm
	storm.mesh = cone
	storm.position = Vector3(-60, sea_y + 100.0, -720)
	_vista.add_child(storm)


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


func _smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 8.0
	p.gravity = Vector3(0.6, 1.2, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.52, 0.52, 0.5, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.mesh = q
	p.position = at
	_vista.add_child(p)
