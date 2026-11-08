# ENV-002 — Relatório de QA do rio e das pontes

Execução em 2026-11-08, Godot `4.7.2.stable.official.ed1daf0bf`, Linux x86_64. Testes headless pelos scripts abaixo; capturas e vídeos renderizados pelo Godot com o renderizador **Forward Mobile** em Vulkan por software (Mesa llvmpipe), 1280×720, via Movie Maker (`--write-movie`, 30 fps). Base: branch `feature/env-001-cozy` (commit `090b4d5`). Todos os comandos terminaram com código 0.

## Comandos

```text
godot --headless --path . -s tools/river_tile_bake.gd
godot --headless --path . -s tools/river_smoke.gd
godot --headless --path . -s tools/environment_smoke.gd
godot --headless --path . -s tools/farm_smoke.gd
godot --headless --path . -s tools/sales_counter_smoke.gd
godot --headless --path . -s tools/harvest_smoke.gd
godot --headless --path . -s tools/customer_smoke.gd
godot --headless --path . -s tools/hud_smoke.gd
godot --headless --path . -s tools/environment_expansion_smoke.gd
godot --path . --write-movie out.png --fixed-fps 30 -s tools/river_capture.gd -- --view=<vista> [--debug]
```

## Testes de aceite

| Teste | Verificação executada | Resultado |
|---|---|---|
| **A — Continuidade** | Para as 6 junções: entrada voltada para a saída anterior, distância entre linhas d'água = sobreposição prevista, mesma largura, peça de junção presente, água dos dois lados. 175 pontos da linha central testados contra a máscara de água. Início e fim na borda do mapa. Inspeção visual de junções, curvas e margens. | **Passou.** `max_gap_m=0.0`, `max_width_delta_m=0.0`, `dry=0/175`. Capturas 06a–06c sem frestas, margens cortadas ou faixas retangulares. |
| **B — Ponte de madeira** | Física real (teclado `ui_*` com intensidade analógica) pelo acesso oeste, tabuleiro e acesso leste, ida e volta. Mede travamento (> 1,5 s parado), altura máxima/mínima, maior degrau por quadro e quadros sobre a água abaixo do tabuleiro. | **Passou.** 3,92 s / 3,63 s; sobe até 0,301 m (arco 0,30); mínimo −0,007 m; degrau máx. 0,013 m; 0 quadros na água; sem travamento. |
| **C — Ponte de pedra** | Mesmo procedimento, cabeceiras sem acesso. | **Passou.** 2,52 s / 2,27 s; topo 0,402 m (arco 0,40); mínimo 0,001 m; degrau máx. 0,019 m; 0 quadros na água; sem travamento. |
| **D — Bloqueio pela água** | 10 tentativas de 4 s andando direto contra o rio fora das pontes: trecho vertical nos dois sentidos, entre as pontes, braço norte nos dois sentidos, curva sul nos dois sentidos e exatamente sobre 3 junções. | **Passou.** 10/10 bloqueadas, nenhum quadro dentro da água. |
| **E — Compatibilidade** | Câmera ortográfica, joystick, HUD, balcão e fila presentes; 81 células; nenhuma célula de plantio no rio ou nas margens; 63/63 pontos do rio recusam plantio; nenhuma das 163 decorações na área do rio/pontes. Regressões: ambientação, fazenda (plantio, semeadura, tamanhos), balcão/venda, colheita, clientes, HUD e expansão da decoração. | **Passou.** `RIVER_E_INTEGRATION ... cells_in_river=0 decorations_on_river=0` e os 7 smoke tests existentes com `_OK`. |
| **F — Perspectiva** | Capturas na câmera do jogo e em zoom: água, margens, pontes e fazendeiro. A superfície das pontes é deslocada +h em Z para os pés coincidirem com o tabuleiro desenhado; a camada frontal fica na profundidade da borda frontal. | **Passou (visual).** 04/05: fazendeiro sobre as tábuas e as pedras, atrás do corrimão frontal; 04b/05b e vídeos 10/11: entrada, arco e saída sem flutuar ou afundar. |
| **G — Expansão** | `RiverSystem` independente com 2 peças; `add_segment` acrescenta 3 (reto, curva, reto) e outro sistema fecha com `river_pond_endcap_top`. | **Passou.** Nós existentes preservados (3/3), +3 corpos de colisão de água e +3 de junção, folga 0,0 m, 3,9 ms para 3 peças. |
| **H — Desempenho** | Contagem de nós do rio, tempo de montagem do mundo e erros nos logs das capturas renderizadas. | **Passou.** 47 malhas, 242 formas de colisão estáticas (172 caixas de água); `FarmWorld` montado em ~151 ms (headless). Nenhum `ERROR`/`WARNING` nos 13 logs de captura. CPU 1,2–1,7 ms/quadro; GPU 20–24 ms/quadro em **llvmpipe** (CPU, não representa um celular). |

Saída final: `RIVER_SMOKE_OK segments=7 bridges=2`. Integridade: 14/14 PNGs idênticos ao ZIP (SHA-256).

## Evidências

Ver [evidence/river_bridges/README.md](evidence/river_bridges/README.md): 15 capturas reais e 3 vídeos curtos.

## Pendências e riscos

- **Aparelho real:** FPS, aquecimento e serrilhado da água/alpha em Android não foram medidos; o renderizador Mobile rodou por software.
- `farm_smoke.gd` mantém o aviso já registrado no ENV-001 (3 instâncias `ObjectDB` e 1 recurso em uso ao sair); não vem do rio.
- As distribuições de decoração mudaram de lugar no lado oeste porque o rio passou a reservar área; a contagem (163) e a seed são as mesmas.
- O personagem atual é a cápsula provisória; com o sprite/modelo final, revisar o polígono `front_mask_px` das pontes.
- A ponte diagonal do pacote cruza o rio vertical em ângulo; é uma escolha visual documentada, não um defeito de alinhamento.
