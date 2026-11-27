<?php
declare(strict_types=1);

namespace TerraBela\Api;

use TerraBela\Auth\AuthContext;
use TerraBela\Core\Clock;
use TerraBela\Core\Db;
use TerraBela\Http\ApiException;
use TerraBela\Http\Request;

/** POST /events/batch (telemetria) e POST /notifications/{id}/open (abertura idempotente). */
final class EventsApi
{
    public const EVENT_NAMES = [
        'first_open', 'session_start', 'session_end', 'tutorial_step', 'tutorial_completed',
        'crop_planted', 'crop_harvested', 'sale_completed', 'level_up', 'helper_hired',
        'shop_view', 'purchase_started', 'notification_opened', 'reward_claimed',
    ];
    private const FORBIDDEN_KEYS = '/(e-?mail|token|password|senha|phone|telefone|secret|name|nome)/i';

    public function __construct(private Db $db, private Clock $clock)
    {
    }

    public function batch(Request $req, AuthContext $ctx): array
    {
        $in = $req->json(262144);
        $events = V::list($in, 'events', 1, 100);
        $accepted = 0;
        $duplicates = 0;
        $rejected = [];
        $maxFuture = $this->clock->now() + 86400;
        foreach ($events as $i => $e) {
            try {
                if (!is_array($e)) {
                    throw new ApiException(422, 'validation_failed', 'evento inválido');
                }
                $eventId = V::opId($e, 'event_id');
                $name = V::enum($e, 'name', self::EVENT_NAMES);
                $occurred = V::optTime($e, 'occurred_at') ?? $this->clock->sql();
                if (strtotime($occurred . ' UTC') > $maxFuture) {
                    throw new ApiException(422, 'validation_failed', 'occurred_at no futuro');
                }
                $props = $e['properties'] ?? null;
                $propsJson = null;
                if ($props !== null) {
                    if (!is_array($props)) {
                        throw new ApiException(422, 'validation_failed', 'properties deve ser objeto');
                    }
                    foreach (array_keys($props) as $k) {
                        if (preg_match(self::FORBIDDEN_KEYS, (string) $k)) {
                            throw new ApiException(422, 'validation_failed', "propriedade não permitida: $k");
                        }
                    }
                    $propsJson = json_encode($props, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
                    if (strlen((string) $propsJson) > 2048) {
                        throw new ApiException(422, 'validation_failed', 'properties acima de 2 KB');
                    }
                }
                $n = $this->db->exec(
                    'INSERT IGNORE INTO game_events (event_id, player_id, event_name, occurred_at, received_at, app_version, properties) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [$eventId, $ctx->playerId, $name, $occurred, $this->clock->sql(), V::optStr($e, 'app_version', 32), $propsJson]
                );
                $n > 0 ? $accepted++ : $duplicates++;
            } catch (ApiException $ex) {
                $rejected[] = ['index' => $i, 'message' => $ex->getMessage()];
            }
        }
        return ['accepted' => $accepted, 'duplicates' => $duplicates, 'rejected' => $rejected];
    }

    public function notificationOpen(Request $req, AuthContext $ctx): array
    {
        $id = $req->params['id'];
        $in = $req->json();
        $campaign = V::optStr($in, 'campaign_id', 64, '/^[A-Za-z0-9_.:-]+$/');
        $n = $this->db->exec(
            "INSERT IGNORE INTO notification_events (player_id, notification_id, campaign_id, event_type, occurred_at) VALUES (?, ?, ?, 'opened', ?)",
            [$ctx->playerId, $id, $campaign, $this->clock->sql()]
        );
        return ['recorded' => $n > 0, 'already_recorded' => $n === 0];
    }
}
