<?php
declare(strict_types=1);

namespace TerraBela\Billing;

use PDOException;
use TerraBela\Auth\AuthContext;
use TerraBela\Auth\GoogleIdTokenVerifier;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Core\Log;
use TerraBela\Economy\LedgerService;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;

/**
 * Validação de compras Google Play no servidor (TBF-MVP-05).
 * Concede somente após estado "comprado" confirmado pela API da Google, atomicamente com o
 * registro único do purchase token e o ledger; repetir a chamada devolve o resultado original.
 * Reembolso (RTDN voided) revoga direitos e marca a compra; débito de saldo fica para revisão (política do PO).
 */
final class IapService
{
    private const PLATFORM = 'google_play';

    public function __construct(
        private Db $db,
        private Clock $clock,
        private LedgerService $ledger,
        private GooglePlayClient $play,
        private GoogleIdTokenVerifier $oidc,
        private Log $log,
        private ?string $rtdnAudience,
        private ?string $rtdnServiceAccount,
    ) {
    }

    /** Valor que o app deve passar como obfuscatedAccountId no BillingFlowParams. */
    public static function obfuscatedAccountId(string $playerPublicId): string
    {
        return hash('sha256', 'tbf:' . $playerPublicId);
    }

    /** @return array<string,mixed> */
    public function verify(AuthContext $ctx, string $sku, string $purchaseToken): array
    {
        $product = $this->db->one(
            "SELECT id, sku, product_type, benefit FROM iap_products WHERE platform = 'google_play' AND sku = ? AND active = 1 ORDER BY benefit_version DESC LIMIT 1",
            [$sku]
        );
        if ($product === null) {
            throw new ApiException(404, 'product_not_found', 'Produto não disponível.');
        }
        $hash = hash('sha256', $purchaseToken);
        $existing = $this->db->one('SELECT * FROM iap_transactions WHERE purchase_token_hash = ?', [$hash]);
        if ($existing !== null && (int) $existing['player_id'] !== $ctx->playerId) {
            throw new ApiException(409, 'purchase_belongs_to_other_account', 'Esta compra pertence a outra conta.');
        }
        if ($existing !== null && $existing['state'] === 'granted') {
            $this->finalize($existing, $product['product_type']);
            return $this->result($existing, $product, $ctx, true);
        }
        if (!$this->play->configured()) {
            throw new ApiException(503, 'billing_not_configured', 'Validação de compras ainda não configurada no servidor.');
        }
        try {
            $gp = $this->play->getProduct($sku, $purchaseToken);
        } catch (PurchaseNotFound) {
            throw new ApiException(422, 'purchase_invalid', 'Compra não reconhecida pela Google Play.');
        } catch (\RuntimeException $e) {
            $this->log->error('google_play_error', ['msg' => $e->getMessage()]);
            throw new ApiException(503, 'store_unavailable', 'Google Play indisponível. Tente novamente.');
        }

        if (isset($gp['productId']) && $gp['productId'] !== $sku) {
            throw new ApiException(422, 'purchase_invalid', 'Compra não corresponde ao produto.');
        }
        $expectedAccount = self::obfuscatedAccountId($ctx->playerPublicId);
        if (!empty($gp['obfuscatedExternalAccountId']) && !hash_equals($expectedAccount, (string) $gp['obfuscatedExternalAccountId'])) {
            throw new ApiException(403, 'purchase_account_mismatch', 'Compra feita por outra conta.');
        }
        $purchaseState = (int) ($gp['purchaseState'] ?? -1);
        $raw = sprintf('p%d/c%d/a%d', $purchaseState, (int) ($gp['consumptionState'] ?? -1), (int) ($gp['acknowledgementState'] ?? -1));
        $state = match ($purchaseState) {
            0 => 'purchased',
            2 => 'pending',
            1 => 'canceled',
            default => throw new ApiException(422, 'purchase_invalid', 'Estado de compra desconhecido.'),
        };
        if ($state === 'purchased' && (int) ($gp['consumptionState'] ?? 0) === 1 && $existing === null) {
            throw new ApiException(409, 'purchase_already_consumed', 'Compra já consumida e não registrada neste servidor.');
        }
        $orderId = isset($gp['orderId']) ? (string) $gp['orderId'] : null;
        $purchaseTime = isset($gp['purchaseTimeMillis']) ? gmdate('Y-m-d H:i:s', intdiv((int) $gp['purchaseTimeMillis'], 1000)) : null;

        $tx = $this->db->tx(function (Db $db) use ($ctx, $product, $purchaseToken, $hash, $orderId, $purchaseTime, $raw, $state) {
            $now = $this->clock->sql();
            try {
                $db->insert(
                    "INSERT INTO iap_transactions (public_id, player_id, product_id, platform, purchase_token, purchase_token_hash, order_id, state, store_state_raw, purchase_time, created_at, updated_at)
                     VALUES (?, ?, ?, 'google_play', ?, ?, ?, 'pending', ?, ?, ?, ?)",
                    [Ids::uuidBin(), $ctx->playerId, $product['id'], $purchaseToken, $hash, $orderId, $raw, $purchaseTime, $now, $now]
                );
            } catch (PDOException $e) {
                if (!Db::isDuplicate($e)) {
                    throw $e;
                }
            }
            $row = $db->one('SELECT * FROM iap_transactions WHERE purchase_token_hash = ? FOR UPDATE', [$hash]);
            if ((int) $row['player_id'] !== $ctx->playerId) {
                throw new ApiException(409, 'purchase_belongs_to_other_account', 'Esta compra pertence a outra conta.');
            }
            if ($row['state'] === 'granted' || $row['state'] === 'refunded') {
                return $row + ['_replayed' => true];
            }
            if ($state !== 'purchased') {
                $db->exec('UPDATE iap_transactions SET state = ?, store_state_raw = ?, order_id = COALESCE(?, order_id), updated_at = ? WHERE id = ?',
                    [$state === 'pending' ? 'pending' : 'canceled', $raw, $orderId, $now, $row['id']]);
                $this->event($db, 'verify', 'verify:' . $hash . ':' . $state, (int) $row['id'], 'VERIFY_' . strtoupper($state), ['sku' => $product['sku']]);
                return array_merge($row, ['state' => $state === 'pending' ? 'pending' : 'canceled', '_replayed' => false]);
            }
            $benefit = json_decode($product['benefit'], true) ?: [];
            $publicId = Ids::binToUuid($row['public_id']);
            if (isset($benefit['currency'], $benefit['amount'])) {
                $this->ledger->post($ctx->playerId, (string) $benefit['currency'], (int) $benefit['amount'], 'iap', 'iap_purchase', $product['sku'], 'iap:' . $hash);
            }
            foreach ((array) ($benefit['entitlements'] ?? []) as $key) {
                $db->exec(
                    "INSERT INTO entitlements (player_id, entitlement_key, source, source_reference, granted_at) VALUES (?, ?, 'iap', ?, ?)
                     ON DUPLICATE KEY UPDATE revoked_at = NULL, source = 'iap', source_reference = VALUES(source_reference)",
                    [$ctx->playerId, (string) $key, $publicId, $now]
                );
            }
            $db->exec(
                "UPDATE iap_transactions SET state = 'granted', store_state_raw = ?, order_id = COALESCE(?, order_id), granted_at = ?, finalize_status = 'pending', updated_at = ? WHERE id = ?",
                [$raw, $orderId, $now, $now, $row['id']]
            );
            $this->event($db, 'verify', 'verify:' . $hash . ':granted', (int) $row['id'], 'VERIFY_GRANTED', ['sku' => $product['sku'], 'order_id' => $orderId]);
            return array_merge($row, ['state' => 'granted', 'finalize_status' => 'pending', '_replayed' => false]);
        });

        if ($tx['state'] === 'granted') {
            $this->finalize($tx, $product['product_type']);
        }
        return $this->result($tx, $product, $ctx, (bool) ($tx['_replayed'] ?? false));
    }

