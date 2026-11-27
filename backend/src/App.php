<?php
declare(strict_types=1);

namespace TerraBela;

use TerraBela\Admin\AdminApp;
use TerraBela\Api\AuthApi;
use TerraBela\Api\ConfigApi;
use TerraBela\Api\DevicesApi;
use TerraBela\Api\EventsApi;
use TerraBela\Api\MeApi;
use TerraBela\Api\SaveApi;
use TerraBela\Api\V;
use TerraBela\Api\WalletApi;
use TerraBela\Auth\AppleIdTokenVerifier;
use TerraBela\Auth\FacebookTokenVerifier;
use TerraBela\Auth\GoogleIdTokenVerifier;
use TerraBela\Auth\JwksCache;
use TerraBela\Auth\TokenService;
use TerraBela\Billing\GooglePlayClient;
use TerraBela\Billing\IapService;
use TerraBela\Config\RemoteConfigService;
use TerraBela\Core\Clock;
use TerraBela\Core\Config;
use TerraBela\Core\CurlHttpClient;
use TerraBela\Core\Db;
use TerraBela\Core\HttpClient;
use TerraBela\Core\Ids;
use TerraBela\Core\Log;
use TerraBela\Core\RateLimiter;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;
use TerraBela\Http\Response;
use TerraBela\Http\Router;
use TerraBela\LiveOps\CampaignService;
use TerraBela\LiveOps\ExperimentService;
use TerraBela\LiveOps\FcmClient;
use TerraBela\LiveOps\MetricsService;
use TerraBela\LiveOps\RuleEngine;
use TerraBela\Ops\BackupService;
use TerraBela\Players\DataExport;
use TerraBela\Players\PlayerService;
use TerraBela\Rewards\RewardService;

/** Kernel da API: monta serviços, rotas /api/v1 e trata autenticação, rate limit e erros. */
final class App
{
    public const API_VERSION = '1.0.0';

    public readonly Db $db;
    public readonly Clock $clock;
    public readonly Log $log;
    public readonly TokenService $tokens;
    public readonly Economy\LedgerService $ledger;
    public readonly RemoteConfigService $remoteConfig;
    public readonly RewardService $rewards;
    public readonly IapService $iap;
    public readonly PlayerService $players;
    public readonly CampaignService $campaigns;
    public readonly RuleEngine $rules;
    public readonly MetricsService $metrics;
    public readonly RateLimiter $limiter;
    public readonly BackupService $backups;
    public readonly DataExport $exporter;
    public readonly ExperimentService $experiments;
    private Router $router;
    private ?AdminApp $admin = null;

