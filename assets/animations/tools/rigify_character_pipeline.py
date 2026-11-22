"""
rigify_character_pipeline.py  --  Terra Bela Farm  --  pipeline de personagem com Rigify

Malha estática (ex.: TRELLIS) -> malha limpa e otimizada p/ mobile -> metarig Rigify encaixado
por landmarks -> rig Rigify gerado -> skin (bone heat, máx. 4 influências) -> esqueleto de jogo
com nomes padronizados (RIG_STANDARD.md) dirigido pelos ossos DEF do Rigify -> retarget das
animações da Universal Animation Library (UAL) para os controles FK do Rigify -> bake no esqueleto
de jogo -> .glb para o Godot 4.

Uso:
    blender -b --factory-startup -P rigify_character_pipeline.py -- config.json [stage]
stage (opcional, p/ depuração): mesh | rig | skin | anim | all (padrão)

Ver Farmer/farmer_rigify_config.json e ../RIG_STANDARD.md.
"""
import bpy, bmesh, sys, os, json, math, addon_utils
from mathutils import Vector, Matrix, Quaternion

# ---------------------------------------------------------------------------
# Convenção de nomes: osso DEF do Rigify -> nome padrão do jogo (= nomes da UAL)
# ---------------------------------------------------------------------------
DEF_TO_STD = {
    "DEF-spine": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02",
    "DEF-spine.003": "spine_03", "DEF-spine.004": "neck_01", "DEF-spine.005": "head",
}
for _s, _x in (("L", "l"), ("R", "r")):
    DEF_TO_STD.update({
        f"DEF-shoulder.{_s}": f"clavicle_{_x}", f"DEF-upper_arm.{_s}": f"upperarm_{_x}",
        f"DEF-forearm.{_s}": f"lowerarm_{_x}", f"DEF-hand.{_s}": f"hand_{_x}",
        f"DEF-thigh.{_s}": f"thigh_{_x}", f"DEF-shin.{_s}": f"calf_{_x}",
        f"DEF-foot.{_s}": f"foot_{_x}", f"DEF-toe.{_s}": f"ball_{_x}",
    })
STD_PARENT = {
    "root": None, "pelvis": "root", "spine_01": "pelvis", "spine_02": "spine_01", "spine_03": "spine_02",
    "neck_01": "spine_03", "head": "neck_01",
}
for _x in "lr":
    STD_PARENT.update({
        f"clavicle_{_x}": "spine_03", f"upperarm_{_x}": f"clavicle_{_x}", f"lowerarm_{_x}": f"upperarm_{_x}",
        f"hand_{_x}": f"lowerarm_{_x}", f"thigh_{_x}": "pelvis", f"calf_{_x}": f"thigh_{_x}",
        f"foot_{_x}": f"calf_{_x}", f"ball_{_x}": f"foot_{_x}",
    })
STD_ORDER = list(STD_PARENT.keys())          # já está em ordem pai -> filho
UAL_NAME = {"head": "Head"}                   # único nome que difere da UAL
ARM_BONES = {f"{b}_{x}" for b in ("clavicle", "upperarm", "lowerarm", "hand") for x in "lr"}


def log(*a):
    print("[pipeline]", *a, flush=True)


def _sel(objs, active):
    bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = active


