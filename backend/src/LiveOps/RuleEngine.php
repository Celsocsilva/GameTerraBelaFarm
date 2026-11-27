<?php
declare(strict_types=1);

namespace TerraBela\LiveOps;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Rewards\RewardService;

/**
 * Motor de regras declarativo (TBF-MVP-10): condições tipadas → concessão de benefício.
 * Nunca executa PHP/SQL vindo da interface: cada tipo de condição vira um trecho SQL fixo com parâmetros.
 * Uma concessão por (jogador, regra, ocorrência); teto por execução; simulação (dry run); pausa; histórico.
 * O benefício é registrado antes de qualquer aviso e nunca depende de aceitar marketing.
 */
final class RuleEngine
{
    public const CONDITION_TYPES = [
        'account_age_days_lte' => 'Conta criada há no máximo N dias (days)',
        'account_age_days_gte' => 'Conta criada há pelo menos N dias (days)',
        'inactive_days_gte' => 'Sem abrir o jogo há pelo menos N dias (days)',
        'active_within_days' => 'Abriu o jogo nos últimos N dias (days)',
        'has_verified_purchase' => 'Tem compra verificada',
        'no_verified_purchase' => 'Nunca comprou',
        'event_count_gte' => 'Evento (event) ocorreu pelo menos N vezes (count) nos últimos D dias (within_days)',
        'locale_in' => 'Idioma do jogador numa lista (locales)',
    ];

    public function __construct(private Db $db, private Clock $clock, private RewardService $rewards)
    {
    }

    /** @param list<array<string,mixed>> $conditions */
    public static function validate(array $conditions): void
    {
        if ($conditions === [] || !array_is_list($conditions) || count($conditions) > 10) {
            throw new \InvalidArgumentException('Informe de 1 a 10 condições');
        }
        foreach ($conditions as $c) {
            $type = $c['type'] ?? null;
            if (!is_string($type) || !isset(self::CONDITION_TYPES[$type])) {
                throw new \InvalidArgumentException('Tipo de condição desconhecido: ' . json_encode($type));
            }
            $days = $c['days'] ?? null;
            if (in_array($type, ['account_age_days_lte', 'account_age_days_gte', 'inactive_days_gte', 'active_within_days'], true) && (!is_int($days) || $days < 0 || $days > 3650)) {
                throw new \InvalidArgumentException("$type exige days inteiro entre 0 e 3650");
            }
            if ($type === 'event_count_gte' && (!is_string($c['event'] ?? null) || !is_int($c['count'] ?? null) || $c['count'] < 1 || !is_int($c['within_days'] ?? null) || $c['within_days'] < 1 || $c['within_days'] > 365)) {
                throw new \InvalidArgumentException('event_count_gte exige event, count ≥ 1 e within_days 1..365');
            }
            if ($type === 'locale_in' && (!is_array($c['locales'] ?? null) || $c['locales'] === [])) {
                throw new \InvalidArgumentException('locale_in exige lista locales');
            }
        }
    }

    /** @param list<array<string,mixed>> $conditions @return array{0:string,1:list<mixed>} */
    private function where(array $conditions): array
    {
        $sql = [];
        $p = [];
        $now = $this->clock->now();
        foreach ($conditions as $c) {
            switch ($c['type']) {
                case 'account_age_days_lte':
                    $sql[] = 'p.created_at >= ?';
                    $p[] = gmdate('Y-m-d H:i:s', $now - 86400 * $c['days']);
                    break;
                case 'account_age_days_gte':
                    $sql[] = 'p.created_at <= ?';
                    $p[] = gmdate('Y-m-d H:i:s', $now - 86400 * $c['days']);
                    break;
                case 'inactive_days_gte':
                    $sql[] = 'p.last_seen_at IS NOT NULL AND p.last_seen_at <= ?';
                    $p[] = gmdate('Y-m-d H:i:s', $now - 86400 * $c['days']);
                    break;
                case 'active_within_days':
                    $sql[] = 'p.last_seen_at >= ?';
                    $p[] = gmdate('Y-m-d H:i:s', $now - 86400 * $c['days']);
                    break;
                case 'has_verified_purchase':
                    $sql[] = "EXISTS (SELECT 1 FROM iap_transactions t WHERE t.player_id = p.id AND t.state = 'granted')";
                    break;
                case 'no_verified_purchase':
                    $sql[] = "NOT EXISTS (SELECT 1 FROM iap_transactions t WHERE t.player_id = p.id AND t.state IN ('granted','refunded'))";
                    break;
                case 'event_count_gte':
                    $sql[] = '(SELECT COUNT(*) FROM game_events e WHERE e.player_id = p.id AND e.event_name = ? AND e.occurred_at >= ?) >= ?';
                    array_push($p, $c['event'], gmdate('Y-m-d H:i:s', $now - 86400 * $c['within_days']), $c['count']);
                    break;
                case 'locale_in':
                    $locales = array_values(array_map('strval', $c['locales']));
                    $sql[] = 'p.locale IN (' . implode(',', array_fill(0, count($locales), '?')) . ')';
                    array_push($p, ...$locales);
                    break;
            }
        }
        return [implode(' AND ', $sql), $p];
    }

