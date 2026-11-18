# API interna

Os módulos são declarados no manifesto de `exodus hub/loader.luau`.
`__contract` descreve métodos exportados, dependências e métodos consumidos.
`Permissions.resolve` entrega somente as APIs declaradas. A ordem de setup segue
o grafo de dependências; ciclos são rejeitados. As assinaturas completas estão
nos contratos dos próprios módulos.

Conexões devem ser registradas em Utils e encerradas no teardown. Código de
combate pertence a `logic`; adaptação dos serviços do jogo, a GameInfo; componentes
visuais, a `front/library`; ações e apresentação, a `front/app`. Camera e AutoJump
são extras universais. `extras/spec.md` contém as restrições de execução desses
recursos.

## Dados, geometria e status

- **GameInfo**: objetos, habilidades, regiões, contexto pessoal da rodada,
  sincronização e snapshots. `getGameContext().inMatch` indica participação;
  `roundActive` indica apenas o estado global.
- **BallSync**: estado por sessão, decodificação, ordem e expiração dos pacotes.
- **DeflectGeometry**: constantes e cálculos de alcance, janela, resiliência,
  latência, treino e projeção. AP, AutoSpam e extras consomem essa API diretamente.
- **Status** (`core/status.luau`): `get(nome)` consulta um produtor e
  `collect(nomes)` coleta vários. Isola falhas e leituras recursivas. O loader
  configura os provedores; diagnósticos e UI usam a mesma API. `ClashStats`
  registra métricas do clash e também exporta `getStatus()`.
- **StatusView**: apenas formatação das observações para a UI.

```lua
local geometry = DeflectGeometry.resolve(speed, {
  window = 0.4, -- opcional: consulta a janela do jogo se omitido
  factor = 0.3,
  latency = ping,
})
local window = DeflectGeometry.getWindow(speed, { factor = 0.3 })
local rawWindow = DeflectGeometry.getWindow(speed, { raw = true })
local rawRadius = DeflectGeometry.getRadius(speed, { component = "raw" })
```

`resolve` devolve a geometria completa. `getRadius` aceita os componentes `full`,
`base`, `raw`, `resilience`, `window` e `ping`. No perfil comum, o raio é
`alcance bruto + velocidade × (janela + latência) × fator`: o fator não reduz o
alcance fixo. `latencyFactor` permite outro fator para o ping. `windowScale` e
`windowOffset` ajustam a janela daquela consulta; `resilience = false` usa o
alcance base e `ping = false` desconsidera latência.

`profile = "autoParry"` aplica as regras de antecipação por frame e latência;
`profile = "training"`, as regras do treino. O AP escolhe o fator adaptativo e
solicita a recomposição por `withAutoParryFactor`. `compose` combina parcelas
explícitas; `projectRadius` fornece o cálculo numérico sem alocar uma tabela.

## Targeting

`aux/targeting.luau` centraliza os leitores da partida. GameInfo injeta o estado
atual e expõe `getTargetSignals(time?)`; `getStatus().targeting` traz o mesmo
formato para diagnóstico. O treino usa seu próprio `BallState.goal` e não consulta
os leitores da partida.

Os 14 leitores são `sync.target`, `sync.highlight`, `replicator.target`,
`replicator.highlight`, `replicator.latestTargetId`, `replicator.IsLocalTarget`,
`history.target`, `history.highlight`, `workspace.GameBallTarget`,
`character.PlayerBallHighlight`, `ball.color`, `ball.trail`, `ui.BallIndicator` e
`ball.skinFace`. `docs/game.md` descreve as condições nativas desses sinais.

```lua
local report = GameInfo.getTargetSignals()
-- report.targeted: qualquer fonte disponível confirmou o jogador local
-- report.known: pelo menos uma fonte conseguiu responder
-- report.targetId: jogador local se houve positivo; senão, primeiro ID disponível
-- report.positive: nomes das fontes positivas
-- report.conflict: coexistem respostas positivas e negativas
for _, signal in ipairs(report.signals) do
  -- signal.name, family, state = "yes" / "no" / "unavailable"
  -- signal.available, targeted (boolean quando disponível), targetId (opcional)
  -- signal.reason explica indisponibilidade, ambiguidade ou falha de leitura
end
```

A regra de autorização é OR: um positivo prevalece mesmo com votos negativos.
Isso é uma política permissiva, não uma garantia de acerto. As fontes visuais
podem atrasar um frame, e várias leituras derivam do mesmo estado nativo.
Cor ambígua de skin, faces transitórias, elementos desabilitados/ocultos e fontes
incompatíveis não votam. Cada leitor isola suas falhas. Estado de rede vencido,
histórico que não corresponde à última sequência e replicador mais antigo que o
pacote aceito não confirmam alvo. Fora da rodada ativa os votos são limpos.

