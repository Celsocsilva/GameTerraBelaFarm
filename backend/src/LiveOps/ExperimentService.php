<?php
declare(strict_types=1);

namespace TerraBela\LiveOps;

use TerraBela\Config\RemoteConfigService;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;

/**
 * Testes A/B sobre o Remote Config (TBF-MVP-13a).
 * Divisão determinística: bucket = sha256(sal:chave:id_público) mod 10000. O primeiro hash decide se o
 * jogador entra (traffic_percent); um segundo hash escolhe a variante pelos pesos. A variante fica gravada
 * na primeira entrega e não muda depois, mesmo se os pesos forem editados.
 * As variantes só sobrescrevem features, routes e tuning: limites de economia, manutenção e sync
 * continuam valendo do Remote Config publicado, porque o servidor os usa para validar o cliente.
 */
final class ExperimentService
{
    public const OVERRIDABLE = ['features', 'routes', 'tuning'];
    public const MAX_VARIANTS = 6;
    public const MAX_RUNNING = 10;

    public function __construct(private Db $db, private Clock $clock, private RemoteConfigService $config)
    {
    }

    /** Valida e normaliza a definição vinda do backoffice. @return list<array{key:string,weight:int,overrides:array}> */
    public function validateVariants(mixed $variants, ?array $basePayload = null): array
    {
        if (!is_array($variants) || !array_is_list($variants) || count($variants) < 2 || count($variants) > self::MAX_VARIANTS) {
            throw new \InvalidArgumentException('Informe de 2 a ' . self::MAX_VARIANTS . ' variantes (lista JSON).');
        }
        $out = [];
        $seen = [];
        $total = 0;
        foreach ($variants as $i => $v) {
            $key = is_array($v) ? ($v['key'] ?? null) : null;
            if (!is_string($key) || !preg_match('/^[a-z][a-z0-9_]{0,31}$/', $key) || isset($seen[$key])) {
                throw new \InvalidArgumentException("Variante $i: key obrigatória, única, minúscula (a-z, 0-9, _).");
            }
            $seen[$key] = true;
            $weight = $v['weight'] ?? null;
            if (!is_int($weight) || $weight < 0 || $weight > 10000) {
                throw new \InvalidArgumentException("Variante $key: weight inteiro entre 0 e 10000.");
            }
            $total += $weight;
            $ov = $v['overrides'] ?? [];
            if (!is_array($ov) || ($ov !== [] && array_is_list($ov))) {
                throw new \InvalidArgumentException("Variante $key: overrides deve ser um objeto.");
            }
            foreach (array_keys($ov) as $section) {
                if (!in_array($section, self::OVERRIDABLE, true) || !is_array($ov[$section])) {
                    throw new \InvalidArgumentException("Variante $key: só pode sobrescrever " . implode(', ', self::OVERRIDABLE) . " (objetos). Economia, manutenção e sync ficam no servidor.");
                }
            }
            if (strlen((string) json_encode($ov)) > 8192) {
                throw new \InvalidArgumentException("Variante $key: overrides acima de 8 KB.");
            }
            if ($basePayload !== null) {
                try {
                    RemoteConfigService::validate(self::merge($basePayload, $ov));
                } catch (\InvalidArgumentException $e) {
                    throw new \InvalidArgumentException("Variante $key gera Remote Config inválido: " . $e->getMessage());
                }
            }
            $out[] = ['key' => $key, 'weight' => $weight, 'overrides' => $ov];
        }
        if ($total <= 0) {
            throw new \InvalidArgumentException('A soma dos pesos precisa ser maior que zero.');
        }
        return $out;
    }

