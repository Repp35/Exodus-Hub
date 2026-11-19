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

## Identificação de alvo na partida

O cliente possui duas fases relacionadas: `StandardBall.ChangeTarget` escreve
`Workspace.GameBallTarget` e `HighlightTargetPlayerID`; o tick da simulação escreve
`TargetPlayerID`. O replicador também mantém `latestTargetId`,
`IsLocalTarget()` e o último item de `history` com `targetId`/`highlightId`.
Os eventos `BallSyncData` e `BallSnapshot` transportam esse estado. Leituras do
mesmo estado são correlacionadas e podem mudar em frames diferentes.

Os sinais visuais encontrados no dump são:

- `PlayerBallHighlight` habilitado no personagem do alvo, atualizado por
  `BallHighlightManager`. `BlockingHighlights` pode desabilitá-lo temporariamente
  por feedback de bloqueio; ausência não prova que o jogador deixou de ser alvo.
- `GameBall.Color = Color3.fromRGB(202, 56, 30)` para o alvo local, definido em
  `GameBallInitializer`. Posse substitui a cor por verde. A cor normal de uma skin
  pode coincidir com o vermelho e tornar a leitura ambígua.
- `GameBall.Trails.BallTrail.Color` copiado de `BallTrailTarget.Color` para o alvo
  local, ou de `BallTrail2.Color` para os demais. Sequências iguais são ambíguas.
- `PlayerGui.Interface.BallIndicatorUI.Indicator.ImageColor3` vermelho puro para
  alvo local e branco para os demais, em `BallIndicator`. O script não atualiza a
  cor enquanto a seta está oculta; a cor de uma seta oculta não deve votar.
- A textura do Decal em `GameBall.SkinFace`: `BallSkinClient.pickFace` usa
  `serious_1`, `evil`, `crazy` e `crazy_talking` quando o alvo é local. Outras faces
  podem representar acerto, miss, previsão ou congelamento; não confirmam alvo.
  A tabela `Inventory.BallSkins[BallSkin].Faces` define os assets de cada skin.

O Highlight da própria bola não diferencia os alvos: suas cores de preenchimento
e contorno são iguais nos dois ramos. `SkinTargetColor` é preenchido pelo script
de skins, mas o código de renderização inspecionado usa o vermelho acima.
`LastParryTarget`, posse, direção, distância, feedback de bloqueio e histórico
antigo de simulação não garantem quem é o alvo atual.

`DarkSealAbility` ativa `Player.DarkSealed = true` no dono, com duração de 15 s
(`SealTime`) e cooldown de 20 s. O servidor recusa ativar se outro jogador já está
marcado; morte, reset e destruição limpam a marca e invalidam o timer por token.
Não se deve inferir marca ativa por habilidade equipada, cooldown ou VFX.
A seleção nativa exclui o próprio rebatedor, camuflagem e companheiros em equipes
antes da prioridade Dark Seal; só depois compara alinhamento com a câmera.
A previsão do hub verifica a marca antes de exigir câmera válida: marca em terceiro
impede antecipar para o jogador local; marca local válida dispensa alinhamento.

## Auto spam: sinais e previsão de retorno

O motor mantém sinais de animação, pernas da bola e histórico de trocas separados.
`BlockStart`, `BlockLoop` e `Parry` são classificados pelos assets de todos os
estilos. Eventos são avaliados imediatamente; uma varredura limitada recupera
tracks já em execução e assets que chegaram por streaming. O loop não renova
indefinidamente a vida de uma tentativa. Respawn, remoção e detach limpam as
inscrições dos personagens anteriores.

A previsão calcula a interceptação da bola com o adversário e o voo de retorno
até o alcance local, considerando movimento relativo, latência e duração do
frame. A posição e direção de sincronização são usadas quando recentes. Uma
animação pode chegar antes ou depois do alvo; sua evidência permanece disponível
para a próxima avaliação. Contato físico numa saída confirmada também permite
antecipar quando a animação ainda não foi recebida.

O estado passa de idle para anticipating e depois clashing quando o alvo local
é confirmado. A antecipação possui prazo absoluto e é consumida por tentativa e
perna. O guard de envio revalida a sessão; trocas rápidas confirmadas permitem uma
ponte curta durante lacunas de dados, cujo prazo não é renovado pela incerteza.
`AutoSpam.getStatus()` expõe fase, tempos previstos, origem da animação,
latência de frame e motivo da última interrupção para diagnóstico.

A seleção prevista acompanha o maior alinhamento entre candidatos elegíveis,
sem exigir um cone artificial de câmera. Em duelo com um único candidato válido,
a previsão dispensa câmera. Camuflagem e equipes são filtradas antes do Dark Seal.
Os testes novos verificam recuperação, ativação e limpeza observáveis, sem exigir
a presença de gates ou constantes internas.
