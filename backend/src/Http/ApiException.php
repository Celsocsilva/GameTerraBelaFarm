<?php
declare(strict_types=1);

namespace TerraBela\Http;

/** Erro de API com código estável e mensagem não sensível. */
final class ApiException extends \RuntimeException
{
    /** @param array<string,mixed> $details */
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly array $details = [],
    ) {
        parent::__construct($message);
    }
}
