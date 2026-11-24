# Ferramentas de desenvolvimento

Esta pasta não integra a distribuição HTTP do hub.

- `tests/`: verificações de APIs, manifesto, permissões, compilação e carregamento Luau; não verificam regras de combate.
- `checks/`: ambiente mínimo de serviços para o smoke de APIs e lista de globais externos.
- `diagnostics/`: inspeção e captura manual de desempenho no cliente Roblox.
- `tools/`: validação de permissões e geração/validação de assets.
- `formatter.py`, `formatting/`: CLI, regras e backend StyLua.

Os comandos e requisitos atuais estão em [docs/development.md](../../docs/development.md).
O CI usa Luau oficial para sintaxe e carregamento de APIs; não traduz Luau para Lua 5.4.
