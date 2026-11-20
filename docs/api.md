# API interna

Os módulos são declarados no manifesto de `exodus hub/loader.luau`.
`__contract` descreve a interface pública, imports e APIs mínimas necessárias à
compatibilidade. Essas listas não concedem permissões. `Permissions.resolve`
entrega views de dependências filtradas pela família do consumidor, com tabelas
somente para leitura. APIs novas da mesma categoria não exigem novos grants por
método. A ordem de setup segue os imports; ciclos são rejeitados.

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

Os dois leitores são `replicator.IsLocalTarget` e `workspace.GameBallTarget`.

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
Cada leitor isola suas falhas. Replicador vencido ou mais antigo que o pacote
aceito não confirma alvo. Fora da rodada ativa os votos são limpos. Sinais
visuais derivados não participam da autorização.

Snapshots expõem `targetSignals` e `targetSource`; `targetId`/`targeted` refletem a
resolução. `exchangeTargetId` preserva a identidade recebida pela rede, usada nas
trocas do AutoSpam. Sinais visuais não criam evidência de troca por dash/retorno.
Se houver conflito de alvo, o AP não simula a trajetória de outro jogador como
se fosse local. Se a identificação continua válida após expirar a sincronização,
o movimento usa a observação atual da bola, sem reciclar posição/direção antigas.
A autorização de alvo não ignora alcance, cooldown, congelamento ou personagem
morto. As leituras compartilham o cache curto de GameInfo, sem varrer a árvore
inteira do jogo a cada frame.

## Perigo físico compartilhado

`DeflectGeometry.getDanger(position, velocity, targetPosition, speed, range,
responseTime, targetVelocity)` calcula a entrada na esfera do alcance nativo,
considerando a velocidade relativa do jogador. Retorna `score` (0–100), `ready`,
`entryTime`, `responseTime`, `alignment`, `closestDistance` e `closingSpeed`.
A trajetória precisa interceptar a esfera: aproximação radial sozinha não basta.
O índice representa urgência, não probabilidade de acertar ou ser o alvo:
100 significa contato; 50 é a fronteira `entryTime == responseTime`; uma
trajetória que não intercepta o alcance recebe zero. Não há espera de confirmação
nem acumulação de amostras para liberar o clique.

AP usa a janela configurada e a margem de reação. A ativação do AutoSpam
não exige identificar o oponente no gate de proximidade ou no retorno visual;
a associação pode acontecer depois, quando uma troca fornece essa evidência.
A cor vermelha pode confirmar o alvo local, sem substituir um alvo de terceiro
confirmado. Treino e spam manual mantêm regras próprias.

## Pré-ativação em contato extremo

A previsão exige uma animação de deflect observada no oponente, ainda válida e
não consumida. Também exige alvo local ou do oponente, previsão de mira para o
jogador local e retorno dentro do orçamento de 100 a 250 ms, conforme latência
e frame. A distância entre jogadores é limitada ao maior entre 13 studs e o
raio de defesa sem janela; a bola deve estar dentro do raio calculado com 0,8
da janela. Uma tentativa e uma perna da bola não são reutilizadas.

A fase especulativa termina ao confirmar o alvo local, expirar, ter a previsão
desligada ou mudar a mira prevista. O prazo é limitado a 450 ms. Isso não
garante o deflect ou o alvo real escolhido pelo oponente.

## TTI recebido no clash

ClashStats registra `lastIncomingTTI` e `previousIncomingTTI` ao receber uma troca
real de alvo para o jogador local; frames ou pacotes repetindo o mesmo alvo não
refazem a amostra. `incomingRecordedAt` identifica a medição. O painel Travel
mostra essas duas estimativas em milissegundos, inclusive após a morte.
`lastOutgoingTTI`, `previousOutgoingTTI` e `outgoingRecordedAt` registram de forma
separada a mesma medição na troca para o oponente, sem esperar a chegada da bola.

O TTI é estimado no recebimento pela distância até o raio de impacto, velocidade
de aproximação relativa ao jogador e aceleração positiva disponível. Não é um
cronômetro de tempo como alvo, nem o intervalo entre dois deflects. Trajetórias
sem aproximação válida ficam indisponíveis, sem produzir infinito. Curvas e
mudanças posteriores de velocidade podem alterar o tempo efetivo de impacto.
Reiniciar o AutoSpam preserva as últimas amostras da mesma bola.

## AutoSpam

A bola deve estar válida, em movimento e fora de treino; o hub e o AutoSpam
precisam estar ligados e o jogador vivo. As entradas são:

