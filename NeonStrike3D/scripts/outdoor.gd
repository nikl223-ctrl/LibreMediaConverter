extends Node3D
## Riverlands: procedural daylight river valley with GPU-instanced trees and vegetation.
## Built for low draw-call counts and Android Compatibility rendering.

const GRASS_TEX := "res://assets/generated/grass_mobile.jpg"
const SOIL_TEX := "res://assets/generated/soil_mobile.jpg"
const BARK_TEX := "res://assets/generated/bark_mobile.jpg"
const ROCK_TEX := "res://assets/generated/rock_mobile.jpg"
const WATER_TEX := "res://assets/generated/water_mobile.jpg"
const EXTENT: float = 360.0
const GRID: int = 180

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
    _create_hero_trees()
    _create_undergrowth()
    _create_shrubs()
    _create_rocks()
    _create_clouds()

func _safe_tex(path: String) -> Texture2D:
    if ResourceLoader.exists(path):
        return load(path) as Texture2D
    var fallback := Image.create(32, 32, false, Image.FORMAT_RGB8)
    fallback.fill(Color("#8c9a7b"))
    return ImageTexture.create_from_image(fallback)

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
    bark = _mat(BARK_TEX, Color("#b9a48b"))
    bark.uv1_scale = Vector3(1.0, 2.0, 1.0)
    rock_material = _mat(ROCK_TEX, Color("#adb0a7"))
    rock_material.uv1_scale = Vector3(2.0, 2.0, 1.0)
    for tone in [Color("#48743b"), Color("#628647"), Color("#77a25b"), Color("#416943")]:
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
    ground_material.set_shader_parameter("grass_tex", _safe_tex(GRASS_TEX))
    ground_material.set_shader_parameter("soil_tex", _safe_tex(SOIL_TEX))

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
    water_material.set_shader_parameter("water_tex", _safe_tex(WATER_TEX))

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
    env.ambient_light_energy = 0.48
    env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#c9d5c5")
    env.fog_density = 0.0019
    we.environment = env
    add_child(we)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-44.0, -33.0, 0.0)
    sun.light_color = Color("#fff3d6")
    sun.light_energy = 0.92
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 120.0
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
    var far_hill := pow(maxf(0.0, absf(x) - 90.0) * 0.019, 1.35)
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
    floor_shape.size = Vector3(720.0, 1.0, 720.0)
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
    var segments := 560
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

func _spawn_multimesh(label: String, mesh: Mesh, material: Material, transforms: Array) -> void:
    if transforms.is_empty():
        return
    mesh.surface_set_material(0, material)
    # Mobile-friendly: tile instances in 96m regions for proper GPU frustum culling
    # instead of drawing all 1500 trees and 15000 blades at once.
    var buckets: Dictionary = {}
    for t in transforms:
        var key := Vector2i(floori(t.origin.x / 96.0), floori(t.origin.z / 96.0))
        if not buckets.has(key):
            buckets[key] = []
        buckets[key].append(t)
    for key in buckets:
        var group: Array = buckets[key]
        var multi := MultiMesh.new()
        multi.transform_format = MultiMesh.TRANSFORM_3D
        multi.mesh = mesh
        multi.instance_count = group.size()
        for i in range(group.size()):
            multi.set_instance_transform(i, group[i])
        var instance := MultiMeshInstance3D.new()
        instance.name = "%s_%d_%d" % [label, key.x, key.y]
        instance.multimesh = multi
        instance.visibility_range_end = 265.0
        instance.visibility_range_end_margin = 35.0
        add_child(instance)

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
    for i in range(1550):
        var is_near := i < 330
        var x := (rng.randf_range(-95.0, -29.0) if i % 2 == 0 else rng.randf_range(35.0, 96.0)) if is_near else (rng.randf_range(-330.0, -30.0) if i % 2 == 0 else rng.randf_range(36.0, 330.0))
        var z := rng.randf_range(-155.0, 70.0) if is_near else rng.randf_range(-337.0, 337.0)
        if absf(z + 118.0) < 11.0 and absf(x) < 33.0:
            continue
        if absf(z + 218.0) < 15.0 and absf(x + 66.0) < 22.0:
            continue
        var height := rng.randf_range(5.0, 12.0)
        var width := rng.randf_range(0.78, 1.34)
        var level := _terrain_height(x, z)
        var center := Vector3(x, level, z)
        trunks.append(_make_transform(center + Vector3(0.0, height * 0.37, 0.0), Vector3(width, height * 0.74, width), rng.randf_range(-PI, PI)))
        var tone := i % 4
        for j in range(4):
            var spread := height * (0.16 if j > 0 else 0.0)
            var offset := Vector3(rng.randf_range(-spread, spread), height * rng.randf_range(0.72, 0.97), rng.randf_range(-spread, spread))
            var size := rng.randf_range(0.23, 0.35) * height
            var canopy_scale := Vector3(size, size * rng.randf_range(0.77, 1.05), size)
            crowns[tone].append(_make_transform(center + offset, canopy_scale, rng.randf_range(0.0, TAU)))
    _spawn_multimesh("InstancedTreeTrunks", trunk_mesh, bark, trunks)
    for tone in range(4):
        _spawn_multimesh("LeafCanopies_%d" % tone, crown_mesh, leaves[tone], crowns[tone])


