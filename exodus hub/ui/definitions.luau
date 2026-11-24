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
      title = "Informações",
      columns = 1,
      width = 360,
      utility = true,
      sections = {
        {
          title = "Sessão",
          components = {
            { kind = "readout", title = "FPS", info = "fps" },
            { kind = "readout", title = "Ping", info = "ping" },
            { kind = "readout", title = "Tempo no hub", info = "uptime" },
            { kind = "readout", title = "Executor", info = "executor" },
            { kind = "readout", title = "Auto Execute", info = "autoexecute" },
            { kind = "readout", title = "Roblox", info = "clientVersion" },
          },
        },
        {
          title = "Jogador",
          components = {
            { kind = "readout", title = "Usuário", info = "username" },
            { kind = "readout", title = "Nome de exibição", info = "displayName" },
            { kind = "readout", title = "User ID", info = "userId" },
          },
        },
        {
          title = "Jogo",
          components = {
            { kind = "readout", title = "Nome", info = "game" },
            { kind = "readout", title = "Criador", info = "creator" },
            { kind = "readout", title = "Grupo", info = "group" },
            { kind = "readout", title = "Place ID", info = "placeId" },
            { kind = "readout", title = "Universe ID", info = "universeId" },
            { kind = "readout", title = "Versão do place", info = "placeVersion" },
          },
        },
        {
          title = "Servidor",
          components = {
            { kind = "readout", title = "Jogadores", info = "population" },
            { kind = "readout", title = "Região", info = "region" },
            { kind = "readout", title = "País", info = "country" },
            { kind = "readout", title = "Cidade", info = "city" },
            { kind = "readout", title = "Job ID", info = "serverId" },
          },
        },
        {
          title = "Exodus",
          components = {
            { kind = "readout", title = "Versão do hub", info = "hubVersion" },
            { kind = "readout", title = "Versão da integração", info = "gameVersion" },
            { kind = "readout", title = "Desenvolvedores do hub", info = "hubDevelopers" },
            { kind = "readout", title = "Desenvolvedores da integração", info = "gameDevelopers" },
          },
        },
      },
    },
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
              description = "Limita a renderização em studs.",
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
              description = "Salva scripts acessíveis. Depende do executor.",
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
              description = "Libera o zoom da câmera.",
              key = "UniversalInfiniteZoom",
              feature = "InfiniteZoom",
            },
            {
              kind = "toggle",
              title = "Infinite Jump",
              description = "Pula no ar.",
              key = "UniversalInfiniteJump",
              shortcutKey = "InfiniteJumpKeybind",
              feature = "InfiniteJump",
            },
            { kind = "toggle", title = "Fly", description = "Permite voar.", key = "UniversalFly", shortcutKey = "FlyKeybind", feature = "Fly" },
            {
              kind = "scroll",
              title = "Fly Speed",
              description = "1x = 50 studs/s.",
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
              description = "Usa a velocidade definida abaixo.",
              key = "UniversalSpeedEnabled",
              desktopExpanded = true,
              shortcutKey = "SpeedKeybind",
              feature = "Speed",
            },
            {
              kind = "scroll",
              title = "Speed",
              description = "Define a velocidade.",
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
              description = "Usa a gravidade definida abaixo.",
              key = "UniversalGravityEnabled",
              shortcutKey = "GravityKeybind",
              feature = "Gravity",
            },
            {
              kind = "scroll",
              title = "Gravity",
              description = "Define a gravidade.",
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
              description = "Evita que o personagem cubra a câmera.",
              key = "UniversalInvisicam",
              shortcutKey = "InvisicamKeybind",
              feature = "Invisicam",
            },
            {
              kind = "toggle",
              title = "Noclip",
              description = "Atravessa objetos.",
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
            { kind = "toggle", title = "Auto Execute", key = "AutoExecuteOnJoin", description = "Executa ao entrar. Depende do executor." },
            {
              kind = "toggle",
              title = "Todos os jogos",
              key = "AutoExecuteAllGames",
              parentKey = "AutoExecuteOnJoin",
              description = "Off: só neste jogo. On: todos.",
            },
            { kind = "toggle", title = "Atualizar automaticamente", key = "AutoExecute", description = "Instala novas versões em um estado seguro." },
            { kind = "toggle", title = "System Notifications", key = "DesktopNotifications", desktopOnly = true },
            {
              kind = "toggle",
              title = "Shortcut Notifications",
              description = "Avisa ao usar atalhos.",
              key = "DesktopShortcutNotifications",
              parentKey = "DesktopNotifications",
              desktopOnly = true,
            },
            { kind = "toggle", title = "System Notifications", key = "MobileNotifications", mobileOnly = true },
            {
              kind = "toggle",
              title = "Modo PC",
              description = "Usa a interface de PC.",
              key = "ForcePCUI",
              desktopExpanded = true,
            },
            { kind = "button", title = "Resetar personagem", description = "Reinicia o personagem.", action = "resetCharacter" },
            { kind = "button", title = "Rejoin", description = "Volta ao mesmo servidor.", action = "rejoin" },
            { kind = "button", title = "Server Hop", description = "Busca outro servidor com ping até 100 ms.", action = "serverHop" },
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
