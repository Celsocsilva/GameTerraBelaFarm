-- TerraBela Farm backend - migration 003_backoffice_liveops
-- TBF-MVP-01 (admin/RBAC/auditoria), 05 (política de reembolso), 07 (métricas diárias),
-- 08/09 (campanhas push e fila FCM), 10 (motor de regras de benefícios).
-- Regra do PO: COMMENT em toda tabela, coluna e índice; constraints descritas em docs/database/CATALOG.md.

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE TABLE admin_users (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do usuário do backoffice',
    email VARCHAR(191) NOT NULL
        COMMENT 'E-mail de login do operador (minúsculas); não é jogador',
    display_name VARCHAR(80) NOT NULL
        COMMENT 'Nome exibido no backoffice e na auditoria',
    role VARCHAR(16) NOT NULL
        COMMENT 'Papel RBAC: admin (tudo), operation (LiveOps e config), support (jogadores e benefícios), read (somente leitura)',
    password_hash VARCHAR(255) NULL
        COMMENT 'Hash password_hash() (Argon2id ou bcrypt); NULL até o usuário concluir o link de configuração',
    totp_secret VARCHAR(64) NULL
        COMMENT 'Segredo TOTP (Base32) do segundo fator; NULL quando o 2FA não foi configurado',
    totp_enabled TINYINT(1) NOT NULL DEFAULT 0
        COMMENT '1 quando o login exige o código do aplicativo autenticador',
    totp_last_step BIGINT UNSIGNED NULL
        COMMENT 'Último passo TOTP (unix/30) aceito; impede reutilizar o mesmo código; NULL antes do primeiro uso',
    status VARCHAR(16) NOT NULL DEFAULT 'active'
        COMMENT 'Estado: active ou disabled (sem acesso, sessões revogadas)',
    failed_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Falhas de login consecutivas; zera no login correto',
    locked_until DATETIME(6) NULL
        COMMENT 'Instante UTC até quando o login fica bloqueado após muitas falhas; NULL sem bloqueio',
    setup_token_hash CHAR(64) NULL
        COMMENT 'SHA-256 do token do link de configuração de senha (uso único); NULL depois de usado',
    setup_expires_at DATETIME(6) NULL
        COMMENT 'Instante UTC de expiração do link de configuração; NULL sem link pendente',
    last_login_at DATETIME(6) NULL
        COMMENT 'Instante UTC do último login completo; NULL se nunca entrou',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação do usuário',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da última alteração de cadastro, senha ou 2FA',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_admin_users_email (email)
        COMMENT 'Um usuário por e-mail; busca no login',
    UNIQUE KEY uq_admin_users_setup (setup_token_hash)
        COMMENT 'Localiza o usuário pelo link de configuração',
    CONSTRAINT ck_admin_users_role CHECK (role IN ('admin','operation','support','read')),
    CONSTRAINT ck_admin_users_status CHECK (status IN ('active','disabled')),
    CONSTRAINT ck_admin_users_totp CHECK (totp_enabled IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Operadores do backoffice com RBAC por papel (domínio: administração), separados dos jogadores';

CREATE TABLE admin_sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da sessão do backoffice',
    admin_id INT UNSIGNED NOT NULL
        COMMENT 'Operador da sessão (FK admin_users.id)',
    token_hash CHAR(64) NOT NULL
        COMMENT 'HMAC-SHA256 do cookie de sessão; o valor do cookie nunca é gravado',
    csrf_token CHAR(64) NOT NULL
        COMMENT 'Token anti-CSRF desta sessão, exigido em todo formulário POST',
    mfa_passed TINYINT(1) NOT NULL DEFAULT 0
        COMMENT '1 quando a senha e (se habilitado) o TOTP foram confirmados; 0 aguardando o código',
    ip_hash CHAR(64) NOT NULL
        COMMENT 'SHA-256 com chave do IP de login (auditoria sem guardar IP em claro)',
    user_agent VARCHAR(255) NULL
        COMMENT 'Navegador do login (truncado); NULL se ausente',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do login',
    last_seen_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da última página; expira após 30 min sem uso',
    expires_at DATETIME(6) NOT NULL
        COMMENT 'Expiração absoluta UTC (12 h após o login)',
    revoked_at DATETIME(6) NULL
        COMMENT 'Instante UTC do logout ou revogação; NULL enquanto válida',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_admin_sessions_token (token_hash)
        COMMENT 'Autenticação de cada página pelo hash do cookie',
    KEY ix_admin_sessions_admin (admin_id, revoked_at)
        COMMENT 'Revogação das sessões de um operador; atende a FK',
    KEY ix_admin_sessions_expiry (expires_at)
        COMMENT 'Limpeza periódica pelo cron',
    CONSTRAINT fk_admin_sessions_user FOREIGN KEY (admin_id) REFERENCES admin_users (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_admin_sessions_mfa CHECK (mfa_passed IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Sessões do backoffice em banco, com expiração ociosa e absoluta (domínio: administração)';

CREATE TABLE admin_audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do registro de auditoria',
    admin_id INT UNSIGNED NULL
        COMMENT 'Operador que agiu (FK admin_users.id); NULL para tentativas sem usuário identificado ou ações do sistema',
    action VARCHAR(48) NOT NULL
        COMMENT 'Ação: login_ok, login_failed, wallet_adjust, reward_grant, config_publish, campaign_schedule etc.',
    target_type VARCHAR(32) NULL
        COMMENT 'Tipo do alvo (player, config, campaign, product, rule, admin_user); NULL quando não se aplica',
    target_id VARCHAR(64) NULL
        COMMENT 'Identificador público do alvo; NULL quando não se aplica',
    details JSON NULL
        COMMENT 'Dados da ação sem segredos (valores antes/depois, motivo); NULL sem detalhes',
    ip_hash CHAR(64) NULL
        COMMENT 'SHA-256 com chave do IP de origem; NULL em ações do sistema',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da ação',
    PRIMARY KEY (id)
        COMMENT 'Chave interna; ordem cronológica de gravação',
    KEY ix_admin_audit_admin (admin_id, id)
        COMMENT 'Histórico por operador; atende a FK',
    KEY ix_admin_audit_target (target_type, target_id, id)
        COMMENT 'Histórico de um alvo (ex.: todas as ações sobre um jogador)',
    KEY ix_admin_audit_created (created_at)
        COMMENT 'Filtro por período na tela de auditoria',
    CONSTRAINT fk_admin_audit_user FOREIGN KEY (admin_id) REFERENCES admin_users (id)
        ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Trilha append-only de ações no backoffice (domínio: administração/segurança)';

ALTER TABLE iap_transactions
    ADD COLUMN refund_clawback BIGINT UNSIGNED NULL
        COMMENT 'Quantidade da moeda do benefício descontada no reembolso (limitada ao saldo); NULL sem reembolso ou sem moeda'
        AFTER refunded_at,
    ADD COLUMN refund_shortfall BIGINT UNSIGNED NULL
        COMMENT 'Parte do benefício reembolsado que não pôde ser descontada por falta de saldo (fica para análise); NULL sem reembolso'
        AFTER refund_clawback;

CREATE TABLE notification_campaigns (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da campanha',
    public_id CHAR(12) NOT NULL
        COMMENT 'Código curto da campanha (C-xxxxxxxxxx) enviado no data do push como campaign_id',
    name VARCHAR(120) NOT NULL
        COMMENT 'Nome interno da campanha (não aparece para o jogador)',
    category VARCHAR(16) NOT NULL
        COMMENT 'operational (avisos do jogo, respeita notify_operational) ou promotional (ofertas, exige opt-in notify_promotional)',
    title VARCHAR(65) NOT NULL
        COMMENT 'Título da notificação exibido no aparelho',
    body VARCHAR(240) NOT NULL
        COMMENT 'Texto da notificação exibido no aparelho',
    route VARCHAR(16) NOT NULL
        COMMENT 'Destino ao tocar: farm, shop, tomatoes, corn, pumpkins, helpers, rewards, events',
    locale VARCHAR(16) NULL
        COMMENT 'Segmento por idioma do aparelho (pt_BR, es, en); NULL envia para todos os idiomas',
    platform VARCHAR(16) NULL
        COMMENT 'Segmento por plataforma (android/ios); NULL todas',
    inactive_days_min SMALLINT UNSIGNED NULL
        COMMENT 'Segmento: só jogadores sem atividade há pelo menos N dias; NULL sem filtro',
    status VARCHAR(16) NOT NULL DEFAULT 'draft'
        COMMENT 'Estado: draft, scheduled, sending, completed, canceled',
    scheduled_at DATETIME(6) NULL
        COMMENT 'Instante UTC a partir do qual o cron começa o envio; NULL em rascunho',
    expires_at DATETIME(6) NULL
        COMMENT 'Instante UTC após o qual envios pendentes são descartados; NULL sem expiração',
    audience_count INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Instalações colocadas na fila quando o envio começou',
    sent_count INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Mensagens aceitas pelo FCM (aceite não prova entrega)',
    failed_count INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Mensagens com falha definitiva',
    skipped_count INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Mensagens descartadas (limite semanal, opt-out, expiração)',
    created_by INT UNSIGNED NULL
        COMMENT 'Operador que criou (FK admin_users.id); NULL se criada pelo sistema',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação',
    started_at DATETIME(6) NULL
        COMMENT 'Instante UTC em que a fila foi montada; NULL antes do envio',
    completed_at DATETIME(6) NULL
        COMMENT 'Instante UTC do fim do envio ou cancelamento; NULL enquanto em andamento',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_campaigns_public_id (public_id)
        COMMENT 'Código público único da campanha',
    KEY ix_campaigns_status_schedule (status, scheduled_at)
        COMMENT 'Seleção pelo cron das campanhas a iniciar',
    KEY ix_campaigns_created_by (created_by)
        COMMENT 'Atende a FK created_by',
    CONSTRAINT fk_campaigns_created_by FOREIGN KEY (created_by) REFERENCES admin_users (id)
        ON DELETE SET NULL ON UPDATE RESTRICT,
    CONSTRAINT ck_campaigns_category CHECK (category IN ('operational','promotional')),
    CONSTRAINT ck_campaigns_status CHECK (status IN ('draft','scheduled','sending','completed','canceled')),
    CONSTRAINT ck_campaigns_route CHECK (route IN ('farm','shop','tomatoes','corn','pumpkins','helpers','rewards','events'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Campanhas de notificação push com segmento, agenda e contadores (domínio: LiveOps)';

CREATE TABLE notification_outbox (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da tarefa de envio (vira o notification_id do push)',
    campaign_id INT UNSIGNED NOT NULL
        COMMENT 'Campanha da mensagem (FK notification_campaigns.id)',
    device_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Instalação de destino (FK player_devices.id)',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador de destino (FK players.id), para limite semanal e auditoria',
    status VARCHAR(16) NOT NULL DEFAULT 'pending'
        COMMENT 'Estado: pending (na fila), sent (aceita pelo FCM), failed (erro definitivo), skipped (descartada pela política)',
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Tentativas de envio feitas',
    scheduled_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC da próxima tentativa (backoff exponencial com jitter em falhas temporárias)',
    last_error VARCHAR(160) NULL
        COMMENT 'Último erro do FCM, sem dados pessoais; NULL sem erro',
    fcm_message_id VARCHAR(160) NULL
        COMMENT 'Identificador devolvido pelo FCM no aceite; NULL antes do aceite',
    sent_at DATETIME(6) NULL
        COMMENT 'Instante UTC do aceite pelo FCM; NULL se não aceita',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC em que entrou na fila',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_outbox_campaign_device (campaign_id, device_id)
        COMMENT 'Invariante: no máximo uma mensagem por campanha e instalação; atende a FK campaign_id',
    KEY ix_outbox_status_schedule (status, scheduled_at, id)
        COMMENT 'Seleção ordenada das tarefas elegíveis pelo cron',
    KEY ix_outbox_player_sent (player_id, status, sent_at)
        COMMENT 'Contagem de pushes promocionais por jogador na semana; atende a FK player_id',
    KEY ix_outbox_device (device_id)
        COMMENT 'Atende a FK device_id',
    CONSTRAINT fk_outbox_campaign FOREIGN KEY (campaign_id) REFERENCES notification_campaigns (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_outbox_device FOREIGN KEY (device_id) REFERENCES player_devices (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_outbox_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_outbox_status CHECK (status IN ('pending','sent','failed','skipped'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Fila durável de envio FCM com nova tentativa e status distintos (domínio: LiveOps)';

CREATE TABLE reward_rules (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da versão da regra',
    rule_key VARCHAR(48) NOT NULL
        COMMENT 'Chave estável da regra (ex.: welcome, comeback_3d)',
    version SMALLINT UNSIGNED NOT NULL
        COMMENT 'Versão imutável; mudar condição ou benefício cria nova versão',
    description VARCHAR(200) NOT NULL
        COMMENT 'Descrição humana da regra',
    conditions JSON NOT NULL
        COMMENT 'Condições tipadas (lista de {"type":..., parâmetros}); nunca código executável',
    occurrence VARCHAR(8) NOT NULL
        COMMENT 'Frequência da concessão por jogador: once, day, week ou month',
    currency VARCHAR(8) NULL
        COMMENT 'Moeda do benefício (cash/gold); NULL quando só concede direito',
    amount BIGINT UNSIGNED NULL
        COMMENT 'Quantidade da moeda do benefício; NULL quando currency é NULL',
    entitlement_key VARCHAR(64) NULL
        COMMENT 'Direito permanente concedido; NULL quando não houver',
    expires_hours SMALLINT UNSIGNED NULL
        COMMENT 'Horas para resgatar depois da concessão; NULL sem expiração',
    max_grants_per_run INT UNSIGNED NOT NULL DEFAULT 1000
        COMMENT 'Teto de concessões por execução (orçamento/limite de público)',
    notify_campaign_id INT UNSIGNED NULL
        COMMENT 'Campanha operacional usada para avisar o jogador (FK notification_campaigns.id); NULL sem aviso',
    status VARCHAR(16) NOT NULL DEFAULT 'paused'
        COMMENT 'Estado: active (avaliada pelo cron), paused, retired (substituída por versão nova)',
    created_by INT UNSIGNED NULL
        COMMENT 'Operador que criou a versão (FK admin_users.id); NULL se pelo sistema',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação da versão',
    last_run_at DATETIME(6) NULL
        COMMENT 'Instante UTC da última avaliação pelo cron; NULL se nunca rodou',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_reward_rules_key_version (rule_key, version)
        COMMENT 'Versão única por regra',
    KEY ix_reward_rules_status (status)
        COMMENT 'Seleção das regras ativas pelo cron',
    KEY ix_reward_rules_campaign (notify_campaign_id)
        COMMENT 'Atende a FK notify_campaign_id',
    KEY ix_reward_rules_created_by (created_by)
        COMMENT 'Atende a FK created_by',
    CONSTRAINT fk_reward_rules_campaign FOREIGN KEY (notify_campaign_id) REFERENCES notification_campaigns (id)
        ON DELETE SET NULL ON UPDATE RESTRICT,
    CONSTRAINT fk_reward_rules_created_by FOREIGN KEY (created_by) REFERENCES admin_users (id)
        ON DELETE SET NULL ON UPDATE RESTRICT,
    CONSTRAINT ck_reward_rules_occurrence CHECK (occurrence IN ('once','day','week','month')),
    CONSTRAINT ck_reward_rules_status CHECK (status IN ('active','paused','retired')),
    CONSTRAINT ck_reward_rules_currency CHECK (currency IS NULL OR currency IN ('cash','gold'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Motor de regras declarativo de benefícios automáticos, versionado (domínio: recompensas)';

CREATE TABLE rule_executions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da execução',
    rule_id INT UNSIGNED NOT NULL
        COMMENT 'Versão de regra executada (FK reward_rules.id)',
    dry_run TINYINT(1) NOT NULL
        COMMENT '1 simulação (não concede), 0 execução real',
    eligible_count INT UNSIGNED NOT NULL
        COMMENT 'Jogadores que atenderam às condições',
    granted_count INT UNSIGNED NOT NULL
        COMMENT 'Benefícios novos concedidos (0 em simulação)',
    started_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC do início',
    finished_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC do fim',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    KEY ix_rule_executions_rule (rule_id, id)
        COMMENT 'Histórico por regra; atende a FK',
    CONSTRAINT fk_rule_executions_rule FOREIGN KEY (rule_id) REFERENCES reward_rules (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_rule_executions_dry CHECK (dry_run IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Histórico de avaliações das regras de benefício (domínio: recompensas)';

CREATE TABLE daily_metrics (
    metric_date DATE NOT NULL
        COMMENT 'Dia UTC a que o valor se refere',
    metric VARCHAR(40) NOT NULL
        COMMENT 'Nome do indicador: dau, new_players, sessions, iap_granted, iap_refunded, cash_source, cash_sink, gold_source, gold_sink, push_sent, push_opened, rewards_claimed',
    dimension VARCHAR(40) NOT NULL DEFAULT ''
        COMMENT 'Recorte opcional do indicador (ex.: SKU, motivo); vazio para o total',
    value BIGINT NOT NULL
        COMMENT 'Valor inteiro agregado do dia (contagem ou soma de moeda em unidades inteiras)',
    computed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do último recálculo (o cron recalcula hoje e ontem)',
    PRIMARY KEY (metric_date, metric, dimension)
        COMMENT 'Um valor por dia, indicador e recorte; alimenta os gráficos do painel',
    KEY ix_daily_metrics_metric (metric, metric_date)
        COMMENT 'Série temporal de um indicador'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Agregados diários para o painel, recalculados de forma incremental (domínio: analytics)';

INSERT INTO schema_migrations (version) VALUES ('003_backoffice_liveops');