func _create_hero_trees() -> void:
    # Larger hand-assembled trees along the campaign route. Shared materials keep memory low.
    var wood := bark
    var canopy_material: Material = leaves[1]
    var branch := CylinderMesh.new()
    branch.top_radius = 0.07
    branch.bottom_radius = 0.16
    branch.height = 3.4
    branch.radial_segments = 7
    var treetop := SphereMesh.new()
    treetop.radius = 1.0
    treetop.height = 2.0
    treetop.radial_segments = 12
    treetop.rings = 8
    for i in range(30):
        var z := -175.0 + float(i % 15) * 17.0 + rng.randf_range(-6.0, 6.0)
        var x := -36.0 - float(i / 15) * 20.0 + rng.randf_range(-10.0, 9.0)
        if absf(z + 118.0) < 14.0 or absf(z + 218.0) < 15.0:
            continue
        var group := Node3D.new()
        group.name = "AncientTree_%02d" % i
        group.position = Vector3(x, _terrain_height(x,z), z)
        add_child(group)
        var height := rng.randf_range(9.0, 15.5)
        var trunk := MeshInstance3D.new()
        var trunk_mesh := CylinderMesh.new()
        trunk_mesh.top_radius = 0.27
        trunk_mesh.bottom_radius = 0.49
        trunk_mesh.height = height * 0.79
        trunk_mesh.radial_segments = 10
        trunk.mesh = trunk_mesh
        trunk.material_override = wood
        trunk.position.y = height * 0.395
        group.add_child(trunk)
        for j in range(5):
            var angle := TAU * float(j) / 5.0
            var branch_instance := MeshInstance3D.new()
            branch_instance.mesh = branch
            branch_instance.material_override = wood
            branch_instance.position = Vector3(cos(angle) * 0.91, height * 0.7, sin(angle) * 0.91)
            branch_instance.rotation.z = 0.7 * sin(angle)
            branch_instance.rotation.x = 0.7 * cos(angle)
            group.add_child(branch_instance)
            var crown := MeshInstance3D.new()
            crown.mesh = treetop
            crown.material_override = canopy_material
            crown.position = Vector3(cos(angle) * 2.25, height * 0.85 + rng.randf_range(-1.2, 1.2), sin(angle) * 2.2)
            crown.scale = Vector3(2.5, 2.0, 2.8)
            group.add_child(crown)
        var central := MeshInstance3D.new()
        central.mesh = treetop
        central.material_override = leaves[i % 4]
        central.position = Vector3(0.0, height * 0.96, 0.0)
        central.scale = Vector3(3.1, 2.4, 3.4)
        group.add_child(central)

func _create_shrubs() -> void:
    # Small dense shrubs and flower patches break up the obvious low-poly ground.
    var bush_mesh := SphereMesh.new()
    bush_mesh.radius = 0.5
    bush_mesh.height = 1.0
    bush_mesh.radial_segments = 9
    bush_mesh.rings = 6
    var dense: Array[Transform3D] = []
    var flowers: Array[Transform3D] = []
    for i in range(3800):
        var x := rng.randf_range(-95.0, 82.0) if i < 2300 else rng.randf_range(-330.0, 330.0)
        var z := rng.randf_range(-165.0, 75.0) if i < 2300 else rng.randf_range(-330.0, 330.0)
        if absf(x - _river_center(z)) < 11.0:
            continue
        var height := _terrain_height(x, z)
        var radius := rng.randf_range(0.33, 1.17)
        if i % 7 == 0:
            flowers.append(_make_transform(Vector3(x,height + 0.13,z), Vector3(radius * 0.45, radius * 0.35, radius * 0.43), rng.randf_range(0,TAU)))
        else:
            dense.append(_make_transform(Vector3(x,height + 0.22,z), Vector3(radius * 1.8,radius * 0.9,radius * 1.3), rng.randf_range(0,TAU)))
    var shrub := StandardMaterial3D.new()
    shrub.albedo_color = Color("#386338")
    shrub.roughness = 1.0
    var flower := StandardMaterial3D.new()
    flower.albedo_color = Color("#b9afbd")
    flower.roughness = 1.0
    _spawn_multimesh("ForestShrubs", bush_mesh, shrub, dense)
    _spawn_multimesh("Wildflowers", bush_mesh, flower, flowers)

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
    grass_mat.albedo_color = Color("#568c3e")
    grass_mat.roughness = 1.0
    grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    var transforms: Array[Transform3D] = []
    for i in range(15500):
        var near := i < 4600
        var x := rng.randf_range(-76.0, 75.0) if near else rng.randf_range(-335.0, 335.0)
        var z := rng.randf_range(-165.0, 75.0) if near else rng.randf_range(-333.0, 333.0)
        if absf(x - _river_center(z)) < 10.5:
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
    for i in range(900):
        var z := rng.randf_range(-330.0,330.0)
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
    for i in range(12):
        var cx := rng.randf_range(-110.0, 110.0)
        var cy := rng.randf_range(46.0, 69.0)
        var cz := rng.randf_range(-175.0, -85.0)
        for j in range(4):
            var p := Vector3(cx + float(j - 2) * 5.7, cy + rng.randf_range(-1.1, 1.2), cz + rng.randf_range(-3.0,3.0))
            transforms.append(_make_transform(p, Vector3(rng.randf_range(9.0,15.0),rng.randf_range(2.5,4.8),rng.randf_range(6.0,10.0))))
    _spawn_multimesh("SoftClouds", cloud_mesh, cloud_mat, transforms)