# ---------------------------------------------------------------------------
# 1. MALHA
# ---------------------------------------------------------------------------
def prep_mesh(cfg):
    name = cfg["name"]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=cfg["mesh"])
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    for o in meshes:
        mw = o.matrix_world.copy(); o.parent = None; o.data.transform(mw); o.matrix_world = Matrix.Identity(4)
    if len(meshes) > 1:
        _sel(meshes, meshes[0]); bpy.ops.object.join()
    mesh = meshes[0]
    for o in new:
        if o != mesh and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    mesh.name = mesh.data.name = f"{name}_Mesh"
    rep = {"tris_in": sum(len(p.vertices) - 2 for p in mesh.data.polygons)}

    # --- correção de renderização: soldar costuras de UV (TRELLIS separa a malha em ~200 ilhas),
    #     normais para fora, sombreamento suave
    bm = bmesh.new(); bm.from_mesh(mesh.data)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=cfg.get("weld_distance", 1e-5))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rep["welded_verts"] = n0 - len(bm.verts)
    rep["boundary_edges"] = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(mesh.data); bm.free()
    for p in mesh.data.polygons:
        p.use_smooth = True

    # pés em z = 0 (landmarks são medidos neste espaço)
    minz = min(v.co.z for v in mesh.data.vertices)
    mesh.data.transform(Matrix.Translation((0, 0, -minz)))
    if cfg.get("target_height"):
        h = max(v.co.z for v in mesh.data.vertices)
        mesh.data.transform(Matrix.Scale(cfg["target_height"] / h, 4))

    # --- orçamento mobile: decimação
    tgt = cfg.get("target_tris")
    if tgt and rep["tris_in"] > tgt:
        _sel([mesh], mesh)
        mod = mesh.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = 'COLLAPSE'; mod.ratio = tgt / rep["tris_in"]
        mod.use_collapse_triangulate = True
        mod.use_symmetry = True; mod.symmetry_axis = 'X'
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh.data.calc_loop_triangles()
    rep["tris_out"] = len(mesh.data.loop_triangles)
    rep["verts_out"] = len(mesh.data.vertices)

    # --- material único, não-metálico, textura pequena
    mat = mesh.data.materials[0]
    mat.name = f"{name}_Mat"
    mat.use_backface_culling = True            # malha agora é fechada -> single-sided (mais barato no mobile)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = cfg.get("roughness", 0.85)
    tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
    img = bpy.data.images.load(cfg["basecolor"]) if cfg.get("basecolor") else tex.image
    size = cfg.get("texture_size", 512)
    if img.size[0] != size:
        img = img.copy(); img.scale(size, size)
    tdir = os.path.join(cfg["out_dir"], "textures"); os.makedirs(tdir, exist_ok=True)
    tpath = os.path.join(tdir, f"{name.lower()}_basecolor_{size}.png")
    img.filepath_raw = tpath; img.file_format = 'PNG'; img.save()
    img = bpy.data.images.load(tpath, check_existing=False); img.name = os.path.basename(tpath)
    tex.image = img
    tex.interpolation = 'Linear'
    rep["texture"] = [tpath, size]
    log("mesh", rep)
    return mesh, rep


# ---------------------------------------------------------------------------
# 2. RIGIFY: metarig encaixado por landmarks + geração
# ---------------------------------------------------------------------------
def build_metarig(cfg):
    L = {k: Vector(v) for k, v in cfg["landmarks"].items()}
    bpy.ops.object.armature_basic_human_metarig_add()
    meta = bpy.context.object
    meta.name = f"{cfg['name']}_Metarig"
    meta.data.name = f"{cfg['name']}_Metarig"
    bpy.ops.object.mode_set(mode='EDIT')
    eb = meta.data.edit_bones
    # mobile: sem ossos de seio/pelvis extras; pescoço com 1 osso (spine.005 removido)
    for n in ("breast.L", "breast.R", "pelvis.L", "pelvis.R"):
        eb.remove(eb[n])

    def setb(n, h, t):
        b = eb[n]; b.use_connect = False; b.head = h; b.tail = t

    P, N = L["pelvis"], L["neck_base"]
    pts = [P.lerp(N, t) for t in (0, 0.22, 0.48, 0.74, 1.0)]
    for i, n in enumerate(("spine", "spine.001", "spine.002", "spine.003")):
        setb(n, pts[i], pts[i + 1])
    setb("spine.004", N, L["head_base"])
    if cfg.get("single_neck", True):
        eb["spine.006"].parent = eb["spine.004"]
        eb.remove(eb["spine.005"])
        eb["spine.006"].name = "spine.005"
        setb("spine.005", L["head_base"], L["head_top"])
    else:
        nb = L["neck_base"].lerp(L["head_base"], 0.5)
        setb("spine.004", N, nb); setb("spine.005", nb, L["head_base"])
        setb("spine.006", L["head_base"], L["head_top"])
    bend = Vector((0, cfg.get("elbow_back_offset", 0.012), 0))
    for side, sx in (("L", 1), ("R", -1)):
        m = lambda v: Vector((v.x * sx, v.y, v.z))
        setb(f"shoulder.{side}", m(L["clav_head"]), m(L["shoulder"]))
        setb(f"upper_arm.{side}", m(L["shoulder"]), m(L["elbow"] + bend))
        setb(f"forearm.{side}", m(L["elbow"] + bend), m(L["wrist"]))
        setb(f"hand.{side}", m(L["wrist"]), m(L["hand_tip"]))
        setb(f"thigh.{side}", m(L["hip"]), m(L["knee"]))
        setb(f"shin.{side}", m(L["knee"]), m(L["ankle"]))
        setb(f"foot.{side}", m(L["ankle"]), m(L["ball"]))
        setb(f"toe.{side}", m(L["ball"]), m(L["toe"]))
        a = L["ankle"]
        setb(f"heel.02.{side}", m(Vector((a.x - 0.03, a.y + 0.03, 0.0))), m(Vector((a.x + 0.03, a.y + 0.03, 0.0))))
    # cadeias conectadas
    for n in ("spine.001", "spine.002", "spine.003", "spine.005"):
        eb[n].use_connect = True
    # pescoço NÃO conectado (mesma posição): senão o basic_spine engole a cadeia do pescoço/cabeça
    # (no metarig padrão isso é evitado porque os ombros são filhos conectados de spine.003)
    eb["spine.004"].use_connect = False
    if not cfg.get("single_neck", True):
        eb["spine.006"].use_connect = True
    for s in "LR":
        for n in (f"forearm.{s}", f"hand.{s}", f"shin.{s}", f"foot.{s}", f"toe.{s}"):
            eb[n].use_connect = True
    # rolls: membros com eixo Z para trás/frente -> dobra no eixo X (lateral)
    bpy.ops.armature.select_all(action='DESELECT')
    for b in eb:
        b.select = b.select_head = b.select_tail = True
    bpy.ops.armature.calculate_roll(type='GLOBAL_NEG_Y')
    bpy.ops.object.mode_set(mode='OBJECT')
    # parâmetros Rigify: 1 segmento por membro (menos ossos DEF), sem B-Bones
    pb = meta.pose.bones
    for s in "LR":
        for n in (f"upper_arm.{s}", f"thigh.{s}"):
            p = pb[n].rigify_parameters
            p.segments = 1
            p.bbones = 1
            p.rotation_axis = 'automatic'
    pb["spine"].rigify_parameters.pivot_pos = 1
    meta.data.rigify_rig_basename = f"{cfg['name']}_Rigify"
    return meta


