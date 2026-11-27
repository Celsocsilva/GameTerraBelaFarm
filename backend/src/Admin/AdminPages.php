<?php
declare(strict_types=1);

namespace TerraBela\Admin;

use TerraBela\Core\Clock;
use TerraBela\Core\Ids;
use TerraBela\Http\Response;
use TerraBela\LiveOps\CampaignService;
use TerraBela\LiveOps\RuleEngine;

/** Telas do backoffice. Cada ação de escrita passa por AdminApp::act (RBAC + CSRF já validado + PRG) e grava auditoria. */
final class AdminPages
{
    private const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    private const PER_PAGE = 50;

    public function __construct(private AdminApp $a)
    {
    }

    public function route(string $sub, bool $post): Response
    {
        $u = self::UUID;
        $routes = [
            ['GET', '#^$#', 'view', fn () => $this->dashboard()],
            ['POST', '#^metrics/recompute$#', 'rules.manage', fn () => $this->recompute()],
            ['GET', '#^players$#', 'view', fn () => $this->players()],
            ['GET', "#^players/($u)$#", 'view', fn ($m) => $this->player($m[1])],
            ['POST', "#^players/($u)/wallet$#", 'wallet.adjust', fn ($m) => $this->walletAdjust($m[1])],
            ['POST', "#^players/($u)/reward$#", 'players.support', fn ($m) => $this->rewardGrant($m[1])],
            ['POST', "#^players/($u)/revoke$#", 'players.support', fn ($m) => $this->revokeSessions($m[1])],
            ['POST', "#^players/($u)/export$#", 'players.support', fn ($m) => $this->playerExport($m[1])],
            ['GET', '#^system$#', 'system.manage', fn () => $this->system()],
            ['POST', '#^system/backup$#', 'system.manage', fn () => $this->backupNow()],
            ['GET', '#^ledger$#', 'view', fn () => $this->ledger()],
            ['GET', '#^purchases$#', 'view', fn () => $this->purchases()],
            ['GET', '#^products$#', 'view', fn () => $this->products()],
            ['POST', '#^products$#', 'products.manage', fn () => $this->productAdd()],
            ['POST', '#^products/(\d+)/deactivate$#', 'products.manage', fn ($m) => $this->productDeactivate((int) $m[1])],
            ['GET', '#^config$#', 'view', fn () => $this->config()],
            ['POST', '#^config/publish$#', 'config.publish', fn () => $this->configPublish()],
            ['POST', '#^config/retire$#', 'config.publish', fn () => $this->configRetire()],
            ['GET', '#^events$#', 'view', fn () => $this->events()],
            ['GET', '#^campaigns$#', 'view', fn () => $this->campaigns()],
            ['POST', '#^campaigns$#', 'campaigns.manage', fn () => $this->campaignCreate()],
            ['GET', '#^campaigns/(\d+)$#', 'view', fn ($m) => $this->campaign((int) $m[1])],
            ['POST', '#^campaigns/(\d+)/(schedule|cancel|test)$#', 'campaigns.manage', fn ($m) => $this->campaignAction((int) $m[1], $m[2])],
            ['GET', '#^rules$#', 'view', fn () => $this->rules()],
            ['POST', '#^rules$#', 'rules.manage', fn () => $this->ruleCreate()],
            ['GET', '#^rules/(\d+)$#', 'view', fn ($m) => $this->rule((int) $m[1])],
            ['POST', '#^rules/(\d+)/(dryrun|run|activate|pause)$#', 'rules.manage', fn ($m) => $this->ruleAction((int) $m[1], $m[2])],
            ['GET', '#^experiments$#', 'view', fn () => $this->experiments()],
            ['POST', '#^experiments$#', 'experiments.manage', fn () => $this->experimentCreate()],
            ['GET', '#^experiments/(\d+)$#', 'view', fn ($m) => $this->experiment((int) $m[1])],
            ['POST', '#^experiments/(\d+)/(start|stop)$#', 'experiments.manage', fn ($m) => $this->experimentAction((int) $m[1], $m[2])],
            ['GET', '#^calendar$#', 'view', fn () => $this->calendar()],
            ['GET', '#^audit$#', 'audit.view', fn () => $this->audit()],
            ['GET', '#^users$#', 'users.manage', fn () => $this->users()],
            ['POST', '#^users$#', 'users.manage', fn () => $this->userCreate()],
            ['POST', '#^users/(\d+)/(disable|enable|reset)$#', 'users.manage', fn ($m) => $this->userAction((int) $m[1], $m[2])],
            ['GET', '#^account$#', 'view', fn () => $this->account()],
            ['POST', '#^account/(password|totp-start|totp-confirm|totp-disable)$#', 'view', fn ($m) => $this->accountAction($m[1])],
        ];
        $method = $post ? 'POST' : 'GET';
        foreach ($routes as [$verb, $re, $perm, $fn]) {
            if ($verb === $method && preg_match($re, $sub, $m)) {
                return $this->a->can($perm) ? $fn($m) : $this->a->forbidden();
            }
        }
        return $this->a->render('Página não encontrada', '<p><a href="' . $this->url('') . '">Voltar ao painel</a></p>', '', 404);
    }

    // ------------------------------------------------------------------ helpers

    private function url(string $path, array $q = []): string
    {
        return View::h($this->a->view->url($path, $q));
    }

    private function q(string $k, string $default = ''): string
    {
        $v = $this->a->req->query[$k] ?? $default;
        return is_string($v) ? trim($v) : $default;
    }

    private function page(): int
    {
        return max(1, min(1000, (int) $this->q('page', '1')));
    }

    private function form(string $action, string $inner, string $class = 'stack', string $button = 'Salvar', string $btnClass = ''): string
    {
        return '<form method="post" class="' . $class . '" action="' . $this->url($action) . '">' . $this->a->view->csrf($this->a->s) . $inner
            . '<button' . ($btnClass === '' ? '' : ' class="' . $btnClass . '"') . '>' . View::h($button) . '</button></form>';
    }

    private function nonce(): string
    {
        return '<input type="hidden" name="nonce" value="' . bin2hex(random_bytes(8)) . '">';
    }

    /** @return array<string,mixed> */
    private function playerByUuid(string $uuid): array
    {
        $bin = Ids::uuidToBin($uuid);
        $p = $bin === null ? null : $this->a->db->one('SELECT * FROM players WHERE public_id = ?', [$bin]);
        if ($p === null) {
            throw new AdminError('Jogador não encontrado.');
        }
        return $p;
    }

    private function playerLink(?string $bin): string
    {
        if ($bin === null) {
            return '—';
        }
        $uuid = Ids::binToUuid($bin);
        return '<a href="' . $this->url('players/' . $uuid) . '"><code>' . View::h(substr($uuid, 0, 8)) . '…</code></a>';
    }

    private static function json(?string $raw): string
    {
        if ($raw === null) {
            return '—';
        }
        $d = json_decode($raw, true);
        return '<code>' . View::h(json_encode($d, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)) . '</code>';
    }

    private static function stateBadge(string $s): string
    {
        $kind = match ($s) {
            'granted', 'active', 'sent', 'completed', 'published', 'available', 'claimed' => 'ok',
            'refunded', 'failed', 'canceled', 'disabled', 'retired', 'deleted', 'expired' => 'bad',
            'pending', 'scheduled', 'sending', 'paused', 'draft', 'deletion_requested' => 'warn',
            default => '',
        };
        return View::badge($s, $kind);
    }

    /** "2026-12-01T10:00" no horário de Brasília → DATETIME UTC. */
    private static function localToUtc(string $v): ?string
    {
        if ($v === '') {
            return null;
        }
        $d = \DateTimeImmutable::createFromFormat('Y-m-d\TH:i', $v, new \DateTimeZone('America/Sao_Paulo'));
        if ($d === false) {
            throw new AdminError('Data/hora inválida.');
        }
        return $d->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');
    }

    // ------------------------------------------------------------------ painel

    private function dashboard(): Response
    {
        $db = $this->a->db;
        $c = $this->a->clock;
        $n = fn (string $sql, array $p = []) => (int) ($db->one($sql, $p)['n'] ?? 0);
        $m = $this->a->app->metrics;
        $kpis = View::kpi('Jogadores', $n("SELECT COUNT(*) n FROM players WHERE status <> 'deleted'"))
            . View::kpi('Ativos 24 h', $n('SELECT COUNT(*) n FROM players WHERE last_seen_at >= ?', [$c->sql(-86400)]))
            . View::kpi('Ativos 7 dias', $n('SELECT COUNT(*) n FROM players WHERE last_seen_at >= ?', [$c->sql(-7 * 86400)]))
            . View::kpi('Novos hoje (UTC)', $n('SELECT COUNT(*) n FROM players WHERE created_at >= ?', [gmdate('Y-m-d 00:00:00', $c->now())]))
            . View::kpi('Saves na nuvem', $n('SELECT COUNT(*) n FROM player_saves'))
            . View::kpi('Compras 30 dias', $n('SELECT COUNT(*) n FROM iap_transactions WHERE granted_at >= ?', [$c->sql(-30 * 86400)]))
            . View::kpi('Reembolsos 30 dias', $n('SELECT COUNT(*) n FROM iap_transactions WHERE refunded_at >= ?', [$c->sql(-30 * 86400)]))
            . View::kpi('Compras a finalizar', $n("SELECT COUNT(*) n FROM iap_transactions WHERE finalize_status = 'pending'"), 'acknowledge/consume na Google')
            . View::kpi('Push enviados 7 dias', $n("SELECT COUNT(*) n FROM notification_outbox WHERE status = 'sent' AND sent_at >= ?", [$c->sql(-7 * 86400)]))
            . View::kpi('Benefícios resgatados 7 dias', $n('SELECT COUNT(*) n FROM reward_grants WHERE claimed_at >= ?', [$c->sql(-7 * 86400)]));
        $last = $db->one('SELECT MAX(computed_at) AS t FROM daily_metrics');
        $schema = $db->one('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1');
        $maint = $this->a->app->remoteConfig->value('maintenance.enabled', false) === true;
        $body = ($maint ? '<div class="flash error">Modo manutenção LIGADO no Remote Config: o jogo está bloqueado para os jogadores.</div>' : '')
            . '<div class="grid">' . $kpis . '</div>'
            . '<h2>Últimos 30 dias</h2><div class="cols">'
            . View::bars($m->series('dau', 30), 'Jogadores ativos por dia (DAU)')
            . View::bars($m->series('new_players', 30), 'Novos jogadores')
            . View::bars($m->series('iap_granted', 30), 'Compras confirmadas')
            . View::bars($m->series('push_opened', 30), 'Push abertos')
            . View::bars($m->series('gold_source', 30), 'Ouro creditado')
            . View::bars($m->series('gold_sink', 30), 'Ouro gasto')
            . '</div>'
            . '<h2>Retenção por coorte</h2>'
            . View::table($m->retention(14), [
                'cohort' => 'Coorte (UTC)', 'size' => 'Jogadores',
                'D1' => fn ($r) => $r['d1'] === null ? '—' : View::h($r['d1'] . '%'),
                'D7' => fn ($r) => $r['d7'] === null ? '—' : View::h($r['d7'] . '%'),
                'D30' => fn ($r) => $r['d30'] === null ? '—' : View::h($r['d30'] . '%'),
            ], 'Sem coortes ainda.')
            . '<h2>Sistema</h2><div class="card">' . View::dl([
                'Ambiente' => $this->a->app->config->str('APP_ENV', 'production'),
                'Schema do banco' => $schema['version'] ?? '—',
                'Métricas atualizadas em' => View::dt($last['t'] ?? null) . ' (o cron recalcula hoje e ontem a cada execução)',
                'Remote Config publicado' => 'v' . ($this->a->app->remoteConfig->current(null)['version'] ?? '—'),
                'Crash/ANR' => 'Android Vitals no Google Play Console (o backend não recebe crash)',
            ])
            . ($this->a->can('rules.manage') ? $this->form('metrics/recompute', '', 'inline', 'Recalcular métricas (30 dias)', 'ghost') : '')
            . '</div>';
        return $this->a->render('Painel', $body, '');
    }

