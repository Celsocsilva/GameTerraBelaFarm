<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Auth\AppleIdTokenVerifier;
use TerraBela\Auth\AuthContext;
use TerraBela\Auth\FacebookTokenVerifier;
use TerraBela\Auth\GoogleIdTokenVerifier;
use TerraBela\Auth\ProviderIdentity;
use TerraBela\Auth\TokenService;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;
use TerraBela\Players\PlayerService;

/**
 * POST /auth/guest, /auth/google, /auth/apple, /auth/facebook, /auth/link, /auth/refresh, /auth/logout.
 * Contas nunca são unidas por e-mail; conflitos devolvem 409 com resumo das duas fazendas.
 */
final class AuthApi
{
    /** @param list<string> $googleClientIds @param list<string> $appleClientIds */
    public function __construct(
        private Db $db,
        private Clock $clock,
        private TokenService $tokens,
        private PlayerService $players,
        private GoogleIdTokenVerifier $google,
        private FacebookTokenVerifier $facebook,
        private array $googleClientIds,
        private string $appKey,
        private ?AppleIdTokenVerifier $apple = null,
        private array $appleClientIds = [],
    ) {
    }

    public function guest(Request $req): array
    {
        $in = $req->json();
        $ua = $req->header('user-agent');
        if (isset($in['guest_id']) || isset($in['guest_secret'])) {
            $guestId = V::str($in, 'guest_id', 36, 36);
            $secret = V::str($in, 'guest_secret', 20, 128);
            $row = $this->db->one(
                "SELECT i.id, i.player_id, i.secret_hash, p.public_id, p.status FROM player_identities i
                   JOIN players p ON p.id = i.player_id
                  WHERE i.provider = 'guest' AND i.subject = ?",
                [$guestId]
            );
            if ($row === null || !hash_equals((string) $row['secret_hash'], hash_hmac('sha256', $secret, $this->appKey))) {
                throw new ApiException(401, 'invalid_credentials', 'Credencial de visitante inválida.');
            }
            if ($row['status'] !== 'active') {
                throw new ApiException(403, 'account_inactive', 'Esta conta não está ativa.');
            }
            $this->db->exec('UPDATE player_identities SET last_used_at = ? WHERE id = ?', [$this->clock->sql(), $row['id']]);
            return ['created' => false, 'player_id' => Ids::binToUuid($row['public_id'])]
                + $this->tokens->issue((int) $row['player_id'], 'guest', $ua);
        }

        $locale = V::optStr($in, 'locale', 16);
        return $this->db->tx(function () use ($locale, $ua) {
            $p = $this->players->create($locale);
            $guestId = Ids::binToUuid(Ids::uuidBin());
            $secret = Ids::token('tbfg_');
            $this->db->insert(
                "INSERT INTO player_identities (player_id, provider, subject, secret_hash, created_at) VALUES (?, 'guest', ?, ?, ?)",
                [$p['id'], $guestId, hash_hmac('sha256', $secret, $this->appKey), $this->clock->sql()]
            );
            return [
                'created' => true,
                'player_id' => $p['public_id'],
                // O segredo só é devolvido agora: o app deve guardá-lo em armazenamento protegido.
                'guest_id' => $guestId,
                'guest_secret' => $secret,
            ] + $this->tokens->issue($p['id'], 'guest', $ua);
        });
    }

    public function google(Request $req): array
    {
        $in = $req->json();
        $identity = $this->google->identity(V::str($in, 'id_token', 20, 4096), $this->googleClientIds, V::optStr($in, 'nonce', 128));
        return $this->loginWith($identity, $req);
    }

    /** Sign in with Apple: identity_token do ASAuthorizationAppleIDCredential (iOS) ou do fluxo web/Android. */
    public function apple(Request $req): array
    {
        $in = $req->json();
        return $this->loginWith($this->appleIdentity($in), $req);
    }

    private function appleIdentity(array $in): ProviderIdentity
    {
        if ($this->apple === null) {
            throw new ApiException(503, 'provider_not_configured', 'Login com Apple ainda não está configurado no servidor.');
        }
        return $this->apple->identity(V::str($in, 'id_token', 20, 4096), $this->appleClientIds, V::optStr($in, 'nonce', 128));
    }

