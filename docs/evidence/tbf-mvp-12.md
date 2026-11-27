# TBF-MVP-12 — backup, restauração, exportação LGPD e desempenho

Data: 27/11/2026. Ambiente de prova: container com PHP 8.3 e MySQL 8.0.46 real.

## Entregue

- **Backup lógico** (`src/Ops/BackupService.php`, `bin/backup.php`, cron diário com `BACKUP_ENABLED=1`): snapshot consistente, gz, criptografia opcional AES-256-GCM (`BACKUP_ENCRYPTION_KEY`), retenção `BACKUP_KEEP`, pasta protegida por `.htaccess`. Tela "Sistema e backup" no backoffice (só admin).
- **Restauração verificada** (`bin/restore.php ARQUIVO --confirm`): exige o marcador de fim do arquivo; teste compara `CHECKSUM TABLE` do banco original e do restaurado.
- **Exportação LGPD** (`src/Players/DataExport.php`): `GET /api/v1/me/export` (3 por hora) e botão na ficha do jogador no backoffice (auditado). Não inclui hashes nem tokens. Inventário de dados em `docs/privacy/DATA_SAFETY.md`.
- **Desempenho**: `bin/bench.php` mede 16 consultas críticas com volume simulado. A primeira rodada achou 4 varreduras completas; a migration `004_perf_indexes.sql` (11 índices com COMMENT) zerou.

## Benchmark (depois da migration 004)

Volume: 20000 jogadores, 200000 eventos, 160000 lançamentos no ledger, 20000 sessões e 20000 aparelhos (carga em 8.4 s). Banco: 8.0.46-0ubuntu0.24.04.5. Data: 2026-11-27 22:24 UTC. 30 execuções por consulta.

| Consulta | Plano (tabela:tipo(índice)) | p50 ms | p95 ms | Varredura completa |
|---|---|---:|---:|---|
| Autenticar token (toda requisição) | s:const(uq_sessions_access_hash) → p:const(PRIMARY) | 0.11 | 0.23 | não |
| Carteira com trava (lançamento) | wallets:const(PRIMARY) | 0.08 | 0.23 | não |
| Idempotência do lançamento | : | 0.06 | 0.16 | não |
| Teto diário de cash do cliente | economy_ledger:range(ix_ledger_player_daily) | 0.12 | 0.22 | não |
| Histórico do ledger (50) | economy_ledger:ref(uq_ledger_player_idempotency) | 0.12 | 0.22 | não |
| Remote Config vigente | remote_config_versions:ref(uq_remote_config_env_version) | 0.08 | 0.12 | não |
| Login visitante | i:const(uq_identities_provider_subject) | 0.07 | 0.16 | não |
| Painel: DAU do dia (eventos) | game_events:range(ix_game_events_time_player) | 24.02 | 26.97 | não |
| Painel: DAU do dia (sessões) | player_sessions:index_merge(ix_sessions_created,ix_sessions_rotated) | 1.25 | 2.97 | não |
| Painel: novos jogadores do dia | players:range(ix_players_created) | 0.10 | 0.16 | não |
| Painel: ouro creditado no dia | economy_ledger:range(ix_ledger_created) | 15.54 | 23.99 | não |
| Painel: ativos 7 dias | players:range(ix_players_last_seen) | 0.47 | 0.55 | não |
| Push: público promocional (pt_BR) | d:ref(ix_devices_audience) → p:eq_ref(PRIMARY) → c:ref(ix_consents_player_type) | 26.30 | 27.22 | não |
| Regra: inativos há 7+ dias sem benefício | p:ref(ix_players_status_deletion) → <subquery2>:eq_ref(<auto_distinct_key>) → g:index(uq_reward_grants_occurrence) | 16.09 | 16.53 | não |
| Backoffice: lista de jogadores | p:index(PRIMARY) → w:eq_ref(PRIMARY) | 0.10 | 0.18 | não |
| Backoffice: ledger 24 h por origem | economy_ledger:range(ix_ledger_created) | 50.73 | 52.39 | não |

Consultas com varredura completa em tabela grande: 0.

## Verificação

`TBF_ENV_FILE=... php backend/tests/run.php`: 304 verificações ok, 0 falhas (inclui backup, restauração com checksum, criptografia, retenção e exportação).
