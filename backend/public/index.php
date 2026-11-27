<?php
declare(strict_types=1);

/**
 * Front controller da API TerraBela Farm (único arquivo PHP na pasta pública).
 * O código e o .env ficam FORA da pasta pública; app-path.php diz onde estão.
 */

ini_set('display_errors', '0');
$appDir = is_file(__DIR__ . '/app-path.php') ? (string) require __DIR__ . '/app-path.php' : dirname(__DIR__);

if (!is_file($appDir . '/src/bootstrap.php')) {
    http_response_code(503);
    header('Content-Type: application/json; charset=utf-8');
    echo '{"error":{"code":"not_installed","message":"Backend não instalado: confira app-path.php."}}';
    exit;
}
require $appDir . '/src/bootstrap.php';

$config = TerraBela\Core\Config::load($appDir . '/.env');
try {
    $app = new TerraBela\App($config);
} catch (Throwable $e) {
    error_log('[terrabela] boot failure: ' . get_class($e) . ': ' . $e->getMessage());
    http_response_code(503);
    header('Content-Type: application/json; charset=utf-8');
    echo '{"error":{"code":"service_unavailable","message":"Serviço indisponível."}}';
    exit;
}
$app->handle(TerraBela\Http\Request::fromGlobals($config->str('TRUST_PROXY', '0')))->send();
