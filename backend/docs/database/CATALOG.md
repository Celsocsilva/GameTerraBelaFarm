# Catálogo complementar do schema — TerraBela Farm backend

Complementa os COMMENT nativos (MVP_LIVEOPS.md 9.1): o MySQL não aceita COMMENT em FOREIGN KEY e CHECK,
então cada constraint é descrita aqui pelo nome estável. `bin/datadict.php` falha se uma constraint,
view, trigger, rotina ou event do banco não aparecer neste arquivo.

**Política geral:** jogadores nunca são apagados fisicamente (exclusão = `status` deleted + purge de dados pessoais
pelo cron). Por isso os `ON DELETE CASCADE` abaixo só agiriam numa remoção manual de suporte; ledger e compras usam
`RESTRICT` para nunca perder trilha financeira. Todas as FKs usam `ON UPDATE RESTRICT` (chaves internas nunca mudam).

## Chaves estrangeiras (cardinalidade N:1 para `players` salvo indicação)

| Constraint | Relação e regra |
| --- | --- |
| `fk_identities_player` | player_identities.player_id → players.id. Um jogador tem 0..3 vínculos (no máximo um por provedor). CASCADE. |
| `fk_sessions_player` | player_sessions.player_id → players.id. 0..N sessões por jogador (uma por aparelho/login). CASCADE. |
| `fk_devices_player` | player_devices.player_id → players.id. 0..N instalações por jogador. CASCADE. |
| `fk_consents_player` | player_consents.player_id → players.id. Histórico 0..N. CASCADE. |
| `fk_saves_player` | player_saves.player_id → players.id. Relação 1:0..1 (um save corrente). CASCADE. |
| `fk_save_versions_player` | player_save_versions.player_id → players.id. Até SAVE_HISTORY cópias. CASCADE. |
| `fk_sync_operations_player` | sync_operations.player_id → players.id. Idempotência por jogador. CASCADE. |
| `fk_wallets_player` | wallets.player_id → players.id. Relação 1:1, criada junto com o jogador. CASCADE. |
| `fk_ledger_player` | economy_ledger.player_id → players.id. RESTRICT: lançamentos financeiros nunca somem com o jogador. |
| `fk_entitlements_player` | entitlements.player_id → players.id. CASCADE. |
| `fk_iap_tx_player` | iap_transactions.player_id → players.id. RESTRICT (auditoria fiscal). |
| `fk_iap_tx_product` | iap_transactions.product_id → iap_products.id (N:1, versão do benefício usada). RESTRICT: versões de produto usadas nunca são apagadas. |
| `fk_iap_events_transaction` | iap_events.transaction_id → iap_transactions.id (N:0..1). SET NULL: evento fica mesmo sem a compra. |
| `fk_game_events_player` | game_events.player_id → players.id. CASCADE. |
| `fk_reward_grants_player` | reward_grants.player_id → players.id. CASCADE. |
| `fk_reward_grants_ledger` | reward_grants.ledger_id → economy_ledger.id (1:0..1). RESTRICT. |
| `fk_notification_events_player` | notification_events.player_id → players.id. CASCADE. |
| `fk_admin_sessions_user` | admin_sessions.admin_id → admin_users.id (N:1). CASCADE: sessões somem com o operador. |
| `fk_admin_audit_user` | admin_audit_log.admin_id → admin_users.id (N:0..1). SET NULL: a trilha fica mesmo se o operador for removido. |
| `fk_campaigns_created_by` | notification_campaigns.created_by → admin_users.id. SET NULL. |
| `fk_outbox_campaign` | notification_outbox.campaign_id → notification_campaigns.id (N:1). CASCADE. |
| `fk_outbox_device` | notification_outbox.device_id → player_devices.id (N:1). CASCADE. |
| `fk_outbox_player` | notification_outbox.player_id → players.id (N:1). CASCADE. |
| `fk_reward_rules_campaign` | reward_rules.notify_campaign_id → notification_campaigns.id (N:0..1). SET NULL: a regra continua sem aviso. |
| `fk_reward_rules_created_by` | reward_rules.created_by → admin_users.id. SET NULL. |
| `fk_experiments_created_by` | experiments.created_by → admin_users.id. SET NULL. |
| `fk_experiment_assignments_experiment` | experiment_assignments.experiment_id → experiments.id (N:1). CASCADE. |
| `fk_experiment_assignments_player` | experiment_assignments.player_id → players.id (N:1). CASCADE: a variante some com a conta. |
| `fk_rule_executions_rule` | rule_executions.rule_id → reward_rules.id (N:1). CASCADE. |

