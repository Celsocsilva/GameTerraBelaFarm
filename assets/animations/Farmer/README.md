# Farmer — fazendeiro rigado com Rigify (padrão do jogo)

Fazendeiro (malha TRELLIS) limpo e otimizado para mobile, rigado com **Rigify** no Blender 5.3, com esqueleto de jogo
de **23 ossos** e **25 animações** da Universal Animation Library retargetadas para as proporções dele.
Padrão e convenção de nomes: `../RIG_STANDARD.md`.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `farmer.glb` | **Entregável do Godot**: malha + esqueleto de jogo + 25 animações + textura 512 (~1,5 MB) |
| `farmer_character.tscn` | Cena pronta: modelo (frente em –Z, como o jogo) + `FarmerAnimator` |
| `farmer_animation_controller.gd` | `FarmerAnimator`: parado/andar/correr/sprint, carregando, agachado, plantar, colher, ações |
| `blender/farmer_rigify.blend` | Fonte editável: metarig, rig Rigify (controles), esqueleto de jogo, malha, ações `RIG_*` (pasta ignorada pelo Godot) |
| `farmer_rigify_config.json` | Config do pipeline (reproduz tudo) |
| `textures/farmer_basecolor_512.png` | Textura do jogo (costas já corrigidas) |
| `textures/farmer_basecolor.png`, `..._original.png` | Textura 1024 corrigida e original do TRELLIS (fontes) |
| `source/farmer_trellis.glb` | Malha original (= `farmer_source.glb`) |
| `preview/` | Folhas de contato renderizadas no Blender (ignorada pelo Godot) |
| `_legacy_ual_rig/` | Rig anterior (sem Rigify, 65 ossos, malha sem solda). Ignorado pelo Godot; pode ser apagado |

## O que mudou em relação ao rig anterior

| | Antes | Agora |
|---|---|---|
| Malha | 200 pedaços soltos, 3.696 arestas abertas → rachaduras/linhas claras ao dobrar | 1 peça fechada, 0 arestas abertas, normais para fora, sombreamento suave |
| Triângulos | 7.962 | 6.000 |
| Textura | 1024² + cópia extraída | 512² |
| Ossos no jogo | 65 (40 de dedos sem uso) | 23 |
| Rig de animação | esqueleto simples | Rigify (FK/IK, torso, pés com IK) |
| Pesos | distância aos ossos, por ilha | bone heat na malha fechada, suavizados, ≤ 4, normalizados |
| `.glb` | 5,6 MB | 1,4 MB |
| Godot | não testado | teste automático + capturas (ver `docs/evidence/farmer-rig-001.md`) |

## Animar no Blender

Abra `blender/farmer_rigify.blend`. Selecione `Farmer_Rigify`, escolha uma ação `RIG_<Nome>` (ou desmute a faixa NLA
dela) e anime os controles. O `Farmer_Armature` e a malha acompanham. Para exportar de novo, rode o pipeline ou faça
o bake no `Farmer_Armature` (ver `RIG_STANDARD.md`, seção 4).

## Limitações conhecidas

- Mãos em luva (sem dedos), como na arte original.
- `Carry_*` é a animação de andar/parado com os braços travados segurando à frente; a caixa deve ser presa no jogo
  (`BoneAttachment3D` em `spine_03`).
- Pernas curtas: as velocidades de referência do `FarmerAnimator` são estimativas para o modelo em escala 1; calibre
  olhando os pés depois de colocar no `CharacterBody3D` (o jogo hoje usa uma cápsula de 1,8 m).
- As costas da textura TRELLIS continuam um pouco mais escuro que a frente (correção por ganho, não repintura).
