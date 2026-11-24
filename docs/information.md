# Informações

A página usa um cartão por seção. Campos opcionais ausentes são omitidos; falhas de consulta aparecem no cartão, sem notificações de erro. Os rótulos usam negrito e os avisos usam itálico; dados externos são escapados antes de RichText.

| Seção | Dados |
| --- | --- |
| Sessão | Usuário, executor, FPS e ping |
| Jogo | Nome, criador e grupo, quando houver |
| Servidor | País, cidade e jogadores/capacidade |
| Versões | Hub, script do jogo e Roblox |
| Desenvolvedores | Lista de nomes, sem duplicatas |

FPS conta quadros renderizados. Ping usa Stats, com `Player:GetNetworkPing()` como alternativa. Nome e criador vêm de MarketplaceService, com a API pública de jogos como alternativa. Grupos usam GroupService; usuários também podem ser resolvidos pelo CreatorId. Versões do hub e de cada jogo são independentes.

## Localização

Ordem das fontes: `DataModel.ServerRegion`, metadados replicados `ServerCountry`/`ServerCity`/`ServerRegion` e endereço da conexão atual, quando exposto pelo executor nos eventos ou logs. Logs só são aceitos depois de identificar o JobId atual. Endereços privados são descartados.

A geolocalização consulta IPWhois e ipapi por HTTPS, sempre com o endereço explícito do servidor. Não usa país da conta, cookies ou pedidos de entrada em servidores. Quando as fontes do servidor não respondem após oito segundos, pode consultar o país da conexão do jogador por IPWhois/ipapi; esse endereço não é salvo nem exibido. A consulta não bloqueia a inicialização.

`ServerRegion` é uma API do servidor e normalmente não está preenchida no cliente. Logs de rede também podem não estar acessíveis ao executor. Nesse caso, a cidade fica “Não confirmada”. Uma janela de 20 amostras de ping, coletadas a cada segundo, permite mostrar o país da conexão como **estimativa** quando todas são positivas, no máximo 60 ms e variam até 15 ms. Essa heurística não confirma o país e nunca determina cidade; ping alto ou indisponível remove a estimativa. Dados reais têm prioridade. Consultas ao servidor são repetidas a cada 30 segundos enquanto a sessão estiver ativa. A localização por IP é aproximada e pode representar o relay de rede.

Fontes: [Roblox ServerRegion](https://devforum.roblox.com/t/read-your-games-server-region-with-new-api/4996710), [Player](https://create.roblox.com/docs/reference/engine/classes/Player), [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService), [GroupService](https://create.roblox.com/docs/reference/engine/classes/GroupService), [logs de conexão](https://github.com/bloxstraplabs/bloxstrap/blob/main/Bloxstrap/Integrations/ActivityWatcher.cs), [IPWhois](https://ipwhois.io/documentation), [ipapi](https://ipapi.co/api/).
