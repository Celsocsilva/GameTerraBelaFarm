"""
measure_stride.py -- mede a velocidade de chão (m/s, personagem em escala 1) de cada ciclo de locomoção,
para calibrar o FarmerAnimator sem patinar os pés.

blender -b <personagem>_rigify.blend -P measure_stride.py -- Walk_Loop,Jog_Fwd_Loop,...

Método: em cada quadro, o pé mais baixo (osso ball_l/ball_r do esqueleto de jogo) é o pé de apoio; a velocidade
de chão é quanto ele anda para trás (+Y no Blender, pois a frente é -Y) por segundo. Usa a mediana.
"""
import bpy, sys, json
import numpy as np

anims = sys.argv[sys.argv.index("--") + 1].split(",")
sc = bpy.context.scene
fps = sc.render.fps
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name.endswith("_Rigify"))
game = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o.name.endswith("_Armature"))
for tr in rig.animation_data.nla_tracks:
    tr.mute = True
if game.animation_data:
    for tr in game.animation_data.nla_tracks:
        tr.mute = True
out = {}
for an in anims:
    act = bpy.data.actions["RIG_" + an]
    rig.animation_data.action = act
    if hasattr(rig.animation_data, "action_slot") and act.slots:
        rig.animation_data.action_slot = act.slots[0]
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    pos = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        pos.append([np.array(game.matrix_world @ game.pose.bones[b].head) for b in ("ball_l", "ball_r")])
    pos = np.array(pos)                       # [frame, foot, xyz]
    v = []
    for i in range(len(pos) - 1):
        k = int(np.argmin(pos[i, :, 2]))      # pé de apoio
        v.append((pos[i + 1, k, 1] - pos[i, k, 1]) * fps)
    v = np.array(v)
    out[an] = round(float(np.median(v[v > 0])) if (v > 0).any() else 0.0, 3)
print("STRIDE " + json.dumps(out))
