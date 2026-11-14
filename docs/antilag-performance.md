# Anti-lag: implementação e validação

A reformulação parte da revisão `3b61f394a0d964baed7010e041e2070d1eff50a2`. O anti-lag passa a gerenciar regiões e relevância visual dos personagens, com orçamento de trabalho e restauração das alterações.

## Regiões e visibilidade

A partição usa células de 32 studs e os limites reais de peças rotacionadas. Cada mapa/lobby tem seu próprio conjunto de células; pisos e paredes grandes ficam independentes para não inflar a região inteira. Novas instâncias entram por eventos, peças movidas são auditadas e reintegradas gradualmente, e mudanças de opções preservam o índice. `AntiLagKeepVisible=true` protege objetos que precisam permanecer visíveis.

O frustum usa planos da câmera e o suporte do bounding box, inclusive na vertical. A distância considera o ponto mais próximo dos limites. O padrão passa de 650 para 160 studs, com mínimo de 64, removendo a antiga proteção de 220 studs ao redor da câmera. As configurações salvas continuam sendo respeitadas. O lobby é ocultado visualmente durante a participação na partida, mantendo seus caminhos, interações e física.

Um raycast ao centro seleciona um bloqueador. A região só é ocultada quando seus oito cantos estão atrás do mesmo bloco opaco convexo. O teste analítico aceita paredes rotacionadas, pisos e tetos. Uma borda exposta, um objeto atravessando a parede ou um bloqueador contendo a câmera impedem a ocultação. Meshes, unions e cilindros não são tratados como caixas sólidas.

Terreno usa uma célula interna cercada por 27 voxels completamente sólidos e sem água. Leituras são compartilhadas e expiram em 100 ms; a cache tem até 64 entradas. Não há ocultação baseada apenas em altitude. Sem prova de oclusão ou orçamento disponível, o objeto fica visível. O motor Roblox mantém seus mecanismos internos de renderização.

O teto compartilhado entre cenário e personagens é de oito raycasts e uma leitura de voxels por heartbeat. Bloqueadores positivos são reutilizados com verificação geométrica. O trabalhador de propriedades usa orçamento de 0,8 ms e até 96 itens por lote; regiões usam 0,65 ms e até 160 passos. São limites de trabalho, não garantias de duração de uma chamada do motor.

## Personagens e processamento

A lista de jogadores é mantida por eventos. Até quatro personagens são avaliados por heartbeat, sem `GetPlayers` ou `GetDescendants` nos callbacks de relevância. Os limites de cada personagem são atualizados no máximo a cada 0,5 s, além da invalidação por mudanças de descendentes.

A atualização procedural de espadas de jogadores invisíveis é descartada. Os visíveis compartilham aproximadamente 120 atualizações/s, com faixa de 10–30 Hz. O personagem local continua na frequência nativa e os tracks de animação seguem tocando no motor. As conexões de marcadores registradas pelo adaptador são limpas quando o jogador sai.

O adaptador pode suspender callbacks puramente visuais de pescoços, cores de armas, gradientes e shimmer quando o cliente permite inspecionar conexões. O loop portátil de visibilidade de auras é pausado enquanto as auras estão desativadas. Os controles nativos de qualidade e os módulos de orçamento de VFX/áudio são aproveitados para evitar clones dispensáveis antes da alocação.

A sincronização da bola e da câmera, os eventos de combate e a física continuam ativos. As mudanças não alteram `CanCollide`, `CanTouch`, `CanQuery`, joints, velocidades, ownership ou estado físico dos personagens. Nenhuma peça física é movida para fora do Workspace.

## Gráficos e memória

O anti-lag mantém seu controle de ativação. Dentro dele, os padrões são qualidade 1, texturas desativadas, sombras/reflexos/detalhes reduzidos e pós-processamento/efeitos desligados. A névoa termina na distância configurada e começa 48 studs antes. A opção existente “Remover névoa” continua disponível.

Decals, textures, texturas de meshes e roupas são removidos visualmente. Componentes PBR puramente visuais são guardados temporariamente fora do Workspace, evitando setters restritos. Seu parent é restaurado e a remoção do mapa libera os componentes guardados. O journal registra propriedades modificadas ou observadas. Ao desligar/recarregar, restauração, índices, máscaras, watchers e patches são liberados. Nas peças ocultas, o watcher observa apenas a máscara visual, evitando callbacks das mudanças de CFrame dos personagens.

`antiLag.getStatus()` mostra regiões, personagens ocultos, raycasts, falhas, callbacks suspensos e classes de espadas adaptadas. `scheduler.Supported=false` significa ausência de inspeção de conexões; regiões, efeitos, texturas, relevância visual e controle portátil de auras continuam funcionando. Mesmo com suporte, confira `SwordClasses` e `SuspendedCallbacks` para confirmar as integrações daquele cliente.

## Símbolos originais

Os três PNGs originais (`settings`, `chevron`, `minimize`) permanecem byte a byte iguais. A decodificação Base64 agora é local, sem depender de `HttpService:Base64Decode`. Os registros de assets são reutilizados em memória durante a sessão e os PNGs temporários são removidos depois do registro. Referências genéricas e os três SVGs sem consumidores foram removidos; a licença permanece.

O verificador compara os PNGs, payloads e chamadas reais da interface. Testes verificam todos os bytes decodificados, o registro único por símbolo e falhas sem substituição por símbolos genéricos.

## Validação

Foram aprovados 67 testes `test_*.py`, incluindo integração no runtime Luau real, além das transições de fechamento/reload. Quatro arquivos Luau alterados compilam; formatter, PNGs, referências de ícones e `git diff --check` passaram. O workflow instala Luau 0.747 e verifica o SHA-256 do download.

Os testes cobrem frustum, distância, paredes rotacionadas, pisos, tetos, visão parcial, terreno e abertura de terreno, limites de raycasts, câmera girando durante uma transição parcial, peças movidas, remoção de objetos/mapas, 14 jogadores, respawn, limpeza de listeners, restauração de propriedades e interface desktop/mobile.

No cenário determinístico com um personagem local e 13 remotos invisíveis, 60 frames produzem 60 atualizações pesadas locais e zero remotas; 780 chamadas remotas são descartadas. Com 13 remotos visíveis, o trabalho procedural fica limitado a aproximadamente 130 atualizações/s. Esses números são contadores do harness, não FPS ou tempos de GPU de uma partida.

O utilitário `exodus hub/indeed/antilag_benchmark.luau` mede FPS médio, frametime p50/p95/p99, picos acima de 33/50 ms, memória, população e status do anti-lag. Ele apenas lê o cliente e desconecta seu callback ao terminar. Para comparar 1 e 14 jogadores, use a mesma rota, dispositivo, mapa e configuração, aguarde a indexação e faça três amostras de 30 s por condição. Compare p95/p99 e travamentos, além do FPS médio. A execução Cloud desta alteração não contém uma sessão Roblox e não fornece um resultado de FPS real.

Cinco harnesses antigos fora do workflow obrigatório falham igualmente na revisão de origem e nesta alteração: `parry_runtime_regression.py`, `cooldown_context_regression.py`, `fierce_grace_regression.py`, `spam_timer_regression.py` e `update_channel_regression.py`. A comparação foi feita em um worktree limpo de `3b61f39`; os erros envolvem mocks de Utils, valores de cooldown ausentes, expectativa de Fierce e CONFIG ausente. Eles não foram contabilizados como testes aprovados nem atribuídos ao anti-lag.
