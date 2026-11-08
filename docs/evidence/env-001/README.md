# ENV-001 — capturas reais da ambientação

Capturas de 8 de novembro de 2026 realizadas no Godot 4.7.2, renderizador Mobile, viewport 1280×720. A primeira precede as mudanças; as demais usam os 45 PNGs instalados e `CozyEnvironment` com seed 1701. O modo `debug` acrescenta marcadores verdes (permitido) e vermelhos (proibido) apenas à captura de QA; ele não aparece no jogo.

| Captura | Conteúdo |
| --- | --- |
| [01-before.png](01-before.png) | Cena original, chão verde uniforme. |
| [02-after.png](02-after.png) | Cena principal com grama repetida e detalhes. |
| [03-grass-detail.png](03-grass-detail.png) | Grama, flores, pedras, tufos e arbustos na câmera próxima. |
| [04-field-preserved.png](04-field-preserved.png) | Plantas maduras nos sulcos, sem decorações no cultivo. |
| [05-overview.png](05-overview.png) | Vista geral com árvores, arbustos, props, balcão e área de plantio. |
| [06-placement-mask.png](06-placement-mask.png) | Amostragem das zonas permitidas/proibidas para decoração. |

Resultado automatizado: `ENVIRONMENT_SMOKE_OK assets=45 placements=163`, `ENV_EXPANSION size=128 placements=656 setup_ms=85 valid=true`, além de `FARM_SMOKE_OK`, `SALES_SMOKE_OK`, `HARVEST_SMOKE_OK`, `CUSTOMER_SMOKE_OK` e `HUD_SMOKE_OK`. Consulte [ENVIRONMENT_QA.md](../../ENVIRONMENT_QA.md) para os critérios, comandos e limitações.
