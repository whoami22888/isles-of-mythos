class_name OpeningArt
extends RefCounted
## Shared art helpers for the opening battle and washed ashore.
## Every asset is preloaded (not path-concatenated) so the Android export
## dependency scanner packs it. Presentation only: no game state here.

const LIB := "res://assets/opening/library/"
const SOFT := preload("res://assets/opening/soft_round.png")
const CREATURE_SHADER := preload("res://shaders/opening_creature.gdshader")
const CASTAWAY := preload("res://assets/opening/library/castaway_ubc_rigged/castaway_ubc_rigged.glb")
const CUTLASS := preload("res://assets/opening/library/silas_cutlass_saber/silas_cutlass_saber.glb")
const CANNON := preload("res://assets/opening/library/cannon_01/cannon_01.glb")
const WINE_BARREL := preload("res://assets/opening/library/wine_barrel_01/wine_barrel_01.glb")
const BARRELS := preload("res://assets/opening/library/wooden_barrels_01/wooden_barrels_01.glb")
const CRATE_A := preload("res://assets/opening/library/wooden_crate_01/wooden_crate_01.glb")
const CRATE_B := preload("res://assets/opening/library/wooden_crate_02/wooden_crate_02.glb")
const CHEST := preload("res://assets/opening/library/treasure_chest/treasure_chest.glb")
const ROPE := preload("res://assets/opening/library/rope_coil_procedural/rope_coil_procedural.glb")
const PLANKS := preload("res://assets/opening/library/plank_pile_procedural/plank_pile_procedural.glb")
const DRIFT_TRUNK := preload("res://assets/opening/library/driftwood_trunk/driftwood_trunk.glb")
const DRIFT_BRANCHES := preload("res://assets/opening/library/driftwood_branches/driftwood_branches.glb")
const TORN_SAIL := preload("res://assets/opening/library/torn_sail/torn_sail.glb")
const SNAPPED_MAST := preload("res://assets/opening/library/snapped_mast/snapped_mast.glb")
const HULL_BOW := preload("res://assets/opening/library/hull_half_bow/hull_half_bow.glb")
const HULL_STERN := preload("res://assets/opening/library/hull_half_stern/hull_half_stern.glb")
const COAST_ROCKS_01 := preload("res://assets/opening/library/coast_rocks_01/coast_rocks_01.glb")
const COAST_ROCKS_03 := preload("res://assets/opening/library/coast_rocks_03/coast_rocks_03.glb")
const CLIFF := preload("res://assets/opening/library/cliff_hy3d/cliff_hy3d.glb")
const SEA_STACK := preload("res://assets/opening/library/sea_stack_boulder_02/sea_stack_boulder_02.glb")
const DARK_BOULDER := preload("res://assets/opening/library/dark_boulder_06/dark_boulder_06.glb")
const LEVIATHAN_HEAD := preload("res://assets/opening/library/leviathan_head_hy3d/leviathan_head_hy3d.glb")
const LEVIATHAN_TENTACLE := preload("res://assets/opening/library/leviathan_tentacle/leviathan_tentacle.glb")
const TIDEPUCK := preload("res://assets/opening/library/tidepuck_hy3d/tidepuck_hy3d.glb")
const JUNGLE_CLUMP := preload("res://assets/opening/library/jungle_clump_hy3d/jungle_clump_hy3d.glb")

## The approved leviathan grade (stills v2): desaturated sea-green, matte-wet.
const CREATURE_GRADE := [0.28, Color(0.86, 0.98, 0.9), 0.95, 0.18, 0.5]


static func spawn(scene: PackedScene, node_name: String = "") -> Node3D:
	if scene == null:
		return Node3D.new()
	var node := scene.instantiate() as Node3D
	if node == null:
		return Node3D.new()
	if node_name != "":
		node.name = node_name
	return node


static func put(parent: Node, scene: PackedScene, node_name: String, pos: Vector3, rot_deg: Vector3, scale: float) -> Node3D:
	var node := spawn(scene, node_name)
	parent.add_child(node)
	node.position = pos
	node.rotation_degrees = rot_deg
	node.scale = Vector3.ONE * scale
	return node


static func meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(meshes(child))
	return found


