# Rio modular e pontes — ENV-002

Arquitetura do cenário, ambientação, colisões, navegação e procedimento de expansão do rio do TerraBela Farm. Projeto Godot 4.7.2 (renderizador Mobile), cena principal `res://scenes/world/farm_world.tscn`. Repositório: [github.com/Celsocsilva/GameTerraBelaFarm](https://github.com/Celsocsilva/GameTerraBelaFarm). Website oficial: [https://terrabelafarm.com](https://terrabelafarm.com).

## 1. Inspeção do projeto (antes da implementação)

| Item | Estado encontrado (base: ENV-001, commit `090b4d5`) |
|---|---|
| Engine e cena | Godot 4.7.2, `config/features` 4.7 + Mobile, cena principal `scenes/world/farm_world.tscn`. |
| Terreno | `Ground` (StaticBody3D) 64 × 64 m centrado na origem, topo em Y = 0; grama `cozy_ground.gdshader`; paredes `TerrainBoundary` nas quatro bordas (±32 m). |
| Câmera | `IsometricCamera` ortográfica, tamanho 12, 45° de inclinação (altura = distância = 14), sem giro; segue o fazendeiro com zona morta e limite de foco ±26 m. |
| Personagem | `Farmer` (CharacterBody3D, cápsula r 0,45 × 1,8 m), teclado (`ui_*`) e joystick virtual; sem navegação automática (NavigationMesh inexistente). |
| Cultivo | Três `PlantingPlot` contínuas em x ∈ [−7,0; 7,0], z ∈ [2,3; ~16]. |
| Venda e circulação | Balcão em z = 21,5 com cercas laterais até as bordas; clientes atrás (+Z); base de dinheiro ao lado; corredor central livre. |
| Obstáculos | Cerca (−5, −2), construção (5, −3), árvore (−10, 10). |
| Expansão | Norte do mapa (z < −23) reservado sem decoração sólida; oeste livre. |
| Convenção de sprites de chão | PNGs deitados (QuadMesh rodado −90° em X), comprimento em Z multiplicado por 1/sin 45° para aparecer na proporção da arte; decorações em pé são `Sprite3D` billboard com pivô na base. |
| Captura “antes” | [07a-antes.png](evidence/river_bridges/07a-antes.png), renderizada do commit base. |

## 2. Traçado escolhido

O rio entra pela borda oeste ao norte (z ≈ −21), corre para leste, faz a curva para o sul, desce num trecho reto em x ≈ −14,3 (onde ficam as duas pontes), vira para oeste em z ≈ 7 e sai pela borda oeste em z ≈ 7,5 depois da curva grande. Assim:

- não toca os canteiros de tomate (borda oeste em x = −7), a cerca, a construção nem a árvore existente;
- não toca o balcão, a fila de clientes nem o caminho fazendeiro ↔ balcão;
- forma um bolsão a oeste (≈ 15 × 28 m) acessível só pelas pontes, reservado para futuros terrenos;
- o norte continua livre para a expansão já prevista no ENV-001;
- termina nas bordas do mapa sem margem transparente (os retos das pontas são recortados na linha d'água).

Sequência de peças (`RiverSystem.tscn → course`): reto horizontal (recortado) → curva `corner_left_up` → reto vertical → reto vertical → curva `corner_right_down` → curva grande `curve_large_right` → reto horizontal (recortado). Cada tipo de curva aparece uma vez.

## 3. Hierarquia de nós

```
FarmWorld
└── RiverSystem              (scenes/world/river/RiverSystem.tscn, scripts/world/river/river_system.gd)
    ├── RiverSegments        Segment_NN_<tile> (tile do PNG com água animada) + Junction_NN (peça de junção)
    ├── RiverBanks           Bank_NN_* (faixas bank_strip_*.png sobre as margens)
    ├── WaterSurface         Surface_NN (faixa contínua de água sob os tiles)
    ├── BridgeWood           (scenes/world/river/BridgeWood.tscn, scripts/world/river/river_bridge.gd)
    │   ├── Art, FrontLayer/FrontStrip_NN, WalkSurface/Deck, Rails/Front_NN, Back_NN
    │   └── ApproachWest, ApproachEast (+ ApproachWestPosts, ApproachEastPosts)
    ├── BridgeStone          (scenes/world/river/BridgeStone.tscn)
    └── RiverCollisions      Blockers_NN (água de cada tile) + JunctionBlocker_NN
```

`FarmWorld._build_river()` instancia o rio depois dos obstáculos e antes da câmera e da decoração. `CozyEnvironment.reserved_areas` recebe o `RiverSystem`; `is_allowed_position()` consulta `blocks_decoration()` de cada área reservada.

## 4. Montagem modular

1. `tools/river_tile_bake.gd` lê cada PNG de `assets/river_tiles/` e grava `data/river/river_tile_meta.json`: aberturas de água por borda (linha d'água e trecho ocupado) e máscara de água em células de 8 px (água = azul − vermelho > 0,12). Os PNGs não são alterados.
2. Cada segmento entra pela borda oposta à saída do anterior. A escala do tile é escolhida para que a largura da água na entrada seja igual à largura de saída do anterior; a posição alinha os centros das aberturas, com sobreposição de `junction_overlap` (0,08 m). Escala sempre uniforme: nenhum tile é esticado; a única correção em Z é a mesma 1/sin 45° do restante do chão.
3. Recortes permitidos: só em peças retas, ao longo do fluxo (`length_px`, `trim_entry`), porque a arte reta é contínua nessa direção. Usado para começar e terminar exatamente na borda do mapa.
4. Peça complementar de junção: as pontas dos PNGs têm margens arredondadas e uma borda de água mais clara. Em cada encontro, uma fatia do meio de um tile reto (vertical ou horizontal, conforme o eixo) é desenhada por cima com o shader `river_water_junction.gdshader`, que esmaece as duas pontas. Resultado em [06c-juncao-retos.png](evidence/river_bridges/06c-juncao-retos.png).
5. `WaterSurface`: faixa de água contínua, um pouco mais estreita que o canal, sob os tiles; só aparece se houver fresta.

## 5. Água animada

`assets/river_tiles/river_water.gdshader` (tiles) e `river_water_junction.gdshader` compartilham `river_water_common.gdshaderinc`:

- anima só os pixels de água do PNG (mesma regra da máscara); margens, pedras e flores ficam intactas;
- deslocamento da pintura de até 1,4 texel, variação lenta de brilho (±4,5 %) e reflexos em traços curtos que se movem devagar;
- padrão calculado em coordenadas de MUNDO: contínuo entre tiles e sem troca brusca de direção nas curvas;
- `unshaded`, 2 leituras de textura e algumas funções seno por fragmento, sem luz, sombra ou textura de ruído; independente do personagem;
- `RiverSystem.water_animation = false` congela a animação (aparelhos fracos ou capturas estáticas).

## 6. Pontes

`river_bridge.gd` (classe `RiverBridge`) é usado pelas duas cenas. O PNG é só aparência:

| Camada | Função |
|---|---|
| `Art` | PNG deitado no chão (mesma convenção dos tiles), acima da água. |
| `WalkSurface/Deck` | `ConcavePolygonShape3D` em arco entre `deck_front_px` e `deck_back_px`, altura 0 nas cabeceiras e `arch_height` no meio (madeira 0,30 m, pedra 0,40 m). Cada ponto é deslocado +h em Z: nesta câmera, (x, h, z) aparece no mesmo lugar que (x, 0, z − h), então os pés ficam sobre as tábuas e as pedras da arte. |
| `Rails` | Caixas invisíveis (1,2 m) ao longo das duas bordas do tabuleiro; impedem cair na água e não bloqueiam as cabeceiras. |
| `FrontLayer` | Faixas perpendiculares à câmera com o corrimão, os postes e as lanternas da frente (`front_mask_px`), na profundidade da borda frontal. Quem está sobre a ponte fica atrás do corrimão; quem está na margem da frente fica na frente da ponte. |
| `ApproachWest/East` (só madeira) | `bridge_approach_left/right.png` no chão, caminháveis, com colisão cilíndrica nos postes de corda. A escala segue o tamanho dos postes da ponte. |

A ponte de pedra não usa os acessos de corda: as cabeceiras de pedra apoiam direto nas margens, mantendo a identidade diferente da ponte de madeira.

## 7. Colisões e navegação

- **Bloqueio da água:** `Blockers_NN` agrupa as células de água da máscara em caixas (altura 1,6 m). As caixas cobrem só água; o fazendeiro (raio 0,45 m) anda pela margem até a beira. `JunctionBlocker_NN` fecha a borda clara de cada junção.
- **Vão das pontes:** células cujo centro está dentro do polígono de caminhada de uma ponte (ampliado em 0,05 m) não geram bloqueio; os corrimãos selam as laterais desse vão.
- **Física do personagem:** inalterada (`move_speed`, gravidade, `floor_max_angle` e `floor_snap_length` padrão). Rampa máxima ≈ 8°; o teste mede degrau máximo de 0,019 m por quadro físico.
- **Navegação automática:** o projeto não tem NavigationMesh nem agentes; clientes andam em rotas próprias atrás do balcão, longe do rio. Se uma navegação for criada, inclua `RiverCollisions` como obstáculo e `WalkSurface` das pontes como área navegável.
- **Plantio e decoração:** `RiverSystem.is_planting_allowed()` e `blocks_decoration()` recusam água, margens ilustradas, pontes, acessos e uma folga de 2,2 m nas cabeceiras. A plantação atual fica fora dessa área (teste E).

## 8. Como adicionar segmentos de rio

1. Novo PNG de rio: coloque em `assets/river_tiles/` e rode `godot --headless --path . -s tools/river_tile_bake.gd`. Confira no log as bordas detectadas como abertura.
2. Em `RiverSystem.tscn`, acrescente `{"tile": "<nome sem .png>"}` ao fim de `course`. A entrada é sempre a borda oposta à saída anterior; use uma peça cujas aberturas combinem (ex.: depois de saída `left`, a peça precisa de abertura `right`).
3. Em código (fases futuras), `river_system.add_segment({"tile": ...})` cria só o novo tile, a junção e as colisões dele; o que já existe não é recriado (teste G).
4. Para estender além da borda atual, primeiro amplie o terreno e as paredes do mapa; depois troque o último reto recortado por peças inteiras.
5. Use `river_pond_endcap_top` para encerrar um braço (só abertura superior).
6. Rode `tools/river_smoke.gd` e capture com `tools/river_capture.gd` (vistas `overview`, `focus --focus=x,z --size=s`, `--debug`).

## 9. Como adicionar uma ponte

1. Crie uma cena herdando o padrão de `BridgeWood.tscn`: nó `Node3D` com `river_bridge.gd`, `art`, `art_width_m`.
2. Marque em px do PNG: `deck_front_px` e `deck_back_px` (mesma quantidade de pontos, de oeste para leste), `front_mask_px` (polígono do que fica na frente), `arch_height`. Opcional: acessos, posts e caminhos dos acessos.
3. Instancie como filho de `RiverSystem` (antes de `RiverCollisions` na árvore) sobre um trecho reto; as duas cabeceiras precisam cair em terra firme. O vão no bloqueio da água é aberto automaticamente.
4. Valide com `tools/river_capture.gd -- --view=focus ... --debug` (polígono verde, bloqueios vermelhos) e com um caminho de travessia no smoke test.

## 10. Limitações conhecidas

- O pacote desenha as pontes em perspectiva diagonal; elas cruzam o rio vertical num ângulo (~30°). As travessias seguem o tabuleiro desenhado.
- As faixas `bank_strip_*` só servem para margens horizontais (não há versão vertical sem rotacionar a arte, o que quebraria a luz e a perspectiva).
- Capturas e testes rodaram em Linux com Vulkan por software (llvmpipe); FPS em Android real ainda precisa de homologação.
