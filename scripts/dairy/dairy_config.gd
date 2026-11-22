extends RefCounted
class_name DairyConfig
## DAIRY-001 (10/11): leite das vacas e compra de vacas.
## DAIRY-002 (10/11, pedido do Celso): começa com 1 vaca; cada vaca nova espera
## ao menos 20 s antes da primeira garrafa; depois só dá leite quando come
## milho do cocho, em intervalos aleatórios, na proporção do milho comido.
## Números PROVISÓRIOS (aguardando o Celso), reunidos aqui para ajuste.

const ITEM := &"milk"
## Vacas no curral no começo do jogo; as outras são compradas.
const INITIAL_COWS := 1
## Total de vacas no curral (1 inicial + 11 compráveis).
const MAX_COWS := 7
const MAX_EXTRA_COWS := MAX_COWS - INITIAL_COWS
## Tempo mínimo de uma vaca nova (ou do início do jogo) até a primeira garrafa.
const MILK_WARMUP := 20.0
## Depois do aquecimento, cada vaca tenta comer em intervalos aleatórios.
const EAT_INTERVAL_MIN := 5.0
const EAT_INTERVAL_MAX := 11.0
## Sem milho no cocho (ou área do leite cheia), tenta de novo depois disto.
const HUNGRY_RETRY := 1.0
## Proporção: cada espiga de milho comida vira MILK_PER_CORN garrafas
## (1 caixa de milho = 8 espigas = 8 garrafas = 1 caixa de leite).
const CORN_PER_MEAL := 1
const MILK_PER_CORN := 1
## Preço de uma caixa cheia (8 garrafas) no balcão. Tomate 3, milho 4,
## abóbora 6, fardo de madeira 6.
const PRICE_PER_CRATE := 5
## Capacidade da área do leite (caixas). Cheia, as vacas param de produzir.
const PILE_MAX_CRATES := 27
## Cocho de milho dentro do curral: até 9 caixas (uma camada 3 x 3).
const FEEDER_MAX_CRATES := 9
const FEED_ITEM := &"corn"

## Pedido do Celso: cada vaca custa 200 dinheiros e mais 20 caixas de milho,
## descarregadas da mochila na plataforma (como a contratação do ajudante).
const COW_PRICE := 200
const COW_CORN_CRATES := 20
const COW_CORN_ITEM := &"corn"
