<?php
declare(strict_types=1);

namespace TerraBela\Billing;

use TerraBela\Core\Clock;
use TerraBela\Core\HttpClient;
use TerraBela\Core\ServiceAccountAuth;

/**
 * Google Play Developer API (androidpublisher v3) para produtos únicos:
 * consulta, acknowledge e consume. Autentica com conta de serviço (JWT → OAuth2),
 * cujo JSON fica FORA da raiz pública (GOOGLE_PLAY_SERVICE_ACCOUNT_FILE).
 */
class GooglePlayClient
{
    private const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
    private const BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/';

    private ServiceAccountAuth $auth;

    public function __construct(
        private HttpClient $http,
        Clock $clock,
        ?string $serviceAccountFile,
        public readonly string $packageName,
    ) {
        $this->auth = new ServiceAccountAuth($http, $clock, $serviceAccountFile, self::SCOPE);
    }

    public function configured(): bool
    {
        return $this->auth->configured();
    }

    /** @return array<string,mixed> resposta ProductPurchase da Google */
    public function getProduct(string $sku, string $token): array
    {
        $resp = $this->call('GET', $this->url($sku, $token));
        if ($resp['status'] === 404 || $resp['status'] === 400 || $resp['status'] === 410) {
            throw new PurchaseNotFound('Compra não encontrada na Google Play');
        }
        if ($resp['status'] !== 200) {
            throw new \RuntimeException('Google Play respondeu HTTP ' . $resp['status']);
        }
        return (array) json_decode($resp['body'], true);
    }

    public function acknowledge(string $sku, string $token): bool
    {
        $r = $this->call('POST', $this->url($sku, $token) . ':acknowledge', '{}');
        return $r['status'] >= 200 && $r['status'] < 300;
    }

    public function consume(string $sku, string $token): bool
    {
        $r = $this->call('POST', $this->url($sku, $token) . ':consume', '');
        return $r['status'] >= 200 && $r['status'] < 300;
    }

    private function url(string $sku, string $token): string
    {
        return self::BASE . rawurlencode($this->packageName) . '/purchases/products/' . rawurlencode($sku) . '/tokens/' . rawurlencode($token);
    }

    /** @return array{status:int,headers:array<string,string>,body:string} */
    private function call(string $method, string $url, ?string $body = null): array
    {
        $headers = ['Authorization' => 'Bearer ' . $this->token(), 'Accept' => 'application/json'];
        if ($body !== null) {
            $headers['Content-Type'] = 'application/json';
        }
        return $this->http->request($method, $url, $headers, $body);
    }

    private function token(): string
    {
        return $this->auth->token();
    }
}
