# Estrutura do Exodus

| Caminho | Responsabilidade |
| --- | --- |
| `exodus hub/loader.luau` | Entrada única; identifica o jogo e carrega a sessão |
| `exodus hub/core/` | Sessão, configurações, armazenamento, diagnóstico e integração |
| `exodus hub/universal/` | Recursos carregados em todos os jogos |
| `exodus hub/universal/anti_lag/` | Anti Lag, propriedades reversíveis e seleção espacial |
| `exodus hub/ui/` | Toda a interface, páginas, temas, ações e componentes |
| `exodus hub/ui/controllers/` | Janela, minis, spam, atalhos, notificações e informações |
| `exodus hub/ui/components/` | Componentes reutilizáveis |
| `exodus hub/ui/assets/` | Ícones e imagens |
| `exodus hub/hubs/<jogo>/` | Somente lógica e configuração específicas do jogo |
| `exodus hub/indeed/` | Ferramentas e verificações mínimas universais |
| `exodus hub/hubs/<jogo>/indeed/` | Ferramentas e verificações específicas do jogo |

## Phantom Ball

- `combat/`: funções ativas como Auto Parry, Auto Spam e habilidades.
- `prediction/`: geometria, previsão de dash e estatísticas de clash.
- `game/`: bola, jogadores, partida, cooldowns, remotes e adaptação nativa.
- `combat_loop.luau`: coordena as avaliações de combate.
- `game_runtime.luau`: conecta os eventos do jogo.
- `game_ui.luau`: apenas dados que configuram a UI compartilhada.
- `hub.json`: IDs, nome, autor, notificação e opções da integração.

## Carregamento e renomeação

O loader consulta o repositório pelo ID numérico `1334849119`. O endereço atual
é obtido pela API do GitHub; usuário e nome do repositório não ficam fixos no
loader. Os arquivos da sessão são baixados na mesma revisão imutável.
Depois de renomear o repositório, use seu novo endereço para obter o loader.

Place ID tem prioridade sobre Universe ID. Sempre são carregadas a base e a UI;
a lógica de um jogo só é baixada quando seus IDs correspondem.
O catálogo é gerado automaticamente a partir das pastas com `hub.json`.

`"permissions": true` habilita a política de permissões para a integração.
Sem essa opção, o arquivo de permissões não é baixado. O loader mantém somente
as verificações básicas de contratos, APIs e dependências.

## Arquivos reunidos

Sessão/estado, integração, diagnóstico, câmera, notificações, informações e
componentes básicos foram agrupados por responsabilidade. Dentro desses arquivos,
as APIs existentes permanecem em seções isoladas para preservar referências e
limpeza. Cada arquivo é baixado, compilado e executado uma vez por carregamento.
Auto Parry e Auto Spam continuam independentes.

[Adicionar jogos](../exodus%20hub/hubs/README.md) · [Verificações](development.md)
