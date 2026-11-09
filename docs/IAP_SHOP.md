# FV-SHOP-001 — Loja IAP do TerraBela Farm

## Escopo implementado

A nova modal é aberta pelo botão **Loja** já existente no HUD. Traz cinco categorias: **Aceleradores**, **Recursos**, **Assistentes**, **Máquinas** e **Pacotes**, com 15 ofertas conceituais. É possível selecionar categorias, consultar um item e fechar a loja pelo botão X ou ação `ui_cancel`.

O visual reutiliza ícones existentes do projeto, com fundo creme, moldura marrom e abas em tons quentes. Os textos são Labels/Button do Godot e estão em `localization/ui.csv` (pt_BR, es e en). Nenhum PNG possui preços ou rótulos fixos novos.

**Não há checkout ou venda real nesta entrega.** Todos os itens têm `available=false`, IDs de produto de plataforma vazios, preço indefinido e botão de compra desabilitado. O catálogo é uma preparação para IAP, não um sistema de pagamentos concluído. Nenhum produto concede recursos, altera a Wallet ou chama uma API de cobrança.

## Arquivos

- `scenes/ui/shop/FarmShopModal.tscn` — modal reutilizável em tela cheia
- `scripts/ui/shop/farm_shop_modal.gd` — layout, localização, seleção e navegação
- `scripts/ui/shop/shop_catalog.gd` — dados conceituais e ícones
- `scripts/ui/hud/farm_hud.gd` — abertura pelo botão existente
- `localization/ui.csv` — chaves e tradução
- `tools/shop_smoke.gd` — teste de contrato/segurança e navegação
- `tools/hud_smoke.gd` — integração da abertura pelo HUD
- `tools/hud_capture.gd` — capturas do catálogo (modo `store`)

## Contrato de produto

Cada oferta contém:

- `id`: ID interno estável
- `category`: categoria visual
- `title_key` e `description_key`: textos localizáveis
- `icon`: referência a imagem permitida e existente
- `store_product_id_android` e `store_product_id_ios`: vazios
- `available`: false

Os itens atuais são hipóteses de oferta. **Não existe preço, quantidade de itens, duração de boost, conteúdo de pacote, entitlement ou SKU aprovado.** Definir esses campos e as regras correspondentes antes de habilitar compras.

O ajudante já contratado no gameplay usa a `Wallet` e a plataforma `HelperPad`. A futura loja IAP não deve duplicar contratações ou conflitar com esse estado. Mapear cada entitlement adquirido para efeitos de domínio testados e persistidos, preservando os meios gratuitos de progressão conforme as decisões de produto.

## Etapa posterior — integração de IAP

Para habilitar compras, implementar um serviço de plataforma desacoplado da UI que:

1. Carregue produtos e preços reais das lojas Android/iOS, no idioma/moeda definidos pela plataforma.
2. Valide disponibilidade e elegibilidade antes de oferecer o botão Comprar.
3. Inicie o fluxo nativo de compra autorizado pelo usuário.
4. Verifique transações e recibos no backend seguro e conceda benefícios **apenas após validação**, de forma idempotente.
5. Suporte acknowledgement/consumption quando necessário, cancelamento, pendências, reembolso/revogação e restauração de compras elegíveis.
6. Salve e sincronize entitlements de modo seguro e auditável, especialmente benefícios permanentes.
7. Isole compras com moeda real de pagamentos com a `Wallet`, impedindo crédito artificial.
8. Respeite as políticas vigentes de Google Play e Apple App Store, sem links ou checkout externo não autorizado.

Não armazenar credenciais de plataforma, certificados, tokens ou recibos sensíveis no repositório.

## Verificação

Executar na versão real do Godot configurada no projeto:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/shop_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/hud_smoke.gd
```

Para imagens reais do jogo:

```powershell
Godot_v4.7.2-stable_win64.exe --path . --resolution 1280x720 -s tools/hud_capture.gd -- "C:/temp/terrabela-shop" store
Godot_v4.7.2-stable_win64.exe --path . --resolution 720x1280 -s tools/hud_capture.gd -- "C:/temp/terrabela-shop" store-retrato
```

Validar abertura/fechamento, scroll, seleção, PT/ES/EN, disposição em paisagem/retrato, ausência de compra, ausência de crédito e regressões de plantio/colheita/venda. A importação do CSV no Godot deve ser refeita para atualizar os recursos `.translation`.

**Status QA da PR:** código e scripts de teste entregues; Godot não está disponível neste ambiente de integração. Portanto, nenhum smoke test ou captura real foi executado aqui.