- Alvo local com bola a até 5 studs no momento da troca, sem exigir parceiro.
- Retorno local observado por rede ou cor, com a bola dentro do raio calculado
  com 0,8 da janela. A sequência de rede aceita retorno em até 600 ms mais
  latência; a cor também pode fornecer o alvo local sem parceiro identificado.
- Previsão com animação de deflect, conforme a seção anterior.
- Dash normal com troca confirmada durante o dash, ou evento Haunter válido.

Depois da ativação, uma troca pode identificar o parceiro. O AutoSpam não possui
saída por distância entre jogadores. Cooldown bloqueado continuamente encerra
após `225 ms − 125 ms × progresso de velocidade + latência`, somando 120 ms
quando o parceiro está a até `10 + 6 × progresso` studs. Progresso varia de 0
a 1 entre velocidades mínima e máxima; a margem é removida imediatamente ao
sair da distância. Reset previsto, liberação ou confirmação de parry reiniciam
a contagem. O mesmo prazo limita o tempo com o alvo no parceiro aguardando o
retorno ao jogador local. Alvo desconhecido não inicia esse relógio.

A saída física requer bola fora do raio dos dois e afastando-se de ambos por
120 ms. Reset, teleporte, pausa, treino, fim de partida, mortes, desligamento e
redirecionamento confirmado para terceiro são saídas próprias. Os gates de
ativação são avaliados no estado inativo; os de saída, no estado ativo. Uma
entrada consumida não dispara repetidamente. Dynamic mantém sua política de
saída própria e seu contexto de sessão separado.

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
| AntiLagRenderDistance | 300 | Raio configurável entre 300 e 1200 studs ao redor do personagem; valores salvos inferiores usam 300. |
| AntiLagFloorCull | true | Mantido por compatibilidade; o corte inferior fica sempre ativo. |

O filtro oculta instâncias inteiramente fora do raio configurado ou inteiramente
abaixo de 2 studs da menor altura alcançada pelo personagem. Peças que cruzam
os limites permanecem visíveis para preservar o chão, paredes e personagens. Luzes, sombras e efeitos de
pós-processamento são desativados. As alterações são locais e reversíveis.

A API utilizada não corta Terrain sólido e não impede a replicação de objetos.
Depois que uma instância é liberada para aparecer, ela não é ocultada novamente
pelo anti-lag enquanto existir, mesmo que saia do raio configurado. O corte
inicial e a indexação são graduais. A liberação de objetos antes ocultos é limitada
a 4 a cada 0,1 segundo e também por orçamento de tempo; colisões e consultas
físicas permanecem.

O AP avalia também `PreSimulation`, além do tick após física e dos eventos de
sincronização. Qualquer fonte positiva de alvo local vence fontes negativas.
O primeiro envio reserva o ciclo antes do remote; uma trava de requisição em
voo impede envios concorrentes mesmo se um evento de alvo rearmar o ciclo
durante a chamada. Alcance físico, cooldown e validade da bola continuam sendo
revalidados no envio.

A identificação de alvo em partida usa somente `BallReplicator:IsLocalTarget()`
e `Workspace.GameBallTarget`. O primeiro compara `latestTargetId` com o jogador
local; o segundo recebe a atribuição do servidor na troca de alvo. Qualquer sim
autoriza o alvo local. Cor, trail, highlight, UI e histórico não autorizam o AP.
A ordem de chegada dos dois caminhos depende da replicação em execução.

## Assistências de Phantom Ball

A página utilitária `assists` tem atalho próprio ao lado do Config, com PNG
embutido. `ManualSpamUIOnDuel` e `ParryOnDeath` são persistentes e desativados por
padrão. O x1 exige partida ativa, jogador local vivo e exatamente dois jogadores
com vidas e personagem vivo; a transição abre somente a GUI do spam manual no mobile, sem ligar cliques.
A opção fica oculta no desktop e permite fechar a GUI depois. `ParryOnDeath` religa o AP no evento de morte.
As conexões são removidas no teardown/reload. A página universal é independente.

O dumper agenda lotes de até 100 scripts concorrentes, incluindo lotes menores
inteiros, e aguarda sua conclusão antes de iniciar outro lote ou escrever o
resultado final. Scripts sem fonte passam por até 10 novas rodadas após a
tentativa inicial, encerrando cedo quando recuperados. Cancelamento e erros
de workers são propagados ao controlador; os manifestos mantêm o índice original.

## Disponibilidade de habilidades

