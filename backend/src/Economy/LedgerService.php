<?php
declare(strict_types=1);

namespace TerraBela\Economy;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Http\ApiException;

/**
 * Ledger append-only: cada lançamento trava a carteira (FOR UPDATE), confere a chave de
 * idempotência, grava o lançamento com saldo resultante e atualiza a projeção na mesma transação.
 */
final class LedgerService
{
    public const CURRENCIES = ['cash', 'gold'];

    public function __construct(private Db $db, private Clock $clock)
    {
    }

    /**
     * @param null|callable(Db,array<string,int>):void $guard validação extra com a carteira travada (ex.: teto diário)
     * @return array{ledger_id:int,currency:string,amount:int,balance_after:int,replayed:bool}
     */
    public function post(int $playerId, string $currency, int $amount, string $source, string $reason, ?string $reference, string $idempotencyKey, ?callable $guard = null): array
    {
        if (!in_array($currency, self::CURRENCIES, true) || $amount === 0) {
            throw new \InvalidArgumentException('Lançamento inválido');
        }
        return $this->db->tx(function (Db $db) use ($playerId, $currency, $amount, $source, $reason, $reference, $idempotencyKey, $guard) {
            $wallet = $db->one('SELECT cash_balance, gold_balance FROM wallets WHERE player_id = ? FOR UPDATE', [$playerId]);
            if ($wallet === null) {
                throw new ApiException(404, 'wallet_not_found', 'Carteira não encontrada.');
            }
            $prev = $db->one(
                'SELECT id, currency, amount, balance_after FROM economy_ledger WHERE player_id = ? AND idempotency_key = ?',
                [$playerId, $idempotencyKey]
            );
            if ($prev !== null) {
                if ($prev['currency'] !== $currency || (int) $prev['amount'] !== $amount) {
                    throw new ApiException(409, 'idempotency_mismatch', 'Esta chave de operação já foi usada com outros valores.');
                }
                return ['ledger_id' => (int) $prev['id'], 'currency' => $currency, 'amount' => $amount, 'balance_after' => (int) $prev['balance_after'], 'replayed' => true];
            }
            $balances = ['cash' => (int) $wallet['cash_balance'], 'gold' => (int) $wallet['gold_balance']];
            if ($guard !== null) {
                $guard($db, $balances);
            }
            $after = $balances[$currency] + $amount;
            if ($after < 0) {
                throw new ApiException(409, 'insufficient_funds', 'Saldo insuficiente.', ['currency' => $currency, 'balance' => $balances[$currency]]);
            }
            $id = $db->insert(
                'INSERT INTO economy_ledger (player_id, currency, amount, balance_after, source, reason, reference, idempotency_key, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [$playerId, $currency, $amount, $after, $source, $reason, $reference, $idempotencyKey, $this->clock->sql()]
            );
            $col = $currency === 'cash' ? 'cash_balance' : 'gold_balance';
            $db->exec(
                "UPDATE wallets SET $col = ?, version = version + 1, updated_at = ? WHERE player_id = ?",
                [$after, $this->clock->sql(), $playerId]
            );
            return ['ledger_id' => $id, 'currency' => $currency, 'amount' => $amount, 'balance_after' => $after, 'replayed' => false];
        });
    }

    /** @return array{cash:int,gold:int,version:int,updated_at:?string} */
    public function wallet(int $playerId): array
    {
        $w = $this->db->one('SELECT cash_balance, gold_balance, version, updated_at FROM wallets WHERE player_id = ?', [$playerId]);
        if ($w === null) {
            throw new ApiException(404, 'wallet_not_found', 'Carteira não encontrada.');
        }
        return ['cash' => (int) $w['cash_balance'], 'gold' => (int) $w['gold_balance'], 'version' => (int) $w['version'], 'updated_at' => Clock::iso($w['updated_at'])];
    }

    /** Soma dos créditos do cliente na moeda desde o início do dia UTC. */
    public function clientCreditsToday(Db $db, int $playerId, string $currency): int
    {
        $start = gmdate('Y-m-d 00:00:00', $this->clock->now());
        $row = $db->one(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM economy_ledger
              WHERE player_id = ? AND currency = ? AND source = 'client' AND created_at >= ? AND amount > 0",
            [$playerId, $currency, $start]
        );
        return (int) ($row['total'] ?? 0);
    }
}
