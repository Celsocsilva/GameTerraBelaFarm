# TerraBela Farm — Ambientação Cozy v1

Pacote para enriquecer visualmente a fazenda com grama, flores, pedras, arbustos, árvores e pequenos elementos de cenário.

## Diretórios

- `assets/terrain/grass/`: **4 texturas 512 × 512**, repetíveis nos eixos horizontal e vertical. Use nos materiais de terreno (`PlaneMesh`, `StandardMaterial3D`, UV/tiling) ou como `TextureRect` com repeat.
- `assets/terrain/patches/`: tiles/patches ilustrados de grama, pedras e solo, com bordas próprias. **Não são seamless**; aplicar de forma individual.
- `assets/decor/flowers/`: flores e maciços florais, sprites PNG RGBA independentes.
- `assets/decor/vegetation/`: tufos de grama e arbustos, PNG RGBA.
- `assets/decor/rocks/`: pedras e rochas, PNG RGBA.
- `assets/decor/trees/`: árvores, PNG RGBA.
- `assets/decor/farm_props/`: cercas, placas, caminhos, barril, feno, madeiras e acessórios, PNG RGBA.
- `previews/`: catálogo de sprites e teste visual da textura repetida 2×2.
- `docs/manifest.json`: lista dos assets e metadados.

## Diretrizes de integração no Godot 4

- **Terreno:** preserve o material dos sulcos de cultivo. A grama nova substitui ou sobrepõe apenas áreas gramadas ao redor do terreno, não o solo cultivado.
- **Escala:** dimensione os sprites em função das unidades do mundo, da câmera e do espaço de jogo; não use o tamanho dos PNGs como escala física. Prefira sprites decorativos discretos.
- **Colocação:** pedras e flores devem ficar no solo, fora das células de cultivo, zonas de venda, áreas de navegação e colisões; não criar bloqueios invisíveis.
- **Alpha:** mantenha transparência habilitada nos `Sprite3D` ou `TextureRect`; não renderize o fundo dos previews como asset.
- **Qualidade:** teste os sprites nas escalas de câmera existentes (mobile e desktop). Habilite filtragem com mipmaps apropriada conforme distância, para minimizar serrilhado.
- **Repetição:** configure UV/texture repeat na textura de grama e ajuste tiles_per_meter conforme a proporção real do mapa. Evite aumentar demais detalhes e flores.
- **Distribuição:** posicionar de forma determinística com seed, a partir de regiões de decoração, evitando repetição artificial de padrão; não distribuir aleatoriamente por cima de plantios.

## QA executado neste pacote

- Verificação de existência, dimensões e canal alpha dos PNGs.
- A grama seamless foi construída de maneira periódica e inspecionada em uma prévia de repetição 2×2. `periodic_edge_max_channel_diff` no manifesto informa a diferença máxima das cores entre bordas opostas.
- Os sprites foram isolados e exportados individualmente, com canal alpha.

**Limitação:** não foi executada a cena Godot nesta entrega. O encaixe final, tamanho e oclusão precisam ser validados na execução do jogo.
