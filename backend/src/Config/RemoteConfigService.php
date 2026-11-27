<?php
declare(strict_types=1);

namespace TerraBela\Config;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;

/**
 * Remote Config versionado: rascunho → publicado; rollback = retirar a versão atual,
 * voltando a valer a maior versão publicada anterior compatível com o cliente.
 */
final class RemoteConfigService
{
    /** @var array<string,array<string,mixed>> */
    private array $cache = [];

    public function __construct(private Db $db, private Clock $clock, private string $environment)
    {
    }

    /** @return array{version:int,checksum:string,payload:array<string,mixed>,published_at:?string}|null */
    public function current(?string $clientVersion): ?array
    {
        $key = $clientVersion ?? '*';
        if (isset($this->cache[$key])) {
            return $this->cache[$key];
        }
        $rows = $this->db->all(
            "SELECT version_number, min_client_version, max_client_version, payload, checksum, published_at
               FROM remote_config_versions
              WHERE environment = ? AND status = 'published'
              ORDER BY version_number DESC LIMIT 20",
            [$this->environment]
        );
        foreach ($rows as $r) {
            if ($clientVersion !== null) {
                if (version_compare($clientVersion, $r['min_client_version'], '<')) {
                    continue;
                }
                if ($r['max_client_version'] !== null && version_compare($clientVersion, $r['max_client_version'], '>')) {
                    continue;
                }
            }
            return $this->cache[$key] = [
                'version' => (int) $r['version_number'],
                'checksum' => $r['checksum'],
                'payload' => json_decode($r['payload'], true),
                'published_at' => Clock::iso($r['published_at']),
            ];
        }
        return null;
    }

    /** Valor por caminho com ponto (ex.: economy.client_credit.cash.max_per_day). */
    public function value(string $path, mixed $default = null): mixed
    {
        $cfg = $this->current(null);
        $node = $cfg['payload'] ?? [];
        foreach (explode('.', $path) as $part) {
            if (!is_array($node) || !array_key_exists($part, $node)) {
                return $default;
            }
            $node = $node[$part];
        }
        return $node;
    }

    public static function checksum(array $payload): string
    {
        return hash('sha256', json_encode(self::canonical($payload), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    private static function canonical(mixed $v): mixed
    {
        if (is_array($v) && !array_is_list($v)) {
            ksort($v);
        }
        return is_array($v) ? array_map([self::class, 'canonical'], $v) : $v;
    }

    /** Valida o schema mínimo antes de gravar (tipos e faixas seguras). */
    public static function validate(array $payload): void
    {
        $errors = [];
        foreach (['maintenance', 'features', 'economy', 'sync'] as $section) {
            if (!isset($payload[$section]) || !is_array($payload[$section])) {
                $errors[] = "seção obrigatória: $section";
            }
        }
        if (!is_bool($payload['maintenance']['enabled'] ?? null)) {
            $errors[] = 'maintenance.enabled deve ser booleano';
        }
        foreach (($payload['features'] ?? []) as $k => $v) {
            if (!is_bool($v)) {
                $errors[] = "features.$k deve ser booleano";
            }
        }
        $cash = $payload['economy']['client_credit']['cash'] ?? null;
        if (!is_array($cash) || !is_int($cash['max_per_operation'] ?? null) || !is_int($cash['max_per_day'] ?? null)
            || $cash['max_per_operation'] < 0 || $cash['max_per_operation'] > 10_000_000
            || $cash['max_per_day'] < $cash['max_per_operation'] || $cash['max_per_day'] > 1_000_000_000
            || !is_array($cash['reasons'] ?? null)) {
            $errors[] = 'economy.client_credit.cash precisa de reasons, max_per_operation e max_per_day inteiros e coerentes';
        }
        if (isset($payload['economy']['client_credit']['gold'])) {
            $errors[] = 'gold nunca pode ser creditado pelo cliente (somente IAP/recompensa no servidor)';
        }
        if (!is_array($payload['economy']['client_debit_reasons'] ?? null)) {
            $errors[] = 'economy.client_debit_reasons deve ser lista';
        }
        $max = $payload['sync']['max_snapshot_bytes'] ?? null;
        if (!is_int($max) || $max < 1024 || $max > 1_048_576) {
            $errors[] = 'sync.max_snapshot_bytes entre 1024 e 1048576';
        }
        if (json_encode($payload) !== false && preg_match('/secret|password|private_key|api_key/i', (string) json_encode($payload))) {
            $errors[] = 'o payload parece conter segredo; Remote Config é público';
        }
        if ($errors) {
            throw new \InvalidArgumentException(implode('; ', $errors));
        }
    }

    /** Publica nova versão (usado pelo bin/config.php e futuramente pelo painel). */
    public function publish(array $payload, string $changelog, string $by, string $minClient = '0.0.0', ?string $maxClient = null): int
    {
        self::validate($payload);
        if (trim($changelog) === '') {
            throw new \InvalidArgumentException('changelog obrigatório');
        }
        return $this->db->tx(function (Db $db) use ($payload, $changelog, $by, $minClient, $maxClient) {
            $row = $db->one('SELECT COALESCE(MAX(version_number), 0) AS v FROM remote_config_versions WHERE environment = ? FOR UPDATE', [$this->environment]);
            $next = (int) $row['v'] + 1;
            $db->insert(
                "INSERT INTO remote_config_versions (environment, version_number, status, min_client_version, max_client_version, payload, checksum, changelog, created_by, created_at, published_at)
                 VALUES (?, ?, 'published', ?, ?, ?, ?, ?, ?, ?, ?)",
                [$this->environment, $next, $minClient, $maxClient, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), self::checksum($payload), mb_substr($changelog, 0, 500), $by, $this->clock->sql(), $this->clock->sql()]
            );
            $this->cache = [];
            return $next;
        });
    }

    /** Rollback: retira a versão publicada indicada. */
    public function retire(int $version): void
    {
        $this->db->exec(
            "UPDATE remote_config_versions SET status = 'retired' WHERE environment = ? AND version_number = ? AND status = 'published'",
            [$this->environment, $version]
        );
        $this->cache = [];
    }
}
