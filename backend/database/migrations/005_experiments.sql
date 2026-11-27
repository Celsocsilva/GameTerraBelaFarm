-- TerraBela Farm backend - migration 005_experiments
-- TBF-MVP-13a: testes A/B sobre o Remote Config. Cada experimento divide os jogadores de forma
-- determinística (hash do id público + chave + sal) e cada variante sobrescreve só seções
-- de jogo (features, routes, tuning); limites de economia ficam sempre no servidor.
-- Regra do PO: COMMENT em toda tabela, coluna, índice e constraint.

SET NAMES utf8mb4;

CREATE TABLE experiments (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno do experimento',
    experiment_key VARCHAR(48) NOT NULL
        COMMENT 'Chave estável usada pelo app (ex.: shop_layout_v2)',
    name VARCHAR(120) NOT NULL
        COMMENT 'Nome humano mostrado no backoffice',
    hypothesis VARCHAR(500) NULL
        COMMENT 'Hipótese e métrica de sucesso escritas pelo operador',
    status VARCHAR(16) NOT NULL DEFAULT 'draft'
        COMMENT 'Estado: draft (editável), running (atribuindo), stopped (encerrado, todos voltam ao padrão)',
    traffic_percent TINYINT UNSIGNED NOT NULL DEFAULT 100
        COMMENT 'Percentual dos jogadores que entram no experimento (0 a 100); o resto fica no padrão',
    variants JSON NOT NULL
        COMMENT 'Lista de variantes [{"key","weight","overrides"}]; overrides só em features, routes e tuning',
    salt CHAR(16) NOT NULL
        COMMENT 'Sal aleatório da divisão; muda a distribuição sem depender da chave',
    goal_event VARCHAR(40) NULL
        COMMENT 'Evento de telemetria contado como conversão nos resultados; NULL sem meta própria',
    min_client_version VARCHAR(32) NOT NULL DEFAULT '0.0.0'
        COMMENT 'Versão mínima do app que participa (versões antigas ficam no padrão)',
    winner_variant VARCHAR(32) NULL
        COMMENT 'Variante escolhida ao encerrar; NULL sem decisão (a aplicação é feita publicando o Remote Config)',
    created_by INT UNSIGNED NULL
        COMMENT 'Operador que criou (FK admin_users.id); NULL se pelo sistema',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        COMMENT 'Instante UTC de criação',
    started_at DATETIME(6) NULL
        COMMENT 'Instante UTC em que começou a atribuir; NULL em rascunho',
    stopped_at DATETIME(6) NULL
        COMMENT 'Instante UTC do encerramento; NULL enquanto não encerrado',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_experiments_key (experiment_key)
        COMMENT 'Chave única por experimento',
    KEY ix_experiments_status (status)
        COMMENT 'Seleção dos experimentos em andamento a cada requisição do app',
    KEY ix_experiments_created_by (created_by)
        COMMENT 'Atende a FK created_by',
    CONSTRAINT fk_experiments_created_by FOREIGN KEY (created_by) REFERENCES admin_users (id)
        ON DELETE SET NULL ON UPDATE RESTRICT,
    CONSTRAINT ck_experiments_status CHECK (status IN ('draft','running','stopped')),
    CONSTRAINT ck_experiments_traffic CHECK (traffic_percent <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Testes A/B sobre o Remote Config (domínio: LiveOps)';

CREATE TABLE experiment_assignments (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT
        COMMENT 'Identificador interno da atribuição',
    experiment_id INT UNSIGNED NOT NULL
        COMMENT 'Experimento (FK experiments.id)',
    player_id BIGINT UNSIGNED NOT NULL
        COMMENT 'Jogador atribuído (FK players.id)',
    variant_key VARCHAR(32) NOT NULL
        COMMENT 'Variante recebida; fixa para o jogador mesmo se os pesos mudarem',
    first_exposed_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC da primeira entrega da variante ao app (início da janela de resultado)',
    last_exposed_at DATETIME(6) NOT NULL
        COMMENT 'Instante UTC da entrega mais recente',
    PRIMARY KEY (id)
        COMMENT 'Chave interna',
    UNIQUE KEY uq_experiment_assignments_player (experiment_id, player_id)
        COMMENT 'Uma variante por jogador e experimento',
    KEY ix_experiment_assignments_variant (experiment_id, variant_key, first_exposed_at)
        COMMENT 'Resultados por variante e janela de exposição',
    KEY ix_experiment_assignments_player (player_id)
        COMMENT 'Atende a FK player_id e a exportação/exclusão do jogador',
    CONSTRAINT fk_experiment_assignments_experiment FOREIGN KEY (experiment_id) REFERENCES experiments (id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_experiment_assignments_player FOREIGN KEY (player_id) REFERENCES players (id)
        ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Variante de cada jogador em cada experimento A/B (domínio: LiveOps)';

INSERT INTO schema_migrations (version) VALUES ('005_experiments');
