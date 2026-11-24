# Adicionar um jogo

Crie `hubs/<jogo>/hub.json` com IDs reais:

```json
{
  "title": "Nome do jogo",
  "placeIds": [123456789],
  "universeIds": [987654321],
  "permissions": false
}
```

Um dos grupos de IDs basta. A pasta identifica a integração. `author`,
`notification` e `dataFolder` são opcionais. O armazenamento padrão fica em
`Exodus Hub/hubs/<jogo>`; use `dataFolder` apenas para preservar um local existente.

Arquivos `.luau` fora de `indeed/` entram no catálogo automaticamente. A chave é o
nome do arquivo sem sublinhados: `auto_parry.luau` vira `autoparry`. Chaves devem
ser únicas e não podem substituir módulos compartilhados.

Cada módulo declara `__contract`, dependências, `setup` e, se possuir recursos,
`teardown`. Um `setup` bem-sucedido retorna `true`. Recursos ligados ao personagem
usam `bindCharacter` e `detachCharacter`, com `bindCharacter = true` no contrato.

`game_runtime.luau` exporta `bind` e `createAPI(loaded)`. Este último retorna o
adaptador consumido pela base. Todos os campos são opcionais:

- `getUIConfig`: definição de páginas, opções e capacidades.
- `controls`: callbacks das ações da interface.
- `createActions(context)`: ações e estados adicionais; recebe o escopo da UI.
- `readouts`: indicadores com `id`, `key`, `anchor`, `position` e função `read`.
- `updateBlockers`: funções que retornam `true` enquanto uma atualização deve esperar.
- `miniVisibility`: mapa de chave de configuração para regra de visibilidade.
- `migrateConfig(data)`: migração dos arquivos antigos da integração.
- `getJumpButton`: controle nativo adicional de pulo, quando necessário.
- Métodos de habilidades e adaptação visual usados pela integração.

O Auto Execute consulta a revisão a cada 120 segundos, prepara os arquivos e
aguarda 0,4 segundo contínuo sem bloqueios antes de substituir a sessão. Uma
falha na regra bloqueia a atualização. Desativar Auto Execute cancela uma troca
pendente. O botão de atualização e uma nova execução do loadstring forçam a troca.

As regras de Mini UI complementam a escolha do usuário sem salvar alterações:
a UI aparece quando a regra ou a opção manual está ativa e faz a transição de
saída quando ambas deixam de estar ativas. Elas não ativam a função do botão.

Módulos compartilhados declaram suas chaves após o título e as diretivas, por exemplo
`-- @modules exemplo`. Bundles listam todas as chaves separadas por vírgulas.
Depois de adicionar arquivos, gere os catálogos com os comandos de
[desenvolvimento](../../docs/development.md). Não edite os catálogos à mão.

Testes ficam em `indeed/tests/`; diagnósticos, em `indeed/diagnostics/`.
Use o Phantom Ball como referência para uma integração completa.
