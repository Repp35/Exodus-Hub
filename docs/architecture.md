# Arquitetura do Exodus Hub

Este documento descreve os contratos implementados. As regras de manutenção estão
em [AGENTS.md](../AGENTS.md). A base carrega sem integração: jogos acrescentam
suas páginas, ações e recursos, sem substituir o funcionamento do hub.

## Responsabilidades

| Origem | Responsabilidade | Limite |
| --- | --- | --- |
| `loader.luau` | Transporte, revisão, cache, compilação, integridade e troca da sessão | Não implementa opções, componentes ou lógica de jogo. A superfície de inicialização é gerada de `ui/`. |
| `core/runtime/` | Bootstrap, ordenação, recursos, personagem, agendamento e propriedades reversíveis | Não define apresentação nem algoritmos de combate. |
| `core/config/` | Schema, estado observável e arquivos separados por domínio | Só aceita chaves registradas; cada chave tem um proprietário. |
| `core/security/` | Política interna e dependências declaradas | A política é a mesma com qualquer jogo; manifestos não a substituem. |
| `core/integration/` | Adaptador e fronteira de cada jogo | Não contém algoritmos ou nomes específicos de jogos. |
| `core/session/`, `core/diagnostics/`, `core/services/` | Sessão, diagnóstico e serviços do hub | Não armazenam estado de combate de uma integração. |
| `ui/components/` | Componentes reutilizáveis e seus recursos visuais | Um nome de componente não pode ser registrado duas vezes. |
| `core/presentation/`, `universal/presentation/` | Consumidores da API: páginas do hub, controles e ações universais | Declaram dados e callbacks, sem criar elementos visuais. |
| `universal/` | Implementação de opções universais | Escreve somente suas configurações; usa os serviços compartilhados. Não conhece jogos. |
| `hubs/<id>/` | Lógica do jogo, suas configurações e uso da API de controles | Não cria elementos gráficos por fora da biblioteca nem altera outro domínio. |
| `ui/` | Biblioteca reutilizável, independente de consumidores | Não importa jogos, loader, persistência ou adaptadores do hub. |

Essas permissões organizam APIs internas e detectam erros. Código Luau no executor
continua tendo acesso ao ambiente Roblox: isto não é uma sandbox para código hostil.

## Descoberta e dependências

Os catálogos são gerados recursivamente. Um módulo compartilhado declara
`-- @modules nome`; o nome de um módulo de jogo é o arquivo sem `_`. Nomes são
únicos dentro da integração e não substituem módulos compartilhados. `indeed/`
não é distribuído. Não se adicionam arquivos manualmente ao loader ou aos catálogos.

Todo módulo declara os exports em `provides`/`data`, as dependências em `requires`
e os membros consumidos em `requiresMethods`/`requiresData`. Uma API não declarada
é recusada, mesmo que exista no provedor. Ciclos, exports ausentes, colisões e
políticas inválidas impedem a inicialização. A ordenação respeita dependências e
usa uma ordem estável para desempates.

`setup(deps)` retorna `true`. Se o módulo possui recursos, exporta `teardown()`
idempotente, registrado antes do setup para permitir limpeza de uma falha parcial.
Conexões, tarefas e restaurações pertencem a um `lifetime.scope()`. `scope.child()`
vincula recursos ao pai; `destroy()` libera-os uma vez, na ordem inversa.
`scope.defer()` e `scope.delay()` cancelam tarefas pendentes no encerramento.

## Configuração e estado

A declaração é local ao proprietário:

```lua
Feature.__config = {
  schema = { ExampleEnabled = "boolean", ExampleValue = "rate" },
  defaults = { ExampleEnabled = false, ExampleValue = 20 },
  constraints = { ExampleValue = { min = 0, max = 100 } },
  persistent = { ExampleEnabled = false },
}
```

`persistent = false` desativa o salvamento de todas as chaves daquele módulo. Uma
tabela escolhe por chave; as não mencionadas são persistentes. Nenhuma política
pode mencionar chaves de outro módulo. O jogo não decide defaults nem persistência
de configurações do hub. `constraints.choices` define enumerações textuais.

`Utils.setConfig(patch)` é a única entrada de escrita. Valida o patch inteiro antes
de aplicá-lo e publica alterações imutáveis. Universais só escrevem suas chaves;
o adaptador do jogo só escreve chaves de sua integração. A UI escreve em resposta
às ações do usuário. Módulos observam configuração; a UI não dispara uma segunda
rota de ativação além desse evento.

O estado completo das opções sobrevive ao reload, atualização e reexecução na mesma
sessão. Fechar o hub descarta essa cópia da sessão. Em uma nova abertura, somente
chaves persistentes voltam. Fly, Noclip, Speed, Gravity, Jump Power, Infinite Jump,
Invisicam e Auto Jump não religam por preferência de uma sessão anterior; seus
valores configurados continuam salvos.

O hub usa `Exodus Hub/config.json`; cada jogo usa
`Exodus Hub/hubs/<id>/config.json`. O formato inclui domínio e versão. Backups são
verificados antes da substituição. A migração protege os arquivos antigos e não
aplica chaves de outro domínio. Auto Execute mantém seu arquivo próprio.

## API de observação

Um módulo recebe `Options = "options"` e declara os métodos que usa. A mesma
fachada de leitura está disponível em `_G.Exodus.Options`:

