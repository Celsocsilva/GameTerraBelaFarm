<?php
declare(strict_types=1);

namespace TerraBela\Http;

/**
 * Faixas de IP publicadas pela Cloudflare (https://www.cloudflare.com/ips/).
 * Só confiamos em CF-Connecting-IP quando a conexão chega de uma destas faixas;
 * assim ninguém forja o IP chamando o servidor de origem direto.
 * Revisar a lista a cada poucos meses (mudanças são raras e anunciadas).
 */
final class CloudflareIps
{
    public const RANGES = [
        '173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22', '141.101.64.0/18',
        '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20', '197.234.240.0/22', '198.41.128.0/17',
        '162.158.0.0/15', '104.16.0.0/13', '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22',
        '2400:cb00::/32', '2606:4700::/32', '2803:f800::/32', '2405:b500::/32', '2405:8100::/32',
        '2a06:98c0::/29', '2c0f:f248::/32',
    ];

    public static function contains(string $ip): bool
    {
        $bin = @inet_pton($ip);
        if ($bin === false) {
            return false;
        }
        foreach (self::RANGES as $cidr) {
            [$net, $bits] = explode('/', $cidr);
            $netBin = inet_pton($net);
            if (strlen($netBin) !== strlen($bin)) {
                continue;
            }
            $bits = (int) $bits;
            $bytes = intdiv($bits, 8);
            if (substr($bin, 0, $bytes) !== substr($netBin, 0, $bytes)) {
                continue;
            }
            $rest = $bits % 8;
            if ($rest === 0) {
                return true;
            }
            $mask = chr((0xff << (8 - $rest)) & 0xff);
            if ((($bin[$bytes] & $mask) === ($netBin[$bytes] & $mask))) {
                return true;
            }
        }
        return false;
    }
}
