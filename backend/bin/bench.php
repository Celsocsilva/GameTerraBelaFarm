<?php
declare(strict_types=1);

/**
 * Benchmark das consultas críticas (TBF-MVP-12) com volume simulado. SÓ em banco de teste: o banco é populado.
 *   TBF_ENV_FILE=/caminho/test.env php bin/bench.php [jogadores=20000] [saida.md]
 * Para cada consulta: plano (EXPLAIN: tipo de acesso, índice, linhas estimadas) e tempo p50/p95 de 30 execuções.
 * Falha (código 1) se alguma consulta crítica fizer varredura completa (type=ALL) numa tabela grande.
 */
require __DIR__ . '/_cli.php';

use TerraBela\Core\Db;

$config = tbf_config();
if ($config->str('APP_ENV', '') !== 'local' || !str_contains($config->str('DB_NAME'), 'test')) {
    fwrite(STDERR, "Recusado: só roda com APP_ENV=local e DB_NAME contendo 'test'.\n");
    exit(2);
}
$n = max(1000, (int) ($argv[1] ?? 20000));
$out = $argv[2] ?? null;
$db = Db::fromConfig($config);
$pdo = $db->pdo;
$pdo->exec('SET SESSION cte_max_recursion_depth = 10000000');
$t0 = microtime(true);

