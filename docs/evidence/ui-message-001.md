# UI-MESSAGE-001 — Modal grande para mensagens (moldura com laço vermelho)

Data: 2026-11-09 · Godot 4.7.2 · alterações locais (sem commit).

## O que é
Segundo modal do jogo, para avisos e explicações maiores. O modal de recompensa
(`RewardPopup`) continua só para recompensas.

Princípio do Celso: quanto menos texto, mais fácil de usar e entender. Use título de
1 a 2 palavras e mensagem de 1 a 2 frases curtas. O texto longo das capturas existe só
para provar que a fonte encolhe e nada sai da moldura.

## Arquivos
- `assets/ui/components/panel_message_large.png`: a moldura enviada pelo Celso (1199 x 1312, sem alteração).
- `scripts/ui/hud/message_popup.gd` + `scenes/ui/hud/components/MessagePopup.tscn` (classe `MessagePopup`).
- `FarmHUD.tscn`: nó `Root/MessagePopup`; `FarmHUD.show_message(título, mensagem, botão = "MESSAGE_OK")`.
- `localization/ui.csv`: `MESSAGE_OK`, `HELP_HELPER_TITLE`, `HELP_HELPER_TEXT` (exemplo).

## Áreas internas (pixels do PNG)
| Texto | Retângulo | Fonte máx/mín |
|---|---|---|
| Título (faixa vermelha, abaixo do laço) | 240,196 720x92 | 78/34, 1 linha, contorno vermelho |
| Mensagem (creme, ~55 px de margem) | 170,450 860x430 | 64/30, até 5 linhas, quebra por palavra |
| Botão OK (CtaButton verde) | 380,905 440x126 | 0,40 da altura |

O ajuste usa `UiStyle.fit_font_box` (o mesmo do modal de recompensa). Trocar o idioma com o
modal aberto refaz os textos. O cartão escala para caber em retrato e paisagem.

## Uso
```gdscript
hud.show_message("HELP_HELPER_TITLE", "HELP_HELPER_TEXT")   # chaves de ui.csv
hud.message_popup.closed.connect(func(): ...)               # uma vez por abertura
```

## Validação
- `tools/crop_areas_smoke.gd` (parte do modal): abre nos 3 idiomas com o texto real e com o texto
  longo, confere tradução, título dentro da faixa, mensagem dentro do creme, botão OK e `closed`
  emitido uma vez por abertura (fechar duas vezes não repete).
- Capturas no jogo real: `tools/message_popup_capture.gd`, em `docs/evidence/ui-message-001/`
  (retrato 720x1280 e paisagem 1280x720). Fontes medidas: título 70 px, mensagem curta 64 px,
  mensagem longa 42–45 px.
- Renderizadas com OpenGL (llvmpipe) num Linux sem GPU; a fonte do sistema pode variar no Windows.

## Pendências
- Onde o jogo vai abrir este modal (ex.: primeira vez na plataforma do ajudante). Hoje ele está
  pronto e testado, mas nenhum fluxo do jogo o abre sozinho.
