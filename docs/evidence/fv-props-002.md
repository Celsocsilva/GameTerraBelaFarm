# FV-PROPS-002 — Banca de vendas com toalha xadrez mais funda

Data: 2026-11-08 · Godot 4.7.2 · alterações locais (sem commit).

## O que mudou
- Nova arte `assets/sales/stall_market_gingham_deep.png` (Downloads "Balcão de feira campestre
  profundo.png", 2170x725): recortada na área opaca e reduzida para 2048x685 com 5 px de margem
  transparente, mesmo tratamento da banca anterior (proporção e transparência preservadas; PNG em LFS
  pelo `.gitattributes`). A arte antiga `stall_market_gingham.png` continua no projeto, sem uso.
- `scripts/farming/sales_counter.gd`: `STALL_TEXTURE` aponta para a arte funda e
  `STALL_CLOTH_CENTER` 0,20 → 0,22 (meio do tampo de toalha na nova arte).
- Escala e colisão NÃO mudaram: largura na cena 11,05 m, colisão 11,05 x 1,6 x 3,195 m, pegada,
  cercas, fila de clientes, pilha de dinheiro e distância do terreno iguais. Como a arte é mais alta
  na mesma largura, o quadro inclinado sobe de 1,15 m para ~2,30 m atrás e as caixas sobem junto
  com a toalha (fileiras a 0,096 e 0,344 da altura da arte, dentro da toalha).

## Validação
- `tools/stall_signs_smoke.gd`: caminho da arte nova, colisão/pegada inalteradas, caixas na frente
  do quadro e dentro da toalha → `STALL_SIGNS_SMOKE_OK`.
- `tools/angle_audit.gd`: banca na proporção exata do PNG na tela → `ANGLE_AUDIT_OK`.
- customer_smoke e sales_counter_smoke verdes (fila e vendas sem mudança).
- Capturas reais (`tools/stall_signs_capture.gd`): `docs/evidence/fv-props-002/antes/` e
  `depois/`; comparativos lado a lado `00-comparativo-banca.png` e
  `00b-comparativo-banca-distancia.png` (esquerda antes, direita depois).
