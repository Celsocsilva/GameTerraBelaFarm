# Catálogo de assets de ambientação — ENV-001

Fonte dos metadados: `TerraBelaFarm_Ambientacao_Cozy_v1.zip`, `docs/manifest.json`, `docs/README.md` e `docs/QA_assets.json`. Caminhos relativos à raiz do projeto Godot. Dimensões em pixels; os 45 PNGs constam como `RGBA` no QA.

**Status atual:** `aplicado` = configurado para uso em runtime por `scripts/world/cozy_environment.gd`, chamado por `FarmWorld`; `disponível` = presente no projeto, mas fora dessa integração; `reservado` = finalidade futura explícita, ainda fora da integração. Para os sprites das listas, `aplicado` indica elegibilidade para sorteio, não uma instância garantida. A seed fixa reproduz a distribuição, mas uma partida pode não sortear todas as variantes.

| Caminho | Categoria | Dimensões (px) | Tipo | Finalidade | Status atual |
|---|---|---:|---|---|---|
| `assets/decor/flowers/daisies_white.png` | Flores | 145 × 104 | Sprite RGBA | Maciço de margaridas para bordas de gramado. | aplicado |
| `assets/decor/flowers/flowers_yellow.png` | Flores | 120 × 99 | Sprite RGBA | Flores amarelas para acentos discretos fora da lavoura. | aplicado |
| `assets/decor/flowers/flowers_purple.png` | Flores | 126 × 104 | Sprite RGBA | Flores roxas para variedade nas bordas. | aplicado |
| `assets/decor/flowers/flowers_red.png` | Flores | 124 × 114 | Sprite RGBA | Flores vermelhas para pontos de cor junto a caminhos. | aplicado |
| `assets/decor/flowers/sunflowers.png` | Flores | 123 × 131 | Sprite RGBA | Girassóis para pontos focais esparsos. | aplicado |
| `assets/decor/vegetation/grass_tuft_spiky.png` | Vegetação | 143 × 121 | Sprite RGBA | Tufo de capim pontiagudo para transição entre terreno e objetos. | aplicado |
| `assets/decor/vegetation/grass_tuft_broad.png` | Vegetação | 138 × 113 | Sprite RGBA | Tufo de capim largo para preencher margens. | aplicado |
| `assets/decor/rocks/rock_cluster_small.png` | Rochas | 181 × 84 | Sprite RGBA | Pedras pequenas para margens de caminho. | aplicado |
| `assets/decor/rocks/rock_cluster_medium.png` | Rochas | 203 × 113 | Sprite RGBA | Pedras médias para agrupamentos de cenário. | aplicado |
| `assets/decor/rocks/rock_cluster_large.png` | Rochas | 219 × 152 | Sprite RGBA | Rochas grandes para pontos focais fora da circulação. | aplicado |
| `assets/decor/vegetation/bush_white_flowers.png` | Vegetação | 147 × 127 | Sprite RGBA | Arbusto florido branco para bordas não cultiváveis. | aplicado |
| `assets/decor/vegetation/bush_red_berries.png` | Vegetação | 137 × 130 | Sprite RGBA | Arbusto com frutos vermelhos para bordas. | aplicado |
| `assets/decor/vegetation/bush_purple_flowers.png` | Vegetação | 135 × 128 | Sprite RGBA | Arbusto florido roxo para bordas. | aplicado |
| `assets/decor/trees/tree_green.png` | Árvores | 156 × 159 | Sprite RGBA | Árvore verde para enquadramento e sombra visual. | aplicado |
| `assets/decor/trees/tree_orchard.png` | Árvores | 134 × 154 | Sprite RGBA | Árvore de pomar para áreas de pomar futuras. | aplicado |
| `assets/decor/trees/tree_pink_blossom.png` | Árvores | 136 × 157 | Sprite RGBA | Árvore florida para ponto focal raro. | aplicado |
| `assets/decor/trees/tree_pine.png` | Árvores | 131 × 174 | Sprite RGBA | Pinheiro para borda e variação de silhueta. | aplicado |
| `assets/decor/farm_props/fence_wood.png` | Objetos rurais | 247 × 123 | Sprite RGBA | Trecho de cerca para delimitação visual. | disponível |
| `assets/decor/farm_props/fence_gate.png` | Objetos rurais | 172 × 142 | Sprite RGBA | Portão para entradas legíveis em cercas. | disponível |
| `assets/decor/farm_props/path_dirt.png` | Objetos rurais | 116 × 122 | Sprite RGBA | Marca individual de caminho de terra. | disponível |
| `assets/decor/farm_props/path_stones_round.png` | Objetos rurais | 114 × 122 | Sprite RGBA | Marca individual de caminho com pedras redondas. | disponível |
| `assets/decor/farm_props/path_stones_large.png` | Objetos rurais | 113 × 123 | Sprite RGBA | Marca individual de caminho com pedras grandes. | disponível |
| `assets/decor/farm_props/path_wood_planks.png` | Objetos rurais | 114 × 122 | Sprite RGBA | Marca individual de caminho com tábuas. | disponível |
| `assets/decor/farm_props/path_pebbles.png` | Objetos rurais | 119 × 122 | Sprite RGBA | Marca individual de caminho com seixos. | disponível |
| `assets/decor/farm_props/sign_wood_blank.png` | Objetos rurais | 162 × 144 | Sprite RGBA | Placa vazia para identificação futura sem texto embutido. | reservado |
| `assets/decor/farm_props/sign_wood_arrow.png` | Objetos rurais | 124 × 134 | Sprite RGBA | Seta para sinalizar percurso ou destino. | disponível |
| `assets/decor/farm_props/lantern_post.png` | Objetos rurais | 126 × 161 | Sprite RGBA | Poste de lanterna para marcos ao longo de caminhos. | aplicado |
| `assets/decor/farm_props/barrel_wood.png` | Objetos rurais | 112 × 121 | Sprite RGBA | Barril para composição de área de trabalho. | aplicado |
| `assets/decor/farm_props/hay_bale.png` | Objetos rurais | 116 × 104 | Sprite RGBA | Fardo de feno para composição rural. | aplicado |
| `assets/decor/farm_props/wood_logs.png` | Objetos rurais | 112 × 102 | Sprite RGBA | Toras para composição de área de trabalho. | aplicado |
| `assets/decor/farm_props/crate_empty.png` | Objetos rurais | 99 × 100 | Sprite RGBA | Caixote decorativo vazio; distinto das caixas funcionais. | disponível |
| `assets/decor/farm_props/sack_burlap.png` | Objetos rurais | 83 × 108 | Sprite RGBA | Saco de juta para composição rural. | disponível |
| `assets/decor/farm_props/wood_wheel.png` | Objetos rurais | 107 × 115 | Sprite RGBA | Roda de madeira para composição rural. | disponível |
| `assets/decor/vegetation/grass_flower_rock_patch.png` | Vegetação | 184 × 111 | Sprite RGBA | Composição de capim, flor e pedra para variação localizada. | disponível |
| `assets/decor/flowers/flower_patch_red.png` | Flores | 131 × 103 | Sprite RGBA | Mancha floral vermelha para clareiras e bordas. | disponível |
| `assets/terrain/patches/grass_patch_plain.png` | Patches de terreno | 195 × 186 | Patch decorativo não repetível | Patch isolado de grama para transição local. | disponível |
| `assets/terrain/patches/grass_patch_daisies.png` | Patches de terreno | 195 × 187 | Patch decorativo não repetível | Patch isolado de grama com margaridas. | disponível |
| `assets/terrain/patches/grass_patch_yellow.png` | Patches de terreno | 193 × 187 | Patch decorativo não repetível | Patch isolado de grama com flores amarelas. | disponível |
| `assets/terrain/patches/grass_patch_pebbles.png` | Patches de terreno | 195 × 188 | Patch decorativo não repetível | Patch isolado de grama com seixos. | disponível |
| `assets/terrain/patches/soil_patch.png` | Patches de terreno | 184 × 183 | Patch decorativo não repetível | Patch isolado de solo decorativo fora dos sulcos. | disponível |
| `assets/terrain/patches/soil_patch_corner.png` | Patches de terreno | 182 × 182 | Patch decorativo não repetível | Canto isolado de solo decorativo fora dos sulcos. | disponível |
| `assets/terrain/grass/grass_base_seamless_512.png` | Texturas de grama | 512 × 512 | Textura repetível | Textura base repetível para área gramada. | aplicado |
| `assets/terrain/grass/grass_flowers_sparse_seamless_512.png` | Texturas de grama | 512 × 512 | Textura repetível | Textura repetível de grama com flores esparsas. | aplicado |
| `assets/terrain/grass/grass_pebbles_sparse_seamless_512.png` | Texturas de grama | 512 × 512 | Textura repetível | Textura repetível de grama com seixos esparsos. | aplicado |
| `assets/terrain/grass/grass_mixed_sparse_seamless_512.png` | Texturas de grama | 512 × 512 | Textura repetível | Textura repetível de grama com detalhes mistos esparsos. | aplicado |