    public function occurrenceKey(string $occurrence): string
    {
        $t = $this->clock->now();
        return match ($occurrence) {
            'once' => 'once',
            'day' => gmdate('Y-m-d', $t),
            'week' => gmdate('o-\WW', $t),
            'month' => gmdate('Y-m', $t),
        };
    }

    /** @param array<string,mixed> $in @return int id da nova versão */
    public function createVersion(array $in, ?int $adminId): int
    {
        $key = (string) ($in['rule_key'] ?? '');
        if (!preg_match('/^[a-z][a-z0-9_]{2,47}$/', $key)) {
            throw new \InvalidArgumentException('Chave da regra: letras minúsculas, números e _ (3 a 48)');
        }
        $conditions = is_array($in['conditions'] ?? null) ? $in['conditions'] : json_decode((string) ($in['conditions'] ?? ''), true);
        if (!is_array($conditions)) {
            throw new \InvalidArgumentException('Condições devem ser JSON válido');
        }
        self::validate($conditions);
        $occ = (string) ($in['occurrence'] ?? '');
        if (!in_array($occ, ['once', 'day', 'week', 'month'], true)) {
            throw new \InvalidArgumentException('Frequência inválida');
        }
        $currency = ($in['currency'] ?? '') === '' ? null : (string) $in['currency'];
        $amount = ($in['amount'] ?? '') === '' ? null : (int) $in['amount'];
        $ent = ($in['entitlement_key'] ?? '') === '' ? null : (string) $in['entitlement_key'];
        if (($currency === null) !== ($amount === null) || ($currency !== null && !in_array($currency, ['cash', 'gold'], true)) || ($amount !== null && ($amount < 1 || $amount > 1_000_000)) || ($currency === null && $ent === null)) {
            throw new \InvalidArgumentException('Benefício: moeda (cash/gold) + quantidade 1..1.000.000 e/ou um direito');
        }
        $max = max(1, min(100000, (int) ($in['max_grants_per_run'] ?? 1000)));
        $exp = ($in['expires_hours'] ?? '') === '' ? null : max(1, min(8760, (int) $in['expires_hours']));
        $campaign = ($in['notify_campaign_id'] ?? '') === '' ? null : (int) $in['notify_campaign_id'];
        $desc = trim((string) ($in['description'] ?? ''));
        if ($desc === '' || mb_strlen($desc) > 200) {
            throw new \InvalidArgumentException('Descrição obrigatória (até 200 caracteres)');
        }
        return $this->db->tx(function (Db $db) use ($key, $conditions, $occ, $currency, $amount, $ent, $max, $exp, $campaign, $desc, $adminId) {
            $v = (int) $db->one('SELECT COALESCE(MAX(version), 0) AS v FROM reward_rules WHERE rule_key = ? FOR UPDATE', [$key])['v'] + 1;
            $db->exec("UPDATE reward_rules SET status = 'retired' WHERE rule_key = ? AND status <> 'retired'", [$key]);
            return $db->insert(
                "INSERT INTO reward_rules (rule_key, version, description, conditions, occurrence, currency, amount, entitlement_key, expires_hours, max_grants_per_run, notify_campaign_id, status, created_by, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paused', ?, ?)",
                [$key, $v, $desc, json_encode($conditions), $occ, $currency, $amount, $ent, $exp, $max, $campaign, $adminId, $this->clock->sql()]
            );
        });
    }