    public function __construct(public readonly Config $config, ?Db $db = null, ?HttpClient $http = null, ?Clock $clock = null)
    {
        $this->db = $db ?? Db::fromConfig($config);
        $this->clock = $clock ?? new Clock();
        $http ??= new CurlHttpClient();
        $storage = $config->optional('STORAGE_DIR') ?? (\defined('TBF_APP_DIR') ? TBF_APP_DIR . '/storage' : null);
        $this->log = new Log($storage === null ? null : $storage . '/logs');
        $appKey = $config->str('APP_KEY');
        if (strlen($appKey) < 32) {
            throw new \RuntimeException('APP_KEY deve ter pelo menos 32 caracteres');
        }

        $this->tokens = new TokenService($this->db, $this->clock, $appKey, $config->int('ACCESS_TOKEN_TTL', 3600), $config->int('REFRESH_TOKEN_TTL', 30 * 86400));
        $this->players = new PlayerService($this->db, $this->clock);
        $this->ledger = new Economy\LedgerService($this->db, $this->clock);
        $this->remoteConfig = new RemoteConfigService($this->db, $this->clock, $config->str('APP_ENV', 'production'));
        $this->rewards = new RewardService($this->db, $this->clock, $this->ledger);
        $this->limiter = new RateLimiter($this->db, $this->clock, $appKey);
        $jwks = new JwksCache($http, $this->clock, $storage === null ? null : $storage . '/cache');
        $google = new GoogleIdTokenVerifier($jwks, $this->clock);
        $facebook = new FacebookTokenVerifier($http, $config->optional('FACEBOOK_APP_ID'), $config->optional('FACEBOOK_APP_SECRET'));
        $play = new GooglePlayClient($http, $this->clock, $config->optional('GOOGLE_PLAY_SERVICE_ACCOUNT_FILE'), $config->str('ANDROID_PACKAGE_NAME', 'com.terrabela.farm'));
        $fcm = new FcmClient($http, $this->clock, $config->optional('FCM_SERVICE_ACCOUNT_FILE'), $config->optional('FCM_PROJECT_ID'));
        $this->campaigns = new CampaignService($this->db, $this->clock, $fcm, $config->int('PUSH_PROMO_WEEKLY_CAP', 3));
        $this->rules = new RuleEngine($this->db, $this->clock, $this->rewards);
        $this->metrics = new MetricsService($this->db, $this->clock);
        $backupDir = $config->optional('BACKUP_DIR') ?? ($storage ?? sys_get_temp_dir()) . '/backups';
        $this->backups = new BackupService($this->db, $this->clock, $backupDir, $config->int('BACKUP_KEEP', 14), $config->optional('BACKUP_ENCRYPTION_KEY'));
        $this->exporter = new DataExport($this->db, $this->clock);
        $this->experiments = new ExperimentService($this->db, $this->clock, $this->remoteConfig);
        $this->iap = new IapService($this->db, $this->clock, $this->ledger, $play, $google, $this->log, $config->optional('RTDN_AUDIENCE'), $config->optional('RTDN_SERVICE_ACCOUNT_EMAIL'));

        $auth = new AuthApi($this->db, $this->clock, $this->tokens, $this->players, $google, $facebook, $config->list('GOOGLE_CLIENT_IDS'), $appKey, new AppleIdTokenVerifier($jwks, $this->clock), $config->list('APPLE_CLIENT_IDS'));
        $me = new MeApi($this->db, $this->clock, $this->players, $this->tokens, $config->int('DELETION_GRACE_DAYS', 30));
        $save = new SaveApi($this->db, $this->clock, $this->ledger, $this->remoteConfig, $config->int('SAVE_HISTORY', 10), $config->int('SAVE_MAX_BYTES', 262144));
        $wallet = new WalletApi($this->db, $this->ledger, $this->remoteConfig);
        $cfg = new ConfigApi($this->remoteConfig);
        $events = new EventsApi($this->db, $this->clock);
        $devices = new DevicesApi($this->db, $this->clock);

        $r = $this->router = new Router();
        $p = '/api/v1';
        $r->add('GET', $p . '/health', fn () => $this->health());
        $r->add('POST', $p . '/auth/guest', $auth->guest(...), ['rate' => 'auth']);
        $r->add('POST', $p . '/auth/google', $auth->google(...), ['rate' => 'auth']);
        $r->add('POST', $p . '/auth/apple', $auth->apple(...), ['rate' => 'auth']);
        $r->add('POST', $p . '/auth/facebook', $auth->facebook(...), ['rate' => 'auth']);
        $r->add('POST', $p . '/auth/refresh', $auth->refresh(...), ['rate' => 'auth']);
        $r->add('POST', $p . '/auth/link', $auth->link(...), ['auth' => true, 'rate' => 'auth']);
        $r->add('POST', $p . '/auth/logout', $auth->logout(...), ['auth' => true]);
        $r->add('GET', $p . '/me', $me->get(...), ['auth' => true]);
        $r->add('DELETE', $p . '/me', $me->delete(...), ['auth' => true]);
        $r->add('GET', $p . '/me/export', function (Request $q, $ctx) {
            $this->limiter->hit('export', (string) $ctx->playerId, $this->config->int('RATE_EXPORT_PER_HOUR', 3), 3600);
            return Response::json($this->exporter->export($ctx->playerId), 200, ['Content-Disposition' => 'attachment; filename="terrabela-meus-dados.json"']);
        }, ['auth' => true]);
        $r->add('PUT', $p . '/preferences/notifications', $me->putNotificationPreferences(...), ['auth' => true]);
        $r->add('GET', $p . '/save', $save->get(...), ['auth' => true]);
        $r->add('POST', $p . '/sync', $save->sync(...), ['auth' => true]);
        $r->add('GET', $p . '/wallet', $wallet->get(...), ['auth' => true]);
        $r->add('GET', $p . '/wallet/ledger', $wallet->history(...), ['auth' => true]);
        $r->add('POST', $p . '/wallet/operations', $wallet->operations(...), ['auth' => true]);
        $r->add('GET', $p . '/inventory', $wallet->inventory(...), ['auth' => true]);
        $r->add('GET', $p . '/config', $cfg->get(...), ['rate' => 'public']);
        $r->add('GET', $p . '/experiments', function (Request $q, $ctx) {
            $v = $q->query['client_version'] ?? null;
            $v = is_string($v) && preg_match('/^\d+(\.\d+){0,3}$/', $v) ? $v : null;
            return Response::json($this->experiments->forPlayer($ctx->playerId, $v), 200, ['Cache-Control' => 'private, no-store']);
        }, ['auth' => true]);
        $r->add('POST', $p . '/events/batch', $events->batch(...), ['auth' => true]);
        $r->add('POST', $p . '/notifications/{id}/open', $events->notificationOpen(...), ['auth' => true]);
        $r->add('POST', $p . '/devices/register', $devices->register(...), ['auth' => true]);
        $r->add('DELETE', $p . '/devices/{id}', $devices->delete(...), ['auth' => true]);
        $r->add('GET', $p . '/rewards', fn (Request $q, $ctx) => ['rewards' => $this->rewards->list($ctx->playerId)], ['auth' => true]);
        $r->add('POST', $p . '/rewards/{id}/claim', fn (Request $q, $ctx) => $this->rewards->claim($ctx->playerId, $q->params['id']), ['auth' => true]);
        $r->add('POST', $p . '/iap/verify', function (Request $q, $ctx) {
            $in = $q->json();
            return $this->iap->verify($ctx, V::str($in, 'product_id', 1, 100, '/^[a-z0-9_.]+$/'), V::str($in, 'purchase_token', 10, 512));
        }, ['auth' => true, 'rate' => 'iap']);
        $r->add('POST', $p . '/iap/google/rtdn', fn (Request $q) => $this->iap->rtdn($q), ['rate' => 'public']);
    }

