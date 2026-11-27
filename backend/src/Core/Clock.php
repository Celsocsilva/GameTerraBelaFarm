<?php
declare(strict_types=1);

namespace TerraBela\Core;

/** Relógio do servidor (UTC). Substituível nos testes. */
class Clock
{
    private ?int $fixed = null;

    public function now(): int
    {
        return $this->fixed ?? time();
    }

    public function set(?int $ts): void
    {
        $this->fixed = $ts;
    }

    public function advance(int $seconds): void
    {
        $this->fixed = $this->now() + $seconds;
    }

    /** DATETIME(6) em UTC para gravar no MySQL. */
    public function sql(int $offsetSeconds = 0): string
    {
        return gmdate('Y-m-d H:i:s', $this->now() + $offsetSeconds) . '.000000';
    }

    public static function iso(?string $sqlDatetime): ?string
    {
        if ($sqlDatetime === null) {
            return null;
        }
        $dt = new \DateTimeImmutable($sqlDatetime, new \DateTimeZone('UTC'));
        return $dt->format('Y-m-d\TH:i:s\Z');
    }
}
