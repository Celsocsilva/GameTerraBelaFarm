-- TerraBela Farm backend - migration 001_core
-- TBF-MVP-01/02/03/04/06/07 (fundação, identidade, save, economia, config, telemetria)
-- Compatível com MySQL 8.0+ (alvo) e MariaDB 10.6+ (hospedagem compartilhada).
-- Regra do Product Owner (MVP_LIVEOPS.md 9.1): toda tabela, coluna e índice tem COMMENT.
-- Constraints (FK/CHECK/UNIQUE) estão descritas também em docs/database/CATALOG.md.
-- Import manual (phpMyAdmin): selecione o banco e importe este arquivo inteiro uma única vez.

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE TABLE schema_migrations (
    version VARCHAR(64) NOT NULL
        COMMENT 'Nome do arquivo de migration aplicado, sem extensão (ex.: 001_core)',
    applied_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC em que a migration terminou de ser aplicada',
    checksum CHAR(64) NULL
        COMMENT 'SHA-256 do arquivo SQL aplicado pelo runner; NULL quando importado manualmente pelo phpMyAdmin',
    PRIMARY KEY (version)
        COMMENT 'Uma linha por migration; impede aplicar a mesma versão duas vezes'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Controle de versões do schema do backend TerraBela Farm (domínio: plataforma)';

CREATE TABLE players (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do jogador; nunca exposto ao cliente',
    public_id BINARY(16) NOT NULL
        COMMENT 'Identificador público opaco (UUID v4 binário) exposto ao app como player_id',
    status VARCHAR(24) NOT NULL DEFAULT 'active'
        COMMENT 'Estado da conta: active, deletion_requested (exclusão pedida, sessões revogadas) ou deleted (dados pessoais removidos)',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação da conta (primeiro acesso como visitante ou por provedor)',
    last_seen_at DATETIME(6) NULL
        COMMENT 'Instante UTC da última requisição autenticada; NULL até o primeiro uso de token',
    locale VARCHAR(16) NULL
        COMMENT 'Idioma informado pelo app (ex.: pt_BR, es, en); NULL quando não informado',
    deletion_requested_at DATETIME(6) NULL
        COMMENT 'Instante UTC em que o jogador pediu exclusão via DELETE /me; NULL se nunca pediu',
    deleted_at DATETIME(6) NULL
        COMMENT 'Instante UTC em que o purge removeu os dados pessoais; NULL enquanto não executado',
    PRIMARY KEY (id)
        COMMENT 'Chave interna compacta para FKs',
    UNIQUE KEY uq_players_public_id (public_id)
        COMMENT 'Busca do jogador pelo identificador público e garantia de unicidade',
    KEY ix_players_last_seen (last_seen_at, id)
        COMMENT 'Consultas de atividade (DAU/MAU, segmentação por última atividade)',
    KEY ix_players_status_deletion (status, deletion_requested_at)
        COMMENT 'Seleção pelo cron das contas com exclusão pendente após a carência',
    CONSTRAINT ck_players_status CHECK (status IN ('active','deletion_requested','deleted'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Contas de jogador (domínio: identidade). Uma fazenda por jogador';

CREATE TABLE player_identities (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do vínculo de identidade',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador dono do vínculo (FK players.id)',
    provider VARCHAR(16) NOT NULL
        COMMENT 'Provedor: guest (visitante com segredo do servidor), google ou facebook',
    subject VARCHAR(191) NOT NULL
        COMMENT 'Identificador estável do usuário no provedor (sub do Google, user_id do Facebook, guest_id do visitante)',
    secret_hash CHAR(64) NULL
        COMMENT 'HMAC-SHA256 (hex) do segredo do visitante com APP_KEY; NULL para provedores externos',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC em que o vínculo foi criado',
    last_used_at DATETIME(6) NULL
        COMMENT 'Instante UTC do último login por este vínculo; NULL se nunca usado após a criação',
    PRIMARY KEY (id)
        COMMENT 'Chave interna do vínculo',
    UNIQUE KEY uq_identities_provider_subject (provider, subject)
        COMMENT 'Invariante: uma identidade de provedor pertence a no máximo um jogador',
    UNIQUE KEY uq_identities_player_provider (player_id, provider)
        COMMENT 'Invariante: no máximo um vínculo por provedor em cada jogador; também atende a FK player_id',
    CONSTRAINT fk_identities_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_identities_provider CHECK (provider IN ('guest','google','facebook'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Vínculos de login de cada jogador (domínio: identidade). Nunca une contas por e-mail';

CREATE TABLE player_sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da sessão',
    public_id BINARY(16) NOT NULL
        COMMENT 'Identificador público opaco da sessão (usado em logs e logout por dispositivo)',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador autenticado nesta sessão (FK players.id)',
    access_hash CHAR(64) NOT NULL
        COMMENT 'HMAC-SHA256 (hex) do token de acesso atual; o token em texto nunca é gravado',
    access_expires_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC de expiração do token de acesso (curto, padrão 1 hora)',
    refresh_hash CHAR(64) NOT NULL
        COMMENT 'HMAC-SHA256 (hex) do refresh token atual; troca a cada /auth/refresh',
    previous_refresh_hash CHAR(64) NULL
        COMMENT 'HMAC do refresh token anterior; reapresentá-lo indica roubo e revoga a sessão. NULL antes da primeira rotação',
    refresh_expires_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC de expiração do refresh token (padrão 30 dias, renovado a cada rotação)',
    login_provider VARCHAR(16) NOT NULL
        COMMENT 'Provedor usado para abrir a sessão: guest, google ou facebook',
    user_agent VARCHAR(255) NULL
        COMMENT 'User-Agent do app ao abrir a sessão (truncado em 255); NULL se ausente',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de abertura da sessão',
    rotated_at DATETIME(6) NULL
        COMMENT 'Instante UTC da última rotação de tokens; NULL se nunca rotacionada',
    revoked_at DATETIME(6) NULL
        COMMENT 'Instante UTC de revogação (logout, reuso de refresh, exclusão); NULL enquanto válida',
    revoke_reason VARCHAR(32) NULL
        COMMENT 'Motivo da revogação: logout, refresh_reuse, account_deleted, admin; NULL enquanto válida',
    PRIMARY KEY (id)
        COMMENT 'Chave interna da sessão',
    UNIQUE KEY uq_sessions_public_id (public_id)
        COMMENT 'Unicidade do identificador público da sessão',
    UNIQUE KEY uq_sessions_access_hash (access_hash)
        COMMENT 'Autenticação de cada requisição pelo hash do token de acesso',
    UNIQUE KEY uq_sessions_refresh_hash (refresh_hash)
        COMMENT 'Localização da sessão no /auth/refresh',
    KEY ix_sessions_previous_refresh (previous_refresh_hash)
        COMMENT 'Detecção de reuso de refresh token já rotacionado',
    KEY ix_sessions_player (player_id, revoked_at)
        COMMENT 'Revogação de todas as sessões ativas do jogador; atende a FK player_id',
    KEY ix_sessions_refresh_expiry (refresh_expires_at)
        COMMENT 'Limpeza periódica de sessões expiradas pelo cron',
    CONSTRAINT fk_sessions_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Sessões do app com token de acesso curto e refresh rotativo (domínio: identidade)';

CREATE TABLE player_devices (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da instalação',
    public_id BINARY(16) NOT NULL
        COMMENT 'Identificador público da instalação, usado em DELETE /devices/{id}',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador dono da instalação (FK players.id)',
    installation_id VARCHAR(64) NOT NULL
        COMMENT 'Identificador aleatório gerado pelo app na instalação; não é ID de hardware',
    platform VARCHAR(16) NOT NULL
        COMMENT 'Plataforma da instalação: android ou ios',
    fcm_token VARCHAR(512) NULL
        COMMENT 'Token de registro do Firebase Cloud Messaging; NULL sem permissão ou após invalidação',
    fcm_token_hash CHAR(64) NULL
        COMMENT 'SHA-256 (hex) do token FCM para unicidade e busca; NULL quando fcm_token é NULL',
    app_version VARCHAR(32) NULL
        COMMENT 'Versão do app informada no último registro (ex.: 0.3.0); NULL se não informada',
    locale VARCHAR(16) NULL
        COMMENT 'Idioma do aparelho no último registro; NULL se não informado',
    timezone VARCHAR(64) NULL
        COMMENT 'Fuso IANA do aparelho (ex.: America/Sao_Paulo) para horário de silêncio; NULL se não informado',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do primeiro registro da instalação',
    last_seen_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do último registro/atualização',
    revoked_at DATETIME(6) NULL
        COMMENT 'Instante UTC da revogação (logout do aparelho, token inválido, exclusão); NULL enquanto ativa',
    PRIMARY KEY (id)
        COMMENT 'Chave interna da instalação',
    UNIQUE KEY uq_devices_public_id (public_id)
        COMMENT 'Unicidade do identificador público da instalação',
    UNIQUE KEY uq_devices_player_installation (player_id, installation_id)
        COMMENT 'Uma linha por instalação de cada jogador; atende a FK player_id',
    UNIQUE KEY uq_devices_fcm_token_hash (fcm_token_hash)
        COMMENT 'Um token FCM aponta para uma única instalação ativa',
    CONSTRAINT fk_devices_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_devices_platform CHECK (platform IN ('android','ios'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Instalações do app e tokens FCM por jogador (domínio: notificações)';

CREATE TABLE player_consents (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do registro de consentimento',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador que registrou a preferência (FK players.id)',
    consent_type VARCHAR(32) NOT NULL
        COMMENT 'Tipo: notify_operational (avisos do jogo), notify_promotional (ofertas) ou os_notification_permission (estado da permissão do sistema)',
    granted TINYINT(1) NOT NULL
        COMMENT 'Valor registrado: 1 concedido, 0 negado/retirado',
    source VARCHAR(32) NOT NULL
        COMMENT 'Origem do registro: app_settings, os_prompt, api',
    recorded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do registro; o mais recente por tipo é o estado vigente',
    PRIMARY KEY (id)
        COMMENT 'Chave interna; ordem de inserção desempata registros no mesmo instante',
    KEY ix_consents_player_type (player_id, consent_type, recorded_at, id)
        COMMENT 'Leitura do estado vigente por tipo e histórico do jogador; atende a FK player_id',
    CONSTRAINT fk_consents_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_consents_granted CHECK (granted IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Histórico append-only de preferências de notificação e permissões (domínio: privacidade)';

CREATE TABLE player_saves (
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador dono do save (FK players.id); um save corrente por jogador',
    revision INT UNSIGNED NOT NULL
        COMMENT 'Revisão monotônica do save; começa em 1 e cresce a cada POST /sync aceito',
    schema_version SMALLINT UNSIGNED NOT NULL
        COMMENT 'Versão do formato do save definida pelo app (App.SAVE_VERSION)',
    snapshot JSON NOT NULL
        COMMENT 'Snapshot do estado do jogo enviado pelo app; saldos de moedas nele são ignorados (servidor é autoridade)',
    snapshot_bytes INT UNSIGNED NOT NULL
        COMMENT 'Tamanho em bytes do JSON do snapshot, para limites e monitoramento',
    client_saved_at DATETIME(6) NULL
        COMMENT 'Instante informado pelo app para o save (relógio do aparelho, só informativo); NULL se ausente',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do servidor em que esta revisão foi gravada',
    PRIMARY KEY (player_id)
        COMMENT 'Um save corrente por jogador; também atende a FK',
    CONSTRAINT fk_saves_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_saves_revision CHECK (revision >= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Save na nuvem corrente de cada jogador (domínio: persistência)';

CREATE TABLE player_save_versions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da cópia histórica',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador dono da cópia (FK players.id)',
    revision INT UNSIGNED NOT NULL
        COMMENT 'Revisão que esta cópia representava antes de ser substituída',
    schema_version SMALLINT UNSIGNED NOT NULL
        COMMENT 'Versão do formato do save desta cópia',
    snapshot JSON NOT NULL
        COMMENT 'Conteúdo da revisão substituída, para recuperação pelo suporte',
    saved_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC em que a revisão substituída havia sido gravada',
    archived_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC em que a revisão foi movida para o histórico',
    PRIMARY KEY (id)
        COMMENT 'Chave interna da cópia',
    UNIQUE KEY uq_save_versions_player_revision (player_id, revision)
        COMMENT 'Uma cópia por revisão de cada jogador; ordena a poda do histórico; atende a FK',
    CONSTRAINT fk_save_versions_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Histórico limitado (SAVE_HISTORY revisões) de saves substituídos (domínio: persistência)';

CREATE TABLE sync_operations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do registro de idempotência',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador que enviou a operação (FK players.id)',
    operation_id VARCHAR(64) NOT NULL
        COMMENT 'Identificador estável gerado pelo app para a operação; repetir devolve a resposta original',
    operation_type VARCHAR(16) NOT NULL
        COMMENT 'Tipo da operação: save (POST /sync)',
    request_hash CHAR(64) NOT NULL
        COMMENT 'SHA-256 do corpo normalizado; mesmo operation_id com corpo diferente é rejeitado',
    response_status SMALLINT UNSIGNED NOT NULL
        COMMENT 'Código HTTP da resposta original',
    response_body JSON NOT NULL
        COMMENT 'Corpo JSON da resposta original devolvido em repetições',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do processamento original',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_sync_operations_player_op (player_id, operation_id)
        COMMENT 'Invariante de idempotência: operation_id único por jogador; atende a FK',
    KEY ix_sync_operations_created (created_at)
        COMMENT 'Poda periódica de registros antigos pelo cron',
    CONSTRAINT fk_sync_operations_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Registro de idempotência de comandos de sincronização (domínio: persistência)';

CREATE TABLE wallets (
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador dono da carteira (FK players.id)',
    cash_balance BIGINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Saldo de cash (moeda comum do jogo) em unidades inteiras; projeção do economy_ledger',
    gold_balance BIGINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Saldo de gold (moeda premium) em unidades inteiras; projeção do economy_ledger',
    version INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Contador de alterações; cresce 1 a cada lançamento no ledger',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da última alteração de saldo',
    PRIMARY KEY (player_id)
        COMMENT 'Uma carteira por jogador; linha travada com FOR UPDATE em cada lançamento',
    CONSTRAINT fk_wallets_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Saldos correntes cash/gold; só alterados junto com economy_ledger na mesma transação (domínio: economia)';

CREATE TABLE economy_ledger (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do lançamento; ordem dentro do jogador',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador do lançamento (FK players.id)',
    currency VARCHAR(8) NOT NULL
        COMMENT 'Moeda: cash (comum) ou gold (premium)',
    amount BIGINT NOT NULL
        COMMENT 'Quantidade inteira assinada: positiva credita, negativa debita; nunca zero',
    balance_after BIGINT UNSIGNED NOT NULL
        COMMENT 'Saldo da moeda logo após este lançamento',
    source VARCHAR(16) NOT NULL
        COMMENT 'Origem: client (operação do app dentro da política), iap (compra verificada), reward (benefício resgatado), admin, system',
    reason VARCHAR(40) NOT NULL
        COMMENT 'Motivo de negócio (ex.: sale_collected, helper_hired, iap_purchase, reward_claim)',
    reference VARCHAR(128) NULL
        COMMENT 'Referência externa opcional (SKU, id do benefício, id de pedido); NULL quando não houver',
    idempotency_key VARCHAR(100) NOT NULL
        COMMENT 'Chave única por jogador que impede lançar a mesma operação duas vezes',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do lançamento',
    PRIMARY KEY (id)
        COMMENT 'Chave interna do lançamento',
    UNIQUE KEY uq_ledger_player_idempotency (player_id, idempotency_key)
        COMMENT 'Invariante de idempotência do ledger; atende a FK player_id',
    KEY ix_ledger_player_id (player_id, id)
        COMMENT 'Histórico paginado por cursor do jogador',
    KEY ix_ledger_player_daily (player_id, currency, source, created_at)
        COMMENT 'Soma de créditos do cliente no dia para o teto diário',
    CONSTRAINT fk_ledger_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_ledger_currency CHECK (currency IN ('cash','gold')),
    CONSTRAINT ck_ledger_amount_nonzero CHECK (amount <> 0),
    CONSTRAINT ck_ledger_source CHECK (source IN ('client','iap','reward','admin','system'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Ledger append-only de moedas; fonte da verdade dos saldos (domínio: economia)';

CREATE TABLE entitlements (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do direito concedido',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador que recebeu o direito (FK players.id)',
    entitlement_key VARCHAR(64) NOT NULL
        COMMENT 'Chave do item permanente (ex.: helper_slot_extra, cosmetic_hat_straw) definida no catálogo',
    source VARCHAR(16) NOT NULL
        COMMENT 'Origem: iap, reward, admin',
    source_reference VARCHAR(128) NOT NULL
        COMMENT 'Referência da origem (id da transação IAP ou do benefício)',
    granted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da concessão',
    revoked_at DATETIME(6) NULL
        COMMENT 'Instante UTC da revogação (reembolso/estorno); NULL enquanto vigente',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_entitlements_player_key (player_id, entitlement_key)
        COMMENT 'Um direito por chave por jogador (concessão idempotente); atende a FK',
    CONSTRAINT fk_entitlements_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_entitlements_source CHECK (source IN ('iap','reward','admin'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Itens permanentes concedidos pelo servidor (domínio: economia)';

CREATE TABLE iap_products (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do produto/versão',
    platform VARCHAR(16) NOT NULL
        COMMENT 'Loja: google_play (app_store em expansão futura)',
    sku VARCHAR(100) NOT NULL
        COMMENT 'Product ID cadastrado na loja (Play Console)',
    product_type VARCHAR(16) NOT NULL
        COMMENT 'consumable (consumido após conceder, ex.: pacote de gold) ou non_consumable (direito permanente)',
    benefit_version SMALLINT UNSIGNED NOT NULL
        COMMENT 'Versão imutável do benefício; mudar o benefício exige nova versão',
    benefit JSON NOT NULL
        COMMENT 'Benefício aprovado: {"currency":"gold","amount":N} e/ou {"entitlements":["chave"]}',
    active TINYINT(1) NOT NULL DEFAULT 0
        COMMENT '1 quando esta versão é a vigente para o SKU; 0 rascunho ou versão antiga',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de cadastro desta versão',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_iap_products_sku_version (platform, sku, benefit_version)
        COMMENT 'Versão de benefício única por SKU e loja',
    KEY ix_iap_products_active (platform, sku, active)
        COMMENT 'Busca da versão ativa do SKU na validação de compra',
    CONSTRAINT ck_iap_products_type CHECK (product_type IN ('consumable','non_consumable')),
    CONSTRAINT ck_iap_products_active CHECK (active IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Catálogo interno que mapeia SKU da loja a benefício versionado; preços vêm sempre da loja (domínio: monetização)';

CREATE TABLE iap_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da compra',
    public_id BINARY(16) NOT NULL
        COMMENT 'Identificador público opaco da compra devolvido ao app',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador que apresentou a compra (FK players.id)',
    product_id INT UNSIGNED NOT NULL
        COMMENT 'Versão do produto/benefício usada na concessão (FK iap_products.id)',
    platform VARCHAR(16) NOT NULL
        COMMENT 'Loja da compra: google_play',
    purchase_token VARCHAR(512) NOT NULL
        COMMENT 'Purchase token da Google Play, necessário para consultar/consumir; nunca registrado em log',
    purchase_token_hash CHAR(64) NOT NULL
        COMMENT 'SHA-256 (hex) do purchase token; garante uso único',
    order_id VARCHAR(100) NULL
        COMMENT 'orderId (GPA.xxxx) retornado pela Google; NULL enquanto a compra estiver pendente',
    state VARCHAR(16) NOT NULL
        COMMENT 'Estado: pending (aguardando pagamento), granted (benefício concedido), canceled, refunded (estornada pela loja)',
    store_state_raw VARCHAR(32) NULL
        COMMENT 'purchaseState/consumptionState/acknowledgementState da última consulta, para auditoria; NULL antes da consulta',
    finalize_status VARCHAR(16) NOT NULL DEFAULT 'none'
        COMMENT 'Finalização na loja: none, pending (consume/acknowledge a repetir), done',
    finalize_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Tentativas de consume/acknowledge feitas',
    purchase_time DATETIME(6) NULL
        COMMENT 'Instante UTC da compra segundo a loja; NULL se não informado',
    granted_at DATETIME(6) NULL
        COMMENT 'Instante UTC da concessão do benefício; NULL se ainda não concedido',
    refunded_at DATETIME(6) NULL
        COMMENT 'Instante UTC em que o estorno foi registrado; NULL se não houve',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do primeiro registro da compra',
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da última mudança de estado',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_iap_tx_public_id (public_id)
        COMMENT 'Unicidade do identificador público',
    UNIQUE KEY uq_iap_tx_token_hash (purchase_token_hash)
        COMMENT 'Invariante: um purchase token gera no máximo uma concessão',
    UNIQUE KEY uq_iap_tx_order (platform, order_id)
        COMMENT 'Invariante: um pedido da loja gera no máximo uma transação (NULLs permitidos)',
    KEY ix_iap_tx_player (player_id, created_at)
        COMMENT 'Histórico de compras do jogador; atende a FK player_id',
    KEY ix_iap_tx_product (product_id)
        COMMENT 'Atende a FK product_id e relatórios por produto',
    KEY ix_iap_tx_finalize (finalize_status, updated_at)
        COMMENT 'Seleção pelo cron das compras com consume/acknowledge pendente',
    CONSTRAINT fk_iap_tx_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_iap_tx_product FOREIGN KEY (product_id) REFERENCES iap_products (id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_iap_tx_state CHECK (state IN ('pending','granted','canceled','refunded')),
    CONSTRAINT ck_iap_tx_finalize CHECK (finalize_status IN ('none','pending','done'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Compras na loja validadas no servidor (domínio: monetização). Retida para auditoria fiscal';

CREATE TABLE iap_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do evento',
    source VARCHAR(16) NOT NULL
        COMMENT 'Origem: verify (chamada do app), rtdn (notificação Pub/Sub da Google), reconcile (cron)',
    message_id VARCHAR(128) NOT NULL
        COMMENT 'Identificador do evento na origem (messageId do Pub/Sub ou id gerado); torna o processamento idempotente',
    transaction_id BIGINT UNSIGNED NULL
        COMMENT 'Compra afetada (FK iap_transactions.id); NULL quando o token ainda não é conhecido',
    event_type VARCHAR(48) NOT NULL
        COMMENT 'Tipo: ONE_TIME_PRODUCT_PURCHASED, VOIDED_PURCHASE, VERIFY_GRANTED, VERIFY_PENDING etc.',
    payload JSON NOT NULL
        COMMENT 'Dados do evento sem purchase token em claro (substituído pelo hash)',
    received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de recebimento',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_iap_events_source_message (source, message_id)
        COMMENT 'Invariante: cada mensagem da origem é processada uma vez',
    KEY ix_iap_events_transaction (transaction_id)
        COMMENT 'Linha do tempo de uma compra; atende a FK',
    CONSTRAINT fk_iap_events_transaction FOREIGN KEY (transaction_id) REFERENCES iap_transactions (id)
        ON DELETE SET NULL ON UPDATE RESTRICT,
    CONSTRAINT ck_iap_events_source CHECK (source IN ('verify','rtdn','reconcile'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Trilha de eventos de compra, inclusive notificações RTDN (domínio: monetização)';

CREATE TABLE remote_config_versions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da versão de configuração',
    environment VARCHAR(16) NOT NULL
        COMMENT 'Ambiente: local, staging ou production',
    version_number INT UNSIGNED NOT NULL
        COMMENT 'Número sequencial da versão dentro do ambiente, visível ao app',
    status VARCHAR(16) NOT NULL
        COMMENT 'Estado: draft (rascunho), published (vigente quando for a maior compatível), retired (retirada por rollback)',
    min_client_version VARCHAR(32) NOT NULL DEFAULT '0.0.0'
        COMMENT 'Menor versão do app que pode receber esta configuração (semver)',
    max_client_version VARCHAR(32) NULL
        COMMENT 'Maior versão do app compatível; NULL sem limite superior',
    payload JSON NOT NULL
        COMMENT 'Parâmetros públicos tipados (flags, limites); nunca contém segredos',
    checksum CHAR(64) NOT NULL
        COMMENT 'SHA-256 do payload canônico; usado como ETag',
    changelog VARCHAR(500) NOT NULL
        COMMENT 'Descrição humana da mudança, obrigatória para publicar',
    created_by VARCHAR(64) NOT NULL
        COMMENT 'Quem criou a versão (usuário admin ou cli)',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação',
    published_at DATETIME(6) NULL
        COMMENT 'Instante UTC da publicação; NULL em rascunho',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_remote_config_env_version (environment, version_number)
        COMMENT 'Número de versão único por ambiente',
    KEY ix_remote_config_env_status (environment, status, version_number)
        COMMENT 'Busca da maior versão publicada compatível em GET /config',
    CONSTRAINT ck_remote_config_status CHECK (status IN ('draft','published','retired')),
    CONSTRAINT ck_remote_config_env CHECK (environment IN ('local','staging','production'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Versões de Remote Config com histórico e rollback (domínio: operação)';

CREATE TABLE game_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do evento',
    event_id VARCHAR(64) NOT NULL
        COMMENT 'Identificador idempotente gerado pelo app; reenvio do mesmo evento é ignorado',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador pseudônimo que gerou o evento (FK players.id)',
    event_name VARCHAR(40) NOT NULL
        COMMENT 'Nome do evento da lista permitida (first_open, session_start, crop_harvested...)',
    occurred_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC do evento segundo o aparelho (limitado a +24h do servidor)',
    received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de recebimento pelo servidor',
    app_version VARCHAR(32) NULL
        COMMENT 'Versão do app que enviou; NULL se ausente',
    properties JSON NULL
        COMMENT 'Propriedades permitidas do evento (até 2 KB), sem e-mail, tokens ou dados pessoais; NULL se nenhuma',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_game_events_event_id (event_id)
        COMMENT 'Invariante: cada event_id é gravado uma vez',
    KEY ix_game_events_player_time (player_id, occurred_at, id)
        COMMENT 'Linha do tempo do jogador e retenção por coorte; atende a FK',
    KEY ix_game_events_name_time (event_name, occurred_at)
        COMMENT 'Agregados diários por evento para o dashboard',
    CONSTRAINT fk_game_events_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Telemetria client-side recebida em lote (domínio: analytics)';

CREATE TABLE reward_grants (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do benefício',
    public_id BINARY(16) NOT NULL
        COMMENT 'Identificador público do benefício usado em POST /rewards/{id}/claim',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador elegível (FK players.id)',
    rule_key VARCHAR(64) NOT NULL
        COMMENT 'Regra ou campanha que concedeu (ex.: welcome_v1, comeback_3d_v1, admin_manual)',
    occurrence_key VARCHAR(100) NOT NULL
        COMMENT 'Ocorrência da regra (ex.: once, 2026-W48); garante um benefício por ocorrência',
    currency VARCHAR(8) NULL
        COMMENT 'Moeda do benefício (cash ou gold); NULL quando o benefício é só um direito',
    amount BIGINT UNSIGNED NULL
        COMMENT 'Quantidade inteira da moeda; NULL quando currency é NULL',
    entitlement_key VARCHAR(64) NULL
        COMMENT 'Direito permanente concedido no resgate; NULL quando não houver',
    status VARCHAR(16) NOT NULL DEFAULT 'available'
        COMMENT 'Estado: available (pode resgatar), claimed (resgatado), expired, revoked',
    expires_at DATETIME(6) NULL
        COMMENT 'Instante UTC limite para resgate; NULL sem expiração',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC da concessão (registrada antes de qualquer notificação)',
    claimed_at DATETIME(6) NULL
        COMMENT 'Instante UTC do resgate; NULL se não resgatado',
    ledger_id BIGINT UNSIGNED NULL
        COMMENT 'Lançamento do resgate (FK economy_ledger.id); NULL antes do resgate ou sem moeda',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_reward_grants_public_id (public_id)
        COMMENT 'Unicidade do identificador público',
    UNIQUE KEY uq_reward_grants_occurrence (player_id, rule_key, occurrence_key)
        COMMENT 'Invariante: um benefício por regra e ocorrência para cada jogador; atende a FK player_id',
    KEY ix_reward_grants_player_status (player_id, status, expires_at)
        COMMENT 'Listagem de benefícios disponíveis em GET /rewards',
    KEY ix_reward_grants_ledger (ledger_id)
        COMMENT 'Atende a FK ledger_id e auditoria do resgate',
    CONSTRAINT fk_reward_grants_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_reward_grants_ledger FOREIGN KEY (ledger_id) REFERENCES economy_ledger (id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_reward_grants_status CHECK (status IN ('available','claimed','expired','revoked')),
    CONSTRAINT ck_reward_grants_currency CHECK (currency IS NULL OR currency IN ('cash','gold'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Benefícios concedidos a jogadores e seu resgate idempotente (domínio: recompensas)';

CREATE TABLE notification_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do evento de notificação',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador que abriu a notificação (FK players.id)',
    notification_id VARCHAR(64) NOT NULL
        COMMENT 'Identificador da notificação vindo do campo data do push (ex.: N-123)',
    campaign_id VARCHAR(64) NULL
        COMMENT 'Campanha de origem informada no push; NULL para notificações operacionais',
    event_type VARCHAR(16) NOT NULL
        COMMENT 'Tipo: opened (toque do jogador)',
    occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC do registro',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_notification_events_once (player_id, notification_id, event_type)
        COMMENT 'Invariante: abertura contada uma vez por jogador e notificação; atende a FK',
    KEY ix_notification_events_campaign (campaign_id, event_type)
        COMMENT 'Contagem de aberturas por campanha no dashboard',
    CONSTRAINT fk_notification_events_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT ck_notification_events_type CHECK (event_type IN ('opened'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Eventos de engajamento com notificações push (domínio: LiveOps)';

CREATE TABLE rate_limits (
    bucket CHAR(64) NOT NULL
        COMMENT 'SHA-256 de (regra + IP ou jogador); nunca guarda o IP em claro',
    window_start DATETIME NOT NULL
        COMMENT 'Início UTC da janela fixa de contagem',
    hits INT UNSIGNED NOT NULL DEFAULT 1
        COMMENT 'Quantidade de requisições contadas na janela',
    PRIMARY KEY (bucket, window_start)
        COMMENT 'Contador único por balde e janela',
    KEY ix_rate_limits_window (window_start)
        COMMENT 'Limpeza periódica das janelas antigas pelo cron'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Contadores de rate limit por janela fixa (domínio: segurança)';

INSERT INTO schema_migrations (version) VALUES ('001_core');
