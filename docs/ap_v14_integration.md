# Integração modular do AP LAB

A implementação atual corresponde à evolução do laboratório V14 no módulo AP
versão 16. A comparação, as decisões e as limitações estão em
[Integração das melhorias do AP LAB V14](ap_lab_v14_port.md).

## Responsabilidades

- BallSync/GameInfo: ingestão nativa e remota, ordenação, validade e projeção da bola.
- Targeting: seleção consolidada existente e tracker independente de episódios do AP.
- AutoParry: pressão adaptativa, alcance, rearme, cadência e coordenação com spam.
- Cooldown: tentativa aceita, janela pendente, confirmação, miss e elegibilidade de resgate.
- AutoFierce: verificação final de necessidade antes de ativar a habilidade.
- Remote: envio com guardas e distinção entre tentativa de entrada e chamada nativa aceita.
- CombatLoop: agendamento compartilhado; a UI apenas consome status e configuração.

O laboratório permanece uma referência; seus loops e bootstrap não são executados
junto com o hub. A suíte padrão verifica APIs, permissões e compatibilidade Luau,
sem congelar regras de combate. Confirmar CPS, FPS e resultados no servidor exige
reprodução no cliente real, com as mesmas configurações e recursos ativos.
