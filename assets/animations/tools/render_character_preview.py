"""
render_character_preview.py -- folha de contato das animações de um personagem rigado (Terra Bela Farm)

blender -b <personagem>_rigify.blend -P render_character_preview.py -- <saida.png> <Anim1,Anim2,...> [quadros_por_anim] [vista]
vista: front | three_quarter (padrão) | side | back
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
anims = args[1].split(",")
per = int(args[2]) if len(args) > 2 else 4
view = args[3] if len(args) > 3 else "three_quarter"
TILE = 320

sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name.endswith("_Rigify"))
mesh = next(o for o in bpy.data.objects if o.type == 'MESH' and o.name.endswith("_Mesh"))
for o in bpy.data.objects:
    o.hide_render = o is not mesh
for tr in rig.animation_data.nla_tracks:
    tr.mute = True

# câmera / luzes
cam_data = bpy.data.cameras.new("PrevCam"); cam_data.type = 'ORTHO'; cam_data.ortho_scale = 1.25
cam = bpy.data.objects.new("PrevCam", cam_data); sc.collection.objects.link(cam)
az = {"front": 0, "three_quarter": 35, "side": 90, "back": 180}[view]
r = 3.0; a = math.radians(az)
cam.location = (r * math.sin(a), -r * math.cos(a), 0.75)
d = Vector((0, 0, 0.5)) - cam.location
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
for nm, rot, e in (("Key", (50, 0, 30), 3.0), ("Fill", (60, 0, -120), 1.2), ("Rim", (60, 0, 180), 1.5)):
    ld = bpy.data.lights.new(nm, 'SUN'); ld.energy = e
    lo = bpy.data.objects.new(nm, ld); lo.rotation_euler = [math.radians(x) for x in rot]; sc.collection.objects.link(lo)
w = bpy.data.worlds.new("PrevWorld"); sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.78, 0.84, 0.74, 1); bg.inputs[1].default_value = 0.6
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = sc.render.resolution_y = TILE
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Standard'
# chão
bpy.ops.mesh.primitive_plane_add(size=3)
fl = bpy.context.object; fl.hide_render = False
fm = bpy.data.materials.new("Floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.62, 0.45, 1)
fl.data.materials.append(fm)

rows = []
tmp = os.path.join(os.path.dirname(out), "_tile.png")
for an in anims:
    act = bpy.data.actions.get("RIG_" + an) or bpy.data.actions.get(an)
    rig.animation_data.action = act
    if hasattr(rig.animation_data, "action_slot") and act.slots:
        rig.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    row = []
    for i in range(per):
        f = int(round(f0 + (f1 - f0) * i / per))
        sc.frame_set(f)
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(TILE, TILE, 4)
        bpy.data.images.remove(img)
        row.append(px)
    rows.append(np.concatenate(row, axis=1))
sheet = np.concatenate(rows[::-1], axis=0)   # pixels do Blender começam embaixo
H, W = sheet.shape[:2]
im = bpy.data.images.new("sheet", W, H)
im.pixels = sheet.reshape(-1).tolist()
im.filepath_raw = out; im.file_format = 'PNG'; im.save()
os.remove(tmp)
print("SHEET", out, W, H)
