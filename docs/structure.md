# Estrutura

| Caminho | Responsabilidade |
| --- | --- |
| `exodus hub/loader.luau` | HTTP, cache, seleção do jogo e validação dos módulos |
| `core/bootstrap.luau` | Composição e inicialização da sessão |
| `core/session.luau` | Estado, configurações e encerramento |
| `core/updates.luau` | Consulta de revisões e espera por um estado seguro |
| `core/game_integration.luau` | Interface comum para os adaptadores dos jogos |
| `core/catalog.luau` | Catálogo gerado dos módulos compartilhados |
| `universal/` | Recursos independentes do jogo |
| `ui/` | Componentes, páginas, animações e controles compartilhados |
| `hubs/<jogo>/` | Regras, ações, indicadores e adaptações do jogo |
| `hubs/catalog.luau` | Catálogo gerado das integrações |
| `indeed/` | Ferramentas, testes e diagnósticos; fora da distribuição |

Os caminhos da tabela, exceto o loader, são relativos a `exodus hub/`.

O loader resolve o repositório pelo ID `1334849119`. Cada sessão usa uma única
revisão do GitHub. Place ID tem prioridade sobre Universe ID; jogos sem
integração recebem os recursos universais. Downloads iguais são reunidos;
fontes sem alteração são reutilizadas pelo hash do catálogo, com limite de 8 MiB.
Os módulos são executados e seus contratos são validados antes de encerrar a
sessão anterior. A inicialização segue as dependências; a limpeza ocorre na ordem
inversa, inclusive quando um `setup` falha.

No Phantom Ball, `combat/` contém as automações; `prediction/`, os cálculos;
`game/`, os dados e adaptações nativas. `game_runtime.luau` monta o adaptador;
`game_ui.luau` declara páginas e configurações. O código compartilhado não
consulta IDs, estados de partida ou caminhos nativos desse jogo.

[Adicionar jogos](../exodus%20hub/hubs/README.md) · [Desenvolvimento](development.md)
