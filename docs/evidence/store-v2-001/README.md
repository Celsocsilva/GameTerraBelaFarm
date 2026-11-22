# STORE-V2-001 — carrossel e ofertas IAP de demonstração

## Implementado

- StoreScreen landscape com carrossel, setas, indicadores e retorno ao jogo.
- Sete IDs estáveis: `vip_7d`, `remove_ads`, `rural_pack`, `coins_mini`, `coins_medium`, `coins_large`, `helpers_6`.
- Preço de demonstração por região independente do idioma: BRL no Brasil; USD nos EUA e no modo Espanha demo.
- Cards grandes, título branco com contorno, fonte mínima de 12 pt, preços legíveis e badges de moedas, dinheiro, madeira e ajudantes quando aplicável.
- Botões de fechar e navegação usam sprites normal/pressionado e Tween de 96% para feedback tátil.

## Segurança

O serviço de compra é indisponível no runtime. Apenas `StorePurchaseService.Mode.SIMULATED`, injetado pelo teste, concede ouro/dinheiro por meio de `StoreEntitlements`; cada `transaction_id` é aplicado uma vez. Anúncios, tijolos, madeira e ajudantes são registrados como payload de domínio pendente, sem inventar sistemas inexistentes.

`coins_large` usa temporariamente a arte de moedas médias como fallback configurável: uma arte exclusiva ainda não foi fornecida.

## Verificação executada

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/store_v2_smoke.gd
Godot_v4.7.2-stable_win64.exe --path . --resolution 1280x720 -s tools/store_v2_capture.gd -- docs/evidence/store-v2-001
```

Resultado: `STORE_V2_OK`. A captura `store-v2-pt_BR.png` demonstra a composição, botões e preços em BRL.
