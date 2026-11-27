<?php
declare(strict_types=1);

/**
 * Testes de integração do backend contra um MySQL REAL de teste (sem PHPUnit, sem Composer).
 * O banco indicado é APAGADO e recriado: use somente um banco de teste.
 *
 *   TBF_ENV_FILE=/caminho/test.env php tests/run.php [filtro]
 *
 * Google, Facebook e Google Play são simulados com chaves RSA geradas na hora.
 */

require dirname(__DIR__) . '/src/bootstrap.php';
require __DIR__ . '/FakeHttpClient.php';

use TerraBela\App;
use TerraBela\Auth\Jwt;
use TerraBela\Billing\IapService;
use TerraBela\Core\Clock;
use TerraBela\Core\Config;
use TerraBela\Core\Db;
use TerraBela\Core\Ids;
use TerraBela\Http\Request;
use TerraBela\Http\Response;
use TerraBela\Tests\FakeHttpClient;

$envFile = getenv('TBF_ENV_FILE') ?: dirname(__DIR__) . '/.env.test';
$baseConfig = Config::load($envFile);
if ($baseConfig->str('APP_ENV', '') !== 'local' || !str_contains($baseConfig->str('DB_NAME'), 'test')) {
    fwrite(STDERR, "Recusado: os testes exigem APP_ENV=local e DB_NAME contendo 'test' (o banco é recriado).\n");
    exit(2);
}
$filter = $argv[1] ?? null;
$storage = sys_get_temp_dir() . '/tbf-test-storage-' . getmypid();
$baseConfig = $baseConfig->with('STORAGE_DIR', $storage);

// ---------- banco limpo + migrations ----------
function fresh_db(Config $c): Db
{
    $db = Db::fromConfig($c);
    $db->pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
    foreach ($db->all("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()") as $t) {
        $db->pdo->exec('DROP TABLE `' . $t['TABLE_NAME'] . '`');
    }
    $db->pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
    $files = glob(dirname(__DIR__) . '/database/migrations/*.sql');
    sort($files);
    foreach ($files as $f) {
        $buf = '';
        foreach (preg_split('/\R/', (string) file_get_contents($f)) as $line) {
            if ($buf === '' && (trim($line) === '' || str_starts_with(trim($line), '--'))) {
                continue;
            }
            $buf .= $line . "\n";
            if (str_ends_with(trim($line), ';')) {
                $db->pdo->exec($buf);
                $buf = '';
            }
        }
    }
    return $db;
}

// ---------- provedores simulados ----------
$googleKey = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($googleKey, $googlePem);
$gd = openssl_pkey_get_details($googleKey)['rsa'];
$jwks = ['keys' => [['kty' => 'RSA', 'kid' => 'test-kid', 'alg' => 'RS256', 'use' => 'sig', 'n' => Ids::b64urlEncode($gd['n']), 'e' => Ids::b64urlEncode($gd['e'])]]];

$saKey = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($saKey, $saPem);
@mkdir($storage, 0700, true);
$saFile = $storage . '/sa.json';
file_put_contents($saFile, json_encode(['client_email' => 'play@test.iam.gserviceaccount.com', 'private_key' => $saPem, 'private_key_id' => 'k1', 'token_uri' => 'https://oauth2.googleapis.com/token']));

/** Estado das compras simuladas na Google Play: token => resposta ProductPurchase */
$playPurchases = [];
$http = new FakeHttpClient();
$http->on('GET', 'https://www.googleapis.com/oauth2/v3/certs', fn () => [200, $jwks, ['cache-control' => 'public, max-age=3600']]);
$appleKey = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($appleKey, $applePem);
$ad = openssl_pkey_get_details($appleKey)['rsa'];
$http->on('GET', 'https://appleid.apple.com/auth/keys', fn () => [200, ['keys' => [['kty' => 'RSA', 'kid' => 'apple-kid', 'alg' => 'RS256', 'use' => 'sig', 'n' => Ids::b64urlEncode($ad['n']), 'e' => Ids::b64urlEncode($ad['e'])]]], ['cache-control' => 'public, max-age=3600']]);
$http->on('POST', 'https://oauth2.googleapis.com/token', fn () => [200, ['access_token' => 'ya29.fake', 'expires_in' => 3600]]);
$http->on('GET', 'https://graph.facebook.com/', function (string $url) {
    parse_str((string) parse_url($url, PHP_URL_QUERY), $q);
    if ($q['input_token'] === 'fb-valid-token-user-77') {
        return [200, ['data' => ['is_valid' => true, 'app_id' => '1234', 'user_id' => '77']]];
    }
    return [200, ['data' => ['is_valid' => false]]];
});
$playBase = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.terrabela.farm/purchases/products/';
$http->on('GET', $playBase, function (string $url) use (&$playPurchases) {
    $token = rawurldecode(substr($url, strrpos($url, '/') + 1));
    return isset($playPurchases[$token]) ? [200, $playPurchases[$token]] : [404, ['error' => 'not found']];
});
$http->on('POST', $playBase, function (string $url) use (&$playPurchases) {
    preg_match('#/tokens/([^/:]+):(consume|acknowledge)$#', $url, $m);
    $token = rawurldecode($m[1]);
    if ($m[2] === 'consume') {
        $playPurchases[$token]['consumptionState'] = 1;
    } else {
        $playPurchases[$token]['acknowledgementState'] = 1;
    }
    return [204, ''];
});

function google_jwt(string $pem, array $claims): string
{
    return Jwt::signRs256($claims, $pem, 'test-kid');
}

// ---------- mini framework ----------
$results = ['pass' => 0, 'fail' => 0];
$current = '';
function check(bool $cond, string $msg): void
{
    global $results, $current;
    if ($cond) {
        $results['pass']++;
    } else {
        $results['fail']++;
        echo "    FALHOU [$current] $msg\n";
    }
}
function eq(mixed $expected, mixed $actual, string $msg): void
{
    check($expected === $actual, $msg . ' (esperado ' . json_encode($expected) . ', obtido ' . json_encode($actual) . ')');
}

final class Client
{
    public ?string $access = null;
    public array $last = [];
    public function __construct(public App $app)
    {
    }
    public function call(string $method, string $path, ?array $body = null, array $headers = [], array $query = []): Response
    {
        if ($this->access !== null && !isset($headers['authorization'])) {
            $headers['authorization'] = 'Bearer ' . $this->access;
        }
        $headers['user-agent'] ??= 'TerraBelaFarm-Test/0.1';
        $raw = $body === null ? '' : json_encode($body);
        $r = $this->app->handle(new Request($method, '/api/v1' . $path, $headers, $query, $raw, '10.0.0.1'));
        $this->last = $r->data();
        return $r;
    }
    public function guest(): array
    {
        $r = $this->call('POST', '/auth/guest', ['locale' => 'pt_BR']);
        $this->access = $this->last['access_token'];
        return $this->last;
    }
}

$tests = [];
function test(string $name, callable $fn): void
{
    global $tests;
    $tests[$name] = $fn;
}

$clock = new Clock();
$makeApp = function (array $overrides = []) use (&$baseConfig, $http, $clock, $saFile): App {
    $c = $baseConfig->with('GOOGLE_PLAY_SERVICE_ACCOUNT_FILE', $saFile)->with('RATE_AUTH_PER_MINUTE', '100000');
    foreach ($overrides as $k => $v) {
        $c = $c->with($k, $v);
    }
    return new App($c, Db::fromConfig($c), $http, $clock);
};

// =====================================================================
test('health e rota inexistente', function () use ($makeApp) {
    $c = new Client($makeApp());
    $r = $c->call('GET', '/health');
    eq(200, $r->status, 'health 200');
    eq('006_apple_login', $c->last['schema_version'], 'versão do schema');
    check(isset($r->headers['X-Request-Id']), 'X-Request-Id presente');
    eq(404, $c->call('GET', '/nao-existe')->status, '404');
    eq(405, $c->call('DELETE', '/health')->status, '405');
    eq(401, $c->call('GET', '/me')->status, 'sem token 401');
    eq(400, $c->app->handle(new Request('POST', '/api/v1/auth/guest', [], [], '{quebrado', '1.1.1.1'))->status, 'JSON inválido 400');
});

test('visitante: criar, entrar de novo, segredo errado', function () use ($makeApp) {
    $c = new Client($makeApp());
    $g = $c->guest();
    check($g['created'] === true && strlen($g['guest_secret']) > 30 && str_starts_with($g['access_token'], 'tbfa_'), 'conta criada com segredo e tokens');
    $r = $c->call('GET', '/me');
    eq(200, $r->status, 'GET /me');
    eq($g['player_id'], $c->last['player_id'], 'mesmo player_id');
    eq(['cash' => 0, 'gold' => 0], $c->last['wallet'], 'carteira zerada');
    eq('guest', $c->last['identities'][0]['provider'], 'vínculo guest');
    eq(false, $c->last['notification_preferences']['promotional'], 'promocional começa desligado');

    $c2 = new Client($c->app);
    $c2->call('POST', '/auth/guest', ['guest_id' => $g['guest_id'], 'guest_secret' => $g['guest_secret']]);
    eq(false, $c2->last['created'], 'login de volta não cria conta');
    eq($g['player_id'], $c2->last['player_id'], 'mesma fazenda');
    check(!isset($c2->last['guest_secret']), 'segredo não é devolvido de novo');
    $r = $c2->call('POST', '/auth/guest', ['guest_id' => $g['guest_id'], 'guest_secret' => 'tbfg_errado_errado_errado']);
    eq(401, $r->status, 'segredo errado 401');
    $db = $c->app->db;
    $row = $db->one("SELECT secret_hash FROM player_identities WHERE subject = ?", [$g['guest_id']]);
    check($row['secret_hash'] !== $g['guest_secret'] && strlen($row['secret_hash']) === 64, 'segredo guardado só como HMAC');
    check($db->one('SELECT COUNT(*) n FROM player_sessions WHERE access_hash = ?', [$g['access_token']])['n'] == 0, 'token não fica em claro');
});

test('refresh rotativo, reuso revoga, logout', function () use ($makeApp, $clock) {
    $c = new Client($makeApp());
    $g = $c->guest();
    $c->call('POST', '/auth/refresh', ['refresh_token' => $g['refresh_token']]);
    $new = $c->last;
    check(isset($new['access_token']) && $new['refresh_token'] !== $g['refresh_token'], 'novos tokens');
    $c->access = $g['access_token'];
    eq(401, $c->call('GET', '/me')->status, 'access antigo deixou de valer');
    $c->access = $new['access_token'];
    eq(200, $c->call('GET', '/me')->status, 'access novo vale');
    $r = $c->call('POST', '/auth/refresh', ['refresh_token' => $g['refresh_token']]);
    eq(401, $r->status, 'reuso do refresh antigo');
    eq('refresh_token_reused', $c->last['error']['code'], 'código refresh_token_reused');
    eq(401, $c->call('GET', '/me')->status, 'sessão revogada após reuso');
    eq(401, $c->call('POST', '/auth/refresh', ['refresh_token' => $new['refresh_token']])->status, 'refresh atual também morre');

    $c->guest();
    eq(200, $c->call('POST', '/auth/logout')->status, 'logout');
    eq(401, $c->call('GET', '/me')->status, 'após logout 401');

    $g2 = $c->guest();
    $clock->advance(3601);
    eq('token_expired', ($c->call('GET', '/me') && true) ? $c->last['error']['code'] : null, 'access expira em 1h');
    eq(200, $c->call('POST', '/auth/refresh', ['refresh_token' => $g2['refresh_token']])->status, 'refresh renova após expirar');
    $clock->set(null);
});

