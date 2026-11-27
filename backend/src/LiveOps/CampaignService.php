<?php
declare(strict_types=1);

namespace TerraBela\LiveOps;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;

/**
 * Campanhas push (TBF-MVP-09): segmento, agenda, fila durável (notification_outbox), nova tentativa com
 * backoff e jitter, opt-out e limite semanal de promocionais. Aceite do FCM não prova entrega.
 */
final class CampaignService
{
    public const ROUTES = ['farm', 'shop', 'tomatoes', 'corn', 'pumpkins', 'helpers', 'rewards', 'events'];
    public const MAX_ATTEMPTS = 5;

    public function __construct(
        private Db $db,
        private Clock $clock,
        private FcmClient $fcm,
        private int $promoWeeklyCap = 3,
    ) {
    }

    /** @param array<string,mixed> $in @return int id */
    public function create(array $in, ?int $adminId): int
    {
        $errors = [];
        $name = trim((string) ($in['name'] ?? ''));
        $title = trim((string) ($in['title'] ?? ''));
        $body = trim((string) ($in['body'] ?? ''));
        $category = (string) ($in['category'] ?? '');
        $route = (string) ($in['route'] ?? 'farm');
        $locale = trim((string) ($in['locale'] ?? '')) ?: null;
        $platform = trim((string) ($in['platform'] ?? '')) ?: null;
        $inactive = ($in['inactive_days_min'] ?? '') === '' ? null : (int) $in['inactive_days_min'];
        if ($name === '' || mb_strlen($name) > 120) {
            $errors[] = 'nome (1 a 120 caracteres)';
        }
        if ($title === '' || mb_strlen($title) > 65) {
            $errors[] = 'título (1 a 65 caracteres)';
        }
        if ($body === '' || mb_strlen($body) > 240) {
            $errors[] = 'texto (1 a 240 caracteres)';
        }
        if (!in_array($category, ['operational', 'promotional'], true)) {
            $errors[] = 'categoria';
        }
        if (!in_array($route, self::ROUTES, true)) {
            $errors[] = 'rota';
        }
        if ($locale !== null && !preg_match('/^[a-z]{2}(_[A-Z]{2})?$/', $locale)) {
            $errors[] = 'idioma (ex.: pt_BR, es, en)';
        }
        if ($platform !== null && !in_array($platform, ['android', 'ios'], true)) {
            $errors[] = 'plataforma';
        }
        if ($inactive !== null && ($inactive < 1 || $inactive > 365)) {
            $errors[] = 'dias de inatividade (1 a 365)';
        }
        if ($errors) {
            throw new \InvalidArgumentException('Campos inválidos: ' . implode(', ', $errors));
        }
        return $this->db->insert(
            'INSERT INTO notification_campaigns (public_id, name, category, title, body, route, locale, platform, inactive_days_min, status, created_by, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, \'draft\', ?, ?)',
            ['C-' . substr(bin2hex(random_bytes(5)), 0, 10), $name, $category, $title, $body, $route, $locale, $platform, $inactive, $adminId, $this->clock->sql()]
        );
    }

    /** SQL do público: instalações ativas com token, respeitando preferências e segmento. @return array{0:string,1:list<mixed>} */
    private function audienceSql(array $c): array
    {
        $prefType = $c['category'] === 'promotional' ? 'notify_promotional' : 'notify_operational';
        // Promocional exige opt-in explícito (último registro = 1); operacional vale até o opt-out (último registro = 0).
        $prefCond = $c['category'] === 'promotional'
            ? "COALESCE(($this->latestConsent), 0) = 1"
            : "COALESCE(($this->latestConsent), 1) = 1";
        $sql = "SELECT d.id AS device_id, d.player_id FROM player_devices d JOIN players p ON p.id = d.player_id
                 WHERE d.revoked_at IS NULL AND d.fcm_token IS NOT NULL AND p.status = 'active'
                   AND $prefCond
                   AND COALESCE((SELECT c2.granted FROM player_consents c2 WHERE c2.player_id = d.player_id AND c2.consent_type = 'os_notification_permission' ORDER BY c2.recorded_at DESC, c2.id DESC LIMIT 1), 1) = 1";
        $params = [$prefType];
        if ($c['locale'] !== null) {
            $sql .= ' AND d.locale = ?';
            $params[] = $c['locale'];
        }
        if ($c['platform'] !== null) {
            $sql .= ' AND d.platform = ?';
            $params[] = $c['platform'];
        }
        if ($c['inactive_days_min'] !== null) {
            $sql .= ' AND (p.last_seen_at IS NULL OR p.last_seen_at < ?)';
            $params[] = $this->clock->sql(-86400 * (int) $c['inactive_days_min']);
        }
        return [$sql, $params];
    }

