-- TerraBela Farm backend - migration 006_apple_login
-- TBF-MVP-13b: Sign in with Apple (exigido pela App Store quando o app oferece Google/Facebook).
-- Só amplia a CHECK de provedores; nenhum dado muda. DROP CONSTRAINT funciona em MySQL 8.0.19+ e MariaDB 10.2+.

SET NAMES utf8mb4;

ALTER TABLE player_identities DROP CONSTRAINT ck_identities_provider;
ALTER TABLE player_identities
    ADD CONSTRAINT ck_identities_provider CHECK (provider IN ('guest','google','facebook','apple'));
ALTER TABLE player_identities
    MODIFY provider VARCHAR(16) NOT NULL
        COMMENT 'Provedor: guest (visitante com segredo do servidor), google, facebook ou apple';
ALTER TABLE player_sessions
    MODIFY login_provider VARCHAR(16) NOT NULL
        COMMENT 'Provedor usado para abrir a sessão: guest, google, facebook ou apple';

INSERT INTO schema_migrations (version) VALUES ('006_apple_login');
