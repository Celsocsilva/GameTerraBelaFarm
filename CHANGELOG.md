# Changelog

## Unreleased

- CROP-CORN-001: cultivo do milho na área de milho. Quatro estágios em `assets/crops/corn/stages/` (broto, jovem com cinco folhas, com uma espiga, maduro com duas espigas), grade de plantio própria (2 tiras x 3 sulcos x 6 fileiras), colheita com espigas voando para a mochila (4 por pé, provisório), caixa de milho (`assets/harvest/crate_corn_full.png`), pilha na parcela de estoque, plataforma do ajudante liberada (ajudante próprio que colhe, empilha e replanta) e venda no balcão na vaga reservada ao milho (esquerda; caixa a 4, provisório). A madeira passou para a vaga da direita, e os fardos usam as artes de toras editadas por Celso em `assets/items/logs/`. Dados das culturas em `scripts/farming/crop_catalog.gd`; aviso "Mochila ocupada" (PT/ES/EN) ao entrar num canteiro com outro produto na mochila. A abóbora segue "Em breve". Teste `tools/corn_smoke.gd`, capturas `tools/corn_capture.gd`, evidências em `docs/evidence/corn-001/`.

- FV-WOOD-002: floresta densa de eucaliptos no canto sudoeste, ao sul do rio e além da cerca do balcão (60 árvores no total); pontes e rampas com as artes novas de frente (mesmos nomes em `assets/bridges/`, pontos de tabuleiro, arco, corrimão e acessos refeitos nas cenas); corte em 3 golpes do machado animado (quadros do GIF) com os estágios entalhe, corte fundo, inclinada, caída e toco com toras, e só então as toras vão para a mochila. Teste `tools/wood_smoke.gd` e `tools/river_smoke.gd`, evidências em `docs/evidence/wood-001/`.

- FV-WOOD-001: plantações de eucalipto (23 árvores, sem colisão) nas bordas de trás e oeste dos canteiros de tomate, milho e abóbora e na margem leste do rio. A arte segue a estação local (data do aparelho + hemisfério do idioma, configurável por `terrabela/seasons/*`): primavera, verão, outono e inverno com neve. Parado perto, o fazendeiro corta a árvore, que vira o toco cortado; 4 toras voam para a mochila (fardos de 4/6/8 toras no lugar das caixas), o toco some e a árvore rebrota. As toras vão para uma pilha própria no balcão e os clientes compram fardos (6 por fardo de 8, provisório). Mochila com um produto por vez. Teste `tools/wood_smoke.gd`, evidências em `docs/evidence/wood-001/`.

- UI-MESSAGE-001: segundo modal, grande, para mensagens (moldura de madeira com laço vermelho em `assets/ui/components/panel_message_large.png`): título na faixa vermelha, mensagem no creme com margem e botão OK, textos por chave (PT/ES/EN) que encolhem para caber. `FarmHUD.show_message()`. O modal de recompensa segue só para recompensas. Evidências em `docs/evidence/ui-message-001/`.

- ENV-FENCE-001: cercas com a arte de madeira do projeto (`FenceRun`, `assets/fences/coop_fence_02.png`) no lugar das caixas coloridas: cerca provisória do norte e cercas laterais do balcão, postes nas pontas e vãos iguais, mesmas colisões.

- CROP-AREAS-001: áreas de milho (leste) e abóbora (norte), afastadas entre si e do tomate, cada uma com canteiro, placa da cultura, parcela de estoque de 10% com pilha própria e plataforma do ajudante no chão (bloqueada "Em breve" até existir arte de crescimento dessas culturas). Teste `tools/crop_areas_smoke.gd`, evidências em `docs/evidence/crop-areas-001/`.

- FV-STACK-001: banca de vendas de volta à arte plana (`assets/sales/stall_market_gingham.png`; a versão funda fica guardada sem uso), caixas sobre a toalha; no balcão e na parcela de 10% as caixas formam UMA única pilha por cultura (`CrateStack`: tomate no meio, milho à esquerda, abóbora à direita), altura visual limitada (4 no balcão, 5 na parcela) e contador "xN" acima da pilha quando passa do limite. Contagem lógica, colisão, fila, dinheiro e distância do terreno inalterados. Teste `tools/crate_stack_smoke.gd`, evidências em `docs/evidence/fv-stack-001/`.

