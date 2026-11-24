# Estrutura atual

Exodus tem um loader, uma base universal e módulos específicos por jogo.
Todo jogo carrega a base universal. Quando há um ID cadastrado, o loader também
carrega os módulos da pasta correspondente.

| Caminho | Responsabilidade |
| --- | --- |
| `exodus hub/loader.luau` | Selecionar o jogo, baixar módulos e iniciar a sessão |
| `exodus hub/modules/core/` | Configuração, permissões, estado, ciclo de vida e ponte com o jogo |
| `exodus hub/modules/front/` | Toda a UI: componentes, páginas, mini UIs, spam, atalhos e animações |
| `exodus hub/modules/features/` | Funções universais, incluindo Auto Jump e câmera |
| `exodus hub/modules/render/` | Anti Lag geral e restauração de propriedades |
| `exodus hub/modules/tools/` | Dumper e navegação de servidores |
| `exodus hub/hubs/<jogo>/modules/` | Lógica específica do jogo e configuração declarativa da UI |
| `exodus hub/hubs/<jogo>/hub.json` | Nome, IDs, autor e notificação |
| `exodus hub/hubs/catalog.luau` | Catálogo gerado automaticamente; não editar à mão |
| `exodus hub/indeed/` | Testes e ferramentas universais |
| `exodus hub/hubs/<jogo>/indeed/` | Testes, ferramentas e diagnósticos exclusivos do jogo |

## Carregamento

1. O loader resolve uma revisão do repositório.
2. Consulta o catálogo; Place ID tem prioridade sobre Universe ID.
3. Baixa a base universal e, quando houver suporte, os módulos daquele jogo.
4. Valida contratos e dependências e calcula a ordem de inicialização.
5. Inicia a UI compartilhada usando a configuração do jogo e mostra a notificação.

Todos os downloads da sessão usam a mesma revisão. Um jogo sem suporte não baixa
a lógica do Phantom Ball. Módulos da base não podem ser substituídos por cópias
na pasta do jogo.

## Interface

Os componentes existem apenas em `modules/front/`, inclusive os controles de
spam e as mini UIs. O arquivo `gameui.luau` do jogo fornece somente dados:
`pages`, `additions`, `pageOrder` e `combatUI`. Não cria instâncias nem injeta UI.
A base combina essa configuração com as páginas universais.

## Jogos

A integração cadastrada é Phantom Ball, em `hubs/phantom-ball/`. Ela contém
combate, sincronização da bola, adaptador visual nativo e configurações próprias.
MM2 e outros jogos usam a base universal até receberem módulos específicos.

A configuração antiga do Phantom Ball permanece em `Exodus Hub`. As demais
sessões usam `Exodus Hub/hubs/<id>`. O README.md principal não faz parte desta
manutenção de documentação.

Veja [como adicionar um jogo](../exodus%20hub/hubs/README.md) e
[como verificar alterações](development.md).
