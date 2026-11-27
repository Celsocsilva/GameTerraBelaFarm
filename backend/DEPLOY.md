# Publicar o backend em https://skyplan.com.br/terrabelafarm

Passo a passo para hospedagem compartilhada com cPanel (ou painel parecido), **sem SSH e sem Composer**.
Leva uns 20 minutos. Nada aqui foi executado no servidor: cada passo é seu.

Resultado esperado: `https://skyplan.com.br/terrabelafarm/api/v1/health` respondendo
`{"status":"ok", ...}`.

## 0. Antes de começar

- No painel, em **Select PHP Version** (ou MultiPHP Manager), deixe o domínio em **PHP 8.1 ou mais novo**
  com as extensões `pdo_mysql`, `openssl`, `curl`, `mbstring` e `json` ligadas.
- Em **phpMyAdmin**, veja a versão do servidor na tela inicial: o ideal é **MySQL 8.0+** (MariaDB 10.6+ também deve servir).
- Gere o pacote no seu computador, dentro da pasta `backend` do projeto: `php bin/package.php`
  (ou use o zip que veio pronto: `terrabelafarm-backend-AAAAMMDD.zip`).

## 1. Banco de dados

1. **MySQL Databases** → crie um banco (ex.: `usuario_tbf`) e um usuário (ex.: `usuario_tbfapi`) com senha forte.
2. Adicione o usuário ao banco com **ALL PRIVILEGES** (só neste banco).
3. Anote: nome do banco, usuário, senha e host (quase sempre `localhost`).

## 2. Enviar os arquivos

1. **File Manager** → vá para a pasta do usuário (a que **contém** `public_html`, ex.: `/home/usuario`).
2. **Upload** do zip e **Extract** ali mesmo. Vão aparecer:
   - `public_html/terrabelafarm/` com `index.php`, `.htaccess` e `app-path.php` (os únicos arquivos públicos);
   - `terrabelafarm_app/` **fora** do `public_html` (código, migrations, `.env.example`).
3. Se o `skyplan.com.br` usar outra pasta raiz (domínio adicional), mova `terrabelafarm/` para dentro dela e
   ajuste `app-path.php` para o caminho absoluto de `terrabelafarm_app` (ex.: `return '/home/usuario/terrabelafarm_app';`).
4. Ative **Show Hidden Files** no File Manager para ver `.htaccess` e `.env`.
5. Dê permissão de escrita (755 ou 775) em `terrabelafarm_app/storage`, `storage/logs` e `storage/cache`.

> Se a hospedagem não permitir nada fora do `public_html`, coloque `terrabelafarm_app` dentro de
> `public_html/terrabelafarm/_app`, edite `app-path.php` para `return __DIR__ . '/_app';` e confira que
> `https://skyplan.com.br/terrabelafarm/_app/.env` responde **403** (o `.htaccess` da pasta bloqueia tudo).

## 3. Configurar o `.env`

1. Em `terrabelafarm_app/`, copie `.env.example` para `.env` e edite:
   - `APP_ENV=production`
   - `APP_KEY=` 64 caracteres hexadecimais aleatórios. Gere no seu PC com
     `php -r "echo bin2hex(random_bytes(32));"`. **Guarde num cofre de senhas**: trocar depois derruba todas as sessões e os visitantes perdem o acesso.
   - `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST` do passo 1.
2. Deixe Google, Facebook e Google Play vazios por enquanto: essas rotas respondem 503 até serem configuradas.
3. Nunca coloque o `.env` no Git nem dentro do `public_html`.

## 4. Criar as tabelas (phpMyAdmin)

1. **phpMyAdmin** → selecione o banco do passo 1 → **Importar**.
2. Importe, nesta ordem, um de cada vez:
   1. `terrabelafarm_app/database/migrations/001_core.sql`
   2. `terrabelafarm_app/database/migrations/002_seed_remote_config.sql`
   (baixe-os pelo File Manager ou use os arquivos do zip no seu PC).
3. Confira: 20 tabelas e, em `schema_migrations`, as linhas `001_core` e `002_seed_remote_config`.
4. Futuras migrations (`003_...`) seguem o mesmo caminho, **sempre com backup antes** (phpMyAdmin → Exportar).

## 5. Testar

No navegador ou no terminal do seu PC:

```bash
curl https://skyplan.com.br/terrabelafarm/api/v1/health
curl -X POST https://skyplan.com.br/terrabelafarm/api/v1/auth/guest -H "Content-Type: application/json" -d "{}"
curl "https://skyplan.com.br/terrabelafarm/api/v1/config?client_version=0.3.0"
```

- `health` deve mostrar `"schema_version":"003_backoffice_liveops"` e `"environment":"production"`.
- `auth/guest` deve devolver `player_id`, `guest_secret` e `access_token` (é uma conta de teste; pode ignorar).
- Confira que estes endereços **não** abrem (403/404): `/terrabelafarm/app-path.php`, `/terrabelafarm/.htaccess`, `/terrabelafarm_app/.env`.
- Se `/api/v1/me` com o token responder 401 mesmo com token válido, a hospedagem está descartando o
  cabeçalho `Authorization`; o `.htaccess` já trata o caso comum. Me avise se acontecer.
