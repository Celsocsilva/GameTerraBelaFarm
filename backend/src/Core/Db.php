<?php
declare(strict_types=1);

namespace TerraBela\Core;

use PDO;
use PDOException;

/**
 * Acesso ao MySQL via PDO com prepared statements, sessão em UTC
 * e transações curtas com nova tentativa em deadlock/lock wait.
 */
final class Db
{
    public function __construct(public readonly PDO $pdo)
    {
    }

    public static function fromConfig(Config $config): self
    {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            $config->str('DB_HOST', 'localhost'),
            $config->int('DB_PORT', 3306),
            $config->str('DB_NAME')
        );
        $pdo = new PDO($dsn, $config->str('DB_USER'), $config->str('DB_PASSWORD', ''), [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_STRINGIFY_FETCHES => false,
        ]);
        $pdo->exec("SET time_zone = '+00:00'");
        return new self($pdo);
    }

    /** @param array<int|string,mixed> $params */
    public function one(string $sql, array $params = []): ?array
    {
        $st = $this->pdo->prepare($sql);
        $st->execute($params);
        $row = $st->fetch();
        return $row === false ? null : $row;
    }

    /** @param array<int|string,mixed> $params @return list<array<string,mixed>> */
    public function all(string $sql, array $params = []): array
    {
        $st = $this->pdo->prepare($sql);
        $st->execute($params);
        return $st->fetchAll();
    }

    /** @param array<int|string,mixed> $params */
    public function exec(string $sql, array $params = []): int
    {
        $st = $this->pdo->prepare($sql);
        $st->execute($params);
        return $st->rowCount();
    }

    /** @param array<int|string,mixed> $params */
    public function insert(string $sql, array $params = []): int
    {
        $this->exec($sql, $params);
        return (int) $this->pdo->lastInsertId();
    }

    public function inTransaction(): bool
    {
        return $this->pdo->inTransaction();
    }

    /**
     * Executa $fn numa transação. Repete até $retries vezes em deadlock (1213)
     * ou lock wait timeout (1205); as operações devem ser idempotentes.
     *
     * @template T
     * @param callable(Db):T $fn
     * @return T
     */
    public function tx(callable $fn, int $retries = 3): mixed
    {
        if ($this->pdo->inTransaction()) {
            return $fn($this);
        }
        $attempt = 0;
        while (true) {
            $attempt++;
            $this->pdo->beginTransaction();
            try {
                $result = $fn($this);
                $this->pdo->commit();
                return $result;
            } catch (\Throwable $e) {
                if ($this->pdo->inTransaction()) {
                    $this->pdo->rollBack();
                }
                if ($e instanceof PDOException && $attempt < $retries && self::isRetryable($e)) {
                    usleep(random_int(20_000, 80_000) * $attempt);
                    continue;
                }
                throw $e;
            }
        }
    }

    public static function isRetryable(PDOException $e): bool
    {
        $code = (int) ($e->errorInfo[1] ?? 0);
        return $code === 1213 || $code === 1205;
    }

    public static function isDuplicate(PDOException $e): bool
    {
        return (int) ($e->errorInfo[1] ?? 0) === 1062;
    }
}
