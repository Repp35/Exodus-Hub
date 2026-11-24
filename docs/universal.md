# Execução universal

O contexto reconhece Phantom Ball pelo Place ID `12979690461` ou pelo
Universe ID `4538598064`. A relação foi consultada em
`https://apis.roblox.com/universes/v1/places/12979690461/universe`.
Studio, nomes de objetos e atributos de outros jogos não habilitam a integração.

Dentro do Phantom Ball, todos os módulos e páginas continuam disponíveis.
Fora dele, o loader não baixa nem executa os módulos game/combat do Phantom Ball,
o CombatLoop, o Auto Jump específico de partida ou o adaptador de sensibilidade
de câmera. O runtime não instala watchers, transporte nem manutenção da bola.
As configurações de combate salvas são preservadas, mas não iniciam esses módulos.

## Interface

| Disponível em qualquer jogo | Exclusivo do Phantom Ball |
| --- | --- |
| Anti AFK na página Universals | Auto Parry, Auto Spam e spam manual |
| Infinite Zoom, Infinite Jump, Fly e velocidade de voo | Dynamic Parry e seus atalhos |
| Speed, Gravity, Invisicam e Noclip | Giros Sword, Emote e Explosion |
| Anti Lag, distância e remoção geral de efeitos | Remoção do som da espada e adaptadores nativos do Anti Lag |
| Dumper | Auto Dark, Auto Fierce, Auto Jump e Auto Dash |
| Modo PC, notificações e reset de configurações | Mini controles, informações de clash e assistências |
| Resetar personagem, Rejoin e Server Hop | Sensibilidade da câmera para parry |

O filtro clona as definições antes da construção da interface. Recriar a interface
com Modo PC não modifica as páginas originais. Atalhos universais continuam ativos;
atalhos especiais de spam e Dynamic Parry são ignorados no modo universal.
O botão de assistências também fica oculto.

O Anti Lag usa o motor reversível de propriedades e renderização em ambos os
contextos; os patches, módulos e atributos PB só são usados no Phantom Ball.

## Validação

O smoke Luau inicializa as APIs reais nos dois contextos, verifica o bloqueio dos
módulos específicos, o runtime universal, os controles disponíveis e o filtro sem
mutação das definições. Também verifica identificação por universo e ausência de
widgets/assistências de combate no contexto universal. A suíte cobre sintaxe,
permissões, contratos e globais. Não simula física, renderização, políticas dos
servidores ou permissões dos executores. Validação visual e funcional dentro do
cliente Roblox continua necessária; suporte universal não garante que servidores
aceitem alterações locais de movimento.