    /** Consume (consumível) ou acknowledge (permanente). Falha fica pendente para o cron. */
    public function finalize(array $tx, string $productType): void
    {
        if (($tx['finalize_status'] ?? '') !== 'pending' || !$this->play->configured()) {
            return;
        }
        $sku = $this->db->one('SELECT sku FROM iap_products WHERE id = ?', [$tx['product_id']])['sku'] ?? null;
        $ok = false;
        try {
            $ok = $productType === 'consumable'
                ? $this->play->consume((string) $sku, $tx['purchase_token'])
                : $this->play->acknowledge((string) $sku, $tx['purchase_token']);
        } catch (\RuntimeException $e) {
            $this->log->error('iap_finalize_error', ['tx' => (int) $tx['id'], 'msg' => $e->getMessage()]);
        }
        $this->db->exec(
            'UPDATE iap_transactions SET finalize_status = ?, finalize_attempts = finalize_attempts + 1, updated_at = ? WHERE id = ?',
            [$ok ? 'done' : 'pending', $this->clock->sql(), $tx['id']]
        );
    }

    /** Cron: repete consume/acknowledge pendentes (prazo da Google: ~3 dias). */
    public function reconcilePending(int $limit = 50): int
    {
        $rows = $this->db->all(
            "SELECT t.*, p.product_type FROM iap_transactions t JOIN iap_products p ON p.id = t.product_id
              WHERE t.finalize_status = 'pending' AND t.finalize_attempts < 20 ORDER BY t.updated_at LIMIT " . (int) $limit
        );
        foreach ($rows as $r) {
            $this->finalize($r, $r['product_type']);
        }
        return count($rows);
    }