static func world_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in meshes(node):
		var local := mesh.get_aabb()
		for i in 8:
			var point: Vector3 = mesh.global_transform * local.get_endpoint(i)
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box


## Scale `node` so its world height is `meters` (call once it is in the tree).
static func fit_height(node: Node3D, meters: float) -> void:
	var box := world_aabb(node)
	if box.size.y < 0.001:
		return
	node.scale *= meters / box.size.y


static func grade(node: Node, desat: float, tint: Color, dark: float, rough_lo: float, rough_hi: float) -> void:
	for mesh in meshes(node):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = CREATURE_SHADER
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.roughness_texture:
				mat.set_shader_parameter("orm_tex", src.roughness_texture)
				mat.set_shader_parameter("has_orm", true)
			if src.normal_texture:
				mat.set_shader_parameter("normal_tex", src.normal_texture)
				mat.set_shader_parameter("has_normal", true)
			mat.set_shader_parameter("desat", desat)
			mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
			mat.set_shader_parameter("dark", dark)
			mat.set_shader_parameter("rough_lo", rough_lo)
			mat.set_shader_parameter("rough_hi", rough_hi)
			mesh.set_surface_override_material(i, mat)


static func grade_creature(node: Node) -> void:
	grade(node, CREATURE_GRADE[0], CREATURE_GRADE[1], CREATURE_GRADE[2], CREATURE_GRADE[3], CREATURE_GRADE[4])


## Multiply every surface's albedo by `col` (per-instance duplicates).
static func tone(node: Node, col: Color) -> void:
	for mesh in meshes(node):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as BaseMaterial3D
			mat.albedo_color = col
			mesh.set_surface_override_material(i, mat)


static func surface_tag(mesh: MeshInstance3D, i: int) -> String:
	var src := mesh.get_active_material(i)
	var tag := str(mesh.name)
	if src:
		tag += "|" + str(src.resource_name)
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
			tag += "|" + (src as BaseMaterial3D).albedo_texture.resource_path + "|" + str((src as BaseMaterial3D).albedo_texture.resource_name)
	if mesh.mesh is ArrayMesh:
		tag += "|" + str((mesh.mesh as ArrayMesh).surface_get_name(i))
	return tag.to_lower()


## Tone only the cloth: surfaces whose material, mesh or texture name says sail.
static func tone_matching(node: Node, needle: String, col: Color, roughness: float = -1.0) -> int:
	var hits := 0
	for mesh in meshes(node):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as BaseMaterial3D
			if src == null or not (needle in surface_tag(mesh, i)):
				continue
			var mat := src.duplicate() as BaseMaterial3D
			mat.albedo_color = col
			if roughness >= 0.0:
				mat.roughness = roughness
				mat.metallic_specular = 0.1
			mesh.set_surface_override_material(i, mat)
			hits += 1
	return hits


static func set_layers(node: Node, layers: int) -> void:
	for mesh in meshes(node):
		mesh.layers = layers


static func soft_disc(parent: Node, at: Vector3, size: float, col: Color, additive: bool) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	disc.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = SOFT
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(disc)
	disc.global_position = at
	return disc