test('save na nuvem: revisão, idempotência, conflito, histórico, limite', function () use ($makeApp) {
    $app = $makeApp(['SAVE_HISTORY' => '2']);
    $c = new Client($app);
    $c->guest();
    $c->call('GET', '/save');
    eq(0, $c->last['revision'], 'sem save: revisão 0');
    $snap = ['farm' => ['plots' => [['crop' => 'tomato', 'stage' => 2]]], 'wallet' => ['cash' => 999999, 'gold' => 999999]];
    $body = ['operation_id' => 'op-save-0001', 'base_revision' => 0, 'schema_version' => 1, 'snapshot' => $snap, 'client_saved_at' => '2026-11-27T10:00:00-03:00'];
    eq(200, $c->call('POST', '/sync', $body)->status, 'primeiro sync');
    eq(1, $c->last['revision'], 'revisão 1');
    eq(0, $c->last['wallet']['cash'], 'saldo do snapshot é ignorado (servidor é autoridade)');
    $c->call('POST', '/sync', $body);
    eq(true, $c->last['replayed'], 'repetição devolve resposta original');
    eq(1, $c->last['revision'], 'repetição não cria revisão');
    $body2 = $body;
    $body2['snapshot']['farm']['plots'][0]['stage'] = 3;
    eq(409, $c->call('POST', '/sync', $body2)->status, 'mesmo operation_id com outro conteúdo');
    eq('idempotency_mismatch', $c->last['error']['code'], 'código idempotency_mismatch');
    $stale = ['operation_id' => 'op-save-0002', 'base_revision' => 0, 'schema_version' => 1, 'snapshot' => ['x' => 1]];
    eq(409, $c->call('POST', '/sync', $stale)->status, 'base_revision velha → conflito');
    eq('save_conflict', $c->last['error']['code'], 'código save_conflict');
    eq(1, $c->last['error']['current_revision'], 'conflito informa revisão atual');
    for ($i = 2; $i <= 5; $i++) {
        $c->call('POST', '/sync', ['operation_id' => "op-save-000$i-b", 'base_revision' => $i - 1, 'schema_version' => 1, 'snapshot' => ['rev' => $i]]);
    }
    eq(5, $c->last['revision'], 'revisão 5');
    $c->call('GET', '/save');
    eq(['rev' => 5], $c->last['snapshot'], 'GET /save devolve o último');
    $hist = $app->db->all('SELECT revision FROM player_save_versions ORDER BY revision');
    eq([3, 4], array_map(fn ($r) => (int) $r['revision'], $hist), 'histórico podado para SAVE_HISTORY=2');
    $big = ['operation_id' => 'op-save-big1', 'base_revision' => 5, 'schema_version' => 1, 'snapshot' => ['blob' => str_repeat('a', 270000)]];
    eq(413, $c->call('POST', '/sync', $big)->status, 'snapshot acima do limite');
    eq(422, $c->call('POST', '/sync', ['operation_id' => 'op-save-list', 'base_revision' => 5, 'schema_version' => 1, 'snapshot' => [1, 2]])->status, 'snapshot lista rejeitado');
});

test('ledger: política do cliente, idempotência, saldo, teto diário', function () use ($makeApp) {
    $app = $makeApp();
    $c = new Client($app);
    $c->guest();
    $ops = fn (array ...$o) => $c->call('POST', '/wallet/operations', ['operations' => $o]);
    $ops(['operation_id' => 'sale-0001', 'currency' => 'cash', 'amount' => 1200, 'reason' => 'sale_collected', 'reference' => 'counter']);
    eq('applied', $c->last['results'][0]['status'], 'crédito de venda aplicado');
    eq(1200, $c->last['wallet']['cash'], 'saldo 1200');
    $ops(['operation_id' => 'sale-0001', 'currency' => 'cash', 'amount' => 1200, 'reason' => 'sale_collected']);
    eq(true, $c->last['results'][0]['replayed'], 'replay não duplica');
    eq(1200, $c->last['wallet']['cash'], 'saldo continua 1200');
    $ops(['operation_id' => 'sale-0001', 'currency' => 'cash', 'amount' => 1300, 'reason' => 'sale_collected']);
    eq('idempotency_mismatch', $c->last['results'][0]['error']['code'], 'mesma chave com outro valor');
    $ops(['operation_id' => 'gold-hack1', 'currency' => 'gold', 'amount' => 500, 'reason' => 'sale_collected']);
    eq('credit_not_allowed', $c->last['results'][0]['error']['code'], 'app não credita gold');
    $ops(['operation_id' => 'cash-hack1', 'currency' => 'cash', 'amount' => 100, 'reason' => 'free_money']);
    eq('credit_not_allowed', $c->last['results'][0]['error']['code'], 'motivo não permitido');
    $ops(['operation_id' => 'cash-big01', 'currency' => 'cash', 'amount' => 5001, 'reason' => 'sale_collected']);
    eq('credit_over_limit', $c->last['results'][0]['error']['code'], 'acima do teto por operação');
    $ops(['operation_id' => 'hire-00001', 'currency' => 'cash', 'amount' => -2000, 'reason' => 'helper_hired']);
    eq('insufficient_funds', $c->last['results'][0]['error']['code'], 'saldo insuficiente');
    $ops(['operation_id' => 'hire-00002', 'currency' => 'cash', 'amount' => -200, 'reason' => 'helper_hired'], ['operation_id' => 'bad-debit1', 'currency' => 'cash', 'amount' => -1, 'reason' => 'whatever']);
    eq('applied', $c->last['results'][0]['status'], 'débito permitido');
    eq('debit_not_allowed', $c->last['results'][1]['error']['code'], 'débito com motivo desconhecido');
    eq(1000, $c->last['wallet']['cash'], 'saldo 1000');
    $batch = [];
    for ($i = 0; $i < 41; $i++) {
        $batch[] = ['operation_id' => sprintf('daily-%04d', $i), 'currency' => 'cash', 'amount' => 5000, 'reason' => 'sale_collected'];
    }
    $c->call('POST', '/wallet/operations', ['operations' => $batch]);
    $applied = count(array_filter($c->last['results'], fn ($r) => $r['status'] === 'applied'));
    eq(39, $applied, 'teto diário 200000 (1200 + 39×5000 ≤ 200000)');
    eq('daily_credit_limit', end($c->last['results'])['error']['code'], 'excesso barrado pelo teto diário');
    $c->call('GET', '/wallet/ledger', null, [], ['limit' => '5']);
    eq(5, count($c->last['items']), 'histórico paginado');
    check($c->last['next_before'] !== null, 'cursor para próxima página');
    $sum = $app->db->one('SELECT SUM(amount) s FROM economy_ledger')['s'];
    $c->call('GET', '/wallet');
    eq((int) $sum, $c->last['cash'], 'saldo = soma do ledger');
});

test('ledger: concorrência real (processos paralelos)', function () use ($makeApp, &$baseConfig) {
    if (!function_exists('pcntl_fork')) {
        check(true, 'pcntl indisponível, teste pulado');
        return;
    }
    $app = $makeApp();
    $c = new Client($app);
    $g = $c->guest();
    $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($g['player_id'])])['id'];
    $children = [];
    for ($w = 0; $w < 8; $w++) {
        $child = pcntl_fork();
        if ($child === 0) {
            $db = Db::fromConfig($baseConfig);
            $ledger = new TerraBela\Economy\LedgerService($db, new Clock());
            for ($i = 0; $i < 25; $i++) {
                $ledger->post($pid, 'cash', 10, 'system', 'test', null, "par-$w-$i");
                $ledger->post($pid, 'cash', 7, 'system', 'test', null, "same-$i"); // mesma chave em todos os processos
            }
            file_put_contents(sys_get_temp_dir() . "/tbf-par-$w.ok", 'ok');
            // SIGKILL evita que o filho feche a conexão MySQL herdada do processo pai.
            posix_kill(getmypid(), SIGKILL);
        }
        $children[] = $child;
    }
    $ok = true;
    foreach ($children as $ch) {
        pcntl_waitpid($ch, $st);
    }
    for ($w = 0; $w < 8; $w++) {
        $f = sys_get_temp_dir() . "/tbf-par-$w.ok";
        $ok = $ok && is_file($f);
        @unlink($f);
    }
    check($ok, 'todos os processos terminaram sem erro');
    $c->call('GET', '/wallet');
    eq(8 * 25 * 10 + 25 * 7, $c->last['cash'], 'saldo exato sob concorrência (sem crédito duplicado)');
    eq(8 * 25 + 25, (int) $app->db->one('SELECT COUNT(*) n FROM economy_ledger WHERE player_id = ?', [$pid])['n'], 'número de lançamentos exato');
});

test('remote config: ETag, versão do cliente, rollback, manutenção', function () use ($makeApp) {
    $app = $makeApp();
    $c = new Client($app);
    $r = $c->call('GET', '/config', null, [], ['client_version' => '0.3.0']);
    eq(200, $r->status, 'config publicada');
    eq(1, $c->last['version'], 'versão 1');
    $etag = $r->headers['ETag'];
    eq(304, $c->call('GET', '/config', null, ['if-none-match' => $etag])->status, '304 com ETag igual');
    $payload = json_decode((string) file_get_contents(dirname(__DIR__) . '/config/remote-config.default.json'), true);
    $payload['features']['store_enabled'] = true;
    $v2 = $app->remoteConfig->publish($payload, 'teste loja', 'test', '0.5.0');
    eq(2, $v2, 'publicou v2');
    $c->call('GET', '/config', null, [], ['client_version' => '0.3.0']);
    eq(1, $c->last['version'], 'app antigo continua na v1 (min_client_version)');
    $r = $c->call('GET', '/config', null, ['if-none-match' => $etag], ['client_version' => '0.5.1']);
    eq(2, $c->last['version'], 'app novo recebe v2');
    $app->remoteConfig->retire(2);
    $c->call('GET', '/config', null, [], ['client_version' => '0.5.1']);
    eq(1, $c->last['version'], 'rollback volta para v1');
    $bad = $payload;
    $bad['economy']['client_credit']['gold'] = ['reasons' => ['x'], 'max_per_operation' => 1, 'max_per_day' => 1];
    $threw = false;
    try {
        $app->remoteConfig->publish($bad, 'tentativa', 'test');
    } catch (InvalidArgumentException) {
        $threw = true;
    }
    check($threw, 'config que deixa o app creditar gold é recusada');
    $m = $payload;
    $m['maintenance'] = ['enabled' => true, 'message' => 'Volte em 10 minutos'];
    $app->remoteConfig->publish($m, 'manutenção', 'test');
    $c2 = new Client($makeApp());
    eq(503, $c2->call('POST', '/auth/guest', [])->status, 'manutenção bloqueia login');
    eq('Volte em 10 minutos', $c2->last['error']['message'], 'mensagem de manutenção');
    eq(200, $c2->call('GET', '/health')->status, 'health segue ok');
    $app->db->exec("UPDATE remote_config_versions SET status = 'retired' WHERE version_number > 1");
});