    /** POST /iap/google/rtdn — push autenticado do Pub/Sub (OIDC). */
    public function rtdn(Request $req): array
    {
        if ($this->rtdnAudience === null || $this->rtdnServiceAccount === null) {
            throw new ApiException(503, 'rtdn_not_configured', 'RTDN não configurado.');
        }
        $claims = $this->oidc->verify((string) $req->bearer(), [$this->rtdnAudience]);
        if (($claims['email'] ?? '') !== $this->rtdnServiceAccount || ($claims['email_verified'] ?? false) !== true) {
            throw new ApiException(403, 'forbidden', 'Remetente não autorizado.');
        }
        $in = $req->json();
        $messageId = (string) ($in['message']['messageId'] ?? $in['message']['message_id'] ?? '');
        $data = json_decode((string) base64_decode((string) ($in['message']['data'] ?? ''), true), true);
        if ($messageId === '' || !is_array($data)) {
            throw new ApiException(400, 'invalid_message', 'Mensagem RTDN inválida.');
        }
        if (($data['packageName'] ?? '') !== $this->play->packageName) {
            return ['ignored' => 'package_mismatch'];
        }
        $token = $data['voidedPurchaseNotification']['purchaseToken'] ?? $data['oneTimeProductNotification']['purchaseToken'] ?? null;
        $type = isset($data['voidedPurchaseNotification']) ? 'VOIDED_PURCHASE'
            : (isset($data['oneTimeProductNotification']) ? 'ONE_TIME_' . (int) ($data['oneTimeProductNotification']['notificationType'] ?? 0)
            : (isset($data['testNotification']) ? 'TEST' : 'OTHER'));
        $hash = $token === null ? null : hash('sha256', (string) $token);
        $safe = $data;
        unset($safe['voidedPurchaseNotification']['purchaseToken'], $safe['oneTimeProductNotification']['purchaseToken']);
        $safe['purchase_token_hash'] = $hash;

        return $this->db->tx(function (Db $db) use ($messageId, $type, $hash, $safe) {
            $tx = $hash === null ? null : $db->one('SELECT id, public_id, player_id, state FROM iap_transactions WHERE purchase_token_hash = ? FOR UPDATE', [$hash]);
            if (!$this->event($db, 'rtdn', $messageId, $tx === null ? null : (int) $tx['id'], $type, $safe)) {
                return ['duplicate' => true];
            }
            if ($type === 'VOIDED_PURCHASE' && $tx !== null && $tx['state'] !== 'refunded') {
                $now = $this->clock->sql();
                // Política de reembolso (docs/ECONOMY_POLICY.md): desconta a moeda do benefício só até o
                // saldo disponível (nunca negativo, sem dívida); o que faltar fica em refund_shortfall para análise.
                $clawback = null;
                $shortfall = null;
                if ($tx['state'] === 'granted') {
                    $benefit = json_decode((string) ($db->one('SELECT p.benefit FROM iap_transactions t JOIN iap_products p ON p.id = t.product_id WHERE t.id = ?', [$tx['id']])['benefit'] ?? '{}'), true) ?: [];
                    if (isset($benefit['currency'], $benefit['amount']) && (int) $benefit['amount'] > 0) {
                        $currency = (string) $benefit['currency'];
                        $col = $currency === 'gold' ? 'gold_balance' : 'cash_balance';
                        $bal = (int) ($db->one("SELECT $col AS b FROM wallets WHERE player_id = ? FOR UPDATE", [$tx['player_id']])['b'] ?? 0);
                        $clawback = min((int) $benefit['amount'], $bal);
                        $shortfall = (int) $benefit['amount'] - $clawback;
                        if ($clawback > 0) {
                            $this->ledger->post((int) $tx['player_id'], $currency, -$clawback, 'system', 'iap_refund', Ids::binToUuid($tx['public_id']), 'refund:' . $hash);
                        }
                    }
                }
                $db->exec("UPDATE iap_transactions SET state = 'refunded', refunded_at = ?, refund_clawback = ?, refund_shortfall = ?, updated_at = ? WHERE id = ?", [$now, $clawback, $shortfall, $now, $tx['id']]);
                $db->exec(
                    "UPDATE entitlements SET revoked_at = ? WHERE player_id = ? AND source = 'iap' AND source_reference = ? AND revoked_at IS NULL",
                    [$now, $tx['player_id'], Ids::binToUuid($tx['public_id'])]
                );
                return ['processed' => 'refunded'];
            }
            return ['processed' => 'logged'];
        });
    }

    private function event(Db $db, string $source, string $messageId, ?int $txId, string $type, array $payload): bool
    {
        return $db->exec(
            'INSERT IGNORE INTO iap_events (source, message_id, transaction_id, event_type, payload, received_at) VALUES (?, ?, ?, ?, ?, ?)',
            [$source, mb_substr($messageId, 0, 128), $txId, $type, json_encode($payload, JSON_UNESCAPED_SLASHES), $this->clock->sql()]
        ) > 0;
    }

    private function result(array $tx, array $product, AuthContext $ctx, bool $replayed): array
    {
        return [
            'status' => $tx['state'],
            'transaction_id' => Ids::binToUuid($tx['public_id']),
            'sku' => $product['sku'],
            'benefit' => json_decode($product['benefit'], true),
            'replayed' => $replayed,
            'wallet' => $this->ledger->wallet($ctx->playerId),
        ];
    }
}
