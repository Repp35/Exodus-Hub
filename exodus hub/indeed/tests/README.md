# Cobertura mantida

Os testes verificam contratos, interfaces e regras atuais. Uma falha não autoriza
restaurar uma regra de gameplay que foi alterada deliberadamente. Antes de mudar
produção para satisfazer um teste, confira a intenção da alteração e o histórico.

Foram retirados 14 casos obsoletos e quatro harnesses antigos incompatíveis:

- Miss deixando auto/manual desligados ou bloqueando reativação: regras removidas
  pelos commits `2b11a7b2` e `26e857e5`.
- Paradas e rearmamento que presumiam ausência de proteção de proximidade:
  incompatíveis com a continuidade atual de clash (incluindo `add74a75`).
- Timeout automático de retorno e saída por dash: não são mais usados pelo
  caminho atual de desativação.
- Cancelamento de um deflect encerrando rajada manual: comportamento alterado
  em `b5324f3a` para manter o manual durante Fierce.
- Harnesses `parry_runtime_regression`, `cooldown_context_regression`,
  `fierce_grace_regression` e `spam_timer_regression`: extraíam trechos internos,
  usavam dependências antigas ou não traduziam o Luau atual. A cobertura útil de
  dispatch, cooldown, Fierce e scheduler já está nos testes `test_*.py`.

As verificações de Fierce que exigiam desligar o spam foram retiradas
(`425a3be3`), preservando as verificações de resgate e lock único do AutoParry.
No teste de saída por terceiro alvo, o nome antigo `third_target` foi substituído
pelo motivo atual `target_redirected_far`. Foi retirada a exigência de desligamento
imediato por troca de bola dentro da proteção de proximidade. A cobertura de
nova bola e sequência continua no teste que entrega pacotes pelo caminho real
de atualização.

Continuam os testes de reload, cache, timeout, contratos, sincronização, geometria,
UI, formatter, scheduler, permissões e funcionalidades atuais. Os harnesses
`update_channel_regression.py` e `ui_transition_regression.py` continuam no CI.

```sh
python3 -m unittest discover -s 'exodus hub/indeed/tests' -p 'test_*.py'
python3 'exodus hub/indeed/tests/update_channel_regression.py'
python3 'exodus hub/indeed/tests/ui_transition_regression.py'
```
