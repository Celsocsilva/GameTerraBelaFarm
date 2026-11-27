<?php
declare(strict_types=1);

namespace TerraBela\LiveOps;

use TerraBela\Core\Clock;
use TerraBela\Core\HttpClient;
use TerraBela\Core\ServiceAccountAuth;

/**
 * Firebase Cloud Messaging HTTP v1 (OAuth2 com conta de serviço de privilégio mínimo).
 * Mensagem notification + data; todos os valores de data são strings e não levam dados pessoais.
 */
class FcmClient
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
    private ServiceAccountAuth $auth;

    public function __construct(private HttpClient $http, Clock $clock, ?string $serviceAccountFile, private ?string $projectId)
    {
        $this->auth = new ServiceAccountAuth($http, $clock, $serviceAccountFile, self::SCOPE);
    }

    public function configured(): bool
    {
        return $this->auth->configured();
    }

    /**
     * @param array<string,string> $data
     * @return array{result:string,message_id:?string,error:?string} result: sent | invalid_token | retry | failed
     */
    public function send(string $token, string $title, string $body, array $data): array
    {
        $project = $this->projectId ?? (string) ($this->auth->account()['project_id'] ?? '');
        $payload = ['message' => [
            'token' => $token,
            'notification' => ['title' => $title, 'body' => $body],
            'data' => array_map('strval', $data),
            'android' => ['priority' => 'high', 'notification' => ['channel_id' => 'terrabela_default']],
        ]];
        try {
            $resp = $this->http->request('POST', 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($project) . '/messages:send', [
                'Authorization' => 'Bearer ' . $this->auth->token(),
                'Content-Type' => 'application/json',
            ], json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        } catch (\RuntimeException $e) {
            return ['result' => 'retry', 'message_id' => null, 'error' => mb_substr($e->getMessage(), 0, 150)];
        }
        $json = json_decode($resp['body'], true) ?: [];
        if ($resp['status'] === 200) {
            return ['result' => 'sent', 'message_id' => (string) ($json['name'] ?? ''), 'error' => null];
        }
        $errCode = (string) ($json['error']['details'][0]['errorCode'] ?? $json['error']['status'] ?? 'HTTP_' . $resp['status']);
        if ($resp['status'] === 404 || $errCode === 'UNREGISTERED' || ($resp['status'] === 400 && str_contains($resp['body'], 'registration token'))) {
            return ['result' => 'invalid_token', 'message_id' => null, 'error' => $errCode];
        }
        if ($resp['status'] === 429 || $resp['status'] >= 500) {
            return ['result' => 'retry', 'message_id' => null, 'error' => $errCode];
        }
        return ['result' => 'failed', 'message_id' => null, 'error' => $errCode];
    }
}
