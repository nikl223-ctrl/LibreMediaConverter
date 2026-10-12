extends Node3D
## Procedural city environment and traffic for the Android rescue sim.
## An original visual approximation of a 2012 ambulance driving game.
## No original game assets are copied into this project.

const BLOCK: float = 80.0
const EDGE: float = 315.0
const ROAD_WIDTH: float = 16.0

var rng := RandomNumberGenerator.new()
var asphalt: StandardMaterial3D
var sidewalk: StandardMaterial3D
var grass: StandardMaterial3D
var white: StandardMaterial3D
var yellow: StandardMaterial3D
var wall_materials: Array[ShaderMaterial] = []
var traffic: Array[Dictionary] = []
var landmark_material: StandardMaterial3D
var traffic_time: float = 0.0
var traffic_count: int = 24
var world_root: Node3D

func initialize() -> void:
    rng.seed = 2012
    world_root = self
    _create_materials()
    _build_lighting()
    _build_terrain()
    _build_roads()
    _build_buildings()
    _build_street_props()
    _build_trees()
    _build_traffic()

func _material(color: Color, rough: float = 0.86) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = rough
    return mat

func _create_materials() -> void:
    asphalt = _material(Color("#414449"), 0.98)
    sidewalk = _material(Color("#979d99"))
    grass = _material(Color("#4f8152"))
    white = _material(Color("#d4d4c7"))
    yellow = _material(Color("#ddbd54"))
    landmark_material = _material(Color("#fc9a2d"))
    var tones := [
        Color("#a6a69b"), Color("#b6aca2"), Color("#a3b4b9"),
        Color("#b2aa8a"), Color("#a5a5a9"), Color("#c0ac9b")
    ]
    for color in tones:
        var material := ShaderMaterial.new()
        var shader := Shader.new()
        shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform vec4 wall_color : source_color = vec4(0.66,0.66,0.66,1.0);