- FV-HELPER-001: ajudante contratado por uma plataforma no chão (paga dinheiro a dinheiro, 100 para contratar e 5 graus), colhe, empilha caixas na parcela de 10% e replanta; o fazendeiro recolhe a pilha pisando na parcela. Teste `tools/helper_smoke.gd`, evidências em `docs/evidence/fv-helper-001/`.

- FV-FARM-008: terreno de tomate afastado do balcão (3x a faixa de grama), cerca e construção recuadas e parcela extra de 10% da área do terreno. Teste em `tools/farm_smoke.gd`, evidências em `docs/evidence/fv-farm-008/`.

- UI-REWARD-001: modal de recompensa com fontes menores, áreas internas com margem e ajuste automático (quebra por palavra, tamanho mínimo, reticências só como último recurso); textos por chave em `localization/ui.csv` com EN/ES (Reward!/¡Recompensa!, Quest complete!/¡Misión completada!, Collect/Recoger). Teste em `tools/hud_smoke.gd`, capturas `tools/reward_popup_capture.gd`, evidências em `docs/evidence/ui-reward-001/`.

- FV-PROPS-002: banca de vendas com a arte de toalha xadrez mais funda (`assets/sales/stall_market_gingham_deep.png`), mesma largura, colisão, fila, caixas e distância do terreno. Evidências em `docs/evidence/fv-props-002/`.

- FV-PROPS-001: balcão de vendas com a arte da banca de feira de toalha xadrez (mesma pegada, colisão, caixas, fila e dinheiro) e placa de madeira com o nome da cultura (Label3D traduzido PT/ES/EN) em cada terreno de plantio; artes de tomate, milho e abóbora prontas. Teste `tools/stall_signs_smoke.gd`, captura `tools/stall_signs_capture.gd`, evidências em `docs/evidence/fv-props-001/`.

- ENV-002: rio modular no lado oeste do mapa com 14 PNGs do pacote Rio e Pontes v1, água animada por shader leve, peças de junção sem frestas, faixas de margem com flores, ponte de madeira (`BridgeWood.tscn`, com acessos) e ponte de pedra (`BridgeStone.tscn`) atravessáveis por superfície em arco e corrimãos invisíveis. A água bloqueia a passagem fora das pontes; decoração e plantio respeitam o rio. Adicionados `river_tile_bake.gd`, `river_smoke.gd`, `river_capture.gd`, documentação e evidências em `docs/evidence/river_bridges/`.

- ENV-001: integrados 45 PNGs de ambientação; grama repetível com variações locais e decoração determinística fora dos canteiros, rotas e zona de venda. Adicionados catálogo, guia, validação e capturas comparativas.

- Criada a fundação Godot mobile, documentação arquitetural e estrutura de agentes.
- Adicionada validação inicial de arquivos e workflows condicionados para Android/iOS.
- FV-HARVEST-001: colheita automática de tomates maduros com sucção até a mochila e pilha dinâmica de até 7 caixas (8 tomates cada), com reservas transacionais, cancelamento e save.
- FV-SALES-001: bancada de descarga renomeada para Balcão de vendas, com largura dobrada (8,5 m), colisão e cercas laterais; clientes compram 1-3 caixas sorteadas a 3 dinheiros por caixa; dinheiro empilhado numa base 3 x 5 ao lado do balcão e saldo no HUD.
- UI-004: HUD da fazenda com os PNGs individuais do pacote UI v4 (contadores de dinheiro, tomates e caixas, painel de nível, missão, popup de recompensa, aviso de venda, botão da loja e faixa de mensagens); todos os números são Labels da engine, o dinheiro usa o maço oficial e os estados vêm da Wallet, da mochila e das vendas.
- UI v5: PNGs da v5 no lugar da v4 (margem transparente, CTAs 30% mais largos, popup de recompensa isolado), componente CtaButton com estados, cena UIAssetQA, auditoria tools/ui_asset_audit.gd e textos que se ajustam até 9.999.999.
- Progressão 6x mais lenta (ProgressionConfig.DIFFICULTY_MULTIPLIER): XP por nível e metas das missões multiplicados por 6.
- Novo ícone da loja (icon_store_shop.png) com o nome em Label traduzido (Loja / Tienda / Shop); ícone antigo com tomates removido.
