<?php
declare(strict_types=1);

namespace TerraBela\Players;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;

/**
 * Exportação dos dados de um jogador (LGPD art. 18, II e V: acesso e portabilidade).
 * Inclui tudo o que o servidor guarda sobre a conta, exceto segredos de autenticação
 * (hashes de token/segredo, tokens de compra e de push), que não identificam nada para o titular.
 */
final class DataExport
{
    public const SCHEMA = 'terrabela.player_export.v1';

    public function __construct(private Db $db, private Clock $clock)
    {
    }

    /** @return array<string,mixed> */
    public function export(int $playerId): array
    {
        $db = $this->db;
        $p = $db->one('SELECT public_id, status, created_at, last_seen_at, locale, deletion_requested_at FROM players WHERE id = ?', [$playerId]);
        if ($p === null) {
            throw new \InvalidArgumentException('Jogador não encontrado');
        }
        $iso = static fn (?string $s) => Clock::iso($s);
        $w = $db->one('SELECT cash_balance, gold_balance, updated_at FROM wallets WHERE player_id = ?', [$playerId]);
        $save = $db->one('SELECT revision, schema_version, snapshot, client_saved_at, updated_at FROM player_saves WHERE player_id = ?', [$playerId]);
        return [
            'schema' => self::SCHEMA,
            'generated_at' => gmdate('Y-m-d\TH:i:s\Z', $this->clock->now()),
            'controller' => 'Skyplan Brasil Ltda (TerraBela Farm)',
            'account' => [
                'player_id' => Ids::binToUuid($p['public_id']), 'status' => $p['status'], 'created_at' => $iso($p['created_at']),
                'last_seen_at' => $iso($p['last_seen_at']), 'locale' => $p['locale'], 'deletion_requested_at' => $iso($p['deletion_requested_at']),
            ],
            'linked_logins' => array_map(fn ($r) => [
                'provider' => $r['provider'], 'provider_user_id' => $r['provider'] === 'guest' ? null : $r['subject'],
                'linked_at' => $iso($r['created_at']), 'last_used_at' => $iso($r['last_used_at']),
            ], $db->all('SELECT provider, subject, created_at, last_used_at FROM player_identities WHERE player_id = ? ORDER BY id', [$playerId])),
            'devices' => array_map(fn ($r) => [
                'installation_id' => $r['installation_id'], 'platform' => $r['platform'], 'app_version' => $r['app_version'], 'locale' => $r['locale'],
                'timezone' => $r['timezone'], 'push_enabled' => (bool) $r['has_token'], 'first_seen_at' => $iso($r['created_at']),
                'last_seen_at' => $iso($r['last_seen_at']), 'removed_at' => $iso($r['revoked_at']),
            ], $db->all('SELECT installation_id, platform, app_version, locale, timezone, fcm_token IS NOT NULL AS has_token, created_at, last_seen_at, revoked_at FROM player_devices WHERE player_id = ? ORDER BY id', [$playerId])),
            'consents' => array_map(fn ($r) => [
                'type' => $r['consent_type'], 'granted' => (bool) $r['granted'], 'source' => $r['source'], 'recorded_at' => $iso($r['recorded_at']),
            ], $db->all('SELECT consent_type, granted, source, recorded_at FROM player_consents WHERE player_id = ? ORDER BY id', [$playerId])),
            'sessions' => array_map(fn ($r) => [
                'provider' => $r['login_provider'], 'device' => $r['user_agent'], 'started_at' => $iso($r['created_at']), 'ended_at' => $iso($r['revoked_at']),
            ], $db->all('SELECT login_provider, user_agent, created_at, revoked_at FROM player_sessions WHERE player_id = ? ORDER BY id DESC LIMIT 200', [$playerId])),
            'wallet' => $w === null ? null : ['cash' => (int) $w['cash_balance'], 'gold' => (int) $w['gold_balance'], 'updated_at' => $iso($w['updated_at'])],
            'ledger' => array_map(fn ($r) => [
                'at' => $iso($r['created_at']), 'currency' => $r['currency'], 'amount' => (int) $r['amount'], 'balance_after' => (int) $r['balance_after'],
                'source' => $r['source'], 'reason' => $r['reason'],
            ], $db->all('SELECT created_at, currency, amount, balance_after, source, reason FROM economy_ledger WHERE player_id = ? ORDER BY id', [$playerId])),
            'cloud_save' => $save === null ? null : [
                'revision' => (int) $save['revision'], 'schema_version' => (int) $save['schema_version'], 'saved_at' => $iso($save['updated_at']),
                'snapshot' => json_decode($save['snapshot'], true),
            ],
            'purchases' => array_map(fn ($r) => [
                'product' => $r['sku'], 'store' => $r['platform'], 'order_id' => $r['order_id'], 'state' => $r['state'],
                'purchased_at' => $iso($r['purchase_time']), 'granted_at' => $iso($r['granted_at']), 'refunded_at' => $iso($r['refunded_at']),
            ], $db->all('SELECT p.sku, t.platform, t.order_id, t.state, t.purchase_time, t.granted_at, t.refunded_at FROM iap_transactions t JOIN iap_products p ON p.id = t.product_id WHERE t.player_id = ? ORDER BY t.id', [$playerId])),
            'entitlements' => array_map(fn ($r) => [
                'key' => $r['entitlement_key'], 'source' => $r['source'], 'granted_at' => $iso($r['granted_at']), 'revoked_at' => $iso($r['revoked_at']),
            ], $db->all('SELECT entitlement_key, source, granted_at, revoked_at FROM entitlements WHERE player_id = ? ORDER BY id', [$playerId])),
            'rewards' => array_map(fn ($r) => [
                'rule' => $r['rule_key'], 'currency' => $r['currency'], 'amount' => $r['amount'] === null ? null : (int) $r['amount'], 'entitlement' => $r['entitlement_key'],
                'status' => $r['status'], 'created_at' => $iso($r['created_at']), 'claimed_at' => $iso($r['claimed_at']), 'expires_at' => $iso($r['expires_at']),
            ], $db->all('SELECT rule_key, currency, amount, entitlement_key, status, created_at, claimed_at, expires_at FROM reward_grants WHERE player_id = ? ORDER BY id', [$playerId])),
            'experiments' => array_map(fn ($r) => [
                'experiment' => $r['experiment_key'], 'variant' => $r['variant_key'], 'first_seen_at' => $iso($r['first_exposed_at']),
            ], $db->all('SELECT e.experiment_key, a.variant_key, a.first_exposed_at FROM experiment_assignments a JOIN experiments e ON e.id = a.experiment_id WHERE a.player_id = ? ORDER BY a.id', [$playerId])),
            'notifications_received' => (int) $db->one("SELECT COUNT(*) n FROM notification_outbox WHERE player_id = ? AND status = 'sent'", [$playerId])['n'],
            'game_events' => array_map(fn ($r) => [
                'name' => $r['event_name'], 'at' => $iso($r['occurred_at']), 'app_version' => $r['app_version'], 'properties' => $r['properties'] === null ? null : json_decode($r['properties'], true),
            ], $db->all('SELECT event_name, occurred_at, app_version, properties FROM game_events WHERE player_id = ? ORDER BY id DESC LIMIT 5000', [$playerId])),
        ];
    }
}