def generate_rig(meta):
    _sel([meta], meta)
    bpy.ops.pose.rigify_generate()
    rig = meta.data.rigify_target_rig
    meta.hide_set(True)
    return rig


# ---------------------------------------------------------------------------
# 3. SKIN
# ---------------------------------------------------------------------------
def skin(mesh, rig, cfg):
    _sel([mesh, rig], rig)
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    rep = {}
    me = mesh.data
    zero = [v.index for v in me.vertices if not any(g.weight > 1e-4 for g in v.groups)]
    rep["unweighted_after_heat"] = len(zero)
    if zero:
        # fallback: herda pesos do vizinho mais próximo com peso
        from mathutils.kdtree import KDTree
        good = [v for v in me.vertices if v.index not in set(zero)]
        kd = KDTree(len(good))
        for i, v in enumerate(good): kd.insert(v.co, i)
        kd.balance()
        for vi in zero:
            _, i, _ = kd.find(me.vertices[vi].co)
            for g in good[i].groups:
                mesh.vertex_groups[g.group].add([vi], g.weight, 'REPLACE')
    _sel([mesh], mesh)
    bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
    bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=2)
    bpy.ops.object.vertex_group_clean(group_select_mode='ALL', limit=0.01)
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    rep["max_influences"] = max(len([g for g in v.groups if g.weight > 0]) for v in me.vertices)
    rep["groups"] = [g.name for g in mesh.vertex_groups]
    log("skin", rep)
    return rep


# ---------------------------------------------------------------------------
# 4. ESQUELETO DE JOGO (nomes padronizados) dirigido pelos DEF do Rigify
# ---------------------------------------------------------------------------
def build_game_skeleton(rig, mesh, cfg):
    name = cfg["name"]
    missing = [d for d in DEF_TO_STD if d not in rig.data.bones]
    extra = [b.name for b in rig.data.bones if b.use_deform and b.name not in DEF_TO_STD]
    if missing or extra:
        raise RuntimeError(f"DEF inesperados: faltando={missing} extras={extra}")
    data = bpy.data.armatures.new(f"{name}_Skeleton")
    game = bpy.data.objects.new(f"{name}_Armature", data)
    bpy.context.scene.collection.objects.link(game)
    _sel([game], game)
    bpy.ops.object.mode_set(mode='EDIT')
    std_to_def = {v: k for k, v in DEF_TO_STD.items()}
    eb = data.edit_bones
    for n in STD_ORDER:
        b = eb.new(n)
        if n == "root":
            b.head = (0, 0, 0); b.tail = (0, 0, 0.1)
        else:
            src = rig.data.bones[std_to_def[n]]
            m = rig.matrix_world @ src.matrix_local
            b.head = rig.matrix_world @ src.head_local
            b.tail = rig.matrix_world @ src.tail_local
            b.align_roll(m.to_3x3() @ Vector((0, 0, 1)))
        if STD_PARENT[n]:
            b.parent = eb[STD_PARENT[n]]
        b.use_deform = n != "root"
    bpy.ops.object.mode_set(mode='OBJECT')
    data.display_type = 'STICK'
    # restrições: cada osso de jogo copia o DEF correspondente
    for n in STD_ORDER:
        c = game.pose.bones[n].constraints.new('COPY_TRANSFORMS')
        c.target = rig
        c.subtarget = "root" if n == "root" else "ORG-" + std_to_def[n][4:]   # ORG = resultado FK/IK com torção completa
    # malha passa a usar o esqueleto de jogo
    for vg in mesh.vertex_groups:
        if vg.name in DEF_TO_STD:
            vg.name = DEF_TO_STD[vg.name]
    for m in mesh.modifiers:
        if m.type == 'ARMATURE':
            m.object = game
    mesh.parent = game
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    return game


