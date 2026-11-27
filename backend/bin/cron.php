<?php
declare(strict_types=1);

/**
 * Manutenção periódica. Agende no painel da hospedagem (Cron Jobs), por exemplo a cada 15 minutos:
 *   php /home/USUARIO/terrabelafarm_app/bin/cron.php >/dev/null 2>&1
 * Tarefas: finalizar compras pendentes na Google, rodar regras de benefício ativas (no máximo 1x/hora cada),
 * enviar campanhas push agendadas (fila com nova tentativa), recalcular métricas de hoje/ontem,
 * expirar benefícios, limpar sessões/rate limit/sessões do backoffice, podar idempotência antiga
 * e remover dados pessoais de contas com exclusão vencida.
 */
require __DIR__ . '/_cli.php';

$app = tbf_app();
$db = $app->db;
$clock = $app->clock;
$lock = fopen(sys_get_temp_dir() . '/tbf-cron-' . md5(__DIR__) . '.lock', 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    echo "Outro cron em execução.\n";
    exit(0);
}

$report = [];
$report['iap_finalize'] = $app->iap->reconcilePending();
foreach (['rules' => fn () => $app->rules->runActive(), 'push' => fn () => $app->campaigns->runDue(500), 'metrics_rows' => fn () => $app->metrics->recompute(1)] as $k => $job) {
    try {
        $report[$k] = $job();
    } catch (Throwable $e) {
        $report[$k] = 'erro: ' . get_class($e);
        $app->log->error('cron_job', ['job' => $k, 'type' => get_class($e), 'msg' => $e->getMessage()]);
    }
}
$report['admin_sessions_deleted'] = $db->exec('DELETE FROM admin_sessions WHERE expires_at < ? LIMIT 5000', [$clock->sql(-7 * 86400)]);
$report['rewards_expired'] = $db->exec("UPDATE reward_grants SET status = 'expired' WHERE status = 'available' AND expires_at IS NOT NULL AND expires_at < ?", [$clock->sql()]);
$report['sessions_deleted'] = $db->exec('DELETE FROM player_sessions WHERE refresh_expires_at < ? LIMIT 5000', [$clock->sql(-7 * 86400)]);
$report['rate_limits_deleted'] = $db->exec('DELETE FROM rate_limits WHERE window_start < ? LIMIT 20000', [gmdate('Y-m-d H:i:s', $clock->now() - 3600)]);
$report['sync_ops_deleted'] = $db->exec('DELETE FROM sync_operations WHERE created_at < ? LIMIT 20000', [$clock->sql(-30 * 86400)]);

// Exclusão de conta: após a carência, apaga dados pessoais e de jogo; ledger e compras ficam (auditoria fiscal), sem vínculo de identidade.
$grace = $app->config->int('DELETION_GRACE_DAYS', 30);
$due = $db->all("SELECT id FROM players WHERE status = 'deletion_requested' AND deletion_requested_at < ? LIMIT 200", [$clock->sql(-$grace * 86400)]);
foreach ($due as $p) {
    $db->tx(function (TerraBela\Core\Db $db) use ($p, $clock) {
        $id = (int) $p['id'];
        foreach (['player_identities', 'player_sessions', 'player_devices', 'player_consents', 'player_saves', 'player_save_versions', 'sync_operations', 'game_events', 'notification_events'] as $t) {
            $db->exec("DELETE FROM $t WHERE player_id = ?", [$id]);
        }
        $db->exec("UPDATE players SET status = 'deleted', deleted_at = ?, locale = NULL, last_seen_at = NULL WHERE id = ?", [$clock->sql(), $id]);
    });
}
$report['accounts_purged'] = count($due);

$app->log->info('cron', $report);
echo json_encode($report) . "\n";
