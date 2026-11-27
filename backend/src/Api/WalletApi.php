<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Auth\AuthContext;
use TerraBela\Config\RemoteConfigService;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Economy\LedgerService;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;

/**
 * GET /wallet, GET /wallet/ledger, POST /wallet/operations e GET /inventory.
 * Política do cliente (Remote Config, valores pendentes de aprovação do PO):
 *  - crédito de cash só com motivo permitido, teto por operação e teto diário;
 *  - gold NUNCA é creditado pelo app (somente IAP verificada ou recompensa do servidor);
 *  - débitos de cash/gold só com motivo permitido e saldo suficiente.
 */
final class WalletApi
{
    public function __construct(
        private Db $db,
        private LedgerService $ledger,
        private RemoteConfigService $config,
    ) {
    }

    public function get(Request $req, AuthContext $ctx): array
    {
        return $this->ledger->wallet($ctx->playerId);
    }

    public function history(Request $req, AuthContext $ctx): array
    {
        $limit = max(1, min(100, (int) ($req->query['limit'] ?? 50)));
        $before = isset($req->query['before']) ? (int) $req->query['before'] : PHP_INT_MAX;
        $rows = $this->db->all(
            'SELECT id, currency, amount, balance_after, source, reason, reference, created_at FROM economy_ledger
              WHERE player_id = ? AND id < ? ORDER BY id DESC LIMIT ' . $limit,
            [$ctx->playerId, $before]
        );
        $items = array_map(static fn ($r) => [
            'id' => (int) $r['id'],
            'currency' => $r['currency'],
            'amount' => (int) $r['amount'],
            'balance_after' => (int) $r['balance_after'],
            'source' => $r['source'],
            'reason' => $r['reason'],
            'reference' => $r['reference'],
            'created_at' => Clock::iso($r['created_at']),
        ], $rows);
        return ['items' => $items, 'next_before' => count($items) === $limit ? end($items)['id'] : null];
    }

    public function operations(Request $req, AuthContext $ctx): array
    {
        $in = $req->json();
        $ops = V::list($in, 'operations', 1, 50);
        $credit = (array) $this->config->value('economy.client_credit', []);
        $debitReasons = (array) $this->config->value('economy.client_debit_reasons', []);
        $results = [];
        foreach ($ops as $i => $op) {
            if (!is_array($op)) {
                throw new ApiException(422, 'validation_failed', "Operação $i inválida.");
            }
            $opId = V::opId($op, 'operation_id');
            $currency = V::enum($op, 'currency', LedgerService::CURRENCIES);
            $amount = V::int($op, 'amount', -1_000_000_000, 1_000_000_000);
            $reason = V::str($op, 'reason', 3, 40, '/^[a-z][a-z0-9_]+$/');
            $reference = V::optStr($op, 'reference', 128);
            try {
                if ($amount === 0) {
                    throw new ApiException(422, 'validation_failed', 'amount não pode ser zero.');
                }
                $guard = null;
                if ($amount > 0) {
                    $rule = $credit[$currency] ?? null;
                    if (!is_array($rule) || !in_array($reason, (array) ($rule['reasons'] ?? []), true)) {
                        throw new ApiException(403, 'credit_not_allowed', 'Este crédito não pode ser feito pelo app.');
                    }
                    if ($amount > (int) $rule['max_per_operation']) {
                        throw new ApiException(422, 'credit_over_limit', 'Crédito acima do limite por operação.');
                    }
                    $maxDay = (int) $rule['max_per_day'];
                    $guard = function (Db $db) use ($ctx, $currency, $amount, $maxDay) {
                        if ($this->ledger->clientCreditsToday($db, $ctx->playerId, $currency) + $amount > $maxDay) {
                            throw new ApiException(429, 'daily_credit_limit', 'Limite diário de créditos atingido.');
                        }
                    };
                } elseif (!in_array($reason, $debitReasons, true)) {
                    throw new ApiException(403, 'debit_not_allowed', 'Motivo de gasto não permitido.');
                }
                $r = $this->ledger->post($ctx->playerId, $currency, $amount, 'client', $reason, $reference, 'client:' . $opId, $guard);
                $results[] = ['operation_id' => $opId, 'status' => 'applied'] + $r;
            } catch (ApiException $e) {
                $results[] = ['operation_id' => $opId, 'status' => 'rejected', 'error' => ['code' => $e->errorCode, 'message' => $e->getMessage()] + $e->details];
            }
        }
        return ['results' => $results, 'wallet' => $this->ledger->wallet($ctx->playerId)];
    }

    public function inventory(Request $req, AuthContext $ctx): array
    {
        $rows = $this->db->all(
            'SELECT entitlement_key, source, granted_at FROM entitlements WHERE player_id = ? AND revoked_at IS NULL ORDER BY entitlement_key',
            [$ctx->playerId]
        );
        return [
            'entitlements' => array_map(static fn ($r) => [
                'key' => $r['entitlement_key'], 'source' => $r['source'], 'granted_at' => Clock::iso($r['granted_at']),
            ], $rows),
            'wallet' => $this->ledger->wallet($ctx->playerId),
        ];
    }
}
