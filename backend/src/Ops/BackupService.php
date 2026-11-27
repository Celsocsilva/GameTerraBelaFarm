<?php
declare(strict_types=1);

namespace TerraBela\Ops;

use PDO;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;

/**
 * Backup lógico do banco em PHP puro (a hospedagem compartilhada não garante mysqldump nem shell):
 * SQL compactado (.sql.gz) com estrutura + dados num snapshot consistente (InnoDB), importável pelo phpMyAdmin
 * ou por bin/restore.php. Opcional: criptografia AES-256-GCM com BACKUP_ENCRYPTION_KEY (.sql.gz.enc).
 * Tabelas voláteis (rate limit, sessões do backoffice) vão só com a estrutura.
 */
final class BackupService
{
    private const STRUCTURE_ONLY = ['rate_limits', 'admin_sessions'];
    private const BATCH = 200;
    private const MAGIC = "TBFENC1\n";

    public function __construct(
        private Db $db,
        private Clock $clock,
        private string $dir,
        private int $keep = 14,
        private ?string $encryptionKey = null,
    ) {
    }

    /** @return array{file:string,bytes:int,tables:int,rows:int,sha256:string,encrypted:bool,seconds:float} */
    public function create(): array
    {
        $started = microtime(true);
        if (!is_dir($this->dir) && !@mkdir($this->dir, 0700, true) && !is_dir($this->dir)) {
            throw new \RuntimeException('Não foi possível criar a pasta de backup');
        }
        $guard = $this->dir . '/.htaccess';
        if (!is_file($guard)) {
            @file_put_contents($guard, "Require all denied\nDeny from all\n");
        }
        $name = 'tbf-' . gmdate('Ymd-His', $this->clock->now()) . '-' . bin2hex(random_bytes(3)) . '.sql.gz';
        $tmp = $this->dir . '/.' . $name . '.part';
        $gz = gzopen($tmp, 'wb6');
        if ($gz === false) {
            throw new \RuntimeException('Não foi possível gravar o backup');
        }
        $pdo = $this->db->pdo;
        $tables = 0;
        $rows = 0;
        try {
            $pdo->exec('SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ');
            $pdo->exec('START TRANSACTION WITH CONSISTENT SNAPSHOT');
            $schema = $this->db->one('SELECT DATABASE() AS d, VERSION() AS v');
            gzwrite($gz, "-- TerraBela Farm backup\n-- banco: {$schema['d']} · servidor: {$schema['v']} · criado (UTC): " . gmdate('Y-m-d H:i:s', $this->clock->now()) . "\n"
                . "-- Restaurar: phpMyAdmin > Importar (aceita .gz) num banco vazio, ou php bin/restore.php ARQUIVO --confirm\n"
                . "SET NAMES utf8mb4;\nSET time_zone = '+00:00';\nSET FOREIGN_KEY_CHECKS = 0;\nSET UNIQUE_CHECKS = 0;\n\n");
            $list = $this->db->all("SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME");
            foreach ($list as $t) {
                $table = $t['t'];
                $q = '`' . str_replace('`', '``', $table) . '`';
                $create = $this->db->one("SHOW CREATE TABLE $q");
                gzwrite($gz, "DROP TABLE IF EXISTS $q;\n" . $create['Create Table'] . ";\n\n");
                $tables++;
                if (in_array($table, self::STRUCTURE_ONLY, true)) {
                    continue;
                }
                $binary = [];
                foreach ($this->db->all('SELECT COLUMN_NAME c, DATA_TYPE d FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', [$table]) as $c) {
                    $binary[$c['c']] = in_array($c['d'], ['binary', 'varbinary', 'blob', 'tinyblob', 'mediumblob', 'longblob'], true);
                }
                $stmt = $pdo->query("SELECT * FROM $q");
                $batch = [];
                $cols = null;
                while (($r = $stmt->fetch(PDO::FETCH_ASSOC)) !== false) {
                    $cols ??= '(' . implode(', ', array_map(static fn ($c) => '`' . str_replace('`', '``', $c) . '`', array_keys($r))) . ')';
                    $vals = [];
                    foreach ($r as $col => $v) {
                        $vals[] = match (true) {
                            $v === null => 'NULL',
                            $binary[$col] ?? false => '0x' . bin2hex((string) $v),
                            is_int($v) || is_float($v) => (string) $v,
                            default => $pdo->quote((string) $v),
                        };
                    }
                    $batch[] = '(' . implode(', ', $vals) . ')';
                    $rows++;
                    if (count($batch) >= self::BATCH) {
                        gzwrite($gz, "INSERT INTO $q $cols VALUES " . implode(', ', $batch) . ";\n");
                        $batch = [];
                    }
                }
                $stmt->closeCursor();
                if ($batch) {
                    gzwrite($gz, "INSERT INTO $q $cols VALUES " . implode(', ', $batch) . ";\n");
                }
                gzwrite($gz, "\n");
            }
            gzwrite($gz, "SET FOREIGN_KEY_CHECKS = 1;\nSET UNIQUE_CHECKS = 1;\n-- fim do backup ($tables tabelas, $rows linhas)\n");
            $pdo->exec('COMMIT');
        } catch (\Throwable $e) {
            gzclose($gz);
            @unlink($tmp);
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
        gzclose($gz);
        $final = $this->dir . '/' . $name;
        $encrypted = false;
        if ($this->encryptionKey !== null && $this->encryptionKey !== '') {
            $plain = (string) file_get_contents($tmp);
            $iv = random_bytes(12);
            $tag = '';
            $cipher = openssl_encrypt($plain, 'aes-256-gcm', $this->key(), OPENSSL_RAW_DATA, $iv, $tag);
            if ($cipher === false) {
                @unlink($tmp);
                throw new \RuntimeException('Falha ao criptografar o backup');
            }
            file_put_contents($tmp, self::MAGIC . $iv . $tag . $cipher);
            $final .= '.enc';
            $encrypted = true;
        }
        rename($tmp, $final);
        @chmod($final, 0600);
        $this->prune();
        return [
            'file' => basename($final), 'bytes' => (int) filesize($final), 'tables' => $tables, 'rows' => $rows,
            'sha256' => hash_file('sha256', $final), 'encrypted' => $encrypted, 'seconds' => round(microtime(true) - $started, 2),
        ];
    }

    /** @return list<array{file:string,bytes:int,created_at:string}> mais novo primeiro */
    public function list(): array
    {
        $out = [];
        foreach (glob($this->dir . '/tbf-*.sql.gz*') ?: [] as $f) {
            $out[] = ['file' => basename($f), 'bytes' => (int) filesize($f), 'created_at' => gmdate('Y-m-d H:i:s', (int) filemtime($f))];
        }
        usort($out, static fn ($a, $b) => strcmp($b['file'], $a['file']));
        return $out;
    }

    /** Há backup nas últimas $hours horas? */
    public function recent(int $hours = 20): bool
    {
        $l = $this->list();
        return $l !== [] && strtotime($l[0]['created_at'] . ' UTC') > $this->clock->now() - $hours * 3600;
    }

    public function prune(): int
    {
        $n = 0;
        foreach (array_slice($this->list(), max(1, $this->keep)) as $old) {
            if (@unlink($this->dir . '/' . $old['file'])) {
                $n++;
            }
        }
        return $n;
    }

    /** Lê um backup (descriptografa se preciso) e aplica num banco. @return array{statements:int} */
    public function restore(string $file, Db $target): array
    {
        $path = str_contains($file, '/') ? $file : $this->dir . '/' . basename($file);
        if (!is_file($path)) {
            throw new \InvalidArgumentException('Backup não encontrado');
        }
        $raw = (string) file_get_contents($path);
        if (str_starts_with($raw, self::MAGIC)) {
            $iv = substr($raw, 8, 12);
            $tag = substr($raw, 20, 16);
            $raw = openssl_decrypt(substr($raw, 36), 'aes-256-gcm', $this->key(), OPENSSL_RAW_DATA, $iv, $tag);
            if ($raw === false) {
                throw new \RuntimeException('Chave de backup incorreta ou arquivo alterado');
            }
        }
        $sql = gzdecode($raw);
        if ($sql === false) {
            throw new \RuntimeException('Backup corrompido (gzip)');
        }
        $n = 0;
        $buf = '';
        foreach (preg_split('/\R/', $sql) as $line) {
            $t = trim($line);
            if ($buf === '' && ($t === '' || str_starts_with($t, '--'))) {
                continue;
            }
            $buf .= $line . "\n";
            if (str_ends_with($t, ';')) {
                $target->pdo->exec($buf);
                $buf = '';
                $n++;
            }
        }
        if (!str_contains($sql, '-- fim do backup')) {
            throw new \RuntimeException('Backup incompleto (sem marcador de fim)');
        }
        return ['statements' => $n];
    }

    private function key(): string
    {
        $k = (string) $this->encryptionKey;
        return ctype_xdigit($k) && strlen($k) === 64 ? (string) hex2bin($k) : hash('sha256', $k, true);
    }
}