`GameInfo.getAbilityAvailability("dark" | "dash" | "fierce")` retorna booleano
e motivo de indisponibilidade. Usa `ClientAbilities.Abilities`, que o
AbilityManager do dump limpa e recria ao receber o equipamento do servidor,
e bloqueia `CurGamemode == 3` (sem habilidades). Não confunde cooldown com
equipamento. A UI valida antes de habilitar automações ou seus botões flutuantes
e exibe o motivo da recusa. Dark e Up Dash ficam ocultos sem a habilidade,
inclusive após troca de equipamento; a configuração de visibilidade é preservada.
Auto Jump é universal e não depende de habilidade equipada nem desse modo.

## Dynamic Parry

`logic/dynamicparry.luau` é um controle manual, sem ativação por alvo. Um toque
envia uma chamada nativa `Deflect()`; manter o botão por 180 ms inicia o spam.
Em Toggle, soltar mantém a rajada e o próximo clique encerra. Em Hold, soltar
encerra. `DynamicParryKey` seleciona a tecla no PC e tem prioridade sobre os
atalhos do hub quando o recurso está habilitado.

O módulo adapta o componente mobile nativo: preserva o ImageButton circular,
borda interna, constraints e layout. Remove o escudo e o texto BLOCK; ON/OFF
fica centralizado, com fundo vermelho/verde. O frame e o botão acompanham as
mudanças de tamanho e posição do original, sem dimensão própria. Usa a API
`Shared.UI.ButtonAnimations:Bind/Unbind` e as referências de cooldown/flash
nativas. `GameInfo.getNativeButtonAnimations()` centraliza o acesso à biblioteca.
O frame original fica oculto; referências, input nativo e visibilidade são
restaurados ao desligar/recarregar. Respawn e troca de interface reanexam o botão.
O envio usa `Remote.fireNativeParry`, independentemente de `ClickMethod`, para
manter o fluxo e as animações nativas. A rajada usa o scheduler único de Spam,
com estado independente de manual spam e AutoSpam.

O Dynamic mantém sua própria sessão e consulta `Cooldown` diretamente, sem
usar o estado, a configuração ou funções do AutoSpam. `DynamicParryDeactivation`
habilita somente a saída automática por cooldown contínuo, após 300 ms mais ping.
O limite varia com velocidade, latência e proximidade (10–16 studs), como no
AutoSpam, mas os timers são independentes. Alvo, reset da bola e distância não
encerram o Dynamic. Morte, desligamento e controles manuais continuam encerrando.
O AutoSpam também não encerra por `target_return_timeout` nem por `ball_reset`;
resets ainda limpam evidências para impedir ativações com dados de outra bola.

## Clique manual e controle

Imediatamente antes de reservar o envio do AP e na guarda final do remote, o AP
lê `DeflectAbility.LastDeflectCallAt` (fallback `LastPressClock`) com `pcall`.
Uma chamada manual desde a entrada no alvo atual bloqueia o AP nesse ciclo; a
marca da própria chamada do AP é excluída. Uma nova volta de alvo libera o ciclo.
Falha de leitura não bloqueia nem agenda verificações. O mesmo marcador nativo
cobre Dynamic, mouse, teclado e toque que passam por `Deflect()`.

Dynamic Parry fica abaixo de Manual Spam na Main. O botão selecionado aceita
as entradas de teclado, mouse e gamepad reconhecidas pelo Roblox. O hub aceita
captura de botões de gamepad, seleção de controles, ativação nativa e sliders
pelo direcional. `ButtonSelect` ou a tecla `Menu` abre/fecha o painel; com ele
aberto, o gamepad navega a interface sem disparar atalhos de combate. O foco é
restaurado no teardown. Remotos de TV dependem dos eventos de teclado/gamepad
expostos pelo Roblox no dispositivo, sem inferência de protocolos de hardware.

A bola e seus descendentes são excluídos dos cortes espaciais e da remoção de
efeitos do otimizador. Ao trocar a bola, suas propriedades são restauradas
imediatamente. A visão é avaliada em `PreRender`; objetos ocultos que entram na
visão são restaurados na atualização da câmera, sem a antiga fila de 48 por
passagem. A indexação e os cortes restantes continuam incrementais.

As páginas usam fade sequencial: a página atual desaparece antes da próxima
aparecer, com apenas um CanvasGroup de página visível por vez. Uma revisão por
transição cancela callbacks antigos e um finalizador garante a página ativa.
Notificações persistentes e de falha de inicialização reaplicam texto branco
sem RichText, inclusive ao reutilizar cartões existentes.

## Verificação de permissões antes de publicar

