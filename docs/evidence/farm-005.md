# FARM-005 — caminhos, construções, folga dos cultivos, 7 vacas e regra de semeadura (10/11/2026)

Pedido do Celso:

1. Retirar ou mudar de lugar o que invade as áreas de cultivo ou fica muito perto delas.
2. Máximo de 7 vacas, em todos os controles.
3. Quando existem frutos maduros, só se semeia depois que todos forem colhidos, em todos os cultivos.
4. Implementar os caminhos do terreno e incluir outras construções da biblioteca de assets.

## O que mudou

| Pedido | Como ficou |
|---|---|
| Folga dos cultivos | Árvores, props e arbustos ficam a pelo menos 2,6 m dos lados e do fundo dos canteiros, e 4 m na frente (do lado da câmera, onde a copa subiria por cima das plantas). As pilhas ganharam 1,8 m de folga, e as plataformas e placas também ganharam mais espaço. As fileiras de pinheiros (eucalipto) foram para 3,2 m da borda. Constantes: `CROP_CLEARANCE`, `CROP_CLEARANCE_FRONT`, `CROP_STOCK_CLEARANCE` e `EUCALYPTUS_EDGE_GAP` em `scripts/world/farm_world.gd`. |
| 7 vacas | `DairyConfig.MAX_COWS = 7` (uma de cada cor). A placa mostra "1/7" e tem 6 marcadores. A compra para no teto e `CowPen.add_cow()` não passa de 7. |
| Regra de semeadura (corrigida no FARM-006) | É um ciclo. **Plantando**: pode semear o terreno todo, mesmo que os primeiros pés já tenham amadurecido. Na primeira versão, um pé maduro travava o resto do plantio, e esse era o bug. **Colhendo**: a colheita começou em qualquer cultivo (`FarmWorld.harvest_phase`), então ninguém semeia, nem o fazendeiro andando pelo canteiro nem os ajudantes. **Tudo colhido**: quando nada do que foi plantado ficou por colher (crescendo, maduro ou sendo colhido), em todos os cultivos, as covas colhidas reabrem e a semeadura volta. Código: `FarmWorld.can_sow()`, `PlantingGrid.has_pending_crop()` e `reopen_harvested()`. |
| Caminhos | `FarmPaths` (`scripts/world/farm_paths.gd`) cria 16 caminhos de terra, com cerca de 290 m no total. Ligam o balcão, a frente do tomate, a plataforma do ajudante, o corredor do norte (milho e abóbora), as duas pontes, a casa, o galinheiro, o curral (portão e placa "Vacas"), a área do leite e as construções novas. As curvas são suavizadas e as bordas têm ruído. A terra vem da arte `assets/terrain/path_cross.png`, tornada contínua por `tools/art/gen_path_dirt.py` (`assets/terrain/path/path_dirt_seamless.png`). Árvores e props não ficam em cima dos caminhos. |
| Construções | `FarmBuildings` (`scripts/world/farm_buildings.gd`), por enquanto só cenário, com colisão no corpo: celeiro (`barn.png`) e paiol (`granary.png`) no pasto leste, galinheiro (`chicken_coop.png`) a oeste da casa, oficina (`industry/workshop.png`) e galpão de máquinas (`industry/machine_shop.png`) ao norte do milho. Todos ficam longe dos canteiros, do rio, das pontes e do curral, e cada um tem um caminho até a frente. Ficaram de fora: igreja, mercado, clínica veterinária, casa simples e os galpões de ordenha (a casinha de ordenha já está no curral). |

## Testes

- `tools/farm005_smoke.gd`: os caminhos ficam dentro do mapa e fora de canteiros, pilhas, rio (só cruzam nas pontes) e construções. As construções ficam longe de canteiros, rio, pontes, curral e casa. Nenhuma vegetação (pinheiros, floresta da borda, decoração e vegetação do curral) fica dentro da folga dos canteiros/pilhas ou em cima de caminhos.
- `tools/sow_rule_smoke.gd` (ciclo completo): com um pé maduro ainda se planta o terreno todo dos três cultivos. Depois que a colheita começa, ninguém semeia (cova colhida, o fazendeiro andando e o ajudante). Colher tomate e milho e deixar a abóbora ainda trava. Com tudo colhido, as covas reabrem e se semeia o terreno todo de novo. O `harvest_smoke` agora aceita a cova reaberta depois da última colheita.
- Ajustados para as mudanças: `dairy_smoke` (1/7, teto de 7), `wood_smoke` e `polish_smoke` (fileiras afastadas dos canteiros) e `farm003_smoke` (o caminho do curral tira alguns arbustos). Os outros smokes passam; o `hud_smoke` tem a falha antiga do modal de recompensa.

## Capturas (`docs/evidence/farm-005/`, `tools/layout_capture.gd`)

01 mapa inteiro; 02–04 tomate, milho e abóbora de perto; 05–09 as construções; 10 casa, galinheiro e pontes; 11 curral, leite e "Vacas".
