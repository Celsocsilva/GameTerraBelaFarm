# Matriz de agentes — v2.0.0

12 especialistas + AGENT-00 coordenador. Contratos canônicos no registry.

| ID | Domínio | Especialidade | Nível |
| --- | --- | --- | --- |
| AGENT-00 | coordination | [Orchestrator](../../agents/orchestrator.md) | 4 |
| AGENT-01 | product | [Game Director](../../agents/agent-01-game-director.md) | 1 |
| AGENT-02 | architecture | [Solution Architect](../../agents/agent-02-solution-architect.md) | 2 |
| AGENT-03 | gameplay | [Gameplay Engineer](../../agents/agent-03-gameplay-engineer.md) | 2 |
| AGENT-04 | art | [Technical Art & Animation](../../agents/agent-04-technical-artist.md) | 2 |
| AGENT-05 | ui | [Mobile UI/UX & Admin Frontend](../../agents/agent-05-mobile-uiux.md) | 2 |
| AGENT-06 | qa | [QA & Integration Engineer](../../agents/agent-06-qa-engineer.md) | 3 |
| AGENT-07 | devops | [Mobile & Backend DevOps](../../agents/agent-07-devops-engineer.md) | 4 |
| AGENT-08 | review | [Engineering Reviewer](../../agents/agent-08-engineering-reviewer.md) | 1 |
| AGENT-09 | backend | [Backend Engineer](../../agents/agent-09-backend-engineer.md) | 2 |
| AGENT-10 | database | [Database Engineer / DBA](../../agents/agent-10-database-engineer.md) | 2 |
| AGENT-11 | liveops | [LiveOps & Data Analytics Engineer](../../agents/agent-11-liveops-analytics-engineer.md) | 2 |
| AGENT-12 | security | [Security & Monetization Engineer](../../agents/agent-12-security-monetization-engineer.md) | 2 |

## Revisões cruzadas quando aplicáveis

| Mudança | Executor | Revisores especialistas | Gate independente |
| --- | --- | --- | --- |
| API/save/Remote Config | 09 + 03 | 02, 10, 12 | 06, 08 |
| Schema/migrations | 10 | 09, 07 | 06, 08 |
| Autenticação/IAP | 12 + 09 + 05 | 02, 10 | 06, 08 |
| FCM/campanhas/benefícios | 11 + 09 + 05 | 10, 12, 01 | 06, 08 |
| Dashboard/analytics | 11 + 05 | 09, 10, 12 | 06, 08 |
| Gameplay/arte | 03 + 04 + 05 | 02, 01 | 06, 08 |
| Deploy/backup/release | 07 | 10, 12 | 06, 08 + humano |

A matriz orienta a coordenação assistida; não automatiza aprovação ou gates.
