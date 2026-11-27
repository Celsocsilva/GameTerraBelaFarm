<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\Clock;
use TerraBela\Http\ApiException;

/**
 * Valida o identity token do Sign in with Apple (RS256 via JWKS da Apple, issuer, audience e validade).
 * audience = Bundle ID do app iOS (ou Services ID no Android/web), em APPLE_CLIENT_IDS.
 * Nonce: o app manda à Apple o SHA-256 do nonce bruto e ao servidor o nonce bruto; aceitamos as duas formas.
 * O e-mail (muitas vezes um relay privado) não é usado nem guardado: a conta é ligada só pelo "sub".
 */
final class AppleIdTokenVerifier
{
    public const JWKS_URL = 'https://appleid.apple.com/auth/keys';
    public const ISSUER = 'https://appleid.apple.com';

    public function __construct(private JwksCache $jwks, private Clock $clock)
    {
    }

    /** @param list<string> $audiences @return array<string,mixed> */
    public function verify(string $idToken, array $audiences, ?string $nonce = null, int $leeway = 60): array
    {
        if ($audiences === []) {
            throw new ApiException(503, 'provider_not_configured', 'Login com Apple ainda não está configurado no servidor.');
        }
        try {
            $jwt = Jwt::decode($idToken);
        } catch (\InvalidArgumentException) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        if (($jwt['header']['alg'] ?? '') !== 'RS256' || !isset($jwt['header']['kid'])) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        $key = $this->jwks->key(self::JWKS_URL, (string) $jwt['header']['kid']);
        if ($key === null || !Jwt::verifyRs256($jwt['signing_input'], $jwt['signature'], $key)) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        $c = $jwt['payload'];
        $now = $this->clock->now();
        $aud = $c['aud'] ?? null;
        $ok = ($c['iss'] ?? '') === self::ISSUER
            && is_string($aud) && in_array($aud, $audiences, true)
            && isset($c['exp']) && (int) $c['exp'] + $leeway >= $now
            && (!isset($c['iat']) || (int) $c['iat'] - $leeway <= $now)
            && isset($c['sub']) && is_string($c['sub']) && $c['sub'] !== '' && strlen($c['sub']) <= 191;
        if ($ok && $nonce !== null) {
            $claim = isset($c['nonce']) ? (string) $c['nonce'] : '';
            $ok = $claim !== '' && (hash_equals($claim, $nonce) || hash_equals($claim, hash('sha256', $nonce)));
        }
        if (!$ok) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        return $c;
    }

    /** @param list<string> $audiences */
    public function identity(string $idToken, array $audiences, ?string $nonce): ProviderIdentity
    {
        return new ProviderIdentity('apple', (string) $this->verify($idToken, $audiences, $nonce)['sub']);
    }
}
