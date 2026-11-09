# CROP-AREAS-001 + ENV-FENCE-001 — Áreas de milho e abóbora e cerca de madeira

Data: 2026-11-09 · Godot 4.7.2 · alterações locais (sem commit).

## Cerca (ENV-FENCE-001)
- Novo componente `scripts/world/fence_run.gd` (`FenceRun`): trecho reto de cerca com
  `assets/fences/coop_fence_02.png`, a única peça da pasta desenhada de frente (as outras são
  diagonais e não combinam com a câmera, que olha de +Z). Peças vizinhas dividem o poste da
  junta: o trecho começa e termina num poste e os vãos ficam iguais (~2,6 m, sem esticar a arte
  mais que 25%). Altura compensada pela câmera de 45°, como placas e caixas.
- Trocadas as duas cercas que eram caixas coloridas:
  - cerca provisória ao norte (`Fence`, 5 m): mesma posição e mesma colisão;
  - cercas laterais do balcão (`CounterBarrier_L/R`, de ponta a ponta do mapa): mesma colisão,
    os trilhos e postes de caixa saíram.
- A decoração não nasce mais colada atrás da cerca do balcão (faixa reservada).

## Áreas de cultura (CROP-AREAS-001)
`FarmWorld.CROP_AREAS` define milho (leste, canto em x 19, z -8) e abóbora (norte, canto em
x -4, z -30). Cada área reaproveita os componentes existentes:
- canteiro: 2 tiras com a mesma arte do solo do tomate (escala 0,75), meta `crop`;
- placa da cultura: `CropSign`, criada sozinha pelo meta `crop` (Milho/Maíz/Corn, Abóbora/Calabaza/Pumpkin);
- área de estoque: parcela de 10% da área do canteiro, a leste, com uma `TomatoPile` da cultura
  (`item_id` corn/pumpkin, pilha centrada);
- plataforma de contratar o ajudante no chão: `HelperPad` com `HelperHiring` próprio.

Distâncias: cada área fica a pelo menos 6 m de qualquer outra (incluindo estoque e plataforma),
fora do rio, sem bloquear as saídas das pontes, longe do balcão/cerca, da construção e da cerca
provisória, dentro do mapa e longe do ponto onde o fazendeiro nasce.

### Por que as plataformas estão "Em breve"
Ainda não existe arte de crescimento de milho e abóbora (só tomate em `assets/crops/tomato/stages`),
nem arte de caixa dessas culturas (`crate_full.png` mostra tomates). Então os canteiros novos não
entram no `PlantingGrid` e a plataforma fica bloqueada: aparece acinzentada com "Em breve", não
cobra nem contrata, e ao pisar nela a faixa de avisos mostra "Milho em breve!". Quando a arte
existir, basta marcar a área como `plantable` e ligar um `PlantingGrid`/`FarmHelper` por área.

## Validação
- `tools/crop_areas_smoke.gd` → `CROP_AREAS_SMOKE_OK areas=2` (cercas, áreas, plataformas
  bloqueadas sem cobrar e modal grande).
- Demais smokes: ver relatório no thread. `tools/stall_signs_smoke.gd` passou a esperar 3 placas.
- Capturas: `tools/crop_areas_capture.gd` → `docs/evidence/crop-areas-001/`
  (visão geral, área do milho, área da abóbora, cerca provisória, cerca do balcão).
