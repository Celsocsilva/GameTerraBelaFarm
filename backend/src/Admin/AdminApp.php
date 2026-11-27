<?php
declare(strict_types=1);

namespace TerraBela\Admin;

use TerraBela\App;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;
use TerraBela\Http\Response;

/**
 * Backoffice web em /admin servido pelo mesmo index.php da API.
 * Segurança: sessão em cookie HttpOnly+Secure+SameSite=Strict, CSRF em todo POST, RBAC por rota,
 * rate limit e bloqueio no login, 2FA TOTP opcional, CSP com nonce (sem JS), auditoria de cada ação.
 */
final class AdminApp
{
    public const COOKIE = 'tbf_admin';
    private const FLASH = 'tbf_admin_flash';

    public readonly AdminAuth $auth;
    public readonly Db $db;
    public readonly Clock $clock;
    private AdminPages $pages;

    // Estado da requisição atual
    public Request $req;
    public View $view;
    /** @var array<string,mixed>|null */
    public ?array $s = null;
    private ?array $flash = null;
    /** @var list<string> */
    private array $cookies = [];

    public function __construct(public readonly App $app)
    {
        $this->db = $app->db;
        $this->clock = $app->clock;
        $this->auth = new AdminAuth(
            $app->db,
            $app->clock,
            $app->config->str('APP_KEY'),
            60 * $app->config->int('ADMIN_IDLE_MINUTES', 30),
            3600 * $app->config->int('ADMIN_SESSION_HOURS', 12),
        );
        $this->pages = new AdminPages($this);
    }

    public function handle(Request $req): Response
    {
        $this->req = $req;
        $this->view = new View($req->basePath, bin2hex(random_bytes(12)));
        $this->s = null;
        $this->cookies = [];
        $this->flash = $this->readFlash();
        try {
            $resp = $this->dispatch($req);
        } catch (\Throwable $e) {
            $this->app->log->error('admin_unhandled', ['type' => get_class($e), 'msg' => $e->getMessage(), 'at' => basename($e->getFile()) . ':' . $e->getLine()]);
            $resp = $this->render('Erro', '<p>Erro interno. A ocorrência foi registrada no log.</p>', '', 500);
        }
        $resp->cookies = array_merge($resp->cookies, $this->cookies);
        $resp->headers += [
            'Content-Type' => 'text/html; charset=utf-8',
            'Content-Security-Policy' => "default-src 'none'; style-src 'nonce-" . $this->view->nonce . "'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
            'X-Frame-Options' => 'DENY',
            'X-Content-Type-Options' => 'nosniff',
            'Referrer-Policy' => 'same-origin',
            'Cache-Control' => 'no-store',
            'X-Robots-Tag' => 'noindex, nofollow',
        ];
        return $resp;
    }

    private function dispatch(Request $req): Response
    {
        $sub = trim(substr($req->path, strlen('/admin')), '/');
        $post = $req->method === 'POST';
        if (!in_array($req->method, ['GET', 'POST'], true)) {
            return $this->render('Método não permitido', '', '', 405);
        }
        if ($post && !$this->sameOrigin($req)) {
            return $this->render('Requisição recusada', '<p>Origem inválida.</p>', '', 403);
        }

        // Rotas sem sessão completa
        if ($sub === 'login') {
            return $post ? $this->loginPost() : $this->loginForm();
        }
        if ($sub === 'setup') {
            return $post ? $this->setupPost() : $this->setupForm((string) ($req->query['token'] ?? ''));
        }

        $this->s = $this->auth->session($req->cookie(self::COOKIE));
        if ($this->s === null) {
            return $post ? $this->redirect('login') : $this->redirect('login', $sub === '' ? [] : ['next' => $sub]);
        }
        if ($post) {
            $csrf = (string) ($req->form()['_csrf'] ?? '');
            if (!hash_equals($this->s['csrf_token'], $csrf)) {
                $this->audit('csrf_rejected', null, null, ['path' => $sub]);
                return $this->render('Sessão expirada', '<p>O formulário expirou. <a href="' . View::h($this->view->url($sub)) . '">Recarregue a página</a> e tente de novo.</p>', '', 403);
            }
        }
        if ((int) $this->s['mfa_passed'] !== 1) {
            if ($sub === 'mfa') {
                return $post ? $this->mfaPost() : $this->mfaForm();
            }
            if ($sub === 'logout' && $post) {
                return $this->logout();
            }
            return $this->redirect('mfa');
        }
        if ($sub === 'logout' && $post) {
            return $this->logout();
        }
        if ($sub === 'mfa') {
            return $this->redirect('');
        }
        return $this->pages->route($sub, $post);
    }

