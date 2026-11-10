# FV-POLISH-001 — caixas, pilha 3x3, placeholders, props, áreas e pinheiros

Capturas no jogo real (OpenGL em xvfb, 1280x720, pt_BR) com `tools/polish_capture.gd`.
Os arquivos `00-antes-*` são o estado anterior (main 78dfa44), para comparação.

- `01-visao-geral.png`: mapa inteiro. Sem o galpão vermelho, sem a árvore primitiva e sem o muro verde da borda; áreas de abóbora e milho no tamanho do tomate, nos fundos; pinheiros no norte (3 fileiras) e no leste.
- `02-fundos-norte.png`: abóbora (esquerda) e milho (direita), placas na frente dos canteiros, corredor livre até a ponte de madeira.
- `03-lado-leste.png`: bosque regular de pinheiros a leste, pasto livre ao lado do tomate, cerca no pasto sudeste.
- `04-caixas-fazendeiro-e-balcao.png`: caixas da mochila com a mesma arte e largura (1,69 m) das caixas do balcão.
- `05-pilha-ajudante-tomate.png` / `06-pilha-ajudante-milho.png`: pilha da área de coleta em grade 3 x 3 por camada (14 e 7 caixas).
- `07-props-e-fazendeiro.png`: barril e lampião em escala natural ao lado do fazendeiro.
- `08-areas-de-cultivo.png`: as três áreas de cultivo com o mesmo tamanho.

Teste headless: `godot --headless --path . -s tools/polish_smoke.gd` → `POLISH_SMOKE_OK`
(caixa da mochila = balcão para tomate e milho, clientes com a arte da caixa, pilhas de ajudante em grade,
sem primitivas sem textura no mapa, props dentro da escala nova, áreas com 100% da área do tomate e 81 covas,
pinheiros no leste e no norte sem entrar em canteiros, estoques, plataformas, balcão ou saída das pontes).

## O que foi removido (elementos sem textura)

| Elemento | Onde estava | O que virou |
|---|---|---|
| `Building` (caixa vermelha 3,2 x 2,2 x 3 m) | (5, -13), norte do tomate | removido (era o galpão provisório) |
| `Tree` (cilindro marrom + esfera verde) | (-10, 10), perto da ponte de pedra | removido (pinheiros com arte no lugar) |
| `TerrainBoundary` x4 (muro verde-escuro de 2 m) | bordas do mapa | só colisão, sem malha |
| Caixas `BoxMesh` dos clientes (marrom + tampa colorida) | nas mãos dos clientes | sprites com a arte de `ItemArt` (tomate, milho, fardo de toras) |

Mantidos de propósito (dependem de arte que ainda não existe): a cápsula azul do fazendeiro, as cápsulas
dos clientes/ajudantes e a base de madeira (caixa amarela clara) da pilha de dinheiro 3 x 5 ao lado do balcão.
