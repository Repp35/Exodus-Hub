# Interfaces do jogo

Referência: scripts de `ReplicatedStorage.Shared` presentes no dump
`SrcDump_olym4`. Nomes e valores devem ser conferidos quando o jogo atualizar.

## Habilidades

| Habilidade | ID | Dados relevantes |
| --- | --- | --- |
| Deflect | 1 | Alcance base de 8,5 studs; janela de 0,85 s na velocidade 16 até 0,20 s na velocidade 600. Clash pode impor mínimo e aplicar pressão. |
| Dash normal | 2 | `DashSpeed = 120`, `DashTime = 0.2`, estado `Dashing`. |
| FierceDeflect | 19 | `ActivateAndBlock`; estado e cooldown independentes do envio de deflect. |
| DarkSeal | 20 | Endpoint de habilidade obtido pelo adaptador de GameInfo. |
| WindDash | 22 | `DashSpeed = 200`, `DashTime = 0.05`, `DashTime2 = 0.75`; usa `Controlling` e `MoveDir` como Vector3Value. |

Dash normal e WindDash publicam o mesmo `IsDashing` e usam a mesma animação
`Movement/Dash`. Esse sinal não identifica o tipo. WindDash desliga o sinal após
a primeira fase de 50 ms, embora o movimento continue. Seu script contém
`DashSpeed2 = 150`, mas o tick inspecionado ainda multiplica por `DashSpeed`;
não se deve assumir a velocidade da segunda fase pelo nome dessa variável.

`Shared.Abilities.ClientAbilities.Abilities` contém as instâncias locais.
`Shared.Enums.AbilityID` e `Shared.Abilities.AbilitySystem` definem IDs e classes.

## Rodada e participação

`Workspace.MatchStatus = 6` significa rodada global ativa. Isso não prova que o
jogador esteja nela. `BGameMatch.IsPlayerInLobby` consulta a região `Lobby Area`
e `Training/Areas/SafeArea`; a lista de vivos combina Lives, Playing e posição.

O hub observa vida do Humanoid, Lives, Playing, região e entrada por teleporte.
Após morrer numa rodada ativa, o jogador permanece fora dela até o encerramento
da rodada e uma nova entrada. Respawn e valores antigos de Lives/Playing não
reabrem participação na mesma rodada.

## Bola e defesa

`BallReplicator` fornece estado, sequência de 16 bits, histórico e `SimulateFrom`.
A posição desenhada pode conter interpolação e grace; não substitui o estado da
simulação. Os pacotes expõem alvo, posição real, direção, velocidade, aceleração,
limite de velocidade, lock, grace e tempo do servidor.

`GameBall.GetKillDistance()` fornece o raio de morte (4 studs no dump).
`DeflectAbility.Deflect` pode recusar chamadas com intervalo inferior a 0,008 s;
retorno nil sozinho não confirma que houve envio. Cooldown, previsão local e
confirmação do servidor são estados diferentes.
