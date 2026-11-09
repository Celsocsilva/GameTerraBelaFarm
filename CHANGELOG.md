# Changelog

## Unreleased

- FV-SHOP-001: botão Loja agora abre modal navegável com 5 categorias e 15 ofertas conceituais; UI traduzível PT/ES/EN; sem preços, SKUs ou checkout fictícios. Compra desabilitada até integração segura de IAP e validação de recebimentos. Testes em `tools/shop_smoke.gd` e documentação em `docs/IAP_SHOP.md`.

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
