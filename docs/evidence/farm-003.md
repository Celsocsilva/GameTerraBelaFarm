# FARM-003 — cultivos, casa do fazendeiro e curral (09/11)

Capturas: `godot --path . --resolution 1280x720 -s tools/farm003_capture.gd -- <pasta>` (renderer OpenGL, xvfb).
Teste: `godot --headless --path . -s tools/farm003_smoke.gd` -> `FARM003_SMOKE_OK`.

| Pedido | Como ficou | Captura |
|---|---|---|
| Abóbora com 2 peças do solo de 3 sulcos largo | `SOIL_TEXTURE_WIDE`, 2 peças, 36 covas, área igual às outras culturas | 02 |
| Barris 20% menores | `BARREL_SCALE = 0.8` (1,6–1,84 m) | 09 |
| Área dos cultivos 10% menor | `CROP_AREA_REDUCTION = 0.9` (tomate 1,53x) | 01, 03 |
| Fonte do número de dinheiro = recursos | Prêmio da missão 36 = progresso 36; topo direito já igual | 10-* |
| Tradução ao trocar idioma | missão, prêmio, nível, vendas, faixa, loja, placas, ajudante | 10/11/12-pt_BR/es/en |
| Placa do milho à esquerda como a da abóbora | `CROP_SIGN_OFFSET.x` nas duas | 04 |
| Casa do fazendeiro à esquerda antes do rio | base (-6,0; 18,4), 7 m, colisão 5,4 x 3,6 m | 05 |
| Plantações com enfileiramento orgânico | `PlantingGrid.organic_*`, `size_jitter` | 02, 03 |
| Curral com 7 vacas animadas e cores distintas | `CowPen` + `FarmCow`, 7 cores | 06, 07, 08 |

Vacas: arte já existente no projeto (3 cores, 8 quadros: parada, piscando, 4 de caminhada, pastando, feliz). As bordas tinham respingos vermelhos do recorte; o script `tools/art/gen_cow_variants.py` limpa e gera 4 cores novas por recoloração (sem Meshy, sem 3D).

Pendências para decidir: portão só visual (curral fechado, sem interação/produção de leite); posição da casa (alternativa: oeste do rio).
