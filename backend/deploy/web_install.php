<?php
declare(strict_types=1);

/**
 * Instalador de USO ÚNICO para hospedagem sem SSH (substitui o web_migrate.php):
 *   1) aplica as migrations pendentes;
 *   2) opcional: cria o PRIMEIRO administrador do backoffice e mostra um link de configuração de senha
 *      (uso único, 72 h). A senha nunca passa por arquivo, e-mail ou chat: o próprio admin a define no link;
 *   3) opcional: apaga jogadores de TESTE (sem save, sem ledger e sem compra) criados antes de um instante UTC.
 *
 * Envie para a pasta pública com nome aleatório (install_<hex>.php) junto com install_token.txt (32+ caracteres) e chame:
 *   https://.../install_<hex>.php?token=TOKEN[&admin_email=E&admin_name=N][&purge_before=2026-11-27T23:59:59Z]
 * O script apaga a si mesmo e o token ao terminar, com sucesso ou erro. Confira via FTP se sobrou.
 */
header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
$tokenFile = __DIR__ . '/install_token.txt';
$expected = is_file($tokenFile) ? trim((string) file_get_contents($tokenFile)) : '';
if (strlen($expected) < 32 || !hash_equals($expected, (string) ($_GET['token'] ?? ''))) {
    http_response_code(404);
    exit;
}
try {
    $appDir = is_file(__DIR__ . '/app-path.php') ? (string) require __DIR__ . '/app-path.php' : dirname(__DIR__);
    require $appDir . '/src/bootstrap.php';
    $config = TerraBela\Core\Config::load($appDir . '/.env');
    $db = TerraBela\Core\Db::fromConfig($config);
    $clock = new TerraBela\Core\Clock();

    // 1) migrations
    $files = glob($appDir . '/database/migrations/*.sql') ?: [];
    sort($files);
    $has = $db->one("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_migrations'");
    $applied = [];
    if ((int) $has['n'] > 0) {
        foreach ($db->all('SELECT version FROM schema_migrations') as $r) {
            $applied[$r['version']] = true;
        }
    }
    echo 'Banco ' . $db->one('SELECT VERSION() AS v')['v'] . "\n";
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
    echo 'tabelas: ' . $db->one('SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()')['n'] . "\n";

    // 2) primeiro administrador (só se ainda não existir nenhum)
    $email = trim((string) ($_GET['admin_email'] ?? ''));
    if ($email !== '') {
        if ((int) $db->one('SELECT COUNT(*) n FROM admin_users')['n'] > 0) {
            echo "admin: já existe usuário no backoffice; nada criado (use Usuários > Novo link de senha)\n";
        } else {
            $auth = new TerraBela\Admin\AdminAuth($db, $clock, $config->str('APP_KEY'));
            $u = $auth->createUser($email, (string) ($_GET['admin_name'] ?? 'Administrador'), 'admin');
            $base = rtrim((string) ($config->optional('APP_URL') ?? ''), '/');
            if ($base === '') {
                $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https' ? 'https' : 'http';
                $base = $scheme . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
            }
            echo "admin: criado " . strtolower($email) . " (papel admin)\n";
            echo "LINK DE CONFIGURAÇÃO (uso único, 72 h): $base/admin/setup?token={$u['token']}\n";
            $db->insert(
                'INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, details, created_at) VALUES (NULL, ?, ?, ?, ?, ?)',
                ['admin_user_create', 'admin_user', (string) $u['id'], json_encode(['email' => strtolower($email), 'role' => 'admin', 'via' => 'installer']), $clock->sql()]
            );
        }
    }

    // 3) limpeza de jogadores de teste
    $before = trim((string) ($_GET['purge_before'] ?? ''));
    if ($before !== '') {
        $ts = strtotime($before);
        if ($ts === false || $ts > time()) {
            throw new InvalidArgumentException('purge_before inválido (use ISO UTC no passado, ex.: 2026-11-27T23:59:59Z)');
        }
        $ids = array_map('intval', array_column($db->all(
            'SELECT p.id FROM players p
              WHERE p.created_at < ?
                AND NOT EXISTS (SELECT 1 FROM player_saves s WHERE s.player_id = p.id)
                AND NOT EXISTS (SELECT 1 FROM economy_ledger l WHERE l.player_id = p.id)
                AND NOT EXISTS (SELECT 1 FROM iap_transactions t WHERE t.player_id = p.id)
              LIMIT 500',
            [gmdate('Y-m-d H:i:s', $ts)]
        ), 'id'));
        foreach ($ids as $id) {
            $db->tx(function (TerraBela\Core\Db $db) use ($id) {
                foreach (['notification_outbox', 'notification_events', 'reward_grants', 'game_events', 'entitlements', 'sync_operations', 'player_save_versions',
                          'player_consents', 'player_devices', 'player_sessions', 'player_identities', 'wallets'] as $t) {
                    $db->exec("DELETE FROM $t WHERE player_id = ?", [$id]);
                }
                $db->exec('DELETE FROM players WHERE id = ?', [$id]);
            });
        }
        $left = (int) $db->one('SELECT COUNT(*) n FROM players')['n'];
        echo 'jogadores de teste apagados: ' . count($ids) . " (restam $left)\n";
    }
    echo "OK\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo 'ERRO: ' . get_class($e) . ': ' . $e->getMessage() . "\n";
} finally {
    @unlink($tokenFile);
    @unlink(__FILE__);
}
