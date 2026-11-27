<?php
declare(strict_types=1);

/**
 * Administração por linha de comando até o painel PHP (TBF-MVP-07/09) existir.
 *   php bin/admin.php config:show
 *   php bin/admin.php config:publish caminho/config.json "descrição da mudança" [min_client] [max_client]
 *   php bin/admin.php config:retire NUMERO_DA_VERSAO          (rollback)
 *   php bin/admin.php product:add SKU consumable|non_consumable '{"currency":"gold","amount":100}'
 *   php bin/admin.php reward:grant PLAYER_ID RULE_KEY OCCURRENCE cash|gold AMOUNT [EXPIRA_EM_DIAS]
 *   php bin/admin.php stats
 */
require __DIR__ . '/_cli.php';

$app = tbf_app();
$cmd = $argv[1] ?? 'help';
$out = static fn ($v) => print(json_encode($v, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");

switch ($cmd) {
    case 'config:show':
        $out($app->remoteConfig->current(null));
        break;
    case 'config:publish':
        $payload = json_decode((string) file_get_contents($argv[2] ?? ''), true, 64, JSON_THROW_ON_ERROR);
        $v = $app->remoteConfig->publish($payload, (string) ($argv[3] ?? ''), 'cli:' . get_current_user(), $argv[4] ?? '0.0.0', $argv[5] ?? null);
        echo "Publicada versão $v\n";
        break;
    case 'config:retire':
        $app->remoteConfig->retire((int) ($argv[2] ?? 0));
        echo "Versão retirada. Agora vale:\n";
        $out($app->remoteConfig->current(null));
        break;
    case 'product:add':
        $benefit = json_decode((string) ($argv[4] ?? ''), true, 8, JSON_THROW_ON_ERROR);
        $app->db->tx(function (TerraBela\Core\Db $db) use ($argv, $benefit) {
            $sku = (string) $argv[2];
            $row = $db->one("SELECT COALESCE(MAX(benefit_version), 0) AS v FROM iap_products WHERE platform = 'google_play' AND sku = ? FOR UPDATE", [$sku]);
            $db->exec("UPDATE iap_products SET active = 0 WHERE platform = 'google_play' AND sku = ?", [$sku]);
            $db->insert(
                "INSERT INTO iap_products (platform, sku, product_type, benefit_version, benefit, active) VALUES ('google_play', ?, ?, ?, ?, 1)",
                [$sku, (string) $argv[3], (int) $row['v'] + 1, json_encode($benefit)]
            );
        });
        echo "Produto cadastrado/versionado.\n";
        break;
    case 'reward:grant':
        $bin = TerraBela\Core\Ids::uuidToBin((string) ($argv[2] ?? ''));
        $p = $bin === null ? null : $app->db->one('SELECT id FROM players WHERE public_id = ?', [$bin]);
        if ($p === null) {
            fwrite(STDERR, "Jogador não encontrado\n");
            exit(1);
        }
        $days = isset($argv[7]) ? (int) $argv[7] : null;
        $out($app->rewards->grant((int) $p['id'], (string) $argv[3], (string) $argv[4], (string) $argv[5], (int) $argv[6], null, $days === null ? null : $days * 86400));
        break;
    case 'stats':
        $db = $app->db;
        $out([
            'players' => (int) $db->one('SELECT COUNT(*) n FROM players')['n'],
            'active_24h' => (int) $db->one('SELECT COUNT(*) n FROM players WHERE last_seen_at >= ?', [$app->clock->sql(-86400)])['n'],
            'saves' => (int) $db->one('SELECT COUNT(*) n FROM player_saves')['n'],
            'ledger_entries' => (int) $db->one('SELECT COUNT(*) n FROM economy_ledger')['n'],
            'iap_granted' => (int) $db->one("SELECT COUNT(*) n FROM iap_transactions WHERE state = 'granted'")['n'],
        ]);
        break;
    default:
        echo file_get_contents(__FILE__, false, null, 0, 900);
}
