# Exodus Hub

Uma estrutura compartilhada para vários jogos Roblox, com um único
[`loader.luau`](exodus%20hub/loader.luau). A interface, as animações, as ferramentas
e os recursos universais pertencem ao Exodus; cada integração adiciona o que é
específico do jogo.

| Jogo | Seleção | Integração |
| --- | --- | --- |
| Phantom Ball | Place `12979690461` ou Universe `4538598064` | [Pasta do jogo](exodus%20hub/hubs/phantom-ball) |
| Outros jogos | Sem ID cadastrado | Base universal |

As pastas de jogos são descobertas automaticamente a partir de `hub.json`.
O catálogo é atualizado pelo GitHub Actions e o loader baixa apenas a base e
os módulos da integração selecionada, usando a mesma revisão do repositório.
Cada integração possui sua notificação de carregamento e pode informar autor.
O autor padrão permanece `deltapolinha_2915`.

[Adicionar jogos e módulos](exodus%20hub/hubs/README.md) ·
[Desenvolvimento e testes](docs/development.md)

A integração específica atual é Phantom Ball. MM2 e outros jogos recebem os
recursos universais enquanto não houver módulos próprios cadastrados.
