# Revisão dos módulos de lógica

Esta revisão cobre o loader e todos os 26 arquivos Luau em `modules/logic`. A UI mantém as correções anteriores. Não foram criados módulos de código adicionais.

## Regra de otimização

O aviso de [sped.md](../exodus%20hub/modules/logic/extras/sped.md) foi mantido. Os sinais, loops e intervalos existentes de `extras` e `universal` continuam presentes. Em particular, Speed mantém tanto a aplicação em simulação quanto em RenderStepped; Fly, Gravity, Noclip, AutoDark, AutoJump e AutoFierce mantêm suas rotinas por frame. Nenhuma delas foi substituída por um timer mais lento.

As mudanças funcionais são correções de falhas: entradas inválidas, cancelamento, restauração, falhas ao ativar, personagem substituído, iluminação invertida e estados que permaneciam ativos indevidamente. O comportamento em execução ainda precisa ser observado no Roblox.

## Módulo por módulo

Os caminhos abaixo são relativos a `exodus hub/modules/logic/`.

| Módulo | Correção ou melhoria |
| --- | --- |
| `autoparry.luau` | Rejeita vetores e snapshots inválidos ou antigos; timing usa a velocidade sincronizada quando disponível e preserva a posição prevista no treino; consultas após teardown ou sem geometria deixam de indexar nil. Os fatores de janela e os raios de combate existentes permanecem. |
| `autospam.luau` | Desativa ao teleportar a bola ou perder o oponente; impede envio após perda do personagem ou desativação; remove cálculos sem uso e chamada duplicada de troca de alvo. |
| `spam.luau` | Pedidos antigos não alteram a geração nova; mantém os modos de taxa, mas cede execução a cada lote de 32 pedidos para evitar bloquear o scheduler em rajadas; valida o intervalo automático. |
| `aux/character.luau` | Libera o worker e limpa o personagem mesmo quando o processo de vínculo lança erro. |
| `aux/clashstats.luau` | Finalização tolera horário ausente; encerra observações expiradas; evita ler um root já removido. |
| `aux/cooldown.luau` | Busca de evento ausente respeita o retry existente, consultas após teardown são seguras e erros repetidos deixam de inundar o console a cada frame. |
| `aux/dash.luau` | Valida o tipo do root e horários não finitos; a amostragem se recupera de recuo do relógio. |
| `aux/gameinfo.luau` | Valida vetores e IDs, rejeita bola removida, usa decoder alternativo quando o nativo não retorna dados, reinicia o relógio de treino por rodada, reutiliza entradas do cache de dash e mapas de nomes de partida. Busca do módulo de crates tem timeout. |
| `aux/movement.luau` | Rejeita direção inválida antes de normalizar ou disparar a habilidade. |
| `aux/permissions.luau` | Rejeita versões infinitas de contrato e de dependências. |
| `aux/remote.luau` | Reutiliza referências de serviços, valida o módulo de atalhos e invalida reenvios atrasados ao encerrar; inclui teardown para limpar o cache de atalhos. |
| `aux/utils.luau` | Limpeza suporta callbacks que removem outras conexões; salvamentos são serializados e preservam alterações feitas durante uma gravação; erros idênticos recentes são contados sem repetir snapshots e avisos. |
| `extras/antilag.luau` | Corrige inversão da remoção de luzes; rejeita opções numéricas inválidas; restaura patches de módulos substituídos; evita espera infinita por PlayerScripts. Mantém os budgets e os trabalhadores de culling. |
| `extras/autodark.luau` | Isola erros da habilidade e callbacks de uma execução encerrada, mantendo a chamada em cada Heartbeat. |
| `extras/autodash.luau` | Rejeita root já removido e se recupera de recuo do relógio mantendo o intervalo existente. |
| `extras/autofierce.luau` | Uma chamada que retorna após teardown não altera a execução seguinte; erros de disparo são reportados sem repetir stack traces a cada frame. A descoberta do hook manual continua por frame. |
| `extras/autojump.luau` | Evita forçar salto quando o humanoid está sentado ou em PlatformStand, incluindo durante Fly. |
| `extras/camera.luau` | Um require que falha não mata o watcher; ele retenta no intervalo existente. Sensibilidade inválida não contamina os vetores de rotação. |
| `extras/universal/dumper.luau` | Preserva propriedades false, isola estado e pastas por execução, mantém índices estáveis do manifesto, respeita cancelamento antes de gravar e verifica a gravação dos arquivos finais. Remove um loop de uma única iteração. |
| `extras/universal/fly.luau` | Teclas alternativas simultâneas deixam de se anular na soltura; diferencia toque e teclado em aparelhos híbridos; acompanha substituição de humanoid/root e limpa inicializações parciais. |
| `extras/universal/gravity.luau` | Evita força infinita em assemblies ancorados, não regrava força idêntica e só aceita valores finitos; limpa inicializações parciais. |
| `extras/universal/infinitejump.luau` | Evita atuação durante entrada de texto ou com potência/física inválida; limpa inicializações parciais. Mantém JumpRequest e o botão do jogo. |
| `extras/universal/invisicam.luau` | Preserva o ponto de restauração quando Roblox recusa a propriedade e tenta a limpeza mesmo após falha de ativação. |
| `extras/universal/noclip.luau` | Mantém índice incremental de partes, sem varrer todo o personagem a cada mudança de acessório; restaura colisão de partes removidas e limpa inicializações parciais. A aplicação continua por frame. |
| `extras/universal/servers.luau` | Confere cancelamento após HTTP e teleporte, protege callbacks, evita cursores repetidos, valida população, desempata ping por ocupação e libera a operação após timeout. |
| `extras/universal/speed.luau` | Restaura o humanoid substituído, rejeita valores não finitos, aplica o valor interno após aceitar a configuração e limpa inicializações parciais. Mantém os dois eventos por frame. |

## Loader e configuração

O loader passa a baixar com oito workers, com timeout total de 60 segundos, e verifica a assinatura antes de compilar. Uma falha anterior à substituição da sessão não apaga o registro da sessão em uso. Cada módulo inicializado com teardown recebe limpeza no fechamento normal; isso permite restaurar as propriedades de Fly, Speed, Noclip, Gravity e Invisicam, além de desconectar eventos. As notificações de fallback usam geração para impedir que um timer antigo remova a mensagem nova.

`front/app/config.luau` também foi revisado. O registro já valida patches antes de aplicá-los e não sofreu alteração de comportamento. Defaults, atalhos, schema, entitlements e o protocolo dos pacotes de rede permanecem compatíveis.

## Limite da revisão

Foi feita leitura do código e revisão manual dos diffs. Por solicitação do usuário, nenhum teste, benchmark, execução no Roblox ou validação automática de comportamento foi executado. Não há medição de ganho de FPS ou garantia de ausência de regressões.

## Padrões escolhidos pelo usuário

- Auto Dash durante clash e Auto Fierce: ligados.
- Spam: CPF 10, CPS 200, intervalo MS 10; modo inicial CPF.
- Método: Standard (valor interno `Deflect`).
- Sensibilidade: 1,5×.
- Distância do anti-lag: mínimo do slider, 350 studs.
- Invisicam e Anti-AFK: ligados.

Anti-AFK agora possui configuração própria, inicia automaticamente e acompanha alterações e reset. Os demais valores salvos continuam tendo prioridade sobre os defaults; os recursos Universal continuam sendo de sessão.
