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

## Auto spam: observação, TTI e disparo

Os três caminhos principais compartilham a geometria da window completa
(fator 1) e o cálculo físico de entrada no alcance de defesa, com movimento
relativo e latência. A condição de janela é `entryTime <= effectiveWindow`;
`fullRadius` identifica a projeção completa do alcance e da window. Não há espera
por um timer para decidir que a bola entrou nessa janela. O guard de cada envio
recalcula a mesma condição de TTI.

| Caminho | Evidência de ativação, além da window/TTI |
| --- | --- |
| Proximidade | Ao virar alvo, a bola estava a até 5 studs. Salva distância e posição nesse instante; aproximar depois não reescreve o evento. |
| Return | O alvo deixou de ser local e voltou rapidamente, dentro de `RETURN` mais latência. Uma única ida e volta é suficiente. |
| Animação | Tentativa de defesa do adversário observada, com alvo local **ou** no adversário. A previsão usa alcances e TTI; não exige exclusivamente a perna de saída. |

Pacotes e replicador alimentam o mesmo histórico de rede. Atributo de alvo,
snapshot resolvido e observação do AP têm históricos próprios: uma amostra
atrasada de outra origem não apaga a metade de uma troca. A sequência de 16 bits
é deduplicada apenas na entrada de rede, sem ser adiantada por snapshots/AP.
O watcher transmite `GameBallTarget` diretamente no callback da mudança.

O AP entrega exatamente o alvo que reconheceu, sem substituí-lo pelo
`exchangeTargetId` de outro canal. Faz isso quando reconhece a mudança e antes
do envio. O auto spam também avalia nas fases de simulação e renderização
existentes. A integração não cria uma condição adicional de ativação e uma
falha no módulo de spam não impede o AP de continuar avaliando sua defesa.

As animações `BlockStart`, `BlockLoop` e `Parry` são classificadas por asset e
retidas com vida limitada. Eventos iniciam avaliação imediata; varreduras curtas
recuperam tracks em execução/streaming. Tentativas consumidas não são renovadas
indefinidamente por um loop. Respawn e detach removem os observadores antigos.
A antecipação termina pela window física prevista ou pela confirmação da volta,
sem um orçamento de ativação arbitrário de 100 ms.

`getStatus()` informa histórico recente por origem, distância no recebimento do
alvo, TTI/window de proximidade, return e envio, além da última falha por etapa.
Falha numa previsão opcional é registrada e não impede outro caminho pronto.
Morte, reset, congelamento e desativação continuam sendo limites de ciclo de vida.

Os testes de cenários exercitam perda de eventos entre canais, retorno rápido,
distância no instante correto, animação nas duas pernas, TTI e integração real
entre AP, AutoSpam e Spam com serviços simulados. Não equivalem a uma medição
de latência ou a uma garantia de resultado do servidor em partida.