    /** Recusa POST de outro site quando o navegador informa a origem (o cookie SameSite=Strict e o CSRF já cobrem o resto). */
    private function sameOrigin(Request $req): bool
    {
        $origin = $req->header('origin');
        if ($origin === null || $origin === 'null') {
            return true;
        }
        $host = parse_url($origin, PHP_URL_HOST);
        return is_string($host) && strcasecmp($host, (string) $req->header('host')) === 0
            || is_string($host) && strcasecmp($host, (string) ($req->header('x-forwarded-host') ?? '')) === 0;
    }

    // ---------------------------------------------------------------- utilidades para as páginas

    public function render(string $title, string $body, string $active = '', int $status = 200): Response
    {
        return new Response($status, $this->view->page($title, $body, $this->s, $active, $this->flash));
    }

    public function redirect(string $path, array $query = []): Response
    {
        return new Response(303, '', ['Location' => $this->view->url($path, $query)]);
    }

    public function can(string $perm): bool
    {
        return $this->s !== null && Rbac::can($this->s['role'], $perm);
    }

    public function forbidden(): Response
    {
        $this->audit('forbidden', null, null, ['path' => $this->req->path]);
        return $this->render('Sem permissão', '<p>Seu papel não permite esta ação.</p>', '', 403);
    }

    /** Executa uma ação POST com RBAC, mensagem de resultado e redirecionamento (PRG). */
    public function act(string $perm, string $back, callable $fn): Response
    {
        if (!$this->can($perm)) {
            return $this->forbidden();
        }
        try {
            $msg = $fn($this->req->form());
            $this->setFlash('ok', is_string($msg) ? $msg : 'Feito.');
        } catch (AdminError | \InvalidArgumentException | ApiException $e) {
            $this->setFlash('error', $e->getMessage());
        } catch (\JsonException $e) {
            $this->setFlash('error', 'JSON inválido: ' . $e->getMessage());
        }
        return $this->redirect($back);
    }

    /** @param array<string,mixed>|null $details */
    public function audit(string $action, ?string $targetType, ?string $targetId, ?array $details = null, ?int $adminId = null): void
    {
        $this->db->insert(
            'INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, details, ip_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$adminId ?? ($this->s === null ? null : (int) $this->s['id']), $action, $targetType, $targetId,
             $details === null ? null : json_encode($details, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
             $this->auth->ipHash($this->req->ip), $this->clock->sql()]
        );
    }

    public function adminLabel(): string
    {
        return 'admin:' . ($this->s['email'] ?? '?');
    }

    private function cookie(string $name, string $value, int $maxAge): string
    {
        $path = ($this->req->basePath === '' ? '' : $this->req->basePath) . '/admin';
        return $name . '=' . rawurlencode($value) . '; Path=' . $path . '; Max-Age=' . $maxAge . '; HttpOnly; SameSite=Strict'
            . ($this->req->secure || $this->app->config->str('APP_ENV', 'production') !== 'local' ? '; Secure' : '');
    }

    private function setSession(string $token): void
    {
        $this->cookies[] = $this->cookie(self::COOKIE, $token, 3600 * $this->app->config->int('ADMIN_SESSION_HOURS', 12));
    }

