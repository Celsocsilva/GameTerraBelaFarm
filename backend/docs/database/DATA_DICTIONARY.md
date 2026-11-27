# Dicionário de dados — TerraBela Farm backend

Gerado automaticamente por `bin/datadict.php` a partir do INFORMATION_SCHEMA. Não editar à mão.
Constraints (FK/CHECK/UNIQUE) estão descritas também em [CATALOG.md](CATALOG.md).

## `admin_audit_log`

Trilha append-only de ações no backoffice (domínio: administração/segurança)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do registro de auditoria |
| `admin_id` | int unsigned | sim |  | Operador que agiu (FK admin_users.id); NULL para tentativas sem usuário identificado ou ações do sistema |
| `action` | varchar(48) | não |  | Ação: login_ok, login_failed, wallet_adjust, reward_grant, config_publish, campaign_schedule etc. |
| `target_type` | varchar(32) | sim |  | Tipo do alvo (player, config, campaign, product, rule, admin_user); NULL quando não se aplica |
| `target_id` | varchar(64) | sim |  | Identificador público do alvo; NULL quando não se aplica |
| `details` | json | sim |  | Dados da ação sem segredos (valores antes/depois, motivo); NULL sem detalhes |
| `ip_hash` | char(64) | sim |  | SHA-256 com chave do IP de origem; NULL em ações do sistema |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da ação |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_admin_audit_admin` | admin_id,id | não | Histórico por operador; atende a FK |
| `ix_admin_audit_created` | created_at | não | Filtro por período na tela de auditoria |
| `ix_admin_audit_target` | target_type,target_id,id | não | Histórico de um alvo (ex.: todas as ações sobre um jogador) |
| `PRIMARY` | id | sim | Chave interna; ordem cronológica de gravação |

## `admin_sessions`

Sessões do backoffice em banco, com expiração ociosa e absoluta (domínio: administração)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da sessão do backoffice |
| `admin_id` | int unsigned | não |  | Operador da sessão (FK admin_users.id) |
| `token_hash` | char(64) | não |  | HMAC-SHA256 do cookie de sessão; o valor do cookie nunca é gravado |
| `csrf_token` | char(64) | não |  | Token anti-CSRF desta sessão, exigido em todo formulário POST |
| `mfa_passed` | tinyint(1) | não | `0` | 1 quando a senha e (se habilitado) o TOTP foram confirmados; 0 aguardando o código |
| `ip_hash` | char(64) | não |  | SHA-256 com chave do IP de login (auditoria sem guardar IP em claro) |
| `user_agent` | varchar(255) | sim |  | Navegador do login (truncado); NULL se ausente |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do login |
| `last_seen_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da última página; expira após 30 min sem uso |
| `expires_at` | datetime(6) | não |  | Expiração absoluta UTC (12 h após o login) |
| `revoked_at` | datetime(6) | sim |  | Instante UTC do logout ou revogação; NULL enquanto válida |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_admin_sessions_admin` | admin_id,revoked_at | não | Revogação das sessões de um operador; atende a FK |
| `ix_admin_sessions_expiry` | expires_at | não | Limpeza periódica pelo cron |
| `PRIMARY` | id | sim | Chave interna |
| `uq_admin_sessions_token` | token_hash | sim | Autenticação de cada página pelo hash do cookie |

## `admin_users`

Operadores do backoffice com RBAC por papel (domínio: administração), separados dos jogadores

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | int unsigned | não |  | Identificador interno do usuário do backoffice |
| `email` | varchar(191) | não |  | E-mail de login do operador (minúsculas); não é jogador |
| `display_name` | varchar(80) | não |  | Nome exibido no backoffice e na auditoria |
| `role` | varchar(16) | não |  | Papel RBAC: admin (tudo), operation (LiveOps e config), support (jogadores e benefícios), read (somente leitura) |
| `password_hash` | varchar(255) | sim |  | Hash password_hash() (Argon2id ou bcrypt); NULL até o usuário concluir o link de configuração |
| `totp_secret` | varchar(64) | sim |  | Segredo TOTP (Base32) do segundo fator; NULL quando o 2FA não foi configurado |
| `totp_enabled` | tinyint(1) | não | `0` | 1 quando o login exige o código do aplicativo autenticador |
| `totp_last_step` | bigint unsigned | sim |  | Último passo TOTP (unix/30) aceito; impede reutilizar o mesmo código; NULL antes do primeiro uso |
| `status` | varchar(16) | não | `active` | Estado: active ou disabled (sem acesso, sessões revogadas) |
| `failed_attempts` | smallint unsigned | não | `0` | Falhas de login consecutivas; zera no login correto |
| `locked_until` | datetime(6) | sim |  | Instante UTC até quando o login fica bloqueado após muitas falhas; NULL sem bloqueio |
| `setup_token_hash` | char(64) | sim |  | SHA-256 do token do link de configuração de senha (uso único); NULL depois de usado |
| `setup_expires_at` | datetime(6) | sim |  | Instante UTC de expiração do link de configuração; NULL sem link pendente |
| `last_login_at` | datetime(6) | sim |  | Instante UTC do último login completo; NULL se nunca entrou |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de criação do usuário |
| `updated_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da última alteração de cadastro, senha ou 2FA |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | id | sim | Chave interna |
| `uq_admin_users_email` | email | sim | Um usuário por e-mail; busca no login |
| `uq_admin_users_setup` | setup_token_hash | sim | Localiza o usuário pelo link de configuração |

## `daily_metrics`

