-- [[ gameui ]]
--!optimize 2
local GameUI = {}
local miniBalls = {
  { title = "Aim Lock", label = "LOCK", key = "MCAimLock", prefix = "MCAimLockBall" },
  { title = "Aim Assist", label = "ASSIST", key = "MCAimAssist", prefix = "MCAimAssistBall" },
  { title = "Auto Attack", label = "ATTACK", key = "MCAutoSword", prefix = "MCSwordBall" },
  { title = "Auto Crit", label = "CRIT", key = "MCAutoCrit", prefix = "MCCritBall" },
  { title = "Auto Força", label = "FORÇA", key = "MCAutoStrength", prefix = "MCStrengthBall" },
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
              description = "Inicie atacando um jogador. Sincroniza os golpes com o cooldown real da arma.",
            },
            {
              kind = "toggle",
              title = "Auto Crit",
              key = "MCAutoCrit",
              description = "Pula ao seu comando de ataque, mesmo sem Auto Attack ou alvo travado.",
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
              description = "Mira na posição atual do alvo, sem previsão de movimento.",
            },
            {
              kind = "toggle",
              title = "Aim Assist",
              key = "MCAimAssist",
              description = "Correção leve até 16 studs; Aim Lock tem prioridade quando ambos estão ativos.",
            },
            { kind = "slider", title = "Força da mira", key = "MCAimStrength", min = 0, max = 100, increment = 1, valueName = "%" },
          },
        },
        {
          title = "Assistência",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Auto Força",
              key = "MCAutoStrength",
              description = "Usa força em segurança, após uma pausa no combate, uma vez por vida ou totem.",
            },
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Segue o jogador que você atacar, mesmo sem Auto Attack ou mira, verificando trajetória e chegada.",
            },
            {
              kind = "toggle",
              title = "Auto Totem",
              key = "MCAutoTotem",
              description = "Prioriza a hotbar, abre o inventário para acessar reservas e preenche espaços vazios.",
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
              description = "Abre o inventário e repõe cada item esgotado no mesmo slot.",
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
