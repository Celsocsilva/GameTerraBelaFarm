<?php
declare(strict_types=1);

/**
 * Gera database/migrations/002_seed_remote_config.sql a partir de config/remote-config.default.json
 * (para quem importa pelo phpMyAdmin). Uso: php bin/gen-seed.php
 */
require __DIR__ . '/_cli.php';

$payload = json_decode((string) file_get_contents(dirname(__DIR__) . '/config/remote-config.default.json'), true, 64, JSON_THROW_ON_ERROR);
TerraBela\Config\RemoteConfigService::validate($payload);
$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$sum = TerraBela\Config\RemoteConfigService::checksum($payload);
$q = static fn (string $s): string => "'" . str_replace(["\\", "'"], ["\\\\", "\\'"], $s) . "'";
$rows = [];
foreach (['production', 'staging', 'local'] as $env) {
    $rows[] = sprintf("(%s, 1, 'published', '0.0.0', NULL, %s, %s, %s, 'migration', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))",
        $q($env), $q($json), $q($sum), $q('Configuração inicial do MVP (valores propostos, pendentes de aprovação do PO)'));
}
$sql = "-- TerraBela Farm backend - migration 002_seed_remote_config (gerada por bin/gen-seed.php; não editar à mão)\n"
    . "-- Publica a versão 1 do Remote Config em cada ambiente a partir de config/remote-config.default.json.\n\n"
    . "SET NAMES utf8mb4;\nSET time_zone = '+00:00';\n\n"
    . "INSERT INTO remote_config_versions (environment, version_number, status, min_client_version, max_client_version, payload, checksum, changelog, created_by, created_at, published_at) VALUES\n"
    . implode(",\n", $rows) . ";\n\n"
    . "INSERT INTO schema_migrations (version) VALUES ('002_seed_remote_config');\n";
file_put_contents(dirname(__DIR__) . '/database/migrations/002_seed_remote_config.sql', $sql);
echo "ok $sum\n";