Agregados diários para o painel, recalculados de forma incremental (domínio: analytics)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `metric_date` | date | não |  | Dia UTC a que o valor se refere |
| `metric` | varchar(40) | não |  | Nome do indicador: dau, new_players, sessions, iap_granted, iap_refunded, cash_source, cash_sink, gold_source, gold_sink, push_sent, push_opened, rewards_claimed |
| `dimension` | varchar(40) | não | `` | Recorte opcional do indicador (ex.: SKU, motivo); vazio para o total |
| `value` | bigint | não |  | Valor inteiro agregado do dia (contagem ou soma de moeda em unidades inteiras) |
| `computed_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do último recálculo (o cron recalcula hoje e ontem) |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_daily_metrics_metric` | metric,metric_date | não | Série temporal de um indicador |
| `PRIMARY` | metric_date,metric,dimension | sim | Um valor por dia, indicador e recorte; alimenta os gráficos do painel |

## `economy_ledger`

Ledger append-only de moedas; fonte da verdade dos saldos (domínio: economia)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do lançamento; ordem dentro do jogador |
| `player_id` | bigint unsigned | não |  | Jogador do lançamento (FK players.id) |
| `currency` | varchar(8) | não |  | Moeda: cash (comum) ou gold (premium) |
| `amount` | bigint | não |  | Quantidade inteira assinada: positiva credita, negativa debita; nunca zero |
| `balance_after` | bigint unsigned | não |  | Saldo da moeda logo após este lançamento |
| `source` | varchar(16) | não |  | Origem: client (operação do app dentro da política), iap (compra verificada), reward (benefício resgatado), admin, system |
| `reason` | varchar(40) | não |  | Motivo de negócio (ex.: sale_collected, helper_hired, iap_purchase, reward_claim) |
| `reference` | varchar(128) | sim |  | Referência externa opcional (SKU, id do benefício, id de pedido); NULL quando não houver |
| `idempotency_key` | varchar(100) | não |  | Chave única por jogador que impede lançar a mesma operação duas vezes |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do lançamento |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_ledger_player_daily` | player_id,currency,source,created_at | não | Soma de créditos do cliente no dia para o teto diário |
| `ix_ledger_player_id` | player_id,id | não | Histórico paginado por cursor do jogador |
| `PRIMARY` | id | sim | Chave interna do lançamento |
| `uq_ledger_player_idempotency` | player_id,idempotency_key | sim | Invariante de idempotência do ledger; atende a FK player_id |

## `entitlements`

Itens permanentes concedidos pelo servidor (domínio: economia)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do direito concedido |
| `player_id` | bigint unsigned | não |  | Jogador que recebeu o direito (FK players.id) |
| `entitlement_key` | varchar(64) | não |  | Chave do item permanente (ex.: helper_slot_extra, cosmetic_hat_straw) definida no catálogo |
| `source` | varchar(16) | não |  | Origem: iap, reward, admin |
| `source_reference` | varchar(128) | não |  | Referência da origem (id da transação IAP ou do benefício) |
| `granted_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da concessão |
| `revoked_at` | datetime(6) | sim |  | Instante UTC da revogação (reembolso/estorno); NULL enquanto vigente |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | id | sim | Chave interna |
| `uq_entitlements_player_key` | player_id,entitlement_key | sim | Um direito por chave por jogador (concessão idempotente); atende a FK |

## `game_events`

Telemetria client-side recebida em lote (domínio: analytics)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do evento |
| `event_id` | varchar(64) | não |  | Identificador idempotente gerado pelo app; reenvio do mesmo evento é ignorado |
| `player_id` | bigint unsigned | não |  | Jogador pseudônimo que gerou o evento (FK players.id) |
| `event_name` | varchar(40) | não |  | Nome do evento da lista permitida (first_open, session_start, crop_harvested...) |
| `occurred_at` | datetime(6) | não |  | Instante UTC do evento segundo o aparelho (limitado a +24h do servidor) |
| `received_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de recebimento pelo servidor |
| `app_version` | varchar(32) | sim |  | Versão do app que enviou; NULL se ausente |
| `properties` | json | sim |  | Propriedades permitidas do evento (até 2 KB), sem e-mail, tokens ou dados pessoais; NULL se nenhuma |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_game_events_name_time` | event_name,occurred_at | não | Agregados diários por evento para o dashboard |
| `ix_game_events_player_time` | player_id,occurred_at,id | não | Linha do tempo do jogador e retenção por coorte; atende a FK |
| `PRIMARY` | id | sim | Chave interna |
| `uq_game_events_event_id` | event_id | sim | Invariante: cada event_id é gravado uma vez |

## `iap_events`

Trilha de eventos de compra, inclusive notificações RTDN (domínio: monetização)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do evento |
| `source` | varchar(16) | não |  | Origem: verify (chamada do app), rtdn (notificação Pub/Sub da Google), reconcile (cron) |
| `message_id` | varchar(128) | não |  | Identificador do evento na origem (messageId do Pub/Sub ou id gerado); torna o processamento idempotente |
| `transaction_id` | bigint unsigned | sim |  | Compra afetada (FK iap_transactions.id); NULL quando o token ainda não é conhecido |
| `event_type` | varchar(48) | não |  | Tipo: ONE_TIME_PRODUCT_PURCHASED, VOIDED_PURCHASE, VERIFY_GRANTED, VERIFY_PENDING etc. |
| `payload` | json | não |  | Dados do evento sem purchase token em claro (substituído pelo hash) |
| `received_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de recebimento |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_iap_events_transaction` | transaction_id | não | Linha do tempo de uma compra; atende a FK |
| `PRIMARY` | id | sim | Chave interna |
| `uq_iap_events_source_message` | source,message_id | sim | Invariante: cada mensagem da origem é processada uma vez |

