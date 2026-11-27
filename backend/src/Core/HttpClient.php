<?php
declare(strict_types=1);

namespace TerraBela\Core;

/** Cliente HTTP de saída (Google, Facebook, FCM). Implementação real com cURL; testes usam um fake. */
interface HttpClient
{
    /**
     * @param array<string,string> $headers
     * @return array{status:int,headers:array<string,string>,body:string}
     */
    public function request(string $method, string $url, array $headers = [], ?string $body = null, int $timeout = 10): array;
}