    /** @param array<string,mixed> $f campos do formulário */
    public function create(array $f, ?int $adminId): int
    {
        $key = trim((string) ($f['experiment_key'] ?? ''));
        if (!preg_match('/^[a-z][a-z0-9_]{2,47}$/', $key)) {
            throw new \InvalidArgumentException('Chave: 3 a 48 caracteres, minúsculas, números e _.');
        }
        $name = trim((string) ($f['name'] ?? ''));
        if ($name === '' || mb_strlen($name) > 120) {
            throw new \InvalidArgumentException('Nome obrigatório (até 120 caracteres).');
        }
        $traffic = (int) ($f['traffic_percent'] ?? 100);
        if ($traffic < 1 || $traffic > 100) {
            throw new \InvalidArgumentException('Tráfego entre 1 e 100%.');
        }
        $goal = trim((string) ($f['goal_event'] ?? ''));
        if ($goal !== '' && !preg_match('/^[a-z][a-z0-9_]{1,39}$/', $goal)) {
            throw new \InvalidArgumentException('Evento de meta inválido.');
        }
        $minClient = trim((string) ($f['min_client_version'] ?? '')) ?: '0.0.0';
        if (!preg_match('/^\d+(\.\d+){0,3}$/', $minClient)) {
            throw new \InvalidArgumentException('Versão mínima do app inválida (ex.: 0.4.0).');
        }
        $raw = is_string($f['variants'] ?? null) ? json_decode($f['variants'], true, 32) : ($f['variants'] ?? null);
        $base = $this->config->current(null)['payload'] ?? null;
        $variants = $this->validateVariants($raw, $base);
        if ($this->db->one('SELECT id FROM experiments WHERE experiment_key = ?', [$key]) !== null) {
            throw new \InvalidArgumentException('Já existe um experimento com essa chave; use outra (ex.: com sufixo _v2).');
        }
        return $this->db->insert(
            'INSERT INTO experiments (experiment_key, name, hypothesis, status, traffic_percent, variants, salt, goal_event, min_client_version, created_by, created_at)
             VALUES (?, ?, ?, \'draft\', ?, ?, ?, ?, ?, ?, ?)',
            [$key, $name, mb_substr(trim((string) ($f['hypothesis'] ?? '')), 0, 500) ?: null, $traffic,
                json_encode($variants, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), bin2hex(random_bytes(8)), $goal ?: null, $minClient, $adminId, $this->clock->sql()]
        );
    }

    public function start(int $id): void
    {
        $e = $this->get($id);
        if ($e['status'] !== 'draft') {
            throw new \InvalidArgumentException('Só um rascunho pode ser iniciado.');
        }
        $running = (int) $this->db->one("SELECT COUNT(*) n FROM experiments WHERE status = 'running'")['n'];
        if ($running >= self::MAX_RUNNING) {
            throw new \InvalidArgumentException('Já há ' . self::MAX_RUNNING . ' experimentos em andamento; encerre algum antes.');
        }
        // revalida contra o Remote Config atual: ele pode ter mudado desde o rascunho
        $this->validateVariants(json_decode($e['variants'], true), $this->config->current(null)['payload'] ?? null);
        $this->db->exec("UPDATE experiments SET status = 'running', started_at = ? WHERE id = ? AND status = 'draft'", [$this->clock->sql(), $id]);
    }

    public function stop(int $id, ?string $winner): void
    {
        $e = $this->get($id);
        if ($e['status'] !== 'running') {
            throw new \InvalidArgumentException('Só um experimento em andamento pode ser encerrado.');
        }
        $keys = array_column(json_decode($e['variants'], true), 'key');
        if ($winner !== null && !in_array($winner, $keys, true)) {
            throw new \InvalidArgumentException('Variante vencedora inexistente.');
        }
        $this->db->exec("UPDATE experiments SET status = 'stopped', stopped_at = ?, winner_variant = ? WHERE id = ? AND status = 'running'", [$this->clock->sql(), $winner, $id]);
    }

    /** @return array<string,mixed> */
    public function get(int $id): array
    {
        $e = $this->db->one('SELECT * FROM experiments WHERE id = ?', [$id]);
        if ($e === null) {
            throw new \InvalidArgumentException('Experimento não encontrado.');
        }
        return $e;
    }

    /** Número de 0 a 9999 estável para (sal, chave, jogador, fase). */
    public static function bucket(string $salt, string $key, string $playerPublicHex, string $phase): int
    {
        return (int) (hexdec(substr(hash('sha256', "$salt:$key:$playerPublicHex:$phase"), 0, 8)) % 10000);
    }

    /** Variante pelos pesos, ou null quando o jogador fica fora do tráfego. */
    public static function pick(array $e, array $variants, string $playerPublicHex): ?string
    {
        if (self::bucket($e['salt'], $e['experiment_key'], $playerPublicHex, 'traffic') >= (int) $e['traffic_percent'] * 100) {
            return null;
        }
        $total = array_sum(array_column($variants, 'weight'));
        $b = self::bucket($e['salt'], $e['experiment_key'], $playerPublicHex, 'variant') % $total;
        foreach ($variants as $v) {
            if ($b < $v['weight']) {
                return $v['key'];
            }
            $b -= $v['weight'];
        }
        return null;
    }

    /**
     * Atribuições do jogador nos experimentos em andamento, gravando a exposição.
     * @return array{experiments:list<array{key:string,variant:string,overrides:array}>,config:?array,config_version:?int}
     */
    public function forPlayer(int $playerId, ?string $clientVersion): array
    {
        $p = $this->db->one('SELECT public_id FROM players WHERE id = ?', [$playerId]);
        $cfg = $this->config->current($clientVersion);
        $out = ['experiments' => [], 'config' => $cfg['payload'] ?? null, 'config_version' => $cfg['version'] ?? null];
        if ($p === null) {
            return $out;
        }
        $hex = bin2hex($p['public_id']);
        $now = $this->clock->sql();
        $running = $this->db->all("SELECT * FROM experiments WHERE status = 'running' ORDER BY id LIMIT " . self::MAX_RUNNING);
        $existing = [];
        if ($running !== []) {
            $ids = array_map(static fn ($e) => (int) $e['id'], $running);
            foreach ($this->db->all('SELECT experiment_id, variant_key FROM experiment_assignments WHERE player_id = ? AND experiment_id IN (' . implode(',', $ids) . ')', [$playerId]) as $a) {
                $existing[(int) $a['experiment_id']] = $a['variant_key'];
            }
        }
        $touched = [];
        foreach ($running as $e) {
            if ($clientVersion !== null && version_compare($clientVersion, $e['min_client_version'], '<')) {
                continue;
            }
            $variants = json_decode($e['variants'], true);
            $byKey = array_column($variants, null, 'key');
            $variant = $existing[(int) $e['id']] ?? self::pick($e, $variants, $hex);
            if ($variant === null || !isset($byKey[$variant])) {
                continue;
            }
            if (!isset($existing[(int) $e['id']])) {
                $this->db->exec(
                    'INSERT INTO experiment_assignments (experiment_id, player_id, variant_key, first_exposed_at, last_exposed_at) VALUES (?, ?, ?, ?, ?)
                     ON DUPLICATE KEY UPDATE last_exposed_at = VALUES(last_exposed_at)',
                    [(int) $e['id'], $playerId, $variant, $now, $now]
                );
            } else {
                $touched[] = (int) $e['id'];
            }
            $ov = $byKey[$variant]['overrides'];
            $out['experiments'][] = ['key' => $e['experiment_key'], 'variant' => $variant, 'overrides' => $ov === [] ? new \stdClass() : $ov];
            if ($out['config'] !== null) {
                $out['config'] = self::merge($out['config'], $ov);
            }
        }
        if ($touched !== []) {
            $this->db->exec('UPDATE experiment_assignments SET last_exposed_at = ? WHERE player_id = ? AND experiment_id IN (' . implode(',', $touched) . ')', [$now, $playerId]);
        }
        if ($out['config'] !== null) {
            // segurança extra: se algo sair inválido (config base mudou), o app recebe a base sem experimentos
            try {
                RemoteConfigService::validate($out['config']);
            } catch (\InvalidArgumentException) {
                $out['config'] = $cfg['payload'];
            }
        }
        return $out;
    }

    /** Mescla objetos recursivamente; listas são substituídas inteiras. */
    public static function merge(array $base, array $over): array
    {
        foreach ($over as $k => $v) {
            if (is_array($v) && !array_is_list($v) && isset($base[$k]) && is_array($base[$k]) && !array_is_list($base[$k])) {
                $base[$k] = self::merge($base[$k], $v);
            } else {
                $base[$k] = $v;
            }
        }
        return $base;
    }

    /**
     * Resultados por variante: expostos, retenção D1/D7 (voltou a jogar entre 24-48 h / 7-8 dias depois
     * da primeira exposição, entre quem já completou a janela), compradores e conversão no evento de meta.
     * @return list<array<string,mixed>>
     */
    public function results(int $id): array
    {
        $e = $this->get($id);
        $now = $this->clock->sql();
        $end = $e['stopped_at'] ?? $now;
        $rows = [];
        foreach (json_decode($e['variants'], true) as $v) {
            $r = $this->db->one(
                "SELECT COUNT(*) exposed,
                        SUM(a.first_exposed_at <= ? - INTERVAL 2 DAY) d1_base,
                        SUM(a.first_exposed_at <= ? - INTERVAL 2 DAY AND EXISTS (SELECT 1 FROM game_events g WHERE g.player_id = a.player_id
                              AND g.occurred_at >= a.first_exposed_at + INTERVAL 1 DAY AND g.occurred_at < a.first_exposed_at + INTERVAL 2 DAY)) d1,
                        SUM(a.first_exposed_at <= ? - INTERVAL 8 DAY) d7_base,
                        SUM(a.first_exposed_at <= ? - INTERVAL 8 DAY AND EXISTS (SELECT 1 FROM game_events g WHERE g.player_id = a.player_id
                              AND g.occurred_at >= a.first_exposed_at + INTERVAL 7 DAY AND g.occurred_at < a.first_exposed_at + INTERVAL 8 DAY)) d7,
                        SUM(EXISTS (SELECT 1 FROM iap_transactions t WHERE t.player_id = a.player_id AND t.granted_at IS NOT NULL
                              AND t.created_at >= a.first_exposed_at AND t.created_at <= ?)) buyers,
                        SUM(EXISTS (SELECT 1 FROM game_events g WHERE g.player_id = a.player_id AND g.event_name = ?
                              AND g.occurred_at >= a.first_exposed_at AND g.occurred_at <= ?)) converted
                   FROM experiment_assignments a WHERE a.experiment_id = ? AND a.variant_key = ?",
                [$now, $now, $now, $now, $end, (string) ($e['goal_event'] ?? ''), $end, $id, $v['key']]
            );
            $n = (int) $r['exposed'];
            $pct = static fn ($a, $b) => (int) $b > 0 ? round(100 * (int) $a / (int) $b, 1) : null;
            $rows[] = [
                'variant' => $v['key'], 'weight' => $v['weight'], 'exposed' => $n,
                'd1_base' => (int) $r['d1_base'], 'd1_pct' => $pct($r['d1'], $r['d1_base']),
                'd7_base' => (int) $r['d7_base'], 'd7_pct' => $pct($r['d7'], $r['d7_base']),
                'buyers' => (int) $r['buyers'], 'buyers_pct' => $pct($r['buyers'], $n),
                'converted' => $e['goal_event'] === null ? null : (int) $r['converted'],
                'converted_pct' => $e['goal_event'] === null ? null : $pct($r['converted'], $n),
            ];
        }
        return $rows;
    }
}
