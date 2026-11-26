-- [[ gameui ]]
--!optimize 2

-- code
local GameUI = {}
GameUI.definition = {
  combatUI = true,
  abilityKeys = { AutoDark = "dark", DarkBallVisible = "dark", AutoFierce = "fierce", AutoClashUpDash = "dash", UpDashBallVisible = "dash" },
  pageOrder = { "main", "automatic", "settings", "phantom-mini", "utilities", "indeed", "antilag", "assists", "config", "information" },
  pages = {
    {
      id = "main",
      title = "Combat",
      integrationOnly = true,
      columns = 2,
      sections = {
        {
          title = "Defense",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Parry",
              key = "AutoParry",
              shortcutKey = "ParryKeybind",
              description = "Defende automaticamente no momento calculado.",
            },
            {
              kind = "toggle",
              title = "Auto Spam",
              key = "AutoSpam",
              shortcutKey = "ClashKeybind",
              description = "Repete defesas durante o confronto próximo.",
            },
          },
        },
        {
          title = "Dynamic Parry",
          column = 1,
          components = {
            { kind = "toggle", title = "Dynamic Parry", key = "DynamicParry", description = "Ativa a defesa dinâmica pelo atalho configurado." },
            {
              kind = "toggle",
              title = "Auto Stop",
              key = "DynamicParryDeactivation",
              parentKey = "DynamicParry",
              description = "Encerra ao terminar a janela de defesa.",
            },
            {
              kind = "segmented",
              title = "Activation Mode",
              key = "DynamicParryMode",
              parentKey = "DynamicParry",
              options = { { value = "Toggle", label = "Toggle" }, { value = "Hold", label = "Hold" } },
              description = "Escolhe entre alternar e manter pressionado.",
            },
            {
              kind = "keybind",
              title = "Activation Key",
              key = "DynamicParryKey",
              parentKey = "DynamicParry",
              desktopOnly = true,
              description = "Define o botão do teclado ou controle.",
            },
          },
        },
        {
          title = "Spam Settings",
          column = 2,
          components = {
            { kind = "rate_selector", title = "Spam Rate", description = "Define a frequência das defesas repetidas." },
            {
              kind = "dropdown",
              title = "Click Method",
              key = "ClickMethod",
              description = "Escolhe como enviar a defesa.",
              options = { { value = "Deflect", label = "Standard" }, { value = "Direct", label = "Direct" }, { value = "Input", label = "Key Input" } },
            },
          },
        },
        {
          title = "Manual Spam",
          column = 2,
          components = {
            {
              kind = "toggle",
              title = "Manual Spam",
              action = "manualSpam",
              shortcutKey = "SpamKeybind",
              desktopOnly = true,
              description = "Controla o spam pelo botão ou atalho.",
            },
            {
              kind = "segmented",
              title = "Activation Mode",
              key = "ManualSpamMode",
              options = { { value = "Toggle", label = "Toggle" }, { value = "Hold", label = "Hold" } },
              description = "Escolhe entre alternar e manter pressionado.",
            },
            {
              kind = "button",
              title = "Stop Combat",
              action = "panic",
              shortcutKey = "Keybind",
              desktopOnly = true,
              description = "Desliga Auto Parry e Auto Spam e encerra o spam atual.",
            },
          },
        },
      },
    },
    {
      id = "automatic",
      title = "Abilities",
      integrationOnly = true,
      columns = 2,
      sections = {
        {
          title = "Automatic Abilities",
          column = 1,
          components = {
            {
              kind = "toggle",
              title = "Auto Dark",
              key = "AutoDark",
              shortcutKey = "DarkKeybind",
              description = "Usa Dark automaticamente quando necessário.",
            },
            {
              kind = "toggle",
              title = "Auto Fierce",
              key = "AutoFierce",
              shortcutKey = "FierceKeybind",
              description = "Usa Fierce automaticamente quando necessário.",
            },
            {
              kind = "toggle",
              title = "Auto Clash Dash",
              key = "AutoClashUpDash",
              shortcutKey = "AutoDashKeybind",
              description = "Usa o dash durante o confronto próximo.",
            },
          },
        },
        {
          title = "Manual Actions",
          column = 2,
          desktopOnly = true,
          components = {
            { kind = "button", title = "Up Dash", action = "upDash", shortcutKey = "UpDashKeybind", description = "Executa um dash para cima." },
          },
        },
      },
    },
    {
      id = "settings",
      title = "Overlay",
      integrationOnly = true,
      columns = 1,
      width = 360,
      sections = {
        {
          title = "Combat Indicators",
          components = {
            {
              kind = "toggle",
              title = "Clash Distance",
              key = "ClashDistanceVisible",
              shortcutKey = "DistanceInfoKeybind",
              description = "Mostra a distância do confronto.",
            },
            {
              kind = "toggle",
              title = "Ball Travel Time",
              key = "ClashTravelTimeVisible",
              shortcutKey = "TravelInfoKeybind",
              description = "Mostra o tempo estimado de chegada da bola.",
            },
            {
              kind = "toggle",
              title = "Auto Spam Conditions",
              key = "ClashGateInfoVisible",
              shortcutKey = "GateInfoKeybind",
              description = "Mostra as condições que liberam o Auto Spam.",
            },
            { kind = "toggle", title = "Parry CPS Limit", key = "APMaxCpsVisible", description = "Mostra o limite de defesas por segundo." },
          },
        },
      },
    },
    {
      id = "phantom-mini",
      title = "Quick Controls",
      integrationOnly = true,
      mobileOnly = true,
      columns = 2,
      sections = {
        {
          title = "Combat Buttons",
          column = 1,
          components = {
            { kind = "toggle", title = "Auto Parry", key = "ParryBallVisible", description = "Mostra o botão flutuante de Auto Parry." },
            { kind = "toggle", title = "Auto Spam", key = "ClashBallVisible", description = "Mostra o botão flutuante de Auto Spam." },
            { kind = "toggle", title = "Manual Spam Panel", key = "MiniSpamVisible", action = "manualSpam", description = "Mostra o painel de spam manual." },
            {
              kind = "slider",
              title = "Panel Width",
              key = "MiniSpamWidth",
              parentKey = "MiniSpamVisible",
              compact = true,
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
              description = "Ajusta a largura do painel.",
            },
            {
              kind = "slider",
              title = "Panel Height",
              key = "MiniSpamHeight",
              parentKey = "MiniSpamVisible",
              compact = true,
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
              description = "Ajusta a altura do painel.",
            },
          },
        },
        {
          title = "Ability & Movement Buttons",
          column = 2,
          components = {
            { kind = "toggle", title = "Auto Dark", key = "DarkBallVisible", description = "Mostra o botão flutuante de Auto Dark." },
            { kind = "toggle", title = "Up Dash", key = "UpDashBallVisible", description = "Mostra o botão flutuante de Up Dash." },
            { kind = "toggle", title = "Auto Jump", key = "JumpBallVisible", description = "Mostra o botão flutuante de Auto Jump." },
          },
        },
      },
    },
    {
      id = "utilities",
      title = "Extras",
      integrationOnly = true,
      columns = 1,
      width = 360,
      sections = {
        {
          title = "Auto Crates",
          components = {
            {
              kind = "toggle",
              title = "Sword Crates",
              action = "spinSword",
              shortcutKey = "SwordKeybind",
              description = "Abre caixas de espada automaticamente.",
            },
            {
              kind = "toggle",
              title = "Emote Crates",
              action = "spinEmote",
              shortcutKey = "EmoteKeybind",
              description = "Abre caixas de emote automaticamente.",
            },
            {
              kind = "toggle",
              title = "Finisher Crates",
              action = "spinExplosion",
              shortcutKey = "ExplosionKeybind",
              description = "Abre caixas de finalização automaticamente.",
            },
          },
        },
      },
    },
    {
      id = "assists",
      title = "Helpers",
      integrationOnly = true,
      columns = 1,
      width = 360,
      utility = true,
      sections = {
        {
          title = "Match Helpers",
          components = {
            {
              kind = "toggle",
              title = "Duel Spam Panel",
              key = "ManualSpamUIOnDuel",
              mobileOnly = true,
              description = "Mostra o painel no x1 sem ativar o spam.",
            },
            { kind = "toggle", title = "Restore Parry on Death", key = "ParryOnDeath", description = "Religa o Auto Parry ao morrer." },
          },
        },
      },
    },
  },
  additions = {
    {
      page = "antilag",
      section = 1,
      components = {
        {
          kind = "toggle",
          title = "Mute Sword Sounds",
          key = "AntiLagRemoveSwordSounds",
          parentKey = "AntiLagEnabled",
          description = "Silencia os sons das espadas.",
        },
      },
    },
  },
}
GameUI.__config = {
  schema = {
    AutoParry = "boolean",
    AutoParryWindowFactor = "rate",
    AutoParryFactor08Applied = "boolean",
    AutoParryFactor03Applied = "boolean",
    ParryBallVisible = "boolean",
    ParryBallX = "position",
    ParryBallY = "position",
    AutoSpam = "boolean",
    AutoDark = "boolean",
    AutoFierce = "boolean",
    AutoClashUpDash = "boolean",
    ClashBallVisible = "boolean",
    ClashDistanceVisible = "boolean",
    ClashTravelTimeVisible = "boolean",
    ClashGateInfoVisible = "boolean",
    APMaxCpsVisible = "boolean",
    MiniSpamVisible = "boolean",
    MiniSpamScale = "miniScale",
    MiniSpamWidth = "miniScale",
    MiniSpamHeight = "miniScale",
    DarkBallVisible = "boolean",
    JumpBallVisible = "boolean",
    UpDashBallVisible = "boolean",
    CPS = "rate",
    CPF = "rate",
    MS = "rate",
    SpamRateMode = "rateMode",
    DynamicParry = "boolean",
    DynamicParryMode = "spamActivation",
    DynamicParryKey = "keyCode",
    DynamicParryDeactivation = "boolean",
    ManualSpamMode = "spamActivation",
    ClickMethod = "clickMethod",
    Keybind = "keyCode",
    SpamKeybind = "keyCode",
    ManualSpamUIOnDuel = "boolean",
    ParryOnDeath = "boolean",
    ManualSpamEnabled = "boolean",
    ParryKeybind = "keyCode",
    ClashKeybind = "keyCode",
    DarkKeybind = "keyCode",
    UpDashKeybind = "keyCode",
    ClashBallX = "position",
    ClashBallY = "position",
    DarkBallX = "position",
    DarkBallY = "position",
    JumpBallX = "position",
    JumpBallY = "position",
    UpDashBallX = "position",
    UpDashBallY = "position",
    MiniX = "position",
    MiniY = "position",
  },
  defaults = {
    AutoParry = true,
    AutoParryWindowFactor = 0.45,
    AutoParryFactor08Applied = true,
    AutoParryFactor03Applied = true,
    ParryBallVisible = false,
    AutoSpam = true,
    AutoDark = false,
    AutoFierce = true,
    AutoClashUpDash = true,
    ClashBallVisible = false,
    ClashDistanceVisible = false,
    ClashTravelTimeVisible = false,
    ClashGateInfoVisible = false,
    APMaxCpsVisible = false,
    MiniSpamVisible = false,
    MiniSpamScale = 1,
    MiniSpamWidth = 1,
    MiniSpamHeight = 1,
    DarkBallVisible = false,
    JumpBallVisible = false,
    UpDashBallVisible = false,
    CPS = 200,
    CPF = 10,
    MS = 10,
    SpamRateMode = "CPF",
    DynamicParry = false,
    DynamicParryMode = "Toggle",
    DynamicParryKey = Enum.KeyCode.F,
    DynamicParryDeactivation = true,
    ManualSpamMode = "Toggle",
    ClickMethod = "Deflect",
    Keybind = Enum.KeyCode.F9,
    SpamKeybind = Enum.KeyCode.F,
    ManualSpamUIOnDuel = false,
    ParryOnDeath = false,
    ManualSpamEnabled = false,
    ParryKeybind = Enum.KeyCode.P,
    ClashKeybind = Enum.KeyCode.C,
    DarkKeybind = Enum.KeyCode.D,
    UpDashKeybind = Enum.KeyCode.U,
  },
}
for _, page in ipairs(GameUI.definition.pages) do
  for _, section in ipairs(page.sections) do
    for _, component in ipairs(section.components or {}) do
      local key = component.shortcutKey
      if key then
        GameUI.__config.schema[key] = "keyCode"
        if GameUI.__config.defaults[key] == nil then
          GameUI.__config.defaults[key] = Enum.KeyCode.Unknown
        end
      end
    end
  end
end
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }

return GameUI
