# Auto spam: regras da reconstrução

O núcleo anterior foi substituído por uma sessão com evidências de alvo. Cada pacote é observado separadamente; posição repetida e quantidade de frames não determinam se uma troca de alvo aconteceu. As regras abaixo são as aplicadas pelo código, incluindo bloqueios, pausas e envio.

## Validação comum

Para uma nova ativação: recurso AutoSpam e hub ligados; personagem local vivo e vinculado; bola válida da partida (o treino usa o AutoParry próprio); alvo numérico inteiro positivo e conhecido; velocidade numérica finita de 0 a 1000, com movimento maior que zero; posição e velocidade vetoriais finitas; amostra com até 500 ms, sem data futura; bola sem reset, teleporte, trava ou Frozen. NaN, infinito, texto e dados fora da faixa são rejeitados.

Quando existe posição real sincronizada, a divergência permitida da posição usada é `8 + velocidade × (idade da amostra + compensação de rede + 0,15)` studs. Essa verificação evita ativação por posição incoerente, sem impor limites de 0–1000 às coordenadas do mapa. Pacotes duplicados não criam trocas; pacotes antigos e sequências inválidas são ignorados. A sequência aceita a volta de 65535 para 0 e reinicia com uma bola nova.

Um miss atual impede ativação e desliga auto e manual. `miss_finished` é histórico de um cooldown já encerrado e permite uma nova sessão. A classificação do miss continua sendo fornecida pelo módulo Cooldown.

## Geometria

Todos os cálculos de ativação pedem `getDeflectGeometry(..., fator = 1)` com a janela completa calculada pelo jogo. A compensação adicional usada neste módulo é metade do ping informado, limitada a 250 ms.

`fullRadius` já inclui alcance, janela e compensação de rede. A verificação de chegada usa **fullRadius + velocidade de aproximação × janela efetiva completa**; dentro do alcance bruto, a direção não é obrigatória. Fora dele, a bola precisa estar se aproximando. Para o alvo adversário, o alcance bruto é o desse jogador.

## Ativação, em ordem de prioridade

| Gatilho | Todas as condições específicas |
| --- | --- |
| Dash adversário ou próprio | Dados da bola de até 150 ms; jogador adversário vivo a até 70 studs; bola mirando em você ou nele e dentro da geometria acima; sinal de dash ativo, modelo normal com tempo restante positivo, observação de até 200 ms, posição/velocidade finitas, velocidade entre 70 e 140 studs/s e alinhamento de aproximação ≥ 0,6. A distância projetada no ponto mais próximo precisa ser ≤ `min(35, raio próprio + raio adversário + velocidade da bola × janela efetiva 1×)`. Raycast sem obstrução. Não exige troca de alvo recente, CPS mínimo nem pontuação. Cada sinal de dash é usado uma vez por tipo e adversário. |
| Retorno | Sequência real **você → mesmo adversário → você**, sem um terceiro no meio. A passagem pelo adversário dura até **360 ms + compensação de rede**, independentemente da velocidade da bola. O adversário está vivo a até **35 studs** e a bola cabe na geometria completa. A evidência pode aguardar a chegada da bola por até outros 360 ms + compensação, desde que o alvo continue sendo você. Não exige uma segunda troca nem deslocamento da bola entre pacotes. |
| Bola próxima | Primeiro alvo válido da bola ou mudança de alvo para você; bola a até **8 studs**; adversário identificado e vivo a até **16 studs**. No primeiro alvo sem adversário anterior, usa o jogador vivo mais próximo dentro desse limite. A evidência expira em 360 ms. Uma bola isolada sem adversário próximo não inicia spam. |
| Haunter | Evento real com origem/destino CFrame; habilidades disponíveis; identificação de quem teleportou pela distância de até **5 studs** da origem/destino, ou posição local recente (até 750 ms) para uso próprio. Destino/adversário a até **11 studs**, alvo em você ou nesse adversário e bola dentro da geometria completa. Evidência válida por **150 ms**. Depois de ativado, não existe um timeout especial de confirmação de Haunter durante o clash. |

O dash tem prioridade sobre os demais. Um evento não utilizado deixa no diagnóstico o motivo específico: sem parceiro, fora da janela, sem interceptação, sem retorno completo, adversário distante, bola distante, evidência expirada etc. O painel opcional de gates mostra esses motivos por candidato.

## Desativação

