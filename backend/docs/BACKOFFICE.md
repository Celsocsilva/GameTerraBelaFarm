# Backoffice TerraBela Farm (`/terrabelafarm/admin/`)

Painel web servido pelo mesmo `index.php` da API (PHP no servidor, sem JavaScript e sem CDN). Endereço em produção: `https://skyplan.com.br/terrabelafarm/admin/`.

## Acesso e segurança

- **Primeiro administrador**: criado pelo instalador de uso único (`deploy/web_install.php?admin_email=...`), que mostra um **link de configuração** (uso único, 72 h). A pessoa abre o link e define a própria senha; a senha nunca passa por arquivo, e-mail ou chat.
- **Novos operadores**: Usuários → Novo operador gera o link do mesmo jeito. “Novo link de senha” serve para senha esquecida ou celular do 2FA perdido (apaga senha e 2FA e derruba as sessões).
- Senha com no mínimo 12 caracteres, guardada com `password_hash` (bcrypt/argon2).
- Após **5 erros**, login bloqueado por **15 minutos**; e no máximo 10 tentativas por minuto por IP (o IP real vem do `CF-Connecting-IP` só quando a conexão chega da Cloudflare, `TRUST_PROXY=cloudflare`).
- **2FA TOTP** (Minha conta → Configurar 2FA) com Google/Microsoft Authenticator, Authy ou 1Password. Um código não pode ser reutilizado. Recomendado para todos os administradores.
- Sessão: cookie `tbf_admin` HttpOnly, Secure, SameSite=Strict, restrito a `/terrabelafarm/admin`; guardado no banco como HMAC; expira com **30 min sem uso** ou **12 h** no total (`ADMIN_IDLE_MINUTES`, `ADMIN_SESSION_HOURS`).
- Todo formulário tem token CSRF; POST de outra origem é recusado. CSP sem script, `frame-ancestors 'none'`, `noindex`.
- **Auditoria** de login, falhas, cada ação e cada acesso negado (`admin_audit_log`, IP só como hash).

## Papéis

| Papel | Pode |
|---|---|
| admin | tudo, inclusive ajustar carteira e gerenciar usuários |
| operation | Remote Config, produtos, campanhas push, regras de benefício, métricas, auditoria |
| support | conceder benefício a um jogador e encerrar as sessões dele |
| read | ver todas as telas, exceto auditoria e usuários |

## Telas

- **Painel**: jogadores, ativos 24 h/7 dias, novos, saves, compras e reembolsos 30 dias, compras a finalizar, push e benefícios; gráficos de 30 dias (DAU, novos, compras, push abertos, ouro creditado/gasto); retenção D1/D7/D30 por coorte; estado do sistema. Crash/ANR ficam no Android Vitals do Play Console.
- **Jogadores**: busca por player_id (ou o começo dele) ou installation_id; ficha com carteira, save, logins, aparelhos, consentimentos, ledger, compras, direitos, benefícios e auditoria do jogador; ações conforme o papel.
- **Carteira / ledger**: totais de 24 h por moeda e origem e lançamentos com filtros.
- **Compras**: estado, finalização na Google, reembolsos com desconto e falta de saldo.
- **Produtos**: SKUs e versões de benefício; nova versão desativa as anteriores.
- **Remote Config**: versões, publicar (validação no servidor), retirar (rollback), modo manutenção.
- **Eventos**: contagem por evento (7 dias) e eventos recentes.
- **Campanhas push**: rascunho, público estimado, envio de teste, agendamento (horário de Brasília), cancelamento, contadores e erros.
- **Regras de benefício**: versões, simulação, ativar/pausar, executar agora, histórico.
- **Calendário**: envios agendados por dia, regras ativas e campanhas recentes.
- **Auditoria** e **Usuários**.

## Cron

`bin/cron.php` (a cada 15 min no painel da hospedagem) roda: finalização de compras, regras ativas (no máximo 1x/hora cada), campanhas agendadas (fila com até 5 tentativas e backoff), métricas de hoje e ontem, expiração de benefícios e limpezas. Sem `FCM_SERVICE_ACCOUNT_FILE` o envio de push fica parado (o relatório mostra `fcm_configured: 0`).