`indeed/tools/check_permissions.py` roda no workflow antes do build protegido.
Lê a mesma política JSON embutida em `permissions.luau` usada pelo runtime.
Valida imports/exports, cobertura do manifesto e capacidades de família em
acessos diretos ou por alias, incluindo os controllers que recebem as views da
UI. Falhas indicam arquivo, linha, família e capacidade proibida; interrompem o
build. `--report` lista todos os módulos e as capacidades fixas de cada família.
O verificador não amplia permissões nem remove a proteção de runtime. Acessos
computados e repasses arbitrários de tabelas continuam dependendo da validação
de runtime em `permissions.luau`; a análise estática não prova esses casos.

## Separação de plataforma e customização

O UIKit identifica mobile/desktop pelas capacidades de entrada e pela opção
`ForcePCUI`. A API recusa componentes com `desktopOnly` em mobile e vice-versa;
seletores `keybind` são exclusivos de desktop e atalhos visuais não são criados
no mobile. O seletor do Dynamic está marcado `desktopOnly`. O layout mobile
continua acessível pelo botão de toque, sem ativação pela tecla de PC; a opção
PC UI é a exceção explícita.

`AutoSpamClashPrediction` controla somente a ativação antecipada por previsão,
com padrão true. A opção filha de AutoSpam é renderizada quando a capability
`clashPrediction`, fornecida por `AutoSpam.hasClashPrediction()`, está presente.
Geometria de segurança e demais gates continuam independentes dessa opção.

`Player.MobileLayoutEditing`, confirmado no MobileLayout do dump, suspende o
Dynamic e restaura imediatamente o componente Block e suas referências durante
a edição. Ao sair, o substituto é recriado com o tamanho e a posição ajustados,
se Dynamic Parry ainda estiver habilitado. A edição não dispara o Dynamic.

## Famílias de responsabilidade

A política fixa fica em `permissions.luau`. A família é derivada da organização
do manifesto, nunca de grants pedidos pelo próprio módulo. Todos recebem
leitura interna, diagnóstico e gerenciamento de suas inscrições. As capacidades
de comando são compartilhadas integralmente dentro de cada família:

| Família | Responsabilidade adicional |
| --- | --- |
| combat | Executar ações e coordenar estado temporário de combate. AP, AutoSpam, Spam e Dynamic usam exatamente este perfil. |
| game | Manter adaptadores e sincronização do jogo. |
| presentation | Editar preferências, controlar input manual, criar a interface e executar ferramentas por ações do usuário. |
| view | Montar componentes visuais, sem editar configurações globais. |
| lifecycle | Vincular personagens e limpar estado temporário; não dispara ações de combate. |
| universal | Controlar recursos universais; só escreve configurações com prefixo Universal. |
| render | Controlar renderização; só escreve configurações com prefixo AntiLag. |
| tools | Executar dump e navegação de servidores, sem controlar outros recursos universais. |
| infrastructure | Bootstrap, registros e administração central. O loader é a raiz privilegiada. |

Leitura interna não inclui escrever tabelas nem chamar APIs de comando de UI.
Tabelas exportadas que contenham funções são classificadas como APIs da família
provedora, não apenas dados. A classificação das operações é separada dos grants
dos consumidores: declarar uma dependência ou acrescentar `setConfig` ao contrato
não dá ao combate `config.write`.

`Permissions.policy(name)` expõe família, capacidades e imports; não existe
lista de permissões AutoSpam → AP ou por arquivo. Dependências continuam sendo
imports explícitos e requisitos de versão/API, como contratos de compatibilidade.

As preferências de religar AP na morte e mostrar a GUI de spam no x1 pertencem a
`front/controllers/assists.luau`. O controlador de personagem não altera essas
preferências. Dumper e Servers ficam em `extras/universal/tools/`, com perfil de
ferramentas. O verificador proíbe capacidades de UI/configuração no perfil combat
e detecta acessos diretos ao registro global que contornem as views.

Essa é uma fronteira de arquitetura nas APIs internas, não um sandbox da VM ou
do motor Roblox; código nativo, objetos do jogo e acessos dinâmicos arbitrários
não são isolados por ela.

Sliders capturam o arraste no `UserInputService.InputBegan`, apenas se o contato
começar dentro do hitbox. Contêineres e decoração não bloqueiam a captura; um
botão interativo sobreposto bloqueia. Se a consulta da GUI não estiver disponível,
a geometria do contato inicial continua válida. Entrar
no hitbox com um toque já iniciado fora não captura o gesto. Movimentos são
aceitos somente do mesmo toque ou do mouse com botão esquerdo ainda pressionado.
Soltar, cancelar, ocultar, desabilitar, suspender ou perder foco libera a captura.
Navegação por teclado/controle permanece independente do arraste por ponteiro.

