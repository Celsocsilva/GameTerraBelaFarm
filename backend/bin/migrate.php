<?php
declare(strict_types=1);

/**
 * Aplica as migrations pendentes de database/migrations em ordem.
 * Uso: php bin/migrate.php [--status]
 * Sem acesso SSH: importe os mesmos arquivos .sql em ordem pelo phpMyAdmin.
 */
require __DIR__ . '/_cli.php';

$db = TerraBela\Core\Db::fromConfig(tbf_config());
$dir = dirname(__DIR__) . '/database/migrations';
$files = glob($dir . '/*.sql') ?: [];
sort($files);

$hasTable = $db->one("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_migrations'");
$applied = [];
if ((int) $hasTable['n'] > 0) {
    foreach ($db->all('SELECT version FROM schema_migrations') as $r) {
        $applied[$r['version']] = true;
    }
}
$statusOnly = in_array('--status', $argv, true);
foreach ($files as $file) {
    $version = basename($file, '.sql');
    if (isset($applied[$version])) {
        echo "  ok      $version\n";
        continue;
    }
    if ($statusOnly) {
        echo "  pending $version\n";
        continue;
    }
    $sql = (string) file_get_contents($file);
    $statements = tbf_split_sql($sql);
    echo "  apply   $version (" . count($statements) . " comandos)\n";
    foreach ($statements as $st) {
        $db->pdo->exec($st);
    }
    $db->exec('UPDATE schema_migrations SET checksum = ? WHERE version = ?', [hash('sha256', $sql), $version]);
}
echo "Concluído.\n";

/** Divide o SQL em comandos por ';' no fim da linha, ignorando comentários de linha. @return list<string> */
function tbf_split_sql(string $sql): array
{
    $out = [];
    $buf = '';
    foreach (preg_split('/\R/', $sql) as $line) {
        $trim = trim($line);
        if ($buf === '' && ($trim === '' || str_starts_with($trim, '--'))) {
            continue;
        }
        $buf .= $line . "\n";
        if (str_ends_with($trim, ';')) {
            $out[] = trim($buf);
            $buf = '';
        }
    }
    if (trim($buf) !== '') {
        $out[] = trim($buf);
    }
    return $out;
}