## CHECK (MySQL 8.0.16+ e MariaDB 10.2+ aplicam; versões antigas apenas ignoram)

| Constraint | Regra |
| --- | --- |
| `ck_players_status` | status ∈ {active, deletion_requested, deleted}. |
| `ck_identities_provider` | provider ∈ {guest, google, facebook, apple} (apple desde a migration 006). |
| `ck_devices_platform` | platform ∈ {android, ios}. |
| `ck_consents_granted` | granted ∈ {0, 1}. |
| `ck_saves_revision` | revision ≥ 1 (a revisão 0 significa "sem save" e nunca é gravada). |
| `ck_ledger_currency` | currency ∈ {cash, gold}. |
| `ck_ledger_amount_nonzero` | amount ≠ 0 (lançamento sem efeito é proibido). |
| `ck_ledger_source` | source ∈ {client, iap, reward, admin, system}. |
| `ck_entitlements_source` | source ∈ {iap, reward, admin}. |
| `ck_iap_products_type` | product_type ∈ {consumable, non_consumable}. |
| `ck_iap_products_active` | active ∈ {0, 1}. |
| `ck_iap_tx_state` | state ∈ {pending, granted, canceled, refunded}. |
| `ck_iap_tx_finalize` | finalize_status ∈ {none, pending, done}. |
| `ck_iap_events_source` | source ∈ {verify, rtdn, reconcile}. |
| `ck_remote_config_status` | status ∈ {draft, published, retired}. |
| `ck_remote_config_env` | environment ∈ {local, staging, production}. |
| `ck_reward_grants_status` | status ∈ {available, claimed, expired, revoked}. |
| `ck_reward_grants_currency` | currency nulo (só direito) ou ∈ {cash, gold}. |
| `ck_notification_events_type` | event_type = opened. |
| `ck_admin_users_role` | role ∈ {admin, operation, support, read} (permissões em `src/Admin/Rbac.php`). |
| `ck_admin_users_status` | status ∈ {active, disabled}. |
| `ck_admin_users_totp` | totp_enabled ∈ {0, 1}. |
| `ck_admin_sessions_mfa` | mfa_passed ∈ {0, 1}. |
| `ck_campaigns_category` | category ∈ {operational, promotional}. |
| `ck_campaigns_status` | status ∈ {draft, scheduled, sending, completed, canceled}. |
| `ck_campaigns_route` | route ∈ rotas permitidas do MVP (farm, shop, tomatoes, corn, pumpkins, helpers, rewards, events). |
| `ck_outbox_status` | status ∈ {pending, sent, failed, skipped}. |
| `ck_reward_rules_occurrence` | occurrence ∈ {once, day, week, month}. |
| `ck_reward_rules_status` | status ∈ {active, paused, retired}. |
| `ck_reward_rules_currency` | currency nulo ou ∈ {cash, gold}. |
| `ck_rule_executions_dry` | dry_run ∈ {0, 1}. |
| `ck_experiments_status` | status ∈ {draft, running, stopped}. |
| `ck_experiments_traffic` | traffic_percent ≤ 100. |

Saldo não negativo: `wallets.cash_balance`, `wallets.gold_balance` e `economy_ledger.balance_after` são
`BIGINT UNSIGNED`, então o próprio tipo impede saldo negativo; o serviço também verifica antes de gravar.

## UNIQUE e índices

Têm COMMENT nativo e aparecem no [DATA_DICTIONARY.md](DATA_DICTIONARY.md). Índices implícitos de FK não
existem: toda FK é atendida por um índice declarado e comentado.

## Views, triggers, procedures, functions, events e partições

Nenhum no MVP. Motivo: a regra do schema pede finalidade, teste e evidência para cada objeto; atomicidade e
idempotência já ficam nos serviços PHP com transações curtas, e o cron do PHP já cobre as rotinas periódicas.
Particionar `game_events` e `economy_ledger` será avaliado com benchmark quando houver volume real.

## Sequências

Não há sequências customizadas: identificadores internos usam `BIGINT UNSIGNED AUTO_INCREMENT` (lacunas são
normais) e identificadores públicos usam UUID v4 binário (`BINARY(16)`). `remote_config_versions.version_number`
é alocado com `SELECT ... FOR UPDATE` dentro da transação de publicação.
