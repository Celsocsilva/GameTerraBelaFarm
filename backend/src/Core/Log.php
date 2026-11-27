<?php
declare(strict_types=1);

namespace TerraBela\Core;

/**
 * Log em arquivo diário JSONL dentro de storage/logs (fora da raiz pública).
 * Nunca registrar tokens, segredos, purchase tokens ou dados pessoais.
 */
final class Log
{
    public function __construct(private ?string $dir)
    {
    }

    /** @param array<string,mixed> $context */
    public function write(string $level, string $message, array $context = []): void
    {
        if ($this->dir === null) {
            return;
        }
        if (!is_dir($this->dir)) {
            @mkdir($this->dir, 0750, true);
        }
        $line = json_encode(
            ['ts' => gmdate('c'), 'level' => $level, 'msg' => $message] + $context,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
        @file_put_contents($this->dir . '/app-' . gmdate('Y-m-d') . '.log', $line . "\n", FILE_APPEND | LOCK_EX);
    }

    public function info(string $m, array $c = []): void
    {
        $this->write('info', $m, $c);
    }

    public function error(string $m, array $c = []): void
    {
        $this->write('error', $m, $c);
    }
}
