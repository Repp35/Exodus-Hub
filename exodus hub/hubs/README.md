# Adicionar um jogo

Todo jogo carrega os módulos universais e a mesma UI de `../modules/`.
A pasta do jogo contém somente sua lógica específica e a configuração do que
aparece na UI. Não copie nem substitua módulos da base.

## Cadastro e descoberta automática

Crie `hubs/nome-do-jogo/hub.json`:

```json
{
  "title": "Nome do jogo",
  "placeIds": [123456789],
  "universeIds": [987654321]
}
```

Troque pelos IDs reais. Um dos grupos de IDs basta. O identificador é o nome da
pasta. `author` e `notification` são opcionais; o autor padrão é
`deltapolinha_2915` e a notificação padrão usa o título.

Coloque os módulos `.luau` em subpastas de `modules/`. O nome do arquivo é sua
chave: `movement.luau` registra `movement`. Não repita nomes na mesma integração
nem use nomes já existentes na base universal.

O workflow encontra os arquivos e gera `catalog.luau`. Não é necessário editar
o loader, o registro ou uma lista de scripts. A ordem vem das dependências.

## Contrato de módulo

```lua
local Feature = {}
function Feature.setup(deps)
  return true
end
function Feature.teardown()
  return true
end
Feature.__contract = {
  provides = { "setup", "teardown" },
  requires = {},
}
return Feature
```

Declare dependências em `requires` e seus métodos em `requiresMethods`.
Libere conexões, tarefas e alterações no `teardown`. Siga as famílias da base:
`modules/core/`, `modules/game/`, `modules/combat/`, `modules/render/` e
`modules/front/`.

## Configurar a UI

Use um módulo `modules/front/app/gameui.luau` com `definition` declarada como
dado público no contrato. A configuração aceita:

| Campo | Uso |
| --- | --- |
| `pages` | Páginas do jogo usando os componentes existentes |
| `additions` | Controles adicionais em uma página existente |
| `pageOrder` | Ordem dos IDs das páginas |
| `combatUI` | Habilitar os controles compartilhados de combate |

Configurações próprias ficam em `__config.schema` e `__config.defaults`.
Não repita as configurações universais. Veja o `gameui.luau` do Phantom Ball.
Nenhum script de jogo cria componentes ou injeta UI.

Eventos específicos podem ser conectados por `modules/core/gameruntime.luau`,
exportando `bind`. A ponte `hubapi` fornece acessos opcionais aos módulos nativos;
a UI continua pertencendo à base.

[Mapa da estrutura](../../docs/structure.md) ·
[Verificações](../../docs/development.md)

## Testes do jogo

Coloque testes em `indeed/tests/`, diagnósticos em `indeed/diagnostics/` e
ferramentas auxiliares no `indeed/` do próprio jogo. Não coloque arquivos de
desenvolvimento dentro de `modules/`. O runner encontra as suítes automaticamente:

```sh
python3 'exodus hub/indeed/tools/run_tests.py' --hub nome-do-jogo
```

A auditoria de permissões específica é optativa por integração. O Phantom Ball
usa `"checkPermissions": true` em `hub.json`; seu teste respeita esse campo.
Outras integrações definem as verificações necessárias em suas próprias suítes.
