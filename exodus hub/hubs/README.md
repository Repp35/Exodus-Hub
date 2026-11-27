# Adicionar um jogo

Crie `hubs/<id>/hub.json` com `title` e pelo menos um grupo de IDs reais:

```json
{
  "title": "Nome do jogo",
  "placeIds": [123456789],
  "universeIds": [987654321],
  "version": "1.0.0"
}
```

`id`, quando informado, deve coincidir com a pasta. `author`, `notification` e
`developers` são opcionais. Permissões e diretórios de armazenamento são definidos
pela base; o manifesto não os redefine.

Arquivos `.luau` entram recursivamente no catálogo, exceto `indeed/`. O nome do
arquivo sem `_` identifica o módulo. Não pode haver colisões com outros arquivos
da integração ou com módulos compartilhados. Cada arquivo exporta `__contract`,
`setup` e, quando possui recursos, `teardown`. O catálogo não é editado à mão.

`game_runtime.luau` exporta `bind(loaded)` e `createAPI(loaded)`. A composição recebe
as APIs próprias e os serviços públicos permitidos, não o contexto bruto do hub.
Pode devolver estes campos opcionais:

- `getUIConfig`: declarações de páginas e Mini UIs pela API do Exodus.
- `controls`: callbacks de ações do jogo; nomes reservados do hub são proibidos.
- `createActions(context)`: callbacks/estados e resolvers restritos aos controles do jogo.
- `observeState`: observação dos estados transitórios de suas ações.
- `readouts`: indicadores, com identificador e leitura.
- `updateBlockers`: leitores que impedem uma atualização durante uma ação em andamento.
- `miniVisibility`: regras de visibilidade que não alteram a escolha salva nem ativam a função.
- `migrateConfig`: recebe e altera somente chaves próprias/legadas da integração.
- `getJumpButton`: referência ao botão nativo de pulo, quando necessária.
- `getChoices`, `getGameContext` e os leitores de disponibilidade de habilidades.

Configurações de controles podem ficar no próprio módulo ou em `game_ui.luau`,
na pasta do jogo. Também é possível usar `UI.addPage`, `page.addSection` e os
componentes retornados, como `section.toggle`. Só a biblioteca cria os elementos
visuais; o consumidor declara suas opções e callbacks.

Páginas de jogo não renomeiam, reordenam ou substituem páginas compartilhadas.
`pageOrder` ordena apenas as páginas da própria integração. Uma extensão da página
Universal usa `additions` com `page = "indeed"` e `sectionTitle`; ela é uma seção
nova, sem modificar controles existentes. Os schemas pertencem aos respectivos
módulos e podem escolher `persistent` apenas para suas próprias configurações.

Uma extensão que depende de um universal usa `options.get/isEnabled/observe`.
Veja `hubs/phantom-ball/game/performance.luau`: o jogo acompanha Anti Lag e administra
seus próprios recursos, enquanto o universal continua independente do jogo.

A referência dos limites e exemplos está em [Arquitetura](../../docs/architecture.md).
Execute os comandos de [desenvolvimento](../../docs/development.md) para gerar e
validar runtime, permissões, contratos e catálogos.
