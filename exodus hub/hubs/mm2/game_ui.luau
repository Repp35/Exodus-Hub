-- [[ MM2 presentation ]]
--!optimize 2
local GameUI = {}
GameUI.definition = {
  pageOrder = { "mm2-farm", "mm2-combat", "mm2-map", "mm2-visuals", "mm2-alerts" },
  pages = {
    {
      id = "mm2-farm",
      title = "Auto Farm",
      columns = 1,
      sections = {
        {
          title = "Coleta de moedas",
          components = {
            { kind = "toggle", title = "Auto Farm", key = "AutoFarm" },
            { kind = "toggle", title = "Evitar moedas perto do Murderer", key = "AvoidMurdererCoins", parentKey = "AutoFarm" },
            { kind = "toggle", title = "Reset com a bolsa cheia (inocente)", key = "ResetWhenBagFull", parentKey = "AutoFarm" },
            {
              kind = "slider",
              title = "Velocidade do Auto Farm",
              key = "FarmSpeed",
              parentKey = "AutoFarm",
              min = 5,
              max = 100,
              increment = 1,
              valueName = "studs/s",
            },
          },
        },
      },
    },
    {
      id = "mm2-combat",
      title = "Combat",
      columns = 2,
      sections = {
        {
          title = "Shoot Murder",
          components = {
            {
              kind = "toggle",
              title = "Shoot Murder manual",
              key = "ManualShootMurder",
              description = "Use a Mini UI no celular ou a tecla configurada no PC.",
            },
            { kind = "toggle", title = "Botão de Shoot invisível", key = "ManualShootMurderInvisible", mobileOnly = true, parentKey = "ManualShootMurder" },
            {
              kind = "slider",
              title = "Precisão do Shoot manual",
              key = "ManualShootMurderAccuracy",
              parentKey = "ManualShootMurder",
              min = 0,
              max = 100,
              increment = 5,
              valueName = "%",
            },
            { kind = "toggle", title = "Botão de Shoot quadrado", key = "ShootMiniSquare", mobileOnly = true, parentKey = "ManualShootMurder" },
            {
              kind = "slider",
              title = "Tamanho do botão de Shoot",
              key = "ShootMiniScale",
              mobileOnly = true,
              parentKey = "ManualShootMurder",
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
            },
            {
              kind = "keybind",
              title = "Tecla para Shoot Murder",
              key = "ShootKeybind",
              shortcutKey = "ShootKeybind",
              action = "mm2Shoot",
              parentKey = "ManualShootMurder",
              desktopOnly = true,
              silentShortcut = true,
            },
            { kind = "toggle", title = "Auto Shoot Murder", key = "AutoShootMurder" },
            {
              kind = "slider",
              title = "Precisão do Auto Shoot",
              key = "AutoShootMurderAccuracy",
              parentKey = "AutoShootMurder",
              min = 0,
              max = 100,
              increment = 5,
              valueName = "%",
            },
            { kind = "toggle", title = "Legit", key = "LegitSheriff", description = "Aguarda o assassino sacar a faca." },
          },
        },
        {
          title = "Combate com faca",
          column = 2,
          components = {
            { kind = "toggle", title = "Auto Attack (faca)", key = "AutoKnifeAttack" },
            {
              kind = "dropdown",
              title = "Alvo do Auto Attack",
              key = "AutoKnifeAttackTargets",
              parentKey = "AutoKnifeAttack",
              options = {
                { value = "All", label = "Todos" },
                { value = "Sheriff/Hero", label = "Sheriff / Herói" },
                { value = "Innocent", label = "Inocentes" },
              },
            },
            {
              kind = "toggle",
              title = "Manual Lançar Faca",
              key = "ManualKnifeThrow",
              description = "Use a Mini UI no celular ou a tecla configurada no PC. Prioriza o xerife visível.",
            },
            { kind = "toggle", title = "Botão de faca invisível", key = "ManualKnifeInvisible", mobileOnly = true, parentKey = "ManualKnifeThrow" },
            { kind = "toggle", title = "Botão de faca quadrado", key = "KnifeMiniSquare", mobileOnly = true, parentKey = "ManualKnifeThrow" },
            {
              kind = "slider",
              title = "Tamanho do botão de faca",
              key = "KnifeMiniScale",
              mobileOnly = true,
              parentKey = "ManualKnifeThrow",
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
            },
            {
              kind = "keybind",
              title = "Tecla para lançar faca",
              key = "KnifeThrowKeybind",
              shortcutKey = "KnifeThrowKeybind",
              action = "mm2Throw",
              parentKey = "ManualKnifeThrow",
              desktopOnly = true,
              silentShortcut = true,
            },
            { kind = "toggle", title = "Auto Lançar Faca", key = "AutoKnifeThrow" },
            {
              kind = "dropdown",
              title = "Alvo do lançamento",
              key = "AutoKnifeThrowTargets",
              options = {
                "Auto",
                { value = "Sheriff/Hero", label = "Sheriff / Herói" },
                { value = "Innocent", label = "Inocentes" },
                { value = "Nearest", label = "Mais próximo" },
              },
              description = "Seleção compartilhada entre o lançamento manual e automático.",
            },
            {
              kind = "slider",
              title = "Área de mira da faca",
              key = "KnifeCone",
              min = 5,
              max = 85,
              increment = 1,
              valueName = "°",
              description = "Aumente para mirar em alvos mais afastados do centro da tela. Sheriff ou Herói visível tem prioridade mesmo fora dessa área.",
            },
          },
        },
        {
          title = "Coleta de arma",
          components = {
            { kind = "toggle", title = "Auto Pick Gun", key = "AutoGunPickup" },
            {
              kind = "toggle",
              title = "Evitar o Murderer ao pegar a arma",
              key = "GunPickupSafety",
              parentKey = "AutoGunPickup",
              description = "Evita coletar a arma sob ameaça do assassino.",
            },
          },
        },
      },
    },
    {
      id = "mm2-map",
      title = "Map",
      columns = 2,
      sections = {
        {
          title = "Teleporte e jogadores",
          components = {
            { kind = "button", title = "Teleport para o mapa", action = "mm2Map" },
            { kind = "button", title = "Teleport para o lobby", action = "mm2Lobby" },
            { kind = "button", title = "Teleport para o Murderer", action = "mm2Murderer" },
            { kind = "button", title = "Teleport para a arma", action = "mm2Gun" },
            { kind = "toggle", title = "Auto Teleport para a arma", key = "AutoTeleportToGun" },
            { kind = "button", title = "Teleport para quem está com a arma", action = "mm2GunHolder" },
            { kind = "dropdown", title = "Player", key = "MapTargetPlayer", choiceSource = "mm2Players", options = { "None" } },
            { kind = "button", title = "Teleport para o player", action = "mm2Player" },
            { kind = "button", title = "Andar até o player", action = "mm2Walk" },
          },
        },
        {
          title = "Votação de mapas",
          column = 2,
          components = { { kind = "dropdown", title = "Mapa preferido para votar", key = "FavoriteMap", choiceSource = "mm2Maps", options = { "None" } } },
        },
      },
    },
    {
      id = "mm2-visuals",
      title = "Visuals",
      columns = 1,
      sections = {
        {
          title = "ESP de jogadores e objetos",
          components = {
            { kind = "checkbox", title = "ESP", key = "ESPEnabled" },
            { kind = "checkbox", title = "Mostrar função ou tipo de objeto", key = "ESPShowIdentity", parentKey = "ESPEnabled" },
            { kind = "checkbox", title = "Username", key = "ESPShowUsername", parentKey = "ESPEnabled" },
            { kind = "checkbox", title = "Mostrar meu personagem", key = "ESPShowSelf", parentKey = "ESPEnabled" },
            { kind = "checkbox", title = "Mostrar distância", key = "ESPShowDistance", parentKey = "ESPEnabled" },
            { kind = "checkbox", title = "Murderer", key = "ESPMurderer", parentKey = "ESPEnabled", tint = { 255, 65, 65 } },
            { kind = "checkbox", title = "Sheriff + Herói", key = "ESPSheriff", parentKey = "ESPEnabled", tint = { 70, 155, 255 } },
            { kind = "checkbox", title = "Inocentes", key = "ESPInnocent", parentKey = "ESPEnabled", tint = { 70, 220, 120 } },
            { kind = "checkbox", title = "Doces / Moedas", key = "ESPCandyCoin", parentKey = "ESPEnabled", tint = { 255, 185, 70 } },
            { kind = "checkbox", title = "Arma no chão", key = "ESPGun", parentKey = "ESPEnabled", tint = { 70, 225, 255 } },
          },
        },
      },
    },
    {
      id = "mm2-alerts",
      title = "Avisos",
      columns = 1,
      sections = {
        {
          title = "Avisos da partida",
          components = {
            { kind = "toggle", title = "Avisar minha função e quem é o Murderer", key = "AlertRoleAndMurderer" },
            { kind = "toggle", title = "Avisar quando a arma cair", key = "AlertGunDropped" },
          },
        },
      },
    },
  },
  miniBalls = {
    {
      id = "MM2Shoot",
      title = "Shoot\nMurder",
      action = "onMM2Shoot",
      visibleKey = "ManualShootMurder",
      invisibleKey = "ManualShootMurderInvisible",
      squareKey = "ShootMiniSquare",
      scaleKey = "ShootMiniScale",
      xKey = "ShootMiniX",
      yKey = "ShootMiniY",
      shape = "square",
      color = "accent",
      ability = "mm2Shoot",
      mobileOnly = true,
    },
    {
      id = "MM2Knife",
      title = "Lançar\nFaca",
      action = "onMM2Throw",
      visibleKey = "ManualKnifeThrow",
      invisibleKey = "ManualKnifeInvisible",
      squareKey = "KnifeMiniSquare",
      scaleKey = "KnifeMiniScale",
      xKey = "KnifeMiniX",
      yKey = "KnifeMiniY",
      shape = "square",
      color = "red",
      ability = "mm2Throw",
      mobileOnly = true,
    },
  },

}
GameUI.__config = {
  schema = {
    AutoFarm = "boolean",
    AvoidMurdererCoins = "boolean",
    ResetWhenBagFull = "boolean",
    FarmSpeed = "rate",
    ManualShootMurder = "boolean",
    ManualShootMurderInvisible = "boolean",
    ManualShootMurderAccuracy = "rate",
    AutoShootMurder = "boolean",
    AutoShootMurderAccuracy = "rate",
    LegitSheriff = "boolean",
    AutoKnifeAttack = "boolean",
    AutoKnifeAttackTargets = "text",
    ManualKnifeThrow = "boolean",
    ManualKnifeInvisible = "boolean",
    AutoKnifeThrow = "boolean",
    AutoKnifeThrowTargets = "text",
    KnifeCone = "rate",
    AutoGunPickup = "boolean",
    GunPickupSafety = "boolean",
    AutoTeleportToGun = "boolean",
    MapTargetPlayer = "text",
    FavoriteMap = "text",
    ESPEnabled = "boolean",
    ESPShowIdentity = "boolean",
    ESPShowUsername = "boolean",
    ESPShowSelf = "boolean",
    ESPShowDistance = "boolean",
    ESPMurderer = "boolean",
    ESPSheriff = "boolean",
    ESPInnocent = "boolean",
    ESPCandyCoin = "boolean",
    ESPGun = "boolean",
    AlertRoleAndMurderer = "boolean",
    AlertGunDropped = "boolean",
    ShootMiniSquare = "boolean",
    ShootMiniScale = "miniScale",
    ShootMiniX = "position",
    ShootMiniY = "position",
    KnifeMiniSquare = "boolean",
    KnifeMiniScale = "miniScale",
    KnifeMiniX = "position",
    KnifeMiniY = "position",
  },
  defaults = {
    ShootKeybind = Enum.KeyCode.Q,
    KnifeThrowKeybind = Enum.KeyCode.E,
    AutoFarm = false,
    AvoidMurdererCoins = false,
    ResetWhenBagFull = false,
    FarmSpeed = 40,
    ManualShootMurder = false,
    ManualShootMurderInvisible = false,
    ManualShootMurderAccuracy = 100,
    AutoShootMurder = false,
    AutoShootMurderAccuracy = 100,
    LegitSheriff = false,
    AutoKnifeAttack = false,
    AutoKnifeAttackTargets = "All",
    ManualKnifeThrow = false,
    ManualKnifeInvisible = false,
    AutoKnifeThrow = false,
    AutoKnifeThrowTargets = "Auto",
    KnifeCone = 35,
    AutoGunPickup = true,
    GunPickupSafety = false,
    AutoTeleportToGun = false,
    MapTargetPlayer = "None",
    FavoriteMap = "None",
    ESPEnabled = true,
    ESPShowIdentity = true,
    ESPShowUsername = true,
    ESPShowSelf = true,
    ESPShowDistance = true,
    ESPMurderer = true,
    ESPSheriff = true,
    ESPInnocent = true,
    ESPCandyCoin = false,
    ESPGun = true,
    AlertRoleAndMurderer = true,
    AlertGunDropped = true,
    ShootMiniSquare = true,
    ShootMiniScale = 1,
    KnifeMiniSquare = true,
    KnifeMiniScale = 1,
  },
}
for _, page in ipairs(GameUI.definition.pages) do
  for _, section in ipairs(page.sections) do
    for _, component in ipairs(section.components) do
      if not component.mobileOnly and (component.kind == "toggle" or component.kind == "checkbox" or component.kind == "button") then
        component.shortcutKey = component.shortcutKey or ("MM2" .. (component.key or component.action) .. "Keybind")
      end
      if component.shortcutKey then
        local key = component.shortcutKey
        GameUI.__config.schema[key] = "keyCode"
        if GameUI.__config.defaults[key] == nil then
          GameUI.__config.defaults[key] = Enum.KeyCode.Unknown
        end
      end
      if component.tint then
        component.color = Color3.fromRGB(table.unpack(component.tint))
        component.tint = nil
      end
    end
  end
end
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }
return GameUI