## `iap_products`

Catálogo interno que mapeia SKU da loja a benefício versionado; preços vêm sempre da loja (domínio: monetização)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | int unsigned | não |  | Identificador interno do produto/versão |
| `platform` | varchar(16) | não |  | Loja: google_play (app_store em expansão futura) |
| `sku` | varchar(100) | não |  | Product ID cadastrado na loja (Play Console) |
| `product_type` | varchar(16) | não |  | consumable (consumido após conceder, ex.: pacote de gold) ou non_consumable (direito permanente) |
| `benefit_version` | smallint unsigned | não |  | Versão imutável do benefício; mudar o benefício exige nova versão |
| `benefit` | json | não |  | Benefício aprovado: {"currency":"gold","amount":N} e/ou {"entitlements":["chave"]} |
| `active` | tinyint(1) | não | `0` | 1 quando esta versão é a vigente para o SKU; 0 rascunho ou versão antiga |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de cadastro desta versão |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_iap_products_active` | platform,sku,active | não | Busca da versão ativa do SKU na validação de compra |
| `PRIMARY` | id | sim | Chave interna |
| `uq_iap_products_sku_version` | platform,sku,benefit_version | sim | Versão de benefício única por SKU e loja |

## `iap_transactions`

Compras na loja validadas no servidor (domínio: monetização). Retida para auditoria fiscal

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da compra |
| `public_id` | binary(16) | não |  | Identificador público opaco da compra devolvido ao app |
| `player_id` | bigint unsigned | não |  | Jogador que apresentou a compra (FK players.id) |
| `product_id` | int unsigned | não |  | Versão do produto/benefício usada na concessão (FK iap_products.id) |
| `platform` | varchar(16) | não |  | Loja da compra: google_play |
| `purchase_token` | varchar(512) | não |  | Purchase token da Google Play, necessário para consultar/consumir; nunca registrado em log |
| `purchase_token_hash` | char(64) | não |  | SHA-256 (hex) do purchase token; garante uso único |
| `order_id` | varchar(100) | sim |  | orderId (GPA.xxxx) retornado pela Google; NULL enquanto a compra estiver pendente |
| `state` | varchar(16) | não |  | Estado: pending (aguardando pagamento), granted (benefício concedido), canceled, refunded (estornada pela loja) |
| `store_state_raw` | varchar(32) | sim |  | purchaseState/consumptionState/acknowledgementState da última consulta, para auditoria; NULL antes da consulta |
| `finalize_status` | varchar(16) | não | `none` | Finalização na loja: none, pending (consume/acknowledge a repetir), done |
| `finalize_attempts` | smallint unsigned | não | `0` | Tentativas de consume/acknowledge feitas |
| `purchase_time` | datetime(6) | sim |  | Instante UTC da compra segundo a loja; NULL se não informado |
| `granted_at` | datetime(6) | sim |  | Instante UTC da concessão do benefício; NULL se ainda não concedido |
| `refunded_at` | datetime(6) | sim |  | Instante UTC em que o estorno foi registrado; NULL se não houve |
| `refund_clawback` | bigint unsigned | sim |  | Quantidade da moeda do benefício descontada no reembolso (limitada ao saldo); NULL sem reembolso ou sem moeda |
| `refund_shortfall` | bigint unsigned | sim |  | Parte do benefício reembolsado que não pôde ser descontada por falta de saldo (fica para análise); NULL sem reembolso |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do primeiro registro da compra |
| `updated_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da última mudança de estado |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_iap_tx_finalize` | finalize_status,updated_at | não | Seleção pelo cron das compras com consume/acknowledge pendente |
| `ix_iap_tx_player` | player_id,created_at | não | Histórico de compras do jogador; atende a FK player_id |
| `ix_iap_tx_product` | product_id | não | Atende a FK product_id e relatórios por produto |
| `PRIMARY` | id | sim | Chave interna |
| `uq_iap_tx_order` | platform,order_id | sim | Invariante: um pedido da loja gera no máximo uma transação (NULLs permitidos) |
| `uq_iap_tx_public_id` | public_id | sim | Unicidade do identificador público |
| `uq_iap_tx_token_hash` | purchase_token_hash | sim | Invariante: um purchase token gera no máximo uma concessão |

## `notification_campaigns`

Campanhas de notificação push com segmento, agenda e contadores (domínio: LiveOps)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | int unsigned | não |  | Identificador interno da campanha |
| `public_id` | char(12) | não |  | Código curto da campanha (C-xxxxxxxxxx) enviado no data do push como campaign_id |
| `name` | varchar(120) | não |  | Nome interno da campanha (não aparece para o jogador) |
| `category` | varchar(16) | não |  | operational (avisos do jogo, respeita notify_operational) ou promotional (ofertas, exige opt-in notify_promotional) |
| `title` | varchar(65) | não |  | Título da notificação exibido no aparelho |
| `body` | varchar(240) | não |  | Texto da notificação exibido no aparelho |
| `route` | varchar(16) | não |  | Destino ao tocar: farm, shop, tomatoes, corn, pumpkins, helpers, rewards, events |
| `locale` | varchar(16) | sim |  | Segmento por idioma do aparelho (pt_BR, es, en); NULL envia para todos os idiomas |
| `platform` | varchar(16) | sim |  | Segmento por plataforma (android/ios); NULL todas |
| `inactive_days_min` | smallint unsigned | sim |  | Segmento: só jogadores sem atividade há pelo menos N dias; NULL sem filtro |
| `status` | varchar(16) | não | `draft` | Estado: draft, scheduled, sending, completed, canceled |
| `scheduled_at` | datetime(6) | sim |  | Instante UTC a partir do qual o cron começa o envio; NULL em rascunho |
| `expires_at` | datetime(6) | sim |  | Instante UTC após o qual envios pendentes são descartados; NULL sem expiração |
| `audience_count` | int unsigned | não | `0` | Instalações colocadas na fila quando o envio começou |
| `sent_count` | int unsigned | não | `0` | Mensagens aceitas pelo FCM (aceite não prova entrega) |
| `failed_count` | int unsigned | não | `0` | Mensagens com falha definitiva |
| `skipped_count` | int unsigned | não | `0` | Mensagens descartadas (limite semanal, opt-out, expiração) |
| `created_by` | int unsigned | sim |  | Operador que criou (FK admin_users.id); NULL se criada pelo sistema |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de criação |
| `started_at` | datetime(6) | sim |  | Instante UTC em que a fila foi montada; NULL antes do envio |
| `completed_at` | datetime(6) | sim |  | Instante UTC do fim do envio ou cancelamento; NULL enquanto em andamento |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_campaigns_created_by` | created_by | não | Atende a FK created_by |
| `ix_campaigns_status_schedule` | status,scheduled_at | não | Seleção pelo cron das campanhas a iniciar |
| `PRIMARY` | id | sim | Chave interna |
| `uq_campaigns_public_id` | public_id | sim | Código público único da campanha |