Snapshots expõem `targetSignals` e `targetSource`; `targetId`/`targeted` refletem a
resolução. `exchangeTargetId` preserva a identidade recebida pela rede, usada nas
trocas do AutoSpam. Sinais visuais não criam evidência de troca por dash/retorno.
Se houver conflito de alvo, o AP não simula a trajetória de outro jogador como
se fosse local. Se a identificação continua válida após expirar a sincronização,
o movimento usa a observação atual da bola, sem reciclar posição/direção antigas.
A autorização de alvo não ignora alcance, cooldown, congelamento ou personagem
morto. As leituras compartilham o cache curto de GameInfo, sem varrer a árvore
inteira do jogo a cada frame.

## AutoSpam

O manual é independente. A ativação automática usa:

- Retorno real `você → mesmo oponente → você`, dentro do intervalo permitido e
  da geometria calculada.
- Proximidade de até 5 studs **no pacote em que você vira alvo**. Aproximação
  posterior e envio da bola a outro jogador não qualificam esse gatilho.
- Haunter com evento de teleporte e condições geométricas válidas.
- Dash normal confirmado, com uma troca entre você e o mesmo oponente ocorrida
  durante esse dash. Velocidade/animação ou alvo sozinho não bastam; WindDash e
  tipo desconhecido são rejeitados.

Sequências antigas/duplicadas não criam trocas. Mudança de direção sem troca de
alvo não é retorno. As regras de continuidade do clash, miss e cooldown são
independentes da aquisição dessas evidências de ativação.

Miss isolado não encerra o AutoSpam. Cooldown bloqueado continuamente encerra a
sessão após a janela de defesa atual, latência e margem de frames. O prazo ganha
tolerância progressiva quando a ida e volta entre os alcances dos jogadores é
mais rápida que essa janela; distância e velocidade entram no cálculo, sem raio
fixo para essa tolerância. Cooldown liberado, reset previsto ou confirmação de
parry reiniciam a contagem. Aproximar/afastar altera o prazo sem reiniciar o tempo
já bloqueado. Após encerrar, é necessária nova evidência de ativação.

A saída física também observa posição, direção e alcance durante a janela atual:
a bola precisa estar fora do alcance temporal dos dois jogadores e se afastando
de ambos continuamente para encerrar a troca, mesmo com um alvo visual atrasado.
Oposição próxima não veta cooldown persistente, reset ou saída física confirmada.


## Carregamento e atualização

O manifesto de publicação contém a revisão do repositório e checksums por
arquivo. O cache reutiliza fontes com checksum correspondente e recompila as
instâncias por sessão. O checksum detecta diferenças de conteúdo; não é uma
assinatura criptográfica.

O loader autoriza e prepara os módulos antes de substituir o runtime. Runtime
centraliza watchers e distribuição de BallSync. Updater observa publicações via
WebSocket e polling; uma revisão com os mesmos arquivos executáveis pode ser
registrada sem reiniciar. Atualização automática aguarda a participação pessoal
terminar. Reload manual substitui uma espera automática e não aguarda rodada ou
clash. Animar a troca de interface pertence ao controller lifecycle.

## Anti-lag

| Configuração | Padrão | Efeito |
| --- | --- | --- |
| AntiLagEnabled | false | Ativa o otimizador e seu journal reversível. |
| AntiLagRenderDistance | 200 | Raio ao redor do personagem para cenário, personagens, bolas, efeitos e indicadores no mundo. |
| AntiLagFloorCull | true | Usa a menor altura pisada, com margem de 5 studs; mantém peças potencialmente visíveis no campo de visão. |

O culling usa limites de cada objeto e planos da câmera com margem apenas para
o campo de visão. A distância não tem margem adicional nem exceções para
personagens, bolas, indicadores ou objetos `AntiLagKeepVisible`. Peças móveis são
reavaliadas; efeitos, luzes, nomes e interfaces 3D usam a posição de seu suporte
ou Adornee. Ocultar partículas e trails também limpa os rastros já emitidos.

Indexação, ocultação e restauração têm orçamento por frame. O journal restaura
as propriedades ao desligar o recurso; colisões, toque e consultas físicas não
são alterados. Texturas são preservadas.

O filtro atua sobre instâncias: peças e beams que cruzam o limite são mantidos
inteiros para preservar o trecho próximo. A API pública não oferece recorte
esférico por pixel nem corte local do Terrain sólido sem alterar voxels. Efeitos
emitidos de dentro do raio podem se estender além dele; isso não é um far clip
global do motor. Mudanças são aplicadas gradualmente conforme o orçamento.
