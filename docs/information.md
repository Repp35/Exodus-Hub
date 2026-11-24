# Informações

A página usa um cartão por seção. Campos opcionais ausentes são omitidos; falhas de consulta aparecem no cartão e são notificadas uma vez.

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

A geolocalização consulta IPWhois e ipapi por HTTPS, sempre com o endereço explícito do servidor. Não usa o IP do jogador, país da conta, cookies ou pedidos de entrada em servidores. A consulta não bloqueia a inicialização.

`ServerRegion` é uma API do servidor e normalmente não está preenchida no cliente. Logs de rede também podem não estar acessíveis ao executor. Nesse caso, o hub informa a falha; não inventa cidade ou país. A localização por IP é aproximada e pode representar o relay de rede.

Fontes: [Roblox ServerRegion](https://devforum.roblox.com/t/read-your-games-server-region-with-new-api/4996710), [Player](https://create.roblox.com/docs/reference/engine/classes/Player), [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService), [GroupService](https://create.roblox.com/docs/reference/engine/classes/GroupService), [logs de conexão](https://github.com/bloxstraplabs/bloxstrap/blob/main/Bloxstrap/Integrations/ActivityWatcher.cs), [IPWhois](https://ipwhois.io/documentation), [ipapi](https://ipapi.co/api/).