// ---------- volume ----------
$pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
foreach (['notification_outbox', 'notification_events', 'reward_grants', 'game_events', 'economy_ledger', 'wallets', 'player_consents', 'player_devices', 'player_sessions', 'player_identities', 'player_saves', 'players'] as $t) {
    $pdo->exec("DELETE FROM $t");
}
$pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
$seq = "WITH RECURSIVE s(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM s WHERE i < $n)";
$pdo->exec("INSERT INTO players (id, public_id, status, created_at, last_seen_at, locale)
            $seq SELECT i, UNHEX(REPLACE(UUID(), '-', '')), 'active', UTC_TIMESTAMP(6) - INTERVAL (i % 120) DAY - INTERVAL (i % 86400) SECOND,
                   UTC_TIMESTAMP(6) - INTERVAL (i % 40) DAY, ELT(1 + i % 3, 'pt_BR', 'es', 'en') FROM s");
$pdo->exec("INSERT INTO wallets (player_id, cash_balance, gold_balance, updated_at) $seq SELECT i, i % 9000, i % 50, UTC_TIMESTAMP(6) FROM s");
$pdo->exec("INSERT INTO player_identities (player_id, provider, subject, secret_hash, created_at) $seq SELECT i, 'guest', CONCAT('g-', i), SHA2(i, 256), UTC_TIMESTAMP(6) FROM s");
$pdo->exec("INSERT INTO player_sessions (public_id, player_id, access_hash, access_expires_at, refresh_hash, refresh_expires_at, login_provider, created_at, rotated_at)
            $seq SELECT UNHEX(REPLACE(UUID(), '-', '')), i, SHA2(CONCAT('a', i), 256), UTC_TIMESTAMP(6) + INTERVAL 1 HOUR, SHA2(CONCAT('r', i), 256), UTC_TIMESTAMP(6) + INTERVAL 30 DAY,
                   'guest', UTC_TIMESTAMP(6) - INTERVAL (i % 60) DAY, UTC_TIMESTAMP(6) - INTERVAL (i % 30) DAY FROM s");
$pdo->exec("INSERT INTO player_devices (public_id, player_id, installation_id, platform, fcm_token, fcm_token_hash, app_version, locale, created_at, last_seen_at)
            $seq SELECT UNHEX(REPLACE(UUID(), '-', '')), i, CONCAT('inst-', i), 'android', CONCAT('tok-', i), SHA2(CONCAT('tok-', i), 256), '0.3.0', ELT(1 + i % 3, 'pt_BR', 'es', 'en'), UTC_TIMESTAMP(6), UTC_TIMESTAMP(6) FROM s");
$pdo->exec("INSERT INTO player_consents (player_id, consent_type, granted, source, recorded_at) $seq SELECT i, 'notify_promotional', i % 2, 'app_settings', UTC_TIMESTAMP(6) FROM s WHERE i % 3 = 0");
$ev = $n * 10;
$pdo->exec("INSERT INTO game_events (event_id, player_id, event_name, occurred_at, received_at, app_version)
            WITH RECURSIVE s(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM s WHERE i < $ev)
            SELECT CONCAT('ev-', i), 1 + i % $n, ELT(1 + i % 4, 'session_start', 'harvest', 'sale', 'shop_open'), UTC_TIMESTAMP(6) - INTERVAL (i % 2592000) SECOND, UTC_TIMESTAMP(6), '0.3.0' FROM s");
$led = $n * 8;
$pdo->exec("INSERT INTO economy_ledger (player_id, currency, amount, balance_after, source, reason, idempotency_key, created_at)
            WITH RECURSIVE s(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM s WHERE i < $led)
            SELECT 1 + i % $n, IF(i % 10 = 0, 'gold', 'cash'), IF(i % 3 = 0, -5, 25), 100, IF(i % 3 = 0, 'client', ELT(1 + i % 3, 'client', 'reward', 'iap')), 'sale_collected', CONCAT('k-', i), UTC_TIMESTAMP(6) - INTERVAL (i % 2592000) SECOND FROM s");
$pdo->query('ANALYZE TABLE players, wallets, player_identities, player_sessions, player_devices, player_consents, game_events, economy_ledger')->fetchAll();
$seeded = round(microtime(true) - $t0, 1);

// ---------- consultas ----------
$pid = intdiv($n, 2);
$day0 = gmdate('Y-m-d 00:00:00');
$day1 = gmdate('Y-m-d 00:00:00', time() + 86400);
$latest = "SELECT c.granted FROM player_consents c WHERE c.player_id = d.player_id AND c.consent_type = 'notify_promotional' ORDER BY c.recorded_at DESC, c.id DESC LIMIT 1";
$queries = [
    'Autenticar token (toda requisição)' => ["SELECT s.id, s.player_id FROM player_sessions s JOIN players p ON p.id = s.player_id WHERE s.access_hash = ? AND s.revoked_at IS NULL", [hash('sha256', 'a' . $pid)]],
    'Carteira com trava (lançamento)' => ['SELECT cash_balance, gold_balance FROM wallets WHERE player_id = ?', [$pid]],
    'Idempotência do lançamento' => ['SELECT id FROM economy_ledger WHERE player_id = ? AND idempotency_key = ?', [$pid, 'k-1']],
    'Teto diário de cash do cliente' => ["SELECT COALESCE(SUM(amount),0) t FROM economy_ledger WHERE player_id = ? AND currency = 'cash' AND source = 'client' AND created_at >= ? AND amount > 0", [$pid, $day0]],
    'Histórico do ledger (50)' => ['SELECT * FROM economy_ledger WHERE player_id = ? ORDER BY id DESC LIMIT 50', [$pid]],
    'Remote Config vigente' => ["SELECT version_number FROM remote_config_versions WHERE environment = 'local' AND status = 'published' ORDER BY version_number DESC LIMIT 20", []],
    'Login visitante' => ["SELECT i.player_id FROM player_identities i WHERE i.provider = 'guest' AND i.subject = ?", ['g-' . $pid]],
    'Painel: DAU do dia (eventos)' => ['SELECT COUNT(DISTINCT player_id) v FROM game_events WHERE occurred_at >= ? AND occurred_at < ?', [$day0, $day1]],
    'Painel: DAU do dia (sessões)' => ['SELECT COUNT(DISTINCT player_id) v FROM player_sessions WHERE (created_at >= ? AND created_at < ?) OR (rotated_at >= ? AND rotated_at < ?)', [$day0, $day1, $day0, $day1]],
    'Painel: novos jogadores do dia' => ['SELECT COUNT(*) v FROM players WHERE created_at >= ? AND created_at < ?', [$day0, $day1]],
    'Painel: ouro creditado no dia' => ["SELECT COALESCE(SUM(amount),0) v FROM economy_ledger WHERE currency = 'gold' AND amount > 0 AND created_at >= ? AND created_at < ?", [$day0, $day1]],
    'Painel: ativos 7 dias' => ['SELECT COUNT(*) n FROM players WHERE last_seen_at >= ?', [gmdate('Y-m-d H:i:s', time() - 7 * 86400)]],
    'Push: público promocional (pt_BR)' => ["SELECT COUNT(*) n FROM player_devices d JOIN players p ON p.id = d.player_id WHERE d.revoked_at IS NULL AND d.fcm_token IS NOT NULL AND p.status = 'active' AND COALESCE(($latest), 0) = 1 AND d.locale = 'pt_BR'", []],
    'Regra: inativos há 7+ dias sem benefício' => ["SELECT p.id FROM players p WHERE p.status = 'active' AND p.last_seen_at IS NOT NULL AND p.last_seen_at <= ? AND NOT EXISTS (SELECT 1 FROM reward_grants g WHERE g.player_id = p.id AND g.rule_key = 'x' AND g.occurrence_key = 'once') ORDER BY p.id LIMIT 1000", [gmdate('Y-m-d H:i:s', time() - 7 * 86400)]],
    'Backoffice: lista de jogadores' => ['SELECT p.id FROM players p LEFT JOIN wallets w ON w.player_id = p.id ORDER BY p.id DESC LIMIT 51', []],
    'Backoffice: ledger 24 h por origem' => ['SELECT currency, source, COUNT(*) n FROM economy_ledger WHERE created_at >= ? GROUP BY currency, source', [gmdate('Y-m-d H:i:s', time() - 86400)]],
];
$large = ['players', 'player_sessions', 'player_devices', 'game_events', 'economy_ledger', 'wallets', 'player_identities', 'p', 's', 'd', 'w', 'i', 'c', 'g'];
$rows = [];
$bad = 0;
foreach ($queries as $name => [$sql, $params]) {
    $plan = $db->all('EXPLAIN ' . $sql, $params);
    $scan = [];
    foreach ($plan as $p) {
        if (($p['type'] ?? '') === 'ALL' && in_array((string) $p['table'], $large, true) && (int) $p['rows'] > 1000) {
            $scan[] = $p['table'];
        }
    }
    $times = [];
    $st = $pdo->prepare($sql);
    for ($k = 0; $k < 30; $k++) {
        $s = hrtime(true);
        $st->execute($params);
        $st->fetchAll();
        $times[] = (hrtime(true) - $s) / 1e6;
    }
    sort($times);
    $main = $plan[0];
    $rows[] = [
        'name' => $name,
        'access' => implode(' → ', array_map(static fn ($p) => $p['table'] . ':' . $p['type'] . ($p['key'] ? '(' . $p['key'] . ')' : ''), $plan)),
        'p50' => $times[14], 'p95' => $times[28], 'scan' => $scan,
    ];
    if ($scan) {
        $bad++;
    }
}

$md = "# Benchmark das consultas críticas\n\nVolume: $n jogadores, " . ($n * 10) . " eventos, " . ($n * 8) . " lançamentos no ledger, $n sessões e $n aparelhos (carga em {$seeded} s). "
    . 'Banco: ' . $db->one('SELECT VERSION() v')['v'] . '. Data: ' . gmdate('Y-m-d H:i') . " UTC. 30 execuções por consulta.\n\n"
    . "| Consulta | Plano (tabela:tipo(índice)) | p50 ms | p95 ms | Varredura completa |\n|---|---|---:|---:|---|\n";
foreach ($rows as $r) {
    $md .= sprintf("| %s | %s | %.2f | %.2f | %s |\n", $r['name'], str_replace('|', '/', $r['access']), $r['p50'], $r['p95'], $r['scan'] ? 'SIM: ' . implode(', ', $r['scan']) : 'não');
}
$md .= "\nConsultas com varredura completa em tabela grande: $bad.\n";
echo $md;
if ($out !== null) {
    file_put_contents($out, $md);
}
exit($bad === 0 ? 0 : 1);
