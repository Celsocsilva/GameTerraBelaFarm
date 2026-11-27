<?php
declare(strict_types=1);

// Inicialização comum dos scripts de linha de comando / cron.
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
require dirname(__DIR__) . '/src/bootstrap.php';

function tbf_config(): TerraBela\Core\Config
{
    $env = getenv('TBF_ENV_FILE') ?: dirname(__DIR__) . '/.env';
    return TerraBela\Core\Config::load($env);
}

function tbf_app(): TerraBela\App
{
    return new TerraBela\App(tbf_config());
}
