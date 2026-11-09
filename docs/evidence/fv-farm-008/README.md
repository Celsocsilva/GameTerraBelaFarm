# FV-FARM-008 — Canteiro de tomate a 3x do balcão e parcela extra

Data: 2026-11-08. Alteração feita só na pasta local (sem commit/push).

## Interpretação adotada

1. **"3 vezes a distância atual até o balcão"** = a faixa de grama entre a borda
   do canteiro voltada para o balcão e a frente do balcão. Era 4,02 m e passou a
   12,07 m. O canteiro recuou 8,05 m para o norte (−Z): borda de z = 2,30 → −5,75.
   Tamanho, 3 tiras e 81 células não mudaram.
   - Alternativa não usada: distância centro a centro (12,3 m → 37 m), que
     levaria o canteiro para perto da borda norte do mapa.
2. **"Área quadrada com 10% da área do terreno"** = parcela extra com a mesma
   textura de solo (`plowed_soil_three_furrows.png`), área = 10% do canteiro
   (191,31 m² → 19,13 m²). Ela é **quadrada na tela**: 2 tiras da mesma arte,
   escala uniforme (sem distorcer o PNG), 3,63 m × 5,27 m no chão, que a câmera
   a 45° mostra como ~1:1 (altura/largura 1,026).
   - Se a ideia era quadrada no chão (4,37 m × 4,37 m), na tela ela pareceria
     achatada; dá para trocar.
3. **A parcela extra é só visual por enquanto** (sem células de plantio), para
   não mudar a regra da safra (o canteiro só reabre quando todas as células são
   colhidas). Fica 2 m a leste do canteiro, alinhada ao seu centro, longe do rio
   (oeste), do balcão, do dinheiro e das pontes.

## Efeitos colaterais necessários

- O fazendeiro nascia em (0, 0), que agora fica dentro do canteiro: passou a
  nascer 2 m ao norte dele, em z = −7,75.
- A cerca e o galpão provisórios ficavam dentro do novo canteiro: foram para
  z = −12,5 e −13,0, fora do caminho da ponte de madeira (z = −9,6).
- A máscara de decoração (`CozyEnvironment`) recebe as posições de cerca,
  galpão e parcela extra do `FarmWorld` (`blocked_rects`) em vez de valores fixos.

## Arquivos

- `scripts/world/farm_world.gd` — constantes do layout, parcela extra, spawn, obstáculos.
- `scripts/world/cozy_environment.gd` — `blocked_rects` e corredor relativo ao canteiro.
- `tools/farm_smoke.gd` — novo `_check_layout` (gap 3x, 10%, quadrada na tela, fora de rio/balcão/dinheiro/pontes).
- `tools/harvest_smoke.gd` — caminho da caminhada acompanha o canteiro.
- `tools/environment_smoke.gd` — teste de semente copia `blocked_rects`.
- `tools/farm_layout_capture.gd` — capturas desta pasta.

## Validação

Todos headless, código de saída 0: farm_smoke (`LAYOUT_OK gap=12.074 (antes 4.024) ratio=0.1000 screen_aspect=1.026`),
harvest_smoke, customer_smoke, sales_counter_smoke, hud_smoke, environment_smoke,
environment_expansion_smoke, river_smoke e angle_audit.

Capturas (1280x720, `--path . -s tools/farm_layout_capture.gd -- <pasta>`):
01 canteiro até o balcão, 02 visão geral com rio e pontes, 03 parcela extra, 04 visão de jogo inicial.
