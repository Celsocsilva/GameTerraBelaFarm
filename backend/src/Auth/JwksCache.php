<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\Clock;
use TerraBela\Core\HttpClient;

/** Baixa e guarda em cache (arquivo) as chaves públicas JWKS de um provedor. */
final class JwksCache
{
    public function __construct(
        private HttpClient $http,
        private Clock $clock,
        private ?string $cacheDir,
    ) {
    }

    /** @return array<string,mixed>|null */
    public function key(string $url, string $kid): ?array
    {
        $keys = $this->load($url, false);
        if (!isset($keys[$kid])) {
            $keys = $this->load($url, true);
        }
        return $keys[$kid] ?? null;
    }

    /** @return array<string,array<string,mixed>> */
    private function load(string $url, bool $force): array
    {
        $file = $this->cacheDir ? $this->cacheDir . '/jwks-' . substr(hash('sha256', $url), 0, 16) . '.json' : null;
        if (!$force && $file && is_file($file)) {
            $cached = json_decode((string) file_get_contents($file), true);
            if (is_array($cached) && ($cached['expires'] ?? 0) > $this->clock->now()) {
                return $cached['keys'];
            }
        }
        $resp = $this->http->request('GET', $url);
        if ($resp['status'] !== 200) {
            throw new \RuntimeException('JWKS indisponível: HTTP ' . $resp['status']);
        }
        $data = json_decode($resp['body'], true);
        $keys = [];
        foreach (($data['keys'] ?? []) as $k) {
            if (isset($k['kid'])) {
                $keys[(string) $k['kid']] = $k;
            }
        }
        $ttl = 3600;
        if (preg_match('/max-age=(\d+)/', $resp['headers']['cache-control'] ?? '', $m)) {
            $ttl = max(60, min(86400, (int) $m[1]));
        }
        if ($file) {
            if (!is_dir(dirname($file))) {
                @mkdir(dirname($file), 0750, true);
            }
            @file_put_contents($file, json_encode(['expires' => $this->clock->now() + $ttl, 'keys' => $keys]), LOCK_EX);
        }
        return $keys;
    }
}
