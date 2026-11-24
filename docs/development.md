# Desenvolvimento

Código compartilhado fica em `core/`, `ui/` e `universal/`.
Código de um jogo fica diretamente em `hubs/<jogo>/`, separado por responsabilidade.
Arquivos de testes e diagnósticos ficam no `indeed/` correspondente e nunca são
incluídos no catálogo de execução.

Execute na raiz do repositório:

```sh
python3 'exodus hub/indeed/tools/build_hub_catalog.py'
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
python3 'exodus hub/indeed/tools/run_tests.py' --hub all
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
```

Os executáveis Luau 0.748 podem ser fornecidos por `LUAU_BIN`,
`LUAU_COMPILE_BIN` e `LUAU_ANALYZE_BIN`, ou pelo PATH.
As verificações cobrem apenas sintaxe, APIs, dependências e permissões.
Não há suíte de comportamento de combate, interface ou dumper.
O carregamento universal também é verificado sem a política de permissões.

Use `--hub universal` ou `--hub phantom-ball` para executar apenas uma suíte.
O campo `checkPermissions` do jogo controla sua auditoria de desenvolvimento;
`permissions` controla o uso da política durante a execução do hub.

O CI executa as verificações mínimas. Renderização e comportamento real devem
ser conferidos no cliente Roblox e no executor utilizado.

## Permissões internas

`core/permissions.luau` é apenas o motor. O `permissionPolicy` do `hub.json`
define tipos, autorizações e atribuição dos módulos a esses tipos. Módulos novos
nas pastas já cobertas herdam o tipo; o motor não precisa ser editado.
As autorizações descrevem ações, como leitura interna, execução de combate,
escrita de configuração e alteração de UI. Não são listas de APIs por consumidor.

As APIs declaram exceções semânticas em `__contract.access`: `default` informa
a categoria de operação padrão; `methods` classifica operações que diferem dela;
`scoped` marca operações limitadas às configurações pertencentes ao consumidor.
Métodos de consulta usam a categoria genérica `internal.read` por padrão.
Todo módulo com essa categoria pode ler as APIs que importar.

Dados públicos e resultados de leitura em tabelas são cópias de leitura.
As dependências são vistas imutáveis; métodos sem permissão não são expostos.
O escopo `config.own` usa as chaves do `__config.schema` do próprio módulo,
sem nomes ou prefixos fixos no motor. Acesso ao Roblox/remotes não é restringido.
A regra protege a comunicação pelas APIs internas; não é isolamento de scripts
maliciosos com acesso ao ambiente global do executor.
