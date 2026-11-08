# ENV-001 — QA da ambientação

Execução em 2026-11-08, Godot `4.7.2.stable.official.ed1daf0bf`, cena `res://scenes/world/farm_world.tscn`. Os smoke tests foram headless; as capturas reais usaram o renderizador Mobile em GPU NVIDIA, 1280×720. Todos os testes listados terminaram com código de saída 0.

## Comandos executados

Na raiz do projeto, com `Godot_v4.7.2-stable_win64_console.exe`:

```text
--headless --path . -s tools/environment_smoke.gd
--headless --path . -s tools/farm_smoke.gd
--headless --path . -s tools/sales_counter_smoke.gd
--headless --path . -s tools/harvest_smoke.gd
--headless --path . -s tools/customer_smoke.gd
--headless --path . -s tools/hud_smoke.gd
--headless --path . -s tools/environment_expansion_smoke.gd
```

## Casos e resultados

| Caso | Verificação executada | Resultado observado |
|---|---|---|
| ENV-QA-01 — pacote | `Image.load_png_from_buffer` leu todos os PNGs nas sete pastas; formato RGBA8, dimensões não vazias, canto transparente em sprites/patches, canto opaco e 512 × 512 nos quatro tiles. Comparação pixel a pixel das bordas opostas dos tiles. | **Passou:** 45 PNGs; nenhuma borda divergente. |
| ENV-QA-02 — chão | `GrassSurface` usa `ShaderMaterial`; quatro parâmetros de textura 512 × 512; shader contém repetição e UV por coordenadas de mundo; `tiles_per_meter` corresponde à configuração. As três tiras preservam o material e PNG de solo existentes. | **Passou:** `tiles_per_meter=0.23`; shader `res://assets/terrain/grass/cozy_ground.gdshader`. |
| ENV-QA-03 — zonas e sprites | Para cada entrada de `placements`, testou asset, raio positivo, apoio em Y=0,02, `is_allowed_position`, limites do mapa e não interseção com os volumes reais dos três `PlantingPlot`. Testou também distância mínima entre decorações, contagem dos nós, `Sprite3D` com corte alfa, base ancorada e teste de profundidade ativo. | **Passou:** 163 posições: 70 flores, 61 tufos, 12 rochas, 10 arbustos, 4 árvores e 6 objetos rurais. Nenhuma invasão detectada pelos critérios medidos. |
| ENV-QA-04 — seed | Criou segunda instância de `CozyEnvironment` com a mesma seed, densidades, escala e argumentos de `setup`; comparou categoria, asset, posição e raio de cada entrada, na mesma ordem. | **Passou:** seed 1701, 163 entradas idênticas. |
| ENV-QA-05 — regressão básica | Verificou fazendeiro, câmera ortográfica, joystick, HUD, balcão/fila, 81 células, plantio de uma célula e depósito de 8 tomates. | **Passou:** 81 células, 1 plantada, 8 tomates depositados. |
| ENV-QA-06 — testes existentes | Executou `farm_smoke.gd` e `sales_counter_smoke.gd` sem modificá-los. | **Passou:** `FARM_SMOKE_OK` e `SALES_SMOKE_OK`; o teste de vendas registrou 5 bloqueios físicos esperados junto ao balcão. |
| ENV-QA-07 — regressão ampliada | Executou colheita, fila de clientes e HUD. | **Passou:** `HARVEST_SMOKE_OK`, `CUSTOMER_SMOKE_OK` e `HUD_SMOKE_OK`. |
| ENV-QA-08 — expansão simulada | `environment_expansion_smoke.gd` instanciou a decoração para 128×128, sem alterar a cena principal, e revalidou a máscara. | **Passou:** 656 instâncias, 85 ms de `setup` nesta máquina, todas em posições permitidas. Este valor não mede FPS móvel. |
| ENV-QA-09 — integridade | SHA-256 de cada PNG instalado foi comparado aos bytes do ZIP. | **Passou:** 45/45 arquivos idênticos. |

Saída final do teste novo: `ENVIRONMENT_SMOKE_OK assets=45 placements=163`.

## Capturas visuais reais

As seis capturas em [evidence/env-001](evidence/env-001/README.md) mostram antes/depois, grama com flores e pedras, plantação preservada, vista geral com árvores e objetos rurais e a máscara espacial. Na câmera desktop de 1280×720, o material de grama se repete sem linha de emenda observável nas áreas examinadas; os sprites visíveis apresentam transparência e base apoiada no chão. As capturas são quadros renderizados pelo Godot, sem montagem de mockup.

## Limites e pendências

- As capturas conferem o estado inicial e as vistas escolhidas no desktop. Ainda falta percorrer toda a fazenda com o joystick e observar oclusão em movimento, cintilação e possíveis padrões repetitivos em todas as distâncias.
- A opção CLI `--resolution 960x540` manteve a gravação em 1280×720 por causa do viewport configurado; portanto não contamos essa tentativa como validação de layout mobile. Android/iOS reais não foram testados.
- A verificação de zonas combina a máscara pública com os volumes dos canteiros e limites do mapa. Não simula uma rota completa do joystick até cada célula, a bancada e a base de dinheiro, nem valida a fila de clientes durante toda a partida.
- O teste de regressão novo cobre plantio e depósito básicos; colheita, clientes e HUD passaram em smoke tests próprios. Venda completa e desempenho em FPS durante a expansão ainda exigem teste de partida em dispositivo.
- `farm_smoke.gd` terminou com código 0 e `FARM_SMOKE_OK`, mas o Godot emitiu aviso de 3 instâncias `ObjectDB` e 1 recurso ainda em uso ao sair. O aviso não veio do teste novo; convém investigar separadamente.
