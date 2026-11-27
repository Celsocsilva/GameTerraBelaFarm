<?php
declare(strict_types=1);

namespace TerraBela\Rewards;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Economy\LedgerService;
use TerraBela\Http\ApiException;

/**
 * Concessão (registrada antes de notificar) e resgate idempotente de benefícios.
 * Uma concessão por (jogador, regra, ocorrência). Benefício nunca depende de aceitar marketing.
 */
final class RewardService
{
    public function __construct(private Db $db, private Clock $clock, private LedgerService $ledger)
    {
    }

    /** @return array{reward_id:string,created:bool} */
    public function grant(int $playerId, string $ruleKey, string $occurrenceKey, ?string $currency, ?int $amount, ?string $entitlement, ?int $expiresInSeconds): array
    {
        if (($currency === null) !== ($amount === null) || ($currency === null && $entitlement === null) || ($amount !== null && $amount <= 0)) {
            throw new \InvalidArgumentException('Benefício precisa de moeda+quantidade positiva e/ou direito');
        }
        $public = Ids::uuidBin();
        $n = $this->db->exec(
            'INSERT IGNORE INTO reward_grants (public_id, player_id, rule_key, occurrence_key, currency, amount, entitlement_key, status, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, \'available\', ?, ?)',
            [$public, $playerId, $ruleKey, $occurrenceKey, $currency, $amount, $entitlement, $expiresInSeconds === null ? null : $this->clock->sql($expiresInSeconds), $this->clock->sql()]
        );
        if ($n === 0) {
            $row = $this->db->one('SELECT public_id FROM reward_grants WHERE player_id = ? AND rule_key = ? AND occurrence_key = ?', [$playerId, $ruleKey, $occurrenceKey]);
            return ['reward_id' => Ids::binToUuid($row['public_id']), 'created' => false];
        }
        return ['reward_id' => Ids::binToUuid($public), 'created' => true];
    }

    /** @return list<array<string,mixed>> */
    public function list(int $playerId): array
    {
        $rows = $this->db->all(
            "SELECT public_id, rule_key, currency, amount, entitlement_key, status, expires_at, created_at, claimed_at
               FROM reward_grants WHERE player_id = ? AND (status = 'available' OR claimed_at >= ?)
              ORDER BY created_at DESC LIMIT 100",
            [$playerId, $this->clock->sql(-30 * 86400)]
        );
        $now = $this->clock->now();
        return array_map(static function ($r) use ($now) {
            $status = $r['status'];
            if ($status === 'available' && $r['expires_at'] !== null && strtotime($r['expires_at'] . ' UTC') < $now) {
                $status = 'expired';
            }
            return [
                'reward_id' => Ids::binToUuid($r['public_id']),
                'rule_key' => $r['rule_key'],
                'currency' => $r['currency'],
                'amount' => $r['amount'] === null ? null : (int) $r['amount'],
                'entitlement' => $r['entitlement_key'],
                'status' => $status,
                'expires_at' => Clock::iso($r['expires_at']),
                'created_at' => Clock::iso($r['created_at']),
                'claimed_at' => Clock::iso($r['claimed_at']),
            ];
        }, $rows);
    }

    /** @return array<string,mixed> */
    public function claim(int $playerId, string $rewardPublicId): array
    {
        $bin = Ids::uuidToBin($rewardPublicId);
        if ($bin === null) {
            throw new ApiException(404, 'reward_not_found', 'Benefício não encontrado.');
        }
        return $this->db->tx(function (Db $db) use ($playerId, $bin, $rewardPublicId) {
            $g = $db->one('SELECT * FROM reward_grants WHERE public_id = ? AND player_id = ? FOR UPDATE', [$bin, $playerId]);
            if ($g === null) {
                throw new ApiException(404, 'reward_not_found', 'Benefício não encontrado.');
            }
            if ($g['status'] === 'claimed') {
                return ['reward_id' => $rewardPublicId, 'claimed' => true, 'replayed' => true, 'wallet' => $this->ledger->wallet($playerId)];
            }
            if ($g['status'] !== 'available') {
                throw new ApiException(409, 'reward_unavailable', 'Benefício indisponível.', ['status' => $g['status']]);
            }
            if ($g['expires_at'] !== null && strtotime($g['expires_at'] . ' UTC') < $this->clock->now()) {
                $db->exec("UPDATE reward_grants SET status = 'expired' WHERE id = ?", [$g['id']]);
                return ['reward_id' => $rewardPublicId, 'claimed' => false, 'expired' => true];
            }
            $ledgerId = null;
            if ($g['currency'] !== null) {
                $r = $this->ledger->post($playerId, $g['currency'], (int) $g['amount'], 'reward', 'reward_claim', $g['rule_key'], 'reward:' . $rewardPublicId);
                $ledgerId = $r['ledger_id'];
            }
            if ($g['entitlement_key'] !== null) {
                $db->exec(
                    "INSERT INTO entitlements (player_id, entitlement_key, source, source_reference, granted_at) VALUES (?, ?, 'reward', ?, ?)
                     ON DUPLICATE KEY UPDATE revoked_at = NULL",
                    [$playerId, $g['entitlement_key'], $rewardPublicId, $this->clock->sql()]
                );
            }
            $db->exec("UPDATE reward_grants SET status = 'claimed', claimed_at = ?, ledger_id = ? WHERE id = ?", [$this->clock->sql(), $ledgerId, $g['id']]);
            return ['reward_id' => $rewardPublicId, 'claimed' => true, 'replayed' => false, 'wallet' => $this->ledger->wallet($playerId)];
        });
    }
}
