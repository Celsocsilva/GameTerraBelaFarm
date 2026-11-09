# FV-WOOD-001/002 — Eucaliptos com estações, corte e venda de madeira

Data: 2026-11-09 · Godot 4.7.2 · alterações locais (sem commit).

## Arte (organizada a partir das 8 imagens enviadas)
Recortadas (sem a margem transparente) e reduzidas (árvores 512 px de altura, fardos 256 px), mipmaps ligados.

| Arquivo | Imagem original | Uso |
|---|---|---|
| `assets/props/trees/eucalyptus/eucalyptus_spring.png` | verde-claro com brotos (14_31_23) | primavera |
| `assets/props/trees/eucalyptus/eucalyptus_summer.png` | verde-escuro (14_31_21) | verão |
| `assets/props/trees/eucalyptus/eucalyptus_autumn.png` | pontas alaranjadas, folhas no chão (14_31_22) | outono |
| `assets/props/trees/eucalyptus/eucalyptus_winter.png` | com neve (14_31_25) | inverno |
| `assets/props/trees/eucalyptus/eucalyptus_stump_cut.png` | toco + toras + galhos (14_31_26) | árvore cortada |
| `assets/items/logs/log_bundle_4.png` | fardo de 4 toras (14_41_14) | fardo incompleto (até 4 toras) |
| `assets/items/logs/log_bundle_6.png` | fardo de 6 toras (14_41_16) | fardo incompleto (5–6 toras) |
| `assets/items/logs/log_bundle_8.png` | fardo de 8 toras (14_41_13) | fardo cheio (8 toras) |

## Onde ficam as árvores (`FarmWorld.get_eucalyptus_points()`)
23 eucaliptos, sem colisão (não fecham passagens), em fileiras com zigue-zague leve:
- bordas de trás (norte) e oeste do canteiro de tomate e das áreas de milho e abóbora;
- margem leste do rio (lado da fazenda), a 1,2 m dos tiles com a margem ilustrada.
Ficam de fora: frente dos canteiros (lado do balcão), corredor central de acesso, cabeceiras e
acessos das pontes, entorno do balcão, placas, estoques, plataformas, a árvore provisória e o
ponto onde o fazendeiro nasce. A decoração do CozyEnvironment não nasce em cima delas.

## Estação (`scripts/forestry/season_clock.gd`)
Data do aparelho + hemisfério. Padrão "auto": país do idioma do aparelho (pt_BR → sul).
Estações por meses inteiros: no sul dez–fev verão, mar–mai outono, jun–ago inverno, set–nov
primavera; no norte o inverso. Configurável sem mexer no código, em Projeto > Configurações
(chaves opcionais, não adicionadas ao project.godot):
- `terrabela/seasons/hemisphere` = `auto` | `north` | `south`
- `terrabela/seasons/force_season` = `spring` | `summer` | `autumn` | `winter` (vazio = data real)
O `EucalyptusGrove` também tem `hemisphere_mode` e `forced_season`. A estação é revista a cada
30 s; se virar com o jogo aberto aparece o aviso "Outono chegou: os eucaliptos mudaram".

## Mecânica
1. Fazendeiro a até 1,5 m de um eucalipto em pé → corta por 0,6 s (a árvore treme). Saindo de
   perto, o corte cancela.
2. A árvore vira o toco cortado; 4 toras voam para a mochila (mesmo fluxo de reserva da
   colheita: só entram ao chegar).
3. O toco fica 4 s e some; a árvore rebrota 90 s depois, com a arte da estação.
4. Mochila: um produto por vez. As toras usam as mesmas 7 vagas × 8 unidades das caixas; o
   fardo de 8 toras é a "caixa" da madeira (fardo de 4 ou 6 enquanto incompleto). Com tomates
   na mochila o corte não começa (aviso), e com toras na mochila o tomate não é colhido (aviso
   ao entrar no canteiro). O contador de tomates da HUD conta só tomates.
5. Balcão: encostar descarrega tudo; os fardos pulam das mãos para a pilha da madeira, na vaga
   da esquerda do balcão (TomatoPile reaproveitada). Os clientes compram 1–3 fardos; com tomate
   e madeira à venda, cada cliente sorteia um dos dois. Cliente leva os fardos nos braços.
6. Preço: 6 por fardo de 8 toras (proporcional para fardo incompleto), `WoodConfig.PRICE_PER_BUNDLE`
   ou `SalesController.wood_price_per_bundle`.

