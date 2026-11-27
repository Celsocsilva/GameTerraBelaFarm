# Política de economia e reembolso (TBF-MVP-04/05)

Vale para o backend em `backend/` (ledger `economy_ledger`, carteira `wallets`). Os números ficam no Remote Config e podem ser ajustados no backoffice (Remote Config) sem nova versão do app.

## Moedas

| Moeda | Quem credita | Quem debita |
|---|---|---|
| cash (dinheiro do jogo) | o cliente, dentro dos limites abaixo e só com motivos da lista `economy.client_credit.cash.reasons`; benefícios; compras; ajuste do backoffice | o cliente, com motivos de `economy.client_debit_reasons`; reembolso; ajuste |
| gold (ouro, moeda premium) | **somente o servidor**: compra verificada na Google Play, benefício de regra/suporte, ajuste de administrador | o cliente (gasto com motivo permitido), reembolso, ajuste |

O servidor recusa qualquer Remote Config que permita ao cliente creditar ouro.

## Limites de crédito do cliente (aprovados por Celso em 27/11)

- **cash: até 5.000 por operação** (`economy.client_credit.cash.max_per_operation`).
- **cash: até 200.000 por jogador por dia UTC** (`economy.client_credit.cash.max_per_day`), somando só créditos com origem `client`.
- Acima disso a operação é recusada (`limit_exceeded`) e nada é lançado. Benefícios, compras e ajustes não contam no teto.

## Reembolso de compra (RTDN `VOIDED_PURCHASE`)

1. A compra passa para `refunded` e os direitos (entitlements) dela são revogados.
2. A moeda do benefício é **descontada até o saldo disponível**: `desconto = min(benefício, saldo)`. Lançamento `system / iap_refund` no ledger.
3. **O saldo nunca fica negativo.** O que não pôde ser descontado (o jogador já gastou) fica em `iap_transactions.refund_shortfall` para análise; o descontado fica em `refund_clawback`.
4. O backoffice (Compras → filtro “só com falta de saldo”) lista esses casos. Abuso repetido (vários reembolsos com falta) é tratado pelo suporte: avisar, ajustar carteira com motivo registrado ou suspender a conta. Não há desconto automático em compras futuras.
5. Mensagens RTDN repetidas não descontam de novo (idempotência por `messageId` e por chave `refund:<hash do token>`).

## Ajustes manuais (backoffice)

- Só papel **admin**; até 1.000.000 por ajuste; motivo obrigatório (5 a 200 caracteres) gravado na auditoria; envio repetido do mesmo formulário não duplica (chave de idempotência por formulário); débito acima do saldo é recusado.
- Benefício pelo suporte (papel support/admin): até 100.000 por concessão, vira uma recompensa que o jogador resgata no jogo.

## Regras automáticas de benefício

- Uma concessão por jogador, regra e ocorrência (uma vez, por dia, semana ou mês).
- Teto de jogadores por execução (`max_grants_per_run`), simulação antes de ativar, pausa a qualquer momento.
- O benefício é registrado antes de qualquer push e nunca depende de aceitar marketing.
