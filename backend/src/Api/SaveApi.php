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
use TerraBela\Http\Response;

/**
 * GET /save e POST /sync. Revisão monotônica + base_revision (sem sobrescrever outro aparelho às cegas)
 * + operation_id idempotente. O saldo de moedas do snapshot NUNCA é aplicado: a carteira do servidor manda.
 */
final class SaveApi
{
    public function __construct(
        private Db $db,
        private Clock $clock,
        private LedgerService $ledger,
        private RemoteConfigService $config,
        private int $historyLimit,
        private int $defaultMaxBytes,
    ) {
    }

    public function get(Request $req, AuthContext $ctx): array
    {
        $row = $this->db->one('SELECT revision, schema_version, snapshot, client_saved_at, updated_at FROM player_saves WHERE player_id = ?', [$ctx->playerId]);
        return [
            'revision' => $row === null ? 0 : (int) $row['revision'],
            'schema_version' => $row === null ? null : (int) $row['schema_version'],
            'snapshot' => $row === null ? null : json_decode($row['snapshot'], true),
            'client_saved_at' => Clock::iso($row['client_saved_at'] ?? null),
            'updated_at' => Clock::iso($row['updated_at'] ?? null),
            'wallet' => $this->ledger->wallet($ctx->playerId),
            'server_time' => gmdate('Y-m-d\TH:i:s\Z', $this->clock->now()),
        ];
    }

    public function sync(Request $req, AuthContext $ctx): Response
    {
        $maxBytes = (int) $this->config->value('sync.max_snapshot_bytes', $this->defaultMaxBytes);
        $in = $req->json($maxBytes + 4096);
        $opId = V::opId($in, 'operation_id');
        $base = V::int($in, 'base_revision', 0, 2_000_000_000);
        $schema = V::int($in, 'schema_version', 1, 1000);
        $clientSavedAt = V::optTime($in, 'client_saved_at');
        $snapshot = $in['snapshot'] ?? null;
        if (!is_array($snapshot) || ($snapshot !== [] && array_is_list($snapshot))) {
            throw new ApiException(422, 'validation_failed', 'Campo inválido: snapshot (objeto JSON obrigatório).', ['field' => 'snapshot']);
        }
        $json = json_encode($snapshot, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $bytes = strlen((string) $json);
        if ($bytes > $maxBytes) {
            throw new ApiException(413, 'snapshot_too_large', 'O save excede o tamanho máximo.', ['max_bytes' => $maxBytes]);
        }
        $requestHash = hash('sha256', $base . '|' . $schema . '|' . $json);

        [$status, $body] = $this->db->tx(function (Db $db) use ($ctx, $opId, $base, $schema, $clientSavedAt, $json, $bytes, $requestHash) {
            // Trava a linha da carteira como mutex por jogador (sempre existe) para serializar syncs.
            $db->one('SELECT player_id FROM wallets WHERE player_id = ? FOR UPDATE', [$ctx->playerId]);
            $prev = $db->one('SELECT request_hash, response_status, response_body FROM sync_operations WHERE player_id = ? AND operation_id = ?', [$ctx->playerId, $opId]);
            if ($prev !== null) {
                if (!hash_equals($prev['request_hash'], $requestHash)) {
                    throw new ApiException(409, 'idempotency_mismatch', 'Este operation_id já foi usado com outro conteúdo.');
                }
                $body = json_decode($prev['response_body'], true);
                $body['replayed'] = true;
                return [(int) $prev['response_status'], $body];
            }
            $cur = $db->one('SELECT revision, schema_version, snapshot, updated_at FROM player_saves WHERE player_id = ?', [$ctx->playerId]);
            $curRev = $cur === null ? 0 : (int) $cur['revision'];
            if ($base !== $curRev) {
                // Conflito: não grava, não registra idempotência (o app reenvia após resolver).
                throw new ApiException(409, 'save_conflict', 'O save na nuvem mudou em outro aparelho.', [
                    'current_revision' => $curRev,
                    'server_updated_at' => Clock::iso($cur['updated_at'] ?? null),
                ]);
            }
            $now = $this->clock->sql();
            $newRev = $curRev + 1;
            if ($cur === null) {
                $db->exec(
                    'INSERT INTO player_saves (player_id, revision, schema_version, snapshot, snapshot_bytes, client_saved_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [$ctx->playerId, $newRev, $schema, $json, $bytes, $clientSavedAt, $now]
                );
            } else {
                $db->exec(
                    'INSERT INTO player_save_versions (player_id, revision, schema_version, snapshot, saved_at, archived_at) VALUES (?, ?, ?, ?, ?, ?)',
                    [$ctx->playerId, $curRev, $cur['schema_version'], $cur['snapshot'], $cur['updated_at'], $now]
                );
                $db->exec(
                    'UPDATE player_saves SET revision = ?, schema_version = ?, snapshot = ?, snapshot_bytes = ?, client_saved_at = ?, updated_at = ? WHERE player_id = ?',
                    [$newRev, $schema, $json, $bytes, $clientSavedAt, $now, $ctx->playerId]
                );
                $db->exec(
                    'DELETE FROM player_save_versions WHERE player_id = ? AND revision <= ?',
                    [$ctx->playerId, $curRev - $this->historyLimit]
                );
            }
            $body = [
                'revision' => $newRev,
                'updated_at' => Clock::iso($now),
                'wallet' => $this->ledger->wallet($ctx->playerId),
                'replayed' => false,
            ];
            $db->insert(
                "INSERT INTO sync_operations (player_id, operation_id, operation_type, request_hash, response_status, response_body, created_at) VALUES (?, ?, 'save', ?, 200, ?, ?)",
                [$ctx->playerId, $opId, $requestHash, json_encode($body), $now]
            );
            return [200, $body];
        });
        return Response::json($body, $status);
    }
}
