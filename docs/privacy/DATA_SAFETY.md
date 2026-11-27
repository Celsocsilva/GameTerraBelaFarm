# Google Play Data Safety e LGPD — o que o backend guarda (TBF-MVP-12)

Rascunho para preencher o formulário "Segurança dos dados" do Play Console e a política de privacidade. Revisar com o jurídico antes de publicar. Fonte: tabelas em `backend/docs/database/DATA_DICTIONARY.md`.

## Dados coletados

| Categoria do Play | O que é no TerraBela | Tabela | Obrigatório? | Finalidade | Compartilhado com terceiros? |
|---|---|---|---|---|---|
| Identificadores do app/dispositivo | player_id (UUID aleatório), installation_id, token FCM | players, player_devices | sim (sem eles o jogo não salva) | funcionamento, push | Google (FCM entrega o push) |
| ID de usuário de conta | ID do Google ou do Facebook (só o número da conta, sem e-mail, nome ou foto) | player_identities | não (só se o jogador vincular) | login e restaurar a fazenda | não (o servidor só confirma o token com o provedor) |
| Compras | pedido da Google Play, produto, estado | iap_transactions | só se comprar | entregar e estornar compras | Google Play (é quem processa) |
| Atividade no app | eventos de jogo (ex.: colheita, venda, abertura de loja), versão do app | game_events | sim | métricas agregadas, balanceamento, regras de benefício | não |
| Diagnóstico | crash/ANR | — (Android Vitals) | — | estabilidade | Google |
| Outros conteúdos do usuário | save da fazenda | player_saves | sim (Cloud Save) | salvar e restaurar o progresso | não |
| Preferências | aceite de push operacional/promocional, permissão do sistema | player_consents | sim | respeitar opt-in/opt-out | não |

Não coletamos: nome, e-mail, telefone, localização, contatos, fotos, IP em claro (só hash com chave para segurança do backoffice), dados financeiros (cartão fica na Google).

## Práticas

- Criptografia em trânsito: sim (HTTPS obrigatório; HTTP redireciona).
- Exclusão: o jogador pede no app (`DELETE /api/v1/me`); após 30 dias o cron apaga dados pessoais e de jogo. Ledger e compras ficam sem vínculo de identidade (obrigação fiscal/antifraude).
- Acesso/portabilidade (LGPD art. 18): `GET /api/v1/me/export` devolve um JSON com todos os dados da conta (3 por hora); o suporte também exporta pelo backoffice (fica na auditoria).
- Retenção: eventos e sessões antigas são podados pelo cron; backups diários guardados por 14 dias fora da pasta pública (opcionalmente criptografados).
- Acesso interno: só operadores do backoffice com papel, senha forte, 2FA opcional e auditoria de cada ação.

## Pendências antes da publicação na loja

- Texto final da política de privacidade (pt/es/en) com o controlador (Skyplan Brasil Ltda) e o canal do encarregado.
- Formulário de exclusão de conta fora do app (exigência do Play): pode ser uma página simples que gera o pedido pelo suporte.
- Confirmar no Play Console as respostas da tabela acima.
