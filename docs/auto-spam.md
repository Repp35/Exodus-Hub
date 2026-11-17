# Auto spam: regras da reconstrução

O núcleo anterior foi substituído por uma sessão com evidências de alvo. Cada pacote é observado separadamente; posição repetida e quantidade de frames não determinam se uma troca de alvo aconteceu. As regras abaixo são as aplicadas pelo código, incluindo bloqueios, pausas e envio.

## Validação comum

Para uma nova ativação: recurso AutoSpam e hub ligados; personagem local vivo e vinculado; bola válida da partida (o treino usa o AutoParry próprio); alvo numérico inteiro positivo e conhecido; velocidade numérica finita de 0 a 1000, com movimento maior que zero; posição e velocidade vetoriais finitas; amostra com até 500 ms, sem data futura; bola sem reset, teleporte, trava ou Frozen. NaN, infinito, texto e dados fora da faixa são rejeitados.

Quando existe posição real sincronizada, a divergência permitida da posição usada é `8 + velocidade × (idade da amostra + compensação de rede + 0,15)` studs. Essa verificação evita ativação por posição incoerente, sem impor limites de 0–1000 às coordenadas do mapa. Pacotes duplicados não criam trocas; pacotes antigos e sequências inválidas são ignorados. A sequência aceita a volta de 65535 para 0 e reinicia com uma bola nova.

Miss e cooldown comum não desligam AutoSpam ou Manual Spam. A classificação fornecida pelo Cooldown continua disponível para os outros consumidores, mas não funciona como trava de envio do spam.

## Geometria

Todos os cálculos de ativação pedem `getDeflectGeometry(..., fator = 1)` com a janela completa calculada pelo jogo. A compensação adicional usada neste módulo é metade do ping informado, limitada a 250 ms.

`fullRadius` já inclui alcance, janela e compensação de rede. A verificação de chegada usa **fullRadius + velocidade de aproximação × janela efetiva completa**; dentro do alcance bruto, a direção não é obrigatória. Fora dele, a bola precisa estar se aproximando. Para o alvo adversário, o alcance bruto é o desse jogador.

## Ativação, em ordem de prioridade

| Gatilho | Todas as condições específicas |
| --- | --- |
| Dash adversário ou próprio | Dados da bola de até 150 ms; jogador adversário vivo a até 70 studs; bola mirando em você ou nele e dentro da geometria acima; sinal de dash ativo, modelo normal com tempo restante positivo, observação de até 200 ms, posição/velocidade finitas, velocidade entre 70 e 140 studs/s e alinhamento de aproximação ≥ 0,6. A distância projetada no ponto mais próximo precisa ser ≤ `min(35, raio próprio + raio adversário + velocidade da bola × janela efetiva 1×)`. Raycast sem obstrução. Não exige troca de alvo recente, CPS mínimo nem pontuação. O mesmo sinal ainda válido pode voltar a ativar após o intervalo curto; não é marcado como consumido. |
| Retorno | Sequência real **você → mesmo adversário → você**, sem um terceiro no meio. A passagem pelo adversário dura até **360 ms + compensação de rede**, independentemente da velocidade da bola. O adversário está vivo a até **35 studs** e a bola cabe na geometria completa. A evidência pode aguardar a chegada da bola por até outros 360 ms + compensação, desde que o alvo continue sendo você. Não exige uma segunda troca nem deslocamento da bola entre pacotes. |
| Bola próxima | A até **2 studs**, bola mirando em você e adversário vivo a até **16 studs** ativam imediatamente. Entre 2 e **5 studs**, a chegada de um remetente observado prepara uma confirmação: a bola precisa ir de você para esse mesmo remetente e voltar para você. Na volta, ativa no próprio pacote, usando a janela completa; não precisa entrar novamente nos 5 studs. Terceiro alvo, reset ou remetente que deixou de estar perto limpam essa preparação. Sem remetente conhecido, a faixa de 2–5 studs não é armada. |
| Haunter | Evento real com origem/destino CFrame; habilidades disponíveis; identificação de quem teleportou pela distância de até **5 studs** da origem/destino, ou posição local recente (até 750 ms) para uso próprio. Destino/adversário a até **11 studs**, alvo em você ou nesse adversário e bola dentro da geometria completa. Evidência válida por **150 ms**. Depois de ativado, não existe um timeout especial de confirmação de Haunter durante o clash. |

