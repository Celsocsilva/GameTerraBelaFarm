# FARMER-GAME-001 — fazendeiro 3D jogável no FarmWorld

Data: 2026-11-22 · Godot 4.7.2 · local, sem commit

## O que mudou

- `scenes/player/farmer.tscn`: a cápsula azul saiu; entrou `Visual` = `assets/animations/Farmer/farmer_character.tscn`
  em escala **2,5** (2,5 m, proporcional às caixas de 1,69 m do jogo). Colisão (cápsula 0,45 × 1,8) não mudou.
- `scripts/player/farmer_controller.gd`: passa a velocidade real no chão para o `FarmerAnimator` a cada quadro físico.
- `assets/animations/Farmer/farmer_animation_controller.gd` (`FarmerAnimator`): AnimationTree montado em código com
  3 camadas — locomoção (parado/andar/correr; com mochila; agachado; caixa na frente) com velocidade de reprodução
  calculada pela velocidade de chão medida de cada ciclo (`assets/animations/tools/measure_stride.py`); gesto de tronco
  (só tronco e braços) quando ele está andando; gesto de corpo inteiro quando está parado.
- `scripts/world/farm_world.gd` (`_connect_farmer_animation`): eventos → animação
  | Evento do jogo | Animação |
  |---|---|
  | joystick (0–4 m/s) | `Idle_Loop` → `Walk_Loop` → `Jog_Fwd_Loop` |
  | mochila com caixas (`HarvestInventory.get_total() > 0`) | `Backpack_Idle/Walk/Jog_Loop` (mãos nas alças) |
  | cova semeada pelo fazendeiro (`PlantingGrid.cell_planted`) | `Interact` acelerado (gesto de lançar) |
  | colheita começa (`HarvestController.harvest_started`, todas as culturas) | `PickUp_Table` |
  | entrega no balcão, milho no cocho, material nas plataformas, eucalipto derrubado | `Interact` |
- Novas animações no `farmer.glb`: `Backpack_Idle_Loop`, `Backpack_Walk_Loop`, `Backpack_Jog_Loop` (25 no total).
- Clientes e ajudantes continuam com o corpo-cápsula colorido, agora em `scenes/npc/npc_capsule_body.tscn`
  (antes copiavam a cápsula do fazendeiro). `tools/customer_smoke.gd` compara com esse modelo.

## Validação

- `-s tools/farmer_game_smoke.gd` (novo, headless): **17/17 PASS** — cápsula removida, modelo rigado, AnimationTree ativo,
  altura 2,5 m, sombra, clientes com cápsula, parado/correndo/soltar o joystick, velocidade da corrida casada com o chão
  (scale 0,99 a 4 m/s), olha para onde anda, mochila liga/desliga a pose, semear/colher/entregar disparam o gesto.
- `-s tools/farmer_rig_smoke.gd`: OK.
- Bateria completa `tools/*_smoke.gd`: 22 de 25 OK. As 3 que falham (`farm003`, `hud`, `shop`) procuram o modal antigo da loja (`FarmShopModal`), que a Loja V2 local substituiu; já falhavam antes desta mudança e não envolvem o fazendeiro.
- Capturas reais (`--resolution 1280x720 -s tools/farmer_game_capture.gd -- <pasta>`), o fazendeiro andando com
  `Input.action_press` como no teclado/joystick, cada contexto em 3 vistas (câmera do jogo, câmera do jogo com zoom sem
  HUD, 3/4 baixa): `farmer-game-001/`
  1. `01-correndo-no-caminho` (e `01b-parado-idle`)
  2. `02-semeando-no-canteiro` (10 covas semeadas no trajeto)
  3. `03-colhendo-tomates`, `03b-colhendo-parado` (12 tomates na mochila)
  4. `04-mochila-indo-ao-balcao`, `04b-entregando-no-balcao` (entrega confirmada, mochila zerada)
  5. `05-curral-com-milho` (milho voando para o cocho)
  Resumos: `resumo-6-contextos-3-4.png`, `resumo-6-contextos-camera-jogo-zoom.png`. Estado do animador em cada captura:
  `capture_log.txt`.

## Pendências / observações

- Chapéu: a copa tem um calombo herdado do TRELLIS. Tentei alisar por script, mas a aba inclinada deformava junto;
  não apliquei. Precisa de ajuste manual no Blender (Sculpt/edição da copa) e reexportar com o pipeline.
- As caixas da mochila (arte do jogo, billboard) ficam grandes em relação ao corpo, como já eram com a cápsula.
- Ajudantes e clientes ainda são cápsulas; podem virar variações do modelo 3D (mesmo rig e animações) numa próxima etapa.
- Sem APK/aparelho Android nesta etapa.