    private function recompute(): Response
    {
        return $this->a->act('rules.manage', '', function () {
            $rows = $this->a->app->metrics->recompute(29);
            $this->a->audit('metrics_recompute', null, null, ['rows' => $rows]);
            return "Métricas recalculadas ($rows linhas).";
        });
    }

    // ------------------------------------------------------------------ jogadores

    private function players(): Response
    {
        $q = $this->q('q');
        $status = $this->q('status');
        $page = $this->page();
        $where = [];
        $p = [];
        if ($q !== '') {
            $bin = Ids::uuidToBin(strtolower($q));
            if ($bin !== null) {
                $where[] = 'p.public_id = ?';
                $p[] = $bin;
            } elseif (preg_match('/^[0-9a-f]{4,}$/i', $q)) {
                $where[] = 'HEX(p.public_id) LIKE ?';
                $p[] = strtoupper(str_replace('-', '', $q)) . '%';
            } else {
                $where[] = 'EXISTS (SELECT 1 FROM player_devices d WHERE d.player_id = p.id AND d.installation_id = ?)';
                $p[] = $q;
            }
        }
        if (in_array($status, ['active', 'deletion_requested', 'deleted'], true)) {
            $where[] = 'p.status = ?';
            $p[] = $status;
        }
        $rows = $this->a->db->all(
            'SELECT p.public_id, p.status, p.created_at, p.last_seen_at, p.locale, w.cash_balance, w.gold_balance,
                    (SELECT GROUP_CONCAT(DISTINCT i.provider ORDER BY i.provider) FROM player_identities i WHERE i.player_id = p.id) AS providers
               FROM players p LEFT JOIN wallets w ON w.player_id = p.id'
            . ($where ? ' WHERE ' . implode(' AND ', $where) : '')
            . ' ORDER BY p.id DESC LIMIT ' . (self::PER_PAGE + 1) . ' OFFSET ' . (($page - 1) * self::PER_PAGE),
            $p
        );
        $more = count($rows) > self::PER_PAGE;
        $rows = array_slice($rows, 0, self::PER_PAGE);
        $body = '<form class="row" method="get" action="' . $this->url('players') . '">'
            . '<label>Busca<input name="q" value="' . View::h($q) . '" placeholder="player_id, início do id ou installation_id"></label>'
            . '<label>Estado' . View::select('status', ['active' => 'ativo', 'deletion_requested' => 'exclusão pedida', 'deleted' => 'excluído'], $status, true) . '</label>'
            . '<button>Filtrar</button></form><br>'
            . View::table($rows, [
                'Jogador' => fn ($r) => $this->playerLink($r['public_id']),
                'Estado' => fn ($r) => self::stateBadge($r['status']),
                'Login' => fn ($r) => View::h($r['providers'] ?? '—'),
                'Cash' => fn ($r) => View::h(number_format((int) $r['cash_balance'], 0, ',', '.')),
                'Ouro' => fn ($r) => View::h(number_format((int) $r['gold_balance'], 0, ',', '.')),
                'Idioma' => fn ($r) => View::h($r['locale'] ?? '—'),
                'Criado' => fn ($r) => View::dt($r['created_at']),
                'Último acesso' => fn ($r) => View::dt($r['last_seen_at']),
            ], 'Nenhum jogador encontrado.')
            . View::pager(fn ($n) => $this->a->view->url('players', ['q' => $q, 'status' => $status, 'page' => $n]), $page, $more);
        return $this->a->render('Jogadores', $body, 'players');
    }

    private function player(string $uuid): Response
    {
        try {
            $p = $this->playerByUuid($uuid);
        } catch (AdminError $e) {
            return $this->a->render('Jogador não encontrado', '<p><a href="' . $this->url('players') . '">Voltar</a></p>', 'players', 404);
        }
        $db = $this->a->db;
        $id = (int) $p['id'];
        $w = $db->one('SELECT * FROM wallets WHERE player_id = ?', [$id]);
        $save = $db->one('SELECT revision, schema_version, snapshot_bytes, client_saved_at, updated_at FROM player_saves WHERE player_id = ?', [$id]);
        $versions = (int) $db->one('SELECT COUNT(*) n FROM player_save_versions WHERE player_id = ?', [$id])['n'];
        $sessions = (int) $db->one('SELECT COUNT(*) n FROM player_sessions WHERE player_id = ? AND revoked_at IS NULL AND refresh_expires_at > ?', [$id, $this->a->clock->sql()])['n'];
        $consents = $db->all(
            'SELECT c.consent_type, c.granted, c.source, c.recorded_at FROM player_consents c
              WHERE c.player_id = ? AND c.id = (SELECT MAX(c2.id) FROM player_consents c2 WHERE c2.player_id = c.player_id AND c2.consent_type = c.consent_type)
              ORDER BY c.consent_type',
            [$id]
        );
        $body = '<div class="cols"><div class="card">' . View::dl([
                'player_id' => $uuid,
                'Estado' => $p['status'],
                'Criado' => View::dt($p['created_at']),
                'Último acesso' => View::dt($p['last_seen_at']),
                'Idioma' => $p['locale'],
                'Exclusão pedida em' => View::dt($p['deletion_requested_at']),
                'Sessões ativas' => $sessions,
            ]) . '</div><div class="card">' . View::dl([
                'Cash' => number_format((int) ($w['cash_balance'] ?? 0), 0, ',', '.'),
                'Ouro' => number_format((int) ($w['gold_balance'] ?? 0), 0, ',', '.'),
                'Versão da carteira' => $w['version'] ?? '—',
                'Save (revisão)' => $save === null ? 'sem save na nuvem' : $save['revision'] . ' · schema ' . $save['schema_version'] . ' · ' . number_format((int) $save['snapshot_bytes'], 0, ',', '.') . ' bytes',
                'Save atualizado' => View::dt($save['updated_at'] ?? null),
                'Versões anteriores guardadas' => $versions,
            ]) . '</div></div>';

        // Ações
        $actions = '';
        if ($this->a->can('wallet.adjust')) {
            $actions .= '<div class="card"><b>Ajustar carteira</b><p class="muted">Crédito ou débito manual lançado no ledger (source admin). Nunca deixa saldo negativo. Limite de 1.000.000 por ajuste.</p>'
                . $this->form('players/' . $uuid . '/wallet', $this->nonce()
                    . '<label>Moeda</label>' . View::select('currency', ['cash' => 'cash', 'gold' => 'ouro'], 'cash')
                    . '<label>Quantidade (negativo para debitar)</label><input name="amount" type="number" required min="-1000000" max="1000000">'
                    . '<label>Motivo (fica na auditoria)</label><input name="note" required minlength="5" maxlength="200">', 'stack', 'Lançar ajuste') . '</div>';
        }
        if ($this->a->can('players.support')) {
            $actions .= '<div class="card"><b>Conceder benefício</b><p class="muted">Fica disponível em “Recompensas” no jogo até o jogador resgatar.</p>'
                . $this->form('players/' . $uuid . '/reward', $this->nonce()
                    . '<label>Moeda</label>' . View::select('currency', ['cash' => 'cash', 'gold' => 'ouro'], 'cash')
                    . '<label>Quantidade</label><input name="amount" type="number" required min="1" max="100000">'
                    . '<label>Expira em (dias, vazio = não expira)</label><input name="days" type="number" min="1" max="365">'
                    . '<label>Motivo (fica na auditoria)</label><input name="note" required minlength="5" maxlength="200">', 'stack', 'Conceder') . '</div>'
                . '<div class="card"><b>Exportar dados (LGPD)</b><p class="muted">Arquivo JSON com tudo o que o servidor guarda sobre a conta, para atender pedido do titular. Fica registrado na auditoria.</p>'
                . $this->form('players/' . $uuid . '/export', '', 'stack', 'Baixar JSON', 'ghost') . '</div>'
                . '<div class="card"><b>Encerrar sessões</b><p class="muted">Desconecta o jogador em todos os aparelhos (ele entra de novo com o mesmo login).</p>'
                . $this->form('players/' . $uuid . '/revoke', '', 'stack', 'Encerrar sessões', 'danger') . '</div>';
        }
        if ($actions !== '') {
            $body .= '<h2>Ações</h2><div class="cols">' . $actions . '</div>';
        }

        $body .= '<h2>Logins vinculados</h2>' . View::table($db->all('SELECT provider, subject, created_at, last_used_at FROM player_identities WHERE player_id = ?', [$id]), [
                'provider' => 'Provedor',
                'Identificador' => fn ($r) => '<code>' . View::h($r['provider'] === 'guest' ? '(visitante)' : substr($r['subject'], 0, 4) . '…' . substr($r['subject'], -3)) . '</code>',
                'Vinculado' => fn ($r) => View::dt($r['created_at']),
                'Último uso' => fn ($r) => View::dt($r['last_used_at']),
            ])
            . '<h2>Aparelhos</h2>' . View::table($db->all('SELECT public_id, platform, app_version, locale, timezone, fcm_token IS NOT NULL AS has_token, last_seen_at, revoked_at FROM player_devices WHERE player_id = ? ORDER BY id DESC LIMIT 20', [$id]), [
                'Instalação' => fn ($r) => '<code>' . View::h(Ids::binToUuid($r['public_id'])) . '</code>',
                'platform' => 'Plataforma', 'app_version' => 'Versão', 'locale' => 'Idioma', 'timezone' => 'Fuso',
                'Push' => fn ($r) => $r['revoked_at'] !== null ? View::badge('removido', 'bad') : ((int) $r['has_token'] ? View::badge('token ativo', 'ok') : View::badge('sem token')),
                'Visto' => fn ($r) => View::dt($r['last_seen_at']),
            ])
            . '<h2>Consentimentos (último registro)</h2>' . View::table($consents, [
                'consent_type' => 'Tipo',
                'Valor' => fn ($r) => (int) $r['granted'] ? View::badge('sim', 'ok') : View::badge('não', 'bad'),
                'source' => 'Origem',
                'Quando' => fn ($r) => View::dt($r['recorded_at']),
            ])
            . '<h2>Ledger (últimos 50)</h2>' . $this->ledgerTable($db->all('SELECT l.*, NULL AS public_id FROM economy_ledger l WHERE l.player_id = ? ORDER BY l.id DESC LIMIT 50', [$id]), false)
            . '<h2>Compras</h2>' . $this->purchaseTable($db->all('SELECT t.*, pr.sku, NULL AS player_public FROM iap_transactions t JOIN iap_products pr ON pr.id = t.product_id WHERE t.player_id = ? ORDER BY t.id DESC LIMIT 50', [$id]), false)
            . '<h2>Direitos (entitlements)</h2>' . View::table($db->all('SELECT * FROM entitlements WHERE player_id = ? ORDER BY id DESC', [$id]), [
                'entitlement_key' => 'Direito', 'source' => 'Origem', 'source_reference' => 'Referência',
                'Concedido' => fn ($r) => View::dt($r['granted_at']),
                'Revogado' => fn ($r) => View::dt($r['revoked_at']),
            ])
            . '<h2>Benefícios</h2>' . View::table($db->all('SELECT * FROM reward_grants WHERE player_id = ? ORDER BY id DESC LIMIT 50', [$id]), [
                'rule_key' => 'Regra', 'occurrence_key' => 'Ocorrência',
                'Benefício' => fn ($r) => View::h(trim(($r['amount'] ?? '') . ' ' . ($r['currency'] ?? '') . ' ' . ($r['entitlement_key'] ?? ''))),
                'Estado' => fn ($r) => self::stateBadge($r['status']),
                'Criado' => fn ($r) => View::dt($r['created_at']),
                'Expira' => fn ($r) => View::dt($r['expires_at']),
                'Resgatado' => fn ($r) => View::dt($r['claimed_at']),
            ])
            . '<h2>Auditoria deste jogador</h2>' . $this->auditTable($db->all(
                'SELECT l.*, u.display_name FROM admin_audit_log l LEFT JOIN admin_users u ON u.id = l.admin_id WHERE l.target_type = \'player\' AND l.target_id = ? ORDER BY l.id DESC LIMIT 30',
                [$uuid]
            ));
        return $this->a->render('Jogador ' . substr($uuid, 0, 8), $body, 'players');
    }

