<?php
declare(strict_types=1);

namespace TerraBela\Core;

use TerraBela\Auth\Jwt;

/**
 * OAuth2 de conta de serviço Google (JWT bearer → access token), sem bibliotecas.
 * O JSON da conta fica FORA da raiz pública. Usado pela Google Play Developer API e pelo FCM HTTP v1.
 */
final class ServiceAccountAuth
{
    private ?string $token = null;
    private int $expires = 0;
    /** @var array<string,mixed>|null */
    private ?array $account = null;

    public function __construct(
        private HttpClient $http,
        private Clock $clock,
        private ?string $file,
        private string $scope,
    ) {
    }

    public function configured(): bool
    {
        return $this->file !== null && is_file($this->file);
    }

    /** @return array<string,mixed> */
    public function account(): array
    {
        if ($this->account === null) {
            if (!$this->configured()) {
                throw new \RuntimeException('Conta de serviço não configurada');
            }
            $this->account = (array) json_decode((string) file_get_contents((string) $this->file), true);
        }
        return $this->account;
    }

    public function token(): string
    {
        if ($this->token !== null && $this->expires > $this->clock->now() + 60) {
            return $this->token;
        }
        $sa = $this->account();
        $now = $this->clock->now();
        $tokenUri = (string) ($sa['token_uri'] ?? 'https://oauth2.googleapis.com/token');
        $assertion = Jwt::signRs256([
            'iss' => $sa['client_email'] ?? '',
            'scope' => $this->scope,
            'aud' => $tokenUri,
            'iat' => $now,
            'exp' => $now + 3600,
        ], (string) ($sa['private_key'] ?? ''), $sa['private_key_id'] ?? null);
        $resp = $this->http->request('POST', $tokenUri, ['Content-Type' => 'application/x-www-form-urlencoded'],
            http_build_query(['grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => $assertion]));
        $data = json_decode($resp['body'], true);
        if ($resp['status'] !== 200 || empty($data['access_token'])) {
            throw new \RuntimeException('Falha ao obter token OAuth da Google: HTTP ' . $resp['status']);
        }
        $this->token = (string) $data['access_token'];
        $this->expires = $now + (int) ($data['expires_in'] ?? 3600);
        return $this->token;
    }
}