# ---------------------------------------------------------------------------
# 5. RETARGET UAL -> controles Rigify -> bake no esqueleto de jogo
# ---------------------------------------------------------------------------
def import_ual(path):
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before_o]
    src = next(o for o in new if o.type == 'ARMATURE')
    for o in new:
        if o != src: bpy.data.objects.remove(o, do_unlink=True)
    src.name = "UAL_Source"
    acts = {a.name.split(".")[0]: a for a in bpy.data.actions if a not in before_a}
    for k, a in acts.items():
        a.name = "UAL_" + k              # evita colisão com os nomes finais das animações
    return src, acts


# controles FK do Rigify que posicionam cada osso de jogo (resolvidos em ordem pai -> filho)
def control_map(rig):
    names = {b.name for b in rig.pose.bones}
    cm = []
    def first(*c):
        for x in c:
            if x in names: return x
        raise RuntimeError("controle não encontrado: %s" % (c,))
    cm.append(("pelvis", "torso", "loc"))
    cm.append(("pelvis", first("hips"), "rot"))
    cm.append(("spine_01", first("spine_fk.001", "tweak_spine.001"), "rot"))
    cm.append(("spine_02", first("spine_fk.002", "tweak_spine.002"), "rot"))
    cm.append(("spine_03", first("spine_fk.003", "tweak_spine.003"), "rot"))
    cm.append(("neck_01", first("neck"), "rot"))
    cm.append(("head", first("head"), "rot"))
    for s, x in (("L", "l"), ("R", "r")):
        cm += [(f"clavicle_{x}", f"shoulder.{s}", "rot"), (f"upperarm_{x}", f"upper_arm_fk.{s}", "rot"),
               (f"lowerarm_{x}", f"forearm_fk.{s}", "rot"), (f"hand_{x}", f"hand_fk.{s}", "rot"),
               (f"thigh_{x}", f"thigh_fk.{s}", "rot"), (f"calf_{x}", f"shin_fk.{s}", "rot"),
               (f"foot_{x}", f"foot_fk.{s}", "rot"), (f"ball_{x}", f"toe_fk.{s}", "rot")]
    return cm


def set_fk(rig, val=1.0):
    for pb in rig.pose.bones:
        for k in ("IK_FK",):
            if k in pb.keys():
                pb[k] = val


