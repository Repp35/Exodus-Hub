# Ferramentas

Execute a partir da raiz do repositório:

```sh
python3 'exodus hub/indeed/formatter.py' --check 'exodus hub'
python3 'exodus hub/indeed/formatter.py' --in-place 'exodus hub'
python3 'exodus hub/indeed/tools/build_ui_icons.py' --check
python3 -m unittest discover -s 'exodus hub/indeed/tests' -p 'test_*.py'
python3 'exodus hub/indeed/tests/update_channel_regression.py'
python3 'exodus hub/indeed/tests/ui_transition_regression.py'
```

`indeed/formatting` separa transformações de texto, backend StyLua e CLI.
`indeed/tools` contém geração de assets; `diagnostics`, scripts de inspeção;
`benchmarks`, medições offline. Configuração e binário StyLua ficam em
`formatting/resources`. Sem caminhos explícitos, o formatter processa o hub.

Os testes Python usam Lua 5.4 com serviços simulados e tradução limitada de Luau;
`liblua5.4.so.0` deve estar instalada. `LUAU_BIN` permite usar um runtime Luau nos
harnesses que suportam essa opção. As verificações de UI que usam ctypes continuam
em Lua 5.4. Resultados desses ambientes não medem FPS nem resultados do servidor.

O workflow de publicação gera entitlements, manifesto e arquivos versionados.
A pasta `indeed` é excluída da distribuição do hub.
