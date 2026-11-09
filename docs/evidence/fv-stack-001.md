# FV-STACK-001 — Banca plana e pilha única por cultura

Data: 2026-11-08 · Godot 4.7.2.

## O que mudou
- Banca de vendas de volta à arte plana `assets/sales/stall_market_gingham.png` (origem: Downloads
  "Balcão de Feira Campestre xadrez.png", já recortada e reduzida para 2048x534 no FV-PROPS-001).
  A arte funda `stall_market_gingham_deep.png` continua no projeto, sem uso. `STALL_CLOTH_CENTER`
  0,27: a base da pilha fica no meio da toalha. Mesma largura (11,05 m), colisão, cercas, fila,
  pilha de dinheiro e distância do terreno.
- Novo `scripts/farming/crate_stack.gd` (`CrateStack`): regras comuns das pilhas. Cada cultura tem
  uma única pilha vertical; vagas em X por cultura (tomate no meio, milho à esquerda, abóbora à
  direita; 3,6 m no balcão, 1,2 m na parcela), sem sobreposição e dentro do balcão/parcela.
- `SalesCounter`: no máximo 4 caixas visíveis (`MAX_VISUAL_CRATES`); `get_displayed_crates()` agora
  é a contagem lógica sem limite. Acima de 4, um contador "x18" (Label3D, fonte do projeto) aparece
  acima da pilha. Caixas que pulam além do limite pousam no topo.
- `TomatoPile` (parcela de 10%): capacidade lógica continua 27 caixas, no máximo 5 visíveis
  (`VISUAL_MAX`) e o mesmo contador.
- O modal de recompensa não mudou.

## Validação
- Novo `tools/crate_stack_smoke.gd` → `CRATE_STACK_SMOKE_OK` (15 caixas lógicas = 4 visíveis +
  "x15", todas as caixas na mesma coluna, vagas das 3 culturas sem sobrepor e dentro do balcão,
  venda volta a 4 sem contador, caixa parcial no topo, 7 caixas com pulos, parcela 27 = 5 + "x27").
- Ajustados `sales_counter_smoke`, `stall_signs_smoke` (arte plana, base na toalha) e `helper_smoke`.
- Suíte inteira verde: farm, harvest, customer, sales_counter, hud, environment,
  environment_expansion, river, angle_audit, helper, stall_signs, crate_stack.
- Capturas reais 1280x720: `fv-stack-001/banca/` (18 caixas → pilha de 4 + "x18") e
  `fv-stack-001/parcela/` (pilha da parcela com "x10").
