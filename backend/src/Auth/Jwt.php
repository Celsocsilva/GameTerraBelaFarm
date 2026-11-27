<?php
declare(strict_types=1);

namespace TerraBela\Auth;

use TerraBela\Core\Ids;

/** JWT RS256 mínimo (verificação com JWK e assinatura com chave PEM), sem bibliotecas externas. */
final class Jwt
{
    /** @return array{header:array<string,mixed>,payload:array<string,mixed>,signing_input:string,signature:string} */
    public static function decode(string $jwt): array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) {
            throw new \InvalidArgumentException('JWT malformado');
        }
        $header = json_decode((string) Ids::b64urlDecode($parts[0]), true);
        $payload = json_decode((string) Ids::b64urlDecode($parts[1]), true);
        $sig = Ids::b64urlDecode($parts[2]);
        if (!is_array($header) || !is_array($payload) || $sig === false) {
            throw new \InvalidArgumentException('JWT malformado');
        }
        return ['header' => $header, 'payload' => $payload, 'signing_input' => $parts[0] . '.' . $parts[1], 'signature' => $sig];
    }

    /** @param array<string,mixed> $jwk chave RSA com n e e em base64url */
    public static function verifyRs256(string $signingInput, string $signature, array $jwk): bool
    {
        if (($jwk['kty'] ?? '') !== 'RSA' || !isset($jwk['n'], $jwk['e'])) {
            return false;
        }
        $pem = self::rsaJwkToPem((string) $jwk['n'], (string) $jwk['e']);
        $key = openssl_pkey_get_public($pem);
        if ($key === false) {
            return false;
        }
        return openssl_verify($signingInput, $signature, $key, OPENSSL_ALGO_SHA256) === 1;
    }

    /** @param array<string,mixed> $claims */
    public static function signRs256(array $claims, string $privateKeyPem, ?string $kid = null): string
    {
        $header = ['alg' => 'RS256', 'typ' => 'JWT'];
        if ($kid !== null) {
            $header['kid'] = $kid;
        }
        $input = Ids::b64urlEncode(json_encode($header, JSON_UNESCAPED_SLASHES))
            . '.' . Ids::b64urlEncode(json_encode($claims, JSON_UNESCAPED_SLASHES));
        $key = openssl_pkey_get_private($privateKeyPem);
        if ($key === false || !openssl_sign($input, $sig, $key, OPENSSL_ALGO_SHA256)) {
            throw new \RuntimeException('Não foi possível assinar o JWT');
        }
        return $input . '.' . Ids::b64urlEncode($sig);
    }

    public static function rsaJwkToPem(string $n, string $e): string
    {
        $mod = (string) Ids::b64urlDecode($n);
        $exp = (string) Ids::b64urlDecode($e);
        $rsaKey = self::der(0x30, self::derInt($mod) . self::derInt($exp));
        $algo = self::der(0x30, self::der(0x06, "\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01") . "\x05\x00");
        $spki = self::der(0x30, $algo . self::der(0x03, "\x00" . $rsaKey));
        return "-----BEGIN PUBLIC KEY-----\n" . chunk_split(base64_encode($spki), 64, "\n") . "-----END PUBLIC KEY-----\n";
    }

    private static function derInt(string $bytes): string
    {
        $bytes = ltrim($bytes, "\x00");
        if ($bytes === '' || (ord($bytes[0]) & 0x80)) {
            $bytes = "\x00" . $bytes;
        }
        return self::der(0x02, $bytes);
    }

    private static function der(int $tag, string $value): string
    {
        $len = strlen($value);
        if ($len < 0x80) {
            $l = chr($len);
        } else {
            $lb = ltrim(pack('N', $len), "\x00");
            $l = chr(0x80 | strlen($lb)) . $lb;
        }
        return chr($tag) . $l . $value;
    }
}
