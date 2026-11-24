# Desenvolvimento

Use Python 3.12, Luau 0.748 e o StyLua incluído no repositório.
`LUAU_BIN`, `LUAU_COMPILE_BIN`, `LUAU_ANALYZE_BIN` e `STYLUA_BIN` permitem
usar executáveis próprios. Sem essas variáveis, as ferramentas procuram no PATH.

Após alterar o código, execute na raiz:

```sh
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
python3 'exodus hub/indeed/tools/build_notification_surface.py'
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

## Diretivas Luau

Os arquivos de execução usam `--!optimize 2`. `--!native` fica nos cálculos de
geometria e seleção espacial. Essas solicitações dependem do suporte do compilador
e do executor; não substituem a medição de desempenho no cliente.

O registro tipado e os catálogos gerados usam `--!strict`, com análise completa no
CI. Os módulos que recebem APIs dinâmicas mantêm a análise padrão.

## Interface

`ui/theme.luau` define cores e o campo opcional `ICON`. Use uma imagem como
`rbxassetid://123456789`. Em execução, `_G.Exodus.UI.setIcon(123456789)` aplica a
imagem ao botão flutuante e ao canto esquerdo do cabeçalho. `setIcon(nil)` restaura
a inicial. Uma imagem inválida restaura a inicial e mostra o erro.

O cabeçalho reserva margens para ícone, texto e botões. A faixa de botões só
permite rolagem horizontal quando seu conteúdo ultrapassa o espaço disponível.

`ui/appearance.luau` concentra contornos e notificações. O gerador inclui a mesma
superfície no loader para mensagens anteriores à carga dos módulos. O CI verifica
essa cópia; não a edite à mão. Notificações ajustam largura e altura ao texto;
mensagens maiores que a tela usam rolagem interna, sem truncar o conteúdo.
