# IAP-SHOP-002 — banners de ofertas premium

## Entrega

- `assets/ui/shop/offers/iap_vip_week.png`: criativo visual do Pacote VIP.
- `assets/ui/shop/offers/iap_no_ads_month.png`: criativo visual do pacote Sem anúncios mensal.
- As duas artes são exibidas como `AdCreative` sem Labels sobrepostos; texto, preço e benefícios são apresentados pela UI localizada.
- A loja abre na aba **Pacotes**, com o VIP selecionado, mas nenhuma compra é executada no cliente.

## Ofertas exibidas

| ID | Preço de referência | Benefícios exibidos |
| --- | --- | --- |
| `iap_vip_week` | R$ 55,00 | 7 dias sem anúncios, +700 moedas, +2.000 dinheiros e 150 moedas a cada 8 horas. |
| `iap_no_ads_month` | R$ 44,99 | 30 dias sem anúncios, +300 moedas e +1.000 dinheiros por semana. |

Os IDs de produto de Android/iOS continuam vazios e `available=false`. Assim, os benefícios acima não alteram carteira, ouro, recursos ou anúncios enquanto não houver integração nativa, validação de recibo no backend e concessão idempotente.

## Evidência executada em 10/11/2026

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/shop_smoke.gd
Godot_v4.7.2-stable_win64.exe --path . --resolution 1280x720 -s tools/hud_capture.gd -- docs/evidence/iap-shop-002 store
```

Resultado: `SHOP_SMOKE_OK`, incluindo navegação PT/ES/EN, os dois banners renderizados, preços completos com vírgula e botão de compra permanentemente desabilitado. A captura `loja-paisagem-modal.png` mostra a vitrine e o preço do VIP; `loja-paisagem-bundles.png` registra a aba de Pacotes.
