extends Node3D
## Riverlands: procedural daylight river valley with GPU-instanced trees and vegetation.
## Built for low draw-call counts and Android Compatibility rendering.

const GRASS_TEX := "res://assets/generated/grass_mobile.jpg"
const SOIL_TEX := "res://assets/generated/soil_mobile.jpg"
const BARK_TEX := "res://assets/generated/bark_mobile.jpg"
const ROCK_TEX := "res://assets/generated/rock_mobile.jpg"
const WATER_TEX := "res://assets/generated/water_mobile.jpg"
const EXTENT: float = 86.0
const GRID: int = 86

var rng := RandomNumberGenerator.new()
var bark: StandardMaterial3D
var leaves: Array[StandardMaterial3D] = []
var ground_material: ShaderMaterial
var water_material: ShaderMaterial
var rock_material: StandardMaterial3D

func generate(game: Node3D) -> void:
    rng.seed = 260411
    _make_daylight()
    _create_materials()
    _create_land(game)
    _create_river()
    _create_forest()
    _create_undergrowth()
    _create_rocks()
    _create_clouds()

func _mat(tex_path: String, tint: Color, roughness: float = 0.94) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    if ResourceLoader.exists(tex_path):
        material.albedo_texture = load(tex_path)
    material.roughness = roughness
    material.metallic = 0.0
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    return material

func _create_materials() -> void:
    bark = _mat(BARK_TEX, Color("#f8ece0"))
    bark.uv1_scale = Vector3(1.0, 2.0, 1.0)
    rock_material = _mat(ROCK_TEX, Color("#e7e4dc"))
    rock_material.uv1_scale = Vector3(2.0, 2.0, 1.0)
    for tone in [Color("#406737"), Color("#568042"), Color("#729b55"), Color("#355b39")]:
        var m := _mat(GRASS_TEX, tone)
        m.uv1_scale = Vector3(2.2, 2.2, 1.0)
        leaves.append(m)

    ground_material = ShaderMaterial.new()
    var terrain_shader := Shader.new()
    terrain_shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 pos_xz;
void vertex() {
    pos_xz = VERTEX.xz;
}
void fragment() {
    vec2 grass_uv = pos_xz * 0.13;
    vec2 mud_uv = pos_xz * 0.10;
    float river_center = 5.0 + sin(pos_xz.y * 0.058) * 3.5 + cos(pos_xz.y * 0.19) * 1.1;
    float shore = abs(pos_xz.x - river_center);
    float mud = 1.0 - smoothstep(8.0, 15.0, shore);
    vec3 grass = texture(grass_tex, grass_uv).rgb;
    vec3 soil = texture(soil_tex, mud_uv).rgb;
    ALBEDO = mix(grass, soil, mud * 0.94);
    ROUGHNESS = 0.92;
    METALLIC = 0.0;
}
"""
    ground_material.shader = terrain_shader
    ground_material.set_shader_parameter("grass_tex", load(GRASS_TEX))
    ground_material.set_shader_parameter("soil_tex", load(SOIL_TEX))

    water_material = ShaderMaterial.new()
    var river_shader := Shader.new()
    river_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;
uniform sampler2D water_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void vertex() {
    VERTEX.y += 0.035 * sin(VERTEX.z * 2.1 + TIME * 1.65 + VERTEX.x * 1.3);
}
void fragment() {
    vec2 flow = UV * vec2(3.0, 17.0);
    vec3 a = texture(water_tex, flow + vec2(TIME * 0.015, TIME * 0.043)).rgb;
    vec3 b = texture(water_tex, flow * 1.74 + vec2(-TIME * 0.008, TIME * 0.066)).rgb;
    float ripple = clamp(a.r * 0.7 + b.g * 0.3, 0.0, 1.0);
    ALBEDO = mix(vec3(0.18, 0.28, 0.23), vec3(0.44, 0.50, 0.37), ripple);
    ROUGHNESS = clamp(0.23 - ripple * 0.06, 0.13, 0.3);
    METALLIC = 0.02;
    ALPHA = 0.94;
}
"""
    water_material.shader = river_shader
    water_material.set_shader_parameter("water_tex", load(WATER_TEX))

func _make_daylight() -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color("#6e9fcd")
    sky_mat.sky_horizon_color = Color("#c9dded")
    sky_mat.ground_horizon_color = Color("#a6ad95")
    sky_mat.ground_bottom_color = Color("#587457")
    sky_mat.sun_angle_max = 11.0
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.79
    env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#c9d5c5")
    env.fog_density = 0.0053
    we.environment = env
    add_child(we)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-44.0, -33.0, 0.0)
    sun.light_color = Color("#fff3d6")
    sun.light_energy = 1.48
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 65.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    add_child(sun)

