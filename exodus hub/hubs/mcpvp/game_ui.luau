-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local miniBalls = {
  { title = "Aim Lock", label = "LOCK", key = "MCAimLock", prefix = "MCAimLockBall" },
  { title = "Aim Assist", label = "ASSIST", key = "MCAimAssist", prefix = "MCAimAssistBall" },
  { title = "Auto Attack", label = "ATTACK", key = "MCAutoSword", prefix = "MCSwordBall" },
  { title = "Auto Crit", label = "CRIT", key = "MCAutoCrit", prefix = "MCCritBall" },
  { title = "Auto Potion", label = "POTION", key = "MCAutoPotion", prefix = "MCStrengthBall" },
  { title = "Auto Fugir", label = "FUGIR", key = "MCAutoEscape", prefix = "MCEscapeBall" },
  { title = "Auto Pearl", label = "PEARL", key = "MCAutoPearl", prefix = "MCPearlBall" },
  { title = "Auto Totem", label = "TOTEM", key = "MCAutoTotem", prefix = "MCTotemBall" },
  { title = "Reabastecer", label = "REFILL", key = "MCAutoRefill", prefix = "MCRefillBall" },
  { title = "Stop PvP", label = "STOP\nPVP", action = "resetState", prefix = "MCStopPvPBall" },
}
GameUI.definition = {
  miniBalls = miniBalls,
  pageOrder = { "mcpvp", "mcpvp-mini" },
  pages = {
    {
      id = "mcpvp",
      title = "MCPvP",
      columns = 2,
      sections = {
        {
          title = "Combate",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Attack",
              key = "MCAutoSword",
              description = "Continua o PvP iniciado por você com a arma selecionada. Usa machado da hotbar contra escudo e respeita a escolha manual; mace de Density fica fora do combo.",
            },
            {
              kind = "toggle",
              title = "Auto Crit",
              key = "MCAutoCrit",
              description = "Tenta o crítico na queda nativa, inclusive nos cliques manuais. Adapta o tempo ao teto baixo; sem espaço para saltar ou com risco de cristal/obsidian, ataca no chão.",
            },
          },
        },
        {
          title = "Mira",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Aim Lock",
              key = "MCAimLock",
              description = "Acompanha o alvo próximo do PvP atual, inclusive fora da tela, sem previsão de movimento.",
            },
            {
              kind = "toggle",
              title = "Aim Assist",
              key = "MCAimAssist",
              description = "Ajuda leve até 6 blocos. Mantém o mesmo alvo próximo que passar para trás e cede ao seu movimento de câmera.",
            },
          },
        },
        {
          title = "Assistência",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Auto Potion",
              key = "MCAutoPotion",
              description = "Reaplica no pé assim que o efeito acabar, aguardando a confirmação do jogo antes de restaurar a arma.",
            },
            { kind = "toggle", title = "Força", key = "MCAutoStrength", parentKey = "MCAutoPotion" },
            { kind = "toggle", title = "Speed", key = "MCAutoSpeed", parentKey = "MCAutoPotion" },
            {
              kind = "toggle",
              title = "Auto Fugir",
              key = "MCAutoEscape",
              description = "Sem totem e com até metade da vida, tenta pearl para longe, rota de saída e maçã da hotbar. Antecipa a maçã no PvP de espada pelo dano e intervalo observados; preserva a primeira ingestão.",
            },
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Calcula a trajetória até os pés e restaura sua arma após o consumo confirmado. Persegue teleportes; com 10 ou mais jogadores, desiste na terceira fuga longa.",
            },
            {
              kind = "toggle",
              title = "Auto Totem",
              key = "MCAutoTotem",
              description = "Seleciona o totem da hotbar antes de passá-lo à segunda mão. Para reservas, abre o inventário e repõe a hotbar apenas em espaço vazio.",
            },
          },
        },
        {
          title = "Inventário",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Reabastecer hotbar",
              key = "MCAutoRefill",
              description = "Repõe o item esgotado no mesmo slot, mantendo o inventário aberto até concluir a transferência, inclusive durante o PvP.",
            },
          },
        },
      },
    },
  },
}
local miniComponents = {}
GameUI.__config = { schema = {}, defaults = {} }
for _, ball in ipairs(miniBalls) do
  local visibleKey = ball.prefix .. "Visible"
  GameUI.__config.schema[visibleKey] = "boolean"
  GameUI.__config.schema[ball.prefix .. "X"] = "position"
  GameUI.__config.schema[ball.prefix .. "Y"] = "position"
  GameUI.__config.defaults[visibleKey] = false
  miniComponents[#miniComponents + 1] = {
    kind = "toggle",
    title = "Mini " .. ball.title .. " UI",
    key = visibleKey,
    description = ball.action == "resetState" and "Mostra o botão para encerrar o PvP atual sem desligar as funções."
      or "Mostra o botão de " .. ball.title .. ".",
    mobileOnly = true,
  }
end
GameUI.definition.pages[#GameUI.definition.pages + 1] = {
  id = "mcpvp-mini",
  title = "Mini UI",
  columns = 2,
  sections = { { title = "Mini UI", components = miniComponents } },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
