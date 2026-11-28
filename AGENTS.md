# Regras de manutenção do Exodus Hub

## Testes essenciais

Mantenha somente verificações essenciais de permissões, APIs internas, contratos,
exports, dependências, sintaxe/compilação Luau e análise básica de globais.
Verificações de integridade dos catálogos e arquivos gerados também são permitidas.

Não crie nem mantenha suítes extras de comportamento, layout, animações,
funcionalidades, downloads, loader, informações ou auto execute sem pedido
explícito do usuário. Corrigir uma funcionalidade não autoriza adicionar esses testes.

## Documentação e entrega

Crie ou altere documentação somente quando o usuário pedir explicitamente.
Este arquivo registra a política solicitada pelo usuário.

Faça as alterações diretamente na main, em um único commit por solicitação.
Não crie branches ou pull requests. Todas as alterações devem ser feitas na main.

## Fronteiras da interface e dos jogos

Somente código com origem em `ui/` pode criar, clonar ou montar interface.
Implementação dos componentes, notificações, Mini UI, animações e criação de
Instances visuais pertencem a essa pasta. Declarações de páginas, escolha de
componentes, valores e callbacks ficam no consumidor e usam a API da biblioteca.
Qualquer módulo pode consumir essa API; não obrigue configurações dos jogos a
ficarem em `ui/`. A biblioteca não conhece jogos, pasta de integrações ou loader.
O loader pode executar o bootstrap visual gerado de fontes de `ui/`; não mantenha
uma segunda implementação visual no loader. Jogos e universais fornecem funções,
estados e dados e consomem a API visual, sem construir elementos gráficos.
Toda Mini UI usa o mesmo componente, com formato quadrado arredondado ou redondo,
cor, indicador de ativo e tamanho configuráveis pela API. Transições são animadas.
Páginas de uma coluna usam a mesma largura e centralização. Duas colunas mantêm
seus lados; não centralize uma coluna isolada de uma página de duas colunas.

Regras de acesso ficam somente em `hubs/access.luau`. Ausência de regra significa
acesso público. A estrutura interna dos jogos é livre; a descoberta é recursiva e
as dependências e exports devem cumprir os contratos da API.
Aplicações contínuas dos universais usam o agendador compartilhado, antes e depois
da simulação. Eventos e tarefas com orçamento não devem criar trabalho duplicado.
O Action deve gerar e validar o runtime e os catálogos a cada mudança na main.

## Contratos da arquitetura

Consulte [docs/architecture.md](docs/architecture.md). Estas regras correspondem
às fronteiras implementadas; não acrescente restrições sem relação com a tarefa.

- O loader transporta, verifica e inicia. Não contém opções, componentes ou lógica
  de jogos. Sua superfície visual de inicialização é gerada de fontes da UI.
- A biblioteca `ui/` implementa componentes e janelas genéricos. Recebe dados,
  bindings e callbacks. Não importa adaptadores de jogos, estado do hub, serviços
  do loader ou arquivos de configuração de consumidores.
- Jogos, universais e outros consumidores podem declarar páginas e controles e
  operar seus handles pela API. Não constroem, clonam ou montam Instances visuais
  diretamente. Não duplique um componente existente para um jogo.
- A composição conecta consumidores e biblioteca por APIs públicas. Nenhum módulo
  acessa `_G.Exodus.Context`/`Modules` para escapar de suas dependências declaradas.
- Exports e membros de dependências são declarados em `__contract`. A política
  interna é única e obrigatória; um jogo não a troca pelo manifesto.
- Configurações têm dono. Jogos escolhem defaults, migração e persistência apenas
  das próprias chaves. Para acompanhar outro recurso, use `options.get/observe`.
  Não escreva snapshots nem configurações de outro domínio.
- Mudanças de configuração têm uma rota de aplicação no módulo. Não duplique a
  ativação no callback da UI. Desligar libera o escopo de ativação e restaura as
  propriedades; `teardown` é idempotente, inclusive após falhas parciais.
- Universais contínuos usam o agendador nas fases anterior e posterior da simulação.
  Indexação e manutenção respeitam orçamento; não crie workers duplicados.
- Adicionar um componente ou módulo usa descoberta e contratos, sem registros
  manuais no loader. Catálogos e arquivos distribuídos são gerados e validados.
- Cada Mini UI tem tamanho independente. A escala geral da Config multiplica esses
  tamanhos sem sobrescrever os ajustes individuais. Ícones
  internos usam a máscara gerada e a cor única do tema `#DCE6FF`.
- Localização distingue metadados do servidor da aproximação do endpoint. País do
  jogador e ping baixo não são evidência do país do servidor.
