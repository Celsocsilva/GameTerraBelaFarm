# FV-SHOP-003 — Loja V2: sem encolher, valores maiores, badges e marca no rodapé

Pedido do Celso (10/11/2026), aplicado só na pasta local (sem commit).

## O que mudou
- **Nada encolhe ao tocar num valor.** Causa: o clique no botão de compra chamava `_rebuild_cards()`, que recriava os cards no tamanho-base (328x410) sem refazer o layout (cards ~20% menores); além disso, botões de compra, setas e fechar tinham um tween de escala 0,96. Agora o clique não recria os cards, a troca de idioma recria já no tamanho do layout, e o botão (`StorePillButton`) só troca a arte normal/pressionada no mesmo retângulo. O ScrollContainer não realimenta mais a altura dos cards (`_carousel_size`).
- **Cards na proporção da arte** (1040x1512): título, badges e botão ficam nas caixas desenhadas na arte (`TITLE_RECT`, `BADGE_RECT`, `BUTTON_RECT` em `store_card.gd`).
- **Valor do botão maior** (~15%) e botão ocupando a vaga da arte, desenhado em 3 fatias para não deformar as pontas.
- **Títulos curtos**: VIP 7 dias, Sem anúncios, Pacote Rural, Moedas Mini/Super/Mega, 6 Ajudantes (ES/EN equivalentes).
- **Badges**: ícone + quantidade no maior tamanho que cabe na caixa creme (moedas, dinheiro, dinheiro/semana, tijolos, madeira, ajudantes, sem anúncios) e uma linha curta para o resto. Ícones novos: `assets/store/icons/icon_bricks.png`, `assets/store/icons/icon_no_ads.png`.
- **Carteira igual ao HUD**: a loja usa a mesma `HudWalletBar`, na posição e escala exatas do HUD (`FarmHUD.layout_for` → `StoreScreen.set_hud_wallet_rect`). Em retrato o título desce se cruzar a carteira; a carteira não se move.
- **Rodapé**: "Skyplan Brasil Ltda marca registrada" (`STORE_V2_FOOTER`, igual em PT/ES/EN), fixo, inclusive depois de tocar num valor.

## Verificação
- `tools/store_v2_smoke.gd`: STORE_V2_OK (novas checagens: clique não altera retângulos, sem escala, rodapé, proporção, badges, valor >= 22 pt, carteira na posição do HUD, troca de idioma mantém tamanho).
- `tools/shop003_capture.gd`: carteira da loja = carteira do HUD (944, 45.85, 320x60, escala 0,5); retângulos iguais com o valor pressionado e depois do clique (clique real de mouse).
- Falhas antigas e iguais antes desta mudança: `shop_smoke` e `hud_smoke` (procuram a loja antiga FarmShopModal) e `farm003_smoke` (espera "Farm Shop").

## Capturas (`docs/evidence/fv-shop-003/`)
00 antes · 01 HUD · 02 PT · 03 ES · 04 EN · 05 valor pressionado · 06 após o clique · 07 moedas · 08 retrato

## FV-SHOP-004 (mesmo dia)
- Título dos packs: texto marrom-escuro `#3b1503` com borda creme `#fffaf0` (antes branco com borda alaranjada, pouco contraste no creme).
- "Sem anúncios" agora é assinatura mensal: botão "R$ 29,99/mês" (ES "/mes", EN "/mo"), linha "Assinatura mensal sem anúncios", descrição ajustada. Preço de demonstração US/ES continua US$ 8.99/mo.
- Capturas refeitas em `docs/evidence/fv-shop-003/` (02, 03, 04, 05, 06).

## FV-SHOP-005 (mesmo dia)
- Problema: eram 7 bolinhas fixas (uma por card) e a seta andava 1 card; com 3 cards por tela, as posições 5 a 7 não existiam na rolagem, então setas e bolinhas ficavam dessincronizadas, e o arrasto não atualizava nada.
- Agora o carrossel anda por página: bolinhas = páginas (3 em 1280x720, 7 em retrato), a última página encosta no fim, setas apagadas nas pontas, arrasto encaixa na página mais próxima (`scroll_ended`), tocar num card visível não move o carrossel, e a janela tem a largura exata de uma página, centrada.
- Botão de sair 103,5 px (antes 90), mesmo canto (20, 16).
- Preços BR: 6 Ajudantes R$ 79,99; Moedas Super R$ 29,99 com 600 moedas (antes 650 por R$ 39,90).
- Capturas: 07-pagina-2, 07b-pagina-3, 08 retrato.
