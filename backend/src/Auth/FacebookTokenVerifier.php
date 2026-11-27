<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\HttpClient;
use TerraBela\Http\ApiException;

/** Valida o access token do Facebook Login no Graph API (debug_token) com o app token do servidor. */
final class FacebookTokenVerifier
{
    public function __construct(
        private HttpClient $http,
        private ?string $appId,
        private ?string $appSecret,
        private string $graphVersion = 'v21.0',
    ) {
    }

    public function identity(string $accessToken): ProviderIdentity
    {
        if ($this->appId === null || $this->appSecret === null) {
            throw new ApiException(503, 'provider_not_configured', 'Login com Facebook ainda não está configurado no servidor.');
        }
        $url = sprintf(
            'https://graph.facebook.com/%s/debug_token?input_token=%s&access_token=%s',
            $this->graphVersion,
            rawurlencode($accessToken),
            rawurlencode($this->appId . '|' . $this->appSecret)
        );
        try {
            $resp = $this->http->request('GET', $url);
        } catch (\RuntimeException) {
            throw new ApiException(503, 'provider_unavailable', 'Facebook indisponível. Tente novamente.');
        }
        $data = json_decode($resp['body'], true)['data'] ?? null;
        if ($resp['status'] !== 200 || !is_array($data)
            || ($data['is_valid'] ?? false) !== true
            || (string) ($data['app_id'] ?? '') !== $this->appId
            || empty($data['user_id'])) {
            throw new ApiException(401, 'invalid_provider_token', 'Token do provedor inválido.');
        }
        return new ProviderIdentity('facebook', (string) $data['user_id']);
    }
}
