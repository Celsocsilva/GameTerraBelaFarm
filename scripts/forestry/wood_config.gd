extends RefCounted
class_name WoodConfig
## Eucaliptos e madeira (FV-WOOD-001): números do corte, da rebrota e da venda
## num lugar só. Todos são provisórios e aguardam a confirmação do Celso.

## Item carregado na mochila e vendido no balcão.
const ITEM := &"wood"
## Toras que cada eucalipto cortado rende.
const LOGS_PER_TREE := 4
## Toras por fardo amarrado (o "caixote" da madeira). Igual às unidades por
## caixa da mochila, para a capacidade da mochila valer igual para tudo.
const LOGS_PER_BUNDLE := 8
## Preço de um fardo cheio de 8 toras no balcão (proporcional se incompleto).
## O tomate vale 3 por caixa de 8; um fardo exige cortar 2 árvores.
const PRICE_PER_BUNDLE := 6
## Golpes de machado até a árvore inclinar (FV-WOOD-002). Cada golpe é um
## ciclo da animação do machado (axe_only_animation.gif, 8 quadros, 0,89 s) e
## avança um estágio: 1º entalhe, 2º corte fundo, 3º inclinação.
const CHOP_HITS := 3
## Duração (ms) de cada quadro do machado, a mesma do GIF original.
const AXE_FRAME_MS: Array[int] = [110, 110, 120, 80, 90, 120, 120, 140]
## Quadro (0 = primeiro) em que a lâmina bate no tronco.
const AXE_IMPACT_FRAME := 2
## Velocidade da animação do machado (1,0 = a do GIF).
const AXE_SPEED := 1.0
## Segundos entre a árvore inclinada e a árvore caída no chão.
const FALL_SECONDS := 0.35
## Segundos entre a árvore caída e o toco com as toras (quando as toras saem).
const LOGS_SECONDS := 0.45
## Segundos que o toco cortado fica visível antes de sumir.
const STUMP_SECONDS := 4.0
## Segundos (depois de sumir) até a árvore rebrotar no mesmo lugar.
const REGROW_SECONDS := 90.0
## Distância (m, plano XZ) entre o fazendeiro e a árvore para começar o corte.
const CHOP_REACH := 1.5
