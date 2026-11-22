# Farmer — personagem rigado (padrão UAL)

Personagem “Fazendeiro” (malha TRELLIS, 7.962 triângulos, 1 m de altura) com esqueleto padrão de 65 ossos e as
43 animações da Universal Animation Library já convertidas para as proporções dele.
Padrão completo em `../RIG_STANDARD.md`.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `farmer.glb` | **Entregável para o Godot** (malha + esqueleto + 43 animações + textura embutida) |
| `farmer_animation_controller.gd` | Exemplo de controle (idle/andar/correr/sprint/agachar + ações) |
| `farmer_rig.blend` | Fonte editável (rig, pesos, animações retargetadas, UAL de origem oculta) |
| `farmer_pipeline_config.json`, `farmer_landmarks.json` | Entradas do pipeline (reproduzem este mesmo `.glb`) |
| `source/farmer_trellis.glb` | Malha original do TRELLIS (sem rig) |
| `textures/farmer_basecolor.png` | Textura com as costas corrigidas (usada no `.glb`) |
| `textures/farmer_basecolor_original.png` | Textura original do TRELLIS |
| `preview/` | Folha de contato e GIFs (Idle, Walk, Jog) renderizados no Blender |
| `../tools/ual_rig_pipeline.py` | Script que gera tudo isso para qualquer personagem novo |

Observação: `farmer_rig.blend1` é o backup automático do Blender; pode ser ignorado no Git (`*.blend1`).

## Animações essenciais

- **Parar:** `Idle_Loop` (também `Idle_Talking_Loop`, `Idle_Torch_Loop`)
- **Andar:** `Walk_Loop` (também `Walk_Formal_Loop`)
- **Correr:** `Jog_Fwd_Loop`, `Sprint_Loop`
- **Fazenda:** `Interact`, `PickUp_Table`, `Push_Loop`, `Fixing_Kneeling`, `Crouch_Idle_Loop`, `Crouch_Fwd_Loop`, `Driving_Loop`, `Sitting_*`
- Lista completa por categoria em `../RIG_STANDARD.md`.

## O que foi verificado

- `.glb` lido e validado: 65 joints, 43 animações (Idle 2,5 s; Walk 1,33 s; Jog 0,92 s), sem NaN, pesos somando 1,0 em todos os vértices, no máximo 4 influências, material `metallic = 0`.
- Poses renderizadas no Blender (idle, andar, correr, sprint, interagir, pegar, empurrar, agachar, pular, sentar, morrer).
- O pipeline foi reexecutado do zero a partir do script e gerou um `.glb` equivalente (mesmos vértices, joints, animações e durações).

## Limitações conhecidas

- **Não testado dentro do Godot** (sem o Godot disponível durante a preparação). Na primeira importação, confira se `Idle_Loop`/`Walk_Loop` estão em loop e se não há avisos.
- Malha do TRELLIS não é fechada: de certos ângulos aparecem linhas claras finas nas costas do macacão em algumas poses (ex.: empurrar). Para câmera muito próxima vale uma limpeza/retopologia.
- Pesos calculados por distância aos ossos (não pintados à mão); funcionam bem para câmera de jogo, mas ombros/quadril em poses extremas podem ter pequenas deformações.
- Dedos: os 40 ossos existem (compatibilidade com as animações) mas não deformam a malha.
- Pernas curtas: o passo é curto; calibre a velocidade de reprodução pela velocidade de movimento para os pés não patinarem.
