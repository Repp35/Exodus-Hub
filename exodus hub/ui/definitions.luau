-- [[ uiconfig ]]
--!optimize 2
-- @modules uiconfig

-- module
local UIConfig = {}

-- configuration
local CONFIG = {
  PAGES = {
    {
      id = "information",
      title = "Information",
      columns = 1,
      width = 360,
      utility = true,
      sections = {
        { title = "Session", components = { { kind = "readout", info = "session" } } },
        { title = "Game", components = { { kind = "readout", info = "game" } } },
        { title = "Server", components = { { kind = "readout", info = "server" } } },
        { title = "Versions", components = { { kind = "readout", info = "versions" } } },
        { title = "Developers", components = { { kind = "readout", info = "developers" } } },
      },
    },
    {
      id = "antilag",
      title = "Performance",
      columns = 1,
      width = 360,
      sections = {
        {
          title = "Rendering",
          components = {
            { kind = "toggle", title = "Anti Lag", key = "AntiLagEnabled", description = "Reduz o custo de renderização." },
            {
              kind = "slider",
              title = "Render Distance",
              description = "Limita a distância de renderização.",
              key = "AntiLagRenderDistance",
              parentKey = "AntiLagEnabled",
              min = 300,
              max = 1200,
              increment = 1,
              valueName = "studs",
            },
            {
              kind = "toggle",
              title = "Remove Effects",
              key = "AntiLagRemoveEffects",
              parentKey = "AntiLagEnabled",
              description = "Oculta efeitos visuais pesados.",
            },
          },
        },
      },
    },
    {
      id = "indeed",
      title = "Universal",
      columns = 2,
      sections = {
        {
          title = "Movement",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Speed",
              key = "UniversalSpeedEnabled",
              shortcutKey = "SpeedKeybind",
              feature = "Speed",
              description = "Aplica a velocidade escolhida.",
            },
            {
              kind = "scroll",
              title = "Walk Speed",
              key = "UniversalSpeed",
              feature = "Speed",
              parentKey = "UniversalSpeedEnabled",
              min = 0,
              max = 200,
              increment = 1,
              valueName = "WalkSpeed",
              description = "Define a velocidade ao andar.",
            },
            {
              kind = "toggle",
              title = "Fly",
              key = "UniversalFly",
              shortcutKey = "FlyKeybind",
              feature = "Fly",
              description = "Permite voar com os controles de movimento.",
            },
            {
              kind = "scroll",
              title = "Fly Speed",
              key = "UniversalFlySpeed",
              feature = "Fly",
              parentKey = "UniversalFly",
              min = 0.1,
              max = 10,
              increment = 0.1,
              valueName = "x",
              description = "Ajusta a velocidade de voo.",
            },
            {
              kind = "toggle",
              title = "Noclip",
              key = "UniversalNoclip",
              shortcutKey = "NoclipKeybind",
              feature = "Noclip",
              description = "Permite atravessar objetos.",
            },
          },
        },
        {
          title = "Jump & Gravity",
          column = 1,
          components = {
            { kind = "toggle", title = "Auto Jump", key = "AutoJump", shortcutKey = "JumpKeybind", description = "Repete os saltos automaticamente." },
            {
              kind = "toggle",
              title = "Infinite Jump",
              key = "UniversalInfiniteJump",
              shortcutKey = "InfiniteJumpKeybind",
              feature = "InfiniteJump",
              description = "Permite saltar novamente no ar.",
            },
            {
              kind = "toggle",
              title = "Gravity",
              key = "UniversalGravityEnabled",
              shortcutKey = "GravityKeybind",
              feature = "Gravity",
              description = "Aplica a gravidade escolhida.",
            },
            {
              kind = "scroll",
              title = "Gravity Value",
              key = "UniversalGravity",
              feature = "Gravity",
              parentKey = "UniversalGravityEnabled",
              min = 0,
              max = 400,
              increment = 1,
              valueName = "studs/s²",
              description = "Define a força da gravidade.",
            },
          },
        },
        {
          title = "Camera",
          column = 2,
          components = {
            { kind = "number", title = "Sensitivity", key = "CameraSensitivity", min = 0, description = "Ajusta a sensibilidade da câmera." },
            { kind = "toggle", title = "Infinite Zoom", key = "UniversalInfiniteZoom", feature = "InfiniteZoom", description = "Libera a distância do zoom." },
            {
              kind = "toggle",
              title = "Invisicam",
              key = "UniversalInvisicam",
              shortcutKey = "InvisicamKeybind",
              feature = "Invisicam",
              description = "Oculta obstáculos entre a câmera e o personagem.",
            },
          },
        },
        {
          title = "Session",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Anti AFK",
              key = "AntiAFK",
              action = "antiAFK",
              shortcutKey = "AntiAFKKeybind",
              description = "Evita a desconexão por inatividade.",
            },
          },
        },
        {
          title = "Developer Tools",
          column = 2,
          components = {
            { kind = "click", title = "Script Dumper", action = "dumper", description = "Salva scripts acessíveis pelo executor." },
          },
        },
      },
    },
    {
      id = "config",
      title = "Settings",
      columns = 1,
      width = 360,
      utility = true,
      sections = {
        {
          title = "Startup & Updates",
          components = {
            { kind = "toggle", title = "Auto Update", key = "AutoExecute", description = "Atualiza o hub quando o jogo permite." },
            { kind = "toggle", title = "Auto Execute", key = "AutoExecuteOnJoin", description = "Executa ao entrar, se o executor permitir." },
            {
              kind = "toggle",
              title = "All Games",
              key = "AutoExecuteAllGames",
              parentKey = "AutoExecuteOnJoin",
              description = "Executa também nos outros jogos.",
            },
          },
        },
        {
          title = "Notifications",
          components = {
            {
              kind = "toggle",
              title = "System Notifications",
              key = "DesktopNotifications",
              desktopOnly = true,
              description = "Mostra notificações do hub.",
            },
            {
              kind = "toggle",
              title = "Shortcut Notifications",
              key = "DesktopShortcutNotifications",
              parentKey = "DesktopNotifications",
              desktopOnly = true,
              description = "Avisa quando um atalho é usado.",
            },
            { kind = "toggle", title = "System Notifications", key = "MobileNotifications", mobileOnly = true, description = "Mostra notificações do hub." },
          },
        },
        {
          title = "Interface",
          components = {
            { kind = "toggle", title = "Desktop Mode", key = "ForcePCUI", description = "Usa a interface de computador." },
          },
        },
        {
          title = "Character & Server",
          components = {
            { kind = "button", title = "Reset Character", action = "resetCharacter", description = "Reinicia seu personagem." },
            { kind = "button", title = "Rejoin", action = "rejoin", description = "Reconecta ao mesmo servidor." },
            { kind = "button", title = "Server Hop", action = "serverHop", description = "Busca outro servidor com ping até 100 ms." },
          },
        },
        {
          title = "Preferences",
          components = {
            { kind = "button", title = "Reset Settings", action = "resetSettings", description = "Restaura as configurações padrão." },
          },
        },
      },
    },
  },
  SETTINGS = {
    schema = {
      MobileNotifications = "boolean",
      DesktopNotifications = "boolean",
      DesktopShortcutNotifications = "boolean",
      ForcePCUI = "boolean",
      CameraSensitivity = "rate",
      AntiAFK = "boolean",
      AutoJump = "boolean",
      JumpKeybind = "keyCode",
      BtnX = "position",
      BtnY = "position",
      PanelX = "position",
      PanelY = "position",
    },
    defaults = {
      MobileNotifications = true,
      DesktopNotifications = true,
      DesktopShortcutNotifications = true,
      ForcePCUI = false,
      CameraSensitivity = 1.5,
      AntiAFK = true,
      AutoJump = false,
      JumpKeybind = Enum.KeyCode.J,
    },
  },
}

