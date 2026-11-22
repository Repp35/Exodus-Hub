# Desenvolvimento

O projeto é um hub cliente distribuído por HTTP. O loader resolve uma revisão
imutável do GitHub e usa o manifesto para baixar os módulos daquela revisão.

## Verificações básicas

Instale os executáveis oficiais `luau`, `luau-compile` e `luau-analyze` da versão
0.748 e coloque-os no PATH. Alternativamente, configure `LUAU_BIN`,
`LUAU_COMPILE_BIN` e `LUAU_ANALYZE_BIN`.

Execute na raiz:

```sh
python3 -m unittest discover -s 'exodus hub/indeed/tests' -p 'test_*.py'
python3 'exodus hub/indeed/tools/check_permissions.py'
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
```

A suíte verifica manifesto, exports, dependências, ciclos, permissões,
compilação Luau, globais não declarados e inicialização das APIs sem interface
visual. Não verifica constantes, decisões ou regras de combate. Os testes do
formatter verificam somente a ferramenta de desenvolvimento.

O smoke de APIs executa os módulos reais em Luau, com serviços mínimos para
carregamento. Não emula renderização, rede, física nem resultados do servidor.
A análise de globais usa uma lista explícita de APIs Roblox/executor; não é uma
checagem completa de tipos com as definições do Roblox Studio. Sem os binários
Luau, os testes correspondentes são marcados como ignorados; o CI instala os
três executáveis e executa essas verificações.

Os antigos testes de comportamento e suas fixtures estão em
`exodus hub/indeed/legacy_tests`, fora da descoberta padrão. Eles documentam
expectativas históricas, algumas incompatíveis com o código atual, e não são
critério de aprovação do rework. Não é necessário atualizá-los ao ajustar lógica.

## Organização

- `modules/core`: inicialização, configuração, estado, persistência, diagnóstico,
  permissões, recursos e agendamento de combate.
- `modules/game`: integração nativa, jogadores, presença, sincronização e snapshots.
- `modules/combat`: regras de defesa, clash, habilidades, movimento e envio.
- `modules/features`: recursos universais independentes.
- `modules/render`: AntiLag, adaptação nativa, propriedades reversíveis e seleção espacial.
- `modules/tools`: dump e navegação de servidores.
- `modules/front`: biblioteca e controladores da interface existente.

Ao adicionar ou mover um módulo, atualize o manifesto no loader e seu contrato.
As famílias de permissões são definidas em `modules/core/permissions.luau`.
A ordenação de inicialização é derivada das dependências, sem ciclos.

Veja [o relatório do rework](rework.md) para decisões e validação em execução.
