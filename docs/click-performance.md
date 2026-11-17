# Otimização do envio de cliques

A mudança reduz trabalho Lua por clique. CPS, MS, CPF e Auto conservam a contagem e as regras de taxa anteriores. Não foi acrescentado limite nem fila de cliques. O limite de trabalho por frame e a acumulação máxima que já existiam no agendador continuam com os mesmos valores (128 solicitações e 100 ms).

- O agendador prepara um emissor por execução, reutilizando a validação de geração/contexto. O método de clique selecionado é consultado em cada envio.
- A validação completa deixa de se repetir dentro do mesmo clique. Ela continua ocorrendo antes do envio efetivo e novamente na retransmissão atrasada. Desligamento durante uma sequência interrompe os próximos cliques.
- A telemetria agrega as contagens por ciclo do agendador, com contadores separados de tentativas e aceites. Esses registros medem cliques já solicitados: não armazenam cliques para enviar depois. A janela de um segundo tem a precisão temporal do ciclo em que os cliques foram contados.
- O controle de envio em andamento usa um identificador numérico, e os erros são capturados pelo tratamento já existente do agendador, em vez de criar uma captura por clique.
- No Direct, a busca do Remote pode ser reutilizada por até 1/240 s (aproximadamente 4,17 ms); um objeto removido invalida a referência imediatamente. Isso é um cache de referência, sem espera ou redução da frequência de envio.
- A parte do pacote referente à câmera é reconstruída quando a câmera/CFrame muda. Cada clique continua recebendo um buffer próprio, sequência nova e timestamp novo, preservando os pacotes já capturados pelas retransmissões.
- O envio confiável, o envio Unreliable imediato e a retransmissão de 30 ms continuam presentes. O callback da retransmissão é reutilizado, com argumentos próprios para cada envio; não foi adicionada uma fila de retransmissões.
- Input reutiliza a referência ao VirtualInputManager e o callback de soltura. Cada pressionamento continua tendo sua soltura agendada.

## Verificação

A suíte cobre contagem em múltiplas taxas de frames e modos, primeiro clique, cancelamento dentro da mesma sequência, expiração de métricas durante envio suspenso, aceites parciais, troca de câmera/remote, buffers independentes, sequência de pacotes e todas as retransmissões.

Para repetir a comparação com o código anterior:

```sh
python3 "exodus hub/indeed/benchmarks/benchmark_clicks.py"
```

O benchmark carrega o agendador e o emissor reais em Lua 5.4, usando serviços/clientes simulados. Executa 1.200 ciclos a 100 CPF, equivalentes a 20 segundos simulados a 60 FPS. A coleta de lixo é pausada apenas durante a medição, para contabilizar as alocações, e não é alterada no hub.

Resultado de uma execução neste ambiente:

| Medida | Antes | Depois |
| --- | ---: | ---: |
| Cliques | 120.000 | 120.000 |
| Validações completas | 361.200 | 121.200 |
| Tempo de CPU do trecho | 0,4077 s | 0,1280 s |
| Memória alocada durante o trecho, sem coleta | 42.528,9 KiB | 266,0 KiB |

Esses valores medem o custo do código Lua com transporte simulado. Não medem FPS, carga de rede nem aceitação pelo servidor Roblox. O custo interno da habilidade Deflect e do VirtualInputManager continua pertencendo ao jogo/engine.
