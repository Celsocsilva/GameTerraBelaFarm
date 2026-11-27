<?php
declare(strict_types=1);

namespace TerraBela\Http;

final class Response
{
    /** @param array<string,string> $headers */
    public function __construct(
        public int $status = 200,
        public string $body = '',
        public array $headers = [],
        /** @var list<string> cabeçalhos Set-Cookie completos */
        public array $cookies = [],
    ) {
    }

    public static function json(mixed $data, int $status = 200, array $headers = []): self
    {
        $body = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR);
        return new self($status, $body, $headers + ['Content-Type' => 'application/json; charset=utf-8']);
    }

    /** @return array<string,mixed> */
    public function data(): array
    {
        return $this->body === '' ? [] : (array) json_decode($this->body, true);
    }

    public function send(): void
    {
        http_response_code($this->status);
        foreach ($this->headers as $k => $v) {
            header($k . ': ' . $v);
        }
        foreach ($this->cookies as $c) {
            header('Set-Cookie: ' . $c, false);
        }
        echo $this->body;
    }
}
