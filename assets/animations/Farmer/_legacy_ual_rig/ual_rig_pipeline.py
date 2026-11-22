"""
ual_rig_pipeline.py  --  Terra Bela Farm  --  padrão de rig de personagens

Pega uma malha estática (ex.: saída do TRELLIS), encaixa o esqueleto padrão da
Universal Animation Library (Quaternius, 65 ossos), calcula pesos de skinning,
retargeta TODAS as animações da UAL para o personagem e exporta um .glb pronto
para o Godot 4.

Uso (Blender 4.2+ / 5.x):
    blender -b -P ual_rig_pipeline.py -- config.json
ou, dentro do Blender (aba Scripting / MCP):
    import json; exec(open(r"...\\ual_rig_pipeline.py").read()); run(json.load(open(r"...\\config.json")))

config.json (ver Farmer/farmer_pipeline_config.json):
    name          nome do personagem (vira prefixo: <Name>_Armature, <Name>_Mesh)
    mesh          .glb/.gltf da malha (A-pose ou T-pose, de pé, olhando para -Y no Blender)
    ual           caminho do UAL1_Standard.glb (versão sem root motion)
    out_dir       pasta de saída (cria <name>.glb, <name>_rig.blend, textures/)
    landmarks     dict de pontos-chave do corpo (lado esquerdo = +X). Ver LANDMARK_KEYS
    fix_baked_back_shading   true para corrigir costas escuras de texturas TRELLIS
    clean_scene   true (padrão em -b) limpa a cena antes
    save_blend    true (padrão) salva <name>_rig.blend
"""
import bpy, sys, os, json, re, math
import numpy as np
import bmesh
from mathutils import Vector, Matrix

# ----------------------------------------------------------------------------
# PADRÃO DE OSSOS (ver RIG_STANDARD.md) -- igual à UAL, exceto Head -> head
# ----------------------------------------------------------------------------
UAL_TO_STD = {"Head": "head"}
STD_TO_UAL = {v: k for k, v in UAL_TO_STD.items()}
DEFORM = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
          "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
          "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
          "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
ARM_CHAIN = re.compile(r"^(clavicle|upperarm|lowerarm|hand|index|middle|ring|pinky|thumb)_")
LANDMARK_KEYS = ["pelvis", "neck_base", "head_base", "head_top", "clav_head", "shoulder", "elbow",
                 "wrist", "hand_tip", "hip", "knee", "ankle", "ball", "toe"]


def _std(n):  return UAL_TO_STD.get(n, n)
def _ual(n):  return STD_TO_UAL.get(n, n)
def _depth(b):
    d = 0
    while b.parent:
        b = b.parent; d += 1
    return d


# ----------------------------------------------------------------------------
def import_ual(path):
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new_o = [o for o in bpy.data.objects if o not in before_o]
    src = next(o for o in new_o if o.type == 'ARMATURE')
    for o in new_o:                       # só o armature de origem interessa
        if o != src:
            bpy.data.objects.remove(o, do_unlink=True)
    acts = [a for a in bpy.data.actions if a not in before_a]
    src.name = "UAL_Source"
    src.hide_set(True)
    return src, acts


