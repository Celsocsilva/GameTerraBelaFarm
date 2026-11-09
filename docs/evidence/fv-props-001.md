# FV-PROPS-001 — Banca de feira xadrez e placas de cultura

Data: 2026-11-08 · Godot 4.7.2 · alterações locais (sem commit).

## O que mudou

1. **Assets organizados** (PNG via Git LFS, `.gitattributes` já cobre `*.png`):

   | Origem (Downloads) | Destino | Tamanho |
   |---|---|---|
   | `Balcão de Feira Campestre xadrez.png` | `assets/sales/stall_market_gingham.png` | 2048 x 534 |
   | `Imagem do ChatGPT 8 de nov. de 2026, 16_52_02-1.png` (tomate) | `assets/props/signs/sign_crop_tomato.png` | 512 x 539 |
   | `Imagem do ChatGPT 8 de nov. de 2026, 16_52_03-2.png` (milho) | `assets/props/signs/sign_crop_corn.png` | 512 x 603 |
   | `Imagem do ChatGPT 8 de nov. de 2026, 16_52_05-3.png` (abóbora) | `assets/props/signs/sign_crop_pumpkin.png` | 512 x 527 |

   Os 4 PNGs já vinham com fundo transparente (não havia fundo branco para remover).
   Tratamento: pixels com alfa < 40 zerados (respingos quase invisíveis em volta da arte),
   recorte da margem transparente (8 px de folga) e redução proporcional (banca 2048 px de
   largura, placas 512 px). Proporções preservadas. As placas ficaram em `assets/props/signs`
   e não em `assets/decor/farm_props` porque o `environment_smoke` exige exatamente 16 PNGs
   naquele pacote ENV-001.

2. **Banca de vendas** (`scripts/farming/sales_counter.gd`): o tampo e o rebordo marrons
   foram trocados por `StallVisual`, um único quadro com a arte da banca, inclinado do chão
   na frente do balcão (+Z, lado dos clientes) até o alto da borda de trás (-Z). Com a câmera
   fixa a 45°, a arte aparece exatamente na proporção do PNG (auditada no `angle_audit`).
   Não mudaram: pegada 11,05 x 2,925 m, `CounterCollision`, cercas laterais, posição, fila
   de clientes, base de dinheiro, regras de estoque e venda. As caixas sobem para
   `get_crate_base_height()`, de modo que as 2 fileiras pousam sobre a toalha desenhada e
   ficam sempre acima/na frente do quadro.

3. **Placas de cultura** (`scripts/farming/crop_sign.gd`, classe `CropSign`): placa de pé no
   canto frontal esquerdo de cada terreno de plantio (agrupamento com meta `is_crop_group`),
   na grama, sem colisão. A cultura vem do meta `crop` do terreno; `CropSign.CROPS` mapeia
   `tomato`/`corn`/`pumpkin` para arte, chave de tradução e posição da faixa em branco.
   O nome é um `Label3D` com a fonte do projeto (`UiStyle.font()`), ajustado para caber na
   faixa e atualizado ao trocar de idioma. Chaves novas em `localization/ui.csv`:
   `CROP_TOMATO` (Tomate/Tomate/Tomato), `CROP_CORN` (Milho/Maíz/Corn),
   `CROP_PUMPKIN` (Abóbora/Calabaza/Pumpkin). Para milho ou abóbora basta criar o terreno
   com `set_meta("crop", "corn")` (ou chamar `CropSign.set_crop`).

4. A decoração (`CozyEnvironment`) não nasce em cima da placa (`get_obstacle_rects`).

## Validação

| Teste | Resultado |
|---|---|
| `tools/stall_signs_smoke.gd` (novo) | STALL_SIGNS_SMOKE_OK |
| `farm_smoke`, `harvest_smoke`, `customer_smoke`, `sales_counter_smoke`, `hud_smoke` | OK |
| `environment_smoke`, `environment_expansion_smoke`, `river_smoke`, `helper_smoke` | OK |
| `angle_audit` (com banca e placa) | ANGLE_AUDIT_OK elements=14 — banca 0,0% e placa 0,0% de diferença de proporção |

Capturas reais (janela 1280x720): `tools/stall_signs_capture.gd -- <pasta> [pt_BR|es|en]`.

- Antes: `fv-props-001/antes/` (balcão marrom).
- Depois: `fv-props-001/depois/` em pt_BR, es e en — 01 banca com 18 caixas e dinheiro,
  02 banca com a fila de clientes, 03 placa no canteiro, 04 canteiro até a banca,
  05 prévia das 3 placas (milho e abóbora aparecem só nesta captura).

## Riscos e pontos em aberto

- A banca é um quadro 2D inclinado: depende da câmera fixa a 45° sem giro. Se a câmera
  girar ou mudar de inclinação, é preciso recalcular (`VIEW_PITCH_DEGREES`).
- As caixas ficam fisicamente a ~2,2 m de altura (só a tela importa na câmera ortográfica);
  o fazendeiro passa por trás da banca e fica parcialmente coberto pela toalha, como um
  vendedor atrás da mesa.
- Hoje existe um único terreno de plantio (tomate), então há uma placa. A parcela extra de
  10% é a pilha do ajudante, não um terreno de plantio, e ficou sem placa.