func _river_center(z: float) -> float:
    return 5.0 + sin(z * 0.058) * 3.5 + cos(z * 0.19) * 1.1

func _terrain_height(x: float, z: float) -> float:
    var d := absf(x - _river_center(z))
    if d < 8.0:
        return -0.29 + 0.05 * sin(x * 0.28 + z * 0.10)
    if d < 13.5:
        return lerpf(-0.29, 0.025, (d - 8.0) / 5.5)
    var far_hill := pow(maxf(0.0, absf(x) - 43.0) * 0.054, 1.38)
    var natural := sin(x * 0.17 + z * 0.11) * 0.038 + sin(z * 0.15) * 0.027
    return 0.014 + far_hill + natural

func _create_land(game: Node3D) -> void:
    # The simplified flat collision floor keeps mobile movement fast;
    # the rendered terrain adds natural shoreline and distant hills.
    var floor_body := StaticBody3D.new()
    floor_body.name = "WalkingGround"
    floor_body.position = Vector3(0.0, -0.50, 0.0)
    var floor_col := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(170.0, 1.0, 170.0)
    floor_col.shape = floor_shape
    floor_body.add_child(floor_col)
    add_child(floor_body)

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(ground_material)
    var step: float = EXTENT * 2.0 / float(GRID)
    for iz in range(GRID):
        var za := -EXTENT + float(iz) * step
        var zb := za + step
        for ix in range(GRID):
            var xa := -EXTENT + float(ix) * step
            var xb := xa + step
            var a := Vector3(xa, _terrain_height(xa, za), za)
            var b := Vector3(xb, _terrain_height(xb, za), za)
            var c := Vector3(xa, _terrain_height(xa, zb), zb)
            var d := Vector3(xb, _terrain_height(xb, zb), zb)
            _tri(st, a, c, b, Vector2.ZERO, Vector2.DOWN, Vector2.RIGHT)
            _tri(st, b, c, d, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE)
    st.generate_normals()
    var land := MeshInstance3D.new()
    land.name = "NaturalTerrain"
    land.mesh = st.commit()
    add_child(land)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
    st.set_uv(ua)
    st.add_vertex(a)
    st.set_uv(ub)
    st.add_vertex(b)
    st.set_uv(uc)
    st.add_vertex(c)

func _create_river() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(water_material)
    var segments := 160
    for i in range(segments):
        var za := -EXTENT + 2.0 * EXTENT * float(i) / float(segments)
        var zb := -EXTENT + 2.0 * EXTENT * float(i + 1) / float(segments)
        var ca := _river_center(za)
        var cb := _river_center(zb)
        var a := Vector3(ca - 8.9, 0.13, za)
        var b := Vector3(ca + 8.9, 0.13, za)
        var c := Vector3(cb - 8.9, 0.13, zb)
        var d := Vector3(cb + 8.9, 0.13, zb)
        var uva := Vector2(0.0, float(i) / float(segments))
        var uvb := Vector2(1.0, float(i) / float(segments))
        var uvc := Vector2(0.0, float(i + 1) / float(segments))
        var uvd := Vector2(1.0, float(i + 1) / float(segments))
        _tri(st, a, c, b, uva, uvc, uvb)
        _tri(st, b, c, d, uvb, uvc, uvd)
    st.generate_normals()
    var stream := MeshInstance3D.new()
    stream.name = "AnimatedRiver"
    stream.mesh = st.commit()
    add_child(stream)

