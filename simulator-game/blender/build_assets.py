# RoadLife Simulator Blender asset generator
# Runs headless in GitHub Actions with Blender 5.2 LTS.
from pathlib import Path
import math
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets" / "models"
SOURCES = ROOT / "blender" / "generated"
MODELS.mkdir(parents=True, exist_ok=True)
SOURCES.mkdir(parents=True, exist_ok=True)

def clean():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        pass
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

def material(name, color, metallic=0.0, roughness=0.45, transmission=0.0, emission=None, emission_strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if emission is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = emission
    return m

def cube(name, loc, dims, mat=None, bevel=0.0, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
    if mat:
        o.data.materials.append(mat)
    return o

def cyl(name, loc, radius, depth, mat=None, rot=(0,0,0), vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    bevel = o.modifiers.new("EdgeBevel", "BEVEL")
    bevel.width = min(radius * 0.07, 0.04)
    bevel.segments = 2
    bpy.ops.object.shade_smooth()
    return o

def torus(name, loc, major, minor, mat=None, rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=16, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o

def uv_sphere(name, loc, scale, mat=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o

def text_obj(name, text, loc, size, mat, rot=(math.radians(90),0,0), extrude=0.025):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.data.body = text
    o.data.align_x = "CENTER"
    o.data.size = size
    o.data.extrude = extrude
    o.data.bevel_depth = 0.008
    o.data.materials.append(mat)
    return o

def export_asset(name):
    # Convert text/curves, apply modifiers and join the static asset into one mesh.
    # This keeps the rich material layout but drastically cuts Godot node/draw overhead.
    for obj in list(bpy.context.scene.objects):
        if obj.type in {"FONT", "CURVE"}:
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.convert(target="MESH")
            obj.select_set(False)

    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH":
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            for mod in list(obj.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                except Exception:
                    pass
            obj.select_set(False)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    if meshes:
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
        meshes[0].name = name

    blend_path = SOURCES / f"{name}.blend"
    glb_path = MODELS / f"{name}.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print(f"BLENDER_ASSET {name}: {glb_path.stat().st_size} bytes")

def build_sport_sedan():
    clean()
    paint = material("CarPaint", (0.015,0.09,0.46,1), 0.82, 0.16)
    paint2 = material("CarPaintDark", (0.008,0.025,0.08,1), 0.75, 0.18)
    black = material("BlackTrim", (0.008,0.009,0.012,1), 0.1, 0.32)
    rubber = material("TireRubber", (0.006,0.007,0.008,1), 0.0, 0.9)
    chrome = material("BrushedMetal", (0.34,0.37,0.40,1), 0.92, 0.18)
    glass = material("TintedGlass", (0.018,0.04,0.07,1), 0.16, 0.08, 0.42)
    white = material("HeadLamp", (0.72,0.86,1.0,1), 0.12, 0.12, emission=(0.65,0.82,1.0,1), emission_strength=4.0)
    red = material("TailLamp", (0.8,0.01,0.005,1), 0.1, 0.15, emission=(1,0.005,0.002,1), emission_strength=2.6)
    interior = material("Interior", (0.035,0.032,0.03,1), 0.0, 0.68)

    # Sculpted body made from overlapping bevelled hard-surface panels.
    cube("LowerBody", (0,0,0.63), (1.88,4.55,0.52), paint, 0.16)
    cube("ShoulderBody", (0,-0.05,0.91), (1.82,3.95,0.34), paint, 0.13)
    hood = cube("Hood", (0,-1.48,1.07), (1.73,1.25,0.16), paint, 0.08, rot=(math.radians(-3),0,0))
    trunk = cube("Trunk", (0,1.62,1.02), (1.72,0.80,0.20), paint, 0.07, rot=(math.radians(2),0,0))
    cube("Roof", (0,0.30,1.58), (1.46,1.62,0.18), paint2, 0.08)

    # Cabin and glass.
    cube("Windshield", (0,-0.49,1.40), (1.48,0.73,0.56), glass, 0.06, rot=(math.radians(-24),0,0))
    cube("RearGlass", (0,0.91,1.39), (1.46,0.62,0.52), glass, 0.06, rot=(math.radians(28),0,0))
    cube("LeftWindow", (-0.77,0.24,1.34), (0.045,1.18,0.52), glass, 0.025)
    cube("RightWindow", (0.77,0.24,1.34), (0.045,1.18,0.52), glass, 0.025)
    cube("BLeft", (-0.775,0.28,1.38), (0.055,0.09,0.62), black, 0.015)
    cube("BRight", (0.775,0.28,1.38), (0.055,0.09,0.62), black, 0.015)

    # Aggressive bumpers, skirts, grille and diffuser.
    cube("FrontBumper", (0,-2.24,0.56), (1.84,0.16,0.28), paint, 0.055)
    cube("RearBumper", (0,2.24,0.57), (1.84,0.16,0.29), paint, 0.055)
    cube("FrontSplitter", (0,-2.34,0.36), (1.88,0.24,0.07), black, 0.025)
    cube("RearDiffuser", (0,2.34,0.36), (1.80,0.24,0.08), black, 0.02)
    cube("LeftSkirt", (-0.94,0,0.44), (0.08,3.70,0.12), black, 0.025)
    cube("RightSkirt", (0.94,0,0.44), (0.08,3.70,0.12), black, 0.025)
    cube("UpperGrille", (0,-2.335,0.72), (1.10,0.035,0.30), black, 0.015)
    for x in [-0.72,-0.48,-0.24,0,0.24,0.48,0.72]:
        cube("GrilleSlat", (x,-2.36,0.71), (0.035,0.025,0.25), chrome, 0.008)

    # Lights.
    for x in (-0.58,0.58):
        cube("Headlight", (x,-2.31,0.86), (0.48,0.07,0.18), white, 0.045)
        cube("TailLight", (x,2.31,0.83), (0.46,0.07,0.17), red, 0.045)

    # Mirrors, handles and exhaust.
    for x in (-1,1):
        cube("Mirror", (x*0.96,-0.39,1.34), (0.24,0.30,0.13), paint, 0.06)
        for y in (-0.35,0.75):
            cube("Handle", (x*0.925,y,1.02), (0.035,0.24,0.035), chrome, 0.012)
    for x in (-0.57,0.57):
        cyl("Exhaust", (x,2.38,0.38), 0.095, 0.20, chrome, rot=(math.radians(90),0,0), vertices=32)

    # Interior silhouettes.
    for x in (-0.42,0.42):
        cube("Seat", (x,0.15,1.08), (0.48,0.58,0.72), interior, 0.10)
    torus("SteeringWheel", (-0.40,-0.48,1.28), 0.16, 0.025, black, rot=(math.radians(78),0,0))
    cube("Dash", (0,-0.62,1.18), (1.35,0.24,0.18), interior, 0.05)

    # Wheels with rims and brake discs.
    for x in (-0.985,0.985):
        for y in (-1.43,1.43):
            torus("Tire", (x,y,0.48), 0.31, 0.105, rubber, rot=(0,math.radians(90),0))
            cyl("Rim", (x,y,0.48), 0.245, 0.20, chrome, rot=(0,math.radians(90),0), vertices=32)
            cyl("BrakeDisc", (x*1.001,y,0.48), 0.17, 0.215, black, rot=(0,math.radians(90),0), vertices=32)
            for a in range(0,360,60):
                rad=math.radians(a)
                cube("Spoke", (x + (0.105 if x>0 else -0.105), y + math.sin(rad)*0.105, 0.48 + math.cos(rad)*0.105),
                     (0.03,0.19,0.035), chrome, 0.008, rot=(math.radians(-a),0,0))

    # Small lip spoiler.
    cube("SpoilerWing", (0,2.06,1.25), (1.44,0.28,0.075), black, 0.03)
    cube("SpoilerL", (-0.55,1.98,1.15), (0.08,0.13,0.22), black, 0.02)
    cube("SpoilerR", (0.55,1.98,1.15), (0.08,0.13,0.22), black, 0.02)

    export_asset("sport_sedan")

def add_window_grid(width, height, base_y, z0, cols, rows, mat, facing="front"):
    for c in range(cols):
        for r in range(rows):
            x = -width/2 + (c+0.5)*width/cols
            z = z0 + (r+0.5)*height/rows
            if facing == "front":
                cube("Window", (x,base_y,z), (width/cols*0.62,0.055,height/rows*0.58), mat, 0.025)
            else:
                cube("Window", (base_y,x,z), (0.055,width/cols*0.62,height/rows*0.58), mat, 0.025)

def build_modern_building():
    clean()
    concrete = material("Concrete", (0.19,0.22,0.25,1), 0.05, 0.76)
    concrete2 = material("ConcreteLight", (0.48,0.51,0.53,1), 0.02, 0.72)
    glass = material("BlueGlass", (0.03,0.12,0.19,1), 0.35, 0.09, 0.28)
    metal = material("FrameMetal", (0.11,0.13,0.15,1), 0.82, 0.22)
    warm = material("LobbyGlow", (0.45,0.29,0.12,1), 0.05, 0.30, emission=(1.0,0.48,0.16,1), emission_strength=1.8)

    cube("Tower", (0,0,11.5), (12,12,23), concrete, 0.18)
    cube("VerticalAccent", (-4.7,-6.08,12.2), (1.1,0.18,20.5), concrete2, 0.04)
    cube("VerticalAccent2", (4.7,-6.08,12.2), (1.1,0.18,20.5), concrete2, 0.04)
    add_window_grid(8.1,18.4,-6.105,3.0,4,8,glass,"front")
    add_window_grid(8.1,18.4,6.105,3.0,4,8,glass,"front")
    add_window_grid(8.1,18.4,-6.105,3.0,4,8,glass,"side")
    add_window_grid(8.1,18.4,6.105,3.0,4,8,glass,"side")

    for z in [3.1,5.4,7.7,10.0,12.3,14.6,16.9,19.2,21.5]:
        cube("FloorBand", (0,-6.13,z), (11.4,0.10,0.10), metal, 0.018)
        cube("FloorBandRear", (0,6.13,z), (11.4,0.10,0.10), metal, 0.018)

    cube("LobbyGlass", (0,-6.13,1.65), (4.8,0.08,2.75), glass, 0.035)
    cube("LobbyLight", (0,-5.95,1.60), (4.3,0.08,2.35), warm, 0.02)
    cube("EntranceCanopy", (0,-6.75,2.75), (5.3,1.55,0.18), metal, 0.05)
    cube("RoofPlant", (2.6,1.4,23.7), (3.2,3.0,1.4), metal, 0.10)
    cube("RoofPlant2", (-2.5,-1.8,23.4), (2.2,2.0,0.8), concrete2, 0.08)
    export_asset("building_modern")

def build_brick_building():
    clean()
    brick = material("Brick", (0.34,0.085,0.045,1), 0.0, 0.87)
    stone = material("Stone", (0.42,0.40,0.36,1), 0.0, 0.78)
    glass = material("WindowGlass", (0.025,0.07,0.10,1), 0.18, 0.10, 0.22)
    rail = material("Rail", (0.035,0.04,0.045,1), 0.7, 0.30)
    cube("BrickBlock", (0,0,8.0), (14,10,16), brick, 0.13)
    cube("GroundBand", (0,-5.06,1.0), (13.7,0.15,1.8), stone, 0.03)
    add_window_grid(11.8,11.8,-5.08,2.7,5,5,glass,"front")
    add_window_grid(11.8,11.8,5.08,2.7,5,5,glass,"front")
    for floor in range(1,5):
        z=2.8+floor*2.45
        for x in (-4.4,0,4.4):
            cube("BalconySlab",(x,-5.65,z),(2.65,1.25,0.12),stone,0.025)
            cube("BalconyRail",(x,-6.2,z+0.55),(2.5,0.05,0.9),rail,0.015)
    cube("Cornice",(0,0,16.15),(14.35,10.35,0.28),stone,0.04)
    cube("Entrance",(0,-5.10,1.3),(2.0,0.12,2.5),glass,0.03)
    export_asset("building_brick")

def build_garage():
    clean()
    concrete = material("GarageConcrete",(0.18,0.20,0.22,1),0.0,0.74)
    dark = material("DarkMetal",(0.025,0.03,0.035,1),0.82,0.24)
    door = material("RollerDoor",(0.16,0.18,0.20,1),0.72,0.34)
    blue = material("BlueNeon",(0.01,0.18,0.68,1),0.35,0.18,emission=(0.02,0.28,1.0,1),emission_strength=4.5)
    glass = material("OfficeGlass",(0.03,0.08,0.11,1),0.18,0.10,0.25)

    cube("GarageShell",(0,0,2.65),(14,9,5.3),concrete,0.15)
    for x in (-4.2,0,4.2):
        cube("BayDoor",(x,-4.56,2.20),(3.55,0.10,3.75),door,0.035)
        for z in (0.75,1.35,1.95,2.55,3.15):
            cube("DoorLine",(x,-4.63,z),(3.35,0.035,0.035),dark,0.006)
    cube("OfficeWindow",(5.55,4.55,2.05),(2.15,0.08,2.55),glass,0.03)
    cube("Canopy",(0,-5.0,4.85),(13.2,1.45,0.22),dark,0.05)
    text_obj("GarageSign","ROADLIFE GARAGE",(0,-5.18,5.45),0.72,blue,rot=(math.radians(90),0,0),extrude=0.04)
    export_asset("garage")

def build_gas_station():
    clean()
    white = material("StationWhite",(0.72,0.75,0.76,1),0.05,0.58)
    dark = material("StationDark",(0.06,0.07,0.08,1),0.7,0.30)
    green = material("StationGreen",(0.02,0.48,0.18,1),0.38,0.22,emission=(0.01,0.65,0.20,1),emission_strength=2.2)
    screen = material("PumpScreen",(0.02,0.12,0.16,1),0.15,0.12,emission=(0.02,0.22,0.28,1),emission_strength=1.0)
    concrete = material("Forecourt",(0.32,0.33,0.34,1),0.0,0.82)

    cube("Forecourt",(0,0,0.08),(18,14,0.16),concrete,0.02)
    cube("Canopy",(0,0,4.35),(15.5,10.5,0.52),white,0.12)
    cube("CanopyStripe",(0,-5.28,4.36),(15.5,0.14,0.38),green,0.025)
    for x in (-6.2,6.2):
        for y in (-3.8,3.8):
            cyl("Column",(x,y,2.2),0.18,4.3,white,vertices=32)
    for x in (-3.5,0,3.5):
        for y in (-2.0,2.0):
            cube("Pump",(x,y,1.05),(0.78,0.62,1.85),dark,0.10)
            cube("PumpFace",(x,y-0.325 if y<0 else y+0.325,1.28),(0.48,0.035,0.48),screen,0.02)
            cube("PumpBand",(x,y,1.78),(0.82,0.66,0.16),green,0.04)
    text_obj("StationSign","ROADLIFE FUEL",(0,-5.42,4.68),0.54,green,rot=(math.radians(90),0,0),extrude=0.035)
    export_asset("gas_station")

def build_street_props():
    clean()
    metal = material("StreetMetal",(0.08,0.09,0.10,1),0.88,0.25)
    lamp = material("LampGlow",(1.0,0.63,0.25,1),0.1,0.15,emission=(1.0,0.42,0.10,1),emission_strength=5.0)
    red = material("SignalRed",(0.75,0.01,0.01,1),0.1,0.15,emission=(1,0,0,1),emission_strength=2.2)
    amber = material("SignalAmber",(0.85,0.32,0.0,1),0.1,0.15,emission=(1,0.26,0,1),emission_strength=1.6)
    green = material("SignalGreen",(0.0,0.55,0.08,1),0.1,0.15,emission=(0,1,0.08,1),emission_strength=2.1)

    # Lamp at origin.
    cyl("LampPole",(0,0,2.9),0.085,5.8,metal,vertices=32)
    cube("LampArm",(0,-0.48,5.68),(0.10,1.0,0.10),metal,0.025)
    cube("LampHead",(0,-0.92,5.58),(0.42,0.62,0.16),metal,0.045)
    cube("LampLens",(0,-1.02,5.49),(0.32,0.40,0.035),lamp,0.018)

    # Traffic light one side, offset so both can be separated in Godot if desired.
    cyl("SignalPole",(2.3,0,2.1),0.075,4.2,metal,vertices=28)
    cube("SignalHousing",(2.3,-0.08,4.10),(0.42,0.28,1.15),metal,0.055)
    for z,mat in ((4.43,red),(4.10,amber),(3.77,green)):
        cyl("SignalLens",(2.3,-0.235,z),0.12,0.055,mat,rot=(math.radians(90),0,0),vertices=28)
    export_asset("street_props")

builders = [
    build_sport_sedan,
    build_modern_building,
    build_brick_building,
    build_garage,
    build_gas_station,
    build_street_props,
]

manifest = {"generator":"Blender 5.2 LTS","assets":[]}
for fn in builders:
    fn()
    name = fn.__name__.replace("build_","")
    manifest["assets"].append(name)

(ROOT / "assets" / "models" / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print("BLENDER_ASSET_BUILD_COMPLETE")
