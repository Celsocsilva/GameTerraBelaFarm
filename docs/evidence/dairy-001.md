# DAIRY-001/002 — leite das vacas e compra de vacas (10/11/2026)

Pedido do Celso (DAIRY-001): uma área para colher o leite em garrafas (arte `assets/resources/milk-bottom.png`) e uma área para comprar vacas, cada uma por 200 dinheiros e mais 20 caixas de milho.

Ajustes do Celso no mesmo dia (DAIRY-002): começar com 1 vaca e liberar as outras pela compra; cada vaca nova espera ao menos 20 s até as primeiras garrafas; depois só dá leite quando recebe milho, em intervalos aleatórios e na proporção do milho que come; área de ordenha incorporada ao curral com a arte da casinha de ordenha; placa de compra só com "Vacas" (Cows / Vacas).

## Como funciona

- **Curral** (`CowPen`): começa com 1 vaca. Ficou 3,5 m mais largo (leste) e 1,4 m mais fundo (norte). A **casinha de ordenha** (`assets/buildings/dairy/milking_house_cozy.png`, arte do Celso) fica no canto superior direito de dentro do curral (nordeste) e está 20% maior (DAIRY-003). Atrás da cerca da frente fica o **cocho** (caixas de milho). As vacas não andam por cima dos dois nem atravessam o caminho deles. Os pinheiros do leste ficaram mais perto da cerca.
- **Cocho** (`FeedTrough`, `scripts/dairy/feed_trough.gd`): não tem mais piso (DAIRY-003). O fazendeiro chega com milho na mochila e encosta em qualquer lado da cerca (até 1,3 m dela); as caixas voam uma a uma por cima da cerca até o cocho (até 9 caixas = 72 espigas).
- **Leite** (`MilkStation`, `scripts/dairy/milk_station.gd`): cada vaca espera 20 s desde que chegou (a primeira, desde o começo do jogo). Depois, a cada 5 a 11 s (aleatório) ela tenta comer: uma espiga voa do cocho até ela e ela dá 1 garrafa, que voa até a área "Leite", do lado de fora da cerca leste, ao lado da casinha. Sem milho ela não dá leite (aviso "As vacas estão com fome!" com o fazendeiro perto do curral, no máximo a cada 30 s). Com a área do leite cheia (27 caixas) ela não come e o milho fica no cocho. A cada 8 garrafas forma-se uma caixa (`assets/harvest/crate_milk_full.png`).
- **Recolha e venda**: pisando na área do leite, as caixas vão para a mochila. No balcão, o leite tem vaga própria (5 vagas: milho, tomate, abóbora, leite, madeira).
- **Vacas** (plataforma de compra, mesmo fluxo da contratação do ajudante): título "Vacas", contagem "1/7" (FARM-005: teto de 7 vacas, uma de cada cor), preço 200 e "0/20" de milho. O dinheiro sai um a um, e as caixas de milho saem da mochila uma a uma. Sem as 20 caixas a plataforma guarda no máximo 199. Sair pausa sem perder nada. A vaca nova entra pelo portão e começa a contar os 20 s dela.
- Textos PT/ES/EN em `localization/ui.csv`: `MILK_NAME`, `MILK_AREA_TITLE`, `COW_SHOP_TITLE` (Vacas/Vacas/Cows), `COW_SHOP_COUNT`, `COW_BOUGHT`, `COW_NO_MONEY`, `COWS_HUNGRY` (agora pede para encostar na cerca). `COW_FEED_TITLE` saiu.

## Mapa ampliado (MAP-003)

- O mapa cresceu cerca de 15% para a esquerda, para a direita e para o topo: 11,6 m de cada lado (15% dos 77,44 m de largura). A frente (balcão) não mudou. Li "15%" como 15% em cada lado; se a ideia era 15% no total, basta mudar `MAP_SIDE_EXTENSION` em `scripts/world/farm_world.gd`.
- O rio (`scenes/world/river/RiverSystem.tscn`) foi esticado nas pontas para continuar saindo pela nova borda oeste. As barreiras do balcão vão até as novas bordas.
- `BorderForest` (`scripts/world/border_forest.gd`) espalha as duas árvores enviadas (`assets/decor/trees/tree_round_leafy.png` e `tree_pine_tall.png`) nas faixas novas, com clareiras e manchas de cada espécie (ruído), tamanhos e espelhamento aleatórios, longe do rio e da fazenda antiga. Cada árvore tem tronco com colisão.
- FOREST-002: as árvores ficaram 20% maiores (`SIZE_SCALE` 1,2) e mais densas (passo da grade 3,1 → 2,5 m). Numa faixa de 5 m junto à borda externa não há clareiras, para a borda ficar fechada (o teste confere que nenhum ponto da borda fica a mais de 3,2 m de uma árvore, fora o rio). Hoje são 232 árvores, 126 delas pinheiros.

## Números provisórios (`scripts/dairy/dairy_config.gd`)

| Item | Valor |
|---|---|
| Vacas | 1 no começo, até 7 (6 compráveis; FARM-005) |
| Espera da vaca nova | 20 s |
| Refeição | 1 espiga a cada 5–11 s (aleatório) |
| Proporção | 1 espiga = 1 garrafa (1 caixa de milho = 1 caixa de leite) |
| Preço da caixa de leite | 5 (tomate 3, milho 4, abóbora 6, madeira 6) |
| Cocho / área do leite | 9 caixas de milho / 27 caixas de leite |
| Vaca | 200 dinheiros + 20 caixas de milho, em toda compra |

## Testes

- `tools/dairy_smoke.gd`: layout (casinha 20% maior no canto nordeste, cocho dentro do curral, leite e placa fora), mapa +15% nos 3 lados, floresta (pelo menos 80 árvores e 20 de cada espécie), rio na borda oeste nova, milho entregue encostando na cerca, 1 vaca inicial, espera de 20 s, leite só com milho, proporção 1:1, fome, área cheia, espera da vaca comprada, descarregar o milho no cocho (com limite), recolha, venda, compra com milho em 3 viagens, teto de 7 vacas e traduções. OK.
- `tools/farm003_smoke.gd`, `farm_smoke`, `pumpkin_smoke`, `environment_smoke` e `river_smoke` atualizados (1 vaca inicial, mapa novo). Os demais smokes passam; o `hud_smoke` tem a mesma falha antiga do modal de recompensa.
- Capturas: `tools/dairy_capture.gd` em `docs/evidence/dairy-001/` (a vista geral compra 3 vacas direto para mostrar o curral com mais vacas).

## Código mexido

`HelperHiring` com preço fixo, teto próprio e material em toda compra (`fixed_cost`, `max_grade`, `requirement_every_grade`, `requires_material()`). `HelperPad` com `title_key`, `grade_key`, `grade_offset` e marcadores que encolhem acima de 5 graus. `CowPen` com `initial_cows`, `house_rect`, `feeder_rect`, `get_cow_rect()`, `add_cow()` e `keep_clear`. `FarmCow.celebrate()`, `ItemArt` (leite), `SalesCounter`/`SalesController` (vaga e preço do leite), `FarmWorld._build_dairy()`.
