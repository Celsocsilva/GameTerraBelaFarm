<?php
declare(strict_types=1);

namespace TerraBela\Auth;

/** Identidade confirmada junto ao provedor (nunca autodeclarada pelo cliente). */
final class ProviderIdentity
{
    public function __construct(
        public readonly string $provider,
        public readonly string $subject,
    ) {
    }
}
