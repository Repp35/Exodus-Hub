# Execução automática

- **Auto Execute:** executa ao entrar novamente no jogo.
- **Todos os jogos:** ligado permite qualquer jogo; desligado limita ao jogo selecionado.
- **Atualizar automaticamente:** instala novas revisões quando as regras do jogo permitem.

As preferências de execução ficam em `Exodus Hub/auto_execute.json`, separadas das
configurações de cada integração. Desligar a execução invalida também os scripts
já enfileirados. A atualização manual continua disponível.

O hub detecta `queue_on_teleport`, `queueonteleport` e as variantes de Synapse e
Fluxus. Para novas sessões, usa a pasta retornada por `getautoexecpath` ou
`getautoexecfolder`. Quando a API de plugins do Delta X está presente, instala
`DeltaPlugins/ExodusHub.luau`, conforme a [documentação da API](https://github.com/AZYsGithub/DeltaXPlugin).

Se o executor não expõe instalação automática, o inicializador fica salvo em
`Exodus Hub/auto_execute.luau`. Adicione esse arquivo ao Auto Execute do executor
uma vez. A página de informações mostra o modo disponível. O recurso de execução
automática do próprio executor precisa estar habilitado.
