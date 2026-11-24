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
## ciclo do golpe do fazendeiro (CHOP_SWING_SECONDS) e avança um estágio:
## 1º entalhe, 2º corte fundo, 3º inclinação.
const CHOP_HITS := 3
## CHOP-002: ciclo de um golpe do fazendeiro (erguer, descer, voltar) e o
## instante do impacto da lâmina no tronco, dentro do ciclo.
const CHOP_SWING_SECONDS := 1.0
const CHOP_IMPACT_SECONDS := 0.55
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