    private string $latestConsent = 'SELECT c.granted FROM player_consents c WHERE c.player_id = d.player_id AND c.consent_type = ? ORDER BY c.recorded_at DESC, c.id DESC LIMIT 1';

    public function estimate(int $campaignId): int
    {
        $c = $this->get($campaignId);
        [$sql, $params] = $this->audienceSql($c);
        return (int) ($this->db->one("SELECT COUNT(*) AS n FROM ($sql) a", $params)['n'] ?? 0);
    }

    /** @return array<string,mixed> */
    public function get(int $id): array
    {
        $c = $this->db->one('SELECT * FROM notification_campaigns WHERE id = ?', [$id]);
        if ($c === null) {
            throw new \InvalidArgumentException('Campanha não encontrada');
        }
        return $c;
    }

    public function schedule(int $id, string $whenUtcSql, ?string $expiresUtcSql): void
    {
        $n = $this->db->exec(
            "UPDATE notification_campaigns SET status = 'scheduled', scheduled_at = ?, expires_at = ? WHERE id = ? AND status = 'draft'",
            [$whenUtcSql, $expiresUtcSql, $id]
        );
        if ($n === 0) {
            throw new \InvalidArgumentException('Só rascunhos podem ser agendados');
        }
    }

    public function cancel(int $id): void
    {
        $this->db->tx(function (Db $db) use ($id) {
            $db->exec("UPDATE notification_campaigns SET status = 'canceled', completed_at = ? WHERE id = ? AND status IN ('draft','scheduled','sending')", [$this->clock->sql(), $id]);
            $n = $db->exec("UPDATE notification_outbox SET status = 'skipped', last_error = 'canceled' WHERE campaign_id = ? AND status = 'pending'", [$id]);
            $db->exec('UPDATE notification_campaigns SET skipped_count = skipped_count + ? WHERE id = ?', [$n, $id]);
        });
    }

    /** Envio de teste imediato para uma instalação (não conta nos números da campanha). @return array<string,mixed> */
    public function sendTest(int $campaignId, string $devicePublicId): array
    {
        $c = $this->get($campaignId);
        $bin = Ids::uuidToBin($devicePublicId);
        $d = $bin === null ? null : $this->db->one('SELECT fcm_token FROM player_devices WHERE public_id = ? AND revoked_at IS NULL AND fcm_token IS NOT NULL', [$bin]);
        if ($d === null) {
            throw new \InvalidArgumentException('Instalação sem token FCM ativo');
        }
        if (!$this->fcm->configured()) {
            throw new \InvalidArgumentException('FCM não configurado no servidor (FCM_SERVICE_ACCOUNT_FILE)');
        }
        return $this->fcm->send($d['fcm_token'], '[TESTE] ' . $c['title'], $c['body'], $this->data($c, 'TEST-' . bin2hex(random_bytes(4))));
    }

    /** @return array<string,string> */
    private function data(array $c, string $notificationId): array
    {
        return ['schema_version' => '1', 'notification_id' => $notificationId, 'campaign_id' => $c['public_id'], 'route' => $c['route']];
    }

