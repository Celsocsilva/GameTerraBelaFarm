<?php
declare(strict_types=1);

namespace TerraBela\Core;

/** Identificadores opacos, tokens e hashes. */
final class Ids
{
    /** UUID v4 em binário (16 bytes). */
    public static function uuidBin(): string
    {
        $b = random_bytes(16);
        $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
        $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
        return $b;
    }

    public static function binToUuid(string $bin): string
    {
        $h = bin2hex($bin);
        return sprintf('%s-%s-%s-%s-%s', substr($h, 0, 8), substr($h, 8, 4), substr($h, 12, 4), substr($h, 16, 4), substr($h, 20));
    }

    public static function uuidToBin(string $uuid): ?string
    {
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $uuid)) {
            return null;
        }
        return hex2bin(str_replace('-', '', strtolower($uuid))) ?: null;
    }

    /** Token aleatório de 256 bits em base64url com prefixo legível. */
    public static function token(string $prefix): string
    {
        return $prefix . rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }

    public static function requestId(): string
    {
        return bin2hex(random_bytes(8));
    }

    public static function b64urlDecode(string $s): string|false
    {
        $s = strtr($s, '-_', '+/');
        $pad = strlen($s) % 4;
        if ($pad) {
            $s .= str_repeat('=', 4 - $pad);
        }
        return base64_decode($s, true);
    }

    public static function b64urlEncode(string $s): string
    {
        return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    }
}
