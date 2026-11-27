<?php
declare(strict_types=1);

namespace TerraBela\Tests;

use TerraBela\Core\HttpClient;

/** Simula Google/Facebook nos testes: rotas por prefixo de URL → callable que devolve a resposta. */
final class FakeHttpClient implements HttpClient
{
    /** @var array<string,callable> */
    public array $routes = [];
    /** @var list<array{method:string,url:string,body:?string}> */
    public array $calls = [];

    public function on(string $method, string $urlPrefix, callable $fn): void
    {
        $this->routes[$method . ' ' . $urlPrefix] = $fn;
    }

    public function request(string $method, string $url, array $headers = [], ?string $body = null, int $timeout = 10): array
    {
        $this->calls[] = ['method' => $method, 'url' => $url, 'body' => $body];
        $best = null;
        foreach ($this->routes as $key => $fn) {
            [$m, $prefix] = explode(' ', $key, 2);
            if ($m === $method && str_starts_with($url, $prefix) && ($best === null || strlen($prefix) > strlen($best[0]))) {
                $best = [$prefix, $fn];
            }
        }
        if ($best === null) {
            return ['status' => 404, 'headers' => [], 'body' => '{}'];
        }
        $r = ($best[1])($url, $headers, $body);
        return ['status' => $r[0], 'headers' => $r[2] ?? [], 'body' => is_string($r[1]) ? $r[1] : json_encode($r[1])];
    }

    public function count(string $needle): int
    {
        return count(array_filter($this->calls, static fn ($c) => str_contains($c['method'] . ' ' . $c['url'], $needle)));
    }
}
