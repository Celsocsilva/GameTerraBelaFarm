<?php
declare(strict_types=1);

namespace TerraBela\Core;

use TerraBela\Http\ApiException;

/** Rate limit por janela fixa guardado no MySQL (sem Redis na hospedagem compartilhada). */
final class RateLimiter
{
    public function __construct(private Db $db, private Clock $clock, private string $salt)
    {
    }

    public function hit(string $rule, string $subject, int $limit, int $windowSeconds): void
    {
        if ($limit <= 0) {
            return;
        }
        $now = $this->clock->now();
        $windowStart = gmdate('Y-m-d H:i:s', $now - ($now % $windowSeconds));
        $bucket = hash('sha256', $this->salt . '|' . $rule . '|' . $subject);
        $this->db->exec(
            'INSERT INTO rate_limits (bucket, window_start, hits) VALUES (?, ?, 1)
             ON DUPLICATE KEY UPDATE hits = hits + 1',
            [$bucket, $windowStart]
        );
        $row = $this->db->one('SELECT hits FROM rate_limits WHERE bucket = ? AND window_start = ?', [$bucket, $windowStart]);
        if ($row !== null && (int) $row['hits'] > $limit) {
            $retry = $windowSeconds - ($now % $windowSeconds);
            throw new ApiException(429, 'rate_limited', 'Muitas requisições. Tente novamente em instantes.', ['retry_after' => $retry]);
        }
    }
}
