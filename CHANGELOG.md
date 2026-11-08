# Changelog

## Unreleased

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
