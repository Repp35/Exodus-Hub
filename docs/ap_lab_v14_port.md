# Integração das melhorias do AP LAB V14

Comparação feita sobre a `main` em `076ada7c`, incluindo as alterações recentes
em AutoSpam e Cooldown. O laboratório foi utilizado como referência de
comportamento, sem incorporar seu bootstrap, UI ou ciclos de RunService paralelos.

| Caminho | Hub anterior | Integração |
| --- | --- | --- |
| Sync | Remotes e leitura do replicador | Observação de `ApplySnapshot` depois do método original, além dos remotes; amostras nativas validadas por tempo, posição e sequência. |
| Confirmação | Evento remoto de cooldown/parry | `BallFeel.Hit` filtrado por tipo de evento e jogador local; remoto como fallback quando o canal nativo não está disponível. |
| Alvo do AP | Alvo consolidado podia vetar outros sinais | Slots independentes para pacote, highlight, provider, atributo, cor e marca; visuais exigem duas amostras de simulação distintas. |
| Rearme | Dependência da trava por alvo e do cooldown | Episódios ordenados e retorno confirmado com amostra posterior e direção de aproximação; evento antigo não rearma outro disparo. |
| Clash | Trava de disparo bloqueava repetição | Repetição autorizada pelo `GameBall:IsInClash`, com intervalo mínimo de 8 ms e validação nativa de cada tentativa. AutoSpam continua tendo prioridade quando ativo. |
| Geometria | Recalculada para aplicar o fator adaptativo | Cálculo único de aproximação, janela e pressão adaptativa; limite da janela nativa em clash. |
| Simulação | Duas simulações mesmo dentro do raio físico | Segunda simulação apenas quando precisa de velocidade; descarte prévio de amostras muito distantes e cache de projeção de até 1 ms, condicionado a amostra, bola, provider e posição do alvo. |
| Métrica | Pico de CPS instantâneo entre duas chamadas | Janela móvel de um segundo para chamadas aceitas pelo cliente, como no laboratório. Não representa confirmações do servidor. |
| Treino | Zona e janela aproximadas; espera por spawn explícito | `TrainingShared.InZone`/`GetBlockWindow` quando disponíveis, fallback existente, limite de chamadas, retomada somente por amostra nova válida e piso temporal contra pacotes antigos. |

Os sinais adicionais são usados pelo AP. A seleção de alvo consolidada que
alimenta o AutoSpam continua respeitando sua precedência existente. A ingestão de transições do AP também continua durante uma avaliação ou envio
em andamento, sem sobrescrever o episódio novo ao concluir uma chamada antiga.
O arquivo
de AutoSpam e suas regras recentes de ativação não foram modificados.

## Fierce e miss

A inferência anterior podia classificar um miss durante a janela pendente,
durante um reset previsto ou sem relacionar a tentativa a uma chamada aceita.
Agora a classificação considera esses estados e a confirmação do próprio parry.

O Fierce exige cooldown local ainda ativo, tentativa aceita correspondente,
janela conhecida encerrada e margem de latência. Na ausência de informação
suficiente para distinguir uma defesa pendente de um miss, não ativa. A guarda
revalida episódio, tentativa, confirmação e bola antes de chamar a habilidade;
um novo clique aceito ou parry confirmado invalida uma decisão anterior.

Se o jogo deixar de expor a janela pendente, o estado básico do cooldown
continua disponível, mas o resgate automático fica conservador em vez de gastar
Fierce com base apenas num timeout estimado.

## Configuração, validação e limites

- Novas configurações usam fator base `0.45`, como o laboratório. Valores salvos
  e ajustes manuais existentes são preservados; para comparar o mesmo cenário,
  use também o mesmo fator, método de clique e recursos ativos.
- Treino usa intervalo mínimo de 30 ms e o limite de CPS da partida (16 como
  fallback). Partida usa intervalo mínimo de 8 ms; a habilidade nativa mantém
  suas próprias restrições de disponibilidade e limite.
- O hook mantém argumentos e todos os retornos do método original. Ao fechar ou
  recarregar, é desativado e restaurado apenas se ainda possuir o método, sem
  sobrescrever um wrapper de outro script.
- A inicialização e o agendamento continuam modulares, com PostSimulation,
  eventos e verificação temporal em PreSimulation. Não foram adicionados loops
  de combate em RenderStepped nem cópias das avaliações do AutoSpam.
- A suíte padrão continua verificando APIs, permissões, compilação e carregamento
  Luau. Não foram adicionados testes que fixem regras ou valores do combate.

Os valores de aproximadamente 4 CPS no hub e 10/40 CPS no laboratório foram
relatados pelo usuário. Não houve medição em Roblox nesta sessão; não se pode
atribuir uma taxa obtida ao código integrado sem executar a mesma situação no
cliente real. Use `AutoParry.getStatus()` e a captura de runtime para comparar
chamadas aceitas, retornos, simulações e tempo de frame, incluindo treino,
clash, clique manual, miss real e Fierce.