test('Google: login, audience errada, vínculo e conflito de fazendas', function () use ($makeApp, $googlePem, $clock) {
    $app = $makeApp();
    $now = time();
    $claims = ['iss' => 'https://accounts.google.com', 'aud' => 'test-client.apps.googleusercontent.com', 'sub' => 'g-sub-1', 'iat' => $now, 'exp' => $now + 600, 'email' => 'x@example.com'];
    $c = new Client($app);
    $c->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, $claims)]);
    eq(true, $c->last['created'], 'primeiro login Google cria fazenda');
    $farmGoogle = $c->last['player_id'];
    $c->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, $claims)]);
    eq($farmGoogle, $c->last['player_id'], 'segundo login volta para a mesma fazenda');
    eq(401, $c->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, ['aud' => 'outro-app'] + $claims)])->status, 'audience errada');
    eq(401, $c->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, ['exp' => $now - 3600] + $claims)])->status, 'token expirado');
    $other = openssl_pkey_new(['private_key_bits' => 2048]);
    openssl_pkey_export($other, $otherPem);
    eq(401, $c->call('POST', '/auth/google', ['id_token' => google_jwt($otherPem, $claims)])->status, 'assinatura de outra chave');
    eq(401, $c->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, $claims), 'nonce' => 'n-esperado'])->status, 'nonce exigido e ausente');

    $v = new Client($app);
    $guest = $v->guest();
    $claims2 = ['sub' => 'g-sub-2'] + $claims;
    $v->call('POST', '/auth/link', ['provider' => 'google', 'id_token' => google_jwt($googlePem, $claims2)]);
    eq(true, $v->last['linked'], 'visitante vinculou Google');
    $n = new Client($app);
    $n->call('POST', '/auth/google', ['id_token' => google_jwt($googlePem, $claims2)]);
    eq($guest['player_id'], $n->last['player_id'], 'novo aparelho recupera a fazenda do visitante');
    $r = $v->call('POST', '/auth/link', ['provider' => 'google', 'id_token' => google_jwt($googlePem, $claims)]);
    eq(409, $r->status, 'Google já usado em outra fazenda');
    eq('account_conflict', $v->last['error']['code'], 'código account_conflict');
    eq($farmGoogle, $v->last['error']['other_farm']['player_id'], 'conflito mostra a outra fazenda');
    eq($guest['player_id'], $v->last['error']['current_farm']['player_id'], 'e a fazenda atual');
});

test('Facebook: debug_token válido e inválido', function () use ($makeApp) {
    $c = new Client($makeApp());
    $c->call('POST', '/auth/facebook', ['access_token' => 'fb-valid-token-user-77']);
    eq(true, $c->last['created'] ?? null, 'login Facebook criou fazenda');
    eq(401, $c->call('POST', '/auth/facebook', ['access_token' => 'fb-token-invalido-xyz'])->status, 'token inválido 401');
    $nf = new Client($makeApp(['FACEBOOK_APP_ID' => '']));
    eq(503, $nf->call('POST', '/auth/facebook', ['access_token' => 'fb-valid-token-user-77'])->status, 'sem configuração → 503');
});

test('telemetria, abertura de push, dispositivos e preferências', function () use ($makeApp) {
    $app = $makeApp();
    $c = new Client($app);
    $c->guest();
    $c->call('POST', '/events/batch', ['events' => [
        ['event_id' => 'evt-00000001', 'name' => 'first_open', 'occurred_at' => '2026-11-27T12:00:00Z', 'app_version' => '0.3.0'],
        ['event_id' => 'evt-00000002', 'name' => 'crop_harvested', 'properties' => ['crop' => 'tomato', 'qty' => 5]],
        ['event_id' => 'evt-00000003', 'name' => 'hack_event'],
        ['event_id' => 'evt-00000004', 'name' => 'level_up', 'properties' => ['email' => 'a@b.c']],
    ]]);
    eq(2, $c->last['accepted'], '2 eventos aceitos');
    eq(2, count($c->last['rejected']), 'nome fora da lista e propriedade pessoal rejeitados');
    $c->call('POST', '/events/batch', ['events' => [['event_id' => 'evt-00000001', 'name' => 'first_open']]]);
    eq(1, $c->last['duplicates'], 'evento repetido ignorado');
    $c->call('POST', '/notifications/N-123/open', ['campaign_id' => 'C-42']);
    eq(true, $c->last['recorded'], 'abertura registrada');
    $c->call('POST', '/notifications/N-123/open', []);
    eq(true, $c->last['already_recorded'], 'abertura idempotente');

    $c->call('POST', '/devices/register', ['installation_id' => 'inst-aaaa-1111', 'platform' => 'android', 'fcm_token' => 'fcm:TOKEN_abc-123', 'app_version' => '0.3.0', 'locale' => 'pt_BR', 'timezone' => 'America/Sao_Paulo']);
    $dev = $c->last['device_id'];
    eq(true, $c->last['push_registered'], 'token FCM registrado');
    $c->call('POST', '/devices/register', ['installation_id' => 'inst-aaaa-1111', 'platform' => 'android', 'fcm_token' => 'fcm:TOKEN_abc-123']);
    eq($dev, $c->last['device_id'], 'mesma instalação não duplica');
    $o = new Client($app);
    $o->guest();
    $o->call('POST', '/devices/register', ['installation_id' => 'inst-bbbb-2222', 'platform' => 'android', 'fcm_token' => 'fcm:TOKEN_abc-123']);
    eq(1, (int) $app->db->one("SELECT COUNT(*) n FROM player_devices WHERE fcm_token = 'fcm:TOKEN_abc-123'")['n'], 'token FCM pertence a uma instalação só');
    eq(404, $o->call('DELETE', '/devices/' . $dev)->status, 'outro jogador não revoga meu aparelho');
    eq(200, $c->call('DELETE', '/devices/' . $dev)->status, 'dono revoga');
    $c->call('PUT', '/preferences/notifications', ['promotional' => true, 'os_permission_granted' => true, 'source' => 'os_prompt']);
    eq(['operational' => true, 'promotional' => true, 'os_permission_granted' => true], $c->last['notification_preferences'], 'preferências gravadas');
    $c->call('PUT', '/preferences/notifications', ['promotional' => false]);
    eq(false, $c->last['notification_preferences']['promotional'], 'opt-out');
    eq(3, (int) $app->db->one('SELECT COUNT(*) n FROM player_consents')['n'], 'histórico append-only');
});

test('recompensas: concessão única, resgate idempotente, expiração, acesso cruzado', function () use ($makeApp, $clock) {
    $app = $makeApp();
    $c = new Client($app);
    $g = $c->guest();
    $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($g['player_id'])])['id'];
    $r1 = $app->rewards->grant($pid, 'welcome_v1', 'once', 'gold', 50, null, 86400);
    $r1b = $app->rewards->grant($pid, 'welcome_v1', 'once', 'gold', 50, null, 86400);
    eq(false, $r1b['created'], 'mesma ocorrência não concede de novo');
    eq($r1['reward_id'], $r1b['reward_id'], 'devolve o mesmo benefício');
    $c->call('GET', '/rewards');
    eq('available', $c->last['rewards'][0]['status'], 'benefício disponível');
    $o = new Client($app);
    $o->guest();
    eq(404, $o->call('POST', '/rewards/' . $r1['reward_id'] . '/claim')->status, 'outro jogador não resgata');
    $c->call('POST', '/rewards/' . $r1['reward_id'] . '/claim');
    eq(50, $c->last['wallet']['gold'], 'gold creditado no resgate');
    $c->call('POST', '/rewards/' . $r1['reward_id'] . '/claim');
    eq(true, $c->last['replayed'], 'segundo resgate é replay');
    eq(50, $c->last['wallet']['gold'], 'sem crédito duplicado');
    $r2 = $app->rewards->grant($pid, 'comeback_3d_v1', '2026-W48', 'cash', 300, null, 60);
    $clock->advance(120);
    $c->call('POST', '/rewards/' . $r2['reward_id'] . '/claim');
    eq(true, $c->last['expired'] ?? null, 'expirado não credita: ' . json_encode($c->last));
    $clock->set(null);
});

