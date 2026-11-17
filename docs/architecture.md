# Organização do hub

O loader é o ponto de entrada remoto. Ele resolve a publicação, verifica a
 autorização, baixa e confere fontes, valida contratos, ordena dependências e
coordena a inicialização e a limpeza em caso de erro.

## Infraestrutura

- `exodus hub/modules/core/updater.luau`: ciclo de atualização, exclusão de
  reloads concorrentes, polling, WebSocket, comparação de versões e encerramento
  do canal. `create(deps)` constrói uma sessão sem abrir conexões; `start()`
  inicia a observação somente após o startup ter sucesso. `stop()` encerra o
  canal existente. A preparação e a verificação do código remoto são fornecidas
  pelo loader, mantendo uma implementação única do transporte e do cache.
- `exodus hub/modules/core/runtime.luau`: instalação dos watchers, manutenção de
  BallSync e distribuição dos eventos aos assinantes declarados nos contratos.
  `bind(loaded, order, httpService, reportError)` retorna o estado das conexões.
  Os recursos continuam registrados em Utils para limpeza da sessão.

Os dois módulos entram no manifesto normal: são baixados com assinatura,
reutilizam o cache e participam da validação de contratos. A fábrica do updater
é executada após a autorização e reutilizada quando o registro é montado;
não é necessário executá-la duas vezes. O canal só inicia após o runtime e a UI
estarem prontos.

## Funcionalidades e apresentação

- `modules/logic/aux`: estado e serviços compartilhados de combate, personagem,
  movimento, cooldown, comunicação e contratos de acesso.
- `modules/logic`: regras de Auto Parry e spam; `extras` contém recursos opcionais.
- `modules/front/app`: configuração, definições e ações da aplicação.
- `modules/front/controllers`: interação, ciclo visual, janela, notificações e
  telemetria; `front/ui.luau` coordena a construção da interface.
- `modules/front/library`: componentes e infraestrutura visual reutilizáveis.

Novos recursos devem declarar dependências em `__contract`, consumir somente as
APIs solicitadas e registrar conexões para teardown. O updater decide quando
substituir uma sessão; o controller lifecycle executa a animação; o runtime
entrega eventos às regras de negócio. Evite adicionar lógica de gameplay ao
loader ou chamadas de rede aos componentes visuais.

## Verificação

Execute a suíte Python em `exodus hub/indeed/tests`, os harnesses
`update_channel_regression.py` e `ui_transition_regression.py`, a verificação de
ícones e `formatter.py --check`. Os harnesses executam Lua com serviços simulados;
eles verificam regras de lifecycle e contratos, sem substituir a validação do
executor.

## GameInfo e estado da bola

`gameinfo.luau` mantém a API pública existente e adapta os objetos e serviços do
jogo. Duas dependências internas são resolvidas pelo contrato e pelo manifesto:

- `logic/aux/ballsync.luau`: fábrica por sessão, validação e decodificação dos
  pacotes, sequência de 16 bits, seleção entre pacote recebido e replicador,
  expiração e instante de recebimento. A aplicação de dados aceitos invalida o
  cache de snapshots através de um callback. Não instala conexões adicionais.
- `logic/aux/deflectgeometry.luau`: cálculo de raios, antecipação e projeção de
  defesa, usando a configuração central e as consultas do GameInfo. Não guarda
  estado da bola nem abre conexões.

GameInfo continua responsável por treino, descoberta de objetos e habilidades,
conexões, snapshots e integração com a física fornecida pelo jogo. Cada setup
cria uma instância nova do estado de pacotes; snapshots e consumidores consultam
essa mesma instância. Os consumidores de GameInfo não precisam mudar suas APIs.
