"""Prepara a malha da trabalhadora: solda, limpa, decima, UV nova, bake 2048 da textura original
+ rosto da ficha projetado de frente. Saída: glb low-poly com textura + png 2048 do bake.
uso: blender -b --factory-startup -P fw_prep.py -- src.glb face.png out_dir target_tris
"""
import bpy, bmesh, sys, os, math
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index("--") + 1:]
SRC, FACE, OUT, TGT = a[0], a[1], a[2], int(a[3])
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
hi = [o for o in bpy.data.objects if o.type == 'MESH'][0]
for o in list(bpy.data.objects):
    if o != hi: bpy.data.objects.remove(o, do_unlink=True)
hi.data.transform(hi.matrix_world); hi.parent = None; hi.matrix_world = Matrix.Identity(4)
minz = min(v.co.z for v in hi.data.vertices)
hi.data.transform(Matrix.Translation((0, 0, -minz)))
hi.name = "HI"

# ---- low: cópia soldada, sem pedacinhos soltos, decimada
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = lo.data.name = "LO"
bpy.context.scene.collection.objects.link(lo)
bm = bmesh.new(); bm.from_mesh(lo.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
seen = set(); small = []
for v in bm.verts:
    if v in seen: continue
    st = [v]; comp = []; seen.add(v)
    while st:
        x = st.pop(); comp.append(x)
        for e in x.link_edges:
            o = e.other_vert(x)
            if o not in seen: seen.add(o); st.append(o)
    if len(comp) < 50: small += comp
bmesh.ops.delete(bm, geom=small, context='VERTS')
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(lo.data); bm.free()
for p in lo.data.polygons: p.use_smooth = True
tris_in = sum(len(p.vertices) - 2 for p in lo.data.polygons)
bpy.ops.object.select_all(action='DESELECT'); lo.select_set(True); bpy.context.view_layer.objects.active = lo
mod = lo.modifiers.new("Dec", "DECIMATE"); mod.ratio = TGT / tris_in
mod.use_collapse_triangulate = True; mod.use_symmetry = True; mod.symmetry_axis = 'X'
bpy.ops.object.modifier_apply(modifier=mod.name)
lo.data.calc_loop_triangles()
print("LOWPOLY", tris_in, "->", len(lo.data.loop_triangles), "verts", len(lo.data.vertices))

# ---- UV nova
while lo.data.uv_layers: lo.data.uv_layers.remove(lo.data.uv_layers[0])
lo.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=True)
try:
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
except Exception as e:
    print("pack", e)
bpy.ops.object.mode_set(mode='OBJECT')

# ---- frente do rosto (y mínimo perto do centro do rosto)
FACE_Z = 0.834; S = 0.000633
cand = [v.co for v in hi.data.vertices if abs(v.co.x) < 0.02 and abs(v.co.z - 0.80) < 0.03]
y_front = min(c.y for c in cand)
print("FACE_FRONT_Y", y_front)

# ---- material de bake no low: (cor do HI baked) + rosto projetado
size = 2048
base = bpy.data.images.new("fw_base", size, size, alpha=False)
final = bpy.data.images.new("fw_final", size, size, alpha=False)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 4; sc.cycles.device = 'CPU'
lo.data.materials.clear()
mat = bpy.data.materials.new("FW_Bake"); mat.use_nodes = True; lo.data.materials.append(mat)
nt = mat.node_tree; N = nt.nodes; L = nt.links
for n in list(N): N.remove(n)
tex_base = N.new("ShaderNodeTexImage"); tex_base.image = base
out = N.new("ShaderNodeOutputMaterial"); emi = N.new("ShaderNodeEmission")
target = N.new("ShaderNodeTexImage"); target.image = base
nt.nodes.active = target
L.new(emi.outputs[0], out.inputs[0])

# 1) bake cor difusa HI -> LO
bpy.ops.object.select_all(action='DESELECT'); hi.select_set(True); lo.select_set(True)
bpy.context.view_layer.objects.active = lo
sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = 0.012; sc.render.bake.max_ray_distance = 0.04
sc.render.bake.margin = 8
sc.render.bake.use_pass_direct = False; sc.render.bake.use_pass_indirect = False; sc.render.bake.use_pass_color = True
hm = hi.data.materials[0]; hn = hm.node_tree
htex = next(n for n in hn.nodes if n.type == 'TEX_IMAGE'); hout = next(n for n in hn.nodes if n.type == 'OUTPUT_MATERIAL')
hem = hn.nodes.new("ShaderNodeEmission"); hn.links.new(htex.outputs[0], hem.inputs[0]); hn.links.new(hem.outputs[0], hout.inputs[0])
bpy.ops.object.bake(type='EMIT', use_selected_to_active=True, cage_extrusion=0.012, max_ray_distance=0.04, margin=8)
base.filepath_raw = os.path.join(OUT, "fw_base_2048.png"); base.file_format = 'PNG'; base.save()
print("BAKED base")

