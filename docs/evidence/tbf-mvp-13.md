# TBF-MVP-13 — testes A/B pelo Remote Config e Sign in with Apple (servidor)

Data: 27/11/2026. Ambiente de prova: container com PHP 8.3 e MySQL 8.0.46 real.

## 13a. Testes A/B

- **Migration 005** (`experiments`, `experiment_assignments`, 100% COMMENT).
- **Divisão determinística** (`src/LiveOps/ExperimentService.php`): `sha256(sal:chave:id_público)` mod 10000 decide se entra no tráfego e, com outro hash, a variante pelos pesos. A variante fica gravada na primeira entrega e não muda.
- **Seguro por desenho**: variante só sobrescreve `features`, `routes` e `tuning`. Economia (tetos de cash, gold), manutenção e sync nunca entram em teste, porque o servidor usa esses valores para validar o app. Cada variante mesclada passa pela mesma validação do Remote Config ao criar e ao iniciar.
- **API** `GET /api/v1/experiments` (com login): variantes e a config já mesclada; sem cache.
- **Backoffice → Testes A/B** (operação e admin criam, iniciam e encerram; leitura vê): resultados por variante com expostos, retenção D1/D7 (só quem completou a janela), compradores e conversão no evento de meta. Tudo auditado.
- Exportação LGPD inclui as variantes recebidas.

## 13b. Sign in with Apple

- `POST /api/v1/auth/apple` e `provider: "apple"` no `/auth/link` (`src/Auth/AppleIdTokenVerifier.php`): assinatura RS256 pelo JWKS da Apple, `iss` = appleid.apple.com, `aud` em `APPLE_CLIENT_IDS` (Bundle ID e Services ID), validade e nonce (bruto ou SHA-256). Sem `APPLE_CLIENT_IDS` responde 503.
- Mesma regra dos outros logins: nunca mescla fazendas; conta Apple de outra fazenda devolve 409 `account_conflict`. E-mail do token não é guardado.
- **Migration 006** amplia a CHECK de provedores para `apple`.
- Pendente para a integração iOS: revogar o token na Apple quando a conta é excluída (exige a chave do Apple Developer).

## Verificação

`TBF_ENV_FILE=... php backend/tests/run.php`: **350 verificações ok, 0 falhas** (inclui divisão 50/50 em 4.000 jogadores, 20% de tráfego, recusa de variantes que mexem em economia/manutenção, estabilidade da variante, resultados D1/D7, permissões e auditoria; Apple com nonce, audience, issuer, expiração, chave errada, vínculo e conflito). Dicionário: 30 tabelas, 62 constraints, 100% COMMENT.
