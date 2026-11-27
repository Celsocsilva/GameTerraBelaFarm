<?php
declare(strict_types=1);

/**
 * Inicialização do backend TerraBela Farm sem Composer.
 * Define o autoload PSR-4 do namespace TerraBela\ e carrega a configuração.
 */

define('TBF_APP_DIR', dirname(__DIR__));

spl_autoload_register(static function (string $class): void {
    $prefix = 'TerraBela\\';
    if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
        return;
    }
    $relative = str_replace('\\', '/', substr($class, strlen($prefix)));
    $file = __DIR__ . '/' . $relative . '.php';
    if (is_file($file)) {
        require $file;
    }
});

date_default_timezone_set('UTC');
mb_internal_encoding('UTF-8');
