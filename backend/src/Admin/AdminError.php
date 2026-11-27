<?php
declare(strict_types=1);

namespace TerraBela\Admin;

/** Erro de negócio do backoffice com mensagem segura para mostrar ao operador. */
final class AdminError extends \RuntimeException
{
    public function __construct(string $message, public readonly ?int $adminId = null)
    {
        parent::__construct($message);
    }
}