## Low, soft billboard spray (approved stills). Static quads, no particles.
static func spray(parent: Node, at: Vector3, count: int, radius: float, size: float, alpha: float, seed: int = 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var sz := size * rng.randf_range(0.6, 1.4)
		mesh.size = Vector2(sz, sz * rng.randf_range(0.6, 1.0))
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = SOFT
		mat.albedo_color = Color(0.86, 0.9, 0.9, alpha * rng.randf_range(0.5, 1.0))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(quad)
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		quad.global_position = at + Vector3(cos(a) * r, rng.randf_range(0.0, size * 0.8), sin(a) * r)


## Flat foam ring where the leviathan breaks the surface (stills v2).
static func foam_ring(parent: Node, at: Vector3, r: float, water_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var a := TAU * float(i) / 22.0 + rng.randf_range(-0.1, 0.1)
		var rr := r * rng.randf_range(0.8, 1.15)
		soft_disc(parent, Vector3(at.x + cos(a) * rr, water_y + 0.05, at.z + sin(a) * rr), rng.randf_range(3.5, 6.0), Color(0.86, 0.9, 0.88, 0.55), false)
	soft_disc(parent, Vector3(at.x, water_y + 0.04, at.z), r * 2.6, Color(0.7, 0.78, 0.76, 0.35), false)


## Glow below the surface for the eerie calm: two additive soft discs and a
## teal omni that only lights layer 1 (the ships sit on layer 2), specular 0.
static func calm_glow(parent: Node, mid: Vector3, energy: float, size: float, water_y: float) -> Node3D:
	var root := Node3D.new()
	root.name = "AbyssalGlow"
	parent.add_child(root)
	soft_disc(root, Vector3(mid.x, water_y - 0.05, mid.z), size, Color(0.04, 0.26, 0.24, 0.42), true)
	soft_disc(root, Vector3(mid.x, water_y - 0.04, mid.z), size * 0.45, Color(0.05, 0.30, 0.27, 0.35), true)
	var light := OmniLight3D.new()
	light.name = "AbyssalLight"
	light.light_color = Color(0.22, 0.7, 0.62)
	light.light_energy = energy
	light.omni_range = size * 0.7
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	light.light_specular = 0.0
	light.light_cull_mask = 1
	root.add_child(light)
	light.global_position = Vector3(mid.x, water_y + 0.95, mid.z)
	return root


## Quaternius Universal Base Character (CC0) with Universal Animation Library
## clips (CC0, same UE-style skeleton). Faces +Z. Returns a holder whose
## "clips" meta is the AnimationPlayer; looping clips are set to loop.
static func castaway(shirt: Color = Color(-1, 0, 0)) -> Node3D:
	var rig := spawn(CASTAWAY, "Castaway")
	var anim := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for clip_name in anim.get_animation_list():
			var clip := anim.get_animation(clip_name)
			if clip == null:
				continue
			var once := str(clip_name) in ["Jump", "Attack", "Dodge", "Death", "Hit", "Punch", "PickUp", "Interact"]
			clip.loop_mode = Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
		rig.set_meta("clips", anim)
		if anim.has_animation("Idle"):
			anim.play("Idle")
	if shirt.r >= 0.0:
		paint_shirt(rig, shirt)
	return rig


static func paint_shirt(rig: Node, col: Color) -> StandardMaterial3D:
	var painted: StandardMaterial3D = null
	for mesh in meshes(rig):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as StandardMaterial3D
			if src == null or str(src.resource_name) != "Shirt_Linen":
				continue
			if painted == null:
				painted = src.duplicate() as StandardMaterial3D
				painted.albedo_color = col
			mesh.set_surface_override_material(i, painted)
	if painted:
		rig.set_meta("shirt", painted)
	return painted


static func skeleton_of(rig: Node) -> Skeleton3D:
	return rig.find_child("Skeleton3D", true, false) as Skeleton3D


## Silas's cutlass in the right hand (BoneAttachment3D on hand_r).
static func arm_with_cutlass(rig: Node) -> Node3D:
	var skeleton := skeleton_of(rig)
	if skeleton == null or skeleton.find_bone("hand_r") < 0:
		return null
	var hold := BoneAttachment3D.new()
	hold.name = "RightHand"
	hold.bone_name = "hand_r"
	skeleton.add_child(hold)
	var blade := spawn(CUTLASS, "Cutlass")
	hold.add_child(blade)
	# Native saber is 0.94 m tall along +Y with the grip at the origin; the
	# skeleton is in centimetre-free metres, so undo any rig scale.
	var s := skeleton.global_transform.basis.get_scale().x
	blade.scale = Vector3.ONE * (0.85 / maxf(s, 0.0001))
	blade.rotation_degrees = Vector3(0, 0, -90)
	blade.position = Vector3(0.0, 0.08, 0.0) / maxf(s, 0.0001)
	return blade


static func play(rig: Node, clip_name: String, blend: float = 0.18, speed: float = 1.0) -> void:
	if rig == null or not rig.has_meta("clips"):
		return
	var anim := rig.get_meta("clips") as AnimationPlayer
	if anim and anim.has_animation(clip_name) and anim.current_animation != clip_name:
		anim.play(clip_name, blend, speed)
