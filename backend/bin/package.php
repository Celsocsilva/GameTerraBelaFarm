<?php
declare(strict_types=1);

/**
 * Monta o pacote de publicação para hospedagem compartilhada (sem Composer, sem SSH):
 *   dist/terrabelafarm-backend-AAAAMMDD.zip
 *     public_html/terrabelafarm/   -> enviar para a pasta pública (index.php, .htaccess, app-path.php)
 *     terrabelafarm_app/           -> enviar para FORA do public_html (código, migrations, .env.example)
 * O pacote nunca inclui .env, logs, cache, testes nem credenciais.
 * Uso: php bin/package.php [nome_da_pasta_publica] [nome_da_pasta_privada]
 */
if (PHP_SAPI !== 'cli') {
    exit;
}
$root = dirname(__DIR__);
$publicName = $argv[1] ?? 'terrabelafarm';
$privateName = $argv[2] ?? 'terrabelafarm_app';
$dist = $root . '/dist';
@mkdir($dist, 0775, true);
$zipFile = $dist . '/terrabelafarm-backend-' . gmdate('Ymd') . '.zip';
@unlink($zipFile);
$zip = new ZipArchive();
if ($zip->open($zipFile, ZipArchive::CREATE) !== true) {
    fwrite(STDERR, "Não foi possível criar $zipFile\n");
    exit(1);
}
$pub = "public_html/$publicName/";
$priv = "$privateName/";
$zip->addFile("$root/public/index.php", $pub . 'index.php');
$zip->addFile("$root/public/.htaccess", $pub . '.htaccess');
$zip->addFromString($pub . 'app-path.php', "<?php\n// Pasta privada do backend (fora do public_html).\n// public_html/$publicName -> sobe 2 níveis até a pasta do usuário -> $privateName\nreturn dirname(__DIR__, 2) . '/$privateName';\n");

$include = ['src', 'bin', 'database', 'config', 'docs'];
$count = 0;
foreach ($include as $dir) {
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator("$root/$dir", FilesystemIterator::SKIP_DOTS));
    foreach ($it as $file) {
        $rel = substr($file->getPathname(), strlen($root) + 1);
        if (str_starts_with($rel, 'bin/package.php') || preg_match('/\.(log|env)$/', $rel)) {
            continue;
        }
        $zip->addFile($file->getPathname(), $priv . str_replace('\\', '/', $rel));
        $count++;
    }
}
foreach (['.htaccess', '.env.example', 'README.md', 'DEPLOY.md'] as $f) {
    if (is_file("$root/$f")) {
        $zip->addFile("$root/$f", $priv . $f);
    }
}
$zip->addFile("$root/.htaccess", $priv . 'storage/.htaccess');
$zip->addEmptyDir($priv . 'storage/logs');
$zip->addEmptyDir($priv . 'storage/cache');
$zip->close();
echo "Pacote: $zipFile ($count arquivos de código)\n";
