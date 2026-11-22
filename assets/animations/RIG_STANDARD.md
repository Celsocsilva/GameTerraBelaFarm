# Padrão de rig e animação de personagens — Terra Bela Farm

Padrão único para **todos os personagens 3D** do jogo (fazendeiro, ajudantes, clientes, NPCs).
O rig de trabalho é feito no **Rigify** (Blender 5.3) e o jogo recebe um **esqueleto de jogo enxuto de 23 ossos**
com nomes fixos, compatíveis com a **Universal Animation Library (UAL, Quaternius, CC0)** que está em
`assets/animations/Universal Animation Library[Standard]/` e com o perfil humanoide do Godot.

Primeiro personagem no padrão: `Farmer/` (ver `Farmer/README.md`).
Pipeline automático: `tools/rigify_character_pipeline.py` (gera tudo a partir de um `config.json`).

---

## 1. Duas camadas de esqueleto

| Camada | Onde vive | Para quê | Nº de ossos |
|---|---|---|---|
| **Rig Rigify** (`<Nome>_Rigify`) | só no `.blend` | animar no Blender (controles FK/IK, torso, pés com IK) | ~184 (controles, `ORG-`, `MCH-`, `DEF-`) |
| **Esqueleto de jogo** (`<Nome>_Armature`) | `.blend` **e** `.glb` | o que o Godot recebe; deforma a malha | **23** |

Cada osso do esqueleto de jogo tem uma restrição *Copy Transforms* apontando para o osso `ORG-` correspondente do
Rigify. Animar os controles do Rigify move o esqueleto de jogo e a malha. Na exportação as animações são
"assadas" (bake) no esqueleto de jogo e só ele vai para o `.glb` — nenhum osso `ORG-/MCH-/DEF-` ou controle chega ao jogo.

> Por que `ORG-` e não `DEF-`? Com 1 segmento por membro o Rigify tira a torção do `DEF-upper_arm/DEF-thigh`
> (anti-torção). O `ORG-` tem a rotação completa do FK/IK, que é a que o retarget precisa reproduzir
> (erro medido < 5° em todas as animações; com `DEF-` chegava a 24°).

---

## 2. Esqueleto de jogo (23 ossos)

```
root
└─ pelvis
   ├─ spine_01 ─ spine_02 ─ spine_03
   │   ├─ neck_01 ─ head
   │   ├─ clavicle_l ─ upperarm_l ─ lowerarm_l ─ hand_l
   │   └─ clavicle_r ─ upperarm_r ─ lowerarm_r ─ hand_r
   ├─ thigh_l ─ calf_l ─ foot_l ─ ball_l
   └─ thigh_r ─ calf_r ─ foot_r ─ ball_r
```

`root` (1, sem pesos) + tronco/cabeça 6 + braços 4×2 + pernas 4×2 = **23**. Todos deformam, exceto `root`.

### Tabela de correspondência (use para qualquer personagem)

| Esqueleto de jogo | Metarig Rigify (Basic Human) | Osso do rig gerado copiado | Osso deformador Rigify | UAL | Godot `SkeletonProfileHumanoid` |
|---|---|---|---|---|---|
| `root` | — | `root` | — | `root` | Root |
| `pelvis` | `spine` | `ORG-spine` | `DEF-spine` | `pelvis` | Hips |
| `spine_01` | `spine.001` | `ORG-spine.001` | `DEF-spine.001` | `spine_01` | Spine |
| `spine_02` | `spine.002` | `ORG-spine.002` | `DEF-spine.002` | `spine_02` | Chest |
| `spine_03` | `spine.003` | `ORG-spine.003` | `DEF-spine.003` | `spine_03` | UpperChest |
| `neck_01` | `spine.004` | `ORG-spine.004` | `DEF-spine.004` | `neck_01` | Neck |
| `head` | `spine.005` ¹ | `ORG-spine.005` | `DEF-spine.005` | `Head` | Head |
| `clavicle_l` | `shoulder.L` | `ORG-shoulder.L` | `DEF-shoulder.L` | `clavicle_l` | LeftShoulder |
| `upperarm_l` | `upper_arm.L` | `ORG-upper_arm.L` | `DEF-upper_arm.L` | `upperarm_l` | LeftUpperArm |
| `lowerarm_l` | `forearm.L` | `ORG-forearm.L` | `DEF-forearm.L` | `lowerarm_l` | LeftLowerArm |
| `hand_l` | `hand.L` | `ORG-hand.L` | `DEF-hand.L` | `hand_l` | LeftHand |
| `thigh_l` | `thigh.L` | `ORG-thigh.L` | `DEF-thigh.L` | `thigh_l` | LeftUpperLeg |
| `calf_l` | `shin.L` | `ORG-shin.L` | `DEF-shin.L` | `calf_l` | LeftLowerLeg |
| `foot_l` | `foot.L` | `ORG-foot.L` | `DEF-foot.L` | `foot_l` | LeftFoot |
| `ball_l` | `toe.L` | `ORG-toe.L` | `DEF-toe.L` | `ball_l` | LeftToes |
| `*_r` | `*.R` | `ORG-*.R` | `DEF-*.R` | `*_r` | Right* |

