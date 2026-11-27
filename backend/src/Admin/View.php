<?php
declare(strict_types=1);

namespace TerraBela\Admin;

/** HTML do backoffice gerado no servidor: tudo escapado por h(); CSS próprio com nonce (sem CDN, sem JS). */
final class View
{
    public const NAV = [
        '' => ['Painel', 'view'],
        'players' => ['Jogadores', 'view'],
        'ledger' => ['Carteira / ledger', 'view'],
        'purchases' => ['Compras', 'view'],
        'products' => ['Produtos', 'view'],
        'config' => ['Remote Config', 'view'],
        'events' => ['Eventos', 'view'],
        'campaigns' => ['Campanhas push', 'view'],
        'rules' => ['Regras de benefício', 'view'],
        'calendar' => ['Calendário', 'view'],
        'audit' => ['Auditoria', 'audit.view'],
        'users' => ['Usuários', 'users.manage'],
        'system' => ['Sistema e backup', 'system.manage'],
    ];

    public function __construct(public readonly string $base, public readonly string $nonce)
    {
    }

    public static function h(mixed $v): string
    {
        return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    public function url(string $path = '', array $query = []): string
    {
        $u = $this->base . '/admin' . ($path === '' ? '/' : '/' . ltrim($path, '/'));
        return $query ? $u . '?' . http_build_query($query) : $u;
    }

    /** @param array<string,mixed>|null $s sessão */
    public function page(string $title, string $body, ?array $s, string $active = '', ?array $flash = null): string
    {
        $h = [self::class, 'h'];
        $nav = '';
        if ($s !== null && (int) $s['mfa_passed'] === 1) {
            $nav .= '<nav><div class="brand">TerraBela Farm<small>Backoffice</small></div><ul>';
            foreach (self::NAV as $path => [$label, $perm]) {
                if (Rbac::can($s['role'], $perm)) {
                    $nav .= '<li' . ($path === $active ? ' class="on"' : '') . '><a href="' . $h($this->url($path)) . '">' . $h($label) . '</a></li>';
                }
            }
            $nav .= '</ul><div class="me"><a href="' . $h($this->url('account')) . '">' . $h($s['display_name']) . '</a><span>' . $h(Rbac::ROLES[$s['role']] ?? $s['role']) . '</span>'
                . '<form method="post" action="' . $h($this->url('logout')) . '">' . $this->csrf($s) . '<button class="link">Sair</button></form></div></nav>';
        }
        $msg = '';
        if ($flash !== null) {
            $msg = '<div class="flash ' . $h($flash['type']) . '">' . $h($flash['text']) . '</div>';
        }
        return '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
            . '<meta name="robots" content="noindex,nofollow"><title>' . $h($title) . ' · TerraBela Backoffice</title>'
            . '<style nonce="' . $h($this->nonce) . '">' . self::CSS . '</style></head><body class="' . ($nav === '' ? 'bare' : '') . '">'
            . $nav . '<main><h1>' . $h($title) . '</h1>' . $msg . $body . '</main></body></html>';
    }

    public function csrf(?array $s): string
    {
        return $s === null ? '' : '<input type="hidden" name="_csrf" value="' . self::h($s['csrf_token']) . '">';
    }

    /** @param list<array<string,mixed>> $rows @param array<string,string|callable> $cols chave => rótulo, ou rótulo => fn(row): string HTML */
    public static function table(array $rows, array $cols, string $empty = 'Nada por aqui ainda.'): string
    {
        if ($rows === []) {
            return '<p class="muted">' . self::h($empty) . '</p>';
        }
        $out = '<div class="scroll"><table><thead><tr>';
        foreach ($cols as $k => $c) {
            $out .= '<th>' . self::h(is_callable($c) ? $k : $c) . '</th>';
        }
        $out .= '</tr></thead><tbody>';
        foreach ($rows as $r) {
            $out .= '<tr>';
            foreach ($cols as $k => $c) {
                $out .= '<td>' . (is_callable($c) ? $c($r) : self::h($r[$k] ?? '')) . '</td>';
            }
            $out .= '</tr>';
        }
        return $out . '</tbody></table></div>';
    }

    /** @param array<string,mixed> $kv */
    public static function dl(array $kv): string
    {
        $out = '<dl>';
        foreach ($kv as $k => $v) {
            $out .= '<dt>' . self::h($k) . '</dt><dd>' . self::h($v ?? '—') . '</dd>';
        }
        return $out . '</dl>';
    }

    public static function kpi(string $label, int|float|string $value, string $hint = ''): string
    {
        return '<div class="kpi"><span>' . self::h($label) . '</span><b>' . self::h(is_int($value) ? number_format($value, 0, ',', '.') : $value) . '</b>'
            . ($hint === '' ? '' : '<small>' . self::h($hint) . '</small>') . '</div>';
    }

    public static function badge(string $text, string $kind = ''): string
    {
        return '<span class="badge ' . self::h($kind) . '">' . self::h($text) . '</span>';
    }

    /** Gráfico de barras SVG no servidor (sem JS). @param array<string,int> $series data => valor */
    public static function bars(array $series, string $label): string
    {
        $w = 600;
        $hgt = 140;
        $n = max(1, count($series));
        $max = max(1, ...array_values($series ?: [0]));
        $bw = $w / $n;
        $svg = '<figure class="chart"><figcaption>' . self::h($label) . ' <small>(máx. ' . self::h(number_format($max, 0, ',', '.')) . ')</small></figcaption>'
            . '<svg viewBox="0 0 ' . $w . ' ' . ($hgt + 18) . '" role="img" aria-label="' . self::h($label) . '">';
        $i = 0;
        foreach ($series as $date => $v) {
            $bh = $v === 0 ? 0 : max(2, (int) round($hgt * $v / $max));
            $x = round($i * $bw + 1, 1);
            $svg .= '<rect x="' . $x . '" y="' . ($hgt - $bh) . '" width="' . round(max(1, $bw - 2), 1) . '" height="' . $bh . '" class="bar"><title>'
                . self::h($date . ': ' . $v) . '</title></rect>';
            if ($i === 0 || $i === $n - 1 || $i === intdiv($n, 2)) {
                $svg .= '<text x="' . $x . '" y="' . ($hgt + 14) . '" class="axis">' . self::h(substr((string) $date, 5)) . '</text>';
            }
            $i++;
        }
        return $svg . '<line x1="0" y1="' . $hgt . '" x2="' . $w . '" y2="' . $hgt . '" class="base"/></svg></figure>';
    }

    public static function pager(callable $url, int $page, bool $hasNext): string
    {
        $out = '<div class="pager">';
        if ($page > 1) {
            $out .= '<a href="' . self::h($url($page - 1)) . '">← Anterior</a>';
        }
        $out .= '<span>Página ' . $page . '</span>';
        if ($hasNext) {
            $out .= '<a href="' . self::h($url($page + 1)) . '">Próxima →</a>';
        }
        return $out . '</div>';
    }

    public static function select(string $name, array $options, ?string $selected, bool $blank = false): string
    {
        $out = '<select name="' . self::h($name) . '">' . ($blank ? '<option value="">—</option>' : '');
        foreach ($options as $v => $label) {
            $out .= '<option value="' . self::h($v) . '"' . ((string) $v === (string) $selected ? ' selected' : '') . '>' . self::h($label) . '</option>';
        }
        return $out . '</select>';
    }

    /** Datas UTC do banco exibidas no horário de Brasília (UTC-3, sem horário de verão desde 2019). */
    public static function dt(?string $utc): string
    {
        if ($utc === null || $utc === '') {
            return '—';
        }
        return gmdate('d/m/Y H:i', (int) strtotime($utc . ' UTC') - 3 * 3600);
    }

    private const CSS = <<<'CSS'
:root{--bg:#f6f4ee;--panel:#fff;--ink:#22301f;--muted:#6b7566;--line:#e2ddd0;--brand:#3f7d32;--brand-ink:#fff;--warn:#b3541e;--bad:#b42318;--ok:#2f7d32;--soft:#eef5ea}
@media (prefers-color-scheme:dark){:root{--bg:#141a13;--panel:#1d241b;--ink:#e7eee3;--muted:#9aa695;--line:#2f3a2c;--brand:#6fb35d;--brand-ink:#0d130c;--soft:#22301f}}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--ink);display:flex;min-height:100vh}
body.bare{justify-content:center;align-items:flex-start;padding-top:8vh}body.bare main{max-width:420px;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:28px}
nav{width:220px;flex:none;background:var(--panel);border-right:1px solid var(--line);padding:16px 0;display:flex;flex-direction:column}
.brand{font-weight:700;padding:0 18px 14px;color:var(--brand)}.brand small{display:block;color:var(--muted);font-weight:400}
nav ul{list-style:none;margin:0;padding:0;flex:1}nav li a{display:block;padding:7px 18px;color:var(--ink);text-decoration:none}nav li.on a,nav li a:hover{background:var(--soft);color:var(--brand)}
.me{padding:12px 18px;border-top:1px solid var(--line);display:flex;flex-direction:column;gap:2px}.me span{color:var(--muted);font-size:12px}
main{flex:1;min-width:0;padding:22px 28px;max-width:1200px}h1{font-size:22px;margin:0 0 16px}h2{font-size:16px;margin:26px 0 10px}
a{color:var(--brand)}.muted{color:var(--muted)}.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;background:var(--panel);border:1px solid var(--line);border-radius:8px}th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{font-size:12px;color:var(--muted);font-weight:600}
td code,dd code{font-size:12px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}
.kpi{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 14px}.kpi span{color:var(--muted);font-size:12px;display:block}.kpi b{font-size:22px}.kpi small{display:block;color:var(--muted)}
.cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
form.inline{display:inline}form.stack label{display:block;margin:10px 0 4px;font-weight:600;font-size:13px}form.row{display:flex;gap:8px;flex-wrap:wrap;align-items:end}form.row label{display:flex;flex-direction:column;font-size:12px;color:var(--muted);gap:3px}
input,select,textarea{font:inherit;color:var(--ink);background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:7px 9px;max-width:100%}form.stack input,form.stack select,form.stack textarea{width:100%}textarea{font-family:ui-monospace,Consolas,monospace;font-size:12px}
button{font:inherit;background:var(--brand);color:var(--brand-ink);border:0;border-radius:6px;padding:8px 14px;cursor:pointer;margin-top:10px}button.danger{background:var(--bad);color:#fff}button.ghost{background:transparent;color:var(--brand);border:1px solid var(--line)}button.link{background:none;color:var(--muted);padding:0;margin:4px 0 0;text-decoration:underline;text-align:left}form.row button{margin-top:0}
.flash{padding:10px 12px;border-radius:8px;margin-bottom:14px;border:1px solid var(--line)}.flash.ok{background:var(--soft);color:var(--ok)}.flash.error{color:var(--bad);border-color:var(--bad)}.flash.secret{background:var(--panel);border:2px dashed var(--warn);word-break:break-all}
.badge{display:inline-block;padding:1px 8px;border-radius:999px;font-size:12px;border:1px solid var(--line)}.badge.ok{color:var(--ok);border-color:var(--ok)}.badge.bad{color:var(--bad);border-color:var(--bad)}.badge.warn{color:var(--warn);border-color:var(--warn)}
dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:0}dt{color:var(--muted)}dd{margin:0;word-break:break-all}
.chart{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px 12px}.chart figcaption{font-size:12px;color:var(--muted);margin-bottom:6px}.chart svg{width:100%;height:auto}.bar{fill:var(--brand)}.axis{fill:var(--muted);font-size:11px}.base{stroke:var(--line)}
.pager{display:flex;gap:14px;align-items:center;margin-top:10px}pre{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px;overflow:auto;font-size:12px;max-height:360px}
@media (max-width:760px){body{flex-direction:column}nav{width:auto;border-right:0;border-bottom:1px solid var(--line)}nav ul{display:flex;flex-wrap:wrap}nav li a{padding:6px 10px}main{padding:16px}}
CSS;
}
