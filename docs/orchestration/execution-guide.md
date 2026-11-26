# Execution guide

From the repository root:

    C:\Users\Celso\OneDrive\Documentos\ChatGPT\GAME TERRABELA FARM

    python -m orchestration.runtime.cli --root . create FV-001 "Estruturar inventario e sete caixas" --accept "limite logico sete" --accept "descarga sem duplicacao"
    python -m orchestration.runtime.cli --root . dispatch FV-001 architecture
    python -m unittest discover -s orchestration/tests

The first command persists the demand. The second creates a structured handoff for AGENT-02. A human forwards that package to the appropriate ChatGPT or Claude session and records the result in docs/evidence.

## Godot no Windows

Godot 4.7.2 está instalada em:

    C:\Users\Celso\OneDrive\Documentos\PROJECTS\Godot_v4.7.2-stable_win64

Executável configurado para validações:

    C:\Users\Celso\OneDrive\Documentos\PROJECTS\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe

O caminho é uma configuração de ambiente de desenvolvimento; confirme a existência do executável antes de executar validações headless.

## v2.0.0 — novos domínios

Criar tarefas FV distintas para entregas (TBF-MVP são grupos do roadmap). Exemplos após criação: dispatch FV-009 backend, dispatch FV-010 database, dispatch FV-011 liveops, dispatch FV-012 security. Operador consulta arquivo canônico e registra revisões cruzadas/gates. O despacho não executa agentes nem valida gates automaticamente. Validar com python tools/validate_agents.py e python -m unittest discover -s orchestration/tests -v.
