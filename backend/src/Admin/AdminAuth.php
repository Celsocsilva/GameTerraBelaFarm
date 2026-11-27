<?php
declare(strict_types=1);

namespace TerraBela\Admin;

use TerraBela\Core\Clock;
use TerraBela\Core\Db;

/**
 * Login do backoffice: senha (password_hash), bloqueio após falhas, 2FA TOTP opcional, sessão no MySQL
 * (cookie opaco guardado como HMAC), expiração por inatividade e absoluta, token CSRF por sessão,
 * e link de configuração de uso único para novos operadores (a senha nunca passa por e-mail, arquivo ou chat).
 */
final class AdminAuth
{
    public const MIN_PASSWORD = 12;
    public const MAX_FAILURES = 5;
    public const LOCK_SECONDS = 900;
    public const SETUP_TTL = 72 * 3600;

    public function __construct(
        private Db $db,
        private Clock $clock,
        private string $appKey,
        private int $idleSeconds = 1800,
        private int $absoluteSeconds = 43200,
    ) {
    }

    public function hash(string $token): string
    {
        return hash_hmac('sha256', 'admin|' . $token, $this->appKey);
    }

    public function ipHash(string $ip): string
    {
        return hash_hmac('sha256', 'ip|' . $ip, $this->appKey);
    }

