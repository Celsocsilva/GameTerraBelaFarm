# FV-HELPER-001 — Ajudante contratável e pilha na parcela de 10%

Data: 2026-11-08. Alteração feita só na pasta local (sem commit/push).

## Interpretação adotada

1. **Controle no chão, não no HUD** (correção do Celso). Uma plataforma
   quadrada de cantos arredondados (`HelperPad`) fica no chão logo antes da
   parcela de 10%, no lado do balcão (+Z), alinhada a ela. Estilo UI v5: creme,
   borda marrom, faixa amarela com o título, `Grau n/5`, 5 marcadores de
   graduação e quanto falta pagar. É quadrada **na tela** (lado Z × 1/sin 45°),
   como a parcela.
2. **Pagamento dinheiro a dinheiro.** Com o fazendeiro em cima (após 0,35 s),
   sai 1 dinheiro da carteira a cada 0,03 s: um maço voa das mãos dele até a
   plataforma, o saldo do HUD desce 1 por vez e o preenchimento verde sobe.
   Ao completar **100** o ajudante é contratado.
3. **Se sair da plataforma, pausa e guarda o que já pagou** (não devolve, não
   perde, não cobra a mais). Ao voltar, continua de onde parou. Sem saldo, o
   HUD avisa quanto falta.
4. **Graduação** (5 graus). Depois de contratado, a mesma plataforma cobra a
   próxima graduação. Preços provisórios: 100 (contratar), 200, 400, 800, 1600.
   Cada grau deixa o ajudante mais rápido (2,2 → 3,8 m/s), colhendo mais rápido
   (1,0 → 0,5 s por pé) e carregando mais caixas por viagem (1,1,2,2,3).
5. **"Plantar/empilhar os tomates maduros"**: o ajudante colhe os pés maduros
   (mesma trava da colheita do fazendeiro: os dois nunca colhem o mesmo pé),
   leva as caixas e **empilha na parcela de 10%** (até 27 caixas, 3×3×3). Quando
   a safra inteira é colhida e o canteiro reabre, ele também **replanta** as
   covas vazias (o punhado sai das mãos dele).
6. **A pilha não quebra o fluxo atual**: pisando na parcela, o fazendeiro
   recolhe as caixas da pilha para a mochila, uma a uma; depois segue para o
   balcão como sempre. Efeito colateral: esses tomates contam na missão
   "Colher tomates" (como uma colheita).

## Arquivos

- `scripts/helpers/helper_config.gd` — preços e atributos por grau.
- `scripts/helpers/helper_hiring.gd` — grau, `paid`, `pay()` 1 a 1 pela Wallet (origem `helper`).
- `scripts/helpers/helper_pad.gd` — plataforma no chão (shader de quadrado arredondado, Label3D, voo dos maços).
- `scripts/helpers/farm_helper.gd` — ajudante 3D (cópia do fazendeiro em amarelo) e sua máquina de estados.
- `scripts/farming/tomato_pile.gd` — pilha de caixas na parcela e recolha pelo fazendeiro.
- `scripts/world/farm_world.gd` — monta tudo, `get_helper_pad_rect()`, `plant_cell_from()`, avisos no HUD.
- `localization/ui.csv` — chaves `HELPER_*` em pt_BR/es/en.
- `tools/helper_smoke.gd`, `tools/helper_capture.gd`.

## Validação

Headless, código de saída 0: `helper_smoke` (pagamento 1 a 1, pausa ao sair,
contrata em exatamente 100, graus até 5 = 3100 no total, traduções, posição da
plataforma, invariante pilha + carga + mochila + pés = produção, trava com o
fazendeiro, recolha → balcão, caminhada sem teletransporte, replantio), farm,
harvest, customer, sales_counter, hud, environment, environment_expansion,
river e angle_audit.

Capturas (1280x720, `--path . -s tools/helper_capture.gd -- <pasta> [locale]`):
01 plataforma antes da parcela, 02 pagando dinheiro a dinheiro, 03 saiu e
pausou, 04 contratado, 05 ajudante colhendo e empilhando, 06 fazendeiro
recolhe da pilha, 07 visão de jogo.

## Em aberto (confirmar com o Celso)

- Preço das melhorias (200/400/800/1600) e se deve haver 5 graus.
- Pausar e guardar o pago ao sair (alternativa: devolver o que foi pago).
- O ajudante ainda é a cópia do fazendeiro em amarelo (sem arte própria).