## `notification_events`

Eventos de engajamento com notificações push (domínio: LiveOps)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do evento de notificação |
| `player_id` | bigint unsigned | não |  | Jogador que abriu a notificação (FK players.id) |
| `notification_id` | varchar(64) | não |  | Identificador da notificação vindo do campo data do push (ex.: N-123) |
| `campaign_id` | varchar(64) | sim |  | Campanha de origem informada no push; NULL para notificações operacionais |
| `event_type` | varchar(16) | não |  | Tipo: opened (toque do jogador) |
| `occurred_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do registro |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_notification_events_campaign` | campaign_id,event_type | não | Contagem de aberturas por campanha no dashboard |
| `PRIMARY` | id | sim | Chave interna |
| `uq_notification_events_once` | player_id,notification_id,event_type | sim | Invariante: abertura contada uma vez por jogador e notificação; atende a FK |

## `notification_outbox`

Fila durável de envio FCM com nova tentativa e status distintos (domínio: LiveOps)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da tarefa de envio (vira o notification_id do push) |
| `campaign_id` | int unsigned | não |  | Campanha da mensagem (FK notification_campaigns.id) |
| `device_id` | bigint unsigned | não |  | Instalação de destino (FK player_devices.id) |
| `player_id` | bigint unsigned | não |  | Jogador de destino (FK players.id), para limite semanal e auditoria |
| `status` | varchar(16) | não | `pending` | Estado: pending (na fila), sent (aceita pelo FCM), failed (erro definitivo), skipped (descartada pela política) |
| `attempts` | smallint unsigned | não | `0` | Tentativas de envio feitas |
| `scheduled_at` | datetime(6) | não |  | Instante UTC da próxima tentativa (backoff exponencial com jitter em falhas temporárias) |
| `last_error` | varchar(160) | sim |  | Último erro do FCM, sem dados pessoais; NULL sem erro |
| `fcm_message_id` | varchar(160) | sim |  | Identificador devolvido pelo FCM no aceite; NULL antes do aceite |
| `sent_at` | datetime(6) | sim |  | Instante UTC do aceite pelo FCM; NULL se não aceita |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC em que entrou na fila |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_outbox_device` | device_id | não | Atende a FK device_id |
| `ix_outbox_player_sent` | player_id,status,sent_at | não | Contagem de pushes promocionais por jogador na semana; atende a FK player_id |
| `ix_outbox_status_schedule` | status,scheduled_at,id | não | Seleção ordenada das tarefas elegíveis pelo cron |
| `PRIMARY` | id | sim | Chave interna |
| `uq_outbox_campaign_device` | campaign_id,device_id | sim | Invariante: no máximo uma mensagem por campanha e instalação; atende a FK campaign_id |

## `player_consents`

Histórico append-only de preferências de notificação e permissões (domínio: privacidade)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do registro de consentimento |
| `player_id` | bigint unsigned | não |  | Jogador que registrou a preferência (FK players.id) |
| `consent_type` | varchar(32) | não |  | Tipo: notify_operational (avisos do jogo), notify_promotional (ofertas) ou os_notification_permission (estado da permissão do sistema) |
| `granted` | tinyint(1) | não |  | Valor registrado: 1 concedido, 0 negado/retirado |
| `source` | varchar(32) | não |  | Origem do registro: app_settings, os_prompt, api |
| `recorded_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do registro; o mais recente por tipo é o estado vigente |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_consents_player_type` | player_id,consent_type,recorded_at,id | não | Leitura do estado vigente por tipo e histórico do jogador; atende a FK player_id |
| `PRIMARY` | id | sim | Chave interna; ordem de inserção desempata registros no mesmo instante |

## `player_devices`

Instalações do app e tokens FCM por jogador (domínio: notificações)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da instalação |
| `public_id` | binary(16) | não |  | Identificador público da instalação, usado em DELETE /devices/{id} |
| `player_id` | bigint unsigned | não |  | Jogador dono da instalação (FK players.id) |
| `installation_id` | varchar(64) | não |  | Identificador aleatório gerado pelo app na instalação; não é ID de hardware |
| `platform` | varchar(16) | não |  | Plataforma da instalação: android ou ios |
| `fcm_token` | varchar(512) | sim |  | Token de registro do Firebase Cloud Messaging; NULL sem permissão ou após invalidação |
| `fcm_token_hash` | char(64) | sim |  | SHA-256 (hex) do token FCM para unicidade e busca; NULL quando fcm_token é NULL |
| `app_version` | varchar(32) | sim |  | Versão do app informada no último registro (ex.: 0.3.0); NULL se não informada |
| `locale` | varchar(16) | sim |  | Idioma do aparelho no último registro; NULL se não informado |
| `timezone` | varchar(64) | sim |  | Fuso IANA do aparelho (ex.: America/Sao_Paulo) para horário de silêncio; NULL se não informado |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do primeiro registro da instalação |
| `last_seen_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do último registro/atualização |
| `revoked_at` | datetime(6) | sim |  | Instante UTC da revogação (logout do aparelho, token inválido, exclusão); NULL enquanto ativa |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | id | sim | Chave interna da instalação |
| `uq_devices_fcm_token_hash` | fcm_token_hash | sim | Um token FCM aponta para uma única instalação ativa |
| `uq_devices_player_installation` | player_id,installation_id | sim | Uma linha por instalação de cada jogador; atende a FK player_id |
| `uq_devices_public_id` | public_id | sim | Unicidade do identificador público da instalação |

