# Geometria de defesa

`modules/logic/aux/deflectgeometry.luau` possui as constantes e os cálculos de
raio, janela, resiliência, ping, treino e projeção. Recebe dados nativos do
GameInfo; não instala loops nem conexões. Os consumidores pedem a API pelo alias
`DeflectGeometry` em seus contratos.

O AP decide quando defender e qual fator usar. A geometria aplica o fator e
recompõe o raio; o AP não mantém uma segunda fórmula de janela ou raio.

## API principal

```lua
local g = Geometry.resolve(speed, {
  window = 0.4,       -- opcional: substitui a janela consultada no jogo
  factor = 0.3,
  latency = ping,     -- opcional: usa o ping observado quando ausente
})
local full = g.fullRadius
local windowOnly = Geometry.getWindow(speed, { factor = 0.3 })
local rawWindow = Geometry.getWindow(speed, { factor = 0.3, raw = true })
local rawRadius = Geometry.getRadius(speed, { component = "raw" })
local windowRadius = Geometry.getRadius(speed, { component = "window", factor = 0.3 })
```

`resolve` retorna a geometria completa. `getRadius` retorna um número; os
componentes são `full` (padrão), `base`, `raw`, `resilience`, `window` e `ping`.
`getWindow` retorna a janela escolhida multiplicada pelo fator, sem ping; `raw`
retorna a janela antes do fator. A geometria também expõe `deflectWindow` e
`effectiveWindow`, distinguindo a janela escolhida da antecipação aplicada.

No perfil comum, o raio é `alcance bruto + velocidade × (janela + latência) ×
fator`. O fator nunca multiplica o alcance fixo. `factor = 0` conserva o alcance
bruto e zera as parcelas dinâmicas. Fatores acima de 1 são aceitos nesse perfil.
`latencyFactor` permite escolher outro fator para a parcela de ping; quando
omitido, mantém o mesmo fator da janela, preservando o comportamento anterior.

`windowScale` e `windowOffset` ajustam a janela apenas naquela consulta. `ping =
false` desconsidera latência; `resilience = false` usa o alcance base. Nenhuma
consulta altera as regras compartilhadas.

## Perfis e composição

- `profile = "autoParry"`: preserva as regras existentes de janela do jogo,
  antecipação por frame e latência; fator entre 0 e 1. O AP pode escolher um fator
  adaptativo e chamar `withAutoParryFactor` para recalcular no próprio serviço.
- `profile = "training"`: preserva a janela por velocidade, limite do fator e
  padding do treino. O fator atua na janela, sem remover o padding fixo.
- Perfil comum: permite janela explícita, escala, deslocamento, fator e seleção
  de parcelas. As opções de substituição de janela pertencem a esse perfil.

`compose({range, extraRange, speed, window, factor, latency, latencyFactor,
padding})` permite combinar parcelas e devolve raio completo, parcela da janela,
parcela do ping e janela efetiva. Na composição explícita, `latencyFactor` assume
1; é independente do fator da janela. `projectRadius` oferece o cálculo numérico
sem criar tabelas, para caminhos frequentes como o AutoSpam.

As APIs específicas existentes (`getDeflectWindow`, `getDeflectGeometry`,
`getAutoParryGeometry`, `getTrainingGeometry`, `getPlayerRawRadius`, etc.) também
pertencem ao serviço. GameInfo fornece apenas a origem dos dados, e a UI recebe
observações já calculadas. As regras intencionais de miss, Fierce e continuidade
do spam não foram modificadas.
