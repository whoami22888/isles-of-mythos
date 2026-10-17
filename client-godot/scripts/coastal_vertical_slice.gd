extends Node3D
## Coastal showcase integration. Server authority remains outside this scene.

const COAST_DIFFUSE := "res://assets/external/coast-sand-rocks-02/coast_sand_rocks_02_diffuse_1k.png"
const COAST_NORMAL := "res://assets/external/coast-sand-rocks-02/coast_sand_rocks_02_normal_1k.png"
const COAST_ROUGH := "res://assets/external/coast-sand-rocks-02/coast_sand_rocks_02_rough_1k.png"
const COAST_AO := "res://assets/external/coast-sand-rocks-02/coast_sand_rocks_02_ao_1k.png"

func _ready() -> void:
	await get_tree().process_frame
	_apply_coast_material()

func _apply_coast_material() -> void:
	var coast := get_node_or_null("Terrain/SculptedCoast") as MeshInstance3D
	if coast == null or coast.mesh == null:
		push_error("Coastal slice terrain mesh did not instantiate")
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(COAST_DIFFUSE)
	material.normal_enabled = true
	material.normal_texture = load(COAST_NORMAL)
	material.roughness_texture = load(COAST_ROUGH)
	material.ao_enabled = true
	material.ao_texture = load(COAST_AO)
	material.roughness = 0.88
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	coast.material_override = material
