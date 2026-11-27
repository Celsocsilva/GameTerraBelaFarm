<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Http\ApiException;

/** Validação de entrada no servidor com mensagens estáveis. */
final class V
{
    private static function fail(string $field, string $why): never
    {
        throw new ApiException(422, 'validation_failed', "Campo inválido: $field ($why).", ['field' => $field]);
    }

    public static function str(array $in, string $field, int $min = 1, int $max = 255, ?string $pattern = null): string
    {
        $v = $in[$field] ?? null;
        if (!is_string($v)) {
            self::fail($field, 'texto obrigatório');
        }
        $len = mb_strlen($v);
        if ($len < $min || $len > $max) {
            self::fail($field, "tamanho entre $min e $max");
        }
        if ($pattern !== null && !preg_match($pattern, $v)) {
            self::fail($field, 'formato');
        }
        return $v;
    }

    public static function optStr(array $in, string $field, int $max = 255, ?string $pattern = null): ?string
    {
        if (!isset($in[$field]) || $in[$field] === '') {
            return null;
        }
        return self::str($in, $field, 1, $max, $pattern);
    }

    public static function int(array $in, string $field, int $min, int $max): int
    {
        $v = $in[$field] ?? null;
        if (is_string($v) && preg_match('/^-?\d+$/', $v)) {
            $v = (int) $v;
        }
        if (!is_int($v)) {
            self::fail($field, 'inteiro obrigatório');
        }
        if ($v < $min || $v > $max) {
            self::fail($field, "entre $min e $max");
        }
        return $v;
    }

    public static function bool(array $in, string $field): bool
    {
        $v = $in[$field] ?? null;
        if (!is_bool($v)) {
            self::fail($field, 'booleano obrigatório');
        }
        return $v;
    }

    /** @param list<string> $allowed */
    public static function enum(array $in, string $field, array $allowed): string
    {
        $v = $in[$field] ?? null;
        if (!is_string($v) || !in_array($v, $allowed, true)) {
            self::fail($field, 'valores aceitos: ' . implode(', ', $allowed));
        }
        return $v;
    }

    /** Identificador gerado pelo app (operation_id, event_id...). */
    public static function opId(array $in, string $field): string
    {
        return self::str($in, $field, 8, 64, '/^[A-Za-z0-9_.:-]+$/');
    }

    /** @return list<mixed> */
    public static function list(array $in, string $field, int $min, int $max): array
    {
        $v = $in[$field] ?? null;
        if (!is_array($v) || !array_is_list($v)) {
            self::fail($field, 'lista obrigatória');
        }
        if (count($v) < $min || count($v) > $max) {
            self::fail($field, "entre $min e $max itens");
        }
        return $v;
    }

    /** Data ISO-8601 → DATETIME(6) UTC. */
    public static function optTime(array $in, string $field): ?string
    {
        if (!isset($in[$field])) {
            return null;
        }
        $v = $in[$field];
        if (!is_string($v) || strlen($v) > 40) {
            self::fail($field, 'data ISO-8601');
        }
        try {
            $dt = new \DateTimeImmutable($v);
        } catch (\Exception) {
            self::fail($field, 'data ISO-8601');
        }
        return $dt->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s.u');
    }
}
