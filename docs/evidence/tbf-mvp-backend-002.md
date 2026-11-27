# TBF-MVP-BACKEND-002 — backoffice, LiveOps e política de economia

Data: 27/11/2026. Pedido do Celso: "siga com a implementação completa de tudo que está pendente". Ambiente de prova: container com PHP 8.3, MySQL 8.0.46 real e Apache 2.4 + mod_php (estrutura igual à da hospedagem: `public_html/terrabelafarm` + `terrabelafarm_app`).

## Entregue

- **IP real atrás da Cloudflare** (`TRUST_PROXY=cloudflare`): `CF-Connecting-IP` só é aceito quando a conexão vem das faixas publicadas da Cloudflare (`src/Http/CloudflareIps.php`); chamada direta à origem não consegue forjar IP para escapar do rate limit.
- **Política de economia e reembolso** (`docs/ECONOMY_POLICY.md`): cash 5.000 por operação e 200.000 por dia; reembolso desconta a moeda até o saldo, nunca negativo, e registra a falta (`refund_clawback`, `refund_shortfall`).
- **Migration 003** (8 tabelas novas, 28 no total, 57 constraints, 100% COMMENT): usuários/sessões/auditoria do backoffice, campanhas e fila push, regras e execuções, métricas diárias.
- **Backoffice `/admin`** (`src/Admin/`, guia `backend/docs/BACKOFFICE.md`): link de configuração de senha de uso único, bcrypt, bloqueio após 5 erros por 15 min, rate limit por IP, 2FA TOTP com proteção contra reutilização, cookie HttpOnly/Secure/SameSite=Strict, sessão com expiração por inatividade e absoluta, CSRF, CSP sem script, RBAC (admin/operation/support/read) e auditoria de cada ação. Telas: painel com KPIs, gráficos SVG e retenção; jogadores (ficha completa, ajuste de carteira, benefício, encerrar sessões); ledger; compras/reembolsos; produtos; Remote Config (publicar/rollback/manutenção); eventos; campanhas push; regras de benefício; calendário; auditoria; usuários; minha conta.
- **LiveOps no cron**: campanhas FCM HTTP v1 (opt-in promocional, opt-out operacional, permissão do sistema, teto semanal, fila com até 5 tentativas e backoff, token inválido limpo), regras declarativas (nunca executam código vindo da tela; uma concessão por ocorrência; simulação; pausa; versões), métricas diárias idempotentes.
- **Instalador de uso único** `backend/deploy/web_install.php`: migrations pendentes, primeiro admin com link de configuração e limpeza dos jogadores de teste (sem save, ledger ou compra). Apaga a si mesmo e o token.
- **CI** `.github/workflows/backend.yml` (MySQL 8 real), só na pasta local até o Celso pedir para versionar.

## Verificação

`TBF_ENV_FILE=... php backend/tests/run.php`:

```
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
  ok   IP real via Cloudflare (CF-Connecting-IP só de faixas da Cloudflare)
  ok   reembolso de ouro: desconta até o saldo, nunca negativo, registra a falta
  ok   TOTP RFC 6238
  ok   backoffice: link de configuração, login, bloqueio, cookie, CSRF e expiração
  ok   backoffice: 2FA TOTP com proteção contra reutilização
  ok   backoffice: papéis, carteira, benefício, config e auditoria
  ok   campanhas push: público, opt-in, fila, nova tentativa, token inválido
  ok   regras de benefício: simulação, ativação, uma vez por jogador, aviso
  ok   métricas diárias e cron completo
  ok   dicionário de dados: 100% de COMMENT

278 verificações ok, 0 falhas (3.9s)
```

`php backend/bin/datadict.php`: 28 tabelas, 57 constraints, cobertura documental 100%.

HTTP real (Apache local com a mesma estrutura da hospedagem): instalador aplicou a 003 sobre um banco no estado de produção (001+002, 20 tabelas → 28), criou o admin com link de uso único e apagou o visitante de teste; setup de senha 303, login 303 com cookie `HttpOnly; SameSite=Strict; Path=/terrabelafarm/admin`, painel e as 12 telas responderam 200, CSP com nonce presente, HTTP sem TLS redireciona (301).

## Não coberto aqui

- App Godot ainda não chama a API (integração é o último passo).
- Envio real de push depende do JSON da conta de serviço do Firebase no servidor; Google Play Billing/RTDN e logins Google/Facebook dependem das credenciais de cada console.
- Crash/ANR ficam no Android Vitals.
