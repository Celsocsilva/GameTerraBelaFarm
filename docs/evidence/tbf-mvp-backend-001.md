# TBF-MVP-BACKEND-001 — Backend PHP + MySQL (fundação, identidade, save, ledger, config, IAP)

**Data:** 27/11/2026 · **Pedido:** Celso ("implementar o backend em PHP e MySQL; por hora vou publicar em https://skyplan.com.br/terrabelafarm")
**Base:** `docs/architecture/MVP_LIVEOPS.md` e agentes v2.0.0 do PR #32 (branch `docs/mvp-liveops-architecture`, commit 8460355), trazidos para a pasta local.
**Agentes:** AGENT-09 Backend, AGENT-10 DBA, AGENT-12 Segurança & Monetização. QA/Reviewer independentes ainda não revisaram.
**Nota:** "TEE", citado no pedido, não foi encontrado no repositório; assumido como a estrutura de agentes/orquestração do PR #32.

## Entregue

- `backend/` — API REST `/api/v1` em PHP puro (sem Composer), 20 tabelas MySQL com COMMENT em 100% das tabelas, colunas e índices, catálogo de constraints, dicionário gerado, cron, CLI de administração, pacote de publicação. Detalhes em `backend/README.md`; publicação em `backend/DEPLOY.md`.
- Nada foi publicado no servidor nem enviado ao GitHub.

## Ambiente do teste

Container Linux: PHP 8.3.6 CLI, MySQL 8.0.46 (banco `tbf_test`), Apache 2.4 + mod_php com o `.htaccess` do pacote.
Google, Facebook e Google Play simulados com chaves RSA geradas no teste (nenhuma credencial real).

## Comandos e resultados

```text
php bin/migrate.php            -> 001_core (23 comandos), 002_seed_remote_config (4 comandos); 2ª execução: nada pendente
php bin/datadict.php           -> 20 tabelas, 36 constraints; Cobertura documental: 100%
php tests/run.php              -> resultado abaixo
```text
  ok   health e rota inexistente
  ok   visitante: criar, entrar de novo, segredo errado
  ok   refresh rotativo, reuso revoga, logout
  ok   save na nuvem: revisão, idempotência, conflito, histórico, limite
  ok   ledger: política do cliente, idempotência, saldo, teto diário
  ok   ledger: concorrência real (processos paralelos)
  ok   remote config: ETag, versão do cliente, rollback, manutenção
  ok   Google: login, audience errada, vínculo e conflito de fazendas
  ok   Facebook: debug_token válido e inválido
  ok   telemetria, abertura de push, dispositivos e preferências
  ok   recompensas: concessão única, resgate idempotente, expiração, acesso cruzado
  ok   IAP Google Play: pendente, concedido, replay, outra conta, RTDN reembolso
  ok   exclusão de conta e purge do cron
  ok   rate limit no login
  ok   dicionário de dados: 100% de COMMENT

144 verificações ok, 0 falhas (1.9s)
```

Teste HTTP real (Apache, pacote extraído no layout `public_html/terrabelafarm` + `terrabelafarm_app`):

```text
GET  http://.../terrabelafarm/api/v1/health              -> 301 para https (regra do .htaccess)
GET  /terrabelafarm/api/v1/health (https via proxy)     -> 200 {"status":"ok","schema_version":"002_seed_remote_config"}
POST /terrabelafarm/api/v1/auth/guest                   -> 200 player_id, guest_secret, tokens
GET  /terrabelafarm/api/v1/me (Authorization: Bearer)   -> 200 (cabeçalho Authorization chega ao PHP)
POST /terrabelafarm/api/v1/sync                         -> 200 revision 1
GET  /terrabelafarm/api/v1/config?client_version=0.3.0  -> 200 com ETag e Cache-Control
GET  /terrabelafarm/app-path.php | .htaccess | .env      -> 403
```

Logs gerados durante os testes: nenhuma ocorrência de access token, refresh token ou segredo de visitante.

## Não verificado / pendente

- Hospedagem real da Skyplan (versão de PHP/MySQL, mod_rewrite, cron) — depende do passo a passo do Celso.
- MariaDB não testado. Provedores reais (Google, Facebook, Google Play, Pub/Sub) não testados: só simulados.
- App Godot ainda não usa a API (adaptadores em `scripts/services/` são o próximo passo).
- Painel admin com RBAC/MFA, campanhas FCM e motor de regras (TBF-MVP-07 a 10) não implementados.
- Valores de economia (tetos de crédito de cash) e política de reembolso aguardam aprovação do PO.
- CI com MySQL real (GitHub Actions) não criado.
