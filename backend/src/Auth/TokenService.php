<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Http\ApiException;

/**
 * Tokens opacos (não JWT): access curto + refresh rotativo, guardados só como HMAC.
 * Reapresentar um refresh já rotacionado revoga a sessão inteira (detecção de roubo).
 */
final class TokenService
{
    public function __construct(
        private Db $db,
        private Clock $clock,
        private string $appKey,
        private int $accessTtl,
        private int $refreshTtl,
    ) {
    }

    public function hash(string $token): string
    {
        return hash_hmac('sha256', $token, $this->appKey);
    }

    /** @return array<string,mixed> */
    public function issue(int $playerId, string $provider, ?string $userAgent): array
    {
        $access = Ids::token('tbfa_');
        $refresh = Ids::token('tbfr_');
        $sessionPublic = Ids::uuidBin();
        $this->db->insert(
            'INSERT INTO player_sessions (public_id, player_id, access_hash, access_expires_at, refresh_hash, refresh_expires_at, login_provider, user_agent, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $sessionPublic, $playerId, $this->hash($access), $this->clock->sql($this->accessTtl),
                $this->hash($refresh), $this->clock->sql($this->refreshTtl), $provider,
                $userAgent === null ? null : mb_substr($userAgent, 0, 255), $this->clock->sql(),
            ]
        );
        return $this->tokenPayload($access, $refresh, Ids::binToUuid($sessionPublic));
    }

    public function authenticate(?string $accessToken): AuthContext
    {
        if ($accessToken === null || $accessToken === '') {
            throw new ApiException(401, 'unauthorized', 'Autenticação necessária.');
        }
        $row = $this->db->one(
            'SELECT s.id AS session_id, s.access_expires_at, p.id AS player_id, p.public_id, p.status, p.last_seen_at
               FROM player_sessions s JOIN players p ON p.id = s.player_id
              WHERE s.access_hash = ? AND s.revoked_at IS NULL',
            [$this->hash($accessToken)]
        );
        if ($row === null || strtotime($row['access_expires_at'] . ' UTC') < $this->clock->now()) {
            throw new ApiException(401, 'token_expired', 'Sessão expirada. Renove o token.');
        }
        if ($row['status'] !== 'active') {
            throw new ApiException(403, 'account_inactive', 'Esta conta não está ativa.');
        }
        // Atualiza last_seen_at no máximo a cada 5 minutos para poupar escrita.
        if ($row['last_seen_at'] === null || strtotime($row['last_seen_at'] . ' UTC') < $this->clock->now() - 300) {
            $this->db->exec('UPDATE players SET last_seen_at = ? WHERE id = ?', [$this->clock->sql(), $row['player_id']]);
        }
        return new AuthContext((int) $row['player_id'], Ids::binToUuid($row['public_id']), (int) $row['session_id']);
    }

    /** @return array<string,mixed> */
    public function refresh(string $refreshToken): array
    {
        $hash = $this->hash($refreshToken);
        $result = $this->db->tx(function (Db $db) use ($hash) {
            $s = $db->one(
                'SELECT s.id, s.public_id, s.refresh_expires_at, s.revoked_at, p.status
                   FROM player_sessions s JOIN players p ON p.id = s.player_id
                  WHERE s.refresh_hash = ? FOR UPDATE',
                [$hash]
            );
            if ($s === null) {
                $reused = $db->one('SELECT id FROM player_sessions WHERE previous_refresh_hash = ? AND revoked_at IS NULL FOR UPDATE', [$hash]);
                if ($reused !== null) {
                    $db->exec(
                        "UPDATE player_sessions SET revoked_at = ?, revoke_reason = 'refresh_reuse' WHERE id = ?",
                        [$this->clock->sql(), $reused['id']]
                    );
                    return ['revoked' => true];
                }
                throw new ApiException(401, 'invalid_refresh_token', 'Refresh token inválido.');
            }
            if ($s['revoked_at'] !== null || strtotime($s['refresh_expires_at'] . ' UTC') < $this->clock->now()) {
                throw new ApiException(401, 'invalid_refresh_token', 'Refresh token inválido.');
            }
            if ($s['status'] !== 'active') {
                throw new ApiException(403, 'account_inactive', 'Esta conta não está ativa.');
            }
            $access = Ids::token('tbfa_');
            $refresh = Ids::token('tbfr_');
            $db->exec(
                'UPDATE player_sessions
                    SET previous_refresh_hash = refresh_hash, refresh_hash = ?, refresh_expires_at = ?,
                        access_hash = ?, access_expires_at = ?, rotated_at = ?
                  WHERE id = ?',
                [$this->hash($refresh), $this->clock->sql($this->refreshTtl), $this->hash($access), $this->clock->sql($this->accessTtl), $this->clock->sql(), $s['id']]
            );
            return $this->tokenPayload($access, $refresh, Ids::binToUuid($s['public_id']));
        });
        if (isset($result['revoked'])) {
            // A revogação já foi gravada (commit) antes de responder o erro.
            throw new ApiException(401, 'refresh_token_reused', 'Refresh token já utilizado. A sessão foi encerrada por segurança.');
        }
        return $result;
    }

    public function revokeSession(int $sessionId, string $reason): void
    {
        $this->db->exec(
            'UPDATE player_sessions SET revoked_at = ?, revoke_reason = ? WHERE id = ? AND revoked_at IS NULL',
            [$this->clock->sql(), $reason, $sessionId]
        );
    }

    public function revokeAll(int $playerId, string $reason): void
    {
        $this->db->exec(
            'UPDATE player_sessions SET revoked_at = ?, revoke_reason = ? WHERE player_id = ? AND revoked_at IS NULL',
            [$this->clock->sql(), $reason, $playerId]
        );
    }

    /** @return array<string,mixed> */
    private function tokenPayload(string $access, string $refresh, string $sessionId): array
    {
        return [
            'session_id' => $sessionId,
            'access_token' => $access,
            'access_expires_in' => $this->accessTtl,
            'refresh_token' => $refresh,
            'refresh_expires_in' => $this->refreshTtl,
            'token_type' => 'Bearer',
        ];
    }
}
