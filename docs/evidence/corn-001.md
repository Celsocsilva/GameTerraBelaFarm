# CROP-CORN-001 — cultivo do milho

Capturas no jogo real (renderizador OpenGL em xvfb, 1280x720, pt_BR) com `tools/corn_capture.gd`:

- `01-milharal-quatro-estagios.png`: uma faixa de fileiras por estágio (broto atrás, maduro na frente).
- `02-milharal-maduro-pilha-e-plataforma.png`: milharal maduro, ajudante do milho contratado (grau 1), pilha de caixas de milho na parcela de estoque.
- `03-fazendeiro-com-caixas-de-milho.png`: mochila com 5 caixas de milho.
- `04-balcao-milho-tomate-madeira.png`: balcão com milho (esquerda), tomate (meio) e fardos de toras (direita, arte editada).

Teste headless: `godot --headless --path . -s tools/corn_smoke.gd` → `CORN_SMOKE_OK`
(catálogo, 36 covas dentro do canteiro, plantio andando, 4 estágios crescentes, colheita sem criar/perder milho,
depósito e venda no balcão com o preço do milho, um produto por vez na mochila, ajudante empilha 144 e replanta).

Valores provisórios (em `scripts/farming/crop_catalog.gd`): 4 espigas por pé, caixa de milho a 4.