func _spawn_multimesh(label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
    if transforms.is_empty():
        return
    mesh.surface_set_material(0, material)
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for i in range(transforms.size()):
        multimesh.set_instance_transform(i, transforms[i])
    var mi := MultiMeshInstance3D.new()
    mi.name = label
    mi.multimesh = multimesh
    add_child(mi)

func _make_transform(location: Vector3, stretch: Vector3, heading: float = 0.0) -> Transform3D:
    var basis := Basis(Vector3.UP, heading).scaled(stretch)
    return Transform3D(basis, location)

func _create_forest() -> void:
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.25
    trunk_mesh.bottom_radius = 0.40
    trunk_mesh.height = 1.0
    trunk_mesh.radial_segments = 7

    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = 1.0
    crown_mesh.height = 2.0
    crown_mesh.radial_segments = 8
    crown_mesh.rings = 5

    var trunks: Array[Transform3D] = []
    var crowns: Array = [[], [], [], []]
    for i in range(240):
        var x := rng.randf_range(-81.0, -24.0) if i % 2 == 0 else rng.randf_range(27.0, 81.0)
        var z := rng.randf_range(-82.0, 82.0)
        var height := rng.randf_range(5.0, 12.0)
        var width := rng.randf_range(0.78, 1.34)
        var level := _terrain_height(x, z)
        var center := Vector3(x, level, z)
        trunks.append(_make_transform(center + Vector3(0.0, height * 0.37, 0.0), Vector3(width, height * 0.74, width), rng.randf_range(-PI, PI)))
        var tone := i % 4
        for j in range(3):
            var spread := height * (0.16 if j > 0 else 0.0)
            var offset := Vector3(rng.randf_range(-spread, spread), height * rng.randf_range(0.72, 0.97), rng.randf_range(-spread, spread))
            var size := rng.randf_range(0.23, 0.35) * height
            var canopy_scale := Vector3(size, size * rng.randf_range(0.77, 1.05), size)
            crowns[tone].append(_make_transform(center + offset, canopy_scale, rng.randf_range(0.0, TAU)))
    _spawn_multimesh("InstancedTreeTrunks", trunk_mesh, bark, trunks)
    for tone in range(4):
        _spawn_multimesh("LeafCanopies_%d" % tone, crown_mesh, leaves[tone], crowns[tone])

func _create_undergrowth() -> void:
    # One combined blade mesh + 3600 instances produces lush banks without
    # spawning thousands of individual Godot scene nodes.
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var base := 0.0
    for angle in [0.0, PI / 2.0]:
        var dx := cos(angle)
        var dz := sin(angle)
        _tri(st, Vector3(-dx * 0.19, base, -dz * 0.19), Vector3(dx * 0.19, base, dz * 0.19), Vector3(0.0, 0.78, 0.0), Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1.0))
        _tri(st, Vector3(dx * 0.19, base, dz * 0.19), Vector3(-dx * 0.19, base, -dz * 0.19), Vector3(0.0, 0.78, 0.0), Vector2.RIGHT, Vector2.ZERO, Vector2(0.5, 1.0))
    st.generate_normals()
    var clump_mesh := st.commit()
    var grass_mat := StandardMaterial3D.new()
    grass_mat.albedo_color = Color("#78a65a")
    grass_mat.roughness = 1.0
    grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    var transforms: Array[Transform3D] = []
    for i in range(3600):
        var x := rng.randf_range(-78.0, 78.0)
        var z := rng.randf_range(-79.0, 79.0)
        if absf(x - _river_center(z)) < 13.9:
            continue
        var v := rng.randf_range(0.4, 1.25)
        transforms.append(_make_transform(Vector3(x, _terrain_height(x,z) + 0.03, z), Vector3(v,v,v), rng.randf_range(0,TAU)))
    _spawn_multimesh("RiverbankGrassClumps", clump_mesh, grass_mat, transforms)

func _create_rocks() -> void:
    var boulder_mesh := SphereMesh.new()
    boulder_mesh.radius = 1.0
    boulder_mesh.height = 2.0
    boulder_mesh.radial_segments = 9
    boulder_mesh.rings = 5
    var transforms: Array[Transform3D] = []
    for i in range(185):
        var z := rng.randf_range(-81.0,81.0)
        var center := _river_center(z)
        var x := center + (rng.randf_range(9.0, 24.0) * (1.0 if i % 2 == 0 else -1.0))
        var r := rng.randf_range(0.20, 1.24)
        transforms.append(_make_transform(Vector3(x,_terrain_height(x,z)+r*0.15,z), Vector3(r*1.18,r*0.53,r*0.82), rng.randf_range(0,TAU)))
    _spawn_multimesh("ShoreRocks", boulder_mesh, rock_material, transforms)

func _create_clouds() -> void:
    var cloud_mat := StandardMaterial3D.new()
    cloud_mat.albedo_color = Color(0.96, 0.97, 0.97, 0.76)
    cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var cloud_mesh := SphereMesh.new()
    cloud_mesh.radius = 1.0
    cloud_mesh.height = 2.0
    cloud_mesh.radial_segments = 10
    cloud_mesh.rings = 5
    var transforms: Array[Transform3D] = []
    for i in range(14):
        var cx := rng.randf_range(-110.0, 110.0)
        var cy := rng.randf_range(46.0, 69.0)
        var cz := rng.randf_range(-175.0, -85.0)
        for j in range(4):
            var p := Vector3(cx + float(j - 2) * 5.7, cy + rng.randf_range(-1.1, 1.2), cz + rng.randf_range(-3.0,3.0))
            transforms.append(_make_transform(p, Vector3(rng.randf_range(9.0,15.0),rng.randf_range(2.5,4.8),rng.randf_range(6.0,10.0))))
    _spawn_multimesh("SoftClouds", cloud_mesh, cloud_mat, transforms)
