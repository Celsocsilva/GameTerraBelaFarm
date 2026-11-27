<?php
declare(strict_types=1);

namespace TerraBela\Admin;

/**
 * Papéis do backoffice. admin: tudo. operation: LiveOps (config, campanhas, regras, produtos).
 * support: atendimento (benefício a jogador, revogar sessões). read: somente leitura.
 */
final class Rbac
{
    public const ROLES = [
        'admin' => 'Administrador',
        'operation' => 'Operação (LiveOps)',
        'support' => 'Suporte',
        'read' => 'Somente leitura',
    ];

    private const PERMISSIONS = [
        'view' => ['admin', 'operation', 'support', 'read'],
        'players.support' => ['admin', 'support'],
        'wallet.adjust' => ['admin'],
        'config.publish' => ['admin', 'operation'],
        'products.manage' => ['admin', 'operation'],
        'campaigns.manage' => ['admin', 'operation'],
        'rules.manage' => ['admin', 'operation'],
        'audit.view' => ['admin', 'operation'],
        'users.manage' => ['admin'],
        'system.manage' => ['admin'],
    ];

    public static function can(string $role, string $permission): bool
    {
        return in_array($role, self::PERMISSIONS[$permission] ?? [], true);
    }
}