    private function walletAdjust(string $uuid): Response
    {
        return $this->a->act('wallet.adjust', 'players/' . $uuid, function (array $f) use ($uuid) {
            $p = $this->playerByUuid($uuid);
            $currency = (string) ($f['currency'] ?? '');
            $amount = filter_var($f['amount'] ?? '', FILTER_VALIDATE_INT);
            $note = trim((string) ($f['note'] ?? ''));
            $nonce = (string) ($f['nonce'] ?? '');
            if (!in_array($currency, ['cash', 'gold'], true) || $amount === false || $amount === 0 || abs($amount) > 1_000_000) {
                throw new AdminError('Informe moeda e quantidade entre -1.000.000 e 1.000.000 (diferente de zero).');
            }
            if (mb_strlen($note) < 5 || mb_strlen($note) > 200 || !preg_match('/^[a-f0-9]{16}$/', $nonce)) {
                throw new AdminError('Motivo obrigatório (5 a 200 caracteres).');
            }
            $r = $this->a->app->ledger->post((int) $p['id'], $currency, $amount, 'admin', 'admin_adjust', 'admin:' . $this->a->s['id'], 'admin:' . $nonce);
            if (!$r['replayed']) {
                $this->a->audit('wallet_adjust', 'player', $uuid, ['currency' => $currency, 'amount' => $amount, 'balance_after' => $r['balance_after'], 'ledger_id' => $r['ledger_id'], 'note' => $note]);
            }
            return $r['replayed'] ? 'Este ajuste já tinha sido lançado (envio repetido ignorado).' : 'Ajuste lançado. Novo saldo de ' . $currency . ': ' . number_format($r['balance_after'], 0, ',', '.') . '.';
        });
    }

    private function rewardGrant(string $uuid): Response
    {
        return $this->a->act('players.support', 'players/' . $uuid, function (array $f) use ($uuid) {
            $p = $this->playerByUuid($uuid);
            $currency = (string) ($f['currency'] ?? '');
            $amount = filter_var($f['amount'] ?? '', FILTER_VALIDATE_INT);
            $days = ($f['days'] ?? '') === '' ? null : filter_var($f['days'], FILTER_VALIDATE_INT);
            $note = trim((string) ($f['note'] ?? ''));
            $nonce = (string) ($f['nonce'] ?? '');
            if (!in_array($currency, ['cash', 'gold'], true) || $amount === false || $amount < 1 || $amount > 100_000 || $days === false || ($days !== null && ($days < 1 || $days > 365))) {
                throw new AdminError('Informe moeda, quantidade (1 a 100.000) e validade (1 a 365 dias ou vazio).');
            }
            if (mb_strlen($note) < 5 || mb_strlen($note) > 200 || !preg_match('/^[a-f0-9]{16}$/', $nonce)) {
                throw new AdminError('Motivo obrigatório (5 a 200 caracteres).');
            }
            $r = $this->a->app->rewards->grant((int) $p['id'], 'support_grant', 'adm-' . $nonce, $currency, $amount, null, $days === null ? null : $days * 86400);
            if ($r['created']) {
                $this->a->audit('reward_grant', 'player', $uuid, ['currency' => $currency, 'amount' => $amount, 'days' => $days, 'reward_id' => $r['reward_id'], 'note' => $note]);
            }
            return $r['created'] ? 'Benefício concedido. O jogador resgata em Recompensas.' : 'Este benefício já tinha sido concedido (envio repetido ignorado).';
        });
    }

    private function revokeSessions(string $uuid): Response
    {
        return $this->a->act('players.support', 'players/' . $uuid, function () use ($uuid) {
            $p = $this->playerByUuid($uuid);
            $this->a->app->tokens->revokeAll((int) $p['id'], 'admin');
            $this->a->audit('player_sessions_revoked', 'player', $uuid);
            return 'Sessões encerradas.';
        });
    }