    public function setFlash(string $type, string $text): void
    {
        $data = base64_encode(json_encode(['type' => $type, 'text' => mb_substr($text, 0, 600)], JSON_UNESCAPED_UNICODE));
        $this->cookies[] = $this->cookie(self::FLASH, $data . '.' . hash_hmac('sha256', 'flash|' . $data, $this->app->config->str('APP_KEY')), 120);
    }

    private function readFlash(): ?array
    {
        $raw = $this->req->cookie(self::FLASH);
        if ($raw === null) {
            return null;
        }
        $this->cookies[] = $this->cookie(self::FLASH, '', 0);
        $parts = explode('.', $raw, 2);
        if (count($parts) !== 2 || !hash_equals(hash_hmac('sha256', 'flash|' . $parts[0], $this->app->config->str('APP_KEY')), $parts[1])) {
            return null;
        }
        $f = json_decode((string) base64_decode($parts[0], true), true);
        return is_array($f) && isset($f['type'], $f['text']) ? $f : null;
    }

    // ---------------------------------------------------------------- login, 2FA, link de configuração

    private function loginForm(?string $error = null, string $email = ''): Response
    {
        if ($error !== null) {
            $this->flash = ['type' => 'error', 'text' => $error];
        }
        $next = (string) ($this->req->query['next'] ?? $this->req->form()['next'] ?? '');
        $body = '<form method="post" class="stack" action="' . View::h($this->view->url('login')) . '">'
            . '<input type="hidden" name="next" value="' . View::h(preg_match('#^[a-z0-9/_-]{0,120}$#i', $next) ? $next : '') . '">'
            . '<label for="email">E-mail</label><input id="email" name="email" type="email" autocomplete="username" required value="' . View::h($email) . '">'
            . '<label for="password">Senha</label><input id="password" name="password" type="password" autocomplete="current-password" required>'
            . '<button>Entrar</button></form>';
        return $this->render('Entrar', $body, '', $error === null ? 200 : 401);
    }

    private function loginPost(): Response
    {
        $f = $this->req->form();
        $email = mb_substr(trim((string) ($f['email'] ?? '')), 0, 191);
        try {
            $this->app->limiter->hit('admin_login', $this->req->ip, $this->app->config->int('RATE_ADMIN_LOGIN_PER_MINUTE', 10), 60);
        } catch (ApiException $e) {
            $this->audit('login_rate_limited', 'admin_user', $email, null);
            return $this->loginForm('Muitas tentativas deste endereço. Aguarde um minuto.', $email);
        }
        try {
            $r = $this->auth->login($email, (string) ($f['password'] ?? ''), $this->req->ip, $this->req->header('user-agent'));
        } catch (AdminError $e) {
            $this->audit('login_failed', 'admin_user', $email, ['reason' => $e->getMessage()], $e->adminId);
            return $this->loginForm($e->getMessage(), $email);
        }
        $this->setSession($r['token']);
        $this->audit($r['mfa_required'] ? 'login_password_ok' : 'login_ok', 'admin_user', (string) $r['admin_id'], null, $r['admin_id']);
        $next = (string) ($f['next'] ?? '');
        if ($r['mfa_required']) {
            return $this->redirect('mfa');
        }
        return $this->redirect(preg_match('#^[a-z0-9/_-]{1,120}$#i', $next) && !str_starts_with($next, '/') ? $next : '');
    }

    private function mfaForm(): Response
    {
        $body = '<p class="muted">Digite o código de 6 dígitos do aplicativo autenticador.</p>'
            . '<form method="post" class="stack" action="' . View::h($this->view->url('mfa')) . '">' . $this->view->csrf($this->s)
            . '<label for="code">Código</label><input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" required autofocus>'
            . '<button>Confirmar</button></form>'
            . '<form method="post" action="' . View::h($this->view->url('logout')) . '">' . $this->view->csrf($this->s) . '<button class="link">Cancelar e sair</button></form>';
        return $this->render('Verificação em duas etapas', $body);
    }