Chamadas repetidas de `Loader.start()` enquanto existe inicialização em curso
são reconhecidas com `true, nil, nil, "in_progress"` e apenas exibem um aviso.
Não há nova inicialização, rollback, notificação crítica ou alteração de
`Exodus.Started`/`StartError` nesse caminho; a chamada que possui o token continua.

AutoSpam e Dynamic mantêm contextos e decisões de saída distintos. Uma recusa
momentânea de envio não desativa a sessão Dynamic. O contexto manual pode herdar
a referência do clash ativo sem compartilhar suas tabelas mutáveis.

Filhos usam frames sem máscara intermediária, preservando bordas e strokes.
Abertura/fechamento altera visibilidade e altura sem recortar o componente.

### Gate de retorno do AutoSpam

`return_target` exige a sequência de alvo local → adversário → local na mesma
bola, com retorno em até 600 ms mais a compensação de latência já usada pelo
módulo. A distância deve estar dentro do `fullRadius` calculado com window
factor `0.8` no instante do retorno e na avaliação da ativação. Essa window é
um limite espacial, não um substituto da sequência de alvo. Uma volta fora do
raio não fica armada para ativar por aproximação posterior. A cor da bola só
serve como fallback quando não existe alvo conhecido; sozinha não comprova
uma ida e volta nem sobrescreve um alvo confirmado. O painel distingue
`return_no_round_trip`, `return_expired` e `return_outside_window`.

### Clash Prediction: armar e aguardar BlockStart

A previsão usa apenas o jogador que é alvo atual da bola. Primeiro simula a
geometria do AP no oponente, com o raio publicado daquele jogador, sua janela
de clash, movimento e tempo até o contato. Se esse AP estaria pronto, prevê o
alvo pela câmera (`CamCFrame`), respeitando equipes, invisibilidade e Dark Seal;
a orientação do corpo é apenas fallback e exige maior separação entre alvos.
Cabeça não substitui a câmera: no dump ela acompanha a câmera com interpolação.
A câmera enviada no clique pode diferir da última câmera replicada, portanto a
seleção continua sendo uma previsão, não uma confirmação do servidor.

O retorno hipotético é testado contra a região física de acerto. A margem
base é 240 ms mais a latência de uma via, multiplicada por
`AutoSpamPredictionMargin` (padrão `1`, slider de `0.5x` a `2x`).
Esse fator altera somente a margem temporal do perigo, sem ampliar o prazo de
contato nem a validade da animação.

Passando as duas simulações, o painel mostra `armed_waiting_blockstart` sem
enviar cliques. Somente um `BlockStart` recente do mesmo oponente e trecho da
trajetória libera o spam, após revalidar alvo, mira, proximidade e perigo.
`BlockLoop` e `Parry` não disparam prediction. O scan recupera um BlockStart
perdido respeitando seu tempo real de reprodução; eventos que chegam logo antes
da atualização do alvo podem ser associados à troca em até 40 ms. Reset,
troca de alvo e desligamento invalidam o estado armado.

A proximidade de até 5 studs também exige essa ida e volta válida; uma chegada
comum não inicia AutoSpam. Ativar consome a evidência em ambos os gates,
impedindo reativação a partir do mesmo retorno após uma parada.

A evidência de ida e volta exige alvos confirmados nas três etapas. Cor visual
sozinha não confirma posse nem cria uma ida ou uma volta para este gate.

### Refinamento da previsão baseado na primeira implementação com animação

A decisão de perigo não usa mais o maior raio expandido entre AP e AutoSpam.
O retorno precisa alcançar a região física de acerto, considerando contato e
trajetória de devolução, dentro de `(240 ms + latência de uma via) × fator`.
A geometria do AP do oponente continua sendo exigida, mas o contato também deve
ser iminente: no máximo `80 ms + latência`, limitado a 160 ms e à janela do AP.
O BlockStart precisa ter idade inferior a `120 ms + latência` (máximo 250 ms),
e o contato deve ocorrer antes de sua validade expirar. Estar tocando não
renova essa evidência. O fator de margem não altera esses limites de contato
ou idade da animação. São estimativas locais que precisam de validação em jogo.

A previsão também exige alinhamento absoluto mínimo de 0.75 pela câmera ou
0.9 no fallback do corpo, além da separação entre os melhores candidatos.
Ser apenas o candidato mais alinhado não basta. A distância da dupla precisa
caber no raio de perigo calculado pela velocidade e window 0.3, e seu tempo
estimado até a área de acerto deve caber na margem. Uma bola já se afastando
do oponente é recusada mesmo se ainda estiver dentro do raio físico dele.
