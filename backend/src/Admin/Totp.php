<?php
declare(strict_types=1);

namespace TerraBela\Admin;

/** TOTP RFC 6238 (SHA-1, 6 dígitos, passo de 30 s) compatível com Google Authenticator, Authy e 1Password. */
final class Totp
{
    private const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    public static function newSecret(): string
    {
        return self::base32Encode(random_bytes(20));
    }

    public static function code(string $secret, int $time, int $offsetSteps = 0): string
    {
        $key = self::base32Decode($secret);
        $counter = intdiv($time, 30) + $offsetSteps;
        $bin = pack('N2', ($counter >> 32) & 0xffffffff, $counter & 0xffffffff);
        $h = hash_hmac('sha1', $bin, $key, true);
        $o = ord($h[19]) & 0x0f;
        $num = ((ord($h[$o]) & 0x7f) << 24) | (ord($h[$o + 1]) << 16) | (ord($h[$o + 2]) << 8) | ord($h[$o + 3]);
        return str_pad((string) ($num % 1_000_000), 6, '0', STR_PAD_LEFT);
    }

    /** Aceita o passo atual e um vizinho de cada lado (relógio do celular adiantado/atrasado). */
    public static function verify(string $secret, string $code, int $time): bool
    {
        return self::matchStep($secret, $code, $time) !== null;
    }

    /** Passo (unix/30) do código aceito, para impedir reutilização; null se inválido. */
    public static function matchStep(string $secret, string $code, int $time): ?int
    {
        $code = preg_replace('/\s+/', '', $code) ?? '';
        if (!preg_match('/^\d{6}$/', $code)) {
            return null;
        }
        foreach ([-1, 0, 1] as $w) {
            if (hash_equals(self::code($secret, $time, $w), $code)) {
                return intdiv($time, 30) + $w;
            }
        }
        return null;
    }

    public static function uri(string $secret, string $account, string $issuer = 'TerraBela Farm'): string
    {
        return 'otpauth://totp/' . rawurlencode($issuer . ':' . $account) . '?secret=' . $secret . '&issuer=' . rawurlencode($issuer) . '&digits=6&period=30';
    }

    public static function base32Encode(string $bin): string
    {
        $bits = '';
        foreach (str_split($bin) as $c) {
            $bits .= str_pad(decbin(ord($c)), 8, '0', STR_PAD_LEFT);
        }
        $out = '';
        foreach (str_split($bits, 5) as $chunk) {
            $out .= self::ALPHABET[bindec(str_pad($chunk, 5, '0'))];
        }
        return $out;
    }

    public static function base32Decode(string $b32): string
    {
        $b32 = strtoupper(preg_replace('/[\s=]+/', '', $b32) ?? '');
        $bits = '';
        foreach (str_split($b32) as $c) {
            $i = strpos(self::ALPHABET, $c);
            if ($i === false) {
                throw new \InvalidArgumentException('Segredo Base32 inválido');
            }
            $bits .= str_pad(decbin($i), 5, '0', STR_PAD_LEFT);
        }
        $out = '';
        foreach (str_split($bits, 8) as $byte) {
            if (strlen($byte) === 8) {
                $out .= chr(bindec($byte));
            }
        }
        return $out;
    }
}