    public function setStatus(int $id, string $status): void
    {
        if (!in_array($status, ['active', 'paused'], true)) {
            throw new \InvalidArgumentException('Estado inválido');
        }
        $this->db->exec("UPDATE reward_rules SET status = ? WHERE id = ? AND status <> 'retired'", [$status, $id]);
    }

    /** @return array{eligible:int,granted:int} */
    public function run(int $ruleId, bool $dryRun): array
    {
        $r = $this->db->one('SELECT * FROM reward_rules WHERE id = ?', [$ruleId]);
        if ($r === null) {
            throw new \InvalidArgumentException('Regra não encontrada');
        }
        $started = $this->clock->sql();
        $conditions = json_decode($r['conditions'], true);
        [$where, $params] = $this->where($conditions);
        $occ = $this->occurrenceKey($r['occurrence']);
        $sql = "SELECT p.id FROM players p WHERE p.status = 'active' AND $where
                  AND NOT EXISTS (SELECT 1 FROM reward_grants g WHERE g.player_id = p.id AND g.rule_key = ? AND g.occurrence_key = ?)
                ORDER BY p.id LIMIT " . (int) $r['max_grants_per_run'];
        $ids = $this->db->all($sql, array_merge($params, [$r['rule_key'], $occ]));
        $granted = 0;
        if (!$dryRun) {
            foreach ($ids as $row) {
                $res = $this->rewards->grant((int) $row['id'], $r['rule_key'], $occ, $r['currency'], $r['amount'] === null ? null : (int) $r['amount'], $r['entitlement_key'], $r['expires_hours'] === null ? null : (int) $r['expires_hours'] * 3600);
                if ($res['created']) {
                    $granted++;
                    if ($r['notify_campaign_id'] !== null) {
                        $this->enqueueNotice((int) $r['notify_campaign_id'], (int) $row['id']);
                    }
                }
            }
            $this->db->exec('UPDATE reward_rules SET last_run_at = ? WHERE id = ?', [$this->clock->sql(), $ruleId]);
        }
        $this->db->insert(
            'INSERT INTO rule_executions (rule_id, dry_run, eligible_count, granted_count, started_at, finished_at) VALUES (?, ?, ?, ?, ?, ?)',
            [$ruleId, $dryRun ? 1 : 0, count($ids), $granted, $started, $this->clock->sql()]
        );
        return ['eligible' => count($ids), 'granted' => $granted];
    }

    /** Aviso operacional do benefício pelos aparelhos do jogador (campanha disparada por regra). */
    private function enqueueNotice(int $campaignId, int $playerId): void
    {
        $now = $this->clock->sql();
        $this->db->exec(
            "INSERT IGNORE INTO notification_outbox (campaign_id, device_id, player_id, status, scheduled_at, created_at)
             SELECT ?, d.id, d.player_id, 'pending', ?, ? FROM player_devices d
              WHERE d.player_id = ? AND d.revoked_at IS NULL AND d.fcm_token IS NOT NULL",
            [$campaignId, $now, $now, $playerId]
        );
        $this->db->exec(
            "UPDATE notification_campaigns SET status = 'sending', started_at = COALESCE(started_at, ?), completed_at = NULL,
                    audience_count = (SELECT COUNT(*) FROM notification_outbox o WHERE o.campaign_id = notification_campaigns.id)
              WHERE id = ? AND category = 'operational' AND status IN ('draft','sending','completed')",
            [$now, $campaignId]
        );
    }

    /** Cron: roda as regras ativas no máximo uma vez por hora. @return array<string,int> */
    public function runActive(): array
    {
        $out = ['rules_run' => 0, 'rewards_granted' => 0];
        foreach ($this->db->all("SELECT id FROM reward_rules WHERE status = 'active' AND (last_run_at IS NULL OR last_run_at < ?)", [$this->clock->sql(-3600)]) as $r) {
            $res = $this->run((int) $r['id'], false);
            $out['rules_run']++;
            $out['rewards_granted'] += $res['granted'];
        }
        return $out;
    }
}