¹ O metarig *Basic Human* tem pescoço de 2 ossos (`spine.004`, `spine.005`) e cabeça `spine.006`. O padrão usa
**pescoço de 1 osso**: o pipeline remove o `spine.005` original e renomeia a cabeça para `spine.005`.
Também são removidos `breast.L/R` e `pelvis.L/R` (não usados no mobile). O `heel.02.L/R` fica no metarig (o IK do pé precisa dele) e não vira osso de jogo.

### Regras de nomenclatura (obrigatórias no esqueleto de jogo)

| Regra | Certo | Errado |
|---|---|---|
| `snake_case`, tudo **minúsculo**, sem espaço, ponto ou acento | `upperarm_l` | `UpperArm.L`, `Braço_E` |
| Lado como **sufixo** `_l` / `_r` (esquerda do personagem = +X no Blender) | `thigh_r` | `r_thigh`, `Right_Thigh`, `thigh.R` |
| Segmentos numerados com 2 dígitos, da raiz para a ponta | `spine_01`, `neck_01` | `spine1`, `spine_1` |
| Sem prefixos de ferramenta (`DEF-`, `ORG-`, `mixamorig:`, `Bip01`) | `pelvis` | `DEF-spine` |
| Um único `root` na origem (0,0,0), **sem pesos** | `root` | vários ossos raiz |
| Grupos de vértices com o mesmo nome do osso | `hand_l` | `DEF-hand.L` |
| Osso novo (rabo, chapéu, orelha…) | `<parte>_<nn>[_l/_r]`, ex.: `hat_01`, `ear_01_l` | `Chapeu` |

No **metarig/Rigify** valem os nomes do Rigify (`.L/.R`, `DEF-`, `ORG-`): não renomeie ossos do rig gerado,
senão os scripts do Rigify quebram. A tradução acontece só no esqueleto de jogo (tabela acima, constante
`DEF_TO_STD` do pipeline).

### Orientação, escala e unidades

- Pés em **Z = 0** (Blender) / **Y = 0** (Godot); `root` na origem.
- Frente do personagem = **–Y no Blender** → no `.glb` olha para **+Z** (padrão glTF). No jogo a frente do fazendeiro
  é **–Z** (câmera em +Z), por isso `farmer_character.tscn` gira o modelo 180° em Y. Reuse essa cena-modelo.
- Unidade = metro; 24 fps. O fazendeiro tem **1,00 m** (proporção estilizada). Altura-alvo opcional no config (`target_height`).
- Pose de repouso: A-pose ou T-pose (o retarget compensa os braços pela pose neutra do `Idle_Loop` da UAL).
  O cotovelo precisa de uma leve dobra para trás (`elbow_back_offset`) para o IK saber para onde dobrar.

---

## 3. Orçamento mobile (Google Play)

| Item | Limite | Fazendeiro |
|---|---|---|
| Triângulos por personagem principal | ≤ 6.500 (NPC: ≤ 3.000) | 6.000 |
| Malhas / materiais / draw calls | 1 / 1 / 1 | 1 / 1 / 1 |
| Textura base | 512² (NPC 256²), sem normal map | 512² |
| Ossos no jogo | ≤ 30 (padrão 23) | 23 |
| Influências por vértice | máx. 4, soma = 1 | 4, soma = 1 |
| Material | `metallic = 0`, `roughness ≈ 0.85`, face simples (backface culling) | ok |
| `.glb` com animações | ≤ 2 MB | ~1,5 MB (25 animações) |

Malhas geradas por IA (TRELLIS etc.) chegam **cortadas nas costuras de UV** (o fazendeiro tinha 200 pedaços soltos e
3.696 arestas abertas). Isso causa rachaduras/linhas claras quando o corpo dobra e impede pesos contínuos.
O pipeline solda os vértices (`weld_distance`), recalcula normais para fora e aplica sombreamento suave **antes** do
rig; a malha passa a ser uma peça fechada. As costuras de UV continuam existindo só na UV.

---

## 4. Animações

Nomes iguais aos da UAL (os scripts valem para qualquer personagem). Sufixo `_Loop` = ciclo.
Animações próprias do jogo seguem `PascalCase_Com_Underscore` e `_Loop` quando for ciclo.

