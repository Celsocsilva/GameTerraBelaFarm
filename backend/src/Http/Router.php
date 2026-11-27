<?php
declare(strict_types=1);

namespace TerraBela\Http;

final class Router
{
    /** @var list<array{method:string,regex:string,names:list<string>,handler:callable,opts:array<string,mixed>}> */
    private array $routes = [];

    /** @param array{auth?:bool,rate?:string,max_body?:int} $opts */
    public function add(string $method, string $pattern, callable $handler, array $opts = []): void
    {
        $names = [];
        $regex = preg_replace_callback('/\{([a-z_]+)\}/', static function ($m) use (&$names) {
            $names[] = $m[1];
            return '([A-Za-z0-9_.:-]{1,100})';
        }, $pattern);
        $this->routes[] = [
            'method' => $method,
            'regex' => '#^' . $regex . '$#',
            'names' => $names,
            'handler' => $handler,
            'opts' => $opts,
        ];
    }

    /** @return array{0:callable,1:array<string,mixed>,2:array<string,string>} */
    public function match(string $method, string $path): array
    {
        $allowed = [];
        foreach ($this->routes as $r) {
            if (!preg_match($r['regex'], $path, $m)) {
                continue;
            }
            if ($r['method'] !== $method) {
                $allowed[] = $r['method'];
                continue;
            }
            $params = [];
            foreach ($r['names'] as $i => $name) {
                $params[$name] = $m[$i + 1];
            }
            return [$r['handler'], $r['opts'], $params];
        }
        if ($allowed) {
            throw new ApiException(405, 'method_not_allowed', 'Método não permitido para esta rota.', ['allowed' => $allowed]);
        }
        throw new ApiException(404, 'not_found', 'Rota não encontrada.');
    }
}
