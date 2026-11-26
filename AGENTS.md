# Instruções dos agentes — TerraBela Farm

## Objetivo

Construir um jogo mobile nativo na Godot 4.7.2, com Android como primeira plataforma e compatibilidade arquitetural com iOS.

## Regras obrigatórias

1. Trabalhe somente dentro do escopo da tarefa e registre requisitos, decisões e testes.
2. Preserve o histórico Git; não use force push nem apague legado sem autorização explícita.
3. Separe estado, regras, apresentação e integração de plataforma.
4. Não altere economia, assets aprovados ou requisitos de produto silenciosamente.
5. Toda mudança deve informar arquivos alterados, validações executadas e riscos restantes.
6. Não declare uma build ou teste como concluído sem executar a validação correspondente.

## Fluxo

Demanda -> Refinamento -> Arquitetura -> Implementação -> QA -> Review -> PR -> Build -> Homologação

## Definição de pronto

Código/documentação implementados, validação aplicável executada, sem segredos ou temporários versionados e handoff com limitações.

## MVP comercial e LiveOps — contratos v2.0.0

Consultar [especificação MVP](docs/architecture/MVP_LIVEOPS.md), [matriz](docs/orchestration/agent-matrix.md) e [registry](orchestration/config/agents.yaml). 12 especialistas + AGENT-00 coordenador. Novos domínios backend (09), database (10), liveops (11), security (12). DDL exige revisão DBA, COMMENT em todos os objetos/campos suportados, dicionário complementar e performance medida. Segurança revisa login, tokens, dados e IAP. Ações produtivas, benefícios/campanhas reais, alterações econômicas e merge exigem aprovação humana. Usar arquivos canônicos do registry.
