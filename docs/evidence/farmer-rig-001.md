# FARMER-RIG-001 — fazendeiro rigado com Rigify e otimizado para mobile

Data: 2026-11-22 · Blender 5.3.0 (Rigify embutido) · Godot 4.7.2.stable

## Problemas de renderização encontrados na malha original (`farmer_source.glb`)

- Malha em **200 ilhas** soltas, cortada nas costuras de UV (3.696 arestas abertas): rachaduras e linhas claras quando
  o corpo dobra e pesos diferentes em vértices coincidentes.
- Material com `metallic = 1` (personagem escuro/metálico no Godot).
- Costas da textura ~3× mais escuras (iluminação assada do TRELLIS).

Correção (no pipeline): solda de 2.024 vértices duplicados → 1 peça, 0 arestas abertas; normais recalculadas para fora;
sombreamento suave; `metallic = 0`, `roughness = 0.85`; textura com costas corrigidas reduzida para 512².

## Resultado

| Item | Valor |
|---|---|
| Triângulos | 7.962 → **6.000** (2.990 vértices) |
| Textura | 512² PNG (Godot comprime em VRAM) |
| Ossos | Rigify 184 (só no `.blend`) → **23** no jogo |
| Influências | máx. 4, soma = 1 (desvio 0,0000) |
| Animações | 22 (inclui `Carry_Idle_Loop`, `Carry_Walk_Loop`) |
| `.glb` | 1,4 MB (antes 5,6 MB) |
| Erro do retarget (pior osso, pior quadro) | 0,0°–5,0° (maior: `spine_01` em `Push_Loop`) |

## Validação

- `blender -b --factory-startup -P assets/animations/tools/rigify_character_pipeline.py -- assets/animations/Farmer/farmer_rigify_config.json`: OK (menos de 1 minuto).
- `Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`: OK, sem erros.
- `Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/farmer_rig_smoke.gd`: **31 PASS, 0 FAIL** (ossos e nomes,
  hierarquia, 1 superfície, triângulos, 4 influências normalizadas, altura/pés, material, textura, 22 animações + RESET,
  loops, trilhas, coxa se move no `Walk_Loop`, `FarmerAnimator` carregando/plantando).
- `Godot ... --path . --resolution 1280x720 -s tools/farmer_rig_capture.gd -- <pasta>`: capturas abaixo.

O teste pegou um problema real na primeira importação: com `use_name_suffixes` ligado o Godot cortava o `_Loop` dos nomes
(`Walk_Loop` virava `Walk`, `Jump_Loop` virava `Jump`). Corrigido com `nodes/use_name_suffixes=false` +
`assets/animations/tools/character_post_import.gd`, que liga o loop das `*_Loop`.

## Capturas (renderizadas pelo Godot)

- `farmer-rig-001/01-basicas-frente.png` — Idle, Walk, Jog, Sprint, Carry_Walk
- `farmer-rig-001/01-basicas-camera-jogo.png` — mesmas, pela câmera elevada do jogo
- `farmer-rig-001/02-fazenda-frente.png` — Carry_Idle, Fixing_Kneeling (plantar), PickUp_Table (colher), Interact, Crouch_Fwd
- `farmer-rig-001/02-fazenda-camera-jogo.png`

Prévias do Blender: `assets/animations/Farmer/preview/` (`farmer_basicas.png`, `farmer_fazenda.png`, `farmer_costas_push.png`).

## Não feito

- O fazendeiro ainda não substitui a cápsula em `scenes/player/farmer.tscn` (fora do escopo; a cena
  `farmer_character.tscn` está pronta para isso).
- APK / teste em aparelho Android não executados.