    private function mfaPost(): Response
    {
        try {
            $token = $this->auth->verifyMfa($this->s, (string) ($this->req->form()['code'] ?? ''));
        } catch (AdminError $e) {
            $this->audit('mfa_failed', 'admin_user', (string) $this->s['id']);
            $this->flash = ['type' => 'error', 'text' => $e->getMessage()];
            return str_contains($e->getMessage(), 'bloqueado') ? $this->render('Bloqueado', '<p><a href="' . View::h($this->view->url('login')) . '">Voltar ao login</a></p>', '', 401) : $this->mfaForm();
        }
        $this->setSession($token);
        $this->audit('login_ok', 'admin_user', (string) $this->s['id'], ['mfa' => true]);
        return $this->redirect('');
    }

    private function logout(): Response
    {
        $this->auth->revoke((int) $this->s['session_id']);
        $this->audit('logout', 'admin_user', (string) $this->s['id']);
        $this->cookies[] = $this->cookie(self::COOKIE, '', 0);
        $this->s = null;
        return $this->redirect('login');
    }

    private function setupForm(string $token, ?string $error = null): Response
    {
        $u = $this->auth->setupUser($token);
        if ($u === null) {
            return $this->render('Link inválido', '<p>Este link de configuração é inválido, já foi usado ou expirou. Peça um novo a um administrador.</p>', '', 404);
        }
        if ($error !== null) {
            $this->flash = ['type' => 'error', 'text' => $error];
        }
        $body = '<p>Olá, <b>' . View::h($u['display_name']) . '</b> (' . View::h($u['email']) . '). Defina sua senha de acesso ao backoffice.</p>'
            . '<p class="muted">Mínimo de ' . AdminAuth::MIN_PASSWORD . ' caracteres. Use um gerenciador de senhas. Depois do primeiro login, ative a verificação em duas etapas em “Minha conta”.</p>'
            . '<form method="post" class="stack" action="' . View::h($this->view->url('setup')) . '">'
            . '<input type="hidden" name="token" value="' . View::h($token) . '">'
            . '<input type="text" name="username" value="' . View::h($u['email']) . '" autocomplete="username" hidden>'
            . '<label for="p1">Nova senha</label><input id="p1" name="password" type="password" minlength="' . AdminAuth::MIN_PASSWORD . '" autocomplete="new-password" required>'
            . '<label for="p2">Repita a senha</label><input id="p2" name="confirm" type="password" autocomplete="new-password" required>'
            . '<button>Salvar senha</button></form>';
        return $this->render('Configurar acesso', $body, '', $error === null ? 200 : 422);
    }

    private function setupPost(): Response
    {
        $f = $this->req->form();
        $token = (string) ($f['token'] ?? '');
        try {
            $this->app->limiter->hit('admin_setup', $this->req->ip, 10, 60);
            $u = $this->auth->completeSetup($token, (string) ($f['password'] ?? ''), (string) ($f['confirm'] ?? ''));
        } catch (AdminError $e) {
            return $this->setupForm($token, $e->getMessage());
        } catch (ApiException) {
            return $this->setupForm($token, 'Muitas tentativas. Aguarde um minuto.');
        }
        $this->audit('setup_completed', 'admin_user', (string) $u['id'], null, (int) $u['id']);
        $this->setFlash('ok', 'Senha definida. Entre com seu e-mail e a nova senha.');
        return $this->redirect('login');
    }

    /** Link absoluto de configuração para mostrar uma única vez a quem criou o usuário. */
    public function setupLink(string $token): string
    {
        $base = rtrim((string) ($this->app->config->optional('APP_URL') ?? ''), '/');
        if ($base === '') {
            $host = (string) ($this->req->header('host') ?? 'localhost');
            $base = ($this->req->secure ? 'https://' : 'http://') . $host . $this->req->basePath;
        }
        return $base . '/admin/setup?token=' . $token;
    }
}
