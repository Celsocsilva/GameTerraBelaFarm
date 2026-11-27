<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Config\RemoteConfigService;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;
use TerraBela\Http\Response;

/** GET /config?client_version=x.y.z — público, cacheável com ETag; o app guarda a última válida offline. */
final class ConfigApi
{
    public function __construct(private RemoteConfigService $config)
    {
    }

    public function get(Request $req): Response
    {
        $client = isset($req->query['client_version']) && is_string($req->query['client_version'])
            && preg_match('/^\d+(\.\d+){0,3}$/', $req->query['client_version']) ? $req->query['client_version'] : null;
        $cfg = $this->config->current($client);
        if ($cfg === null) {
            throw new ApiException(404, 'config_not_found', 'Nenhuma configuração publicada para esta versão do app.');
        }
        $etag = '"' . substr($cfg['checksum'], 0, 32) . '"';
        $headers = ['ETag' => $etag, 'Cache-Control' => 'public, max-age=300'];
        if (($req->header('if-none-match') ?? '') === $etag) {
            return new Response(304, '', $headers);
        }
        return Response::json([
            'version' => $cfg['version'],
            'published_at' => $cfg['published_at'],
            'config' => $cfg['payload'],
        ], 200, $headers);
    }
}
