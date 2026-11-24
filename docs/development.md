# Desenvolvimento

Use Python 3.12, Luau 0.748 e o StyLua incluído no repositório.
`LUAU_BIN`, `LUAU_COMPILE_BIN`, `LUAU_ANALYZE_BIN` e `STYLUA_BIN` permitem
usar executáveis próprios. Sem essas variáveis, as ferramentas procuram no PATH.

Após alterar o código, execute na raiz:

```sh
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
python3 'exodus hub/indeed/tools/build_hub_catalog.py'
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub/core/catalog.luau' 'exodus hub/hubs/catalog.luau'
python3 'exodus hub/indeed/tools/build_hub_catalog.py' --check
python3 'exodus hub/indeed/tools/run_tests.py' --hub all --require-tools
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
```

Formate os módulos antes de gerar os catálogos: seus hashes correspondem ao
conteúdo final dos arquivos. O CI só valida; não modifica arquivos nem cria commits.
Não há publicação de site nem ofuscação.

`--hub universal` e `--hub phantom-ball` selecionam suítes individuais. Os testes
usam Luau real com serviços simulados. Cobrem contratos, permissões, inicialização,
limpeza, atualizações, cache e aplicação/restauração de propriedades. Renderização,
latência e integração com os módulos nativos ainda precisam ser verificadas no
cliente Roblox e no executor usado.

## Contratos e recursos

Declare dependências em `__contract.requires` e APIs necessárias em
`requiresMethods`/`requiresData`. Exporte funções em `provides`. Use `teardown`
para desfazer alterações, inclusive as feitas antes de uma falha no `setup`.
`lifetime.scope()` libera recursos na ordem inversa, uma única vez.

A política opcional de permissões fica no `hub.json`. `__contract.access`
classifica operações; `config.own` limita escritas às chaves do próprio módulo.
Resultados de leitura e APIs são imutáveis. Essa política organiza o acesso
interno; não isola scripts do ambiente Roblox ou do executor.
