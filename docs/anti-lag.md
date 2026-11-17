# Anti-lag: renderização e restauração

O recurso principal continua sendo ativado pelo usuário. A distância padrão é
128 studs (o mínimo do controle), e `AntiLagFloorCull` começa ligado. Preferências
já salvas continuam sendo respeitadas.

O culling esconde apenas a aparência local de peças estáticas do cenário.
Personagens, bolas e objetos marcados com `AntiLagKeepVisible` são preservados.
Não são alterados tamanho, CFrame, hitboxes, `CanCollide`, `CanTouch` ou `CanQuery`.
Uma peça grande que intersecta a área permitida é conservada inteira.

## Piso e campo de visão

A menor altura de chão pisada pelo personagem é registrada somente quando ele
está apoiado. Subir ou saltar não aumenta esse limite; pisar mais embaixo o reduz.
A margem é de 5 studs abaixo desse piso. O histórico reinicia no respawn e não
exige MatchStatus ou Lives de uma experiência específica.

Dentro da distância permitida, o campo de visão pode manter peças abaixo desse
limite. A avaliação usa os planos da câmera e os limites de cada peça, com margem
angular de 8 graus e espacial de 12 studs. Não usa raycasts para inferir oclusão:
considera o que pode estar visível, preservando geometria nas bordas da imagem.
Objetos muito fora desse campo são ocultados após um intervalo curto, com uma
zona próxima de segurança.

Os blocos espaciais distribuem o trabalho, mas não decidem a visibilidade de
várias peças como se fossem uma só. A câmera é atualizada durante a varredura.
Peças ocultas têm uma etapa prioritária de restauração, e a revelação aplica o
journal imediatamente. A indexação e a avaliação continuam limitadas por
quantidade de itens e orçamento de tempo; a etapa de restauração tem orçamento
adicional de 0,25 ms e até 48 candidatos por tick. Cenas extensas podem precisar
de vários frames para completar uma atualização.

## Opções desligadas por padrão

- `AntiLagClashCull`: durante clash nativo, restringe o cenário
  a **60 studs em cada direção do personagem**, em um cubo de 120 studs de lado,
  alinhado aos eixos do mundo. A câmera não é o centro. Nesse modo, peças
  inteiramente abaixo do último piso apoiado, além da margem de 5 studs, também
  ficam ocultas, mesmo se a câmera estiver apontando para baixo. Ao sair do clash,
  voltam as regras normais. Se o sinal nativo estiver indisponível, usa AutoSpam
  ativo como fallback. As exceções de personagens e indicadores permanecem.
- `AntiLagRemoveTextures`: oculta decals/textures, remove os IDs de textura de
  meshes e mapas de SurfaceAppearance quando essas propriedades são graváveis,
  e usa material liso no cenário, preservando os parâmetros físicos atuais
  antes da troca de material. Mantém Color, VertexColor e a geometria, e
  preserva visuais de personagens e indicadores de combate. Propriedades que o
  cliente não permitir alterar são registradas como indisponíveis no status.

O journal existente restaura os valores originais quando a opção é desligada ou
a sessão termina. Não são destruídas peças para produzir o efeito visual.
