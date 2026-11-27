# TerraBela Farm — backend PHP + MySQL (MVP)

API REST do jogo, conforme `docs/architecture/MVP_LIVEOPS.md` (PR #32) e os agentes v2.0.0
(AGENT-09 Backend, AGENT-10 DBA, AGENT-12 Segurança & Monetização). Itens do backlog cobertos:
TBF-MVP-01 (fundação, RBAC do backoffice), 02 (identidade, lado servidor), 03 (Cloud Save, lado servidor), 04 (ledger),
05 (validação Google Play, RTDN e política de reembolso, lado servidor), 06 (Remote Config), 07 (telemetria, métricas diárias
e painel), 09 (campanhas FCM com fila e nova tentativa) e 10 (motor de regras de benefício e calendário).
Backoffice web em `/admin` (guia em `docs/BACKOFFICE.md`); política de economia em `../docs/ECONOMY_POLICY.md`. O app Godot ainda **não** chama esta API: os adaptadores em `scripts/services/` são a próxima etapa.

## Decisões para caber na hospedagem compartilhada (skyplan.com.br)

| Especificação | Aqui | Motivo |
| --- | --- | --- |
| Composer + PSR-4 | autoload próprio (`src/bootstrap.php`), zero dependências | hospedagem sem SSH; nada para instalar |
| `.env` fora do webroot | `.env` na pasta privada `terrabelafarm_app/`; só `index.php` + `.htaccess` + `app-path.php` ficam no `public_html` | mesma regra do MVP, layout de cPanel |
| Workers PHP CLI e cron | `bin/cron.php` agendado no painel (Cron Jobs) | sem processo contínuo em hospedagem compartilhada |
| Migrations | arquivos SQL em ordem; `bin/migrate.php` **ou** importação no phpMyAdmin | sem shell |
| Fila Redis | nada; fila FCM futura em tabela MySQL | MVP proíbe Redis sem evidência |
| JWT para sessões | tokens opacos (256 bits) guardados só como HMAC, refresh rotativo com detecção de reuso | revogação imediata e simples no MySQL |
| `player_inventory`, `feature_flags` | não criadas: inventário de jogo fica no save; direitos em `entitlements`; flags em `features` do Remote Config | "não criar objetos só para preencher lista" (9.2) |
| Rota extra | `POST /wallet/operations` e `GET /wallet/ledger` | o MVP pede ledger com autoridade do servidor; o app precisa de um canal para créditos/débitos de cash dentro da política |

Compatível com PHP 8.1+ e MySQL 8.0+ (testado em PHP 8.3 + MySQL 8.0.46). MariaDB 10.6+ deve funcionar
(sem colação específica de MySQL), mas não foi testado.

## Rotas (`/api/v1`)

Todas respondem JSON. Erros: `{"error":{"code","message","request_id", ...detalhes}}` com HTTP adequado.
Rotas com 🔒 exigem `Authorization: Bearer <access_token>`.

| Método e rota | Uso |
| --- | --- |
| `GET /health` | estado da API e versão do schema |
| `POST /auth/guest` | `{}` cria visitante e devolve `guest_id` + `guest_secret` (**guardar em armazenamento protegido**; só vem uma vez). `{"guest_id","guest_secret"}` entra de novo |
| `POST /auth/google` | `{"id_token","nonce?"}` do Credential Manager; o servidor valida assinatura, `iss`, `aud`, `exp` e `nonce` |
| `POST /auth/facebook` | `{"access_token"}`; validado no Graph API `debug_token` com o app token do servidor |
| 🔒 `POST /auth/link` | `{"provider":"google"\|"facebook", ...token}` vincula à fazenda atual. Se a conta já pertence a outra fazenda: **409 `account_conflict`** com `current_farm` e `other_farm`; nada é mesclado |
| `POST /auth/refresh` | `{"refresh_token"}` → novos tokens (o antigo morre; reapresentá-lo encerra a sessão) |
| 🔒 `POST /auth/logout` | encerra a sessão deste aparelho |
| 🔒 `GET /me` / `DELETE /me` | perfil, vínculos, preferências / pedido de exclusão (sessões revogadas, purge após `DELETION_GRACE_DAYS`) |
| 🔒 `GET /save` | snapshot atual, `revision`, carteira do servidor e `server_time` |
| 🔒 `POST /sync` | `{"operation_id","base_revision","schema_version","snapshot",{"client_saved_at"}}`. Revisão diferente → **409 `save_conflict`** com `current_revision`; mesmo `operation_id` → mesma resposta (`replayed:true`). Saldos dentro do snapshot são ignorados |
| 🔒 `GET /wallet`, `GET /wallet/ledger?limit&before` | saldo e histórico paginado por cursor |
| 🔒 `POST /wallet/operations` | `{"operations":[{"operation_id","currency","amount","reason","reference?"}]}` até 50. Crédito de cash só com motivo permitido e dentro dos tetos; **gold nunca é creditado pelo app** |
| 🔒 `GET /inventory` | direitos permanentes (`entitlements`) e carteira |
| `GET /config?client_version=0.3.0` | Remote Config compatível, com `ETag` (responde 304) |
| 🔒 `POST /events/batch` | até 100 eventos `{"event_id","name","occurred_at?","app_version?","properties?"}`; nomes da lista do MVP; e-mail/token/nome nas propriedades são recusados |
| 🔒 `POST /devices/register`, `DELETE /devices/{id}` | instalação + token FCM, idioma e fuso |
| 🔒 `PUT /preferences/notifications` | `{"operational?","promotional?","os_permission_granted?"}` (histórico append-only; promocional começa desligado) |
| 🔒 `POST /notifications/{id}/open` | abertura idempotente |
| 🔒 `GET /rewards`, `POST /rewards/{id}/claim` | benefícios e resgate idempotente |
| 🔒 `POST /iap/verify` | `{"product_id","purchase_token"}` → `pending` / `granted` / `canceled`. O app deve passar `obfuscatedAccountId = sha256("tbf:" + player_id)` no fluxo de compra |
| `POST /iap/google/rtdn` | push do Pub/Sub com OIDC (conta de serviço e audience conferidas); reembolso revoga direitos |

Política de economia (Remote Config, `economy`): valores iniciais **propostos** em
`config/remote-config.default.json` (crédito de cash até 5.000 por operação e 200.000 por dia; motivos
`sale_collected`, `milk_sold`, `wood_sold`, `order_completed`). Precisam de aprovação do PO antes do lançamento.
Reembolso de compra consumível não debita gold automaticamente: fica registrado para decisão (política pendente).

## Estrutura

```text
backend/
  public/            index.php (front controller), .htaccess, app-path.example.php  -> public_html/terrabelafarm/
  src/               App.php, Core/, Http/, Auth/, Players/, Economy/, Config/, Rewards/, Billing/, Api/
  database/migrations/  001_core.sql (20 tabelas), 002_seed_remote_config.sql (gerado por bin/gen-seed.php)
  bin/               migrate.php, cron.php, admin.php, datadict.php, gen-seed.php, package.php
  config/            remote-config.default.json
  docs/database/     DATA_DICTIONARY.md (gerado), CATALOG.md (constraints)
  tests/             run.php (integração com MySQL real; recria o banco de teste)
  .env.example       configuração sem segredos
```

## Rodar localmente

```bash
cp .env.example .env.test   # APP_ENV=local, DB_NAME com "test", APP_KEY de 64 hex
TBF_ENV_FILE=.env.test php bin/migrate.php
TBF_ENV_FILE=.env.test php tests/run.php        # APAGA e recria o banco de teste
TBF_ENV_FILE=.env.test php bin/datadict.php     # falha se faltar COMMENT
php -S 127.0.0.1:8000 -t public public/index.php  # API em http://127.0.0.1:8000/api/v1/health (lê backend/.env)
php bin/package.php                             # dist/terrabelafarm-backend-AAAAMMDD.zip
```

Publicação: ver [DEPLOY.md](DEPLOY.md).

## Pendências (próximas etapas)

1. Adaptadores Godot (`scripts/services/`): sessão visitante, Cloud Save com fila offline, Wallet como projeção do ledger, telemetria, preferências de push (último passo, combinado com o Celso).
2. Spikes Android: Credential Manager (Google), Facebook SDK, Google Play Billing e plugin FCM com roteador de rotas para Godot 4.7.2 (TBF-MVP-08 lado app).
3. Credenciais externas no `.env` de produção quando existirem: `GOOGLE_CLIENT_IDS`, Facebook, conta de serviço do Play (Billing/RTDN) e do Firebase (`FCM_SERVICE_ACCOUNT_FILE`).
4. TBF-MVP-12: rotina de backup/restauração testada, revisão Data Safety, benchmark das consultas críticas com volume.
5. CI: `.github/workflows/backend.yml` está pronto na pasta local (MySQL 8 real + `tests/run.php` + `bin/datadict.php`); entra no GitHub quando o Celso pedir para versionar.
