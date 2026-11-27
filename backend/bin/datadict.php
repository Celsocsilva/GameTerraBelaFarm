<?php
declare(strict_types=1);

/**
 * Gera o dicionário de dados a partir do INFORMATION_SCHEMA (MVP_LIVEOPS.md 9.1) e
 * falha (exit 1) se alguma tabela, coluna ou índice próprio estiver sem COMMENT
 * ou se alguma constraint não estiver descrita em docs/database/CATALOG.md.
 * Uso: php bin/datadict.php [arquivo_saida.md]
 */
require __DIR__ . '/_cli.php';

$db = TerraBela\Core\Db::fromConfig(tbf_config());
$outFile = $argv[1] ?? dirname(__DIR__) . '/docs/database/DATA_DICTIONARY.md';
$catalogFile = dirname(__DIR__) . '/docs/database/CATALOG.md';
$catalog = is_file($catalogFile) ? (string) file_get_contents($catalogFile) : '';

$problems = [];
$tables = $db->all("SELECT TABLE_NAME, TABLE_COMMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME");
$md = "# Dicionário de dados — TerraBela Farm backend\n\n"
    . "Gerado automaticamente por `bin/datadict.php` a partir do INFORMATION_SCHEMA. Não editar à mão.\n"
    . "Constraints (FK/CHECK/UNIQUE) estão descritas também em [CATALOG.md](CATALOG.md).\n\n";
foreach ($tables as $t) {
    $name = $t['TABLE_NAME'];
    if (trim((string) $t['TABLE_COMMENT']) === '') {
        $problems[] = "tabela sem COMMENT: $name";
    }
    $md .= "## `$name`\n\n" . $t['TABLE_COMMENT'] . "\n\n| Coluna | Tipo | Nulo | Padrão | Descrição |\n| --- | --- | --- | --- | --- |\n";
    foreach ($db->all('SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION', [$name]) as $c) {
        if (trim((string) $c['COLUMN_COMMENT']) === '') {
            $problems[] = "coluna sem COMMENT: $name.{$c['COLUMN_NAME']}";
        }
        $md .= sprintf("| `%s` | %s | %s | %s | %s |\n", $c['COLUMN_NAME'], $c['COLUMN_TYPE'], $c['IS_NULLABLE'] === 'YES' ? 'sim' : 'não',
            $c['COLUMN_DEFAULT'] === null ? '' : '`' . $c['COLUMN_DEFAULT'] . '`', str_replace('|', '\\|', (string) $c['COLUMN_COMMENT']));
    }
    $md .= "\n| Índice | Colunas | Único | Descrição |\n| --- | --- | --- | --- |\n";
    foreach ($db->all('SELECT INDEX_NAME, MAX(NON_UNIQUE) AS NON_UNIQUE, MAX(INDEX_COMMENT) AS INDEX_COMMENT, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS COLS FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? GROUP BY INDEX_NAME ORDER BY INDEX_NAME', [$name]) as $i) {
        if (trim((string) $i['INDEX_COMMENT']) === '') {
            $problems[] = "índice sem COMMENT: $name.{$i['INDEX_NAME']}";
        }
        $md .= sprintf("| `%s` | %s | %s | %s |\n", $i['INDEX_NAME'], $i['COLS'], (int) $i['NON_UNIQUE'] === 0 ? 'sim' : 'não', $i['INDEX_COMMENT']);
    }
    $md .= "\n";
}
$constraints = $db->all("SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA = DATABASE() AND CONSTRAINT_TYPE IN ('FOREIGN KEY','CHECK') ORDER BY TABLE_NAME, CONSTRAINT_NAME");
$md .= "## Constraints\n\n| Tabela | Constraint | Tipo |\n| --- | --- | --- |\n";
foreach ($constraints as $c) {
    if (!str_contains($catalog, '`' . $c['CONSTRAINT_NAME'] . '`')) {
        $problems[] = "constraint sem descrição no CATALOG.md: {$c['CONSTRAINT_NAME']}";
    }
    $md .= "| `{$c['TABLE_NAME']}` | `{$c['CONSTRAINT_NAME']}` | {$c['CONSTRAINT_TYPE']} |\n";
}
$others = $db->all("SELECT 'VIEW' t, TABLE_NAME n FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE()
    UNION ALL SELECT 'TRIGGER', TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()
    UNION ALL SELECT ROUTINE_TYPE, ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()
    UNION ALL SELECT 'EVENT', EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE()");
$md .= "\nViews, triggers, rotinas e events: " . (count($others) === 0 ? "nenhum (por decisão: sem objetos sem finalidade comprovada).\n" : count($others) . "\n");
foreach ($others as $o) {
    if (!str_contains($catalog, '`' . $o['n'] . '`')) {
        $problems[] = "{$o['t']} sem descrição no CATALOG.md: {$o['n']}";
    }
}

if (!is_dir(dirname($outFile))) {
    mkdir(dirname($outFile), 0775, true);
}
file_put_contents($outFile, $md);
echo count($tables) . " tabelas, " . count($constraints) . " constraints documentadas em $outFile\n";
if ($problems) {
    fwrite(STDERR, "FALHA de cobertura documental:\n - " . implode("\n - ", $problems) . "\n");
    exit(1);
}
echo "Cobertura documental: 100%\n";
