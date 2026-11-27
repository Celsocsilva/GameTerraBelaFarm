<?php
declare(strict_types=1);

namespace TerraBela\Players;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;

final class PlayerService
{
    public function __construct(private Db $db, private Clock $clock)
    {
    }

    /** Cria jogador + carteira zerada. Deve rodar dentro de transação. @return array{id:int,public_id:string} */
    public function create(?string $locale): array
    {
        $public = Ids::uuidBin();
        $id = $this->db->insert(
            'INSERT INTO players (public_id, status, created_at, locale) VALUES (?, \'active\', ?, ?)',
            [$public, $this->clock->sql(), $locale]
        );
        $this->db->exec('INSERT INTO wallets (player_id, updated_at) VALUES (?, ?)', [$id, $this->clock->sql()]);
        return ['id' => $id, 'public_id' => Ids::binToUuid($public)];
    }

    /** Resumo neutro de uma fazenda, usado em conflitos de vínculo (sem dados pessoais). @return array<string,mixed> */
    public function summary(int $playerId): array
    {
        $row = $this->db->one(
            'SELECT p.public_id, p.created_at, p.last_seen_at, w.cash_balance, w.gold_balance, s.revision, s.updated_at AS save_updated_at
               FROM players p
               JOIN wallets w ON w.player_id = p.id
               LEFT JOIN player_saves s ON s.player_id = p.id
              WHERE p.id = ?',
            [$playerId]
        );
        if ($row === null) {
            return [];
        }
        return [
            'player_id' => Ids::binToUuid($row['public_id']),
            'created_at' => Clock::iso($row['created_at']),
            'last_seen_at' => Clock::iso($row['last_seen_at']),
            'wallet' => ['cash' => (int) $row['cash_balance'], 'gold' => (int) $row['gold_balance']],
            'save_revision' => $row['revision'] === null ? 0 : (int) $row['revision'],
            'save_updated_at' => Clock::iso($row['save_updated_at']),
        ];
    }
}
