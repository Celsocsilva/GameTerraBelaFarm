<?php
declare(strict_types=1);

/**
 * Instalador de USO ÚNICO para hospedagem sem SSH: aplica as migrations pendentes pela web.
 * 1. Envie este arquivo para a pasta pública com um nome aleatório (ex.: migrate_<hex>.php).
 * 2. Envie junto um arquivo migrate_token.txt com um token aleatório de 32+ caracteres.
 * 3. Chame https://.../migrate_<hex>.php?token=<token> uma vez.
 * O script apaga a si mesmo e o token ao terminar (com sucesso ou erro). Confira e apague via FTP se sobrar.
 */
header('Content-Type: text/plain; charset=utf-8');
$tokenFile = __DIR__ . '/migrate_token.txt';
$cleanup = static function () use ($tokenFile): void {
    @unlink($tokenFile);
    @unlink(__FILE__);
};
$expected = is_file($tokenFile) ? trim((string) file_get_contents($tokenFile)) : '';
if (strlen($expected) < 32 || !hash_equals($expected, (string) ($_GET['token'] ?? ''))) {
    http_response_code(404);
    exit;
}
try {
    $appDir = is_file(__DIR__ . '/app-path.php') ? (string) require __DIR__ . '/app-path.php' : dirname(__DIR__);
    require $appDir . '/src/bootstrap.php';
    $db = TerraBela\Core\Db::fromConfig(TerraBela\Core\Config::load($appDir . '/.env'));
    $files = glob($appDir . '/database/migrations/*.sql') ?: [];
    sort($files);
    $has = $db->one("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_migrations'");
    $applied = [];
    if ((int) $has['n'] > 0) {
        foreach ($db->all('SELECT version FROM schema_migrations') as $r) {
            $applied[$r['version']] = true;
        }
    }
    echo 'MySQL ' . $db->one('SELECT VERSION() AS v')['v'] . "\n";
    foreach ($files as $file) {
        $version = basename($file, '.sql');
        if (isset($applied[$version])) {
            echo "ok      $version\n";
            continue;
        }
        $sql = (string) file_get_contents($file);
        $buf = '';
        $n = 0;
        foreach (preg_split('/\R/', $sql) as $line) {
            $t = trim($line);
            if ($buf === '' && ($t === '' || str_starts_with($t, '--'))) {
                continue;
            }
            $buf .= $line . "\n";
            if (str_ends_with($t, ';')) {
                $db->pdo->exec($buf);
                $buf = '';
                $n++;
            }
        }
        $db->exec('UPDATE schema_migrations SET checksum = ? WHERE version = ?', [hash('sha256', $sql), $version]);
        echo "applied $version ($n comandos)\n";
    }
    $t = $db->one("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()");
    echo 'tabelas: ' . $t['n'] . "\nOK\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo 'ERRO: ' . get_class($e) . ': ' . $e->getMessage() . "\n";
} finally {
    $cleanup();
}
