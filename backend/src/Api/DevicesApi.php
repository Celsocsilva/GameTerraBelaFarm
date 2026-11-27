<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Auth\AuthContext;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;

/** POST /devices/register e DELETE /devices/{id}: instalação e token FCM. */
final class DevicesApi
{
    public function __construct(private Db $db, private Clock $clock)
    {
    }

    public function register(Request $req, AuthContext $ctx): array
    {
        $in = $req->json();
        $installation = V::str($in, 'installation_id', 8, 64, '/^[A-Za-z0-9_.:-]+$/');
        $platform = V::enum($in, 'platform', ['android', 'ios']);
        $fcm = V::optStr($in, 'fcm_token', 512, '/^[A-Za-z0-9_:.\-]+$/');
        $appVersion = V::optStr($in, 'app_version', 32);
        $locale = V::optStr($in, 'locale', 16, '/^[A-Za-z_-]+$/');
        $tz = V::optStr($in, 'timezone', 64, '/^[A-Za-z_\/+-]+$/');
        $fcmHash = $fcm === null ? null : hash('sha256', $fcm);
        $now = $this->clock->sql();

        return $this->db->tx(function (Db $db) use ($ctx, $installation, $platform, $fcm, $fcmHash, $appVersion, $locale, $tz, $now) {
            if ($fcmHash !== null) {
                // O mesmo token em outra instalação/jogador: o token passou a esta instalação.
                $db->exec(
                    'UPDATE player_devices SET fcm_token = NULL, fcm_token_hash = NULL WHERE fcm_token_hash = ? AND NOT (player_id = ? AND installation_id = ?)',
                    [$fcmHash, $ctx->playerId, $installation]
                );
            }
            $row = $db->one('SELECT id, public_id FROM player_devices WHERE player_id = ? AND installation_id = ? FOR UPDATE', [$ctx->playerId, $installation]);
            if ($row === null) {
                $public = Ids::uuidBin();
                $db->insert(
                    'INSERT INTO player_devices (public_id, player_id, installation_id, platform, fcm_token, fcm_token_hash, app_version, locale, timezone, created_at, last_seen_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [$public, $ctx->playerId, $installation, $platform, $fcm, $fcmHash, $appVersion, $locale, $tz, $now, $now]
                );
            } else {
                $public = $row['public_id'];
                $db->exec(
                    'UPDATE player_devices SET platform = ?, fcm_token = ?, fcm_token_hash = ?, app_version = ?, locale = ?, timezone = ?, last_seen_at = ?, revoked_at = NULL WHERE id = ?',
                    [$platform, $fcm, $fcmHash, $appVersion, $locale, $tz, $now, $row['id']]
                );
            }
            if ($locale !== null) {
                $db->exec('UPDATE players SET locale = ? WHERE id = ?', [$locale, $ctx->playerId]);
            }
            return ['device_id' => Ids::binToUuid($public), 'push_registered' => $fcm !== null];
        });
    }

    public function delete(Request $req, AuthContext $ctx): array
    {
        $bin = Ids::uuidToBin($req->params['id']);
        if ($bin === null) {
            throw new ApiException(404, 'device_not_found', 'Instalação não encontrada.');
        }
        $n = $this->db->exec(
            'UPDATE player_devices SET revoked_at = ?, fcm_token = NULL, fcm_token_hash = NULL WHERE public_id = ? AND player_id = ?',
            [$this->clock->sql(), $bin, $ctx->playerId]
        );
        if ($n === 0 && $this->db->one('SELECT id FROM player_devices WHERE public_id = ? AND player_id = ?', [$bin, $ctx->playerId]) === null) {
            throw new ApiException(404, 'device_not_found', 'Instalação não encontrada.');
        }
        return ['revoked' => true];
    }
}
