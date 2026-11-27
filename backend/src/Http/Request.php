<?php
declare(strict_types=1);

namespace TerraBela\Http;

final class Request
{
    /** @var array<string,string> */
    public array $params = [];

    /**
     * @param array<string,string> $headers nomes em minúsculas
     * @param array<string,mixed> $query
     * @param array<string,string> $cookies
     */
    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $headers = [],
        public readonly array $query = [],
        public readonly string $body = '',
        public readonly string $ip = '127.0.0.1',
        public readonly array $cookies = [],
        public readonly string $basePath = '',
        public readonly bool $secure = true,
    ) {
    }

    /**
     * @param string $proxyMode "0" (usa REMOTE_ADDR), "cloudflare" (CF-Connecting-IP só quando a conexão
     *                          vem de um IP da Cloudflare) ou "1" (primeiro X-Forwarded-For, só atrás de proxy próprio)
     */
    public static function fromGlobals(string $proxyMode = '0'): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = (string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
        // Remove o diretório onde o index.php está publicado (ex.: /terrabelafarm).
        $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
        if ($base !== '' && str_starts_with($uri, $base)) {
            $uri = substr($uri, strlen($base));
        } else {
            $base = '';
        }
        if (str_starts_with($uri, '/index.php')) {
            $uri = substr($uri, strlen('/index.php'));
        }
        $path = '/' . trim($uri, '/');

        $headers = [];
        foreach ($_SERVER as $k => $v) {
            if (str_starts_with($k, 'HTTP_')) {
                $headers[strtolower(str_replace('_', '-', substr($k, 5)))] = (string) $v;
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }
        // Alguns Apache/CGI não repassam Authorization; .htaccess o copia para esta variável.
        if (!isset($headers['authorization']) && isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            $headers['authorization'] = (string) $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
        }

        $remote = (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
        $ip = self::clientIp($remote, $headers, $proxyMode);
        $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($headers['x-forwarded-proto'] ?? '') === 'https' && ($proxyMode !== '0' || CloudflareIps::contains($remote)));

        $body = (string) file_get_contents('php://input', false, null, 0, 1_048_577);
        $cookies = array_map('strval', array_filter($_COOKIE, 'is_string'));
        return new self($method, $path, $headers, $_GET, $body, $ip, $cookies, $base, $secure);
    }

    /** @param array<string,string> $headers */
    public static function clientIp(string $remote, array $headers, string $proxyMode): string
    {
        if ($proxyMode === 'cloudflare') {
            $cf = trim($headers['cf-connecting-ip'] ?? '');
            if ($cf !== '' && filter_var($cf, FILTER_VALIDATE_IP) && CloudflareIps::contains($remote)) {
                return $cf;
            }
            return $remote;
        }
        if ($proxyMode === '1' && isset($headers['x-forwarded-for'])) {
            $first = trim(explode(',', $headers['x-forwarded-for'])[0]);
            if (filter_var($first, FILTER_VALIDATE_IP)) {
                return $first;
            }
        }
        return $remote;
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    public function cookie(string $name): ?string
    {
        return $this->cookies[$name] ?? null;
    }

    public function bearer(): ?string
    {
        $h = $this->header('authorization');
        if ($h === null || !preg_match('/^Bearer\s+(\S+)$/i', $h, $m)) {
            return null;
        }
        return $m[1];
    }

    /** @return array<string,mixed> */
    public function json(int $maxBytes = 65536): array
    {
        if ($this->body === '') {
            return [];
        }
        if (strlen($this->body) > $maxBytes) {
            throw new ApiException(413, 'payload_too_large', 'O corpo da requisição excede o limite permitido.');
        }
        try {
            $data = json_decode($this->body, true, 64, JSON_THROW_ON_ERROR | JSON_BIGINT_AS_STRING);
        } catch (\JsonException) {
            throw new ApiException(400, 'invalid_json', 'O corpo da requisição não é um JSON válido.');
        }
        if (!is_array($data) || array_is_list($data) && $data !== []) {
            throw new ApiException(400, 'invalid_json', 'O corpo deve ser um objeto JSON.');
        }
        return $data;
    }

    /** Formulário HTML (application/x-www-form-urlencoded). @return array<string,mixed> */
    public function form(int $maxBytes = 262144): array
    {
        if ($this->body === '' || strlen($this->body) > $maxBytes) {
            return [];
        }
        parse_str($this->body, $out);
        return $out;
    }
}
