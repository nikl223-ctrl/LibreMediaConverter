extends RefCounted
class_name PBRLibrary

static func material(asset: String, scale: float, fallback: Color, tint := Color.WHITE) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = fallback * tint
	mat.roughness = 0.82
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3(scale, scale, scale)

	var base := "res://assets/pbr/%s/%s" % [asset, asset]
	var diffuse_path := base + "_diff_4k.jpg"
	var normal_path := base + "_nor_gl_4k.jpg"
	var rough_path := base + "_rough_4k.jpg"

	if ResourceLoader.exists(diffuse_path):
		mat.albedo_texture = load(diffuse_path)
		mat.albedo_color = tint
	if ResourceLoader.exists(normal_path):
		mat.normal_enabled = true
		mat.normal_scale = 1.0
		mat.normal_texture = load(normal_path)
	if ResourceLoader.exists(rough_path):
		mat.roughness_texture = load(rough_path)
		mat.roughness = 1.0
	return mat

static func paint(color: Color, metallic := 0.78, roughness := 0.22) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.72
	mat.clearcoat_roughness = 0.12
	return mat

static func glass(color := Color(0.055, 0.085, 0.11, 0.56)) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.08
	mat.roughness = 0.08
	mat.refraction_enabled = true
	mat.refraction_scale = 0.03
	return mat