def retarget(src, acts, rig, game, cfg):
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get
    rest_g = {b.name: (game.matrix_world @ b.matrix_local) for b in game.data.bones}
    rest_u = {b.name: (src.matrix_world @ b.matrix_local) for b in src.data.bones}
    ratio = rest_g["pelvis"].translation.z / rest_u["pelvis"].translation.z
    if src.animation_data is None: src.animation_data_create()
    src.animation_data.action = acts["Idle_Loop"]; sc.frame_set(0)
    eu = src.evaluated_get(dg())
    ref = {n: (src.matrix_world @ eu.pose.bones[n].matrix).to_3x3() for n in rest_u}
    cm = control_map(rig)
    ctrl_names = sorted({c for _, c, _ in cm})
    if rig.animation_data is None: rig.animation_data_create()
    if game.animation_data is None: game.animation_data_create()
    set_fk(rig, 1.0)
    rig_actions = {}
    errs = {}
    errs_bone = {}

    def desired(n, eu):
        un = UAL_NAME.get(n, n)
        pu = src.matrix_world @ eu.pose.bones[un].matrix
        if n in ARM_BONES:  # braços: relativo à pose neutra (Idle f0) -> encaixa A-pose x T-pose
            R = pu.to_3x3() @ ref[un].inverted() @ rest_g[n].to_3x3()
        else:
            R = pu.to_3x3() @ rest_u[un].to_3x3().inverted() @ rest_g[n].to_3x3()
        return R, pu.translation

    for anim in cfg["animations"]:
        base = anim["from"]; out = anim["name"]
        ua = acts[base]
        src.animation_data.action = ua
        f0, f1 = int(round(ua.frame_range[0])), int(round(ua.frame_range[1]))
        act = bpy.data.actions.new(f"RIG_{out}")   # ação editável dos controles Rigify
        act.use_fake_user = True
        rig.animation_data.action = act
        prev = {}
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            eu = src.evaluated_get(dg())
            # reset dos controles
            for c in ctrl_names:
                pb = rig.pose.bones[c]
                pb.rotation_mode = 'QUATERNION'
                pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
            bpy.context.view_layer.update()
            want = {}
            for n, c, kind in cm * cfg.get("solver_passes", 2):
                if n not in want: want[n] = desired(n, eu)
                R, T = want[n]
                R = _override(anim, n, R, rest_g, want)
                pb = rig.pose.bones[c]
                cur = (rig.matrix_world @ rig.pose.bones[_def_of(n)].matrix)
                if kind == "loc":
                    tw = rest_g[n].translation + (T - rest_u["pelvis"].translation) * ratio
                    delta = tw - cur.translation
                    M = rig.matrix_world @ pb.matrix
                    M.translation = M.translation + delta
                    pb.matrix = rig.matrix_world.inverted() @ M
                else:
                    dR = (R @ cur.to_3x3().inverted())
                    M = rig.matrix_world @ pb.matrix
                    M3 = dR @ M.to_3x3()
                    newM = Matrix.Translation(M.translation) @ M3.to_4x4()
                    pb.matrix = rig.matrix_world.inverted() @ newM
                bpy.context.view_layer.update()
            for n in want:                     # erro residual (graus) entre desejado e obtido
                R = _override(anim, n, want[n][0], rest_g, want)
                cur = (rig.matrix_world @ rig.pose.bones[_def_of(n)].matrix).to_3x3().normalized()
                ang = math.degrees((R.to_quaternion().rotation_difference(cur.to_quaternion())).angle)
                ang = min(ang, 360 - ang)
                errs[out] = max(errs.get(out, 0.0), ang)
                key = (out, n)
                errs_bone[key] = max(errs_bone.get(key, 0.0), ang)
            for c in ctrl_names:
                pb = rig.pose.bones[c]
                q = pb.rotation_quaternion.copy()
                if c in prev: q.make_compatible(prev[c])
                prev[c] = q; pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=c)
                if c == "torso":
                    pb.keyframe_insert("location", frame=f, group=c)
        for fc in _fcurves(act):
            for k in fc.keyframe_points: k.interpolation = 'LINEAR'
        rig_actions[out] = act
        worst = sorted(((v, k[1]) for k, v in errs_bone.items() if k[0] == out), reverse=True)[:4]
        log("retarget", out, f1 - f0 + 1, "frames", "erro max %.2f graus" % errs.get(out, 0),
            [(b, round(v, 1)) for v, b in worst])
    retarget.errors = errs
    return rig_actions


def _fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
        return list(act.fcurves)
    res = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for cb in strip.channelbags:
                res += list(cb.fcurves)
    return res


_DEF_OF = {v: k for k, v in DEF_TO_STD.items()}
def _def_of(n): return "ORG-" + _DEF_OF[n][4:]     # osso que o esqueleto de jogo copia


def _override(anim, n, R, rest_g, want):
    """Sobrepõe a rotação de ossos (ex.: braços segurando caixa) -- definido no config.
    pose_override: {osso: [rx, ry, rz]} graus, eixos do mundo na pose de repouso, aplicados sobre o rest
    e acompanhando o peito (spine_03) da animação base. Lado _r usa o espelho automático de ry/rz."""
    ov = anim.get("pose_override", {})
    key = n if n in ov else (n[:-2] + "_l" if n.endswith("_r") and n[:-2] + "_l" in ov else None)
    if key is None:
        return R
    e = list(ov[key])
    if key != n:                       # espelho em X
        e = [e[0], -e[1], -e[2]]
    Rw = Matrix.Rotation(math.radians(e[2]), 3, 'Z') @ Matrix.Rotation(math.radians(e[1]), 3, 'Y') @ Matrix.Rotation(math.radians(e[0]), 3, 'X')
    chest = want.get("spine_03")
    D = (chest[0] @ rest_g["spine_03"].to_3x3().inverted()) if chest else Matrix.Identity(3)
    return D @ Rw @ rest_g[n].to_3x3()