## FV-WOOD-002 (2026-11-09, segunda rodada)
### Floresta no canto sudoeste
`FarmWorld.EUCALYPTUS_FOREST` (x -30,5..-12,5, z 12..30,5): grade hexagonal (2,4 × 2,1 m) com
desvio fixo de até 0,3 m, ao sul da curva do rio até a borda do mapa, dos dois lados da cerca
do balcão. Mesmas exclusões das fileiras (rio e margens, pontes, faixa da cerca, balcão).
Agora são 60 eucaliptos no total, 36 no canto e 29 abaixo da cerca. As árvores abaixo da cerca
ficam fora do alcance do fazendeiro (a cerca do balcão fecha o mapa até a borda) e servem de
paisagem.

### Pontes novas
As 4 artes enviadas substituíram as do jogo com os mesmos nomes em `assets/bridges/`
(`bridge_wood_rope.png`, `bridge_stone_lantern.png`, `bridge_approach_left.png`,
`bridge_approach_right.png`); as antigas continuam no histórico do Git. As artes novas são de
frente (travessia oeste–leste), então os pontos em px das cenas foram refeitos:
`BridgeWood.tscn` e `BridgeStone.tscn` (bordas do tabuleiro, arco 0,55/0,45 m, máscara do
corrimão da frente, acessos de 6 m colados nas cabeceiras, postes com colisão). Posições das
pontes no rio e bloqueio da água inalterados; `river_smoke` atravessa as duas sem molhar.

### Queda do pinheiro no ritmo do machado
- Estágios em `assets/props/trees/eucalyptus/fall/` (mesmo recorte para não pular de lugar):
  `01_whole` (15_37_34), `02_notch` (15_37_35), `03_deep_cut` (15_37_36), `04_leaning`
  (15_37_38), `05_fallen` (15_37_39), `06_stump_logs` (15_37_40).
- Machado: os 8 quadros do `axe_only_animation.gif` em `assets/vfx/axe/axe_chop_01..08.png`,
  com a duração original de cada quadro (0,89 s por golpe). O machado aparece entre o
  fazendeiro e a árvore e é espelhado quando a árvore está à direita.
- Ritmo (`WoodConfig`): 3 golpes, cada um no quadro de impacto (3º quadro) → entalhe, corte
  fundo, inclinada; 0,35 s depois cai; 0,45 s depois vira o toco com as toras e as 4 toras voam
  para a mochila. Corte inteiro: 2,82 s. Sair de perto antes da inclinação cancela e a árvore
  volta inteira. O toco com toras (estágio 6) substitui o toco anterior
  (`eucalyptus_stump_cut.png`, que ficou sem uso).
- Os estágios são verdes; no outono/inverno a árvore troca para a arte verde no primeiro golpe.
- Capturas: `wood-001/03-queda-1..6-*.png` e `03-queda-sequencia.png`,
  `06-floresta-canto-sudoeste.png`, `07-ponte-de-madeira.png`, `08-ponte-de-pedra.png`.

## Números provisórios (aguardam decisão) — `scripts/forestry/wood_config.gd`
| Item | Valor | Comparação |
|---|---|---|
| Toras por árvore | 4 | 2 árvores = 1 fardo |
| Preço do fardo (8 toras) | 6 | caixa de 8 tomates = 3 |
| Tempo de rebrota | 90 s (+4 s de toco) | ciclo do tomate ≈ 60 s |
| Tempo de corte | 3 golpes, 2,8 s | — |

## Testes
- Novo `tools/wood_smoke.gd` (WOOD_SMOKE_OK trees=23): regras de estação/hemisfério,
  traduções PT/ES/EN, posições (fora do rio, dos canteiros, do balcão; perto das bordas e do
  rio), arte das 4 estações, corte → toco → voo → mochila (fardo 4 e 8), cancelamento, toco some
  e rebrota, um produto por vez, depósito no balcão, venda com preço e cliente levando o fardo.
- Smoke tests existentes: todos OK, exceto `hud_smoke.gd`, com a mesma falha antiga do texto do
  modal de recompensa ("Coletar recompensa agora"), que já existia antes desta mudança.

## Capturas (`tools/wood_capture.gd`, renderer real, 1280×720)
- `wood-001/01-visao-geral-eucaliptos-*.png` — mapa inteiro com as fileiras
- `wood-001/02-estacao-{spring,summer,autumn,winter}.png` — mesma borda nas 4 estações
- `wood-001/04-fazendeiro-com-fardo-de-toras.png` — fardo de 8 toras nas costas
- `wood-001/05-balcao-madeira-e-tomate.png` — madeira e tomate à venda no balcão
