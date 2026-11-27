<?php
declare(strict_types=1);

/**
 * Restaura um backup no banco configurado no .env (APAGA e recria as tabelas do backup).
 *   php bin/restore.php tbf-AAAAMMDD-HHMMSS-xxxxxx.sql.gz --confirm
 * Recomendado: restaurar primeiro num banco vazio de teste (outro .env com TBF_ENV_FILE) e conferir.
 * Sem SSH: phpMyAdmin > Importar o .sql.gz (arquivos .enc precisam deste script para descriptografar).
 */
require __DIR__ . '/_cli.php';

$file = $argv[1] ?? '';
if ($file === '' || !in_array('--confirm', $argv, true)) {
    fwrite(STDERR, "Uso: php bin/restore.php ARQUIVO --confirm\n");
    exit(2);
}
$app = tbf_app();
$r = $app->backups->restore($file, $app->db);
echo "Restaurado: {$r['statements']} comandos.\n";