```lua
local enabled = options.isEnabled("AntiLagEnabled")
local value = options.get("UniversalFlySpeed")
local metadata = options.describe("AntiLagEnabled") -- tipo, proprietário, domínio, persistência
scope.add(options.observe({ "AntiLagEnabled", "AntiLagRemoveEffects" }, function(changes)
  synchronize()
end))
synchronize() -- a assinatura observa alterações; não emite um evento inicial
```

Chave desconhecida em `get` ou `observe` é erro. O observador recebe somente as
chaves solicitadas. Ele não concede escrita. O Phantom Ball usa esse contrato para
ativar sua própria adaptação de efeitos e áudio junto com o anti lag universal;
não há chamada do universal para o jogo.

## Universais e apresentação

A configuração de um jogo permanece em `hubs/<id>/`: escolhe componentes e
callbacks da biblioteca, como nos exemplos de
[Fluent](https://github.com/dawid-scripts/Fluent/blob/master/Example.lua),
[WindUI](https://footagesus.github.io/WindUI-Docs/docs/toggle) e
[Linoria](https://github.com/violin-suzutsuki/LinoriaLib/blob/main/Example.lua).
O componente não conhece o consumidor. O painel flutuante e o seletor de taxa são
reutilizáveis: os vínculos com chaves e modos são parâmetros, sem nomes de jogo.


Uma implementação nova entra em `universal/` com schema, contrato e ciclo de vida.
O consumidor declara sua apresentação por dados ou pela API. Uma seção universal
pode exportar `definition` com `title` e `components` e `__contract.section` com a
ordem numérica; a composição a entrega à biblioteca. Os exemplos de
`universal/presentation/` mostram o formato completo. Também é possível adicionar
uma página diretamente no próprio módulo, sem um arquivo de UI separado:

```lua
local page = deps.UI.addPage({ id = "example", title = "Exemplo", columns = 1 })
local section = page.addSection({ title = "Controles" })
local control = section.toggle({ title = "Ativar", key = "ExampleEnabled" })
control.setValue(false)
```

Declare a dependência `UI = "ui"` e o método `addPage`, além do schema de suas
chaves. A API aceita essas declarações antes de montar a janela. A biblioteca só
recebe páginas, estado e callbacks; a composição resolve o armazenamento e os
serviços. Não há importação da pasta de jogos na UI.

Aplicações contínuas usam `universalcontroller.connectPhysics(scope, callback)`:
uma assinatura recebe as fases anterior e posterior à simulação. Eventos discretos
e trabalhos com orçamento não criam um segundo loop equivalente. Ao desligar,
encerre o escopo de ativação e restaure as propriedades. `propertybinding` arbitra
propriedades compartilhadas e restaura o valor original quando o último dono sai.

Um componente novo exporta `install(context)` e declara
`__contract.component = true`. A composição descobre instaladores em `ui/components/` e os fornece à biblioteca. O toolkit e a API
pública expõem os mesmos nomes, sem listas paralelas. O instalador não redefine
um componente existente. Definições de páginas têm componentes registrados,
IDs únicos e relações `parentKey` válidas, sem ciclos.

Mini UIs usam `ui/components/mini.luau`. Cada definição tem seu `scaleKey` e, quando
configurável, `squareKey`, além de coordenadas próprias. A Config oferece
`MiniUIScale`, um multiplicador geral que preserva os tamanhos individuais.
A composição fornece esse valor à UI por um binding de leitura e observação;
a biblioteca não conhece a chave de configuração. No MM2, tamanho e formato
individuais ficam junto de Shoot e Lançar Faca. O handle também
oferece `setSize`, `setDimensions`, `setShape` e `setColor`. Destruir o handle libera
seu input, drag e animações. A propriedade declarativa `option` permite um botão
operado pelo usuário consumir uma opção universal existente; isso não concede ao
jogo acesso de escrita à opção.

Os ícones internos são normalizados para uma máscara branca na geração. O tema
aplica `#DCE6FF` à máscara, preservando transparência. Não se escolhe uma cor por
ícone. Páginas de uma coluna compartilham largura e centralização; as de duas
colunas preservam os lados.

## Anti lag e localização

O anti lag usa orçamento por fase, não destrói geometria nem corta objetos por
altura/chão. A distância é medida até a superfície, com uma área próxima
preservada; personagens e peças móveis não entram no descarte. Geometria distante
pode ser simplificada e depois ocultada conforme as opções. A retirada de
texturas é separada e desligada por padrão. Luzes, sombras e pós-processamento são
suprimidos enquanto ele está ativo. O desligamento restaura alterações de forma
orçada antes de encerrar o otimizador.

A localização prefere metadados publicados pelo jogo. `game.ServerRegion` não é
replicado ao cliente. O leitor acompanha o histórico e os eventos da conexão atual;
quando há um endereço público disponível, consulta sua geolocalização. O ponto de
conexão pode ser um relay, por isso esse resultado é marcado como aproximado.
O país do jogador e o ping não são tratados como país do servidor. Sem evidência,
a interface informa indisponibilidade, e o diagnóstico registra a falha.

Fontes: [ServerRegion](https://create.roblox.com/docs/reference/engine/classes/DataModel#ServerRegion),
[ConnectionAccepted](https://create.roblox.com/docs/reference/engine/classes/NetworkClient#ConnectionAccepted),
[formato da consulta IP](https://ipwhois.io/documentation).