test('IAP Google Play: pendente, concedido, replay, outra conta, RTDN reembolso', function () use ($makeApp, $googlePem, &$playPurchases, $http) {
    $app = $makeApp();
    $app->db->exec("INSERT INTO iap_products (platform, sku, product_type, benefit_version, benefit, active) VALUES ('google_play', 'gold_pack_100', 'consumable', 1, '{\"currency\":\"gold\",\"amount\":100}', 1)");
    $app->db->exec("INSERT INTO iap_products (platform, sku, product_type, benefit_version, benefit, active) VALUES ('google_play', 'helper_slot', 'non_consumable', 1, '{\"entitlements\":[\"helper_slot_extra\"]}', 1)");
    $c = new Client($app);
    $g = $c->guest();
    $acct = IapService::obfuscatedAccountId($g['player_id']);
    $tok = 'purchase-token-' . bin2hex(random_bytes(8));
    $playPurchases[$tok] = ['kind' => 'androidpublisher#productPurchase', 'purchaseState' => 2, 'consumptionState' => 0, 'acknowledgementState' => 0, 'obfuscatedExternalAccountId' => $acct];
    $c->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok]);
    eq('pending', $c->last['status'], 'compra pendente não concede');
    eq(0, $c->last['wallet']['gold'], 'gold continua 0');
    $playPurchases[$tok] = ['purchaseState' => 0, 'orderId' => 'GPA.1111-2222', 'purchaseTimeMillis' => '1764240000000'] + $playPurchases[$tok];
    $c->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok]);
    eq('granted', $c->last['status'], 'compra confirmada concede');
    eq(100, $c->last['wallet']['gold'], 'gold 100');
    eq(1, $playPurchases[$tok]['consumptionState'], 'consumível foi consumido na Google');
    $calls = $http->count(':consume');
    $c->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok]);
    eq(true, $c->last['replayed'], 'repetição é replay');
    eq(100, $c->last['wallet']['gold'], 'sem crédito duplicado');
    eq($calls, $http->count(':consume'), 'não consome de novo');
    $o = new Client($app);
    $o->guest();
    eq(409, $o->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok])->status, 'token de outra conta');
    $tok2 = 'purchase-token-' . bin2hex(random_bytes(8));
    $playPurchases[$tok2] = ['purchaseState' => 0, 'consumptionState' => 0, 'acknowledgementState' => 0, 'orderId' => 'GPA.3333', 'obfuscatedExternalAccountId' => $acct];
    eq(403, $o->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok2])->status, 'compra feita por outra conta (obfuscatedAccountId)');
    eq(422, $c->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => 'token-que-nao-existe'])->status, 'token desconhecido na Google');
    eq(404, $c->call('POST', '/iap/verify', ['product_id' => 'nao_existe', 'purchase_token' => $tok2])->status, 'SKU fora do catálogo');
    $tok3 = 'purchase-token-' . bin2hex(random_bytes(8));
    $playPurchases[$tok3] = ['purchaseState' => 0, 'consumptionState' => 0, 'acknowledgementState' => 0, 'orderId' => 'GPA.4444', 'obfuscatedExternalAccountId' => $acct];
    $c->call('POST', '/iap/verify', ['product_id' => 'helper_slot', 'purchase_token' => $tok3]);
    eq('granted', $c->last['status'], 'permanente concedido');
    eq(1, $playPurchases[$tok3]['acknowledgementState'], 'permanente foi reconhecido (acknowledge)');
    $c->call('GET', '/inventory');
    eq('helper_slot_extra', $c->last['entitlements'][0]['key'] ?? null, 'direito no inventário');

    // RTDN: reembolso do permanente
    $now = time();
    $oidc = google_jwt($googlePem, ['iss' => 'https://accounts.google.com', 'aud' => 'https://example.test/rtdn', 'email' => 'rtdn@test.iam.gserviceaccount.com', 'email_verified' => true, 'sub' => '1', 'iat' => $now, 'exp' => $now + 600]);
    $msg = ['message' => ['messageId' => 'm-1', 'data' => base64_encode(json_encode(['version' => '1.0', 'packageName' => 'com.terrabela.farm', 'voidedPurchaseNotification' => ['purchaseToken' => $tok3, 'orderId' => 'GPA.4444', 'productType' => 2]]))], 'subscription' => 'x'];
    $r = new Client($app);
    eq(401, $r->call('POST', '/iap/google/rtdn', $msg, ['authorization' => 'Bearer x.y.z'])->status, 'RTDN sem OIDC válido');
    $bad = google_jwt($googlePem, ['email' => 'intruso@evil.test'] + JWT::decode($oidc)['payload']);
    eq(403, $r->call('POST', '/iap/google/rtdn', $msg, ['authorization' => 'Bearer ' . $bad])->status, 'RTDN de outra conta de serviço');
    $r->call('POST', '/iap/google/rtdn', $msg, ['authorization' => 'Bearer ' . $oidc]);
    eq('refunded', $r->last['processed'] ?? null, 'reembolso processado');
    $r->call('POST', '/iap/google/rtdn', $msg, ['authorization' => 'Bearer ' . $oidc]);
    eq(true, $r->last['duplicate'] ?? null, 'mensagem repetida ignorada');
    $c->call('GET', '/inventory');
    eq([], $c->last['entitlements'], 'direito revogado');
    $payloads = $app->db->all('SELECT payload FROM iap_events');
    check(!str_contains(json_encode($payloads), $tok3), 'purchase token não fica em claro nos eventos');
});

test('exclusão de conta e purge do cron', function () use ($makeApp, $clock, &$baseConfig) {
    $app = $makeApp();
    $c = new Client($app);
    $g = $c->guest();
    $c->call('POST', '/sync', ['operation_id' => 'op-del-0001', 'base_revision' => 0, 'schema_version' => 1, 'snapshot' => ['a' => 1]]);
    $c->call('POST', '/wallet/operations', ['operations' => [['operation_id' => 'sale-del-01', 'currency' => 'cash', 'amount' => 10, 'reason' => 'sale_collected']]]);
    $c->call('DELETE', '/me');
    eq(true, $c->last['deletion_requested'], 'exclusão pedida');
    eq(401, $c->call('GET', '/me')->status, 'sessões revogadas');
    $c2 = new Client($app);
    eq(403, $c2->call('POST', '/auth/guest', ['guest_id' => $g['guest_id'], 'guest_secret' => $g['guest_secret']])->status, 'conta não entra mais');
    $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($g['player_id'])])['id'];
    $app->db->exec('UPDATE players SET deletion_requested_at = ? WHERE id = ?', [gmdate('Y-m-d H:i:s', time() - 31 * 86400), $pid]);
    $env = getenv('TBF_ENV_FILE');
    $out = shell_exec('TBF_ENV_FILE=' . escapeshellarg((string) $env) . ' php ' . escapeshellarg(dirname(__DIR__) . '/bin/cron.php') . ' 2>&1');
    check(str_contains((string) $out, '"accounts_purged":1'), 'cron purgou a conta: ' . trim((string) $out));
    eq('deleted', $app->db->one('SELECT status FROM players WHERE id = ?', [$pid])['status'], 'status deleted');
    eq(0, (int) $app->db->one('SELECT COUNT(*) n FROM player_identities WHERE player_id = ?', [$pid])['n'], 'identidades removidas');
    eq(0, (int) $app->db->one('SELECT COUNT(*) n FROM player_saves WHERE player_id = ?', [$pid])['n'], 'save removido');
    eq(1, (int) $app->db->one('SELECT COUNT(*) n FROM economy_ledger WHERE player_id = ?', [$pid])['n'], 'ledger mantido para auditoria');
});

test('rate limit no login', function () use ($makeApp) {
    $c = new Client($makeApp(['RATE_AUTH_PER_MINUTE' => '3']));
    $c->app->db->exec('DELETE FROM rate_limits');
    $codes = [];
    for ($i = 0; $i < 5; $i++) {
        $codes[] = $c->call('POST', '/auth/guest', [])->status;
    }
    eq([200, 200, 200, 429, 429], $codes, '4ª tentativa por minuto bloqueada');
});

// ===================================================================== TBF-MVP backoffice / LiveOps

final class AdminClient
{
    public array $cookies = [];
    public ?Response $last = null;
    public function __construct(public App $app)
    {
    }
    public function req(string $method, string $path, array $form = [], array $query = [], string $ip = '10.0.0.9'): Response
    {
        $r = $this->app->handle(new Request($method, '/admin' . ($path === '' ? '' : '/' . $path), ['host' => 'example.test', 'user-agent' => 'AdminTest'], $query, http_build_query($form), $ip, $this->cookies, '', true));
        foreach ($r->cookies as $c) {
            [$kv] = explode(';', $c, 2);
            [$k, $v] = explode('=', $kv, 2);
            if (preg_match('/Max-Age=0\b/', $c)) {
                unset($this->cookies[$k]);
            } else {
                $this->cookies[$k] = rawurldecode($v);
            }
        }
        return $this->last = $r;
    }
    public function csrf(): string
    {
        $r = $this->req('GET', 'account');
        preg_match('/name="_csrf" value="([a-f0-9]{64})"/', $r->body, $m);
        return $m[1] ?? '';
    }
    public function post(string $path, array $form = []): Response
    {
        return $this->req('POST', $path, $form + ['_csrf' => $this->csrf()]);
    }
    public function flash(): string
    {
        if (!isset($this->cookies['tbf_admin_flash'])) {
            return '';
        }
        $f = json_decode((string) base64_decode(explode('.', $this->cookies['tbf_admin_flash'])[0]), true);
        return (string) ($f['text'] ?? '');
    }
    public function login(string $email, string $password): Response
    {
        return $this->req('POST', 'login', ['email' => $email, 'password' => $password]);
    }
}

/** Cria operador pelo link de configuração e devolve [email, senha]. */
function make_admin(App $app, string $role, string $email): array
{
    $r = $app->admin()->auth->createUser($email, ucfirst($role), $role);
    $pwd = 'Senha-Forte-' . bin2hex(random_bytes(4));
    $app->admin()->auth->completeSetup($r['token'], $pwd, $pwd);
    return [$email, $pwd];
}

test('IP real via Cloudflare (CF-Connecting-IP só de faixas da Cloudflare)', function () {
    check(\TerraBela\Http\CloudflareIps::contains('173.245.48.5'), 'IPv4 da Cloudflare');
    check(\TerraBela\Http\CloudflareIps::contains('104.16.1.1'), 'IPv4 /13 da Cloudflare');
    check(\TerraBela\Http\CloudflareIps::contains('2606:4700::1111'), 'IPv6 da Cloudflare');
    check(!\TerraBela\Http\CloudflareIps::contains('8.8.8.8'), 'IP comum não é Cloudflare');
    check(!\TerraBela\Http\CloudflareIps::contains('lixo'), 'valor inválido');
    eq('200.1.2.3', Request::clientIp('173.245.48.5', ['cf-connecting-ip' => '200.1.2.3'], 'cloudflare'), 'usa CF-Connecting-IP vindo da Cloudflare');
    eq('8.8.8.8', Request::clientIp('8.8.8.8', ['cf-connecting-ip' => '200.1.2.3'], 'cloudflare'), 'ignora cabeçalho forjado direto na origem');
    eq('173.245.48.5', Request::clientIp('173.245.48.5', ['cf-connecting-ip' => 'nao-e-ip'], 'cloudflare'), 'ignora valor inválido');
    eq('10.0.0.1', Request::clientIp('10.0.0.1', ['cf-connecting-ip' => '200.1.2.3', 'x-forwarded-for' => '1.1.1.1'], '0'), 'modo 0 usa REMOTE_ADDR');
    eq('1.1.1.1', Request::clientIp('10.0.0.1', ['x-forwarded-for' => '1.1.1.1, 10.0.0.1'], '1'), 'modo 1 usa X-Forwarded-For');
});

