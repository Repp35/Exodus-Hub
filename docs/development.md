# Desenvolvimento

## Alterar a base ou um jogo

Recursos compartilhados e toda a UI ficam em `exodus hub/modules/`.
Lógica exclusiva de um jogo fica em `exodus hub/hubs/<jogo>/modules/`.
Não copie módulos da base para a pasta do jogo. O nome de cada arquivo `.luau`
é sua chave no carregador; as dependências devem constar em `__contract`.

Ao adicionar ou remover arquivos de jogos, o workflow de formatação gera o
catálogo automaticamente. O procedimento local equivalente, executado na raiz:

```sh
python3 'exodus hub/indeed/tools/build_hub_catalog.py'
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
```

## Verificar

Use `luau`, `luau-compile` e `luau-analyze` da versão 0.748 no PATH, ou defina
`LUAU_BIN`, `LUAU_COMPILE_BIN` e `LUAU_ANALYZE_BIN`.

```sh
python3 'exodus hub/indeed/tools/run_tests.py' --hub all
python3 'exodus hub/indeed/tools/run_tests.py' --hub universal
python3 'exodus hub/indeed/tools/run_tests.py' --hub phantom-ball
python3 'exodus hub/indeed/tools/build_hub_catalog.py' --check
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
```

A suíte verifica sintaxe Luau, contratos, permissões, seleção por IDs, descoberta
de pastas, ausência de cópias da base, composição de páginas, abertura do menu e
repetições do dumper. Os serviços Roblox usados nos testes são simulados.
Sem os executáveis Luau, parte das verificações é ignorada; o CI instala os três.

Valide também no cliente Roblox: abrir e reabrir o menu, alternar Modo PC,
respawn, fechar/recarregar, recursos universais e funções específicas do jogo.
O teste local não confirma renderização, respostas do servidor ou APIs de cada
executor. As ferramentas manuais ficam em `exodus hub/indeed/diagnostics/`.

`indeed/` da base contém apenas infraestrutura e testes universais.
Cada jogo guarda testes e diagnósticos em `hubs/<jogo>/indeed/`. O catálogo
considera apenas arquivos dentro de `hubs/<jogo>/modules/`, portanto nunca
baixa testes ou diagnósticos como parte do hub.

A suíte de um jogo decide suas verificações específicas. No Phantom Ball,
`checkPermissions` em `hub.json` habilita a auditoria de permissões do jogo.
Isso não obriga outros jogos a executar essa auditoria. A validação dos contratos
dos módulos efetivamente carregados continua sendo responsabilidade do loader.