| Motivo | Condição |
| --- | --- |
| Miss | Miss atual informado pelo Cooldown. Desliga **auto e manual**, mesmo perto, congelado ou durante reset. O registro `miss_finished` não é um miss ainda ativo. |
| Controle/lifecycle | Hub ou AutoSpam desligado; personagem local morto/removido/desvinculado; adversário morto/saiu; troca do objeto da bola; parada explícita, inclusive resgate Fierce. |
| Terceiro alvo | Uma amostra válida informa que o alvo é outro jogador, fora do par atual. |
| Distância | Adversário a mais de **35 studs**. Uma ativação por interceptação de dash tem **250 ms** para alcançar esse limite, pois pode começar até 70 studs antes da aproximação. |
| Cooldown prolongado | Bloqueio contínuo durante **180 ms**, contados a partir da ativação ou do início do bloqueio, o que for posterior, **e** adversário fora da proteção de **16–40 studs**, interpolada pela velocidade da bola entre os limites do jogo. O contador zera quando o bloqueio termina. |
| Retorno ausente | Bola permanece mirando no adversário por **300–400 ms**, conforme velocidade, sessão com pelo menos **250 ms**, **e** adversário fora da proteção de **10–25 studs**. Troca de volta para você zera a espera. |
| Fuga por dash | **Sem proteção de proximidade.** Bola mirando no adversário, dados de até 150 ms, bola saindo do seu alcance de fuga (janela 0,4×), dash ativo normal de 70–140 studs/s, componente horizontal ≥ 35%, afastamento ≥ 15 studs/s, ganho projetado ≥ 2 studs e separação projetada maior que a soma dos raios + velocidade da bola × janela 0,4×. Exige cooldown conhecido bloqueando por **50 ms** a partir da ativação/bloqueio. Vale para dash próprio ou adversário. |

Miss, terceiro alvo e fuga por dash não recebem proteção por adversário próximo. Os limites de cooldown comum e retorno recebem a proteção indicada.

## Pausa e retomada

Dados inválidos, antigos, alvo incerto, teleporte, reset, bola travada, Frozen e modo treino impedem novos cliques automáticos enquanto persistirem. Essas pausas não contam como cooldown/retorno expirando. A sessão ativa é preservada durante a pausa, mas o histórico de trocas é limpo no reset/alvo desconhecido. Morte, miss e desligamento continuam sendo monitorados. Uma bola substituída encerra a sessão anterior.

Depois de uma parada, é necessária evidência nova para ativar de novo. Não há trava permanente pelo nome do adversário, nem cooldown extra de reativação de 40 ms. Retornos seguintes do mesmo adversário funcionam.

## Envio dos cliques

Ao ativar o auto, CPS/CPF/MS enviam o primeiro clique imediatamente, validando a sessão de novo antes do envio; os seguintes seguem a taxa configurada. Auto mantém o intervalo mínimo e o atraso calculado pelo jogo também para o primeiro clique. Taxa zero/inválida impede o agendador. A trava de envio simultâneo, limite de trabalho por frame e método de clique selecionado continuam valendo. Ativação e aceitação de um clique pelo servidor são estados diferentes.

Manual continua independente da distância/retorno/dash: só o miss atual desliga o botão automaticamente. Personagem indisponível ou hub inativo impede o envio enquanto persistir.

## Gates removidos

Foram retirados: janela de retorno que encolhia até cerca de 40 ms em alta velocidade; exigência duplicada de `exchangeReady`; inferência de bola parada por posições iguais; bloqueios persistentes `stoppedPartner`/`timeoutBlocked`; pontuação e CPS mínimo da previsão de dash; uso do histórico `miss_finished` como bloqueio atual; ativação separada por reentrada no raio de morte (redundante com bola próxima e retorno); confirmação de Haunter aplicada repetidamente depois da ativação.

## Validação

Os testes carregam o módulo AutoSpam inteiro junto com o agendador Spam, simulando pacotes, Heartbeat e transporte. Cobrem retornos de 5–350 ms, várias distâncias/velocidades, pacotes entre frames, posições idênticas, ausência de gatilho, dash válido/inválido, sequência antiga/duplicada/wrap, reset, miss, cooldown, reativação e primeiro envio. Também usam o módulo Cooldown real para provar que `miss_finished` não prende uma nova sessão. Roblox e o servidor não são executados nesses testes.