| Uso no jogo | Animação | Origem |
|---|---|---|
| Parado | `Idle_Loop`, `Idle_Talking_Loop` | UAL |
| Andar / correr | `Walk_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop` | UAL |
| **Carregar caixa** | `Carry_Idle_Loop`, `Carry_Walk_Loop` | UAL `Idle_Loop`/`Walk_Loop` + braços segurando (sobreposição `pose_override` no config) |
| **Mochila com caixas** (jogo atual) | `Backpack_Idle_Loop`, `Backpack_Walk_Loop`, `Backpack_Jog_Loop` | UAL `Idle`/`Walk`/`Jog_Fwd` + mãos nas alças (`pose_override`) |
| **Plantar** | `Fixing_Kneeling` | UAL (ajoelha e mexe na terra) |
| **Colher / pegar** | `PickUp_Table` | UAL |
| Interagir (portão, placa, máquina) | `Interact` | UAL |
| Agachar | `Crouch_Idle_Loop`, `Crouch_Fwd_Loop` | UAL |
| Empurrar (carrinho) | `Push_Loop` | UAL |
| Sentar / dirigir trator | `Sitting_Enter`, `Sitting_Idle_Loop`, `Sitting_Exit`, `Driving_Loop` | UAL |
| Pular | `Jump_Start`, `Jump_Loop`, `Jump_Land` | UAL |
| Comemorar / reação | `Dance_Loop`, `Hit_Chest` | UAL |

Para incluir mais animações da UAL (ex.: `Roll`, `Swim_*`), adicione `{"name": ..., "from": ...}` em `animations` no
config e rode o pipeline de novo. Uma animação feita à mão: anime os **controles Rigify** no `.blend` numa ação
`RIG_<Nome>`, adicione uma faixa NLA e rode o bake (ou acrescente-a ao pipeline).

---

## 5. Como fazer um personagem novo (≈ 2 min de máquina)

1. Malha `.glb` de pé, olhando para –Y, A-pose/T-pose, com 1 textura.
2. Copie `Farmer/farmer_rigify_config.json` e troque `name`, `mesh`, `basecolor` (opcional), `out_dir`, `landmarks`.
   Landmarks (metros, lado esquerdo = +X, Z para cima, pés em Z = 0):
   `pelvis, neck_base, head_base, head_top, clav_head, shoulder, elbow, wrist, hand_tip, hip, knee, ankle, ball, toe`.
3. Rode (Blender fechado ou aberto, tanto faz — roda em segundo plano):
   ```
   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b --factory-startup -P assets\animations\tools\rigify_character_pipeline.py -- <config.json>
   ```
   Etapas: limpar/otimizar malha → metarig por landmarks → `rigify_generate` → pesos (bone heat, ≤ 4, normalizados)
   → esqueleto de jogo → retarget UAL → controles Rigify → bake → `.glb`. O log mostra o erro do retarget por animação.
4. Prévia: `blender -b <out>\blender\<nome>_rigify.blend -P assets\animations\tools\render_character_preview.py -- <saida.png> Idle_Loop,Walk_Loop 4`
5. No Godot: o `.import` do `.glb` usa `nodes/use_name_suffixes=false` e o script
   `assets/animations/tools/character_post_import.gd` (mantém os nomes `*_Loop` e liga o loop). Copie esses dois
   ajustes do `Farmer/farmer.glb.import`.
6. Rode o teste: `Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/farmer_rig_smoke.gd`
   (para outro personagem, copie o teste e troque `SCENE`).

---

## 6. Uso no Godot 4

- No jogo: `scenes/player/farmer.tscn` usa a cena em escala 2,5 e o `FarmWorld` liga os eventos às animações (`docs/evidence/farmer-game-001.md`).
- Cena pronta: `Farmer/farmer_character.tscn` (`Node3D` → `Model` (o `.glb`, girado 180°) + `FarmerAnimator`).
  Instancie dentro do `CharacterBody3D` no lugar da cápsula e chame `animator.update_locomotion(velocity.length())`.
- Objetos na mão (caixa, regador, enxada): `BoneAttachment3D` no `Skeleton3D` com `bone_name = "hand_r"` (ou `hand_l`).
  Para a caixa do `Carry_*`, prenda em `spine_03` à frente do peito.
- As animações da UAL também podem ser usadas direto da biblioteca via *Retarget → BoneMap* com
  `SkeletonProfileHumanoid` (os nomes batem com a tabela da seção 2), mas as animações embutidas no `.glb` são a opção
  de produção (já corrigidas para as proporções do personagem).

---

## 7. Checklist de produção (por personagem)

- [ ] 23 ossos com os nomes da seção 2 (o `farmer_rig_smoke.gd` confere)
- [ ] Malha fechada (0 arestas abertas após a solda), 1 material, `metallic = 0`, ≤ 6.500 triângulos, textura ≤ 512²
- [ ] Pesos: ≤ 4 influências, soma = 1, nenhum vértice sem peso
- [ ] Erro do retarget < 6° em todas as animações (log do pipeline)
- [ ] Import no Godot sem erros; `*_Loop` em loop; nomes das animações com `_Loop`
- [ ] Capturas no Godot (`tools/farmer_rig_capture.gd`) sem rachaduras, buracos ou partes escuras/metálicas
- [ ] Pés sem patinar com a velocidade de referência calibrada no `FarmerAnimator`
