<?php
declare(strict_types=1);

/**
 * Backup do banco agora (o cron já faz 1 por dia):  php bin/backup.php
 * Lista:                                             php bin/backup.php --list
 */
require __DIR__ . '/_cli.php';

$app = tbf_app();
if (in_array('--list', $argv, true)) {
    foreach ($app->backups->list() as $b) {
        echo $b['created_at'] . "  " . str_pad((string) $b['bytes'], 10, ' ', STR_PAD_LEFT) . "  " . $b['file'] . "\n";
    }
    exit(0);
}
echo json_encode($app->backups->create(), JSON_UNESCAPED_SLASHES) . "\n";