    public function facebook(Request $req): array
    {
        $in = $req->json();
        $identity = $this->facebook->identity(V::str($in, 'access_token', 20, 4096));
        return $this->loginWith($identity, $req);
    }

    /** Vincula Google/Facebook/Apple à fazenda atual (o visitante passa a poder recuperar a conta). */
    public function link(Request $req, AuthContext $ctx): array
    {
        $in = $req->json();
        $provider = V::enum($in, 'provider', ['google', 'facebook', 'apple']);
        $identity = match ($provider) {
            'google' => $this->google->identity(V::str($in, 'id_token', 20, 4096), $this->googleClientIds, V::optStr($in, 'nonce', 128)),
            'apple' => $this->appleIdentity($in),
            default => $this->facebook->identity(V::str($in, 'access_token', 20, 4096)),
        };

        return $this->db->tx(function (Db $db) use ($identity, $ctx) {
            $existing = $db->one(
                'SELECT player_id FROM player_identities WHERE provider = ? AND subject = ? FOR UPDATE',
                [$identity->provider, $identity->subject]
            );
            if ($existing !== null) {
                if ((int) $existing['player_id'] === $ctx->playerId) {
                    return ['linked' => true, 'provider' => $identity->provider, 'already_linked' => true];
                }
                throw new ApiException(409, 'account_conflict', 'Esta conta do provedor já está ligada a outra fazenda.', [
                    'current_farm' => $this->players->summary($ctx->playerId),
                    'other_farm' => $this->players->summary((int) $existing['player_id']),
                    'resolution' => 'Escolha no app: manter esta fazenda (não vincula) ou entrar na outra fazenda com POST /auth/' . $identity->provider . '. Nenhum saldo é mesclado.',
                ]);
            }
            $same = $db->one('SELECT id FROM player_identities WHERE player_id = ? AND provider = ?', [$ctx->playerId, $identity->provider]);
            if ($same !== null) {
                throw new ApiException(409, 'provider_already_linked', 'Esta fazenda já tem outra conta deste provedor vinculada.');
            }
            $db->insert(
                'INSERT INTO player_identities (player_id, provider, subject, created_at) VALUES (?, ?, ?, ?)',
                [$ctx->playerId, $identity->provider, $identity->subject, $this->clock->sql()]
            );
            return ['linked' => true, 'provider' => $identity->provider, 'already_linked' => false];
        });
    }

    public function refresh(Request $req): array
    {
        $in = $req->json();
        return $this->tokens->refresh(V::str($in, 'refresh_token', 20, 128));
    }

    public function logout(Request $req, AuthContext $ctx): array
    {
        $this->tokens->revokeSession($ctx->sessionId, 'logout');
        return ['logged_out' => true];
    }

    private function loginWith(ProviderIdentity $identity, Request $req): array
    {
        $ua = $req->header('user-agent');
        return $this->db->tx(function (Db $db) use ($identity, $ua) {
            $row = $db->one(
                'SELECT i.id, i.player_id, p.public_id, p.status FROM player_identities i JOIN players p ON p.id = i.player_id
                  WHERE i.provider = ? AND i.subject = ?',
                [$identity->provider, $identity->subject]
            );
            if ($row !== null) {
                if ($row['status'] !== 'active') {
                    throw new ApiException(403, 'account_inactive', 'Esta conta não está ativa.');
                }
                $db->exec('UPDATE player_identities SET last_used_at = ? WHERE id = ?', [$this->clock->sql(), $row['id']]);
                return ['created' => false, 'player_id' => Ids::binToUuid($row['public_id'])]
                    + $this->tokens->issue((int) $row['player_id'], $identity->provider, $ua);
            }
            $p = $this->players->create(null);
            $db->insert(
                'INSERT INTO player_identities (player_id, provider, subject, created_at, last_used_at) VALUES (?, ?, ?, ?, ?)',
                [$p['id'], $identity->provider, $identity->subject, $this->clock->sql(), $this->clock->sql()]
            );
            return ['created' => true, 'player_id' => $p['public_id']] + $this->tokens->issue($p['id'], $identity->provider, $ua);
        });
    }
}
