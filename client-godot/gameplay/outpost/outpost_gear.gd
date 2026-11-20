extends RefCounted
## Small modelled props for the privateers: the Captain's tricorn and the
## Musketeer's musket. Lit PBR materials, no emission.

const Art := preload("res://gameplay/opening/opening_art.gd")

static var _felt: StandardMaterial3D
static var _iron: StandardMaterial3D
static var _wood: StandardMaterial3D
static var _smoke: StandardMaterial3D


static func _mats() -> void:
	if _felt:
		return
	_felt = StandardMaterial3D.new()
	_felt.albedo_color = Color(0.07, 0.06, 0.055)
	_felt.roughness = 0.95
	_iron = StandardMaterial3D.new()
	_iron.albedo_color = Color(0.2, 0.2, 0.21)
	_iron.metallic = 0.85
	_iron.roughness = 0.45
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.32, 0.19, 0.1)
	_wood.roughness = 0.7
	_smoke = StandardMaterial3D.new()
	_smoke.albedo_color = Color(0.78, 0.76, 0.72, 0.5)
	_smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke.roughness = 1.0


static func _cyl(parent: Node3D, top: float, bottom: float, h: float, mat: Material, segs: int = 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	var m := MeshInstance3D.new()
	m.mesh = c
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## Tricorn: a wide felt brim pinched up on three sides around a low crown.
static func tricorn(rig: Node3D) -> Node3D:
	_mats()
	var sk := Art.skeleton_of(rig)
	if sk == null or sk.find_bone("Head") < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var s := sk.global_transform.basis.get_scale().x
	var hat := Node3D.new()
	hat.name = "Tricorn"
	att.add_child(hat)
	hat.scale = Vector3.ONE / maxf(s, 0.0001)
	hat.position = Vector3(0, 0.17, 0.0) / maxf(s, 0.0001)
	var crown := _cyl(hat, 0.085, 0.105, 0.11, _felt)
	crown.position.y = 0.05
	for k in 3:
		var a := TAU * k / 3.0 + PI
		var flap := _cyl(hat, 0.15, 0.17, 0.018, _felt, 3)
		flap.scale = Vector3(1.0, 1.0, 0.45)
		flap.position = Vector3(sin(a) * 0.075, 0.035, cos(a) * 0.075)
		flap.rotation = Vector3(0, a, 0)
		flap.rotate_object_local(Vector3.RIGHT, -0.55)
	return hat


## Musket held by the unit node (not a bone) so it can level into an aim.
static func musket(holder: Node3D, height: float) -> Node3D:
	_mats()
	var gun := Node3D.new()
	gun.name = "Musket"
	holder.add_child(gun)
	var barrel := _cyl(gun, 0.014, 0.018, 1.0, _iron, 8)
	barrel.rotation_degrees.x = 90
	barrel.position.z = -0.45
	var stock := _cyl(gun, 0.03, 0.05, 0.5, _wood, 6)
	stock.rotation_degrees.x = 90
	stock.position = Vector3(0, -0.02, 0.22)
	stock.scale = Vector3(0.7, 1.0, 1.4)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.96)
	gun.add_child(muzzle)
	carry(gun, height)
	return gun


## Shoulder arms: angled across the body while moving.
static func carry(gun: Node3D, height: float) -> void:
	gun.position = Vector3(0.22, height * 0.68, -0.05)
	gun.rotation_degrees = Vector3(-60, 10, 0)


## Aim: levelled at shoulder height, pointing forward (-Z).
static func aim(gun: Node3D, height: float) -> void:
	gun.position = Vector3(0.18, height * 0.8, -0.15)
	gun.rotation_degrees = Vector3(-2, 0, 0)


static func puff(parent: Node3D, at: Vector3) -> void:
	_mats()
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 8
		sm.rings = 4
		var m := MeshInstance3D.new()
		m.mesh = sm
		m.material_override = _smoke.duplicate()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
		m.global_position = at + Vector3(randf_range(-0.1, 0.1), randf_range(0, 0.1), randf_range(-0.1, 0.1))
		var t := m.create_tween()
		t.tween_property(m, "scale", Vector3.ONE * (2.2 + k * 0.6), 0.9)
		t.parallel().tween_property(m, "global_position", m.global_position + Vector3(0, 0.5, 0), 0.9)
		t.parallel().tween_property(m.material_override, "albedo_color:a", 0.0, 0.9)
		t.tween_callback(m.queue_free)
