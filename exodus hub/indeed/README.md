# Ferramentas de desenvolvimento

Esta pasta não é publicada junto com o hub. Os testes continuam em `tests/`,
incluindo os fixtures e harnesses compartilhados.

- `formatter.py`: entrada compatível para comandos e imports existentes.
- `formatting/rules.py`: transformações de texto e regras de estilo, sem I/O.
- `formatting/backend.py`: configuração, descoberta e execução do StyLua.
- `formatting/cli.py`: argumentos, seleção de arquivos, pipeline e escrita atômica.
- `formatting/resources/`: configuração e executável do StyLua.
- `tools/check_permissions.py`: verifica contratos e acessos às dependências, incluindo os controllers que recebem permissões da UI; bloqueia a publicação no CI.
- `tools/`: geração e validação dos ícones da interface.
- `benchmarks/`: comparação offline do dispatch de cliques.
- `diagnostics/`: scripts Luau de inspeção para execução manual.

A dependência interna do formatter segue `cli → backend → rules`. O pacote
`formatting` exporta a API utilizada pelo wrapper e pelos testes. As regras não
importam a CLI nem iniciam subprocessos. Os caminhos do hub e dos recursos são
resolvidos a partir dos módulos, independentemente do diretório atual.

Execute a partir da raiz do repositório:

```sh
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
python3 'exodus hub/indeed/tools/check_permissions.py'
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 'exodus hub/indeed/benchmarks/benchmark_clicks.py'
python3 -m unittest discover -s 'exodus hub/indeed/tests' -p 'test_*.py'
```

Sem caminhos explícitos, o formatter processa a pasta do hub. Para usá-lo como
pacote, execute `python3 -m formatting` a partir desta pasta, com as mesmas opções.
A animação, o loader e os módulos de produção não dependem destas ferramentas.
