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
              description = "Ataca com a arma escolhida: espada, machado, lança e ferramentas. Mace somente com Breach (Ruptura).",
            },
            {
              kind = "toggle",
              title = "Auto Crit",
              key = "MCAutoCrit",
              description = "Reconhece ataques manuais ou automáticos e prepara o pulo para o próximo golpe.",
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
              description = "Acompanha o alvo próximo com resposta rápida e giro contínuo, sem a espera do antigo modo legit.",
            },
            {
              kind = "toggle",
              title = "Aim Assist",
              key = "MCAimAssist",
              description = "Assistência leve até 16 studs, apenas perto da mira e durante seu movimento. Não centraliza automaticamente.",
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
              description = "Uma tentativa por vida ou consumo de totem, com intervalo do dump (90 s). Após totem, aguarda 4 s sem combate.",
            },
            {
              kind = "toggle",
              title = "Auto Pearl",
              key = "MCAutoPearl",
              description = "Ao sair do alcance de dano, lança no chão aos pés do alvo visível, com previsão curta e colisão no destino.",
            },
            {
              kind = "toggle",
              title = "Auto Totem",
              key = "MCAutoTotem",
              description = "Busca na reserva, coloca na hotbar e equipa o offhand imediatamente. Mantém um totem de reserva na hotbar; fechamento respeita 400 ms.",
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
