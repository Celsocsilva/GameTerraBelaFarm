# Diretrizes de ambientação — ENV-001

## Base do projeto e escopo

O cenário atual em `scripts/world/farm_world.gd` usa chão de 64 × 64 unidades de mundo, câmera ortográfica elevada, três tiras contíguas de cultivo e obstáculos construídos em 3D. `scripts/farming/planting_grid.gd` configura 3 colunas e 9 fileiras por tira (81 células na configuração lida); há cerca, prédio, árvore, balcão de vendas, fila de clientes e pilha de dinheiro. Estes valores descrevem a implementação inspecionada, não uma promessa de layout permanente. O pacote contém 4 texturas repetíveis, 6 patches não repetíveis e 35 sprites. A implementação está em `scripts/world/cozy_environment.gd` e `assets/terrain/grass/cozy_ground.gdshader`; as regras abaixo orientam ajustes e expansão.

Na cena inicial, `placement_seed = 1701` produz 163 instâncias: 70 flores, 61 tufos, 12 rochas, 10 arbustos, 4 árvores e 6 objetos rurais. As seis densidades são exportadas por 100 m²; a grama usa 0,23 repetição por unidade do mundo (tile de cerca de 4,35 unidades). O shader usa a grama base por padrão e mistura as variantes em manchas suaves. A máscara pública `is_allowed_position()` reserva o cultivo com margem de 1,5 unidade, o corredor central, os obstáculos, o balcão e a área de venda. Revise esses valores quando o mapa mudar.

## Densidade e hierarquia

1. Mantenha a área central de cultivo e as interações visivelmente livres. Em cada trecho de 10 × 10 unidades de gramado **fora** da lavoura, comece com até 6 detalhes baixos (flores, tufos, patches ou pedras pequenas), até 2 arbustos ou pedras médias e no máximo 1 árvore, rocha grande ou objeto alto. Conte cada composição pronta como uma peça, para evitar acúmulo invisível.
2. Use a grama base como padrão dominante. Nas superfícies gramadas, limite as variantes com flores, seixos ou mistura a cerca de 20–30% da área visível total, em manchas irregulares. Não forme um mosaico alternado de tiles.
3. Deixe pelo menos metade do gramado livre de sprites sobrepostos. A cada 3–5 ocorrências de um mesmo sprite, alterne variante ou abra um intervalo vazio. Flores altas e lanternas são marcos raros; não as repita junto a cada célula.

## Escala e contato com o chão

1. Meça largura e altura **em unidades do mundo**, nunca a partir dos pixels do PNG. Comece com flores e tufos a 0,35–0,8 unidade de largura visível, arbustos e pedras pequenas a 0,8–1,5, pedras grandes e props a 1–2,2, árvores a 2–3 de largura de copa. Ajuste essas faixas após comparar com o fazendeiro, prédio, árvore 3D existente e câmera ortográfica de tamanho 12.
2. Mantenha o ponto de apoio do sprite na base visível da arte, com o pé rente ao solo. Use o limite opaco informado pelo QA para compensar margens transparentes; não centre o tronco ou a cerca pela caixa inteira do PNG.
3. Para grama repetível, preserve proporção uniforme de UV nos eixos X e Z. Comece testando um tile 512 × 512 a cada 4–6 unidades do mundo e reduza o tamanho se os detalhes parecerem desproporcionais. Os patches têm escala individual e bordas visíveis; jamais os use como material repetível.

## Distribuição e caminhos

1. Defina zonas explícitas: cultivo, circulação do fazendeiro, vendas e fila, entorno de obstáculos, bordas decorativas e área de expansão. Gere posições com seed fixa e coordenadas por zona; um reload deve reproduzir a mesma decoração.
2. Priorize pequenos grupos de 2–4 flores ou tufos em gramado lateral e grandes intervalos vazios. Coloque rochas e arbustos em bordas, nunca como ruído uniforme. Use no máximo uma árvore ornamental como ponto focal por trecho de aproximadamente 10 unidades de borda.
3. Preserve um corredor livre de pelo menos **1,5 unidade de largura** nas rotas do fazendeiro e de pelo menos **2 unidades** perto do balcão, da fila e da pilha de dinheiro. A cápsula do fazendeiro tem raio 0,45; essas larguras são metas de folga, a conferir com a rota real. Não use peças de caminho para sugerir passagem onde uma colisão 3D impede o movimento.
4. Deixe placas, portões e lanternas fora do eixo central do corredor. Oriente setas para o destino real e mantenha a entrada de portão alinhada com a passagem física. Patches de caminho são marcas individuais, não tiles seamless; evite emendas óbvias e sobreposição de margens.

## Colisão, profundidade e legibilidade

1. Texturas de grama, patches planos, flores e tufos são decoração sem colisão nova. Para árvores, rochas grandes, cercas e props que bloqueiem fisicamente, use uma colisão simples limitada ao tronco ou à base opaca, nunca ao retângulo transparente do PNG.
2. Antes de atribuir colisão, verifique continuidade da rota para semear, colher, descarregar no balcão e coletar dinheiro. Não crie bloqueio invisível e não duplique as colisões da cerca, prédio, árvore e limites existentes.
3. Ordene sprites pelo ponto de apoio no chão ou use escrita de profundidade compatível com os materiais atuais. Confira sobreposição do fazendeiro, culturas, caixas, balcão e clientes ao passar à frente e atrás. A arte alta pode cruzar a silhueta do jogador, mas a base deve permanecer ancorada.
4. Mantenha o centro das células e seus indicadores visíveis. Se uma copa ocultar uma interação na câmera fixa ou durante o seguimento da câmera, afaste, reduza ou remova o adereço. Confira mobile e desktop, inclusive transparência, mipmaps e serrilhado.

## Cultivo e expansão

1. Preserve o material e a forma dos sulcos atuais. A textura nova de grama cobre apenas gramado fora das tiras; `soil_patch.png` e `soil_patch_corner.png` são decoração de borda, não substitutos do solo funcional nem novas células plantáveis.
2. Exclua da distribuição toda a união das três `PlantingPlot` e uma faixa externa inicial de **0,75 unidade**. Recalcule a máscara a partir dos módulos e da `PlantingGrid`, pois a largura, o comprimento e a quantidade de fileiras podem mudar. Não coloque pedras, flores, cercas ou patches sobre plantas, alvos de semeadura ou alcance de colheita.
3. Reserve visualmente pelo menos uma faixa contínua de **4 unidades de largura** de gramado acessível para expansão futura antes de preencher bordas com árvores ou cercas. Trate esta reserva como diretriz de layout, não como lote de cultivo já implementado; trigo, milho e animais ainda são planos de produto.
4. Ao acrescentar novas áreas, estenda as zonas e máscaras, gere decoração por coordenada de setor e seed estável, e mantenha corredores entre lavoura, armazenamento e vendas. Revise limites físicos do terreno, limites da câmera e rotas de clientes antes de decorar a borda ampliada.

## Verificação de integração

Na cena Godot, inspecione em escala de mobile e desktop: repetição das quatro texturas de grama; bordas dos seis patches; escala e alpha dos sprites; visibilidade de todas as células; passagem nas rotas de plantio, colheita, balcão e dinheiro; oclusão na frente e atrás do fazendeiro; e espaço livre para expansão. O QA do ZIP verifica dimensões e alpha, mas não valida essas condições em execução.