# 2) emissão = base mix rosto (máscara elíptica, só na frente do rosto)
face = bpy.data.images.load(FACE)
fw, fh = face.size
geo = N.new("ShaderNodeNewGeometry")
sep = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Position"], sep.inputs[0])
def math_node(op, a_, b_):
    m = N.new("ShaderNodeMath"); m.operation = op
    for i, v in enumerate((a_, b_)):
        if isinstance(v, (int, float)): m.inputs[i].default_value = v
        else: L.new(v, m.inputs[i])
    return m.outputs[0]
# uv do recorte do rosto: px = 245 + x/S ; py = 162 + (FACE_Z - z)/S  (recorte 480x440)
EX, EY = 245.0, 162.0
u = math_node('ADD', math_node('MULTIPLY', sep.outputs[0], 1.0 / (S * fw)), EX / fw)
v = math_node('SUBTRACT', 1.0 - EY / fh - FACE_Z / (S * fh), math_node('MULTIPLY', sep.outputs[2], -1.0 / (S * fh)))
comb = N.new("ShaderNodeCombineXYZ"); L.new(u, comb.inputs[0]); L.new(v, comb.inputs[1])
tex_face = N.new("ShaderNodeTexImage"); tex_face.image = face; tex_face.interpolation = 'Cubic'; tex_face.extension = 'EXTEND'
L.new(comb.outputs[0], tex_face.inputs[0])
# máscara: elipse centrada em (0, ZC)
ZC, RX, RZ = 0.809, 0.062, 0.064
ex = math_node('DIVIDE', sep.outputs[0], RX)
ez = math_node('DIVIDE', math_node('SUBTRACT', sep.outputs[2], ZC), RZ)
r2 = math_node('ADD', math_node('MULTIPLY', ex, ex), math_node('MULTIPLY', ez, ez))
ell = math_node('SUBTRACT', 1.0, math_node('MINIMUM', 1.0, math_node('MAXIMUM', math_node('DIVIDE', math_node('SUBTRACT', r2, 0.55), 0.45), 0.0)))
front = math_node('LESS_THAN', sep.outputs[1], y_front + 0.035)
nrm = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Normal"], nrm.inputs[0])
facing = math_node('LESS_THAN', nrm.outputs[1], -0.15)
mask = math_node('MULTIPLY', math_node('MULTIPLY', ell, front), facing)
mix = N.new("ShaderNodeMix"); mix.data_type = 'RGBA'
L.new(mask, mix.inputs[0]); L.new(tex_base.outputs[0], mix.inputs[6]); L.new(tex_face.outputs[0], mix.inputs[7])
L.new(mix.outputs[2], emi.inputs[0])
target.image = final; nt.nodes.active = target
bpy.ops.object.select_all(action='DESELECT'); lo.select_set(True); bpy.context.view_layer.objects.active = lo
sc.render.bake.use_selected_to_active = False
bpy.ops.object.bake(type='EMIT')
final.filepath_raw = os.path.join(OUT, "fw_final_2048.png"); final.file_format = 'PNG'; final.save()
print("BAKED final")

# ---- material final simples e export do low
for n in list(N): N.remove(n)
bsdf = N.new("ShaderNodeBsdfPrincipled"); out = N.new("ShaderNodeOutputMaterial")
t = N.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(OUT, "fw_final_2048.png"))
L.new(t.outputs[0], bsdf.inputs["Base Color"]); L.new(bsdf.outputs[0], out.inputs[0])
bsdf.inputs["Metallic"].default_value = 0.0; bsdf.inputs["Roughness"].default_value = 0.85
mat.name = "FW_Mat"
bpy.data.objects.remove(hi, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT'); lo.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "fw_lowpoly.glb"), export_format='GLB', use_selection=True,
                          export_yup=True, export_animations=False, export_image_format='AUTO')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "fw_prep.blend"), compress=True)
print("DONE")
