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
Menu, notificações, Mini UI, animações e definições visuais pertencem a essa pasta.
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