    /** Cron: inicia campanhas vencidas e processa a fila. @return array<string,int> */
    public function runDue(int $batch = 200): array
    {
        $report = ['campaigns_started' => 0, 'sent' => 0, 'failed' => 0, 'skipped' => 0, 'retry' => 0];
        if (!$this->fcm->configured()) {
            return $report + ['fcm_configured' => 0];
        }
        $now = $this->clock->sql();
        foreach ($this->db->all("SELECT * FROM notification_campaigns WHERE status = 'scheduled' AND scheduled_at <= ? ORDER BY scheduled_at LIMIT 5", [$now]) as $c) {
            [$sql, $params] = $this->audienceSql($c);
            $this->db->tx(function (Db $db) use ($c, $sql, $params, $now) {
                $db->exec(
                    "INSERT IGNORE INTO notification_outbox (campaign_id, device_id, player_id, status, scheduled_at, created_at)
                     SELECT ?, a.device_id, a.player_id, 'pending', ?, ? FROM ($sql) a",
                    array_merge([$c['id'], $now, $now], $params)
                );
                $count = (int) $db->one('SELECT COUNT(*) AS n FROM notification_outbox WHERE campaign_id = ?', [$c['id']])['n'];
                $db->exec("UPDATE notification_campaigns SET status = 'sending', started_at = ?, audience_count = ? WHERE id = ?", [$now, $count, $c['id']]);
            });
            $report['campaigns_started']++;
        }

        $rows = $this->db->all(
            "SELECT o.id, o.campaign_id, o.player_id, o.attempts, d.fcm_token, c.public_id, c.title, c.body, c.route, c.category, c.expires_at, c.status AS campaign_status
               FROM notification_outbox o
               JOIN notification_campaigns c ON c.id = o.campaign_id
               JOIN player_devices d ON d.id = o.device_id
              WHERE o.status = 'pending' AND o.scheduled_at <= ?
              ORDER BY o.scheduled_at, o.id LIMIT " . (int) $batch,
            [$now]
        );
        foreach ($rows as $r) {
            $skip = null;
            if ($r['campaign_status'] !== 'sending') {
                $skip = 'campaign_' . $r['campaign_status'];
            } elseif ($r['expires_at'] !== null && $r['expires_at'] < $now) {
                $skip = 'expired';
            } elseif ($r['fcm_token'] === null) {
                $skip = 'no_token';
            } elseif ($r['category'] === 'promotional' && $this->promoCountWeek((int) $r['player_id']) >= $this->promoWeeklyCap) {
                $skip = 'weekly_cap';
            }
            if ($skip !== null) {
                $this->finish($r, 'skipped', $skip, null);
                $report['skipped']++;
                continue;
            }
            $res = $this->fcm->send($r['fcm_token'], $r['title'], $r['body'], $this->data($r, 'N-' . $r['id']));
            if ($res['result'] === 'sent') {
                $this->finish($r, 'sent', null, $res['message_id']);
                $report['sent']++;
            } elseif ($res['result'] === 'invalid_token') {
                $this->db->exec('UPDATE player_devices d JOIN notification_outbox o ON o.device_id = d.id SET d.fcm_token = NULL, d.fcm_token_hash = NULL WHERE o.id = ?', [$r['id']]);
                $this->finish($r, 'failed', $res['error'], null);
                $report['failed']++;
            } elseif ($res['result'] === 'retry' && (int) $r['attempts'] + 1 < self::MAX_ATTEMPTS) {
                $delay = (int) (60 * (2 ** (int) $r['attempts'])) + random_int(0, 30);
                $this->db->exec('UPDATE notification_outbox SET attempts = attempts + 1, scheduled_at = ?, last_error = ? WHERE id = ?', [$this->clock->sql($delay), $res['error'], $r['id']]);
                $report['retry']++;
            } else {
                $this->finish($r, 'failed', $res['error'], null);
                $report['failed']++;
            }
        }
        // Campanhas sem pendências terminam.
        $this->db->exec(
            "UPDATE notification_campaigns c SET status = 'completed', completed_at = ?
              WHERE status = 'sending' AND NOT EXISTS (SELECT 1 FROM notification_outbox o WHERE o.campaign_id = c.id AND o.status = 'pending')",
            [$now]
        );
        return $report;
    }

    private function promoCountWeek(int $playerId): int
    {
        return (int) $this->db->one(
            "SELECT COUNT(*) AS n FROM notification_outbox o JOIN notification_campaigns c ON c.id = o.campaign_id
              WHERE o.player_id = ? AND o.status = 'sent' AND o.sent_at >= ? AND c.category = 'promotional'",
            [$playerId, $this->clock->sql(-7 * 86400)]
        )['n'];
    }

    private function finish(array $r, string $status, ?string $error, ?string $messageId): void
    {
        $col = ['sent' => 'sent_count', 'failed' => 'failed_count', 'skipped' => 'skipped_count'][$status];
        $this->db->tx(function (Db $db) use ($r, $status, $error, $messageId, $col) {
            $db->exec(
                'UPDATE notification_outbox SET status = ?, attempts = attempts + 1, last_error = ?, fcm_message_id = ?, sent_at = ? WHERE id = ? AND status = \'pending\'',
                [$status, $error === null ? null : mb_substr($error, 0, 160), $messageId, $status === 'sent' ? $this->clock->sql() : null, $r['id']]
            );
            $db->exec("UPDATE notification_campaigns SET $col = $col + 1 WHERE id = ?", [$r['campaign_id']]);
        });
    }
}
