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
conteúdo final dos arquivos. O CI gera e valida os arquivos; na main, registra arquivos gerados se houver diferenças.
Gere tudo antes do commit para evitar uma alteração adicional de geração.
Não há publicação de site nem ofuscação.

`--hub universal` e `--hub phantom-ball` selecionam suítes individuais. Os testes
usam Luau real com serviços simulados. Cobrem contratos, permissões, inicialização,
limpeza, atualizações, cache e aplicação/restauração de propriedades. Renderização,
latência e integração com os módulos nativos ainda precisam ser verificadas no
cliente Roblox e no executor usado.

## Contratos e recursos

Leia [Arquitetura](architecture.md) antes de mudar fronteiras ou adicionar módulos.
A política interna é obrigatória para todos os jogos. Dependências expõem apenas
membros declarados. `__config` define propriedade, validação e persistência; a
API `options` oferece leitura e observação sem permissão de escrita.

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

## Recuperação do loader

HTTP 403 com evidência de limite e HTTP 429 respeitam `Retry-After` ou
`X-RateLimit-Reset`, até 60 segundos. Esperas maiores mostram um erro e cancelam a tentativa automática. O loader retorna sem lançar erro
para o executor; esperas de até cinco segundos são silenciosas. De cinco a 60 segundos, mostra o erro e agenda nova tentativa.
Outras falhas usam intervalos progressivos de 5 a 60 segundos. Carregamentos
novos invalidam recuperações antigas; fechar o hub cancela sua recuperação.
O bootstrap de auto execute também repete falhas ao baixar o próprio loader,
verificando a preferência salva antes de cada tentativa.

Disclosures compõem a transparência dos ancestrais sem sobrescrever a aparência
original dos títulos e descrições. Colunas visíveis são sempre posicionadas da
esquerda para a direita, inclusive após filtros e atualização de readouts.

Os downloads usam um único worker e compartilham o controle de requisições. Atualizações verificam a revisão a cada cinco minutos.
O prazo de download mede cinco segundos sem progresso, em vez de limitar a duração
total de uma fila lenta. Uma requisição pendente impede a abertura da próxima.
