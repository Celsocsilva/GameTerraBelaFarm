# FARM-004 — contratação, semeadura e polimento (09/11)

Capturas: `godot --path . --resolution 1280x720 -s tools/farm004_capture.gd -- <pasta>` (OpenGL, xvfb).
Testes novos/atualizados: `tools/flicker_smoke.gd`, `helper_smoke`, `corn_smoke`, `pumpkin_smoke`, `farm_smoke`, `farm003_smoke`.

| Pedido | Como ficou | Captura |
|---|---|---|
| Contratar ajudante não descarregava nem contava os fardos | O material (20 fardos de madeira / 20 caixas de tomate / 20 de milho) agora sai da MOCHILA na própria plataforma: um fardo/caixa a cada 0,16 s voa das costas até o ícone e o contador "n/20" sobe a cada pouso. Sair da plataforma guarda o que já foi entregue (salvo em `material_units`). Componente compartilhado `HelperPad`/`HelperHiring`: vale para tomate, milho e abóbora. O estoque do balcão NÃO conta mais. | 02a, 02b |
| Semeadura mais longe, grãos menores, mais orgânica | Alcance 3 -> 5 plantas à frente, leque que abre para os sulcos vizinhos, até 12 covas por passo; punhados saem em sequência (perto -> longe), pousam com desvio aleatório e deixam rastro alongado; grãos ~40% menores. | 03a, 03b |
| Cercas orgânicas e 20% maiores | `FenceRun`: peça 20% maior + inclinação, avanço/recuo e altura variando por peça; curral: postes/portão/travessas 20% maiores e postes tortos. | 07a, 07b, 06 |
| Árvores tipo ipê 20% maiores | `tree_pink_blossom` (a de flor rosa) com `IPE_SCALE 1.2`. | 04 |
| Cintilação ao carregar abóbora/milho | Causa: as caixas da mochila ficavam no MESMO plano e brigavam pela profundidade (listras piscando; forte na abóbora, que é 25% mais larga, e leve no milho). Agora cada caixa fica 4,5 cm mais perto da câmera, em qualquer giro do fazendeiro. Também: recortes das artes de estágio pré-calculados e artes pré-carregadas na abertura (antes, cada estágio novo travava 25–55 ms no PC). | 10 |
| pumpkin_smoke (2 falhas antigas) | Eram falhas do TESTE: fazendeiro longe demais (colheita cancelada) e contador de replantio que não somava (lambda). Corrigidas; o jogo não tinha bug ali. | — |
| Casa no gramado indicado na captura + mais 20% (2ª rodada) | 7,0 -> 10,08 m (x1,44). Base (-25,0; 1,5): a oeste do rio, à esquerda da ponte de madeira e acima da ponte de pedra. Coube sem expandir o mapa (~2 m da borda oeste, 2,5 m da saída da ponte de pedra). Barris/árvores não nascem atrás do telhado. | 05, 05b |
| Fileiras orgânicas em todas as culturas | `PlantingGrid`: onda do sulco com 2 frequências, desvios e tamanhos maiores (±10%). | 08, 09, 03b |
| Solo wide em todos os cultivos | Tomate, milho, abóbora e parcelas de estoque com `plowed_soil_three_furrows_wide.png` (600x926). Área mantida: tira 12,6% mais larga e mais curta; frente do canteiro de tomate no mesmo lugar. | 01, 03, 08 |
| Milho 10% maior + mais 20% (2ª rodada) | Alturas e largura máxima x1,32. | 08 |
| Curral 10% menor + arbustos e pinheiros | 15,5x11 -> 14,70x10,44 m (mesmo canto); 7 pinheiros (atrás e a leste) e 8 arbustos (frente/cantos), nada na frente do portão. | 06 |

Pendências para decidir:
- Material da contratação só pela mochila (o estoque do balcão deixou de contar). Se preferir aceitar os dois, é uma troca pequena.
- A parcela de estoque com 2 peças do solo largo ficou um pouco mais larga que alta na tela (0,81 em vez de quadrada).
- `hud_smoke` continua com a falha antiga do texto "Coletar recompensa agora".
