<?php
declare(strict_types=1);

namespace TerraBela\Auth;

/** Jogador e sessão autenticados na requisição atual. */
final class AuthContext
{
    public function __construct(
        public readonly int $playerId,
        public readonly string $playerPublicId,
        public readonly int $sessionId,
    ) {
    }
}