O dash tem prioridade sobre os demais. Um evento não utilizado deixa no diagnóstico o motivo específico: sem parceiro, fora da janela, sem interceptação, sem retorno completo, adversário distante, bola distante, evidência expirada etc. O painel opcional de gates mostra esses motivos por candidato.

## Desativação

| Motivo | Condição |
| --- | --- |
| Controle/lifecycle | Hub ou AutoSpam desligado; personagem local morto/removido/desvinculado; adversário morto ou indisponível. |
| Redirecionamento distante | Uma amostra válida e recente informa outro alvo fora do par, a mais de 35 studs. Registra `target_redirected_far`, mesmo com o parceiro anterior próximo. |
| Distância | Adversário a mais de **35 studs por 250 ms contínuos**. |

A proteção de proximidade de **14 studs** preserva a sessão contra paradas que
não sejam desligamento, morte/indisponibilidade, cooldown explícito ou
redirecionamento distante. A troca da bola tenta encerrar a sessão anterior e
reinicia o histórico de alvos; esse encerramento também passa pela proteção.
O código atual não usa ausência de retorno ou fuga por dash como motivos
automáticos de desativação. O resgate Fierce não solicita desligamento do spam.

## Pausa e retomada

Dados inválidos, antigos, alvo incerto, teleporte, reset, bola travada, Frozen e
modo treino impedem novos cliques automáticos enquanto persistirem. Uma sessão
ativa pode continuar durante a pausa. O histórico é limpo no reset/alvo
desconhecido; a evidência de continuidade de envios também é limpa nas pausas de
movimento. Lacunas breves de sincronização podem usar a evidência recente de
trocas reais quando o parceiro permanece próximo.

Após um desligamento efetivo existe um intervalo de **20 ms** antes de reavaliar
os gatilhos ainda válidos. Chamadas de parada em uma sessão já inativa não
prolongam esse intervalo. Uma chamada protegida por proximidade não provoca
um desligamento nem inicia uma nova espera.

## Envio dos cliques

Ao ativar o auto, CPS/CPF/MS enviam o primeiro clique imediatamente, validando a sessão de novo antes do envio; os seguintes seguem a taxa configurada. Auto mantém o intervalo mínimo e o atraso calculado pelo jogo também para o primeiro clique. Taxa zero/inválida impede o agendador. A trava de envio simultâneo, limite de trabalho por frame e método de clique selecionado continuam valendo. Ativação e aceitação de um clique pelo servidor são estados diferentes.

Manual continua independente da distância, retorno, dash, miss e cooldown. Personagem indisponível ou hub inativo impede o envio enquanto persistir. Um deflect cancelado isoladamente, inclusive durante Fierce, não interrompe a rajada manual.

## Gates removidos

Foram retirados: janela de retorno que encolhia até cerca de 40 ms em alta velocidade; exigência duplicada de `exchangeReady`; inferência de bola parada por posições iguais; bloqueios persistentes `stoppedPartner`/`timeoutBlocked`; pontuação e CPS mínimo da previsão de dash; uso do histórico `miss_finished` como bloqueio atual; ativação separada por reentrada no raio de morte (redundante com bola próxima e retorno); confirmação de Haunter aplicada repetidamente depois da ativação.

## Validação

Os testes mantidos cobrem ativação, sequência antiga/duplicada/wrap, dados
inválidos, reset, continuidade em cooldown e lacunas de sincronização, envio,
contratos e lifecycle. Os casos que exigiam desligamento por miss, Fierce ou
regras antigas de saída foram removidos. O histórico dessas decisões está em
`exodus hub/indeed/tests/README.md`. Os serviços de jogo são simulados nesses testes.
