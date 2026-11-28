-- [[ Prison Life time controls ]]
--!optimize 2
local GameUI = {}
local clock
GameUI.definition = {
  pageOrder = { "prison-time" },
  pages = {
    {
      id = "prison-time",
      title = "Horário",
      columns = 1,
      sections = {
        {
          title = "Horário do dia",
          components = {
            {
              kind = "toggle",
              title = "Controlar horário local",
              key = "PrisonTimeEnabled",
              shortcutKey = "PrisonTimeKeybind",
              description = "Muda o céu e o relógio do jogo só para você. Desligue para seguir o horário do servidor.",
            },
            {
              kind = "textInput",
              title = "Horário (24h)",
              key = "PrisonTimeHour",
              parentKey = "PrisonTimeEnabled",
              description = "Aceita 8, 08:30 ou 8h. 24, 24h e 24:00 equivalem a 00:00.",
              placeholder = "12:00",
              parse = function(value) return clock.parseTime(value) end,
              format = function(value) return clock.formatTime(value) end,
            },
            {
              kind = "toggle",
              title = "Horário fixo",
              key = "PrisonTimeFixed",
              parentKey = "PrisonTimeEnabled",
              description = "Desligado: o tempo avança a partir do horário escolhido.",
            },
            {
              kind = "slider",
              title = "Velocidade do ciclo",
              key = "PrisonTimeSpeed",
              parentKey = "PrisonTimeEnabled",
              min = 0.1,
              max = 20,
              increment = 0.1,
              valueName = "x",
              description = "Com horário fixo desligado, 1x segue o ritmo normal do jogo.",
            },
            { kind = "button", title = "Reiniciar no horário escolhido", action = "prisonTimeRestart", parentKey = "PrisonTimeEnabled" },
            { kind = "button", title = "Sempre de dia", action = "prisonTimeDay", parentKey = "PrisonTimeEnabled" },
            { kind = "button", title = "Sempre de noite", action = "prisonTimeNight", parentKey = "PrisonTimeEnabled" },
          },
        },
      },
    },
  },
}
GameUI.__config = { schema = { PrisonTimeKeybind = "keyCode" }, defaults = { PrisonTimeKeybind = Enum.KeyCode.Unknown } }
function GameUI.setup(deps)
  clock = deps.Clock
  return true
end
GameUI.__contract = {
  provides = { "setup" },
  data = { "definition" },
  requires = { Clock = "localclock" },
  requiresMethods = { Clock = { "parseTime", "formatTime" } },
}
return GameUI
