# Arquitetura do TerraBela Farm

## Princípios

- Mobile-first: toque, landscape, safe areas e performance são requisitos de base.
- Domínios independentes: estado, regras, apresentação e plataforma não se misturam.
- Dados configuráveis: culturas, economia e progressão usam Resources ou arquivos versionados.
- Regras de farming, inventory, commerce e economy devem ser testáveis sem renderização.

## Domínios

Core coordena ciclo de vida e eventos. World controla mapa e câmera. Player controla movimento. Farming implementa culturas. Inventory separa produtos, lotes e caixas. Commerce trata bancada, pedidos e clientes. Economy trata pagamentos e saldo. Progression trata desbloqueios. UI trata HUD e touchscreen. Persistence trata saves. Platform encapsula Android/iOS.

Fluxo do vertical slice:

Input -> Player -> Farming/Commerce -> Inventory -> Economy -> Persistence

Apresentação observa mudanças por sinais e não decide regras econômicas. O limite visual de sete caixas nunca substitui a validação do inventário lógico.

## Ambientação ENV-001

`FarmWorld` cria `Ground`, as três `PlantingPlot`, os obstáculos e o balcão antes de instanciar `CozyEnvironment`. Esse componente aplica `assets/terrain/grass/cozy_ground.gdshader` somente à malha visual do chão. O shader amostra a grama base com coordenadas globais X/Z, repetição periódica de 0,23 tile por unidade e mistura suave das três variantes em regiões selecionadas. Os sulcos têm malha e material próprios e mantêm prioridade visual sobre a grama.

`CozyEnvironment` mantém a hierarquia `Flowers`, `GrassTufts`, `Rocks`, `Bushes`, `Trees` e `FarmDecorations`. Cada instância usa `Sprite3D` com billboard, pivô inferior, descarte de alfa e mipmaps. Apenas árvores, props e rochas maiores recebem colisores simples. A distribuição usa `placement_seed` e densidades exportadas por 100 m²; `placements` e `is_allowed_position()` permitem auditoria da seed e da máscara. A máscara reserva a união dos canteiros com folga, o corredor central, o balcão, a fila, os obstáculos atuais e parte da expansão. Mudanças no mapa exigem revisão dessa máscara.

As decorações são criadas uma vez na inicialização. A engine faz a seleção por câmera dos sprites fora da vista; não há geração por quadro. Para mapas muito maiores, a distribuição deve ser dividida em setores com seed estável e orçamento de instâncias por setor. Consulte [catálogo](../ASSET_CATALOG.md), [guia](../ENVIRONMENT_GUIDELINES.md) e [QA](../ENVIRONMENT_QA.md).

## Rio e pontes ENV-002

`FarmWorld._build_river()` instancia `scenes/world/river/RiverSystem.tscn` depois dos obstáculos e antes da decoração. `RiverSystem` monta o curso a partir de `course` (lista de tiles) e de `data/river/river_tile_meta.json`, cria a água animada, as peças de junção, a superfície contínua e as colisões por segmento. `BridgeWood` e `BridgeStone` (`RiverBridge`) separam aparência (PNG no chão + camada frontal) de física (superfície em arco + corrimãos invisíveis). `CozyEnvironment.reserved_areas` inclui o rio. A física do fazendeiro não mudou. Ver [RIVER_AND_BRIDGES.md](../RIVER_AND_BRIDGES.md) e [RIVER_BRIDGES_QA.md](../RIVER_BRIDGES_QA.md).
