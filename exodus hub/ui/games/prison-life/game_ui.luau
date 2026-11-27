-- [[ Prison Life time controls ]]
--!optimize 2
local GameUI = {}
local function formatTime(value)
  local minutes = math.floor(tonumber(value) or 0) % 1440
  return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end
local function parseTime(text)
  local hour, minute = tostring(text):match("^%s*(%d%d?):(%d%d)%s*$")
  hour, minute = tonumber(hour), tonumber(minute)
  if hour == 24 and minute == 0 then
    return 0
  end
  if not hour or not minute or hour > 23 or minute > 59 then
    return nil
  end
  return hour * 60 + minute
end
GameUI.definition = {
  pageOrder = { "prison-time", "indeed", "antilag", "config", "information" },
  pages = {
    {
      id = "prison-time",
      title = "Time",
      columns = 1,
      sections = {
        {
          title = "Local Clock",
          components = {
            {
              kind = "toggle",
              title = "Local Time",
              key = "UniversalPrisonTimeEnabled",
              description = "Só altera o seu cliente. Desative para voltar ao horário do jogo.",
            },
            {
              kind = "textInput",
              title = "Time (24h)",
              key = "UniversalPrisonTimeMinutes",
              parentKey = "UniversalPrisonTimeEnabled",
              placeholder = "18:30",
              format = formatTime,
              parse = parseTime,
            },
            {
              kind = "dropdown",
              title = "Clock Mode",
              key = "UniversalPrisonTimeMode",
              parentKey = "UniversalPrisonTimeEnabled",
              options = { { value = "Fixed", label = "Fixed" }, { value = "Normal", label = "Normal" }, { value = "Fast", label = "Accelerated" } },
            },
            {
              kind = "slider",
              title = "Time Speed",
              key = "UniversalPrisonTimeSpeed",
              parentKey = "UniversalPrisonTimeEnabled",
              description = "Multiplicador usado no modo acelerado.",
              min = 1,
              max = 120,
              increment = 1,
              valueName = "x",
            },
          },
        },
      },
    },
  },
}
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
