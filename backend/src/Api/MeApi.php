<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Auth\AuthContext;
use TerraBela\Auth\TokenService;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Http\Request;
use TerraBela\Players\PlayerService;

/** GET /me, DELETE /me e PUT /preferences/notifications. */
final class MeApi
{
    private const CONSENT_TYPES = ['notify_operational', 'notify_promotional', 'os_notification_permission'];

    public function __construct(
        private Db $db,
        private Clock $clock,
        private PlayerService $players,
        private TokenService $tokens,
        private int $deletionGraceDays,
    ) {
    }

    public function get(Request $req, AuthContext $ctx): array
    {
        $identities = $this->db->all('SELECT provider, created_at FROM player_identities WHERE player_id = ? ORDER BY provider', [$ctx->playerId]);
        return $this->players->summary($ctx->playerId) + [
            'identities' => array_map(static fn ($r) => ['provider' => $r['provider'], 'linked_at' => Clock::iso($r['created_at'])], $identities),
            'notification_preferences' => $this->preferences($ctx->playerId),
        ];
    }

    /** Pedido de exclusão: encerra sessões e instalações; o cron remove os dados após a carência. */
    public function delete(Request $req, AuthContext $ctx): array
    {
        $this->db->tx(function (Db $db) use ($ctx) {
            $now = $this->clock->sql();
            $db->exec("UPDATE players SET status = 'deletion_requested', deletion_requested_at = ? WHERE id = ? AND status = 'active'", [$now, $ctx->playerId]);
            $db->exec('UPDATE player_devices SET revoked_at = ?, fcm_token = NULL, fcm_token_hash = NULL WHERE player_id = ? AND revoked_at IS NULL', [$now, $ctx->playerId]);
            $this->tokens->revokeAll($ctx->playerId, 'account_deleted');
        });
        return [
            'deletion_requested' => true,
            'purge_after' => gmdate('Y-m-d\TH:i:s\Z', $this->clock->now() + $this->deletionGraceDays * 86400),
        ];
    }

    public function putNotificationPreferences(Request $req, AuthContext $ctx): array
    {
        $in = $req->json();
        $map = [
            'operational' => 'notify_operational',
            'promotional' => 'notify_promotional',
            'os_permission_granted' => 'os_notification_permission',
        ];
        $source = V::optStr($in, 'source', 32, '/^[a-z_]+$/') ?? 'app_settings';
        $current = $this->preferences($ctx->playerId);
        foreach ($map as $field => $type) {
            if (!array_key_exists($field, $in)) {
                continue;
            }
            $value = V::bool($in, $field);
            if (($current[$field] ?? null) === $value) {
                continue;
            }
            $this->db->insert(
                'INSERT INTO player_consents (player_id, consent_type, granted, source, recorded_at) VALUES (?, ?, ?, ?, ?)',
                [$ctx->playerId, $type, $value ? 1 : 0, $source, $this->clock->sql()]
            );
        }
        return ['notification_preferences' => $this->preferences($ctx->playerId)];
    }

    /** Estado vigente: o registro mais recente de cada tipo. Promocional começa desligado. @return array<string,bool|null> */
    public function preferences(int $playerId): array
    {
        $out = ['operational' => true, 'promotional' => false, 'os_permission_granted' => null];
        $names = array_flip(['operational' => 'notify_operational', 'promotional' => 'notify_promotional', 'os_permission_granted' => 'os_notification_permission']);
        foreach (self::CONSENT_TYPES as $type) {
            $r = $this->db->one(
                'SELECT granted FROM player_consents WHERE player_id = ? AND consent_type = ? ORDER BY recorded_at DESC, id DESC LIMIT 1',
                [$playerId, $type]
            );
            if ($r !== null) {
                $out[$names[$type]] = (bool) $r['granted'];
            }
        }
        return $out;
    }
}