def bake_game(rig, game, rig_actions):
    sc = bpy.context.scene
    _sel([game], game)
    bpy.ops.object.mode_set(mode='POSE')
    game_actions = {}
    for out, act in rig_actions.items():
        rig.animation_data.action = act
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        bpy.ops.pose.select_all(action='SELECT')
        bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=True, visual_keying=True,
                         clear_constraints=False, use_current_action=False, bake_types={'POSE'},
                         channel_types={'LOCATION', 'ROTATION', 'SCALE'})
        ga = game.animation_data.action
        ga.name = out; ga.use_fake_user = True
        game.animation_data.action = None
        game_actions[out] = ga
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.animation_data.action = None
    # faixas NLA (o exportador glTF usa uma animação por faixa)
    for tr in list(game.animation_data.nla_tracks): game.animation_data.nla_tracks.remove(tr)
    for out, ga in game_actions.items():
        tr = game.animation_data.nla_tracks.new(); tr.name = out
        st = tr.strips.new(out, int(ga.frame_range[0]), ga); st.name = out
    # rig Rigify fica com as mesmas ações (editáveis) em faixas NLA mudas
    for tr in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(tr)
    for out, act in rig_actions.items():
        tr = rig.animation_data.nla_tracks.new(); tr.name = out
        st = tr.strips.new(out, int(act.frame_range[0]), act); st.name = out
        tr.mute = True
    return game_actions


def export_glb(game, mesh, path):
    # durante a exportação o esqueleto de jogo não pode depender do Rigify
    mutes = []
    for pb in game.pose.bones:
        for c in pb.constraints:
            mutes.append((c, c.enabled)); c.enabled = False
    for pb in game.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
    _sel([game, mesh], game)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=False,
        export_yup=True, export_skins=True, export_def_bones=False, export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_optimize_animation_size=True,
        export_normals=True, export_tangents=False, export_texcoords=True, export_materials='EXPORT',
        export_image_format='AUTO', export_cameras=False, export_lights=False, export_all_influences=False,
        export_reset_pose_bones=True)
    for c, e in mutes: c.enabled = e


# ---------------------------------------------------------------------------
def run(cfg, stage="all"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon_utils.enable("rigify", default_set=True)
    sc = bpy.context.scene
    sc.render.fps = 24
    out_dir = cfg["out_dir"]; os.makedirs(out_dir, exist_ok=True)
    name = cfg["name"]
    bdir = os.path.join(out_dir, "blender"); os.makedirs(bdir, exist_ok=True)
    gdi = os.path.join(bdir, ".gdignore")      # o Godot não deve importar o .blend
    if not os.path.exists(gdi): open(gdi, "w").close()
    blend = os.path.join(bdir, f"{name.lower()}_rigify.blend")
    report = {}
    mesh, report["mesh"] = prep_mesh(cfg)
    if stage == "mesh":
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True); return report
    meta = build_metarig(cfg)
    rig = generate_rig(meta)
    report["rigify_bones"] = len(rig.data.bones)
    if stage == "rig":
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True); return report
    report["skin"] = skin(mesh, rig, cfg)
    game = build_game_skeleton(rig, mesh, cfg)
    report["game_bones"] = [b.name for b in game.data.bones]
    if stage == "skin":
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True); return report
    src, acts = import_ual(cfg["ual"])
    rig_actions = retarget(src, acts, rig, game, cfg)
    bake_game(rig, game, rig_actions)
    for a in list(acts.values()):          # a UAL de origem não fica no .blend final
        bpy.data.actions.remove(a)
    bpy.data.objects.remove(src, do_unlink=True)
    report["animations"] = {k: round(v, 2) for k, v in retarget.errors.items()}
    glb = os.path.join(out_dir, f"{name.lower()}.glb")
    export_glb(game, mesh, glb)
    report["glb"] = glb
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    report["blend"] = blend
    return report


if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    cfg = json.load(open(args[0], encoding="utf-8-sig"))
    rep = run(cfg, args[1] if len(args) > 1 else "all")
    print("JSONOUT" + json.dumps(rep, default=str))
