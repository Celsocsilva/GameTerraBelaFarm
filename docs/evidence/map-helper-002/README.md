# MAP-HELPER-002 — expansão, layout, contratação e estabilidade do milho

Validação executada em 9 de novembro de 2026 com Godot 4.7.2.

## Resultado implementado

- mapa original de 64 × 64 m preservado à esquerda e no rodapé;
- expansão de 6,4 m (+10%) à direita e ao norte, resultando em `Rect2(-32, -38.4, 70.4, 70.4)`;
- chão, colisão, paredes, câmera e ambientação usam os mesmos limites assimétricos;
- milho e abóbora foram escalonados em profundidade, sem sobrepor rio, pontes, balcão ou outras áreas;
- tomate: 100 dinheiros + 20 fardos de madeira;
- milho: 100 dinheiros + 20 caixas de tomate;
- abóbora: 100 dinheiros + 20 caixas de milho, requisito já configurado; a plataforma continua bloqueada porque ainda não existe ciclo/arte plantável de abóbora nesta versão;
- materiais são consumidos do estoque depositado na banca; sem material, o pagamento para em 99/100 e não libera o ajudante;
- caixas de milho passaram a usar posição local ao fazendeiro e uma textura estável para estados parcial/cheio, eliminando a disputa de `global_transform` que causava flick durante deslocamento.

## Evidências visuais

- `01-mapa-expandido-areas-organicas.png` — mapa inteiro e áreas escalonadas;
- `02-custo-ajudante-tomate-madeira.png` — plataforma mostrando 100 + 20 fardos;
- `03-custo-ajudante-milho-tomate.png` — plataforma mostrando 100 + 20 caixas de tomate;
- `04-caixas-milho-estaveis.png` — três caixas de milho acompanhando o fazendeiro.

## Testes executados

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/farm_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/crop_areas_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/corn_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/helper_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/crate_stack_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/environment_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/harvest_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/sales_counter_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/customer_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/wood_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/river_smoke.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/polish_smoke.gd
python tools/validate_agents.py
python -m unittest discover -s orchestration/tests -v
```

Resultados observados:

- `MAP_EXPANSION_OK rect=[P: (-32.0, -38.4), S: (70.4, 70.4)]`;
- `CROP_AREAS_SMOKE_OK areas=2`;
- `CORN_CRATE_STABILITY_OK max_error=0.000000`;
- `CORN_SMOKE_OK`;
- `HELPER_SMOKE_OK`;
- `CRATE_STACK_SMOKE_OK`;
- `ENVIRONMENT_SMOKE_OK assets=45 placements=196`.
- `HARVEST_SMOKE_OK`, `SALES_SMOKE_OK`, `CUSTOMER_SMOKE_OK`;
- `WOOD_SMOKE_OK trees=110`, `RIVER_SMOKE_OK segments=7 bridges=2`;
- 9 contratos operacionais válidos e 6 testes Python aprovados.