## `player_identities`

Vínculos de login de cada jogador (domínio: identidade). Nunca une contas por e-mail

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do vínculo de identidade |
| `player_id` | bigint unsigned | não |  | Jogador dono do vínculo (FK players.id) |
| `provider` | varchar(16) | não |  | Provedor: guest (visitante com segredo do servidor), google ou facebook |
| `subject` | varchar(191) | não |  | Identificador estável do usuário no provedor (sub do Google, user_id do Facebook, guest_id do visitante) |
| `secret_hash` | char(64) | sim |  | HMAC-SHA256 (hex) do segredo do visitante com APP_KEY; NULL para provedores externos |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC em que o vínculo foi criado |
| `last_used_at` | datetime(6) | sim |  | Instante UTC do último login por este vínculo; NULL se nunca usado após a criação |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | id | sim | Chave interna do vínculo |
| `uq_identities_player_provider` | player_id,provider | sim | Invariante: no máximo um vínculo por provedor em cada jogador; também atende a FK player_id |
| `uq_identities_provider_subject` | provider,subject | sim | Invariante: uma identidade de provedor pertence a no máximo um jogador |

## `player_save_versions`

Histórico limitado (SAVE_HISTORY revisões) de saves substituídos (domínio: persistência)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da cópia histórica |
| `player_id` | bigint unsigned | não |  | Jogador dono da cópia (FK players.id) |
| `revision` | int unsigned | não |  | Revisão que esta cópia representava antes de ser substituída |
| `schema_version` | smallint unsigned | não |  | Versão do formato do save desta cópia |
| `snapshot` | json | não |  | Conteúdo da revisão substituída, para recuperação pelo suporte |
| `saved_at` | datetime(6) | não |  | Instante UTC em que a revisão substituída havia sido gravada |
| `archived_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC em que a revisão foi movida para o histórico |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | id | sim | Chave interna da cópia |
| `uq_save_versions_player_revision` | player_id,revision | sim | Uma cópia por revisão de cada jogador; ordena a poda do histórico; atende a FK |

## `player_saves`

Save na nuvem corrente de cada jogador (domínio: persistência)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `player_id` | bigint unsigned | não |  | Jogador dono do save (FK players.id); um save corrente por jogador |
| `revision` | int unsigned | não |  | Revisão monotônica do save; começa em 1 e cresce a cada POST /sync aceito |
| `schema_version` | smallint unsigned | não |  | Versão do formato do save definida pelo app (App.SAVE_VERSION) |
| `snapshot` | json | não |  | Snapshot do estado do jogo enviado pelo app; saldos de moedas nele são ignorados (servidor é autoridade) |
| `snapshot_bytes` | int unsigned | não |  | Tamanho em bytes do JSON do snapshot, para limites e monitoramento |
| `client_saved_at` | datetime(6) | sim |  | Instante informado pelo app para o save (relógio do aparelho, só informativo); NULL se ausente |
| `updated_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do servidor em que esta revisão foi gravada |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | player_id | sim | Um save corrente por jogador; também atende a FK |

## `player_sessions`

