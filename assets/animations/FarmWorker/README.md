# FarmWorker — trabalhadora rural (chapéu de palha, tomates, avental verde)

Malha gerada por IA (`source/farmworker_ai_original.glb`, a partir da ficha em `reference/`) limpa, re-texturizada e
rigada no **padrão do jogo** (`../RIG_STANDARD.md`): esqueleto de jogo de **23 ossos**, as mesmas **25 animações** do
fazendeiro e a mesma cena/animador (`FarmerAnimator`). Opção ao lado do fazendeiro: **não substitui** ninguém.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `farmworker.glb` | Entregável do Godot: malha 6.500 tris + 23 ossos + 25 animações + textura 1024 (~2,5 MB) |
| `farmworker_character.tscn` | Cena pronta (modelo virado para –Z + `FarmerAnimator`), igual à do fazendeiro |
| `res://scenes/player/farmworker.tscn` | Variante do `farmer.tscn` (mesmo controlador/colisão, escala 2,5) usando a trabalhadora |
| `blender/farmworker_rigify.blend` | Fonte editável: metarig, rig Rigify, esqueleto de jogo, ações `RIG_*` |
| `farmworker_rigify_config.json` | Config do pipeline (landmarks, `head_rigid`, `arms_from_rest`) |
| `textures/farmworker_basecolor.png` | Textura 1024 nova (bake + nitidez + rosto da ficha) — fonte do pipeline |
| `textures/farmworker_basecolor_2048.png` | Mesma textura em 2048 (fonte para retoques) |
| `source/farmworker_lowpoly.glb` | Malha limpa/decimada com UV nova, antes do rig (entrada do pipeline) |
| `source/farmworker_ai_original.glb` | Malha original da IA (13,7k tris, textura 1024 em ~300 retalhos) |
| `reference/` | Ficha de personagem e recorte do rosto frontal usado na projeção |
| `preview/` | Renders do Blender (antes/depois, animações); capturas do Godot em `docs/evidence/farmworker-rig-001` |

## Como foi feito (reproduzível)

1. `tools/farmworker_prep_mesh.py` (Blender, ~10 s):
   `blender -b --factory-startup -P assets/animations/tools/farmworker_prep_mesh.py -- <original.glb> reference/rosto_frontal_recorte.png <saida> 6500`
   solda das costuras (11.666 → 6.834 vértices, de 8.456 arestas abertas para 6), remove 3 pedacinhos soltos,
   decima 13.752 → 6.500 tris (simétrico em X), cria **UV nova** (smart project) e faz **bake 2048** da cor original
   para a UV nova (emissão, selected-to-active). O rosto da IA (olhos/boca toscos) é substituído pela **projeção
   frontal do rosto da ficha** com máscara elíptica suave só na frente do rosto. Depois: nitidez + saturação leve e
   redução para 1024 (Pillow).
2. `rigify_character_pipeline.py` com `farmworker_rigify_config.json` (~2,5 min). Duas opções novas do pipeline
   (desligadas por padrão, o fazendeiro não muda):
   - `head_rigid`: chapéu, cabelo e aba presos 100% no osso `head` (o bone heat puxava a aba pelos ombros);
   - `arms_from_rest`: para personagem em **T-pose** — alinha o braço de repouso à UAL, senão o Idle fica de braços abertos.
     As sobreposições `pose_override` (mochila/carregar) partem da pose neutra, como no fazendeiro.
3. Godot: `.import` igual ao do fazendeiro (`use_name_suffixes=false` + `character_post_import.gd`).

Testes:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/farmer_rig_smoke.gd -- --scene=res://assets/animations/FarmWorker/farmworker_character.tscn --max-texture=1024
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 -s tools/farmer_rig_capture.gd -- <pasta> --scene=res://assets/animations/FarmWorker/farmworker_character.tscn
```
Resultado 2026-11-24: 35/35 PASS; erro de retarget máx. 5,0° (Push_Loop), todas < 6°.

## Usar no jogo

- **Ajudante do canteiro de tomates** (desde 25/11): `FarmHelper.create(true)` instancia `farmworker_character.tscn`
  (escala 2,5) e usa o `FarmerAnimator`: Walk/Jog pela velocidade, `Carry_*` com a caixa nos braços, `PickUp_Table` ao
  colher, `Interact` ao semear e entregar. A cena é carregada com `load()`, nunca `preload` (ver CHANGELOG).
- Como jogador: trocar `res://scenes/player/farmer.tscn` por `res://scenes/player/farmworker.tscn` em
  `scenes/world/farm_world.tscn`. Não foi trocado.

## Pendências / limitações

- **Chapéu não é peça separada**: na malha da IA ele está fundido ao cabelo. Está preso 100% na cabeça; separar exige
  modelar/retopologizar o chapéu à parte (corte manual no Blender).
- **Rosto**: projetado da ficha (32 px de olho na ficha original → um pouco suave de perto); a pele do rosto ficou um
  pouco mais alaranjada que o pescoço. Há uma pequena mancha cinza na bochecha direita (borda do cabelo).
- **Costas**: as tranças viraram um bloco escuro e as fitas vermelhas do laço estão amassadas (a IA de imagem única
  inventa as costas). Retoque manual de textura/escultura recomendado.
- Mãos em luva sem dedos separados (as poses de mão da ficha não foram feitas).
- Textura 1024 deixa o `.glb` em ~2,5 MB (padrão recomenda ≤ 2 MB com 512). Exportar com JPEG quebrou o import do
  Godot 4.7.2 ("Couldn't load image ... image/jpeg"), por isso ficou PNG. Para 512: `texture_size: 512` no config.
- Existe uma segunda malha da IA em Downloads (`sample_2026-11-24T193445.766.glb`, textura 2048, rosto melhor, mas com
  73 furos e aba do chapéu vermelha por baixo) — comparação em `preview/ia_original_vs_alternativa.png`.