    public function handle(Request $req): Response
    {
        if ($req->path === '/admin' || str_starts_with($req->path, '/admin/')) {
            return $this->admin()->handle($req);
        }
        $requestId = Ids::requestId();
        $started = microtime(true);
        $playerId = null;
        try {
            if ($req->method === 'OPTIONS') {
                $response = new Response(204);
            } else {
                [$handler, $opts, $params] = $this->router->match($req->method, $req->path);
                $req->params = $params;
                $this->maintenanceGate($req);
                $ctx = null;
                if (!empty($opts['auth'])) {
                    $ctx = $this->tokens->authenticate($req->bearer());
                    $playerId = $ctx->playerId;
                    $this->limiter->hit('player', (string) $ctx->playerId, $this->config->int('RATE_PLAYER_PER_MINUTE', 120), 60);
                }
                $rate = $opts['rate'] ?? null;
                if ($rate === 'auth') {
                    $this->limiter->hit('auth', $req->ip, $this->config->int('RATE_AUTH_PER_MINUTE', 20), 60);
                } elseif ($rate === 'iap') {
                    $this->limiter->hit('iap', (string) $playerId, $this->config->int('RATE_IAP_PER_MINUTE', 10), 60);
                } elseif ($rate === 'public') {
                    $this->limiter->hit('public', $req->ip, $this->config->int('RATE_PUBLIC_PER_MINUTE', 120), 60);
                }
                $out = $ctx === null ? $handler($req) : $handler($req, $ctx);
                $response = $out instanceof Response ? $out : Response::json($out);
            }
        } catch (ApiException $e) {
            $headers = $e->status === 429 && isset($e->details['retry_after']) ? ['Retry-After' => (string) $e->details['retry_after']] : [];
            $response = Response::json(['error' => ['code' => $e->errorCode, 'message' => $e->getMessage(), 'request_id' => $requestId] + $e->details], $e->status, $headers);
        } catch (\Throwable $e) {
            $this->log->error('unhandled', ['request_id' => $requestId, 'type' => get_class($e), 'msg' => $e->getMessage(), 'at' => basename($e->getFile()) . ':' . $e->getLine()]);
            $response = Response::json(['error' => ['code' => 'internal_error', 'message' => 'Erro interno. Tente novamente.', 'request_id' => $requestId]], 500);
        }
        $response->headers['X-Request-Id'] = $requestId;
        $response->headers['X-Content-Type-Options'] = 'nosniff';
        $response->headers['Cache-Control'] ??= 'no-store';
        $this->log->info('request', [
            'request_id' => $requestId, 'method' => $req->method, 'path' => $req->path, 'status' => $response->status,
            'player' => $playerId, 'ms' => (int) round((microtime(true) - $started) * 1000),
        ]);
        return $response;
    }

    /** Backoffice web (/admin), montado só quando usado. */
    public function admin(): AdminApp
    {
        return $this->admin ??= new AdminApp($this);
    }

    /** Modo manutenção via Remote Config: bloqueia tudo menos health e config. */
    private function maintenanceGate(Request $req): void
    {
        if (str_ends_with($req->path, '/health') || str_ends_with($req->path, '/config') || str_contains($req->path, '/rtdn')) {
            return;
        }
        if ($this->remoteConfig->value('maintenance.enabled', false) === true) {
            throw new ApiException(503, 'maintenance', (string) ($this->remoteConfig->value('maintenance.message') ?? 'Servidor em manutenção.'));
        }
    }

    /** @return array<string,mixed> */
    private function health(): array
    {
        $row = $this->db->one('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1');
        return [
            'status' => 'ok',
            'api_version' => self::API_VERSION,
            'schema_version' => $row['version'] ?? null,
            'environment' => $this->config->str('APP_ENV', 'production'),
            'server_time' => gmdate('Y-m-d\TH:i:s\Z', $this->clock->now()),
        ];
    }
}
