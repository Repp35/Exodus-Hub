# Adicionar um jogo

Crie uma pasta com `hub.json`:

```json
{
  "title": "Nome do jogo",
  "placeIds": [123456789],
  "universeIds": [987654321],
  "permissions": false
}
```

Use IDs reais; um dos grupos basta. O nome da pasta identifica a integração.
Autor e mensagem são opcionais. O autor padrão é `deltapolinha_2915`.

Coloque arquivos `.luau` diretamente na pasta e em subpastas descritivas, como
`combat/`, `prediction/` e `game/`. Não crie uma pasta genérica `modules/`.
O nome do arquivo sem sublinhados é sua chave: `auto_parry.luau` registra
`autoparry`. Não repita chaves nem copie módulos universais ou da UI.
O workflow atualiza o catálogo; não existe lista manual de arquivos de jogo.

Cada módulo declara `__contract`, métodos públicos, dependências e um `setup`
que retorna `true`. Use `teardown` para limpar conexões e recursos.
A ordem de inicialização é resolvida pelas dependências.

`game_ui.luau` exporta a configuração declarativa das páginas e opções existentes.
Todos os componentes, mini UIs e controles de spam pertencem à UI compartilhada.
Nenhum jogo injeta componentes. Veja o exemplo do Phantom Ball.

`permissions: true` habilita a política de permissões durante a execução.
É opcional por integração. Os contratos e APIs necessários ao carregamento
continuam sendo verificados em qualquer caso.

Testes mínimos ficam em `indeed/tests/` e diagnósticos em `indeed/diagnostics/`.
O gerador exclui toda a pasta `indeed/` da distribuição.

[Mapa da estrutura](../../docs/structure.md) · [Verificações](../../docs/development.md)
