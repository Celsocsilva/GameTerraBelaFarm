<?php
declare(strict_types=1);

namespace TerraBela\LiveOps;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;

/**
 * Agregados diários (TBF-MVP-07) para o painel: o cron recalcula hoje e ontem (idempotente, REPLACE).
 * DAU usa jogadores com sessão/evento no dia; financeiro vem do ledger e das compras (server-side).
 */
final class MetricsService
{
    public function __construct(private Db $db, private Clock $clock)
    {
    }

    public function recompute(int $daysBack = 1): int
    {
        $n = 0;
        for ($i = $daysBack; $i >= 0; $i--) {
            $n += $this->day(gmdate('Y-m-d', $this->clock->now() - 86400 * $i));
        }
        return $n;
    }

    public function day(string $date): int
    {
        $from = $date . ' 00:00:00';
        $to = gmdate('Y-m-d', strtotime($date . ' UTC') + 86400) . ' 00:00:00';
        $q = fn (string $sql, array $p = []) => (int) ($this->db->one($sql, $p)['v'] ?? 0);
        $m = [
            ['dau', '', $q('SELECT COUNT(DISTINCT player_id) v FROM (SELECT player_id FROM game_events WHERE occurred_at >= ? AND occurred_at < ? UNION ALL SELECT player_id FROM player_sessions WHERE (created_at >= ? AND created_at < ?) OR (rotated_at >= ? AND rotated_at < ?)) x', [$from, $to, $from, $to, $from, $to])],
            ['new_players', '', $q('SELECT COUNT(*) v FROM players WHERE created_at >= ? AND created_at < ?', [$from, $to])],
            ['sessions', '', $q("SELECT COUNT(*) v FROM game_events WHERE event_name = 'session_start' AND occurred_at >= ? AND occurred_at < ?", [$from, $to])],
            ['iap_granted', '', $q('SELECT COUNT(*) v FROM iap_transactions WHERE granted_at >= ? AND granted_at < ?', [$from, $to])],
            ['iap_refunded', '', $q('SELECT COUNT(*) v FROM iap_transactions WHERE refunded_at >= ? AND refunded_at < ?', [$from, $to])],
            ['push_sent', '', $q("SELECT COUNT(*) v FROM notification_outbox WHERE status = 'sent' AND sent_at >= ? AND sent_at < ?", [$from, $to])],
            ['push_opened', '', $q('SELECT COUNT(*) v FROM notification_events WHERE occurred_at >= ? AND occurred_at < ?', [$from, $to])],
            ['rewards_claimed', '', $q('SELECT COUNT(*) v FROM reward_grants WHERE claimed_at >= ? AND claimed_at < ?', [$from, $to])],
        ];
        foreach (['cash', 'gold'] as $cur) {
            $m[] = [$cur . '_source', '', $q('SELECT COALESCE(SUM(amount),0) v FROM economy_ledger WHERE currency = ? AND amount > 0 AND created_at >= ? AND created_at < ?', [$cur, $from, $to])];
            $m[] = [$cur . '_sink', '', $q('SELECT COALESCE(-SUM(amount),0) v FROM economy_ledger WHERE currency = ? AND amount < 0 AND created_at >= ? AND created_at < ?', [$cur, $from, $to])];
        }
        foreach ($this->db->all("SELECT p.sku, COUNT(*) n FROM iap_transactions t JOIN iap_products p ON p.id = t.product_id WHERE t.granted_at >= ? AND t.granted_at < ? GROUP BY p.sku", [$from, $to]) as $r) {
            $m[] = ['iap_granted', mb_substr($r['sku'], 0, 40), (int) $r['n']];
        }
        foreach ($m as [$metric, $dim, $value]) {
            $this->db->exec(
                'REPLACE INTO daily_metrics (metric_date, metric, dimension, value, computed_at) VALUES (?, ?, ?, ?, ?)',
                [$date, $metric, $dim, $value, $this->clock->sql()]
            );
        }
        return count($m);
    }

    /** @return array<string,int> série metric => [data => valor] dos últimos N dias */
    public function series(string $metric, int $days = 30): array
    {
        $from = gmdate('Y-m-d', $this->clock->now() - 86400 * ($days - 1));
        $out = [];
        for ($i = $days - 1; $i >= 0; $i--) {
            $out[gmdate('Y-m-d', $this->clock->now() - 86400 * $i)] = 0;
        }
        foreach ($this->db->all("SELECT metric_date, value FROM daily_metrics WHERE metric = ? AND dimension = '' AND metric_date >= ?", [$metric, $from]) as $r) {
            $out[$r['metric_date']] = (int) $r['value'];
        }
        return $out;
    }

    /** Retenção D1/D7/D30 por coorte de criação: % de jogadores com evento/sessão no dia N após criar a conta. @return list<array<string,mixed>> */
    public function retention(int $cohortDays = 14): array
    {
        $rows = [];
        for ($i = $cohortDays; $i >= 1; $i--) {
            $d = gmdate('Y-m-d', $this->clock->now() - 86400 * $i);
            $size = (int) $this->db->one('SELECT COUNT(*) v FROM players WHERE created_at >= ? AND created_at < ?', [$d . ' 00:00:00', gmdate('Y-m-d', strtotime($d . ' UTC') + 86400) . ' 00:00:00'])['v'];
            $row = ['cohort' => $d, 'size' => $size];
            foreach ([1, 7, 30] as $n) {
                $day = strtotime($d . ' UTC') + 86400 * $n;
                if ($day + 86400 > $this->clock->now()) {
                    $row["d$n"] = null;
                    continue;
                }
                $back = (int) $this->db->one(
                    'SELECT COUNT(DISTINCT p.id) v FROM players p WHERE p.created_at >= ? AND p.created_at < ?
                       AND (EXISTS (SELECT 1 FROM game_events e WHERE e.player_id = p.id AND e.occurred_at >= ? AND e.occurred_at < ?)
                         OR EXISTS (SELECT 1 FROM player_sessions s WHERE s.player_id = p.id AND ((s.created_at >= ? AND s.created_at < ?) OR (s.rotated_at >= ? AND s.rotated_at < ?))))',
                    [$d . ' 00:00:00', gmdate('Y-m-d', strtotime($d . ' UTC') + 86400) . ' 00:00:00',
                     gmdate('Y-m-d H:i:s', $day), gmdate('Y-m-d H:i:s', $day + 86400), gmdate('Y-m-d H:i:s', $day), gmdate('Y-m-d H:i:s', $day + 86400), gmdate('Y-m-d H:i:s', $day), gmdate('Y-m-d H:i:s', $day + 86400)]
                )['v'];
                $row["d$n"] = $size === 0 ? null : round(100 * $back / $size, 1);
            }
            $rows[] = $row;
        }
        return $rows;
    }
}