test('reembolso de ouro: desconta até o saldo, nunca negativo, registra a falta', function () use ($makeApp, $googlePem, &$playPurchases) {
    $app = $makeApp();
    $app->db->exec("INSERT IGNORE INTO iap_products (platform, sku, product_type, benefit_version, benefit, active) VALUES ('google_play', 'gold_pack_100', 'consumable', 1, '{\"currency\":\"gold\",\"amount\":100}', 1)");
    $c = new Client($app);
    $g = $c->guest();
    $tok = 'purchase-token-' . bin2hex(random_bytes(8));
    $playPurchases[$tok] = ['purchaseState' => 0, 'consumptionState' => 0, 'acknowledgementState' => 0, 'orderId' => 'GPA.R-' . bin2hex(random_bytes(3)), 'obfuscatedExternalAccountId' => IapService::obfuscatedAccountId($g['player_id'])];
    $c->call('POST', '/iap/verify', ['product_id' => 'gold_pack_100', 'purchase_token' => $tok]);
    eq(100, $c->last['wallet']['gold'] ?? null, 'ouro creditado');
    $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($g['player_id'])])['id'];
    $app->ledger->post($pid, 'gold', -70, 'system', 'test_spend', null, 'spend-1');
    $now = time();
    $oidc = google_jwt($googlePem, ['iss' => 'https://accounts.google.com', 'aud' => 'https://example.test/rtdn', 'email' => 'rtdn@test.iam.gserviceaccount.com', 'email_verified' => true, 'sub' => '1', 'iat' => $now, 'exp' => $now + 600]);
    $msg = ['message' => ['messageId' => 'm-refund-' . bin2hex(random_bytes(3)), 'data' => base64_encode(json_encode(['version' => '1.0', 'packageName' => 'com.terrabela.farm', 'voidedPurchaseNotification' => ['purchaseToken' => $tok, 'productType' => 2]]))], 'subscription' => 'x'];
    $r = new Client($app);
    $r->call('POST', '/iap/google/rtdn', $msg, ['authorization' => 'Bearer ' . $oidc]);
    eq('refunded', $r->last['processed'] ?? null, 'reembolso processado');
    eq(0, $app->ledger->wallet($pid)['gold'], 'saldo zerado, não negativo');
    $t = $app->db->one('SELECT refund_clawback, refund_shortfall FROM iap_transactions WHERE player_id = ?', [$pid]);
    eq(30, (int) $t['refund_clawback'], 'descontou o disponível (30)');
    eq(70, (int) $t['refund_shortfall'], 'falta registrada (70)');
    eq(1, (int) $app->db->one("SELECT COUNT(*) n FROM economy_ledger WHERE player_id = ? AND reason = 'iap_refund' AND amount = -30", [$pid])['n'], 'lançamento de estorno no ledger');
});

test('TOTP RFC 6238', function () {
    $secret = \TerraBela\Admin\Totp::base32Encode('12345678901234567890');
    eq('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', $secret, 'base32');
    eq('287082', \TerraBela\Admin\Totp::code($secret, 59), 'vetor t=59');
    eq('081804', \TerraBela\Admin\Totp::code($secret, 1111111109), 'vetor t=1111111109');
    check(\TerraBela\Admin\Totp::verify($secret, '287082', 59 + 30), 'aceita passo vizinho');
    check(!\TerraBela\Admin\Totp::verify($secret, '287082', 59 + 90), 'recusa código velho');
    eq('12345678901234567890', \TerraBela\Admin\Totp::base32Decode($secret), 'decode');
});

test('backoffice: link de configuração, login, bloqueio, cookie, CSRF e expiração', function () use ($makeApp, $clock) {
    $app = $makeApp();
    $app->db->exec('DELETE FROM rate_limits');
    $a = new AdminClient($app);
    $r = $a->req('GET', '');
    eq(303, $r->status, 'sem sessão redireciona');
    check(str_starts_with($r->headers['Location'] ?? '', '/admin/login'), 'para o login');
    $u = $app->admin()->auth->createUser('celso@example.test', 'Celso', 'admin');
    eq(200, $a->req('GET', 'setup', [], ['token' => $u['token']])->status, 'link de configuração abre');
    eq(404, $a->req('GET', 'setup', [], ['token' => str_repeat('0', 48)])->status, 'link inválido');
    eq(422, $a->req('POST', 'setup', ['token' => $u['token'], 'password' => 'curta', 'confirm' => 'curta'])->status, 'senha curta recusada');
    $pwd = 'Uma-Senha-Muito-Boa-2026';
    eq(303, $a->req('POST', 'setup', ['token' => $u['token'], 'password' => $pwd, 'confirm' => $pwd])->status, 'senha definida');
    eq(404, $a->req('GET', 'setup', [], ['token' => $u['token']])->status, 'link é de uso único');
    $hash = $app->db->one('SELECT password_hash FROM admin_users WHERE id = ?', [$u['id']])['password_hash'];
    check(str_starts_with($hash, '$2y$') || str_starts_with($hash, '$argon2'), 'senha guardada como hash');

    for ($i = 0; $i < 5; $i++) {
        $a->login('celso@example.test', 'errada-' . $i);
    }
    $r = $a->login('celso@example.test', $pwd);
    eq(401, $r->status, 'bloqueado após 5 falhas mesmo com a senha certa');
    check(str_contains($r->body, '15 minutos'), 'mensagem de bloqueio');
    $clock->set(time() + 16 * 60);
    $r = $a->login('celso@example.test', $pwd);
    eq(303, $r->status, 'login depois do bloqueio');
    $cookie = implode(' | ', $r->cookies);
    check(str_contains($cookie, 'tbf_admin=') && str_contains($cookie, 'HttpOnly') && str_contains($cookie, 'SameSite=Strict') && str_contains($cookie, 'Secure') && str_contains($cookie, 'Path=/admin'), 'cookie seguro: ' . $cookie);
    $r = $a->req('GET', '');
    eq(200, $r->status, 'painel abre');
    check(str_contains($r->body, 'Jogadores ativos por dia') && str_contains($r->body, '<svg'), 'painel com gráficos');
    check(str_contains($r->headers['Content-Security-Policy'] ?? '', "default-src 'none'") && ($r->headers['X-Frame-Options'] ?? '') === 'DENY', 'CSP e anti-frame');
    check(!str_contains($r->body, '<script'), 'sem JavaScript');
    eq(403, $a->req('POST', 'players/' . '00000000-0000-4000-8000-000000000000' . '/revoke', ['_csrf' => 'x'])->status, 'POST sem CSRF válido recusado');
    $tokenHash = $app->db->one('SELECT token_hash FROM admin_sessions ORDER BY id DESC LIMIT 1')['token_hash'];
    check(!str_contains($tokenHash, $a->cookies['tbf_admin']), 'cookie não é gravado em claro');
    $clock->advance(31 * 60);
    eq(303, $a->req('GET', 'players')->status, 'expira após 30 min sem uso');
    $clock->set(null);
    $a2 = new AdminClient($app);
    $a2->login('celso@example.test', $pwd);
    $a2->post('logout');
    eq(303, $a2->req('GET', '')->status, 'logout encerra a sessão');
    $actions = array_column($app->db->all('SELECT action FROM admin_audit_log'), 'action');
    foreach (['setup_completed', 'login_failed', 'login_ok', 'csrf_rejected', 'logout'] as $act) {
        check(in_array($act, $actions, true), "auditoria registra $act");
    }
});

test('backoffice: 2FA TOTP com proteção contra reutilização', function () use ($makeApp, $clock) {
    $app = $makeApp();
    $app->db->exec('DELETE FROM rate_limits');
    [$email, $pwd] = make_admin($app, 'operation', 'ops@example.test');
    $a = new AdminClient($app);
    $a->login($email, $pwd);
    $r = $a->post('account/totp-start');
    preg_match('/<code>([A-Z2-7 ]{20,})<\/code>/', $r->body, $m);
    $secret = str_replace(' ', '', $m[1] ?? '');
    check(strlen($secret) === 32, 'segredo mostrado para cadastrar no app');
    $t = time();
    $clock->set($t);
    $a->post('account/totp-confirm', ['code' => '000000']);
    check(str_contains($a->flash(), 'inválido'), 'código errado não ativa');
    $a->post('account/totp-confirm', ['code' => \TerraBela\Admin\Totp::code($secret, $t)]);
    eq(1, (int) $app->db->one('SELECT totp_enabled FROM admin_users WHERE email = ?', [$email])['totp_enabled'], '2FA ativado');
    $b = new AdminClient($app);
    $b->login($email, $pwd);
    eq('/admin/mfa', $b->last->headers['Location'] ?? null, 'login pede o código');
    eq(303, $b->req('GET', 'players')->status, 'sem código não entra nas páginas');
    $csrf = function () use ($b) {
        preg_match('/name="_csrf" value="([a-f0-9]{64})"/', $b->req('GET', 'mfa')->body, $m);
        return $m[1];
    };
    $b->req('POST', 'mfa', ['code' => \TerraBela\Admin\Totp::code($secret, $t), '_csrf' => $csrf()]);
    check(str_contains($b->last->body, 'já usado'), 'mesmo código não pode ser reutilizado');
    $clock->set($t + 30);
    $b->req('POST', 'mfa', ['code' => \TerraBela\Admin\Totp::code($secret, $t + 30), '_csrf' => $csrf()]);
    eq(303, $b->last->status, 'código novo aceito');
    eq(200, $b->req('GET', 'campaigns')->status, 'entrou após o 2FA');
    $clock->set(null);
});