def import_mesh(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    if not meshes:
        raise RuntimeError("nenhuma malha em " + path)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    if len(meshes) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for o in meshes: o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active if len(meshes) > 1 else meshes[0]
    for o in new:
        if o != mesh and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    mesh.name = mesh.data.name = f"{name}_Mesh"
    minz = min(v.co.z for v in mesh.data.vertices)          # pés em z = 0
    for v in mesh.data.vertices:
        v.co.z -= minz
    if mesh.data.materials:
        mesh.data.materials[0].name = f"{name}_Mat"
        bsdf = mesh.data.materials[0].node_tree.nodes.get("Principled BSDF")
        if bsdf:                                            # TRELLIS exporta metallic=1 -> fica "metal escuro" no Godot
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.85
    return mesh


# ----------------------------------------------------------------------------
def build_rig(src, lm_cfg, name):
    LM = {k: Vector(v) for k, v in lm_cfg.items()}
    missing = [k for k in LANDMARK_KEYS if k not in LM]
    if missing:
        raise RuntimeError("landmarks faltando: %s" % missing)
    U = {b.name: (Vector(b.head_local), Vector(b.tail_local)) for b in src.data.bones}

    def torso_map(p):
        z0, z1 = U["pelvis"][0].z, U["neck_01"][0].z
        t = (p.z - z0) / (z1 - z0)
        base = LM["pelvis"].lerp(LM["neck_base"], t)
        return Vector((base.x + p.x * 0.5, base.y + (p.y - U["pelvis"][0].y) * 0.3, base.z))

    wr_u = U["hand_l"][0]
    R3 = Vector((1, 0, 0)).rotation_difference((LM["hand_tip"] - LM["wrist"]).normalized()).to_matrix()
    s_h = (LM["hand_tip"] - LM["wrist"]).length / 0.21
    arm_map = lambda p: LM["wrist"] + s_h * (R3 @ (p - wr_u))

    target = {}
    for n, (h, t) in U.items():
        base, side = n, 1
        if n.endswith("_r"):
            base, side = n[:-2] + "_l", -1
        hh, tt = U[base]
        if base == "root": H, T = Vector((0, 0, 0)), Vector((0, 0.10, 0))
        elif base == "pelvis": H, T = LM["pelvis"], torso_map(tt)
        elif base in ("spine_01", "spine_02", "spine_03"): H, T = torso_map(hh), torso_map(tt)
        elif base == "neck_01": H, T = LM["neck_base"], LM["head_base"]
        elif base == "Head": H, T = LM["head_base"], LM["head_top"]
        elif base == "clavicle_l": H, T = LM["clav_head"], LM["shoulder"]
        elif base == "upperarm_l": H, T = LM["shoulder"], LM["elbow"]
        elif base == "lowerarm_l": H, T = LM["elbow"], LM["wrist"]
        elif base == "hand_l": H, T = LM["wrist"], arm_map(tt)
        elif any(k in base for k in ("index", "middle", "ring", "pinky", "thumb")): H, T = arm_map(hh), arm_map(tt)
        elif base == "thigh_l": H, T = LM["hip"], LM["knee"]
        elif base == "calf_l": H, T = LM["knee"], LM["ankle"]
        elif base == "foot_l": H, T = LM["ankle"], LM["ball"]
        elif base == "ball_l": H, T = LM["ball"], LM["toe"]
        elif base == "ball_leaf_l": H, T = LM["toe"], LM["toe"] + Vector((0, -0.04, 0))
        else: raise RuntimeError("osso sem mapeamento: " + n)
        if side == -1:
            H = Vector((-H.x, H.y, H.z)); T = Vector((-T.x, T.y, T.z))
        target[n] = (H, T)

    arm_data = src.data.copy(); arm_data.name = f"{name}_Skeleton"
    rig = bpy.data.objects.new(f"{name}_Armature", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm_data.edit_bones: b.use_connect = False
    for n, (H, T) in target.items():
        b = arm_data.edit_bones[n]
        b.head = H; b.tail = T if (T - H).length > 1e-4 else H + Vector((0, 0, 0.01)); b.roll = 0
    bpy.ops.object.mode_set(mode='OBJECT')
    if "Head" in arm_data.bones:
        arm_data.bones["Head"].name = "head"          # padrão: tudo minúsculo
    rig.data.display_type = 'OCTAHEDRAL'
    return rig


# ----------------------------------------------------------------------------
def skin(mesh, rig):
    bones = rig.data.bones
    seg = {n: (np.array(bones[n].head_local), np.array(bones[n].tail_local)) for n in DEFORM}
    for s in "lr":
        seg[f"hand_{s}"] = (seg[f"hand_{s}"][0], np.array(bones[f"middle_04_leaf_{s}"].tail_local))
        seg[f"ball_{s}"] = (seg[f"ball_{s}"][0], np.array(bones[f"ball_leaf_{s}"].tail_local))
    co = np.array([v.co[:] for v in mesh.data.vertices]); N = len(co)

    def dist(P, a, b):
        ab = b - a; t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
        return np.linalg.norm(P - (a + np.outer(t, ab)), axis=1)

    D = np.stack([dist(co, *seg[n]) for n in DEFORM], 1)
    bias = np.ones(len(DEFORM))
    for i, n in enumerate(DEFORM):
        if n.startswith("clavicle"): bias[i] = 0.5
        if n == "neck_01": bias[i] = 0.6
    Wt = bias / np.power(D + 0.012, 4)
    for i, n in enumerate(DEFORM):                      # lado esquerdo/direito
        if n.endswith("_l"): Wt[co[:, 0] < -0.01, i] *= 0.02
        if n.endswith("_r"): Wt[co[:, 0] > 0.01, i] *= 0.02
    Wt /= Wt.sum(1, keepdims=True)

    bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
    nbr = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    isl = -np.ones(N, int); k = 0
    for s in range(N):
        if isl[s] >= 0: continue
        st = [s]; isl[s] = k
        while st:
            x = st.pop()
            for y in nbr[x]:
                if isl[y] < 0: isl[y] = k; st.append(y)
        k += 1
    bm.free()
    for i in range(k):                                  # ilhas pequenas (botões, olhos) = peças rígidas
        m = np.where(isl == i)[0]
        if len(m) < 600 and np.linalg.norm(co[m].max(0) - co[m].min(0)) < 0.10 * max(1.0, co[:, 2].max()):
            Wt[m] = Wt[m].mean(0)
    for _ in range(3):                                  # suavização no grafo
        Wn = Wt.copy()
        for v in range(N):
            if nbr[v]: Wn[v] = 0.6 * Wt[v] + 0.4 * Wt[nbr[v]].mean(0)
        Wt = Wn
    idx = np.argsort(-Wt, 1)[:, :4]                     # máx. 4 influências (glTF/Godot)
    out = np.zeros_like(Wt)
    for v in range(N): out[v, idx[v]] = Wt[v, idx[v]]
    out /= out.sum(1, keepdims=True)

    mesh.vertex_groups.clear()
    vgs = {n: mesh.vertex_groups.new(name=n) for n in DEFORM}
    for i, n in enumerate(DEFORM):
        for v in np.where(out[:, i] > 0.002)[0]:
            vgs[n].add([int(v)], float(out[v, i]), 'REPLACE')
    for m in list(mesh.modifiers): mesh.modifiers.remove(m)
    mod = mesh.modifiers.new("Armature", "ARMATURE"); mod.object = rig
    mesh.parent = rig
    mesh.matrix_parent_inverse = rig.matrix_world.inverted()


# ----------------------------------------------------------------------------
def fix_baked_back_shading(mesh, out_dir):
    """Texturas TRELLIS saem ~3-4x mais escuras nas costas (iluminação 'assada').
    Ganho por texel em função da normal Y da face (frente=1x, costas=razão medida). Guarda o original."""
    mat = mesh.data.materials[0]
    node = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    img = node.image
    tex = os.path.join(out_dir, "textures"); os.makedirs(tex, exist_ok=True)
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    me = mesh.data; uv = me.uv_layers[0].data; me.calc_loop_triangles()
    ny = np.zeros((H, W), np.float32); cov = np.zeros((H, W), np.float32)
    for lt in me.loop_triangles:
        pts = np.array([np.array(uv[l].uv) for l in lt.loops]) * [W - 1, H - 1]
        x0, y0 = np.maximum(np.floor(pts.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(pts.max(0)).astype(int), [W - 1, H - 1])
        if x1 < x0 or y1 < y0: continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        P = np.stack([xs, ys], -1).reshape(-1, 2).astype(np.float32)
        v0 = pts[1] - pts[0]; v1 = pts[2] - pts[0]; v2 = P - pts[0]; d = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(d) < 1e-9: continue
        u = (v2[:, 0] * v1[1] - v1[0] * v2[:, 1]) / d; v = (v0[0] * v2[:, 1] - v2[:, 0] * v0[1]) / d
        Q = P[(u >= -0.03) & (v >= -0.03) & (u + v <= 1.03)].astype(int)
        ny[Q[:, 1], Q[:, 0]] = lt.normal.y; cov[Q[:, 1], Q[:, 0]] = 1
    lin = np.power(np.clip(px[..., :3], 0, 1), 2.2)
    L = 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]
    ratio = float(L[(cov == 1) & (ny < -0.35)].mean() / max(L[(cov == 1) & (ny > 0.35)].mean(), 1e-6))
    if ratio < 1.3:
        return {"applied": False, "ratio": ratio}
    img.filepath_raw = os.path.join(tex, f"{mesh.name[:-5].lower()}_basecolor_original.png")
    img.file_format = 'PNG'; img.save()
    t = np.clip((ny + 0.5) / 1.0, 0, 1); t = t * t * (3 - 2 * t)
    gain = np.power(ratio, t).astype(np.float32)

    def box(a, r):
        k = 2 * r + 1
        c = np.cumsum(np.pad(a, ((r + 1, r), (0, 0)), mode='edge'), 0); a = (c[k:] - c[:-k]) / k
        c = np.cumsum(np.pad(a, ((0, 0), (r + 1, r)), mode='edge'), 1); return (c[:, k:] - c[:, :-k]) / k
    num = box(box(gain * cov, 8), 8); den = box(box(cov, 8), 8) + 1e-6
    gain = np.where(cov == 1, gain, np.where(den > 1e-3, num / den, 1.0)).astype(np.float32)
    new = lin * gain[..., None]
    th = 0.8; new = np.where(new > th, th + (1 - th) * np.tanh((new - th) / (1 - th)), new)
    px[..., :3] = np.power(np.clip(new, 0, 1), 1 / 2.2)
    img.pixels = px.reshape(-1).tolist()
    final = os.path.join(tex, f"{mesh.name[:-5].lower()}_basecolor.png")
    img.filepath_raw = final; img.file_format = 'PNG'; img.save()
    fresh = bpy.data.images.load(final)                 # recarrega do arquivo (sem packed antigo)
    node.image = fresh
    return {"applied": True, "ratio": ratio}


# ----------------------------------------------------------------------------
def retarget_all(src, ual_actions, rig, name):
    sc = bpy.context.scene
    order = sorted(rig.data.bones, key=_depth)
    rest_f = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    rest_u = {b.name: b.matrix_local.copy() for b in src.data.bones}
    ratio = rest_f["pelvis"].translation.z / rest_u["pelvis"].translation.z
    idle = next(a for a in ual_actions if a.name.split(".")[0] == "Idle_Loop")
    if src.animation_data is None: src.animation_data_create()
    src.animation_data.action = idle; sc.frame_set(0)
    eu = src.evaluated_get(bpy.context.evaluated_depsgraph_get())
    ref3 = {b.name: eu.pose.bones[b.name].matrix.to_3x3().copy() for b in src.data.bones}
    if rig.animation_data is None: rig.animation_data_create()
    for tr in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(tr)
    made = []
    for ua in sorted(ual_actions, key=lambda a: a.name):
        base = ua.name.split(".")[0]
        src.animation_data.action = ua
        f0, f1 = int(round(ua.frame_range[0])), int(round(ua.frame_range[1]))
        act = bpy.data.actions.new(f"{name}_{base}")
        rig.animation_data.action = act
        prev = {}
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            eu = src.evaluated_get(bpy.context.evaluated_depsgraph_get())
            Rt = {}
            for b in order:
                n = b.name; un = _ual(n); pu = eu.pose.bones[un].matrix
                if ARM_CHAIN.match(n):     # braços: pose absoluta relativa à pose neutra (Idle f0) -> funciona A-pose x T-pose
                    Rt[n] = pu.to_3x3() @ ref3[un].inverted() @ rest_f[n].to_3x3()
                else:                      # resto: delta em relação ao rest
                    Rt[n] = (pu.to_3x3() @ rest_u[un].to_3x3().inverted()) @ rest_f[n].to_3x3()
                pb = rig.pose.bones[n]
                if b.parent is None:
                    B3 = rest_f[n].to_3x3().inverted() @ Rt[n]
                else:
                    pn = b.parent.name
                    rel = rest_f[pn].to_3x3().inverted() @ rest_f[n].to_3x3()
                    B3 = rel.inverted() @ Rt[pn].inverted() @ Rt[n]
                q = B3.to_quaternion()
                if n in prev: q.make_compatible(prev[n])
                prev[n] = q; pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=n)
                if n == "pelvis":          # bob do quadril, escalado pela razão de altura
                    T = rest_f[n].translation + (pu.translation - rest_u[un].translation) * ratio
                    M = Matrix.Translation(T) @ Rt[n].to_4x4()
                    pb.location = (rest_f[n].inverted() @ M).translation
                    pb.keyframe_insert("location", frame=f, group=n)
        act.use_fake_user = True
        made.append((base, act))
    rig.animation_data.action = None
    for base, act in made:
        tr = rig.animation_data.nla_tracks.new(); tr.name = base
        st = tr.strips.new(base, int(act.frame_range[0]), act); st.name = base
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    return [b for b, _ in made]


def export_glb(rig, mesh, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in (rig, mesh): o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=False,
        export_yup=True, export_skins=True, export_def_bones=False, export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_optimize_animation_size=True,
        export_normals=True, export_tangents=False, export_texcoords=True, export_materials='EXPORT',
        export_image_format='AUTO', export_cameras=False, export_lights=False, export_all_influences=False)


def run(cfg):
    name = cfg["name"]; out_dir = cfg["out_dir"]; os.makedirs(out_dir, exist_ok=True)
    if cfg.get("clean_scene", bpy.app.background):
        bpy.ops.wm.read_homefile(use_empty=True)
    bpy.context.scene.render.fps = 24
    src, ual_actions = import_ual(cfg["ual"])
    mesh = import_mesh(cfg["mesh"], name)
    rig = build_rig(src, cfg["landmarks"], name)
    skin(mesh, rig)
    tex = {"applied": False}
    if cfg.get("fix_baked_back_shading"):
        tex = fix_baked_back_shading(mesh, out_dir)
    names = retarget_all(src, ual_actions, rig, name)
    glb = os.path.join(out_dir, f"{name.lower()}.glb")
    export_glb(rig, mesh, glb)
    if cfg.get("save_blend", True):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, f"{name.lower()}_rig.blend"), compress=True)
    return {"glb": glb, "bones": len(rig.data.bones), "animations": len(names), "texture_fix": tex}


if __name__ == "__main__" and "--" in sys.argv:
    cfg_path = sys.argv[sys.argv.index("--") + 1]
    print(run(json.load(open(cfg_path, encoding="utf-8"))))
