# Exodus Hub: integrações de jogos

`loader.luau` é a única entrada. A base em `modules/` fornece interface,
animações, recursos universais, Anti Lag, dump, persistência e navegação.
Cada pasta de jogo contém seus módulos e um `hub.json` com os IDs.

O catálogo é gerado automaticamente no GitHub pelo workflow de formatação,
sempre que arquivos Luau ou metadados de jogos mudam. Não edite `catalog.luau`.
O loader lê o catálogo, prioriza Place ID e depois Universe ID, e baixa somente
a base mais os módulos do jogo selecionado, todos na mesma revisão imutável.
Jogos sem cadastro recebem apenas a versão universal.

## Adicionar um jogo

1. Crie `hubs/nome-do-jogo/hub.json`:

```json
{
  "id": "nome-do-jogo",
  "title": "Nome do jogo",
  "placeIds": [123456789],
  "universeIds": [987654321]
}
```

Use os IDs reais. `id` é opcional quando igual ao nome da pasta. Um dos grupos
de IDs basta. `author` e `notification` são opcionais; o autor padrão continua
`deltapolinha_2915` e a notificação usa o título do jogo.

2. Coloque os módulos `.luau` dentro da pasta. O nome do arquivo é a chave do
módulo: `movement.luau` registra `movement`. Não repita nomes na mesma integração.
Subpastas são percorridas automaticamente. Não existe lista manual de scripts.

```lua
local Feature = {}
function Feature.setup(deps)
  -- Inicialize o recurso e registre a limpeza.
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

Declare dependências em `__contract.requires` e métodos em `requiresMethods`.
A ordem é calculada pelas dependências; ciclos e dependências ausentes são erros.
Hooks de personagem só iniciam depois de todos os módulos selecionados.

3. Envie ao GitHub. O workflow encontra a pasta e atualiza o catálogo. Não é
necessário editar o loader, o registro ou um manifesto do jogo. Localmente,
execute `python3 'exodus hub/indeed/tools/build_hub_catalog.py'` e o formatter.

## Estender a interface e o runtime

Uma integração pode substituir módulos da base pelo mesmo nome de arquivo.
Por exemplo, `uiconfig.luau` define páginas e configurações; `runtime.luau`
conecta os eventos específicos. A interface principal e as animações da base
continuam compartilhadas. Os módulos reservados `permissions`, `gamecontext` e
`hubapi` não podem ser substituídos. A ponte `hubapi` oferece hooks opcionais
para integrações nativas, sem exigir módulos de combate na versão universal.

Use a mesma organização de permissões da base: `modules/combat/`,
`modules/game/`, `modules/core/`, `modules/features/`, `render/` e `front/`.
Os contratos são validados antes da inicialização.

## Phantom Ball

A pasta `phantom-ball/` preserva combate, habilidades, controles móveis,
telemetria e definições de interface existentes. O Anti Lag nativo está em
`render/nativevisuals.luau`; o motor geral continua na base. A configuração antiga
mantém a pasta `Exodus Hub`. Outras integrações usam `Exodus Hub/hubs/<id>`.

No momento, a integração específica cadastrada é Phantom Ball. MM2 e outros
jogos usam a versão universal até receberem módulos próprios.

Os testes cobrem APIs e roteamento com serviços simulados; renderização,
comportamento de servidores e compatibilidade com executores precisam ser
validados no cliente Roblox. O loader não pode fornecer APIs ausentes no executor.
