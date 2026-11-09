# UI-REWARD-001 — Modal de recompensa: fontes menores, ajuste automático e EN/ES

Data: 2026-11-08 · Godot 4.7.2 · alterações locais (sem commit).

## Problema
Na captura do Celso, os textos do modal ("Recompensa!", "Missão concluída!", valor e "Coletar")
estavam grandes demais: o título encostava nas pontas da faixa vermelha, a mensagem invadia a placa
do valor e a borda do cartão, e textos longos eram apenas encolhidos até ficarem ilegíveis.

## O que mudou
- `scripts/ui/hud/reward_popup.gd`
  - Retângulos internos com margem: título só na parte reta da faixa (132,224 313x54), mensagem no
    creme entre as pontas da faixa e a placa (126,300 325x56), valor dentro da placa (238,364 206x62).
  - Fontes máximo/mínimo: título 42/18 (antes 54), mensagem 30/14 (antes 38), valor 44/18 (antes 56),
    botão 0,36 da altura com margem lateral 0,3 (antes 0,46, sem margem).
  - Textos por chave de `localization/ui.csv`; ao trocar o idioma com o modal aberto tudo é refeito.
  - `show_reward()` aceita chave ou texto pronto (padrão: as chaves abaixo).
- `scripts/ui/hud/ui_style.gd`: `fit_font_box()` reduz a fonte até o texto caber inteiro na largura
  e na altura (descontando contorno e espaçamento entre linhas), quebra por palavra em até N linhas,
  nunca corta palavra; último recurso: recorte com reticências dentro da área.
- `scripts/ui/hud/cta_button.gd`: `caption_ratio` e `caption_inset` (padrões iguais aos antigos).
- `farm_hud.gd` e `ui_preview.gd` usam as chaves.

| Chave | pt_BR | es | en |
|---|---|---|---|
| REWARD_TITLE | Recompensa! | ¡Recompensa! | Reward! |
| REWARD_MISSION_COMPLETE | Missão concluída! | ¡Misión completada! | Quest complete! |
| REWARD_COLLECT | Coletar | Recoger | Collect |

## Validação
- `tools/hud_smoke.gd` (headless) ganhou a etapa 8b: confere as 3 traduções, textos normais e
  longos dentro das áreas, nenhuma área sobreposta, e a troca de idioma com o modal aberto.
  Saída: `REWARD_LOCALE pt_BR/es/en ... HUD_SMOKE_OK`.
- Suíte completa verde: farm, harvest, customer, sales_counter, hud, environment,
  environment_expansion, river, helper, stall_signs, angle_audit.
- Capturas reais (`tools/reward_popup_capture.gd`, sem --headless, 720x1280 e 1280x720):
  `docs/evidence/ui-reward-001/` com `antes-*` e `depois-*`, tela inteira e `-zoom` do cartão, nos 3
  idiomas, casos `normal` e `longo` (textos de estresse bem maiores que os reais, valor 9.999.999).
  Quadro-resumo: `00-comparativo-antes-depois.png` (linhas: normal antes, normal depois, longo antes,
  longo depois; colunas pt_BR, es, en).

```
godot --path . --resolution 720x1280 -s tools/reward_popup_capture.gd -- <pasta absoluta> depois
godot --headless --path . -s tools/hud_smoke.gd
```

## Observações
- No caso de estresse, títulos muito longos ("¡Recompensa especial de la cosecha!") terminam em
  reticências no tamanho mínimo 18, porque a faixa vermelha só comporta uma linha. As traduções reais
  cabem com folga (36 px nos 3 idiomas).
