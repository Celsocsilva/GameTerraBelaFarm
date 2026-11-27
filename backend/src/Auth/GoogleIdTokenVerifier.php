<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\Clock;
use TerraBela\Http\ApiException;

/**
 * Valida ID tokens do Google (Credential Manager / Sign in with Google) e também
 * tokens OIDC de push do Pub/Sub (RTDN): assinatura RS256 via JWKS, issuer, audience e validade.
 */
final class GoogleIdTokenVerifier
{
    public const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
    private const ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];

    public function __construct(private JwksCache $jwks, private Clock $clock)
    {
    }

    /**
     * @param list<string> $audiences client IDs aceitos (ou audiência do push RTDN)
     * @return array<string,mixed> claims validadas
     */
    public function verify(string $idToken, array $audiences, ?string $nonce = null, int $leeway = 60): array
    {
        if ($audiences === []) {
            throw new ApiException(503, 'provider_not_configured', 'Login com Google ainda não está configurado no servidor.');
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
        $ok = in_array($c['iss'] ?? '', self::ISSUERS, true)
            && is_string($aud) && in_array($aud, $audiences, true)
            && isset($c['exp']) && (int) $c['exp'] + $leeway >= $now
            && (!isset($c['iat']) || (int) $c['iat'] - $leeway <= $now)
            && isset($c['sub']) && is_string($c['sub']) && $c['sub'] !== '';
        if ($ok && $nonce !== null) {
            $ok = isset($c['nonce']) && hash_equals((string) $c['nonce'], $nonce);
        }
        if (!$ok) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        return $c;
    }

    /** @param list<string> $audiences */
    public function identity(string $idToken, array $audiences, ?string $nonce): ProviderIdentity
    {
        $claims = $this->verify($idToken, $audiences, $nonce);
        return new ProviderIdentity('google', (string) $claims['sub']);
    }
}
