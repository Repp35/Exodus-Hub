-- [[ uiconfig ]]

-- module
local UIConfig = {}

-- configuration
local CONFIG = {
  PAGES = {
    {
      id = "antilag",
      title = "Anti Lag",
      columns = 1,
      width = 360,
      sections = {
        {
          title = "Anti Lag",
          components = {
            { kind = "toggle", title = "Ativar Anti Lag", key = "AntiLagEnabled" },
            {
              kind = "slider",
              title = "Distância de renderização",
              description = "Define o raio em studs ao redor do personagem.",
              key = "AntiLagRenderDistance",
              parentKey = "AntiLagEnabled",
              min = 300,
              max = 1200,
              increment = 1,
              valueName = "studs",
            },
            { kind = "toggle", title = "Remover efeitos", key = "AntiLagRemoveEffects", parentKey = "AntiLagEnabled" },
          },
        },
      },
    },
    {
      id = "indeed",
      title = "Universals",
      columns = 1,
      width = 360,
      sections = {
        {
          title = "Developer Tools",
          components = {
            {
              kind = "click",
              title = "Dumper",
              description = "Salva scripts e informações acessíveis do jogo.",
              action = "dumper",
            },
          },
        },
        {
          title = "Universal Controls",
          components = {
            { kind = "toggle", title = "Auto Jump", key = "AutoJump", shortcutKey = "JumpKeybind" },
            { kind = "number", title = "Camera Sensitivity", key = "CameraSensitivity", min = 0 },
            { kind = "toggle", title = "Anti AFK", key = "AntiAFK", action = "antiAFK", shortcutKey = "AntiAFKKeybind" },
            {
              kind = "toggle",
              title = "Infinite Zoom",
              description = "Remove o limite de distância da câmera.",
              key = "UniversalInfiniteZoom",
              feature = "InfiniteZoom",
            },
            {
              kind = "toggle",
              title = "Infinite Jump",
              description = "Permite pular no ar.",
              key = "UniversalInfiniteJump",
              shortcutKey = "InfiniteJumpKeybind",
              feature = "InfiniteJump",
            },
            { kind = "toggle", title = "Fly", description = "Permite voar livremente.", key = "UniversalFly", shortcutKey = "FlyKeybind", feature = "Fly" },
            {
              kind = "scroll",
              title = "Fly Speed",
              description = "Multiplicador de voo; 1x equivale a 50 studs/s.",
              key = "UniversalFlySpeed",
              feature = "Fly",
              parentKey = "UniversalFly",
              min = 0.1,
              max = 10,
              increment = 0.1,
              valueName = "x",
            },
            {
              kind = "toggle",
              title = "Speed",
              description = "Ativa a velocidade personalizada.",
              key = "UniversalSpeedEnabled",
              desktopExpanded = true,
              shortcutKey = "SpeedKeybind",
              feature = "Speed",
            },
            {
              kind = "scroll",
              title = "Speed",
              description = "Ajusta a velocidade do personagem.",
              key = "UniversalSpeed",
              feature = "Speed",
              parentKey = "UniversalSpeedEnabled",
              min = 0,
              max = 200,
              increment = 1,
              valueName = "WalkSpeed",
            },
            {
              kind = "toggle",
              title = "Gravity",
              description = "Ativa a gravidade personalizada.",
              key = "UniversalGravityEnabled",
              shortcutKey = "GravityKeybind",
              feature = "Gravity",
            },
            {
              kind = "scroll",
              title = "Gravity",
              description = "Ajusta a gravidade do personagem.",
              key = "UniversalGravity",
              feature = "Gravity",
              parentKey = "UniversalGravityEnabled",
              min = 0,
              max = 400,
              increment = 1,
              valueName = "studs/s²",
            },
            {
              kind = "toggle",
              title = "Invisicam",
              description = "Remove o personagem da visão da câmera.",
              key = "UniversalInvisicam",
              shortcutKey = "InvisicamKeybind",
              feature = "Invisicam",
            },
            {
              kind = "toggle",
              title = "Noclip",
              description = "Permite atravessar objetos.",
              key = "UniversalNoclip",
              shortcutKey = "NoclipKeybind",
              feature = "Noclip",
            },
          },
        },
      },
    },
    {
      id = "config",
      title = "Config",
      columns = 1,
      width = 300,
      utility = true,
      sections = {
        {
          components = {
            { kind = "toggle", title = "System Notifications", key = "DesktopNotifications", desktopOnly = true },
            {
              kind = "toggle",
              title = "Shortcut Notifications",
              description = "Avisa ao alternar funções por atalho. Manual Spam e Up Dash ficam silenciosos.",
              key = "DesktopShortcutNotifications",
              parentKey = "DesktopNotifications",
              desktopOnly = true,
            },
            { kind = "toggle", title = "System Notifications", key = "MobileNotifications", mobileOnly = true },
            {
              kind = "toggle",
              title = "Modo PC",
              description = "Pré-visualiza a interface de PC. Desative para voltar ao modo automático.",
              key = "ForcePCUI",
              desktopExpanded = true,
            },
            { kind = "button", title = "Resetar personagem", description = "Reinicia seu personagem na partida.", action = "resetCharacter" },
            { kind = "button", title = "Rejoin", description = "Reconecta ao servidor atual.", action = "rejoin" },
            { kind = "button", title = "Server Hop", description = "Busca vagas com ping informado de até 100 ms; prioriza o menor.", action = "serverHop" },
            { kind = "button", title = "Reset settings", action = "resetSettings" },
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
        if CONFIG.SETTINGS.defaults[key] == nil then CONFIG.SETTINGS.defaults[key] = Enum.KeyCode.Unknown end
      end
    end
  end
end
function UIConfig.getPages(definition)
  definition = definition or {}; local pages, byId = {}, {}
  for _, source in ipairs(CONFIG.PAGES) do
    local page = table.clone(source); page.sections = {}
    for _, originalSection in ipairs(source.sections) do
      local section = table.clone(originalSection); section.components = table.clone(originalSection.components or {})
      page.sections[#page.sections + 1] = section
    end
    byId[page.id] = page; pages[#pages + 1] = page
  end
  for _, page in ipairs(definition.pages or {}) do
    assert(not byId[page.id], "Duplicate game page: " .. tostring(page.id)); byId[page.id] = page
    pages[#pages + 1] = page
  end
  for _, addition in ipairs(definition.additions or {}) do
    local page = assert(byId[addition.page], "Unknown UI page"); local section = assert(page.sections[addition.section or 1], "Unknown UI section")
    for _, component in ipairs(addition.components or {}) do
      section.components[#section.components + 1] = component
    end
  end
  local ordered, seen = {}, {}
  for _, id in ipairs(definition.pageOrder or {}) do
    if byId[id] and not seen[id] then ordered[#ordered + 1] = byId[id]; seen[id] = true end
  end
  for _, page in ipairs(pages) do
    if not seen[page.id] then ordered[#ordered + 1] = page end
  end
  return ordered
end

-- public-api
UIConfig.pages = CONFIG.PAGES
UIConfig.__config = CONFIG.SETTINGS

-- contract
UIConfig.__contract = { provides = { "getPages" }, data = { "pages" }, requires = {} }

return UIConfig
