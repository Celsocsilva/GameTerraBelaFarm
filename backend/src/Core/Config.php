<?php
declare(strict_types=1);

namespace TerraBela\Core;

/**
 * Configuração lida de um arquivo .env FORA da raiz pública.
 * Variáveis de ambiente reais (getenv) têm prioridade sobre o arquivo.
 */
final class Config
{
    /** @param array<string,string> $values */
    public function __construct(private array $values)
    {
    }

    public static function load(string $envFile): self
    {
        $values = [];
        if (is_file($envFile)) {
            $lines = file($envFile, FILE_IGNORE_NEW_LINES) ?: [];
            foreach ($lines as $line) {
                $line = trim($line);
                if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                    continue;
                }
                [$key, $value] = explode('=', $line, 2);
                $key = trim($key);
                $value = trim($value);
                if (strlen($value) >= 2 && ($value[0] === '"' || $value[0] === "'") && $value[-1] === $value[0]) {
                    $value = substr($value, 1, -1);
                }
                $values[$key] = $value;
            }
        }
        foreach ($values as $key => $_) {
            $env = getenv($key);
            if ($env !== false) {
                $values[$key] = $env;
            }
        }
        return new self($values);
    }

    public function str(string $key, ?string $default = null): string
    {
        $v = $this->values[$key] ?? getenv($key);
        if ($v === false || $v === null || $v === '') {
            if ($default === null) {
                throw new \RuntimeException("Configuração obrigatória ausente: $key");
            }
            return $default;
        }
        return (string) $v;
    }

    public function optional(string $key): ?string
    {
        $v = $this->values[$key] ?? getenv($key);
        return ($v === false || $v === null || $v === '') ? null : (string) $v;
    }

    public function int(string $key, int $default): int
    {
        $v = $this->optional($key);
        return $v === null ? $default : (int) $v;
    }

    public function bool(string $key, bool $default): bool
    {
        $v = $this->optional($key);
        if ($v === null) {
            return $default;
        }
        return in_array(strtolower($v), ['1', 'true', 'yes', 'on'], true);
    }

    /** @return list<string> */
    public function list(string $key): array
    {
        $v = $this->optional($key);
        if ($v === null) {
            return [];
        }
        return array_values(array_filter(array_map('trim', explode(',', $v)), static fn ($s) => $s !== ''));
    }

    public function with(string $key, string $value): self
    {
        $copy = $this->values;
        $copy[$key] = $value;
        return new self($copy);
    }
}