Sessões do app com token de acesso curto e refresh rotativo (domínio: identidade)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da sessão |
| `public_id` | binary(16) | não |  | Identificador público opaco da sessão (usado em logs e logout por dispositivo) |
| `player_id` | bigint unsigned | não |  | Jogador autenticado nesta sessão (FK players.id) |
| `access_hash` | char(64) | não |  | HMAC-SHA256 (hex) do token de acesso atual; o token em texto nunca é gravado |
| `access_expires_at` | datetime(6) | não |  | Instante UTC de expiração do token de acesso (curto, padrão 1 hora) |
| `refresh_hash` | char(64) | não |  | HMAC-SHA256 (hex) do refresh token atual; troca a cada /auth/refresh |
| `previous_refresh_hash` | char(64) | sim |  | HMAC do refresh token anterior; reapresentá-lo indica roubo e revoga a sessão. NULL antes da primeira rotação |
| `refresh_expires_at` | datetime(6) | não |  | Instante UTC de expiração do refresh token (padrão 30 dias, renovado a cada rotação) |
| `login_provider` | varchar(16) | não |  | Provedor usado para abrir a sessão: guest, google ou facebook |
| `user_agent` | varchar(255) | sim |  | User-Agent do app ao abrir a sessão (truncado em 255); NULL se ausente |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de abertura da sessão |
| `rotated_at` | datetime(6) | sim |  | Instante UTC da última rotação de tokens; NULL se nunca rotacionada |
| `revoked_at` | datetime(6) | sim |  | Instante UTC de revogação (logout, reuso de refresh, exclusão); NULL enquanto válida |
| `revoke_reason` | varchar(32) | sim |  | Motivo da revogação: logout, refresh_reuse, account_deleted, admin; NULL enquanto válida |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_sessions_player` | player_id,revoked_at | não | Revogação de todas as sessões ativas do jogador; atende a FK player_id |
| `ix_sessions_previous_refresh` | previous_refresh_hash | não | Detecção de reuso de refresh token já rotacionado |
| `ix_sessions_refresh_expiry` | refresh_expires_at | não | Limpeza periódica de sessões expiradas pelo cron |
| `PRIMARY` | id | sim | Chave interna da sessão |
| `uq_sessions_access_hash` | access_hash | sim | Autenticação de cada requisição pelo hash do token de acesso |
| `uq_sessions_public_id` | public_id | sim | Unicidade do identificador público da sessão |
| `uq_sessions_refresh_hash` | refresh_hash | sim | Localização da sessão no /auth/refresh |

## `players`

Contas de jogador (domínio: identidade). Uma fazenda por jogador

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do jogador; nunca exposto ao cliente |
| `public_id` | binary(16) | não |  | Identificador público opaco (UUID v4 binário) exposto ao app como player_id |
| `status` | varchar(24) | não | `active` | Estado da conta: active, deletion_requested (exclusão pedida, sessões revogadas) ou deleted (dados pessoais removidos) |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de criação da conta (primeiro acesso como visitante ou por provedor) |
| `last_seen_at` | datetime(6) | sim |  | Instante UTC da última requisição autenticada; NULL até o primeiro uso de token |
| `locale` | varchar(16) | sim |  | Idioma informado pelo app (ex.: pt_BR, es, en); NULL quando não informado |
| `deletion_requested_at` | datetime(6) | sim |  | Instante UTC em que o jogador pediu exclusão via DELETE /me; NULL se nunca pediu |
| `deleted_at` | datetime(6) | sim |  | Instante UTC em que o purge removeu os dados pessoais; NULL enquanto não executado |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_players_last_seen` | last_seen_at,id | não | Consultas de atividade (DAU/MAU, segmentação por última atividade) |
| `ix_players_status_deletion` | status,deletion_requested_at | não | Seleção pelo cron das contas com exclusão pendente após a carência |
| `PRIMARY` | id | sim | Chave interna compacta para FKs |
| `uq_players_public_id` | public_id | sim | Busca do jogador pelo identificador público e garantia de unicidade |

## `rate_limits`

Contadores de rate limit por janela fixa (domínio: segurança)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `bucket` | char(64) | não |  | SHA-256 de (regra + IP ou jogador); nunca guarda o IP em claro |
| `window_start` | datetime | não |  | Início UTC da janela fixa de contagem |
| `hits` | int unsigned | não | `1` | Quantidade de requisições contadas na janela |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_rate_limits_window` | window_start | não | Limpeza periódica das janelas antigas pelo cron |
| `PRIMARY` | bucket,window_start | sim | Contador único por balde e janela |

## `remote_config_versions`

Versões de Remote Config com histórico e rollback (domínio: operação)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | int unsigned | não |  | Identificador interno da versão de configuração |
| `environment` | varchar(16) | não |  | Ambiente: local, staging ou production |
| `version_number` | int unsigned | não |  | Número sequencial da versão dentro do ambiente, visível ao app |
| `status` | varchar(16) | não |  | Estado: draft (rascunho), published (vigente quando for a maior compatível), retired (retirada por rollback) |
| `min_client_version` | varchar(32) | não | `0.0.0` | Menor versão do app que pode receber esta configuração (semver) |
| `max_client_version` | varchar(32) | sim |  | Maior versão do app compatível; NULL sem limite superior |
| `payload` | json | não |  | Parâmetros públicos tipados (flags, limites); nunca contém segredos |
| `checksum` | char(64) | não |  | SHA-256 do payload canônico; usado como ETag |
| `changelog` | varchar(500) | não |  | Descrição humana da mudança, obrigatória para publicar |
| `created_by` | varchar(64) | não |  | Quem criou a versão (usuário admin ou cli) |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de criação |
| `published_at` | datetime(6) | sim |  | Instante UTC da publicação; NULL em rascunho |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_remote_config_env_status` | environment,status,version_number | não | Busca da maior versão publicada compatível em GET /config |
| `PRIMARY` | id | sim | Chave interna |
| `uq_remote_config_env_version` | environment,version_number | sim | Número de versão único por ambiente |

## `reward_grants`