-- shortcuts
for _, page in ipairs(CONFIG.PAGES) do
  for _, section in ipairs(page.sections) do
    for _, definition in ipairs(section.components or {}) do
      local key = definition.shortcutKey
      if key then
        CONFIG.SETTINGS.schema[key] = "keyCode"
        if CONFIG.SETTINGS.defaults[key] == nil then
          CONFIG.SETTINGS.defaults[key] = Enum.KeyCode.Unknown
        end
      end
    end
  end
end
function UIConfig.getPages(definition)
  definition = definition or {}
  local pages, byId = {}, {}
  for _, source in ipairs(CONFIG.PAGES) do
    local page = table.clone(source)
    page.sections = {}
    for _, originalSection in ipairs(source.sections) do
      local section = table.clone(originalSection)
      section.components = table.clone(originalSection.components or {})
      page.sections[#page.sections + 1] = section
    end
    byId[page.id] = page
    pages[#pages + 1] = page
  end
  for _, page in ipairs(definition.pages or {}) do
    assert(not byId[page.id], "Duplicate game page: " .. tostring(page.id))
    byId[page.id] = page
    pages[#pages + 1] = page
  end
  for _, addition in ipairs(definition.additions or {}) do
    local page = assert(byId[addition.page], "Unknown UI page")
    local section = assert(page.sections[addition.section or 1], "Unknown UI section")
    for _, component in ipairs(addition.components or {}) do
      section.components[#section.components + 1] = component
    end
  end
  local ordered, seen = {}, {}
  for _, id in ipairs(definition.pageOrder or {}) do
    if byId[id] and not seen[id] then
      ordered[#ordered + 1] = byId[id]
      seen[id] = true
    end
  end
  for _, page in ipairs(pages) do
    if not seen[page.id] then
      ordered[#ordered + 1] = page
    end
  end
  return ordered
end

-- public-api
UIConfig.pages = CONFIG.PAGES
UIConfig.__config = CONFIG.SETTINGS

-- contract
UIConfig.__contract = { provides = { "getPages" }, data = { "pages" }, requires = {} }

return UIConfig