    private function playerExport(string $uuid): Response
    {
        try {
            $p = $this->playerByUuid($uuid);
        } catch (AdminError $e) {
            return $this->a->render('Jogador não encontrado', '', 'players', 404);
        }
        $data = $this->a->app->exporter->export((int) $p['id']);
        $this->a->audit('player_data_export', 'player', $uuid, ['sections' => array_keys($data)]);
        return new Response(200, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), [
            'Content-Type' => 'application/json; charset=utf-8',
            'Content-Disposition' => 'attachment; filename="terrabela-jogador-' . substr($uuid, 0, 8) . '.json"',
        ]);
    }

    // ------------------------------------------------------------------ sistema e backup

    private function system(): Response
    {
        $b = $this->a->app->backups;
        $list = $b->list();
        $db = $this->a->db;
        $sizes = $db->all('SELECT TABLE_NAME t, TABLE_ROWS r, ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024) kb FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC LIMIT 12');
        $body = '<div class="cols"><div class="card">' . View::dl([
                'Backups guardados' => count($list) . ' (mantém os ' . $this->a->app->config->int('BACKUP_KEEP', 14) . ' mais novos)',
                'Último backup' => $list === [] ? 'nenhum ainda' : View::dt($list[0]['created_at']),
                'Automático' => $this->a->app->config->bool('BACKUP_ENABLED', true) ? 'sim, 1 por dia pelo cron' : 'desligado (BACKUP_ENABLED=0)',
                'Criptografia' => $this->a->app->config->optional('BACKUP_ENCRYPTION_KEY') === null ? 'não (arquivo fica fora do public_html)' : 'AES-256-GCM',
                'PHP' => PHP_VERSION,
                'Banco' => $db->one('SELECT VERSION() v')['v'],
            ]) . $this->form('system/backup', '', 'inline', 'Fazer backup agora') . '</div>'
            . '<div class="card"><b>Restaurar</b><p class="muted">Restauração não é feita pela web (risco de apagar dados por engano). Procedimento em DEPLOY.md: baixe o arquivo por FTP de <code>terrabelafarm_app/storage/backups/</code>, importe no phpMyAdmin num banco vazio, confira e só então troque o DB_NAME do .env. Teste de restauração automatizado roda a cada versão (tests/run.php).</p></div></div>'
            . '<h2>Backups</h2>' . View::table($list, [
                'file' => 'Arquivo',
                'Tamanho' => fn ($r) => View::h(number_format($r['bytes'] / 1024, 1, ',', '.') . ' KB'),
                'Criado' => fn ($r) => View::dt($r['created_at']),
            ], 'Nenhum backup ainda.')
            . '<h2>Maiores tabelas</h2>' . View::table($sizes, ['t' => 'Tabela', 'r' => 'Linhas (aprox.)', 'kb' => 'KB']);
        return $this->a->render('Sistema e backup', $body, 'system');
    }

    private function backupNow(): Response
    {
        return $this->a->act('system.manage', 'system', function () {
            $r = $this->a->app->backups->create();
            $this->a->audit('backup_created', 'backup', $r['file'], ['rows' => $r['rows'], 'bytes' => $r['bytes'], 'sha256' => $r['sha256']]);
            return "Backup criado: {$r['file']} ({$r['tables']} tabelas, {$r['rows']} linhas, {$r['seconds']} s).";
        });
    }

    // ------------------------------------------------------------------ economia

    private function ledgerTable(array $rows, bool $withPlayer): string
    {
        $cols = [];
        if ($withPlayer) {
            $cols['Jogador'] = fn ($r) => $this->playerLink($r['public_id']);
        }
        return View::table($rows, $cols + [
            'Quando' => fn ($r) => View::dt($r['created_at']),
            'Moeda' => fn ($r) => View::h($r['currency']),
            'Valor' => fn ($r) => '<b>' . View::h(((int) $r['amount'] > 0 ? '+' : '') . number_format((int) $r['amount'], 0, ',', '.')) . '</b>',
            'Saldo depois' => fn ($r) => View::h(number_format((int) $r['balance_after'], 0, ',', '.')),
            'source' => 'Origem', 'reason' => 'Motivo', 'reference' => 'Referência',
        ], 'Nenhum lançamento.');
    }

    private function ledger(): Response
    {
        $currency = $this->q('currency');
        $source = $this->q('source');
        $reason = $this->q('reason');
        $page = $this->page();
        $where = [];
        $p = [];
        if (in_array($currency, ['cash', 'gold'], true)) {
            $where[] = 'l.currency = ?';
            $p[] = $currency;
        }
        if (in_array($source, ['client', 'iap', 'reward', 'admin', 'system'], true)) {
            $where[] = 'l.source = ?';
            $p[] = $source;
        }
        if ($reason !== '' && preg_match('/^[a-z0-9_]{1,40}$/', $reason)) {
            $where[] = 'l.reason = ?';
            $p[] = $reason;
        }
        $rows = $this->a->db->all(
            'SELECT l.*, pl.public_id FROM economy_ledger l JOIN players pl ON pl.id = l.player_id'
            . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . ' ORDER BY l.id DESC LIMIT ' . (self::PER_PAGE + 1) . ' OFFSET ' . (($page - 1) * self::PER_PAGE),
            $p
        );
        $more = count($rows) > self::PER_PAGE;
        $since = $this->a->clock->sql(-86400);
        $totals = $this->a->db->all(
            'SELECT currency, source, SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS credit, SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS debit, COUNT(*) AS n
               FROM economy_ledger WHERE created_at >= ? GROUP BY currency, source ORDER BY currency, source',
            [$since]
        );
        $body = '<h2>Últimas 24 horas por moeda e origem</h2>' . View::table($totals, [
                'currency' => 'Moeda', 'source' => 'Origem',
                'Créditos' => fn ($r) => View::h(number_format((int) $r['credit'], 0, ',', '.')),
                'Débitos' => fn ($r) => View::h(number_format((int) $r['debit'], 0, ',', '.')),
                'n' => 'Lançamentos',
            ], 'Sem lançamentos nas últimas 24 horas.')
            . '<h2>Lançamentos</h2><form class="row" method="get" action="' . $this->url('ledger') . '">'
            . '<label>Moeda' . View::select('currency', ['cash' => 'cash', 'gold' => 'ouro'], $currency, true) . '</label>'
            . '<label>Origem' . View::select('source', ['client' => 'cliente', 'iap' => 'compra', 'reward' => 'benefício', 'admin' => 'admin', 'system' => 'sistema'], $source, true) . '</label>'
            . '<label>Motivo<input name="reason" value="' . View::h($reason) . '" placeholder="ex.: harvest_sale"></label><button>Filtrar</button></form><br>'
            . $this->ledgerTable(array_slice($rows, 0, self::PER_PAGE), true)
            . View::pager(fn ($n) => $this->a->view->url('ledger', ['currency' => $currency, 'source' => $source, 'reason' => $reason, 'page' => $n]), $page, $more)
            . '<p class="muted">Limites de crédito do cliente (cash por operação/dia) vêm do Remote Config. Ouro nunca é creditado pelo cliente. Política: docs/ECONOMY_POLICY.md.</p>';
        return $this->a->render('Carteira e ledger', $body, 'ledger');
    }

    private function purchaseTable(array $rows, bool $withPlayer): string
    {
        $cols = ['Quando' => fn ($r) => View::dt($r['created_at'])];
        if ($withPlayer) {
            $cols['Jogador'] = fn ($r) => $this->playerLink($r['player_public']);
        }
        return View::table($rows, $cols + [
            'sku' => 'Produto',
            'Estado' => fn ($r) => self::stateBadge($r['state']),
            'Finalização' => fn ($r) => View::h($r['finalize_status'] . ($r['finalize_attempts'] > 0 ? ' (' . $r['finalize_attempts'] . ' tent.)' : '')),
            'order_id' => 'Pedido Google',
            'Concedida' => fn ($r) => View::dt($r['granted_at']),
            'Reembolso' => fn ($r) => $r['refunded_at'] === null ? '—' : View::h(View::dt($r['refunded_at']) . ' · descontado ' . (int) $r['refund_clawback'] . ((int) $r['refund_shortfall'] > 0 ? ' · faltou ' . (int) $r['refund_shortfall'] : '')),
        ], 'Nenhuma compra.');
    }

    private function purchases(): Response
    {
        $state = $this->q('state');
        $page = $this->page();
        $where = [];
        $p = [];
        if (in_array($state, ['pending', 'granted', 'canceled', 'refunded'], true)) {
            $where[] = 't.state = ?';
            $p[] = $state;
        }
        if ($this->q('shortfall') === '1') {
            $where[] = 't.refund_shortfall > 0';
        }
        $rows = $this->a->db->all(
            'SELECT t.*, pr.sku, pl.public_id AS player_public FROM iap_transactions t JOIN iap_products pr ON pr.id = t.product_id JOIN players pl ON pl.id = t.player_id'
            . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . ' ORDER BY t.id DESC LIMIT ' . (self::PER_PAGE + 1) . ' OFFSET ' . (($page - 1) * self::PER_PAGE),
            $p
        );
        $more = count($rows) > self::PER_PAGE;
        $summary = $this->a->db->all('SELECT state, COUNT(*) n FROM iap_transactions GROUP BY state');
        $body = '<div class="grid">';
        foreach ($summary as $s) {
            $body .= View::kpi($s['state'], (int) $s['n']);
        }
        $body .= '</div><br><form class="row" method="get" action="' . $this->url('purchases') . '">'
            . '<label>Estado' . View::select('state', ['pending' => 'pendente', 'granted' => 'concedida', 'canceled' => 'cancelada', 'refunded' => 'reembolsada'], $state, true) . '</label>'
            . '<label>Reembolso sem saldo' . View::select('shortfall', ['1' => 'só com falta de saldo'], $this->q('shortfall'), true) . '</label>'
            . '<button>Filtrar</button></form><br>'
            . $this->purchaseTable(array_slice($rows, 0, self::PER_PAGE), true)
            . View::pager(fn ($n) => $this->a->view->url('purchases', ['state' => $state, 'page' => $n]), $page, $more)
            . '<p class="muted">Reembolsos chegam pela notificação RTDN da Google. O benefício é descontado até o saldo disponível; o que faltar aparece como “faltou” para análise (o saldo nunca fica negativo).</p>';
        return $this->a->render('Compras e reembolsos', $body, 'purchases');
    }

    private function products(): Response
    {
        $rows = $this->a->db->all('SELECT * FROM iap_products ORDER BY sku, benefit_version DESC');
        $body = View::table($rows, [
            'sku' => 'SKU', 'product_type' => 'Tipo', 'benefit_version' => 'Versão',
            'Benefício' => fn ($r) => self::json($r['benefit']),
            'Ativo' => fn ($r) => (int) $r['active'] ? View::badge('ativo', 'ok') : View::badge('inativo'),
            'Criado' => fn ($r) => View::dt($r['created_at']),
            '' => fn ($r) => (int) $r['active'] && $this->a->can('products.manage') ? $this->form('products/' . $r['id'] . '/deactivate', '', 'inline', 'Desativar', 'ghost') : '',
        ], 'Nenhum produto cadastrado.');
        if ($this->a->can('products.manage')) {
            $body .= '<h2>Nova versão de produto</h2><div class="card"><p class="muted">O SKU precisa existir no Google Play Console. Cadastrar uma nova versão desativa as anteriores do mesmo SKU; compras antigas mantêm o benefício da versão em que foram feitas.</p>'
                . $this->form('products', '<label>SKU</label><input name="sku" required pattern="[a-z0-9_.]{1,100}" placeholder="gold_pack_small">'
                    . '<label>Tipo</label>' . View::select('product_type', ['consumable' => 'consumível (pode comprar de novo)', 'non_consumable' => 'não consumível (uma vez)'], 'consumable')
                    . '<label>Benefício (JSON)</label><textarea name="benefit" rows="3" required>{"currency":"gold","amount":100}</textarea>'
                    . '<p class="muted">Formatos aceitos: {"currency":"gold","amount":100} e/ou {"entitlements":["remove_ads"]}.</p>', 'stack', 'Cadastrar versão') . '</div>';
        }
        return $this->a->render('Produtos da loja', $body, 'products');
    }

    private function productAdd(): Response
    {
        return $this->a->act('products.manage', 'products', function (array $f) {
            $sku = trim((string) ($f['sku'] ?? ''));
            $type = (string) ($f['product_type'] ?? '');
            if (!preg_match('/^[a-z0-9_.]{1,100}$/', $sku) || !in_array($type, ['consumable', 'non_consumable'], true)) {
                throw new AdminError('SKU (a-z, 0-9, _ e .) e tipo obrigatórios.');
            }
            $benefit = json_decode((string) ($f['benefit'] ?? ''), true, 8, JSON_THROW_ON_ERROR);
            if (!is_array($benefit) || array_diff(array_keys($benefit), ['currency', 'amount', 'entitlements'])) {
                throw new AdminError('Benefício aceita só currency, amount e entitlements.');
            }
            $hasCurrency = isset($benefit['currency']) || isset($benefit['amount']);
            if ($hasCurrency && (!in_array($benefit['currency'] ?? null, ['cash', 'gold'], true) || !is_int($benefit['amount'] ?? null) || $benefit['amount'] < 1 || $benefit['amount'] > 10_000_000)) {
                throw new AdminError('currency deve ser cash ou gold e amount inteiro de 1 a 10.000.000.');
            }
            $ents = $benefit['entitlements'] ?? [];
            if (!is_array($ents) || !array_is_list($ents) || array_filter($ents, fn ($e) => !is_string($e) || !preg_match('/^[a-z0-9_.]{1,64}$/', $e))) {
                throw new AdminError('entitlements deve ser lista de chaves (a-z, 0-9, _ e .).');
            }
            if (!$hasCurrency && $ents === []) {
                throw new AdminError('O produto precisa dar moeda e/ou direito.');
            }
            $v = $this->a->db->tx(function ($db) use ($sku, $type, $benefit) {
                $row = $db->one("SELECT COALESCE(MAX(benefit_version), 0) AS v FROM iap_products WHERE platform = 'google_play' AND sku = ? FOR UPDATE", [$sku]);
                $db->exec("UPDATE iap_products SET active = 0 WHERE platform = 'google_play' AND sku = ?", [$sku]);
                $v = (int) $row['v'] + 1;
                $db->insert(
                    "INSERT INTO iap_products (platform, sku, product_type, benefit_version, benefit, active, created_at) VALUES ('google_play', ?, ?, ?, ?, 1, ?)",
                    [$sku, $type, $v, json_encode($benefit), $this->a->clock->sql()]
                );
                return $v;
            });
            $this->a->audit('product_version', 'product', $sku, ['version' => $v, 'type' => $type, 'benefit' => $benefit]);
            return "Produto $sku versão $v ativo.";
        });
    }

    private function productDeactivate(int $id): Response
    {
        return $this->a->act('products.manage', 'products', function () use ($id) {
            $p = $this->a->db->one('SELECT sku, benefit_version FROM iap_products WHERE id = ?', [$id]);
            if ($p === null) {
                throw new AdminError('Produto não encontrado.');
            }
            $this->a->db->exec('UPDATE iap_products SET active = 0 WHERE id = ?', [$id]);
            $this->a->audit('product_deactivate', 'product', $p['sku'], ['version' => (int) $p['benefit_version']]);
            return 'Produto desativado: novas compras deste SKU serão recusadas até cadastrar uma versão ativa.';
        });
    }

    // ------------------------------------------------------------------ Remote Config

    private function config(): Response
    {
        $env = $this->a->app->config->str('APP_ENV', 'production');
        $cur = $this->a->app->remoteConfig->current(null);
        $rows = $this->a->db->all('SELECT * FROM remote_config_versions WHERE environment = ? ORDER BY version_number DESC LIMIT 30', [$env]);
        $pretty = $cur === null ? "{}" : json_encode($cur['payload'], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $body = '<p>Ambiente <b>' . View::h($env) . '</b>. Versão em vigor: <b>v' . View::h($cur['version'] ?? '—') . '</b>. O app recebe a versão publicada mais nova compatível com a versão dele (ETag/checksum).</p>'
            . View::table($rows, [
                'version_number' => 'Versão',
                'Estado' => fn ($r) => self::stateBadge($r['status']),
                'Clientes' => fn ($r) => View::h($r['min_client_version'] . ' … ' . ($r['max_client_version'] ?? '∞')),
                'changelog' => 'Mudança', 'created_by' => 'Por',
                'Publicada' => fn ($r) => View::dt($r['published_at']),
                'Checksum' => fn ($r) => '<code>' . View::h(substr($r['checksum'], 0, 10)) . '</code>',
                '' => fn ($r) => $r['status'] === 'published' && $this->a->can('config.publish')
                    ? $this->form('config/retire', '<input type="hidden" name="version" value="' . (int) $r['version_number'] . '">', 'inline', 'Retirar (rollback)', 'ghost') : '',
            ]);
        if ($this->a->can('config.publish')) {
            $body .= '<h2>Publicar nova versão</h2><div class="card"><p class="muted">Validação no servidor: seções maintenance/features/economy/sync obrigatórias, ouro nunca creditável pelo cliente, sem segredos (o Remote Config é público). Para ligar manutenção, mude maintenance.enabled para true.</p>'
                . $this->form('config/publish', '<label>JSON</label><textarea name="payload" rows="22" required>' . View::h($pretty) . '</textarea>'
                    . '<label>Descrição da mudança</label><input name="changelog" required maxlength="500">'
                    . '<label>Versão mínima do app</label><input name="min_client" value="0.0.0" pattern="\d+\.\d+\.\d+">'
                    . '<label>Versão máxima do app (vazio = todas)</label><input name="max_client" pattern="\d+\.\d+\.\d+">', 'stack', 'Publicar') . '</div>';
        } else {
            $body .= '<h2>Conteúdo em vigor</h2><pre>' . View::h($pretty) . '</pre>';
        }
        return $this->a->render('Remote Config', $body, 'config');
    }

    private function configPublish(): Response
    {
        return $this->a->act('config.publish', 'config', function (array $f) {
            $payload = json_decode((string) ($f['payload'] ?? ''), true, 64, JSON_THROW_ON_ERROR);
            if (!is_array($payload)) {
                throw new AdminError('O JSON deve ser um objeto.');
            }
            $min = trim((string) ($f['min_client'] ?? '')) ?: '0.0.0';
            $max = trim((string) ($f['max_client'] ?? '')) ?: null;
            foreach (array_filter([$min, $max]) as $ver) {
                if (!preg_match('/^\d+\.\d+\.\d+$/', $ver)) {
                    throw new AdminError('Versões do app no formato 1.2.3.');
                }
            }
            $v = $this->a->app->remoteConfig->publish($payload, (string) ($f['changelog'] ?? ''), $this->a->adminLabel(), $min, $max);
            $this->a->audit('config_publish', 'config', 'v' . $v, ['checksum' => \TerraBela\Config\RemoteConfigService::checksum($payload), 'changelog' => mb_substr((string) $f['changelog'], 0, 200), 'maintenance' => $payload['maintenance']['enabled'] ?? null]);
            return "Versão $v publicada.";
        });
    }

    private function configRetire(): Response
    {
        return $this->a->act('config.publish', 'config', function (array $f) {
            $v = (int) ($f['version'] ?? 0);
            $published = (int) $this->a->db->one("SELECT COUNT(*) n FROM remote_config_versions WHERE environment = ? AND status = 'published'", [$this->a->app->config->str('APP_ENV', 'production')])['n'];
            if ($published <= 1) {
                throw new AdminError('Não é possível retirar a única versão publicada: publique a correção primeiro.');
            }
            $this->a->app->remoteConfig->retire($v);
            $this->a->audit('config_retire', 'config', 'v' . $v);
            return "Versão $v retirada. Agora vale a v" . ($this->a->app->remoteConfig->current(null)['version'] ?? '?') . '.';
        });
    }

    // ------------------------------------------------------------------ eventos

    private function events(): Response
    {
        $name = $this->q('name');
        $since = $this->a->clock->sql(-7 * 86400);
        $counts = $this->a->db->all('SELECT event_name, COUNT(*) n, COUNT(DISTINCT player_id) players FROM game_events WHERE occurred_at >= ? GROUP BY event_name ORDER BY n DESC LIMIT 60', [$since]);
        $p = [];
        $sql = 'SELECT e.*, pl.public_id FROM game_events e JOIN players pl ON pl.id = e.player_id';
        if ($name !== '' && preg_match('/^[a-z0-9_]{1,40}$/', $name)) {
            $sql .= ' WHERE e.event_name = ?';
            $p[] = $name;
        }
        $recent = $this->a->db->all($sql . ' ORDER BY e.id DESC LIMIT 100', $p);
        $body = '<h2>Últimos 7 dias</h2>' . View::table($counts, [
                'Evento' => fn ($r) => '<a href="' . $this->url('events', ['name' => $r['event_name']]) . '">' . View::h($r['event_name']) . '</a>',
                'n' => 'Ocorrências', 'players' => 'Jogadores',
            ], 'Nenhum evento recebido ainda (o jogo envia em lote por POST /events/batch).')
            . '<h2>Recentes' . ($name !== '' ? ': ' . View::h($name) : '') . '</h2>' . View::table($recent, [
                'Quando' => fn ($r) => View::dt($r['occurred_at']),
                'event_name' => 'Evento',
                'Jogador' => fn ($r) => $this->playerLink($r['public_id']),
                'app_version' => 'Versão',
                'Propriedades' => fn ($r) => self::json($r['properties']),
            ]);
        return $this->a->render('Eventos do jogo', $body, 'events');
    }

    // ------------------------------------------------------------------ campanhas

    private function campaignRow(): array
    {
        return [
            'Campanha' => fn ($r) => '<a href="' . $this->url('campaigns/' . $r['id']) . '">' . View::h($r['name']) . '</a>',
            'Tipo' => fn ($r) => View::h($r['category'] === 'promotional' ? 'promocional' : 'operacional'),
            'Estado' => fn ($r) => self::stateBadge($r['status']),
            'Agendada' => fn ($r) => View::dt($r['scheduled_at']),
            'Público' => fn ($r) => View::h($r['audience_count']),
            'Enviados' => fn ($r) => View::h($r['sent_count'] . ' / falhas ' . $r['failed_count'] . ' / pulados ' . $r['skipped_count']),
        ];
    }

    private function campaigns(): Response
    {
        $rows = $this->a->db->all('SELECT * FROM notification_campaigns ORDER BY id DESC LIMIT 100');
        $body = View::table($rows, $this->campaignRow(), 'Nenhuma campanha ainda.');
        if ($this->a->can('campaigns.manage')) {
            $routes = array_combine(CampaignService::ROUTES, CampaignService::ROUTES);
            $body .= '<h2>Nova campanha</h2><div class="card"><p class="muted">Promocional só vai para quem aceitou (opt-in) e no máximo ' . (int) $this->a->app->config->int('PUSH_PROMO_WEEKLY_CAP', 3) . ' por semana. Operacional vai para todos que não recusaram. A permissão do sistema do celular sempre é respeitada. Nunca coloque dados pessoais no texto.</p>'
                . $this->form('campaigns', '<label>Nome interno</label><input name="name" required maxlength="120">'
                    . '<label>Tipo</label>' . View::select('category', ['operational' => 'operacional (avisos do jogo, benefícios)', 'promotional' => 'promocional (ofertas)'], 'operational')
                    . '<label>Título (até 65)</label><input name="title" required maxlength="65">'
                    . '<label>Texto (até 240)</label><textarea name="body" rows="3" required maxlength="240"></textarea>'
                    . '<label>Abrir na tela</label>' . View::select('route', $routes, 'farm')
                    . '<label>Idioma (vazio = todos)</label>' . View::select('locale', ['pt_BR' => 'pt_BR', 'es' => 'es', 'en' => 'en'], null, true)
                    . '<label>Plataforma (vazio = todas)</label>' . View::select('platform', ['android' => 'Android', 'ios' => 'iOS'], null, true)
                    . '<label>Só quem está sem jogar há pelo menos N dias (vazio = todos)</label><input name="inactive_days_min" type="number" min="1" max="365">',
                    'stack', 'Criar rascunho') . '</div>';
        }
        return $this->a->render('Campanhas push', $body, 'campaigns');
    }

    private function campaignCreate(): Response
    {
        $id = null;
        $resp = $this->a->act('campaigns.manage', 'campaigns', function (array $f) use (&$id) {
            $id = $this->a->app->campaigns->create($f, (int) $this->a->s['id']);
            $c = $this->a->app->campaigns->get($id);
            $this->a->audit('campaign_create', 'campaign', $c['public_id'], ['name' => $c['name'], 'category' => $c['category']]);
            return 'Rascunho criado. Confira o público estimado e agende.';
        });
        return $id === null ? $resp : $this->a->redirect('campaigns/' . $id);
    }

    private function campaign(int $id): Response
    {
        try {
            $c = $this->a->app->campaigns->get($id);
        } catch (\InvalidArgumentException) {
            return $this->a->render('Campanha não encontrada', '', 'campaigns', 404);
        }
        $svc = $this->a->app->campaigns;
        $outbox = $this->a->db->all('SELECT status, COUNT(*) n FROM notification_outbox WHERE campaign_id = ? GROUP BY status', [$id]);
        $errors = $this->a->db->all("SELECT last_error, COUNT(*) n FROM notification_outbox WHERE campaign_id = ? AND last_error IS NOT NULL GROUP BY last_error ORDER BY n DESC LIMIT 10", [$id]);
        $opened = (int) $this->a->db->one('SELECT COUNT(*) n FROM notification_events WHERE campaign_id = ?', [$c['public_id']])['n'];
        $body = '<div class="cols"><div class="card">' . View::dl([
                'Id' => $c['public_id'], 'Tipo' => $c['category'], 'Estado' => $c['status'],
                'Título' => $c['title'], 'Texto' => $c['body'], 'Rota' => $c['route'],
                'Idioma' => $c['locale'] ?? 'todos', 'Plataforma' => $c['platform'] ?? 'todas',
                'Inativos há (dias)' => $c['inactive_days_min'] ?? 'qualquer',
                'Agendada (Brasília)' => View::dt($c['scheduled_at']), 'Expira' => View::dt($c['expires_at']),
                'Iniciada' => View::dt($c['started_at']), 'Concluída' => View::dt($c['completed_at']),
            ]) . '</div><div class="card">' . View::dl([
                'Público estimado agora' => in_array($c['status'], ['draft', 'scheduled'], true) ? $svc->estimate($id) . ' instalações' : '—',
                'Público congelado' => $c['audience_count'],
                'Aceitos pelo FCM' => $c['sent_count'] . ' (aceite não prova entrega)',
                'Falhas' => $c['failed_count'], 'Pulados' => $c['skipped_count'],
                'Aberturas' => $opened,
            ]);
        foreach ($outbox as $o) {
            $body .= View::badge($o['status'] . ': ' . $o['n']) . ' ';
        }
        $body .= '</div></div>';
        if ($errors) {
            $body .= '<h2>Erros</h2>' . View::table($errors, ['last_error' => 'Erro', 'n' => 'Qtd.']);
        }
        if ($this->a->can('campaigns.manage')) {
            $body .= '<h2>Ações</h2><div class="cols">';
            if ($c['status'] === 'draft') {
                $body .= '<div class="card"><b>Agendar</b>' . $this->form('campaigns/' . $id . '/schedule',
                    '<label>Quando (horário de Brasília)</label><input type="datetime-local" name="when" required value="' . gmdate('Y-m-d\TH:i', $this->a->clock->now() - 3 * 3600 + 600) . '">'
                    . '<label>Expira (opcional; depois disso não envia)</label><input type="datetime-local" name="expires">', 'stack', 'Agendar envio') . '</div>';
            }
            $body .= '<div class="card"><b>Envio de teste</b><p class="muted">Para um aparelho (id da instalação na tela do jogador). Não conta nos números.</p>'
                . $this->form('campaigns/' . $id . '/test', '<label>Instalação</label><input name="device" required pattern="[0-9a-f-]{36}">', 'stack', 'Enviar teste', 'ghost') . '</div>';
            if (in_array($c['status'], ['draft', 'scheduled', 'sending'], true)) {
                $body .= '<div class="card"><b>Cancelar</b><p class="muted">Pendências da fila são descartadas.</p>' . $this->form('campaigns/' . $id . '/cancel', '', 'stack', 'Cancelar campanha', 'danger') . '</div>';
            }
            $body .= '</div>';
        }
        return $this->a->render('Campanha: ' . $c['name'], $body, 'campaigns');
    }

    private function campaignAction(int $id, string $action): Response
    {
        return $this->a->act('campaigns.manage', 'campaigns/' . $id, function (array $f) use ($id, $action) {
            $svc = $this->a->app->campaigns;
            $c = $svc->get($id);
            switch ($action) {
                case 'schedule':
                    $when = self::localToUtc((string) ($f['when'] ?? ''));
                    $exp = self::localToUtc((string) ($f['expires'] ?? ''));
                    if ($when === null || $when < $this->a->clock->sql(-300)) {
                        throw new AdminError('Informe uma data/hora futura.');
                    }
                    if ($exp !== null && $exp <= $when) {
                        throw new AdminError('A expiração deve ser depois do envio.');
                    }
                    $svc->schedule($id, $when, $exp);
                    $this->a->audit('campaign_schedule', 'campaign', $c['public_id'], ['scheduled_at' => $when, 'expires_at' => $exp, 'estimate' => $svc->estimate($id)]);
                    return 'Campanha agendada. O cron envia no horário (a cada execução, em lotes).';
                case 'cancel':
                    $svc->cancel($id);
                    $this->a->audit('campaign_cancel', 'campaign', $c['public_id']);
                    return 'Campanha cancelada.';
                default:
                    $res = $svc->sendTest($id, strtolower(trim((string) ($f['device'] ?? ''))));
                    $this->a->audit('campaign_test', 'campaign', $c['public_id'], ['result' => $res['result']]);
                    if ($res['result'] !== 'sent') {
                        throw new AdminError('Teste não enviado: ' . $res['result'] . ' ' . ($res['error'] ?? ''));
                    }
                    return 'Teste aceito pelo FCM.';
            }
        });
    }

    // ------------------------------------------------------------------ regras

    private function rules(): Response
    {
        $rows = $this->a->db->all('SELECT * FROM reward_rules ORDER BY rule_key, version DESC LIMIT 200');
        $body = View::table($rows, [
            'Regra' => fn ($r) => '<a href="' . $this->url('rules/' . $r['id']) . '">' . View::h($r['rule_key'] . ' v' . $r['version']) . '</a>',
            'description' => 'Descrição',
            'Benefício' => fn ($r) => View::h(trim(($r['amount'] ?? '') . ' ' . ($r['currency'] ?? '') . ' ' . ($r['entitlement_key'] ?? ''))),
            'occurrence' => 'Frequência',
            'Estado' => fn ($r) => self::stateBadge($r['status']),
            'Última execução' => fn ($r) => View::dt($r['last_run_at']),
        ], 'Nenhuma regra ainda.');
        if ($this->a->can('rules.manage')) {
            $help = '';
            foreach (RuleEngine::CONDITION_TYPES as $k => $d) {
                $help .= '<li><code>' . View::h($k) . '</code>: ' . View::h($d) . '</li>';
            }
            $body .= '<h2>Nova regra (ou nova versão de uma existente)</h2><div class="card"><p class="muted">A versão nova nasce pausada e aposenta a anterior. Teste com “Simular” antes de ativar. Ativa, roda pelo cron no máximo 1 vez por hora; cada jogador recebe no máximo uma vez por ocorrência (uma vez, por dia, semana ou mês).</p>'
                . $this->form('rules', '<label>Chave</label><input name="rule_key" required pattern="[a-z][a-z0-9_]{2,47}" placeholder="welcome_back_7d">'
                    . '<label>Descrição</label><input name="description" required maxlength="200">'
                    . '<label>Condições (JSON, todas precisam valer)</label><textarea name="conditions" rows="4" required>[{"type":"inactive_days_gte","days":7}]</textarea>'
                    . '<ul class="muted">' . $help . '</ul>'
                    . '<label>Frequência</label>' . View::select('occurrence', ['once' => 'uma vez por jogador', 'day' => 'por dia', 'week' => 'por semana', 'month' => 'por mês'], 'once')
                    . '<label>Moeda</label>' . View::select('currency', ['cash' => 'cash', 'gold' => 'ouro'], 'cash', true)
                    . '<label>Quantidade</label><input name="amount" type="number" min="1" max="1000000">'
                    . '<label>Direito (opcional)</label><input name="entitlement_key" pattern="[a-z0-9_.]{1,64}">'
                    . '<label>Expira em horas (vazio = não expira)</label><input name="expires_hours" type="number" min="1" max="8760">'
                    . '<label>Máximo de jogadores por execução</label><input name="max_grants_per_run" type="number" min="1" max="100000" value="1000">'
                    . '<label>Avisar com a campanha operacional (id numérico, opcional)</label><input name="notify_campaign_id" type="number" min="1">',
                    'stack', 'Criar versão') . '</div>';
        }
        return $this->a->render('Regras de benefício', $body, 'rules');
    }

    private function ruleCreate(): Response
    {
        $id = null;
        $resp = $this->a->act('rules.manage', 'rules', function (array $f) use (&$id) {
            if (($f['notify_campaign_id'] ?? '') !== '') {
                $c = $this->a->db->one('SELECT category FROM notification_campaigns WHERE id = ?', [(int) $f['notify_campaign_id']]);
                if ($c === null || $c['category'] !== 'operational') {
                    throw new AdminError('O aviso precisa ser uma campanha operacional existente.');
                }
            }
            $id = $this->a->app->rules->createVersion($f, (int) $this->a->s['id']);
            $r = $this->a->db->one('SELECT rule_key, version, conditions FROM reward_rules WHERE id = ?', [$id]);
            $this->a->audit('rule_version', 'rule', $r['rule_key'], ['version' => (int) $r['version'], 'conditions' => json_decode($r['conditions'], true)]);
            return 'Versão criada (pausada). Simule e depois ative.';
        });
        return $id === null ? $resp : $this->a->redirect('rules/' . $id);
    }

    private function rule(int $id): Response
    {
        $r = $this->a->db->one('SELECT * FROM reward_rules WHERE id = ?', [$id]);
        if ($r === null) {
            return $this->a->render('Regra não encontrada', '', 'rules', 404);
        }
        $body = '<div class="card">' . View::dl([
                'Chave' => $r['rule_key'] . ' v' . $r['version'], 'Descrição' => $r['description'], 'Estado' => $r['status'],
                'Condições' => json_encode(json_decode($r['conditions'], true), JSON_UNESCAPED_UNICODE),
                'Frequência' => $r['occurrence'],
                'Benefício' => trim(($r['amount'] ?? '') . ' ' . ($r['currency'] ?? '') . ' ' . ($r['entitlement_key'] ?? '')),
                'Expira em (h)' => $r['expires_hours'] ?? 'não expira',
                'Máx. por execução' => $r['max_grants_per_run'],
                'Campanha de aviso' => $r['notify_campaign_id'] ?? '—',
                'Concedidos no total' => (int) $this->a->db->one('SELECT COUNT(*) n FROM reward_grants WHERE rule_key = ?', [$r['rule_key']])['n'],
            ]) . '</div>';
        if ($this->a->can('rules.manage') && $r['status'] !== 'retired') {
            $body .= '<h2>Ações</h2><div class="row">' . $this->form('rules/' . $id . '/dryrun', '', 'inline', 'Simular (não concede)', 'ghost') . ' ';
            $body .= $r['status'] === 'active'
                ? $this->form('rules/' . $id . '/pause', '', 'inline', 'Pausar', 'danger')
                : $this->form('rules/' . $id . '/activate', '', 'inline', 'Ativar');
            $body .= ' ' . $this->form('rules/' . $id . '/run', '', 'inline', 'Executar agora', 'ghost') . '</div>';
        }
        $body .= '<h2>Execuções</h2>' . View::table($this->a->db->all('SELECT * FROM rule_executions WHERE rule_id = ? ORDER BY id DESC LIMIT 50', [$id]), [
            'Quando' => fn ($x) => View::dt($x['started_at']),
            'Tipo' => fn ($x) => (int) $x['dry_run'] ? View::badge('simulação') : View::badge('real', 'ok'),
            'eligible_count' => 'Elegíveis', 'granted_count' => 'Concedidos',
        ], 'Ainda não executada.');
        return $this->a->render('Regra ' . $r['rule_key'], $body, 'rules');
    }

    private function ruleAction(int $id, string $action): Response
    {
        return $this->a->act('rules.manage', 'rules/' . $id, function () use ($id, $action) {
            $r = $this->a->db->one('SELECT rule_key, version, status FROM reward_rules WHERE id = ?', [$id]);
            if ($r === null || $r['status'] === 'retired') {
                throw new AdminError('Regra inexistente ou aposentada.');
            }
            $eng = $this->a->app->rules;
            if ($action === 'activate' || $action === 'pause') {
                $eng->setStatus($id, $action === 'activate' ? 'active' : 'paused');
                $this->a->audit('rule_' . $action, 'rule', $r['rule_key'], ['version' => (int) $r['version']]);
                return $action === 'activate' ? 'Regra ativa: o cron executa no máximo 1 vez por hora.' : 'Regra pausada.';
            }
            $res = $eng->run($id, $action === 'dryrun');
            $this->a->audit($action === 'dryrun' ? 'rule_dry_run' : 'rule_run', 'rule', $r['rule_key'], $res + ['version' => (int) $r['version']]);
            return $action === 'dryrun' ? "Simulação: {$res['eligible']} jogadores elegíveis agora (nada foi concedido)." : "Executada: {$res['granted']} benefícios concedidos de {$res['eligible']} elegíveis.";
        });
    }

    // ------------------------------------------------------------------ testes A/B

    private function experiments(): Response
    {
        $rows = $this->a->db->all('SELECT e.*, (SELECT COUNT(*) FROM experiment_assignments a WHERE a.experiment_id = e.id) exposed FROM experiments e ORDER BY e.id DESC LIMIT 200');
        $body = View::table($rows, [
            'Experimento' => fn ($r) => '<a href="' . $this->url('experiments/' . $r['id']) . '">' . View::h($r['experiment_key']) . '</a>',
            'name' => 'Nome',
            'Variantes' => fn ($r) => View::h(implode(' / ', array_map(static fn ($v) => $v['key'] . ' ' . $v['weight'], json_decode($r['variants'], true)))),
            'Tráfego' => fn ($r) => View::h($r['traffic_percent'] . '%'),
            'exposed' => 'Expostos',
            'Estado' => fn ($r) => self::stateBadge($r['status'] === 'running' ? 'active' : $r['status']),
            'Início' => fn ($r) => View::dt($r['started_at']),
        ], 'Nenhum teste A/B ainda.');
        if ($this->a->can('experiments.manage')) {
            $sample = '[{"key":"control","weight":50,"overrides":{}},{"key":"b","weight":50,"overrides":{"features":{"store_enabled":true}}}]';
            $body .= '<h2>Novo teste A/B</h2><div class="card"><p class="muted">Nasce como rascunho. Cada variante só pode mudar <code>features</code>, <code>routes</code> e <code>tuning</code> do Remote Config; limites de economia, manutenção e sync nunca entram em teste. A divisão é fixa por jogador: quem recebeu uma variante continua nela até o fim. Ao encerrar, todos voltam ao Remote Config publicado; para adotar a vencedora, publique uma nova versão do Remote Config.</p>'
                . $this->form('experiments', '<label>Chave (usada pelo app)</label><input name="experiment_key" required pattern="[a-z][a-z0-9_]{2,47}" placeholder="loja_aberta_v1">'
                    . '<label>Nome</label><input name="name" required maxlength="120">'
                    . '<label>Hipótese e métrica de sucesso</label><input name="hypothesis" maxlength="500" placeholder="Abrir a loja aumenta compradores sem cair a retenção D1">'
                    . '<label>Percentual de jogadores no teste</label><input name="traffic_percent" type="number" min="1" max="100" value="100">'
                    . '<label>Evento de meta (opcional, nome do evento de telemetria)</label><input name="goal_event" pattern="[a-z][a-z0-9_]{1,39}" placeholder="shop_open">'
                    . '<label>Versão mínima do app</label><input name="min_client_version" value="0.0.0" pattern="\\d+(\\.\\d+){0,3}">'
                    . '<label>Variantes (JSON: key, weight, overrides)</label><textarea name="variants" rows="5" required>' . View::h($sample) . '</textarea>',
                    'stack', 'Criar rascunho') . '</div>';
        }
        return $this->a->render('Testes A/B', $body, 'experiments');
    }

    private function experimentCreate(): Response
    {
        $id = null;
        $resp = $this->a->act('experiments.manage', 'experiments', function (array $f) use (&$id) {
            $id = $this->a->app->experiments->create($f, (int) $this->a->s['id']);
            $e = $this->a->app->experiments->get($id);
            $this->a->audit('experiment_create', 'experiment', $e['experiment_key'], ['traffic_percent' => (int) $e['traffic_percent'], 'variants' => json_decode($e['variants'], true)]);
            return 'Rascunho criado. Confira as variantes e inicie.';
        });
        return $id === null ? $resp : $this->a->redirect('experiments/' . $id);
    }

    private function experiment(int $id): Response
    {
        $e = $this->a->db->one('SELECT * FROM experiments WHERE id = ?', [$id]);
        if ($e === null) {
            return $this->a->render('Teste não encontrado', '', 'experiments', 404);
        }
        $variants = json_decode($e['variants'], true);
        $body = '<div class="card">' . View::dl([
                'Chave' => $e['experiment_key'], 'Nome' => $e['name'], 'Hipótese' => $e['hypothesis'] ?? '—', 'Estado' => $e['status'],
                'Tráfego' => $e['traffic_percent'] . '%', 'Evento de meta' => $e['goal_event'] ?? '—', 'Versão mínima do app' => $e['min_client_version'],
                'Início' => View::dt($e['started_at']), 'Fim' => View::dt($e['stopped_at']), 'Vencedora' => $e['winner_variant'] ?? '—',
            ]) . '</div><h2>Variantes</h2>' . View::table($variants, [
                'key' => 'Variante', 'weight' => 'Peso',
                'Sobrescreve' => fn ($v) => '<code>' . View::h(json_encode($v['overrides'] ?: new \stdClass(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)) . '</code>',
            ]);
        $pct = static fn ($v) => $v === null ? '—' : number_format((float) $v, 1, ',', '.') . '%';
        $res = $this->a->app->experiments->results($id);
        $body .= '<h2>Resultados</h2><p class="muted">D1 e D7: jogou de novo entre 24 e 48 h (ou entre 7 e 8 dias) depois da primeira exposição, contando só quem já completou essa janela. Compradores: compra concedida depois da exposição. Diferenças pequenas com poucos jogadores não são conclusivas; espere algumas centenas por variante.</p>'
            . View::table($res, [
                'variant' => 'Variante', 'exposed' => 'Expostos',
                'Retenção D1' => fn ($r) => View::h($pct($r['d1_pct']) . ' de ' . $r['d1_base']),
                'Retenção D7' => fn ($r) => View::h($pct($r['d7_pct']) . ' de ' . $r['d7_base']),
                'Compradores' => fn ($r) => View::h($r['buyers'] . ' (' . $pct($r['buyers_pct']) . ')'),
                'Meta' => fn ($r) => View::h($r['converted'] === null ? '—' : $r['converted'] . ' (' . $pct($r['converted_pct']) . ')'),
            ]);
        if ($this->a->can('experiments.manage')) {
            if ($e['status'] === 'draft') {
                $body .= '<h2>Ações</h2>' . $this->form('experiments/' . $id . '/start', '', 'inline', 'Iniciar teste');
            } elseif ($e['status'] === 'running') {
                $opts = [];
                foreach ($variants as $v) {
                    $opts[$v['key']] = $v['key'];
                }
                $body .= '<h2>Encerrar</h2><div class="card"><p class="muted">Todos voltam ao Remote Config publicado. Registre a vencedora (opcional) e publique uma nova versão do Remote Config para adotá-la.</p>'
                    . $this->form('experiments/' . $id . '/stop', '<label>Vencedora</label>' . View::select('winner', $opts, null, true), 'stack', 'Encerrar teste', 'danger') . '</div>';
            }
        }
        return $this->a->render('Teste A/B ' . $e['experiment_key'], $body, 'experiments');
    }

    private function experimentAction(int $id, string $action): Response
    {
        return $this->a->act('experiments.manage', 'experiments/' . $id, function (array $f) use ($id, $action) {
            $svc = $this->a->app->experiments;
            $e = $svc->get($id);
            if ($action === 'start') {
                $svc->start($id);
                $this->a->audit('experiment_start', 'experiment', $e['experiment_key'], []);
                return 'Teste iniciado: o app recebe as variantes em /experiments.';
            }
            $winner = ($f['winner'] ?? '') === '' ? null : (string) $f['winner'];
            $svc->stop($id, $winner);
            $this->a->audit('experiment_stop', 'experiment', $e['experiment_key'], ['winner' => $winner]);
            return 'Teste encerrado.' . ($winner === null ? '' : " Vencedora: $winner. Publique o Remote Config para adotá-la.");
        });
    }

    // ------------------------------------------------------------------ calendário

    private function calendar(): Response
    {
        $now = $this->a->clock->sql();
        $upcoming = $this->a->db->all("SELECT * FROM notification_campaigns WHERE status IN ('scheduled','sending') ORDER BY COALESCE(scheduled_at, started_at) LIMIT 100");
        $recent = $this->a->db->all("SELECT * FROM notification_campaigns WHERE status IN ('completed','canceled') AND completed_at >= ? ORDER BY completed_at DESC LIMIT 30", [$this->a->clock->sql(-14 * 86400)]);
        $rules = $this->a->db->all("SELECT * FROM reward_rules WHERE status = 'active' ORDER BY rule_key");
        $days = [];
        foreach ($upcoming as $c) {
            $days[substr(View::dt($c['scheduled_at'] ?? $c['started_at']), 0, 10)][] = $c;
        }
        $body = '<h2>Próximos envios</h2>';
        if ($days === []) {
            $body .= '<p class="muted">Nada agendado.</p>';
        }
        foreach ($days as $d => $list) {
            $body .= '<h3>' . View::h($d) . '</h3>' . View::table($list, $this->campaignRow());
        }
        $body .= '<h2>Regras ativas (rodam a cada hora)</h2>' . View::table($rules, [
                'Regra' => fn ($r) => '<a href="' . $this->url('rules/' . $r['id']) . '">' . View::h($r['rule_key'] . ' v' . $r['version']) . '</a>',
                'description' => 'Descrição', 'occurrence' => 'Frequência',
                'Última execução' => fn ($r) => View::dt($r['last_run_at']),
            ], 'Nenhuma regra ativa.')
            . '<h2>Concluídas nos últimos 14 dias</h2>' . View::table($recent, $this->campaignRow(), 'Nenhuma.')
            . '<p class="muted">Horários em Brasília. Agora: ' . View::h(View::dt($now)) . '.</p>';
        return $this->a->render('Calendário LiveOps', $body, 'calendar');
    }

    // ------------------------------------------------------------------ auditoria e usuários

    private function auditTable(array $rows): string
    {
        return View::table($rows, [
            'Quando' => fn ($r) => View::dt($r['created_at']),
            'Quem' => fn ($r) => View::h($r['display_name'] ?? 'sistema/anônimo'),
            'action' => 'Ação',
            'Alvo' => fn ($r) => $r['target_type'] === 'player' && $r['target_id'] !== null
                ? '<a href="' . $this->url('players/' . $r['target_id']) . '">jogador ' . View::h(substr($r['target_id'], 0, 8)) . '</a>'
                : View::h(trim(($r['target_type'] ?? '') . ' ' . ($r['target_id'] ?? ''))),
            'Detalhes' => fn ($r) => self::json($r['details']),
        ], 'Nada registrado.');
    }

    private function audit(): Response
    {
        $action = $this->q('action');
        $admin = $this->q('admin');
        $page = $this->page();
        $where = [];
        $p = [];
        if ($action !== '' && preg_match('/^[a-z_]{1,48}$/', $action)) {
            $where[] = 'l.action = ?';
            $p[] = $action;
        }
        if ($admin !== '' && ctype_digit($admin)) {
            $where[] = 'l.admin_id = ?';
            $p[] = (int) $admin;
        }
        $rows = $this->a->db->all(
            'SELECT l.*, u.display_name FROM admin_audit_log l LEFT JOIN admin_users u ON u.id = l.admin_id'
            . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . ' ORDER BY l.id DESC LIMIT ' . (self::PER_PAGE + 1) . ' OFFSET ' . (($page - 1) * self::PER_PAGE),
            $p
        );
        $actions = array_column($this->a->db->all('SELECT DISTINCT action FROM admin_audit_log ORDER BY action'), 'action');
        $users = [];
        foreach ($this->a->db->all('SELECT id, display_name FROM admin_users ORDER BY display_name') as $u) {
            $users[$u['id']] = $u['display_name'];
        }
        $body = '<form class="row" method="get" action="' . $this->url('audit') . '">'
            . '<label>Ação' . View::select('action', array_combine($actions, $actions) ?: [], $action, true) . '</label>'
            . '<label>Operador' . View::select('admin', $users, $admin, true) . '</label><button>Filtrar</button></form><br>'
            . $this->auditTable(array_slice($rows, 0, self::PER_PAGE))
            . View::pager(fn ($n) => $this->a->view->url('audit', ['action' => $action, 'admin' => $admin, 'page' => $n]), $page, count($rows) > self::PER_PAGE);
        return $this->a->render('Auditoria', $body, 'audit');
    }

    private function users(?string $link = null, ?string $linkFor = null): Response
    {
        $rows = $this->a->db->all('SELECT * FROM admin_users ORDER BY id');
        $me = (int) $this->a->s['id'];
        $body = '';
        if ($link !== null) {
            $body .= '<div class="flash secret"><b>Link de configuração para ' . View::h($linkFor) . '</b> (válido por 72 h, uso único; aparece só agora, entregue por um canal privado):<br><code>' . View::h($link) . '</code></div>';
        }
        $body .= View::table($rows, [
            'display_name' => 'Nome', 'email' => 'E-mail',
            'Papel' => fn ($r) => View::h(Rbac::ROLES[$r['role']] ?? $r['role']),
            'Estado' => fn ($r) => self::stateBadge($r['status']) . ($r['password_hash'] === null ? ' ' . View::badge('aguardando senha', 'warn') : ''),
            '2FA' => fn ($r) => (int) $r['totp_enabled'] ? View::badge('ativo', 'ok') : View::badge('não'),
            'Último login' => fn ($r) => View::dt($r['last_login_at']),
            '' => fn ($r) => (int) $r['id'] === $me ? '<span class="muted">você</span>'
                : ($r['status'] === 'active' ? $this->form('users/' . $r['id'] . '/disable', '', 'inline', 'Desativar', 'danger') : $this->form('users/' . $r['id'] . '/enable', '', 'inline', 'Reativar', 'ghost'))
                    . ' ' . $this->form('users/' . $r['id'] . '/reset', '', 'inline', 'Novo link de senha', 'ghost'),
        ]);
        $body .= '<h2>Novo operador</h2><div class="card"><p class="muted">O usuário define a própria senha pelo link gerado (a senha nunca passa por você).</p>'
            . $this->form('users', '<label>Nome</label><input name="display_name" required maxlength="80"><label>E-mail</label><input name="email" type="email" required>'
                . '<label>Papel</label>' . View::select('role', Rbac::ROLES, 'read'), 'stack', 'Criar e gerar link') . '</div>';
        return $this->a->render('Usuários do backoffice', $body, 'users');
    }

    private function userCreate(): Response
    {
        $f = $this->a->req->form();
        try {
            $r = $this->a->auth->createUser((string) ($f['email'] ?? ''), (string) ($f['display_name'] ?? ''), (string) ($f['role'] ?? ''));
        } catch (AdminError $e) {
            $this->a->setFlash('error', $e->getMessage());
            return $this->a->redirect('users');
        }
        $this->a->audit('admin_user_create', 'admin_user', (string) $r['id'], ['email' => strtolower(trim((string) $f['email'])), 'role' => $f['role']]);
        return $this->users($this->a->setupLink($r['token']), strtolower(trim((string) $f['email'])));
    }

    private function userAction(int $id, string $action): Response
    {
        $u = $this->a->db->one('SELECT id, email FROM admin_users WHERE id = ?', [$id]);
        if ($u === null || $id === (int) $this->a->s['id']) {
            $this->a->setFlash('error', 'Não é possível alterar este usuário (você não pode desativar a si mesmo).');
            return $this->a->redirect('users');
        }
        if ($action === 'reset') {
            $token = $this->a->auth->resetSetup($id);
            $this->a->audit('admin_user_reset', 'admin_user', (string) $id);
            return $this->users($this->a->setupLink($token), $u['email']);
        }
        if ($action === 'disable') {
            $admins = (int) $this->a->db->one("SELECT COUNT(*) n FROM admin_users WHERE role = 'admin' AND status = 'active' AND id <> ?", [$id])['n'];
            if ($admins === 0) {
                $this->a->setFlash('error', 'Precisa sobrar pelo menos um administrador ativo.');
                return $this->a->redirect('users');
            }
        }
        $this->a->auth->setStatus($id, $action === 'disable' ? 'disabled' : 'active');
        $this->a->audit('admin_user_' . $action, 'admin_user', (string) $id);
        $this->a->setFlash('ok', $action === 'disable' ? 'Usuário desativado e sessões encerradas.' : 'Usuário reativado.');
        return $this->a->redirect('users');
    }

    // ------------------------------------------------------------------ minha conta

    private function account(?string $pendingSecret = null): Response
    {
        $s = $this->a->s;
        $body = '<div class="card">' . View::dl(['Nome' => $s['display_name'], 'E-mail' => $s['email'], 'Papel' => Rbac::ROLES[$s['role']] ?? $s['role'], 'Verificação em duas etapas' => (int) $s['totp_enabled'] ? 'ativa' : 'desligada']) . '</div>'
            . '<div class="cols"><div class="card"><h2>Trocar senha</h2>' . $this->form('account/password',
                '<input type="text" name="username" value="' . View::h($s['email']) . '" autocomplete="username" hidden>'
                . '<label>Senha atual</label><input type="password" name="current" autocomplete="current-password" required>'
                . '<label>Nova senha (mín. ' . AdminAuth::MIN_PASSWORD . ')</label><input type="password" name="password" minlength="' . AdminAuth::MIN_PASSWORD . '" autocomplete="new-password" required>'
                . '<label>Repita</label><input type="password" name="confirm" autocomplete="new-password" required>', 'stack', 'Trocar senha') . '</div>'
            . '<div class="card"><h2>Verificação em duas etapas (TOTP)</h2>';
        if ($pendingSecret !== null) {
            $body .= '<p>No aplicativo autenticador (Google Authenticator, Microsoft Authenticator, Authy, 1Password), escolha <b>inserir chave de configuração</b> e informe:</p>'
                . '<div class="flash secret"><code>' . View::h(trim(chunk_split($pendingSecret, 4, ' '))) . '</code><br><small>Conta: ' . View::h($s['email']) . ' · baseado em tempo</small></div>'
                . '<p class="muted">URI para gerenciadores que aceitam colar: <code>' . View::h(Totp::uri($pendingSecret, $s['email'])) . '</code></p>'
                . $this->form('account/totp-confirm', '<label>Código de 6 dígitos que apareceu no app</label><input name="code" inputmode="numeric" required>', 'stack', 'Confirmar e ativar');
        } elseif ((int) $s['totp_enabled']) {
            $body .= '<p>Ativa. Cada login pede o código do aplicativo.</p>' . $this->form('account/totp-disable', '<label>Senha para desligar</label><input type="password" name="password" required>', 'stack', 'Desligar 2FA', 'danger');
        } else {
            $body .= '<p class="muted">Recomendado para todos os operadores, obrigatório na prática para administradores.</p>' . $this->form('account/totp-start', '', 'stack', 'Configurar 2FA');
        }
        $body .= '</div></div>';
        return $this->a->render('Minha conta', $body, 'account');
    }

    private function accountAction(string $action): Response
    {
        $f = $this->a->req->form();
        $s = $this->a->s;
        try {
            switch ($action) {
                case 'password':
                    $this->a->auth->changePassword($s, (string) ($f['current'] ?? ''), (string) ($f['password'] ?? ''), (string) ($f['confirm'] ?? ''));
                    $this->a->audit('password_changed', 'admin_user', (string) $s['id']);
                    $this->a->setFlash('ok', 'Senha trocada. Outras sessões foram encerradas.');
                    break;
                case 'totp-start':
                    $secret = $this->a->auth->totpStart($s);
                    $this->a->audit('totp_setup_started', 'admin_user', (string) $s['id']);
                    $this->a->s['totp_enabled'] = 0;
                    return $this->account($secret);
                case 'totp-confirm':
                    $this->a->auth->totpConfirm($s, (string) ($f['code'] ?? ''));
                    $this->a->audit('totp_enabled', 'admin_user', (string) $s['id']);
                    $this->a->setFlash('ok', '2FA ativado. Os próximos logins vão pedir o código.');
                    break;
                default:
                    $this->a->auth->totpDisable($s, (string) ($f['password'] ?? ''));
                    $this->a->audit('totp_disabled', 'admin_user', (string) $s['id']);
                    $this->a->setFlash('ok', '2FA desligado.');
            }
        } catch (AdminError $e) {
            $this->a->audit('account_action_failed', 'admin_user', (string) $s['id'], ['action' => $action]);
            $this->a->setFlash('error', $e->getMessage());
        }
        return $this->a->redirect('account');
    }
}