Benefícios concedidos a jogadores e seu resgate idempotente (domínio: recompensas)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do benefício |
| `public_id` | binary(16) | não |  | Identificador público do benefício usado em POST /rewards/{id}/claim |
| `player_id` | bigint unsigned | não |  | Jogador elegível (FK players.id) |
| `rule_key` | varchar(64) | não |  | Regra ou campanha que concedeu (ex.: welcome_v1, comeback_3d_v1, admin_manual) |
| `occurrence_key` | varchar(100) | não |  | Ocorrência da regra (ex.: once, 2026-W48); garante um benefício por ocorrência |
| `currency` | varchar(8) | sim |  | Moeda do benefício (cash ou gold); NULL quando o benefício é só um direito |
| `amount` | bigint unsigned | sim |  | Quantidade inteira da moeda; NULL quando currency é NULL |
| `entitlement_key` | varchar(64) | sim |  | Direito permanente concedido no resgate; NULL quando não houver |
| `status` | varchar(16) | não | `available` | Estado: available (pode resgatar), claimed (resgatado), expired, revoked |
| `expires_at` | datetime(6) | sim |  | Instante UTC limite para resgate; NULL sem expiração |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da concessão (registrada antes de qualquer notificação) |
| `claimed_at` | datetime(6) | sim |  | Instante UTC do resgate; NULL se não resgatado |
| `ledger_id` | bigint unsigned | sim |  | Lançamento do resgate (FK economy_ledger.id); NULL antes do resgate ou sem moeda |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_reward_grants_ledger` | ledger_id | não | Atende a FK ledger_id e auditoria do resgate |
| `ix_reward_grants_player_status` | player_id,status,expires_at | não | Listagem de benefícios disponíveis em GET /rewards |
| `PRIMARY` | id | sim | Chave interna |
| `uq_reward_grants_occurrence` | player_id,rule_key,occurrence_key | sim | Invariante: um benefício por regra e ocorrência para cada jogador; atende a FK player_id |
| `uq_reward_grants_public_id` | public_id | sim | Unicidade do identificador público |

## `reward_rules`

Motor de regras declarativo de benefícios automáticos, versionado (domínio: recompensas)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | int unsigned | não |  | Identificador interno da versão da regra |
| `rule_key` | varchar(48) | não |  | Chave estável da regra (ex.: welcome, comeback_3d) |
| `version` | smallint unsigned | não |  | Versão imutável; mudar condição ou benefício cria nova versão |
| `description` | varchar(200) | não |  | Descrição humana da regra |
| `conditions` | json | não |  | Condições tipadas (lista de {"type":..., parâmetros}); nunca código executável |
| `occurrence` | varchar(8) | não |  | Frequência da concessão por jogador: once, day, week ou month |
| `currency` | varchar(8) | sim |  | Moeda do benefício (cash/gold); NULL quando só concede direito |
| `amount` | bigint unsigned | sim |  | Quantidade da moeda do benefício; NULL quando currency é NULL |
| `entitlement_key` | varchar(64) | sim |  | Direito permanente concedido; NULL quando não houver |
| `expires_hours` | smallint unsigned | sim |  | Horas para resgatar depois da concessão; NULL sem expiração |
| `max_grants_per_run` | int unsigned | não | `1000` | Teto de concessões por execução (orçamento/limite de público) |
| `notify_campaign_id` | int unsigned | sim |  | Campanha operacional usada para avisar o jogador (FK notification_campaigns.id); NULL sem aviso |
| `status` | varchar(16) | não | `paused` | Estado: active (avaliada pelo cron), paused, retired (substituída por versão nova) |
| `created_by` | int unsigned | sim |  | Operador que criou a versão (FK admin_users.id); NULL se pelo sistema |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC de criação da versão |
| `last_run_at` | datetime(6) | sim |  | Instante UTC da última avaliação pelo cron; NULL se nunca rodou |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_reward_rules_campaign` | notify_campaign_id | não | Atende a FK notify_campaign_id |
| `ix_reward_rules_created_by` | created_by | não | Atende a FK created_by |
| `ix_reward_rules_status` | status | não | Seleção das regras ativas pelo cron |
| `PRIMARY` | id | sim | Chave interna |
| `uq_reward_rules_key_version` | rule_key,version | sim | Versão única por regra |

## `rule_executions`

Histórico de avaliações das regras de benefício (domínio: recompensas)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno da execução |
| `rule_id` | int unsigned | não |  | Versão de regra executada (FK reward_rules.id) |
| `dry_run` | tinyint(1) | não |  | 1 simulação (não concede), 0 execução real |
| `eligible_count` | int unsigned | não |  | Jogadores que atenderam às condições |
| `granted_count` | int unsigned | não |  | Benefícios novos concedidos (0 em simulação) |
| `started_at` | datetime(6) | não |  | Instante UTC do início |
| `finished_at` | datetime(6) | não |  | Instante UTC do fim |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_rule_executions_rule` | rule_id,id | não | Histórico por regra; atende a FK |
| `PRIMARY` | id | sim | Chave interna |

## `schema_migrations`

Controle de versões do schema do backend TerraBela Farm (domínio: plataforma)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `version` | varchar(64) | não |  | Nome do arquivo de migration aplicado, sem extensão (ex.: 001_core) |
| `applied_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC em que a migration terminou de ser aplicada |
| `checksum` | char(64) | sim |  | SHA-256 do arquivo SQL aplicado pelo runner; NULL quando importado manualmente pelo phpMyAdmin |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | version | sim | Uma linha por migration; impede aplicar a mesma versão duas vezes |

## `sync_operations`

