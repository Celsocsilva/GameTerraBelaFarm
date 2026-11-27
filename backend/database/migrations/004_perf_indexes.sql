-- TerraBela Farm backend - migration 004_perf_indexes
-- TBF-MVP-12: índices achados pelo benchmark (bin/bench.php) para as consultas por período do painel,
-- das métricas diárias e do público de push. Só adiciona índices (sem mudança de dados).
-- Regra do PO: COMMENT em todo índice.

SET NAMES utf8mb4;

ALTER TABLE players
    ADD KEY ix_players_created (created_at)
        COMMENT 'Novos jogadores por dia e coortes de retenção (métricas e painel)';

ALTER TABLE player_sessions
    ADD KEY ix_sessions_created (created_at, player_id)
        COMMENT 'DAU por sessões iniciadas no dia (métricas); cobre player_id',
    ADD KEY ix_sessions_rotated (rotated_at, player_id)
        COMMENT 'DAU por sessões renovadas no dia (métricas); cobre player_id';

ALTER TABLE game_events
    ADD KEY ix_game_events_time_player (occurred_at, player_id)
        COMMENT 'DAU e contagens por período (métricas e painel); cobre player_id';

ALTER TABLE economy_ledger
    ADD KEY ix_ledger_created (created_at, currency, source, amount)
        COMMENT 'Totais de moeda por período e origem (métricas, painel e ledger 24 h); cobre a soma';

ALTER TABLE player_devices
    ADD KEY ix_devices_audience (locale, revoked_at, platform)
        COMMENT 'Público de campanhas push por idioma/plataforma entre instalações ativas';

ALTER TABLE iap_transactions
    ADD KEY ix_iap_tx_granted (granted_at)
        COMMENT 'Compras concedidas por dia (métricas)',
    ADD KEY ix_iap_tx_refunded (refunded_at)
        COMMENT 'Reembolsos por dia (métricas e painel)';

ALTER TABLE reward_grants
    ADD KEY ix_reward_grants_claimed (claimed_at)
        COMMENT 'Benefícios resgatados por dia (métricas e painel)';

ALTER TABLE notification_outbox
    ADD KEY ix_outbox_status_sent (status, sent_at)
        COMMENT 'Pushes aceitos por dia (métricas e painel)';

ALTER TABLE notification_events
    ADD KEY ix_notification_events_time (occurred_at)
        COMMENT 'Aberturas de push por dia (métricas)';

INSERT INTO schema_migrations (version) VALUES ('004_perf_indexes');
