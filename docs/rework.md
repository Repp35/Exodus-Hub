# Rework do runtime e da lógica de clash

Base auditada: `19556ec0f9e2c3f0ab31a2219b48a8bb3ba5a321`.

## Problema e alteração

Com AutoSpam e AutoParry ativos, o código anterior tinha quatro entradas de
avaliação do AutoSpam por frame e três entradas do AutoParry que também
chamavam AutoSpam. Atributos e pacotes acrescentavam notificações. Uma
avaliação ativa podia recalcular risco de destinatário três vezes, percorrendo
jogadores em cada passagem. Isso existia independentemente do CPS.

O CombatLoop agenda a passagem contínua em PostSimulation (Heartbeat somente
como fallback), atualizando cooldown, AutoSpam, AutoParry e AutoFierce nessa
ordem. Nos pacotes, AutoDash é notificado entre AP e AutoFierce, preservando a
ordem anterior. PreSimulation só executa uma passagem adicional quando o prazo estimado
do AutoParry vence. A avaliação do AutoParry não chama mais a avaliação do
AutoSpam. Sistemas continuam responsáveis pelas próprias decisões.

Pacotes e alvos explícitos são processados sincronamente, na ordem recebida.
Notificações derivadas de atributos de clash/cor são agrupadas com `task.defer`;
isso elimina reavaliações do lote, não executa trabalho em paralelo. A aceitação
e ordenação de sequências permanecem no BallSync. Não há fila de pacotes
crescente nem descarte de transições por um simples cache do último alvo.

Durante uma passagem síncrona, os consumidores compartilham o snapshot. Novos
pacotes, alterações de alvo e troca de bola continuam invalidando esse cache.
O cache temporal anterior permanece para acessos fora da passagem. Os snapshots
de bola são dados internos de leitura; snapshots de configuração/diagnóstico
continuam sendo cópias separadas.

AutoSpam usa scratch limitado à avaliação para risco e geometrias por fator,
sem cache global de decisões temporais. A lista de jogadores é reconstruída
somente em entrada/saída; referências de personagem, Humanoid e root são
atualizadas por eventos e verificadas antes do uso. Guardas de envio permanecem
ativas; protocolo, cadência configurada e reenvios Direct foram preservados.

## Responsabilidades e limpeza

Utils mantém sua fachada pública; estado/cópia, persistência com recuperação e
coleta de diagnóstico têm implementações próprias. Atualizar o namespace não
coleta mais o status de todos os sistemas. `Utils.getDiagnostics()` continua
fazendo uma coleta explícita atualizada.

O escopo de recursos da UI foi extraído para Lifetime. UI e os recursos speed,
fly, noclip e infinitejump compartilham essa implementação. GameInfo possui
teardown explícito para soltar módulos nativos, snapshots e referências.
O fechamento também libera `Exodus.Context`.

AntiLag foi separado em propriedades, adaptação nativa e seleção espacial.
Suas políticas, opções visuais, limites de trabalho e restauração foram
preservados. A UI mantém a apresentação anterior; foram reduzidas escritas
repetidas no botão DynamicParry. Speed não aplica mais a mesma manutenção em
RenderStepped além da fase de simulação.

Removidas apenas as funções locais inacessíveis `formatSample` e `formatPoint`
de ClashStats, variáveis sem leitores e os conectores/agendamentos substituídos.
As dependências não usadas de AutoParry e AutoDash para AutoSpam foram removidas. Nenhuma funcionalidade
ou módulo de recurso foi excluído. Testes antigos foram arquivados, não apagados.

## Compatibilidade

A entrada `exodus hub/loader.luau`, IDs de módulos, exports existentes,
configurações, UI e transporte continuam disponíveis. Os caminhos internos
mudaram; consumidores que baixem arquivos internos diretamente precisam usar
o manifesto atual. A migração atualizou manifesto, famílias, ferramentas e
referências documentadas. Use o loader completo, sem misturar revisões.

## Validação e medição

O baseline tinha 450 testes, com 378 falhas e 3 erros, incluindo fixtures e
caminhos obsoletos. A nova suíte padrão valida APIs e compatibilidade, conforme
solicitado; sua aprovação não representa aprovação de todas as regras antigas.

Não houve execução do Roblox nesta sessão. Não há medição de ganho de FPS,
CPU, GPU, física ou rede, nem confirmação de que toda queda a 1 FPS foi resolvida.

Para medir:

1. Reproduza o mesmo clash, dispositivo, gráficos e recursos ativos. Inclua o
   caso AutoSpam + AutoParry a 1 CPS; registre também a revisão anterior.
2. Execute `indeed/diagnostics/profile_runtime.luau` durante o clash. Ele captura
   30 segundos, até 4096 amostras de frame em anel, memória e contadores opcionais
   de CPU. Salva `exodus-runtime-profile.json` quando `writefile` está disponível.
3. Compare p50/p95/p99 de frame, memória, avaliações, varreduras e simulações
   nativas. As durações por módulo incluem chamadas internas; não some medições
   aninhadas como se fossem custos independentes. Contadores do profiler são
   reiniciados no começo e no fim da captura.
4. Repita com AntiLag desligado/ligado e com a interface recolhida/aberta.
   Use MicroProfiler/estatísticas disponíveis no cliente para distinguir scripts,
   renderização, física e alocações. O JSON sozinho não identifica gargalo de GPU.
5. Verifique manualmente treino, alvo terceiro, cooldown, teleporte, morte,
   respawn, reload, fechamento e recursos auxiliares. Compare sucessivos reloads
   para detectar crescimento de conexões/memória.

Também é possível habilitar contadores sem o script de captura:

```lua
_G.Exodus.Context.profiler.setEnabled(true)
-- reproduzir o clash
print(_G.Exodus.Context.profiler.getStatus())
_G.Exodus.Context.profiler.setEnabled(false)
```

A instrumentação é desabilitada por padrão e mantém no máximo 64 categorias.
A validação em cliente real continua sendo necessária antes de integrar o rework.

## Resultado das verificações locais

- 29 verificações básicas aprovadas, sem testes ignorados, com Luau 0.748.
- 69 módulos e suas permissões verificados pelo auditor estático.
- 74 scripts Luau compilados pela suíte de sintaxe.
- Assets PNG e formatação aprovados; nenhum erro de whitespace no diff.

Esses resultados verificam carregamento e compatibilidade estrutural. O smoke
não compõe a UI em um cliente Roblox nem confirma resultado de ações no servidor.

## Testar a branch antes da integração

O loader usa `main` por padrão. Para testar este PR sem misturar seus módulos
com os da main, selecione a branch antes de executar o loader:

```lua
_G.ExodusSourceBranch = "refactor/combat-runtime-20261122"
loadstring(game:HttpGet("https://raw.githubusercontent.com/Repp35/Exodus-v2/refactor/combat-runtime-20261122/exodus%20hub/loader.luau"))()
```

O loader resolve o commit dessa branch e fixa todos os downloads nessa revisão,
inclusive em reload. Ao voltar ao loader principal, limpe
`_G.ExodusSourceBranch = nil`. O ambiente continua exigindo as APIs de executor
que o loader original utilizava.