test('backoffice: papéis, carteira, benefício, config e auditoria', function () use ($makeApp) {
    $app = $makeApp();
    $app->db->exec('DELETE FROM rate_limits');
    $c = new Client($app);
    $g = $c->guest();
    $uuid = $g['player_id'];
    $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($uuid)])['id'];
    $clients = [];
    foreach (['admin', 'operation', 'support', 'read'] as $role) {
        [$e, $p] = make_admin($app, $role, "$role-rbac@example.test");
        $clients[$role] = new AdminClient($app);
        $clients[$role]->login($e, $p);
    }
    foreach (['', 'players', 'players/' . $uuid, 'ledger', 'purchases', 'products', 'config', 'events', 'campaigns', 'rules', 'calendar', 'account'] as $page) {
        eq(200, $clients['read']->req('GET', $page)->status, "leitura abre /$page");
    }
    eq(403, $clients['read']->req('GET', 'audit')->status, 'leitura não vê auditoria');
    eq(403, $clients['read']->req('GET', 'users')->status, 'leitura não vê usuários');
    eq(200, $clients['admin']->req('GET', 'users')->status, 'admin vê usuários');
    eq(403, $clients['read']->post("players/$uuid/reward", ['currency' => 'cash', 'amount' => '10', 'note' => 'teste leitura', 'nonce' => bin2hex(random_bytes(8))])->status, 'leitura não concede');
    eq(403, $clients['support']->post("players/$uuid/wallet", ['currency' => 'cash', 'amount' => '10', 'note' => 'teste suporte', 'nonce' => bin2hex(random_bytes(8))])->status, 'suporte não ajusta carteira');
    eq(403, $clients['support']->post('config/publish', ['payload' => '{}', 'changelog' => 'x'])->status, 'suporte não publica config');

    $nonce = bin2hex(random_bytes(8));
    $clients['admin']->post("players/$uuid/wallet", ['currency' => 'gold', 'amount' => '50', 'note' => 'compensação de teste', 'nonce' => $nonce]);
    check(str_contains($clients['admin']->flash(), 'Novo saldo'), 'ajuste lançado: ' . $clients['admin']->flash());
    $clients['admin']->post("players/$uuid/wallet", ['currency' => 'gold', 'amount' => '50', 'note' => 'compensação de teste', 'nonce' => $nonce]);
    eq(50, $app->ledger->wallet($pid)['gold'], 'envio repetido não duplica');
    $clients['admin']->post("players/$uuid/wallet", ['currency' => 'gold', 'amount' => '-500', 'note' => 'débito maior que saldo', 'nonce' => bin2hex(random_bytes(8))]);
    check(str_contains($clients['admin']->flash(), 'insuficiente'), 'débito acima do saldo recusado');
    eq(50, $app->ledger->wallet($pid)['gold'], 'saldo intacto');
    eq('admin', $app->db->one('SELECT source FROM economy_ledger WHERE player_id = ? ORDER BY id DESC LIMIT 1', [$pid])['source'], 'ledger com source admin');

    $clients['support']->post("players/$uuid/reward", ['currency' => 'cash', 'amount' => '25', 'days' => '7', 'note' => 'atendimento ticket 1', 'nonce' => bin2hex(random_bytes(8))]);
    $c->call('GET', '/rewards');
    eq(25, $c->last['rewards'][0]['amount'] ?? null, 'jogador vê o benefício concedido pelo suporte');
    $clients['support']->post("players/$uuid/revoke");
    eq(401, $c->call('GET', '/me')->status, 'suporte encerrou as sessões do jogador');

    $cur = $app->remoteConfig->current(null);
    $payload = $cur['payload'];
    $payload['features']['new_feature_x'] = true;
    $clients['operation']->post('config/publish', ['payload' => '{"economy":', 'changelog' => 'quebrado']);
    check(str_contains($clients['operation']->flash(), 'JSON inválido'), 'JSON inválido recusado');
    $bad = $payload;
    $bad['economy']['client_credit']['gold'] = ['max_per_operation' => 1];
    $clients['operation']->post('config/publish', ['payload' => json_encode($bad), 'changelog' => 'tentativa de ouro']);
    check(str_contains($clients['operation']->flash(), 'gold nunca'), 'ouro pelo cliente recusado');
    $clients['operation']->post('config/publish', ['payload' => json_encode($payload), 'changelog' => 'liga feature x', 'min_client' => '0.0.0']);
    $new = $app->remoteConfig->current(null);
    check(($new['version'] ?? 0) > $cur['version'] && ($new['payload']['features']['new_feature_x'] ?? false) === true, 'nova versão publicada pelo painel');
    $clients['operation']->post('config/retire', ['version' => (string) $new['version']]);
    $app2 = $makeApp();
    eq($cur['version'], $app2->remoteConfig->current(null)['version'] ?? null, 'rollback pelo painel');

    $clients['operation']->post('products', ['sku' => 'gold_pack_big', 'product_type' => 'consumable', 'benefit' => '{"currency":"gold","amount":1200}']);
    eq(1, (int) $app->db->one("SELECT COUNT(*) n FROM iap_products WHERE sku = 'gold_pack_big' AND active = 1")['n'], 'produto cadastrado pelo painel');
    $clients['operation']->post('products', ['sku' => 'gold_pack_big', 'product_type' => 'consumable', 'benefit' => '{"currency":"diamante","amount":1}']);
    check(str_contains($clients['operation']->flash(), 'currency'), 'benefício inválido recusado');

    $audit = $app->db->all('SELECT action, target_id, details FROM admin_audit_log WHERE action IN (\'wallet_adjust\',\'reward_grant\',\'player_sessions_revoked\',\'config_publish\',\'config_retire\',\'product_version\',\'forbidden\')');
    $acts = array_count_values(array_column($audit, 'action'));
    eq(1, $acts['wallet_adjust'] ?? 0, 'auditoria: 1 ajuste (o repetido não conta)');
    foreach (['reward_grant', 'player_sessions_revoked', 'config_publish', 'config_retire', 'product_version', 'forbidden'] as $act) {
        check(($acts[$act] ?? 0) >= 1, "auditoria: $act");
    }
    $r = $clients['admin']->req('GET', 'players/' . $uuid);
    check(str_contains($r->body, 'compensação de teste'), 'tela do jogador mostra a auditoria dele');
    check(!str_contains($r->body, $g['guest_secret']), 'segredo do visitante nunca aparece');
    $r = $clients['admin']->req('GET', 'audit');
    eq(200, $r->status, 'tela de auditoria');
    $r = $clients['admin']->post('users', ['display_name' => 'Novo Suporte', 'email' => 'novo@example.test', 'role' => 'support']);
    check(preg_match('#/admin/setup\?token=[a-f0-9]{48}#', $r->body) === 1, 'criar usuário mostra o link uma vez');
    check(!str_contains(json_encode($app->db->all('SELECT details FROM admin_audit_log')), 'token='), 'link não vai para a auditoria');
});

test('campanhas push: público, opt-in, fila, nova tentativa, token inválido', function () use ($makeApp, $http, $saFile, $clock) {
    $fcmCalls = [];
    $http->on('POST', 'https://fcm.googleapis.com/v1/projects/', function (string $url, array $h, ?string $body) use (&$fcmCalls) {
        $msg = json_decode((string) $body, true)['message'];
        $fcmCalls[] = $msg;
        return match ($msg['token']) {
            'tok-ok', 'tok-promo' => [200, ['name' => 'projects/p/messages/' . count($fcmCalls)]],
            'tok-bad' => [404, ['error' => ['status' => 'NOT_FOUND', 'details' => [['errorCode' => 'UNREGISTERED']]]]],
            default => [503, ['error' => ['status' => 'UNAVAILABLE']]],
        };
    });
    $app = $makeApp(['FCM_SERVICE_ACCOUNT_FILE' => $saFile, 'FCM_PROJECT_ID' => 'tbf-test']);
    $app->db->exec('DELETE FROM notification_outbox');
    $app->db->exec('UPDATE player_devices SET revoked_at = NOW()');
    $players = [];
    foreach (['tok-ok', 'tok-bad', 'tok-retry', 'tok-promo'] as $i => $tok) {
        $c = new Client($app);
        $c->guest();
        $c->call('POST', '/devices/register', ['installation_id' => 'inst-' . $tok . '-' . bin2hex(random_bytes(3)), 'platform' => 'android', 'fcm_token' => $tok, 'locale' => 'pt_BR']);
        eq(200, $c->last ? 200 : 0, 'registrou');
        $players[$tok] = $c;
    }
    $players['tok-promo']->call('PUT', '/preferences/notifications', ['promotional' => true]);
    $players['tok-retry']->call('PUT', '/preferences/notifications', ['os_permission_granted' => true]);

    $svc = $app->campaigns;
    $op = $svc->create(['name' => 'Aviso colheita', 'category' => 'operational', 'title' => 'Seus tomates estão prontos', 'body' => 'Volte para colher!', 'route' => 'tomatoes', 'locale' => 'pt_BR'], null);
    eq(4, $svc->estimate($op), 'operacional alcança os 4 (ninguém recusou)');
    $promo = $svc->create(['name' => 'Oferta', 'category' => 'promotional', 'title' => 'Oferta de ouro', 'body' => 'Só hoje', 'route' => 'shop'], null);
    eq(1, $svc->estimate($promo), 'promocional só para quem aceitou');
    $players['tok-ok']->call('PUT', '/preferences/notifications', ['os_permission_granted' => false]);
    eq(3, $svc->estimate($op), 'respeita permissão do sistema desligada');
    try {
        $svc->create(['name' => 'x', 'category' => 'operational', 'title' => str_repeat('a', 70), 'body' => 'b', 'route' => 'farm'], null);
        check(false, 'título longo deveria falhar');
    } catch (\InvalidArgumentException) {
        check(true, 'validação de título');
    }
    $players['tok-ok']->call('PUT', '/preferences/notifications', ['os_permission_granted' => true]);
    $svc->schedule($op, $clock->sql(-1), null);
    $svc->schedule($promo, $clock->sql(3600), null);
    $rep = $svc->runDue();
    eq(1, $rep['campaigns_started'], 'só a campanha vencida começou');
    eq(2, $rep['sent'], 'enviados ok (tok-ok e tok-promo)');
    eq(1, $rep['failed'], 'token inválido falha');
    eq(1, $rep['retry'], 'erro temporário reagendado');
    $sent = array_values(array_filter($fcmCalls, fn ($m) => $m['token'] === 'tok-ok'))[0];
    eq('tomatoes', $sent['data']['route'] ?? null, 'rota no payload');
    check(str_starts_with($sent['data']['notification_id'] ?? '', 'N-'), 'notification_id no payload');
    eq(0, (int) $app->db->one("SELECT COUNT(*) n FROM player_devices WHERE fcm_token = 'tok-bad'")['n'], 'token inválido limpo do aparelho');
    for ($i = 0; $i < 6; $i++) {
        $clock->set(time() + 3600 * ($i + 1) * 3);
        $svc->runDue();
    }
    $c = $svc->get($op);
    eq('completed', $c['status'], 'campanha concluída depois das tentativas');
    eq(2, (int) $c['failed_count'], 'falhas: token inválido + temporário esgotado');
    eq(5, (int) $app->db->one("SELECT o.attempts FROM notification_outbox o JOIN player_devices d ON d.id = o.device_id WHERE d.fcm_token = 'tok-retry'")['attempts'], 'máximo de 5 tentativas');
    eq('completed', $svc->get($promo)['status'], 'promocional enviada no horário');
    $promoSent = (int) $svc->get($promo)['sent_count'];
    eq(1, $promoSent, 'promocional para 1');
    $clock->set(null);
});

test('regras de benefício: simulação, ativação, uma vez por jogador, aviso', function () use ($makeApp, $clock) {
    $app = $makeApp();
    $c = new Client($app);
    $c->guest();
    $eng = $app->rules;
    try {
        $eng->createVersion(['rule_key' => 'x_bad', 'description' => 'ruim', 'conditions' => '[{"type":"php_eval","code":"1"}]', 'occurrence' => 'once', 'currency' => 'cash', 'amount' => '10'], null);
        check(false, 'condição desconhecida deveria falhar');
    } catch (\InvalidArgumentException) {
        check(true, 'condição desconhecida recusada');
    }
    $id = $eng->createVersion(['rule_key' => 'welcome_gift', 'description' => 'Presente de boas-vindas', 'conditions' => '[{"type":"account_age_days_lte","days":3},{"type":"no_verified_purchase"}]', 'occurrence' => 'once', 'currency' => 'cash', 'amount' => '200', 'expires_hours' => '72'], null);
    eq('paused', $app->db->one('SELECT status FROM reward_rules WHERE id = ?', [$id])['status'], 'nasce pausada');
    $dry = $eng->run($id, true);
    check($dry['eligible'] >= 1 && $dry['granted'] === 0, 'simulação não concede: ' . json_encode($dry));
    $eng->setStatus($id, 'active');
    $res = $eng->runActive();
    check($res['rules_run'] === 1 && $res['rewards_granted'] >= 1, 'cron concedeu: ' . json_encode($res));
    eq(0, $eng->runActive()['rules_run'], 'no máximo 1 vez por hora');
    $clock->set(time() + 7200);
    eq(0, $eng->run($id, false)['granted'], 'uma vez por jogador (occurrence once)');
    $clock->set(null);
    $c->call('GET', '/rewards');
    check(in_array('welcome_gift', array_column($c->last['rewards'], 'rule_key'), true), 'benefício aparece para o jogador');
    $v2 = $eng->createVersion(['rule_key' => 'welcome_gift', 'description' => 'v2', 'conditions' => [['type' => 'account_age_days_lte', 'days' => 1]], 'occurrence' => 'once', 'currency' => 'cash', 'amount' => '300'], null);
    eq('retired', $app->db->one('SELECT status FROM reward_rules WHERE id = ?', [$id])['status'], 'versão anterior aposentada');
    eq(2, (int) $app->db->one('SELECT version FROM reward_rules WHERE id = ?', [$v2])['version'], 'nova versão numerada');
});