Registro de idempotência de comandos de sincronização (domínio: persistência)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `id` | bigint unsigned | não |  | Identificador interno do registro de idempotência |
| `player_id` | bigint unsigned | não |  | Jogador que enviou a operação (FK players.id) |
| `operation_id` | varchar(64) | não |  | Identificador estável gerado pelo app para a operação; repetir devolve a resposta original |
| `operation_type` | varchar(16) | não |  | Tipo da operação: save (POST /sync) |
| `request_hash` | char(64) | não |  | SHA-256 do corpo normalizado; mesmo operation_id com corpo diferente é rejeitado |
| `response_status` | smallint unsigned | não |  | Código HTTP da resposta original |
| `response_body` | json | não |  | Corpo JSON da resposta original devolvido em repetições |
| `created_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC do processamento original |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `ix_sync_operations_created` | created_at | não | Poda periódica de registros antigos pelo cron |
| `PRIMARY` | id | sim | Chave interna |
| `uq_sync_operations_player_op` | player_id,operation_id | sim | Invariante de idempotência: operation_id único por jogador; atende a FK |

## `wallets`

Saldos correntes cash/gold; só alterados junto com economy_ledger na mesma transação (domínio: economia)

| Coluna | Tipo | Nulo | Padrão | Descrição |
| --- | --- | --- | --- | --- |
| `player_id` | bigint unsigned | não |  | Jogador dono da carteira (FK players.id) |
| `cash_balance` | bigint unsigned | não | `0` | Saldo de cash (moeda comum do jogo) em unidades inteiras; projeção do economy_ledger |
| `gold_balance` | bigint unsigned | não | `0` | Saldo de gold (moeda premium) em unidades inteiras; projeção do economy_ledger |
| `version` | int unsigned | não | `0` | Contador de alterações; cresce 1 a cada lançamento no ledger |
| `updated_at` | datetime(6) | não | `CURRENT_TIMESTAMP(6)` | Instante UTC da última alteração de saldo |

| Índice | Colunas | Único | Descrição |
| --- | --- | --- | --- |
| `PRIMARY` | player_id | sim | Uma carteira por jogador; linha travada com FOR UPDATE em cada lançamento |

## Constraints

| Tabela | Constraint | Tipo |
| --- | --- | --- |
| `admin_audit_log` | `fk_admin_audit_user` | FOREIGN KEY |
| `admin_sessions` | `ck_admin_sessions_mfa` | CHECK |
| `admin_sessions` | `fk_admin_sessions_user` | FOREIGN KEY |
| `admin_users` | `ck_admin_users_role` | CHECK |
| `admin_users` | `ck_admin_users_status` | CHECK |
| `admin_users` | `ck_admin_users_totp` | CHECK |
| `economy_ledger` | `ck_ledger_amount_nonzero` | CHECK |
| `economy_ledger` | `ck_ledger_currency` | CHECK |
| `economy_ledger` | `ck_ledger_source` | CHECK |
| `economy_ledger` | `fk_ledger_player` | FOREIGN KEY |
| `entitlements` | `ck_entitlements_source` | CHECK |
| `entitlements` | `fk_entitlements_player` | FOREIGN KEY |
| `game_events` | `fk_game_events_player` | FOREIGN KEY |
| `iap_events` | `ck_iap_events_source` | CHECK |
| `iap_events` | `fk_iap_events_transaction` | FOREIGN KEY |
| `iap_products` | `ck_iap_products_active` | CHECK |
| `iap_products` | `ck_iap_products_type` | CHECK |
| `iap_transactions` | `ck_iap_tx_finalize` | CHECK |
| `iap_transactions` | `ck_iap_tx_state` | CHECK |
| `iap_transactions` | `fk_iap_tx_player` | FOREIGN KEY |
| `iap_transactions` | `fk_iap_tx_product` | FOREIGN KEY |
| `notification_campaigns` | `ck_campaigns_category` | CHECK |
| `notification_campaigns` | `ck_campaigns_route` | CHECK |
| `notification_campaigns` | `ck_campaigns_status` | CHECK |
| `notification_campaigns` | `fk_campaigns_created_by` | FOREIGN KEY |
| `notification_events` | `ck_notification_events_type` | CHECK |
| `notification_events` | `fk_notification_events_player` | FOREIGN KEY |
| `notification_outbox` | `ck_outbox_status` | CHECK |
| `notification_outbox` | `fk_outbox_campaign` | FOREIGN KEY |
| `notification_outbox` | `fk_outbox_device` | FOREIGN KEY |
| `notification_outbox` | `fk_outbox_player` | FOREIGN KEY |
| `player_consents` | `ck_consents_granted` | CHECK |
| `player_consents` | `fk_consents_player` | FOREIGN KEY |
| `player_devices` | `ck_devices_platform` | CHECK |
| `player_devices` | `fk_devices_player` | FOREIGN KEY |
| `player_identities` | `ck_identities_provider` | CHECK |
| `player_identities` | `fk_identities_player` | FOREIGN KEY |
| `player_save_versions` | `fk_save_versions_player` | FOREIGN KEY |
| `player_saves` | `ck_saves_revision` | CHECK |
| `player_saves` | `fk_saves_player` | FOREIGN KEY |
| `player_sessions` | `fk_sessions_player` | FOREIGN KEY |
| `players` | `ck_players_status` | CHECK |
| `remote_config_versions` | `ck_remote_config_env` | CHECK |
| `remote_config_versions` | `ck_remote_config_status` | CHECK |
| `reward_grants` | `ck_reward_grants_currency` | CHECK |
| `reward_grants` | `ck_reward_grants_status` | CHECK |
| `reward_grants` | `fk_reward_grants_ledger` | FOREIGN KEY |
| `reward_grants` | `fk_reward_grants_player` | FOREIGN KEY |
| `reward_rules` | `ck_reward_rules_currency` | CHECK |
| `reward_rules` | `ck_reward_rules_occurrence` | CHECK |
| `reward_rules` | `ck_reward_rules_status` | CHECK |
| `reward_rules` | `fk_reward_rules_campaign` | FOREIGN KEY |
| `reward_rules` | `fk_reward_rules_created_by` | FOREIGN KEY |
| `rule_executions` | `ck_rule_executions_dry` | CHECK |
| `rule_executions` | `fk_rule_executions_rule` | FOREIGN KEY |
| `sync_operations` | `fk_sync_operations_player` | FOREIGN KEY |
| `wallets` | `fk_wallets_player` | FOREIGN KEY |

Views, triggers, rotinas e events: nenhum (por decisão: sem objetos sem finalidade comprovada).