varying vec2 building_uv;
void vertex() {
    building_uv = UV;
}
void fragment() {
    vec2 tile = building_uv * vec2(9.0,14.0);
    vec2 box = fract(tile);
    vec2 id = floor(tile);
    float frame = step(0.18,box.x) * (1.0-step(0.83,box.x)) *
                  step(0.22,box.y) * (1.0-step(0.86,box.y));
    float lit = step(0.75,fract(sin(dot(id,vec2(17.1,31.7)))*43758.545));
    vec3 glass = mix(vec3(0.13,0.19,0.23),vec3(0.56,0.54,0.38),lit);
    float horizontal = step(0.967,fract(building_uv.y*14.0));
    vec3 brick = wall_color.rgb * (0.94+0.08*fract(sin(dot(id,vec2(3.1,7.4)))*8943.1));
    ALBEDO = mix(brick,glass,frame);
    ALBEDO *= 1.0 - horizontal*0.18;
    ROUGHNESS = mix(0.81,0.34,frame);
    EMISSION = glass * frame * lit * 0.14;
}
"""
        material.shader = shader
        material.set_shader_parameter("wall_color", color)
        wall_materials.append(material)

func _build_lighting() -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color("#4f9ad0")
    sky_mat.sky_horizon_color = Color("#cedfea")
    sky_mat.ground_horizon_color = Color("#a3b0a4")
    sky_mat.ground_bottom_color = Color("#647e65")
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.66
    env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#b2bdc0")
    env.fog_density = 0.003
    we.environment = env
    add_child(we)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-51.0,25.0,0.0)
    sun.light_color = Color("#fff0d8")
    sun.light_energy = 0.93
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 75.0
    add_child(sun)

func _box(parent: Node3D, location: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    item.mesh = mesh
    item.material_override = material
    item.position = location
    parent.add_child(item)
    return item

func _cylinder(parent: Node3D, location: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius * 1.1
    mesh.height = height
    mesh.radial_segments = 9
    item.mesh = mesh
    item.material_override = material
    item.position = location
    parent.add_child(item)
    return item

func _solid(location: Vector3, dimensions: Vector3, mat: Material) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.position = location
    add_child(body)
    _box(body, Vector3.ZERO, dimensions, mat)
    var coll := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = dimensions
    coll.shape = shape
    body.add_child(coll)
    return body

func _build_terrain() -> void:
    _solid(Vector3(0.0,-0.55,0.0),Vector3(666.0,1.1,666.0),grass)
    # A broad perimeter keeps the phone within the explorable map.
    var wall_mat := _material(Color("#3f6950"))
    for p in [
        [Vector3(0,6,-332),Vector3(670,12,2)],
        [Vector3(0,6,332),Vector3(670,12,2)],
        [Vector3(-332,6,0),Vector3(2,12,670)],
        [Vector3(332,6,0),Vector3(2,12,670)]
    ]:
        _solid(p[0],p[1],wall_mat)

func _build_roads() -> void:
    # 7 north-south and 7 east-west streets, numerous intersections.
    var trim := _material(Color("#747a76"))
    for ix in range(-3,4):
        var road_coord := float(ix)*BLOCK
        _box(self,Vector3(road_coord,0.045,0),Vector3(ROAD_WIDTH,0.08,656.0),asphalt)
        _box(self,Vector3(0,0.051,road_coord),Vector3(656.0,0.09,ROAD_WIDTH),asphalt)
        # Continuous curbs on both sides; break up with intersection access.
        for segment in range(-4,4):
            var mid := float(segment)*BLOCK+BLOCK*0.5
            for side in [-1.0,1.0]:
                _box(self,Vector3(road_coord+side*10.2,0.105,mid),Vector3(3.0,0.16,64.0),sidewalk)
                _box(self,Vector3(mid,0.109,road_coord+side*10.2),Vector3(64.0,0.16,3.0),sidewalk)
        for line in range(-31,32):
            var t := float(line)*10.0
            if absf(fmod(absf(t),BLOCK)) > 14.5:
                _box(self,Vector3(road_coord,0.10,t),Vector3(0.19,0.01,4.5),white)
                _box(self,Vector3(t,0.11,road_coord),Vector3(4.5,0.01,0.19),white)
    for x in range(-3,4):
        for z in range(-3,4):
            var px := float(x)*BLOCK
            var pz := float(z)*BLOCK
            for a in range(5):
                var d := (float(a)-2.0)*2.1
                _box(self,Vector3(px-14,0.122,pz+d),Vector3(4.0,0.01,1.0),white)
                _box(self,Vector3(px+d,0.123,pz-14),Vector3(1.0,0.01,4.0),white)

func _build_buildings() -> void:
    var roof := _material(Color("#50555a"))
    var door := _material(Color("#364451"),0.41)
    var trim := _material(Color("#d2c9b4"))
    for bx in range(-3,3):
        for bz in range(-3,3):
            var cx := float(bx)*BLOCK+40.0
            var cz := float(bz)*BLOCK+40.0
            if cx > 5 and cx < 65 and cz < -170 and cz > -245:
                continue
            if cx > 165 and cz > 160:
                continue
            var center := Vector3(cx,0,cz)
            var park := ((bx+2*bz) % 7 == 0)
            if park:
                _box(self,center+Vector3(0,0.12,0),Vector3(61,0.13,61),grass)
                for i in range(4):
                    var x := cx+rng.randf_range(-18,18)
                    var z := cz+rng.randf_range(-18,18)
                    _box(self,Vector3(x,0.29,z),Vector3(9,0.35,3.4),sidewalk)
                continue
            for subx in [-1,1]:
                for subz in [-1,1]:
                    var x := cx+float(subx)*17.0
                    var z := cz+float(subz)*17.0
                    var height := rng.randf_range(12.0,33.0)+float((bx*bz+9)%5)*3.2
                    var width := rng.randf_range(17.0,23.0)
                    var depth := rng.randf_range(17.0,23.0)
                    var building := _solid(Vector3(x,height*0.5,z),Vector3(width,height,depth),wall_materials[rng.randi_range(0,wall_materials.size()-1)])
                    building.name = "CityBuilding_%d_%d" % [bx,bz]
                    _box(self,Vector3(x,height+0.24,z),Vector3(width+0.7,0.42,depth+0.7),roof)
                    _box(self,Vector3(x,height*0.06,z-depth*0.505),Vector3(3.0,3.4,0.10),door)
                    if rng.randf()<0.3:
                        _box(self,Vector3(x,2.0,z-depth*0.515-0.12),Vector3(5.5,0.55,0.1),trim)
    # Emergency hospital and city dispatch buildings.
    _create_hospital()
    _create_station()

func _create_hospital() -> void:
    var tile := _material(Color("#c9d9e2"))
    var glass := _material(Color("#538b99"),0.24)
    var red := _material(Color("#e44748"))
    _solid(Vector3(32.0,12.0,-216.0),Vector3(49,24,47),tile)
    _box(self,Vector3(32.0,24.3,-216.0),Vector3(51,0.6,49),sidewalk)
    for level in range(5):
        _box(self,Vector3(32.0,4.5+4.0*level,-192.25),Vector3(41,2.6,0.13),glass)
    _box(self,Vector3(32.0,3.0,-192.13),Vector3(15,5.0,0.12),glass)
    _box(self,Vector3(32.0,11.4,-192.06),Vector3(9.0,1.1,0.23),red)
    _box(self,Vector3(32.0,12.5,-192.04),Vector3(1.5,8.2,0.26),red)
    _box(self,Vector3(32.0,0.13,-170.0),Vector3(33.0,0.14,44.0),asphalt)

func _create_station() -> void:
    var tile := _material(Color("#d0d0c3"))
    var dark := _material(Color("#445563"),0.33)
    var red := _material(Color("#c44038"))
    _solid(Vector3(191.0,7.0,205.0),Vector3(44.0,14.0,37.0),tile)
    _box(self,Vector3(191.0,14.3,205.0),Vector3(46,0.6,40.0),red)
    for x in [176.0,191.0,206.0]:
        _box(self,Vector3(x,4.1,186.4),Vector3(12.6,7.4,0.25),dark)
        _box(self,Vector3(x,4.1,186.19),Vector3(12.6,0.23,0.26),red)
    _box(self,Vector3(191.0,0.15,155.0),Vector3(48.0,0.13,45.0),asphalt)

func _build_street_props() -> void:
    var steel := _material(Color("#5b6465"),0.45)
    var lamp_color := _material(Color("#f7df9b"),0.21)
    lamp_color.emission_enabled=true
    lamp_color.emission=Color("#ffe3a9")
    lamp_color.emission_energy_multiplier=1.3
    var green := _material(Color("#376b45"))
    var amber := _material(Color("#cdaa31"))
    var red := _material(Color("#b6463b"))
    for ix in range(-3,4):
        for iz in range(-3,4):
            var x := float(ix)*BLOCK
            var z := float(iz)*BLOCK
            if (ix+iz)%2==0:
                _cylinder(self,Vector3(x+12,3.2,z+12),0.095,6.4,steel)
                _box(self,Vector3(x+10.7,6.40,z+12),Vector3(2.8,0.12,0.14),steel)
                _box(self,Vector3(x+9.45,6.30,z+12),Vector3(0.8,0.14,0.48),lamp_color)
            if (ix+iz)%3==0:
                _cylinder(self,Vector3(x-10.4,2.1,z-10.4),0.1,4.2,steel)
                _box(self,Vector3(x-10.4,4.1,z-10.4),Vector3(0.6,1.4,0.45),steel)
                _box(self,Vector3(x-10.4,4.47,z-10.64),Vector3(0.28,0.24,0.1),red)
                _box(self,Vector3(x-10.4,4.10,z-10.64),Vector3(0.28,0.24,0.1),amber)
                _box(self,Vector3(x-10.4,3.74,z-10.64),Vector3(0.28,0.24,0.1),green)

func _build_trees() -> void:
    var trunk_mat := _material(Color("#625a43"))
    var leaf_mat := _material(Color("#427e46"))
    var leaf_mat2 := _material(Color("#55864c"))
    var trunk := CylinderMesh.new()
    trunk.top_radius=0.12
    trunk.bottom_radius=0.20
    trunk.height=1.0
    trunk.radial_segments=6
    var crown := SphereMesh.new()
    crown.radius=1.0
    crown.height=2.0
    crown.radial_segments=8
    crown.rings=5
    var stems: Array[Transform3D]=[]
    var leaves_one: Array[Transform3D]=[]
    var leaves_two: Array[Transform3D]=[]
    for i in range(640):
        var x := rng.randf_range(-310,310)
        var z := rng.randf_range(-310,310)
        var nearest_x := roundf(x/BLOCK)*BLOCK
        var nearest_z := roundf(z/BLOCK)*BLOCK
        if absf(x-nearest_x)<12.8 or absf(z-nearest_z)<12.8:
            continue
        if x>4 and x<66 and z<-171 and z>-254:
            continue
        if x>163 and z>163:
            continue
        var height := rng.randf_range(4.4,7.4)
        stems.append(Transform3D(Basis().scaled(Vector3(1.0,height,1.0)),Vector3(x,height*0.5,z)))
        var leaf := Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3(height*0.37,height*0.38,height*0.36)),Vector3(x,height*0.83,z))
        if i%2==0:
            leaves_one.append(leaf)
        else:
            leaves_two.append(leaf)
    _instance_geometry("StreetTreesTrunks",trunk,trunk_mat,stems)
    _instance_geometry("StreetTreeCanopiesA",crown,leaf_mat,leaves_one)
    _instance_geometry("StreetTreeCanopiesB",crown,leaf_mat2,leaves_two)

func _instance_geometry(label: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D]) -> void:
    mesh.surface_set_material(0,mat)
    var buckets: Dictionary = {}
    for t in transforms:
        var key := Vector2i(floori(t.origin.x/120.0),floori(t.origin.z/120.0))
        if not buckets.has(key):
            buckets[key]=[]
        buckets[key].append(t)
    for key in buckets:
        var array: Array = buckets[key]
        var mult := MultiMesh.new()
        mult.transform_format=MultiMesh.TRANSFORM_3D
        mult.mesh=mesh
        mult.instance_count=array.size()
        for i in range(array.size()):
            mult.set_instance_transform(i,array[i])
        var instance := MultiMeshInstance3D.new()
        instance.name="%s_%d_%d" % [label,key.x,key.y]
        instance.multimesh=mult
        instance.visibility_range_end=260.0
        add_child(instance)

func _create_car_model(parent: Node3D, color: Color, ambulance: bool) -> Node3D:
    var root := Node3D.new()
    parent.add_child(root)
    var body := _material(color,0.45)
    var window_mat := _material(Color("#335764"),0.22)
    var tire := _material(Color("#202328"),0.97)
    var rim := _material(Color("#c1c5c4"),0.36)
    var white_mat := _material(Color("#dfebee"),0.50)
    var red_mat := _material(Color("#d63e38"))
    var blue_mat := _material(Color("#2075bf"))
    blue_mat.emission_enabled=true
    blue_mat.emission=Color("#125ace")
    blue_mat.emission_energy_multiplier=0.75
    var metal := _material(Color("#888f96"),0.32)
    var length := 5.8 if ambulance else 4.1
    var roof_height := 2.8 if ambulance else 1.7
    _box(root,Vector3(0,1.10,0),Vector3(2.05,1.58,length),body)
    _box(root,Vector3(0,roof_height*0.5+0.48,0.2 if ambulance else 0.35),Vector3(1.95,roof_height-1.25,length*0.57),body)
    _box(root,Vector3(0,roof_height*0.5+0.50,-length*0.15),Vector3(1.74,0.91,0.1),window_mat)
    _box(root,Vector3(-1.01,roof_height*0.5+0.54,0.02),Vector3(0.09,0.95,length*0.41),window_mat)
    _box(root,Vector3(1.01,roof_height*0.5+0.54,0.02),Vector3(0.09,0.95,length*0.41),window_mat)
    _box(root,Vector3(0,0.59,-length*0.5-0.05),Vector3(1.8,0.28,0.1),metal)
    _box(root,Vector3(0,0.59,length*0.5+0.05),Vector3(1.8,0.28,0.1),metal)
    for x in [-1.03,1.03]:
        for z in [-length*0.32,length*0.32]:
            var wheel := _cylinder(root,Vector3(x,0.55,z),0.46,0.23,tire)
            wheel.rotation_degrees.z=90
            var hub := _cylinder(root,Vector3(x+(-0.13 if x<0 else 0.13),0.55,z),0.24,0.01,rim)
            hub.rotation_degrees.z=90
    if ambulance:
        for x in [-1.04,1.04]:
            _box(root,Vector3(x,1.25,0.27),Vector3(0.06,0.5,3.1),red_mat)
        _box(root,Vector3(0,roof_height+0.31,-0.45),Vector3(1.56,0.24,0.56),metal)
        _box(root,Vector3(-0.43,roof_height+0.48,-0.45),Vector3(0.58,0.20,0.52),blue_mat)
        _box(root,Vector3(0.43,roof_height+0.48,-0.45),Vector3(0.58,0.20,0.52),blue_mat)
        _box(root,Vector3(0,1.53,length*0.5+0.03),Vector3(0.16,0.90,0.04),red_mat)
        _box(root,Vector3(0,1.53,length*0.5+0.06),Vector3(0.73,0.16,0.06),red_mat)
        _box(root,Vector3(-0.8,0.98,-length*0.5-0.08),Vector3(0.29,0.23,0.09),white_mat)
        _box(root,Vector3(0.8,0.98,-length*0.5-0.08),Vector3(0.29,0.23,0.09),white_mat)
    else:
        _box(root,Vector3(-0.70,0.92,-length*0.5-0.07),Vector3(0.29,0.19,0.08),white_mat)
        _box(root,Vector3(0.70,0.92,-length*0.5-0.07),Vector3(0.29,0.19,0.08),white_mat)
    return root

func create_player_model(parent: Node3D, vehicle_index: int) -> Node3D:
    var shade := Color("#f3f5f1") if vehicle_index==0 else (Color("#ecdbcc") if vehicle_index==1 else Color("#e8eceb"))
    return _create_car_model(parent,shade,true)

func _build_traffic() -> void:
    var palette := [Color("#8b3739"),Color("#3f5369"),Color("#878e82"),Color("#c7bc9e"),Color("#485b50"),Color("#ab8d59")]
    for i in range(traffic_count):
        var root := Node3D.new()
        root.name="CivilianTraffic_%d" % i
        add_child(root)
        var axis := i%2
        var direction := -1.0 if i%4<2 else 1.0
        var road := float(rng.randi_range(-3,3))*BLOCK
        var lane := direction*2.8
        var pos := rng.randf_range(-305.0,305.0)
        if axis==0:
            root.position=Vector3(road+lane,0.06,pos)
            root.rotation.y=PI if direction>0 else 0.0
        else:
            root.position=Vector3(pos,0.06,road+lane)
            root.rotation.y=-PI*0.5 if direction>0 else PI*0.5
        _create_car_model(root,palette[i%palette.size()],false)
        traffic.append({"node":root,"axis":axis,"direction":direction,"speed":rng.randf_range(6.0,13.0),"phase":rng.randf_range(0.0,TAU)})

func advance_traffic(delta: float, player: Node3D) -> void:
    traffic_time += delta
    for t in traffic:
        var vehicle: Node3D = t["node"]
        # Lower updates beyond 125 meters prevent unnecessary work on mobile.
        if vehicle.global_position.distance_to(player.global_position)>250.0:
            continue
        var factor := 0.64+0.36*absf(sin(traffic_time*0.17+float(t["phase"])))
        var speed := float(t["speed"])*factor*float(t["direction"])
        if int(t["axis"])==0:
            vehicle.position.z+=speed*delta
            if absf(vehicle.position.z)>315.0:
                vehicle.position.z=-signf(vehicle.position.z)*315.0
        else:
            vehicle.position.x+=speed*delta
            if absf(vehicle.position.x)>315.0:
                vehicle.position.x=-signf(vehicle.position.x)*315.0