test('métricas diárias e cron completo', function () use ($makeApp) {
    $app = $makeApp();
    $c = new Client($app);
    $c->guest();
    $c->call('POST', '/events/batch', ['events' => [['event_id' => 'ev-m-' . bin2hex(random_bytes(4)), 'name' => 'session_start', 'occurred_at' => gmdate('Y-m-d\TH:i:s\Z')]]]);
    $n = $app->metrics->recompute(1);
    check($n >= 24, "métricas gravadas ($n)");
    $today = gmdate('Y-m-d');
    check((int) $app->db->one("SELECT value FROM daily_metrics WHERE metric_date = ? AND metric = 'dau' AND dimension = ''", [$today])['value'] >= 1, 'DAU de hoje');
    check((int) $app->db->one("SELECT value FROM daily_metrics WHERE metric_date = ? AND metric = 'new_players' AND dimension = ''", [$today])['value'] >= 1, 'novos de hoje');
    eq(30, count($app->metrics->series('dau', 30)), 'série de 30 dias');
    $app->metrics->recompute(1);
    eq(1, (int) $app->db->one("SELECT COUNT(*) n FROM daily_metrics WHERE metric_date = ? AND metric = 'dau' AND dimension = ''", [$today])['n'], 'recalcular é idempotente');
    $out = shell_exec('TBF_ENV_FILE=' . escapeshellarg((string) getenv('TBF_ENV_FILE')) . ' php ' . escapeshellarg(dirname(__DIR__) . '/bin/cron.php') . ' 2>&1');
    $rep = json_decode((string) $out, true);
    check(is_array($rep) && isset($rep['rules'], $rep['push'], $rep['metrics_rows'], $rep['admin_sessions_deleted']), 'cron roda regras, push, métricas e limpeza: ' . trim((string) $out));
    eq(0, $rep['push']['fcm_configured'] ?? null, 'sem FCM configurado o push só registra');
});

test('MVP-12 backup: snapshot, restauração idêntica, criptografia e retenção', function () use ($makeApp, &$baseConfig, $storage) {
    $app = $makeApp();
    $c = new Client($app);
    $c->guest();
    $c->call('POST', '/sync', ['operation_id' => 'op-bk-' . bin2hex(random_bytes(3)), 'base_revision' => 0, 'schema_version' => 1, 'snapshot' => ['texto' => "linha1\nlinha2; fim;", 'emoji' => 'çãé🌽']]);
    $dir = $storage . '/bk-' . bin2hex(random_bytes(3));
    $svc = new \TerraBela\Ops\BackupService($app->db, $app->clock, $dir, 2);
    $r = $svc->create();
    check($r['tables'] >= 28 && $r['rows'] > 0 && $r['bytes'] > 0, 'backup criado: ' . json_encode($r));
    check(is_file($dir . '/.htaccess'), 'pasta de backup bloqueada para a web');
    $rcfg = $baseConfig->with('DB_NAME', 'tbf_test_restore');
    $target = Db::fromConfig($rcfg);
    $target->pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
    foreach ($target->all('SELECT TABLE_NAME t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()') as $t) {
        $target->pdo->exec('DROP TABLE `' . $t['t'] . '`');
    }
    $target->pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
    $res = $svc->restore($r['file'], $target);
    check($res['statements'] > 30, 'comandos aplicados: ' . $res['statements']);
    $diff = [];
    foreach ($app->db->all("SELECT TABLE_NAME t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME NOT IN ('rate_limits','admin_sessions')") as $t) {
        $a = $app->db->one('CHECKSUM TABLE `' . $t['t'] . '`')['Checksum'];
        $b = $target->one('CHECKSUM TABLE `' . $t['t'] . '`')['Checksum'] ?? null;
        if ((string) $a !== (string) $b) {
            $diff[] = $t['t'];
        }
    }
    eq([], $diff, 'todas as tabelas idênticas após restaurar (CHECKSUM TABLE)');
    eq(0, (int) $target->one('SELECT COUNT(*) n FROM rate_limits')['n'], 'tabela volátil só com estrutura');
    $snap = json_decode($target->one('SELECT snapshot FROM player_saves ORDER BY updated_at DESC LIMIT 1')['snapshot'], true);
    eq("linha1\nlinha2; fim;", $snap['texto'] ?? null, 'texto com quebra de linha e ; restaurado');
    $enc = new \TerraBela\Ops\BackupService($app->db, $app->clock, $dir, 2, str_repeat('ab', 32));
    $e = $enc->create();
    check($e['encrypted'] && str_ends_with($e['file'], '.enc'), 'backup criptografado');
    check(!str_contains((string) file_get_contents($dir . '/' . $e['file']), 'CREATE TABLE'), 'conteúdo ilegível sem a chave');
    $wrong = new \TerraBela\Ops\BackupService($app->db, $app->clock, $dir, 2, str_repeat('cd', 32));
    try {
        $wrong->restore($e['file'], $target);
        check(false, 'chave errada deveria falhar');
    } catch (\RuntimeException) {
        check(true, 'chave errada recusada');
    }
    check($enc->restore($e['file'], $target)['statements'] > 30, 'restaura com a chave certa');
    $svc->create();
    eq(2, count($svc->list()), 'retenção mantém só os 2 mais novos');
    check($svc->recent(20), 'detecta backup recente (cron não repete no dia)');
});

test('MVP-12 exportação de dados do jogador (LGPD)', function () use ($makeApp) {
    $app = $makeApp();
    $app->db->exec('DELETE FROM rate_limits');
    $c = new Client($app);
    $g = $c->guest();
    $c->call('POST', '/sync', ['operation_id' => 'op-ex-' . bin2hex(random_bytes(3)), 'base_revision' => 0, 'schema_version' => 1, 'snapshot' => ['fazenda' => 'teste']]);
    $c->call('PUT', '/preferences/notifications', ['promotional' => true]);
    $r = $c->call('GET', '/me/export');
    eq(200, $r->status, 'exportação 200');
    check(str_contains($r->headers['Content-Disposition'] ?? '', 'attachment'), 'baixa como arquivo');
    $d = $c->last;
    eq(\TerraBela\Players\DataExport::SCHEMA, $d['schema'] ?? null, 'schema versionado');
    eq($g['player_id'], $d['account']['player_id'] ?? null, 'conta certa');
    eq('teste', $d['cloud_save']['snapshot']['fazenda'] ?? null, 'save incluído');
    check(count($d['consents']) >= 1 && isset($d['ledger'], $d['devices'], $d['purchases'], $d['rewards'], $d['game_events']), 'seções completas');
    $raw = $r->body;
    check(!str_contains($raw, $g['guest_secret']) && !str_contains($raw, 'secret_hash') && !str_contains($raw, $c->access), 'sem segredos de autenticação');
    $c->call('GET', '/me/export');
    $c->call('GET', '/me/export');
    eq(429, $c->call('GET', '/me/export')->status, 'limite de 3 exportações por hora');
    [$e, $p] = make_admin($app, 'support', 'sup-export@example.test');
    $a = new AdminClient($app);
    $a->login($e, $p);
    $x = $a->post('players/' . $g['player_id'] . '/export');
    eq(200, $x->status, 'suporte exporta pelo painel');
    check(str_starts_with($x->headers['Content-Type'] ?? '', 'application/json') && str_contains($x->body, $g['player_id']), 'JSON do jogador');
    eq(1, (int) $app->db->one("SELECT COUNT(*) n FROM admin_audit_log WHERE action = 'player_data_export' AND target_id = ?", [$g['player_id']])['n'], 'exportação auditada');
    eq(403, $a->req('GET', 'system')->status, 'suporte não vê sistema/backup');
    [$e2, $p2] = make_admin($app, 'admin', 'adm-bk@example.test');
    $b = new AdminClient($app);
    $b->login($e2, $p2);
    eq(200, $b->req('GET', 'system')->status, 'admin vê sistema/backup');
    $b->post('system/backup');
    check(str_contains($b->flash(), 'Backup criado'), 'backup pelo painel: ' . $b->flash());
});