## Configuração de runtime e escala

`FarmWorld` instancia `CozyEnvironment` e chama `setup()`. O shader de grama recebe `GRASS_BASE`, `GRASS_FLOWERS`, `GRASS_PEBBLES` e `GRASS_MIXED`; `grass_tiles_per_meter = 0.23` equivale, na configuração padrão, a cerca de 4,35 unidades de mundo por repetição da textura. A aplicação é por material de runtime, não por referência gravada na cena `.tscn`.

As listas `FLOWERS`, `TUFTS`, `ROCKS`, `BUSHES`, `TREES` e `PROPS` são fontes de variantes para `_place_category()`. Para cada asset **aplicado** da tabela acima, a configuração de escala e colisão corresponde à sua categoria na tabela abaixo; a largura é sorteada nessa faixa e a altura acompanha a proporção do PNG. Os assets disponíveis e reservados ainda não têm escala adotada em runtime. Densidades são instâncias alvo por 100 unidades² de mapa, sujeitas à máscara espacial e à distância mínima entre peças.

| Grupo em runtime | Largura padrão (unidades de mundo) | Densidade padrão / 100 unidades² | Colisão configurada |
|---|---:|---:|---|
| `FLOWERS` | 0,42–0,75 | 1,70 | Não |
| `TUFTS` | 0,50–0,85 | 1,50 | Não |
| `ROCKS` | 0,60–1,25 | 0,30 | Apenas se largura > 0,95 |
| `BUSHES` | 0,95–1,45 | 0,25 | Não |
| `TREES` | 2,40–3,10 | 0,10 | Sim |
| `PROPS` | 0,75–1,30 | 0,15 | Sim |

`_place_category()` escolhe variantes com `placement_seed = 1701` por padrão. Mesmo quando a categoria gera instâncias, uma variante específica pode ficar ausente da partida. O número alvo também pode não ser atingido por rejeições de posição. Não interprete `aplicado` como confirmação de que cada PNG foi visto em execução.

## Uso e limites

- Os quatro arquivos `assets/terrain/grass/*seamless_512.png` são os tiles repetíveis do pacote. Os seis `assets/terrain/patches/*.png` têm bordas próprias e permanecem disponíveis para uso individual, sem UV repeat.
- `sign_wood_blank.png` fica **reservado** para identificação futura que ainda não foi definida na cena. Os demais itens fora das listas e do shader ficam **disponíveis**; nenhuma outra destinação exclusiva foi confirmada.
- O solo funcional continua em `assets/textures/soil/plowed_soil_three_furrows.png`. `soil_patch.png` e `soil_patch_corner.png` não representam células cultiváveis.
- As dimensões e o alpha do pacote foram verificados no QA do ZIP e de novo na importação Godot. As capturas desktop e os testes automatizados estão em [ENVIRONMENT_QA.md](ENVIRONMENT_QA.md); o percurso completo em dispositivo mobile ainda está pendente.
