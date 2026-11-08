# ENV-002 — Evidências reais do rio e das pontes

Quadros renderizados pelo Godot 4.7.2 (Forward Mobile, Vulkan llvmpipe, 1280×720) com `tools/river_capture.gd`; o "antes" foi renderizado a partir do commit base `090b4d5` (ENV-001) com a mesma câmera. Nenhuma imagem é conceitual ou montagem, exceto as composições lado a lado (04b, 05b, 07c), que juntam quadros reais.

| Arquivo | Conteúdo | Vista |
|---|---|---|
| [01-vista-geral-rio.png](01-vista-geral-rio.png) | Rio integrado ao mapa inteiro: canteiros, balcão e as duas pontes | `wide` |
| [02-ponte-madeira.png](02-ponte-madeira.png) | Ponte de madeira com cordas e os dois acessos | `wood` |
| [03-ponte-pedra.png](03-ponte-pedra.png) | Ponte de pedra com lanternas | `stone` |
| [04-fazendeiro-ponte-madeira.png](04-fazendeiro-ponte-madeira.png) | Fazendeiro no meio da ponte de madeira, atrás do corrimão frontal | `wood_cross` |
| [04b-sequencia-travessia-madeira.png](04b-sequencia-travessia-madeira.png) | 4 quadros da travessia com a câmera do jogo | `wood_walk` |
| [05-fazendeiro-ponte-pedra.png](05-fazendeiro-ponte-pedra.png) | Fazendeiro no topo da ponte de pedra | `stone_cross` |
| [05b-sequencia-travessia-pedra.png](05b-sequencia-travessia-pedra.png) | 4 quadros da travessia com a câmera do jogo | `stone_walk` |
| [06a-margens-braco-norte.png](06a-margens-braco-norte.png) | Braço norte, curva e faixas de margem com flores | `north` |
| [06b-curva-sul.png](06b-curva-sul.png) | Curva de saída e curva grande | `curve` |
| [06c-juncao-retos.png](06c-juncao-retos.png) | Junção entre dois retos (peça complementar) | `focus --focus=-14.3,-3.4 --size=6` |
| [07a-antes.png](07a-antes.png) | Cenário antes (ENV-001) | base |
| [07b-depois.png](07b-depois.png) | Mesmo enquadramento depois | `overview` |
| [07c-antes-depois.png](07c-antes-depois.png) | Comparação lado a lado | — |
| [08-debug-colisoes.png](08-debug-colisoes.png) | Bloqueio da água (vermelho), travessias e caminhos dos acessos (verde) | `wide --debug` |
| [09-camera-do-jogo.png](09-camera-do-jogo.png) | Zoom e câmera padrão do jogo perto das pontes | `game` |
| [10-travessia-madeira.mp4](10-travessia-madeira.mp4) | Travessia completa da ponte de madeira (física real) | `wood_walk` |
| [11-travessia-pedra.mp4](11-travessia-pedra.mp4) | Travessia completa da ponte de pedra | `stone_walk` |
| [12-agua-animada.mp4](12-agua-animada.mp4) | 3 s da animação da água sobre uma junção | `water` |

Relatório dos testes: [../../RIVER_BRIDGES_QA.md](../../RIVER_BRIDGES_QA.md).