test('MVP-13a testes A/B: divisão estável, só seções de jogo, exposição e resultados', function () use ($makeApp) {
    $app = $makeApp();
    $app->db->exec('DELETE FROM rate_limits');
    $svc = $app->experiments;
    $bad = [
        '[{"key":"a","weight":50,"overrides":{}}]' => 'uma variante só',
        '[{"key":"a","weight":50,"overrides":{}},{"key":"a","weight":50,"overrides":{}}]' => 'chave repetida',
        '[{"key":"a","weight":50,"overrides":{}},{"key":"b","weight":50,"overrides":{"economy":{"client_credit":{"cash":{"max_per_day":999999999}}}}}]' => 'economia',
        '[{"key":"a","weight":50,"overrides":{}},{"key":"b","weight":50,"overrides":{"maintenance":{"enabled":true}}}]' => 'manutenção',
        '[{"key":"a","weight":50,"overrides":{}},{"key":"b","weight":50,"overrides":{"features":{"store_enabled":"sim"}}}]' => 'feature não booleana',
        '[{"key":"a","weight":0,"overrides":{}},{"key":"b","weight":0,"overrides":{}}]' => 'pesos zerados',
    ];
    foreach ($bad as $json => $why) {
        $ok = false;
        try {
            $svc->create(['experiment_key' => 'bad_' . bin2hex(random_bytes(3)), 'name' => 'x', 'variants' => $json], null);
        } catch (\InvalidArgumentException) {
            $ok = true;
        }
        check($ok, "recusa variante inválida: $why");
    }

    // divisão determinística e equilibrada
    $e = ['salt' => 'abcdef0123456789', 'experiment_key' => 'dist', 'traffic_percent' => 100];
    $vs = [['key' => 'a', 'weight' => 50], ['key' => 'b', 'weight' => 50]];
    $count = ['a' => 0, 'b' => 0];
    for ($i = 0; $i < 4000; $i++) {
        $count[\TerraBela\LiveOps\ExperimentService::pick($e, $vs, bin2hex(hash('md5', "p$i", true)))]++;
    }
    check(abs($count['a'] - 2000) < 160, 'divisão 50/50 equilibrada: ' . json_encode($count));
    $h = bin2hex(random_bytes(16));
    eq(\TerraBela\LiveOps\ExperimentService::pick($e, $vs, $h), \TerraBela\LiveOps\ExperimentService::pick($e, $vs, $h), 'mesmo jogador, mesma variante');
    $in = 0;
    for ($i = 0; $i < 2000; $i++) {
        $in += \TerraBela\LiveOps\ExperimentService::pick(['traffic_percent' => 20] + $e, $vs, bin2hex(hash('md5', "q$i", true))) === null ? 0 : 1;
    }
    check($in > 320 && $in < 480, "20% de tráfego: $in de 2000");

    // pelo backoffice: leitura não cria, operação cria e inicia
    [$re, $rp] = make_admin($app, 'read', 'read-ab@example.test');
    $ro = new AdminClient($app);
    $ro->login($re, $rp);
    eq(200, $ro->req('GET', 'experiments')->status, 'leitura abre testes A/B');
    $key = 'loja_' . bin2hex(random_bytes(3));
    $form = ['experiment_key' => $key, 'name' => 'Loja aberta', 'traffic_percent' => '100', 'goal_event' => 'shop_open', 'min_client_version' => '0.0.0',
        'variants' => '[{"key":"control","weight":50,"overrides":{}},{"key":"loja","weight":50,"overrides":{"features":{"store_enabled":true},"tuning":{"shop_banner":"v2"}}}]'];
    eq(403, $ro->post('experiments', $form)->status, 'leitura não cria teste');
    [$oe, $op] = make_admin($app, 'operation', 'op-ab@example.test');
    $o = new AdminClient($app);
    $o->login($oe, $op);
    $o->post('experiments', $form);
    $id = (int) $app->db->one('SELECT id FROM experiments WHERE experiment_key = ?', [$key])['id'];
    check($id > 0, 'operação cria rascunho: ' . $o->flash());

    $c = new Client($app);
    $g = $c->guest();
    $c->call('GET', '/experiments');
    check(!in_array($key, array_column($c->last['experiments'], 'key'), true), 'rascunho não chega ao app');
    $o->post("experiments/$id/start");
    check(str_contains($o->flash(), 'iniciado'), 'iniciado: ' . $o->flash());
    eq(200, $c->call('GET', '/experiments', null, [], ['client_version' => '0.4.0'])->status, 'GET /experiments 200');
    $mine = array_values(array_filter($c->last['experiments'], fn ($x) => $x['key'] === $key))[0] ?? null;
    check($mine !== null && in_array($mine['variant'], ['control', 'loja'], true), 'jogador recebe uma variante');
    eq($mine['variant'] === 'loja', $c->last['config']['features']['store_enabled'], 'config mesclada com a variante');
    eq(5000, $c->last['config']['economy']['client_credit']['cash']['max_per_operation'] ?? null, 'economia nunca muda');
    $c->call('GET', '/experiments');
    $again = array_values(array_filter($c->last['experiments'], fn ($x) => $x['key'] === $key))[0]['variant'];
    eq($mine['variant'], $again, 'variante estável entre chamadas');
    eq(1, (int) $app->db->one('SELECT COUNT(*) n FROM experiment_assignments WHERE experiment_id = ?', [$id])['n'], 'uma atribuição gravada');
    eq(401, (new Client($app))->call('GET', '/experiments')->status, 'exige login');

    // resultados: 2 jogadores por variante expostos há 10 dias, um volta no D1 e no D7
    $pids = [];
    foreach (['control', 'control', 'loja', 'loja'] as $i => $v) {
        $cc = new Client($app);
        $gg = $cc->guest();
        $pid = (int) $app->db->one('SELECT id FROM players WHERE public_id = ?', [Ids::uuidToBin($gg['player_id'])])['id'];
        $t = $app->clock->sql(-10 * 86400);
        $app->db->exec('INSERT INTO experiment_assignments (experiment_id, player_id, variant_key, first_exposed_at, last_exposed_at) VALUES (?, ?, ?, ?, ?)', [$id, $pid, $v, $t, $t]);
        if ($i % 2 === 0) {
            foreach ([-9 * 86400 + 3600, -3 * 86400 + 3600] as $k => $off) {
                $app->db->exec("INSERT INTO game_events (event_id, player_id, event_name, occurred_at, received_at) VALUES (?, ?, 'shop_open', ?, ?)", ['ab-' . bin2hex(random_bytes(6)), $pid, $app->clock->sql($off), $app->clock->sql()]);
            }
        }
    }
    $res = array_column($svc->results($id), null, 'variant');
    eq(2, $res['loja']['d1_base'], 'base D1 só com quem completou a janela');
    eq(50.0, $res['loja']['d1_pct'], 'D1 50%');
    eq(50.0, $res['control']['d7_pct'], 'D7 50%');
    eq(1, $res['loja']['converted'], 'conversão no evento de meta');
    $page = $o->req('GET', "experiments/$id");
    check(str_contains($page->body, 'Retenção D1') && str_contains($page->body, '50,0%'), 'tela mostra resultados');

    $o->post("experiments/$id/stop", ['winner' => 'loja']);
    eq('stopped', $svc->get($id)['status'], 'encerrado');
    eq('loja', $svc->get($id)['winner_variant'], 'vencedora registrada');
    $c->call('GET', '/experiments');
    check(!in_array($key, array_column($c->last['experiments'], 'key'), true), 'encerrado não chega ao app');
    eq(3, (int) $app->db->one("SELECT COUNT(*) n FROM admin_audit_log WHERE action IN ('experiment_create','experiment_start','experiment_stop') AND target_id = ?", [$key])['n'], 'criação, início e fim auditados');
    $c->call('GET', '/me/export');
    eq($mine['variant'], $c->last['experiments'][0]['variant'] ?? null, 'exportação LGPD inclui a variante');
});

test('MVP-13b Sign in with Apple: login, nonce, audience, vínculo e conflito', function () use ($makeApp, $applePem, $googlePem) {
    eq(503, (new Client($makeApp(['APPLE_CLIENT_IDS' => ''])))->call('POST', '/auth/apple', ['id_token' => str_repeat('x', 30)])->status, 'sem APPLE_CLIENT_IDS: 503');
    $app = $makeApp(['APPLE_CLIENT_IDS' => 'com.terrabela.farm,com.terrabela.farm.web']);
    $app->db->exec('DELETE FROM rate_limits');
    $now = time();
    $raw = 'nonce-bruto-' . bin2hex(random_bytes(4));
    $sub = '001234.' . bin2hex(random_bytes(8)) . '.0101';
    $claims = ['iss' => 'https://appleid.apple.com', 'aud' => 'com.terrabela.farm', 'sub' => $sub, 'iat' => $now, 'exp' => $now + 600, 'nonce' => hash('sha256', $raw), 'email' => 'abc@privaterelay.appleid.com'];
    $tok = fn (array $c, ?string $pem = null) => \TerraBela\Auth\Jwt::signRs256($c, $pem ?? $applePem, 'apple-kid');
    $c = new Client($app);
    eq(200, $c->call('POST', '/auth/apple', ['id_token' => $tok($claims), 'nonce' => $raw])->status, 'login Apple com nonce (hash SHA-256)');
    eq(true, $c->last['created'], 'primeiro login Apple cria fazenda');
    $farm = $c->last['player_id'];
    $c->call('POST', '/auth/apple', ['id_token' => $tok(['nonce' => 'n-direto'] + $claims), 'nonce' => 'n-direto']);
    eq($farm, $c->last['player_id'], 'segundo login volta à mesma fazenda (nonce sem hash também vale)');
    eq(401, $c->call('POST', '/auth/apple', ['id_token' => $tok($claims), 'nonce' => 'outro'])->status, 'nonce diferente');
    eq(401, $c->call('POST', '/auth/apple', ['id_token' => $tok(['aud' => 'com.outro.app'] + $claims)])->status, 'audience errada');
    eq(401, $c->call('POST', '/auth/apple', ['id_token' => $tok(['iss' => 'https://accounts.google.com'] + $claims)])->status, 'issuer errado');
    eq(401, $c->call('POST', '/auth/apple', ['id_token' => $tok(['exp' => $now - 3600] + $claims)])->status, 'token expirado');
    eq(401, $c->call('POST', '/auth/apple', ['id_token' => \TerraBela\Auth\Jwt::signRs256($claims, $googlePem, 'apple-kid')])->status, 'assinatura de outra chave');
    eq(0, (int) $app->db->one("SELECT COUNT(*) n FROM player_identities WHERE provider = 'apple' AND subject LIKE '%privaterelay%'")['n'], 'e-mail não é guardado');
    eq('apple', $app->db->one('SELECT login_provider FROM player_sessions ORDER BY id DESC LIMIT 1')['login_provider'], 'sessão registra apple');

    $v = new Client($app);
    $guest = $v->guest();
    $sub2 = '001234.' . bin2hex(random_bytes(8)) . '.0202';
    $v->call('POST', '/auth/link', ['provider' => 'apple', 'id_token' => $tok(['sub' => $sub2, 'aud' => 'com.terrabela.farm.web'] + $claims), 'nonce' => $raw]);
    eq(true, $v->last['linked'] ?? null, 'visitante vincula Apple (Services ID)');
    $n = new Client($app);
    $n->call('POST', '/auth/apple', ['id_token' => $tok(['sub' => $sub2] + $claims)]);
    eq($guest['player_id'], $n->last['player_id'], 'outro aparelho recupera a fazenda pelo Apple');
    eq(409, $v->call('POST', '/auth/link', ['provider' => 'apple', 'id_token' => $tok($claims)])->status, 'Apple de outra fazenda: conflito, sem mesclar');
    $n->access = $n->last['access_token'];
    $n->call('GET', '/me');
    check(in_array('apple', array_column($n->last['identities'], 'provider'), true), '/me lista apple');
});

test('dicionário de dados: 100% de COMMENT', function () {
    $out = [];
    exec('TBF_ENV_FILE=' . escapeshellarg((string) getenv('TBF_ENV_FILE')) . ' php ' . escapeshellarg(dirname(__DIR__) . '/bin/datadict.php') . ' ' . escapeshellarg(sys_get_temp_dir() . '/tbf-dd.md') . ' 2>&1', $out, $code);
    eq(0, $code, 'datadict sem falhas: ' . implode(' | ', $out));
});

// ---------- execução ----------
$started = microtime(true);
fresh_db($baseConfig);
foreach ($tests as $name => $fn) {
    if ($filter !== null && !str_contains($name, $filter)) {
        continue;
    }
    $current = $name;
    $before = $results['fail'];
    try {
        $fn();
    } catch (Throwable $e) {
        $results['fail']++;
        echo "    ERRO [$name] " . get_class($e) . ': ' . $e->getMessage() . ' @ ' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
    }
    echo ($results['fail'] === $before ? '  ok   ' : '  FAIL ') . $name . "\n";
}
printf("\n%d verificações ok, %d falhas (%.1fs)\n", $results['pass'], $results['fail'], microtime(true) - $started);
exit($results['fail'] === 0 ? 0 : 1);
