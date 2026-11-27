# Estrutura

- `exodus hub/loader.luau`: transporte, cache, integridade e inicialização.
- `exodus hub/core/`: configuração, sessão, serviços e composição do hub.
- `exodus hub/core/presentation/`: uso da API para os controles compartilhados.
- `exodus hub/ui/`: biblioteca de componentes e janelas, sem conhecimento dos consumidores.
- `exodus hub/universal/`: recursos universais e suas declarações de controles.
- `exodus hub/hubs/<id>/`: lógica, opções e uso da API por cada jogo.
- `exodus hub/hubs/access.luau`: acesso de usuários ao hub e às integrações.
- `exodus hub/indeed/`: ferramentas e verificações essenciais; não distribuído.
- `exodus hub/dist/runtime.json`: pacote gerado de fontes e catálogos.

[Contratos e exemplos](architecture.md) · [Comandos de validação](development.md)