    /** @return array{token:string,admin_id:int,mfa_required:bool} */
    public function login(string $email, string $password, string $ip, ?string $userAgent): array
    {
        $email = strtolower(trim($email));
        $u = $this->db->one('SELECT * FROM admin_users WHERE email = ?', [$email]);
        $now = $this->clock->now();
        if ($u === null || $u['password_hash'] === null) {
            password_verify($password, '$2y$10$94il4Ow.RfTt342VVyxl6ebt4ecSDTRKda.twlVO9cTYP27pCMGFi'); // tempo constante
            throw new AdminError('E-mail ou senha incorretos.', null);
        }
        if ($u['status'] !== 'active') {
            throw new AdminError('Usuário desativado.', (int) $u['id']);
        }
        if ($u['locked_until'] !== null && strtotime($u['locked_until'] . ' UTC') > $now) {
            throw new AdminError('Muitas tentativas. Tente de novo em 15 minutos.', (int) $u['id']);
        }
        if (!password_verify($password, $u['password_hash'])) {
            $fails = (int) $u['failed_attempts'] + 1;
            $lock = $fails >= self::MAX_FAILURES ? $this->clock->sql(self::LOCK_SECONDS) : null;
            $this->db->exec('UPDATE admin_users SET failed_attempts = ?, locked_until = ? WHERE id = ?', [$lock === null ? $fails : 0, $lock, $u['id']]);
            throw new AdminError($lock === null ? 'E-mail ou senha incorretos.' : 'Muitas tentativas. Login bloqueado por 15 minutos.', (int) $u['id']);
        }
        if (password_needs_rehash($u['password_hash'], PASSWORD_DEFAULT)) {
            $this->db->exec('UPDATE admin_users SET password_hash = ? WHERE id = ?', [password_hash($password, PASSWORD_DEFAULT), $u['id']]);
        }
        $this->db->exec('UPDATE admin_users SET failed_attempts = 0, locked_until = NULL WHERE id = ?', [$u['id']]);
        $mfa = (int) $u['totp_enabled'] === 1;
        $token = bin2hex(random_bytes(32));
        $this->db->insert(
            'INSERT INTO admin_sessions (admin_id, token_hash, csrf_token, mfa_passed, ip_hash, user_agent, created_at, last_seen_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$u['id'], $this->hash($token), bin2hex(random_bytes(32)), $mfa ? 0 : 1, $this->ipHash($ip), $userAgent === null ? null : mb_substr($userAgent, 0, 255),
             $this->clock->sql(), $this->clock->sql(), $this->clock->sql($mfa ? 600 : $this->absoluteSeconds)]
        );
        if (!$mfa) {
            $this->db->exec('UPDATE admin_users SET last_login_at = ? WHERE id = ?', [$this->clock->sql(), $u['id']]);
        }
        return ['token' => $token, 'admin_id' => (int) $u['id'], 'mfa_required' => $mfa];
    }

    /** Sessão válida (com usuário) ou null. Atualiza last_seen_at. @return array<string,mixed>|null */
    public function session(?string $token): ?array
    {
        if ($token === null || !preg_match('/^[a-f0-9]{64}$/', $token)) {
            return null;
        }
        $s = $this->db->one(
            'SELECT s.id AS session_id, s.csrf_token, s.mfa_passed, s.last_seen_at, s.expires_at, s.revoked_at,
                    u.id, u.email, u.display_name, u.role, u.status, u.totp_enabled, u.totp_secret, u.totp_last_step
               FROM admin_sessions s JOIN admin_users u ON u.id = s.admin_id WHERE s.token_hash = ?',
            [$this->hash($token)]
        );
        $now = $this->clock->now();
        if ($s === null || $s['revoked_at'] !== null || $s['status'] !== 'active'
            || strtotime($s['expires_at'] . ' UTC') <= $now
            || strtotime($s['last_seen_at'] . ' UTC') + $this->idleSeconds <= $now) {
            return null;
        }
        $this->db->exec('UPDATE admin_sessions SET last_seen_at = ? WHERE id = ?', [$this->clock->sql(), $s['session_id']]);
        return $s;
    }

    /** Segundo fator; troca o cookie (fixação de sessão) e devolve o token novo. */
    public function verifyMfa(array $s, string $code): string
    {
        $step = $s['totp_secret'] === null ? null : Totp::matchStep($s['totp_secret'], $code, $this->clock->now());
        if ($step === null || ($s['totp_last_step'] !== null && $step <= (int) $s['totp_last_step'])) {
            $fails = (int) $this->db->one('SELECT failed_attempts FROM admin_users WHERE id = ?', [$s['id']])['failed_attempts'] + 1;
            if ($fails >= self::MAX_FAILURES) {
                $this->db->exec('UPDATE admin_users SET failed_attempts = 0, locked_until = ? WHERE id = ?', [$this->clock->sql(self::LOCK_SECONDS), $s['id']]);
                $this->revoke((int) $s['session_id']);
                throw new AdminError('Muitos códigos errados. Login bloqueado por 15 minutos.', (int) $s['id']);
            }
            $this->db->exec('UPDATE admin_users SET failed_attempts = ? WHERE id = ?', [$fails, $s['id']]);
            throw new AdminError('Código inválido ou já usado.', (int) $s['id']);
        }
        $token = bin2hex(random_bytes(32));
        $this->db->tx(function (Db $db) use ($s, $token, $step) {
            $db->exec('UPDATE admin_users SET totp_last_step = ?, failed_attempts = 0, last_login_at = ? WHERE id = ?', [$step, $this->clock->sql(), $s['id']]);
            $db->exec(
                'UPDATE admin_sessions SET token_hash = ?, csrf_token = ?, mfa_passed = 1, expires_at = ? WHERE id = ?',
                [$this->hash($token), bin2hex(random_bytes(32)), $this->clock->sql($this->absoluteSeconds), $s['session_id']]
            );
        });
        return $token;
    }

    public function revoke(int $sessionId): void
    {
        $this->db->exec('UPDATE admin_sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL', [$this->clock->sql(), $sessionId]);
    }

    public function revokeAll(int $adminId, ?int $exceptSessionId = null): void
    {
        $this->db->exec(
            'UPDATE admin_sessions SET revoked_at = ? WHERE admin_id = ? AND revoked_at IS NULL AND id <> ?',
            [$this->clock->sql(), $adminId, $exceptSessionId ?? 0]
        );
    }

    public static function validatePassword(string $password, string $email): void
    {
        if (mb_strlen($password) < self::MIN_PASSWORD || mb_strlen($password) > 200) {
            throw new AdminError('A senha precisa ter de ' . self::MIN_PASSWORD . ' a 200 caracteres.', null);
        }
        if (stripos($password, explode('@', $email)[0]) !== false || preg_match('/^(.)\1+$/', $password)) {
            throw new AdminError('Senha fraca: não use o e-mail nem caracteres repetidos.', null);
        }
    }

    /** Cria operador sem senha e devolve o token do link de configuração (mostrado uma única vez). */
    public function createUser(string $email, string $name, string $role): array
    {
        $email = strtolower(trim($email));
        $name = trim($name);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 191) {
            throw new AdminError('E-mail inválido.', null);
        }
        if ($name === '' || mb_strlen($name) > 80) {
            throw new AdminError('Nome obrigatório (até 80 caracteres).', null);
        }
        if (!isset(Rbac::ROLES[$role])) {
            throw new AdminError('Papel inválido.', null);
        }
        if ($this->db->one('SELECT id FROM admin_users WHERE email = ?', [$email]) !== null) {
            throw new AdminError('Já existe um usuário com este e-mail.', null);
        }
        $token = bin2hex(random_bytes(24));
        $id = $this->db->insert(
            'INSERT INTO admin_users (email, display_name, role, status, setup_token_hash, setup_expires_at, created_at, updated_at) VALUES (?, ?, ?, \'active\', ?, ?, ?, ?)',
            [$email, $name, $role, hash('sha256', $token), $this->clock->sql(self::SETUP_TTL), $this->clock->sql(), $this->clock->sql()]
        );
        return ['id' => $id, 'token' => $token];
    }

    /** Novo link de configuração (esqueceu a senha / perdeu o 2FA): apaga senha e 2FA e derruba as sessões. */
    public function resetSetup(int $adminId): string
    {
        $token = bin2hex(random_bytes(24));
        $this->db->exec(
            'UPDATE admin_users SET password_hash = NULL, totp_secret = NULL, totp_enabled = 0, totp_last_step = NULL, failed_attempts = 0, locked_until = NULL,
                    setup_token_hash = ?, setup_expires_at = ?, updated_at = ? WHERE id = ?',
            [hash('sha256', $token), $this->clock->sql(self::SETUP_TTL), $this->clock->sql(), $adminId]
        );
        $this->revokeAll($adminId);
        return $token;
    }

    /** @return array<string,mixed>|null */
    public function setupUser(string $token): ?array
    {
        if (!preg_match('/^[a-f0-9]{48}$/', $token)) {
            return null;
        }
        $u = $this->db->one('SELECT id, email, display_name, role, status, setup_expires_at FROM admin_users WHERE setup_token_hash = ?', [hash('sha256', $token)]);
        if ($u === null || $u['status'] !== 'active' || strtotime($u['setup_expires_at'] . ' UTC') <= $this->clock->now()) {
            return null;
        }
        return $u;
    }

    public function completeSetup(string $token, string $password, string $confirm): array
    {
        $u = $this->setupUser($token);
        if ($u === null) {
            throw new AdminError('Link inválido ou expirado. Peça um novo ao administrador.', null);
        }
        if (!hash_equals($password, $confirm)) {
            throw new AdminError('As senhas não conferem.', (int) $u['id']);
        }
        self::validatePassword($password, $u['email']);
        $n = $this->db->exec(
            'UPDATE admin_users SET password_hash = ?, setup_token_hash = NULL, setup_expires_at = NULL, failed_attempts = 0, locked_until = NULL, updated_at = ?
              WHERE id = ? AND setup_token_hash = ?',
            [password_hash($password, PASSWORD_DEFAULT), $this->clock->sql(), $u['id'], hash('sha256', $token)]
        );
        if ($n === 0) {
            throw new AdminError('Link já utilizado.', (int) $u['id']);
        }
        return $u;
    }

    public function changePassword(array $s, string $current, string $new, string $confirm): void
    {
        $u = $this->db->one('SELECT password_hash, email FROM admin_users WHERE id = ?', [$s['id']]);
        if ($u === null || $u['password_hash'] === null || !password_verify($current, $u['password_hash'])) {
            throw new AdminError('Senha atual incorreta.', (int) $s['id']);
        }
        if (!hash_equals($new, $confirm)) {
            throw new AdminError('As senhas novas não conferem.', (int) $s['id']);
        }
        self::validatePassword($new, $u['email']);
        $this->db->exec('UPDATE admin_users SET password_hash = ?, updated_at = ? WHERE id = ?', [password_hash($new, PASSWORD_DEFAULT), $this->clock->sql(), $s['id']]);
        $this->revokeAll((int) $s['id'], (int) $s['session_id']);
    }

    /** Gera segredo pendente (ainda não exigido no login). */
    public function totpStart(array $s): string
    {
        $secret = Totp::newSecret();
        $this->db->exec('UPDATE admin_users SET totp_secret = ?, totp_enabled = 0, totp_last_step = NULL, updated_at = ? WHERE id = ?', [$secret, $this->clock->sql(), $s['id']]);
        return $secret;
    }

    public function totpConfirm(array $s, string $code): void
    {
        $u = $this->db->one('SELECT totp_secret FROM admin_users WHERE id = ?', [$s['id']]);
        $step = $u['totp_secret'] === null ? null : Totp::matchStep($u['totp_secret'], $code, $this->clock->now());
        if ($step === null) {
            throw new AdminError('Código inválido. Confira o horário do celular e tente de novo.', (int) $s['id']);
        }
        $this->db->exec('UPDATE admin_users SET totp_enabled = 1, totp_last_step = ?, updated_at = ? WHERE id = ?', [$step, $this->clock->sql(), $s['id']]);
        $this->revokeAll((int) $s['id'], (int) $s['session_id']);
    }

    public function totpDisable(array $s, string $password): void
    {
        $u = $this->db->one('SELECT password_hash FROM admin_users WHERE id = ?', [$s['id']]);
        if ($u === null || $u['password_hash'] === null || !password_verify($password, $u['password_hash'])) {
            throw new AdminError('Senha incorreta.', (int) $s['id']);
        }
        $this->db->exec('UPDATE admin_users SET totp_secret = NULL, totp_enabled = 0, totp_last_step = NULL, updated_at = ? WHERE id = ?', [$this->clock->sql(), $s['id']]);
    }

    public function setStatus(int $adminId, string $status): void
    {
        $this->db->exec('UPDATE admin_users SET status = ?, updated_at = ? WHERE id = ?', [$status, $this->clock->sql(), $adminId]);
        if ($status !== 'active') {
            $this->revokeAll($adminId);
        }
    }
}
