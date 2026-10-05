import bpy
import math
import os
from mathutils import Vector

# ------------------------------------------------------------
# Cinematic realtime trailer: "Der erste Blick"
# Standard Blender bpy only. No external add-ons or assets.
# ------------------------------------------------------------

FPS = 24
END = 288  # 12 seconds

# ---------- scene reset ----------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                   bpy.data.cameras, bpy.data.lights):
    # Keep cleanup conservative; orphan purge later.
    pass

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = END
scene.render.fps = FPS
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 50
os.makedirs('/tmp/dog_frames', exist_ok=True)
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'
scene.render.filepath = '/tmp/dog_frames/frame_'
scene.render.film_transparent = False

world = bpy.data.worlds.new('CinemaWorld') if not bpy.data.worlds else bpy.data.worlds[0]
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get('Background')
bg.inputs['Color'].default_value = (0.008, 0.012, 0.028, 1)
bg.inputs['Strength'].default_value = 0.20

# ---------- helpers ----------
def mat(name, color, metallic=0.0, rough=0.5, emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = color
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = rough
    if emission is not None:
        if 'Emission Color' in bs.inputs:
            bs.inputs['Emission Color'].default_value = emission
            bs.inputs['Emission Strength'].default_value = emission_strength
        elif 'Emission' in bs.inputs:
            bs.inputs['Emission'].default_value = emission
    return m

def add_cube(name, loc, scale, material=None, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new('Soft edges', 'BEVEL')
        b.width = bevel
        b.segments = 3
    if material:
        o.data.materials.append(material)
    return o

def add_sphere(name, loc, scale, material=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    if material:
        o.data.materials.append(material)
    return o

def add_cylinder(name, loc, radius, depth, material=None, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    if material:
        o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return o

def add_text(name, text, loc, size, material, extrude=0.02, align='CENTER'):
    bpy.ops.object.text_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.data.body = text
    o.data.align_x = align
    o.data.align_y = 'CENTER'
    o.data.size = size
    o.data.extrude = extrude
    o.data.bevel_depth = 0.006
    o.data.materials.append(material)
    return o

def key(obj, frame, location=None, rotation=None, scale=None):
    if location is not None:
        obj.location = location
        obj.keyframe_insert('location', frame=frame)
    if rotation is not None:
        obj.rotation_euler = rotation
        obj.keyframe_insert('rotation_euler', frame=frame)
    if scale is not None:
        obj.scale = scale
        obj.keyframe_insert('scale', frame=frame)

def linearize(obj):
    # Blender 5.x stores animation data in layered Actions.
    # Default keyframe interpolation is already smooth enough for the trailer.
    return

def make_target(name, loc):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=loc)
    t = bpy.context.object
    t.name = name
    return t

def make_camera(name, loc, target_loc, lens=50):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.name = name
    cam.data.lens = lens
    cam.data.sensor_width = 36
    target = make_target(name + '_Target', target_loc)
    c = cam.constraints.new(type='TRACK_TO')
    c.target = target
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'
    return cam, target

def parent_text_to_camera(cam, name, text, y, z, size, start, end):
    white = bpy.data.materials.get('TitleWhite')
    o = add_text(name, text, (0,0,0), size, white, 0.008)
    o.parent = cam
    o.location = (0, y, z)
    o.rotation_euler = (0,0,0)
    o.scale = (0,0,0)
    o.keyframe_insert('scale', frame=max(1,start-2))
    o.scale = (1,1,1)
    o.keyframe_insert('scale', frame=start)
    o.keyframe_insert('scale', frame=end)
    o.scale = (0,0,0)
    o.keyframe_insert('scale', frame=min(END,end+2))
    return o

# ---------- materials ----------
floor_m = mat('Floor', (0.055,0.065,0.075,1), 0.08, 0.40)
wall_m = mat('Wall', (0.12,0.13,0.15,1), 0.02, 0.62)
metal_m = mat('Metal', (0.035,0.04,0.05,1), 0.82, 0.22)
glass_m = mat('GlassTint', (0.035,0.08,0.12,1), 0.2, 0.08)
wood_m = mat('WarmWood', (0.18,0.065,0.025,1), 0.02, 0.48)
skin_m = mat('Skin', (0.58,0.31,0.20,1), 0.0, 0.56)
coat_m = mat('Coat', (0.035,0.045,0.065,1), 0.0, 0.68)
pants_m = mat('Pants', (0.025,0.028,0.035,1), 0.0, 0.78)
shoe_m = mat('Shoes', (0.01,0.012,0.015,1), 0.1, 0.62)
dog_m = mat('GoldenFur', (0.55,0.23,0.055,1), 0.0, 0.78)
dog_dark = mat('DogDark', (0.055,0.025,0.012,1), 0.0, 0.60)
white_m = mat('TitleWhite', (0.92,0.94,1.0,1), 0.0, 0.26, emission=(0.92,0.94,1.0,1), emission_strength=1.25)
warm_light_m = mat('WarmGlow', (1.0,0.35,0.08,1), 0.0, 0.20, emission=(1.0,0.28,0.06,1), emission_strength=5.0)
blue_light_m = mat('BlueGlow', (0.05,0.18,0.9,1), 0.0, 0.20, emission=(0.05,0.18,1.0,1), emission_strength=3.5)

# ---------- environment: animal shelter ----------
add_cube('Ground', (0,0,-0.12), (10,10,0.12), floor_m, 0.02)
add_cube('BackWall', (0,6,2.6), (10,0.16,2.7), wall_m)
add_cube('LeftWall', (-10,0,2.6), (0.16,6.2,2.7), wall_m)
add_cube('RightWall', (10,0,2.6), (0.16,6.2,2.7), wall_m)
add_cube('Ceiling', (0,0,5.35), (10,6.2,0.12), wall_m)

# Entrance frame & glowing sign
add_cube('EntranceTop', (0,-5.8,4.6), (3.5,0.20,0.25), metal_m)
add_cube('EntranceL', (-3.25,-5.8,2.25), (0.25,0.20,2.2), metal_m)
add_cube('EntranceR', (3.25,-5.8,2.25), (0.25,0.20,2.2), metal_m)
sign = add_text('ShelterSign', 'SECOND CHANCE', (0,-6.05,4.75), 0.50, white_m, 0.025)
sign.rotation_euler = (math.radians(90),0,0)

# Desk and warm practical lights
add_cube('Desk', (-4.7,-1.3,0.75), (1.75,0.55,0.75), wood_m)
for x in (-5.4,-4.0):
    add_sphere('DeskLamp', (x,-1.3,2.25), (0.16,0.16,0.16), warm_light_m)

# Kennels on right
for k, y in enumerate((-0.7, 2.1, 4.7)):
    add_cube(f'KennelBack{k}', (6.9,y,1.55), (2.6,0.09,1.55), wall_m)
    add_cube(f'KennelSide{k}', (4.35,y+1.3,1.55), (0.09,1.3,1.55), wall_m)
    for i in range(8):
        x = 4.65 + i*0.64
        add_cylinder(f'Bars{k}_{i}', (x,y-1.22,1.6), 0.028, 3.1, metal_m)

# Accent lights and area lighting
bpy.ops.object.light_add(type='AREA', location=(0,-1,4.7))
key_light = bpy.context.object
key_light.data.energy = 1200
key_light.data.shape = 'RECTANGLE'
key_light.data.size = 8
key_light.data.size_y = 4
key_light.data.color = (1.0,0.48,0.26)

bpy.ops.object.light_add(type='AREA', location=(5,1.7,3.5))
fill = bpy.context.object
fill.data.energy = 900
fill.data.size = 5
fill.data.color = (0.16,0.30,1.0)
fill.rotation_euler = (math.radians(65),0,math.radians(90))

bpy.ops.object.light_add(type='AREA', location=(0,-5.5,3.0))
entrance_light = bpy.context.object
entrance_light.data.energy = 1100
entrance_light.data.size = 5
entrance_light.data.color = (0.35,0.55,1.0)
entrance_light.rotation_euler = (math.radians(90),0,0)

# ---------- character rigs made from parented primitives ----------
def make_man(name, base_loc):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=base_loc)
    root = bpy.context.object
    root.name = name

    torso = add_cylinder(name+'_Torso', (0,0,1.55), 0.34, 0.90, coat_m)
    torso.parent = root
    head = add_sphere(name+'_Head', (0,0,2.25), (0.27,0.27,0.30), skin_m)
    head.parent = root

    for side, x in (('L',-0.43),('R',0.43)):
        arm = add_cylinder(name+'_Arm'+side, (x,0,1.45), 0.11, 0.82, coat_m)
        arm.parent = root
        leg = add_cylinder(name+'_Leg'+side, (x*0.55,0,0.60), 0.13, 0.95, pants_m)
        leg.parent = root
        shoe = add_cube(name+'_Shoe'+side, (x*0.55,-0.12,0.10), (0.16,0.27,0.10), shoe_m, 0.04)
        shoe.parent = root

    return root

def make_dog(name, base_loc, material=dog_m):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=base_loc)
    root = bpy.context.object
    root.name = name

    body = add_sphere(name+'_Body', (0,0,0.66), (0.55,0.80,0.42), material)
    body.parent = root
    chest = add_sphere(name+'_Chest', (0,-0.55,0.78), (0.40,0.42,0.46), material)
    chest.parent = root
    head = add_sphere(name+'_Head', (0,-0.98,1.22), (0.39,0.40,0.37), material)
    head.parent = root
    muzzle = add_sphere(name+'_Muzzle', (0,-1.31,1.14), (0.25,0.26,0.19), material)
    muzzle.parent = root
    nose = add_sphere(name+'_Nose', (0,-1.52,1.18), (0.11,0.10,0.09), dog_dark)
    nose.parent = root

    for side, x in (('L',-0.23),('R',0.23)):
        ear = add_sphere(name+'_Ear'+side, (x,-1.06,1.34), (0.16,0.12,0.30), dog_dark)
        ear.rotation_euler = (math.radians(22), 0, math.radians(16 if side=='L' else -16))
        ear.parent = root
        for yy in (-0.37,0.48):
            leg = add_cylinder(name+f'_Leg{side}{yy}', (x,yy,0.30), 0.09, 0.55, material)
            leg.parent = root

    tail = add_cylinder(name+'_Tail', (0,0.76,0.87), 0.08, 0.80, material, rot=(math.radians(55),0,0))
    tail.parent = root
    return root, head, tail

man = make_man('Man', (0,-9.8,0))
dog, dog_head, dog_tail = make_dog('ChosenDog', (6.0,2.4,0))

# Background dogs
for i,(yy,c) in enumerate([(-0.8,(0.2,0.08,0.03,1)), (4.8,(0.62,0.60,0.55,1))]):
    dm = mat(f'DogBGMat{i}', c, 0, 0.78)
    make_dog(f'DogBG{i}', (6.3,yy,0), dm)

# Final-shot duplicates outdoors/entrance side
man_final = make_man('ManFinal', (-1.0,-7.2,0))
dog_final,_,dog_final_tail = make_dog('DogFinal', (0.7,-7.1,0))

# ---------- animation ----------
# Man enters
key(man, 1, location=(0,-10.4,0))
key(man, 70, location=(0,-4.7,0))
key(man, 120, location=(1.6,-0.1,0))
key(man, 185, location=(4.4,1.45,0))
# kneel / soften posture
key(man, 205, location=(4.4,1.45,0), rotation=(math.radians(7),0,0), scale=(1,1,1))
key(man, 245, location=(4.4,1.45,-0.52), rotation=(math.radians(10),0,0), scale=(1,1,0.82))
for child in man.children:
    if 'ArmR' in child.name:
        child.rotation_euler = (math.radians(-25),0,math.radians(-18))
        child.keyframe_insert('rotation_euler', frame=200)
        child.rotation_euler = (math.radians(-68),0,math.radians(-30))
        child.keyframe_insert('rotation_euler', frame=242)

# simple walking sway
for child in man.children:
    if 'LegL' in child.name:
        for f,a in [(1,12),(18,-12),(36,12),(54,-12),(72,8),(110,-8),(150,6)]:
            child.rotation_euler.x = math.radians(a)
            child.keyframe_insert('rotation_euler', frame=f)
    if 'LegR' in child.name:
        for f,a in [(1,-12),(18,12),(36,-12),(54,12),(72,-8),(110,8),(150,-6)]:
            child.rotation_euler.x = math.radians(a)
            child.keyframe_insert('rotation_euler', frame=f)

# Dog head lift and tail wag
dog_head.rotation_euler.x = math.radians(10)
dog_head.keyframe_insert('rotation_euler', frame=135)
dog_head.rotation_euler.x = math.radians(-9)
dog_head.keyframe_insert('rotation_euler', frame=175)
dog_head.rotation_euler.x = math.radians(-15)
dog_head.keyframe_insert('rotation_euler', frame=225)

for f,a in [(140,-20),(150,20),(160,-24),(170,24),(180,-22),(190,24),(205,-28),(220,28),(238,-25)]:
    dog_tail.rotation_euler.z = math.radians(a)
    dog_tail.keyframe_insert('rotation_euler', frame=f)

# Final shot man + dog walking away from shelter
key(man_final, 240, location=(-1.0,-7.2,0))
key(man_final, 288, location=(-2.8,-12.2,0))
key(dog_final, 240, location=(0.7,-7.1,0))
key(dog_final, 288, location=(-1.3,-12.0,0))
for f,a in [(240,-20),(248,20),(256,-25),(264,25),(272,-20),(280,20),(288,-10)]:
    dog_final_tail.rotation_euler.z = math.radians(a)
    dog_final_tail.keyframe_insert('rotation_euler', frame=f)

# ---------- cameras / shots ----------
cam1,t1 = make_camera('Cam01_Establish', (0,-17.5,3.1), (0,-5.8,2.0), 48)
key(cam1,1,location=(0,-17.5,3.1))
key(cam1,72,location=(0,-12.1,2.4))
key(t1,1,location=(0,-5.5,2.0))
key(t1,72,location=(0,-4.7,1.7))

cam2,t2 = make_camera('Cam02_Track', (-5.8,-4.2,2.5), (0,-1.5,1.2), 46)
key(cam2,73,location=(-5.8,-4.2,2.5))
key(cam2,132,location=(-4.2,-0.2,2.1))
key(t2,73,location=(0,-3.2,1.4))
key(t2,132,location=(2.6,0.8,1.2))

cam3,t3 = make_camera('Cam03_DogClose', (3.55,0.62,1.52), (6.0,2.35,1.10), 72)
cam3.data.dof.use_dof = True
cam3.data.dof.focus_object = dog_head
cam3.data.dof.aperture_fstop = 1.8
key(cam3,133,location=(3.55,0.62,1.52))
key(cam3,192,location=(4.15,1.10,1.42))
key(t3,133,location=(6.0,2.35,1.10))
key(t3,192,location=(6.0,2.35,1.24))

cam4,t4 = make_camera('Cam04_Connection', (1.75,0.35,1.65), (4.9,1.75,0.95), 58)
key(cam4,193,location=(1.75,0.35,1.65))
key(cam4,239,location=(2.55,0.85,1.35))
key(t4,193,location=(4.9,1.75,0.95))
key(t4,239,location=(5.25,1.95,0.90))

cam5,t5 = make_camera('Cam05_Final', (0,-4.0,2.2), (-1.0,-9.0,1.1), 50)
key(cam5,240,location=(0,-4.0,2.2))
key(cam5,288,location=(0,-5.4,2.45))
key(t5,240,location=(-0.1,-8.2,1.15))
key(t5,288,location=(-2.0,-11.5,1.15))

# Camera cuts
for f,cam in [(1,cam1),(73,cam2),(133,cam3),(193,cam4),(240,cam5)]:
    m = scene.timeline_markers.new(f'Shot_{f}', frame=f)
    m.camera = cam
scene.camera = cam1

# ---------- cinematic text ----------
parent_text_to_camera(cam1, 'T1', 'MANCHMAL SUCHT MAN...', -1.45, -4.0, 0.24, 18, 55)
parent_text_to_camera(cam3, 'T2', '...UND WIRD GEFUNDEN.', -1.50, -4.0, 0.22, 150, 185)
parent_text_to_camera(cam5, 'Title', 'DER ERSTE BLICK', 0.22, -4.0, 0.36, 252, 282)
parent_text_to_camera(cam5, 'SubTitle', 'EIN NEUER FREUND. EIN NEUES ZUHAUSE.', -0.42, -4.0, 0.15, 260, 282)

# ---------- interpolation ----------
for o in bpy.context.scene.objects:
    linearize(o)

# Smooth title scale and camera movement
scene.view_settings.look = 'AgX - Medium High Contrast'

# A subtle vignette-like frame made from dark camera-parented planes
def add_letterbox(cam):
    m = mat('Letterbox_'+cam.name, (0,0,0,1), 0, 1)
    for y in (1.62,-1.62):
        p = add_cube('Bar_'+cam.name+str(y), (0,0,0), (2.5,0.30,0.02), m, 0)
        p.parent = cam
        p.location = (0,y,-3.4)
for c in (cam1,cam2,cam3,cam4,cam5):
    add_letterbox(c)

# ---------- save + render ----------
bpy.ops.wm.save_as_mainfile(filepath='/tmp/dog_trailer_scene.blend')
print('Rendering cinematic trailer...')
bpy.ops.render.render(animation=True)
print('DONE:/tmp/dog_frames')