- Erro 503 `service_unavailable`: confira `.env` (APP_KEY com 64 caracteres, dados do banco) e o log de erros do PHP no painel.

## 6. Cron (manutenção)

**Cron Jobs** → a cada 15 minutos:

```text
*/15 * * * *  php /home/usuario/terrabelafarm_app/bin/cron.php >/dev/null 2>&1
```

(Se o painel pedir o caminho do PHP, algo como `/usr/local/bin/php` ou `/opt/cpanel/ea-php83/root/usr/bin/php`.)
Ele finaliza compras pendentes na Google, roda as regras de benefício ativas, envia as campanhas push agendadas,
recalcula as métricas do painel, expira benefícios, limpa sessões (jogo e backoffice) e rate limit e faz o purge das contas com exclusão vencida.

## 6b. Atualizar uma instalação existente (sem SSH)

1. Envie por FTP o conteúdo novo de `terrabelafarm_app/` (sem apagar o `.env`) e de `public_html/terrabelafarm/` (sem sobrescrever o `app-path.php`).
2. Gere um token aleatório (`php -r "echo bin2hex(random_bytes(24));"`), salve em `public_html/terrabelafarm/install_token.txt` e envie `deploy/web_install.php` como `install_<hex>.php`.
3. Abra uma vez: `https://skyplan.com.br/terrabelafarm/install_<hex>.php?token=TOKEN`
   - `&admin_email=EMAIL&admin_name=NOME` cria o primeiro administrador do backoffice e mostra o link de configuração de senha (uso único, 72 h);
   - `&purge_before=2026-11-27T23:59:59Z` apaga jogadores de teste sem save, sem ledger e sem compra criados antes do instante.
4. O instalador apaga a si mesmo e o token. Confira por FTP que nenhum dos dois sobrou.
5. Backoffice: `https://skyplan.com.br/terrabelafarm/admin/` (guia em `docs/BACKOFFICE.md`).

No `.env` de produção, atrás da Cloudflare use `TRUST_PROXY=cloudflare` e, para o link do backoffice, `APP_URL=https://skyplan.com.br/terrabelafarm`.

## 7. Depois, quando for ligar cada integração

| Integração | O que preencher no `.env` | Onde obter |
| --- | --- | --- |
| Login Google | `GOOGLE_CLIENT_IDS` (client ID Web usado pelo Credential Manager) | Google Cloud Console → Credenciais |
| Login Facebook | `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET` | Meta for Developers |
| Google Play Billing | `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` = caminho absoluto de um JSON guardado em `terrabelafarm_app/credentials/` | Play Console → Acesso à API (conta de serviço com permissão de pedidos) |
| Push FCM | `FCM_SERVICE_ACCOUNT_FILE` (JSON da conta de serviço do Firebase com papel de envio do FCM, em `terrabelafarm_app/credentials/`) e opcional `FCM_PROJECT_ID` | Firebase Console → Configurações do projeto → Contas de serviço |
| RTDN | `RTDN_AUDIENCE` e `RTDN_SERVICE_ACCOUNT_EMAIL` da assinatura push autenticada | Google Cloud Pub/Sub → assinatura push para `https://skyplan.com.br/terrabelafarm/api/v1/iap/google/rtdn` |

Produtos de compra entram pelo backoffice (Produtos → Nova versão) quando os SKUs existirem no Play Console.

## Backup e restauração (TBF-MVP-12)

- O cron faz **1 backup por dia** em `terrabelafarm_app/storage/backups/` (SQL compactado, fora do public_html, mantém 14; `BACKUP_KEEP`). Com `BACKUP_ENCRYPTION_KEY` (64 hex) o arquivo sai criptografado (`.enc`): guarde a chave fora do servidor, sem ela o backup não abre.
- Backup manual: backoffice → Sistema e backup → Fazer backup agora.
- **Restaurar** (sem SSH): baixe o `.sql.gz` por FTP; no cPanel crie um banco vazio; phpMyAdmin → Importar o arquivo; confira o painel apontando um `.env` de teste para ele; só então troque `DB_NAME` no `.env` de produção. Com SSH: `php bin/restore.php ARQUIVO --confirm` (aceita `.enc`).
- A restauração é testada a cada versão (`tests/run.php`: tabelas idênticas por CHECKSUM TABLE depois de restaurar num banco vazio).
- Desempenho: `php bin/bench.php 20000` (só em banco de teste) mede as consultas críticas e falha se alguma varrer tabela grande.

## Desfazer

- Tirar do ar: renomeie `public_html/terrabelafarm/index.php` (a API para na hora).
- Voltar o banco: importe o backup exportado antes da migration.
- Remover tudo: apague `public_html/terrabelafarm/`, `terrabelafarm_app/` e o banco.
