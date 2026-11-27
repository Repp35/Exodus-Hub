-- [[ gameui ]]
--!optimize 2

-- code
local GameUI = {}
local function createActions(context)
  local utils, controls, hub = context.utils, context.controls, context.hub
  return {
    callbacks = {
      panic = function()
        context.setSpam(false)
        if controls.onPanic then
          controls.onPanic()
        end
      end,
      upDash = function()
        local ok, reason = hub.getAbilityAvailability("dash")
        if ok then
          controls.onUpDash()
        else
          context.notify(reason)
        end
      end,
      manualSpam = function(enabled)
        if context.desktop then
          if utils.getConfigValue("ManualSpamMode") ~= "Hold" then
            context.setSpam(enabled)
          end
        else
          context.showMini(enabled)
        end
        return true
      end,
    },
    states = {
      manualSpam = function() return context.desktop and utils.isManualSpamActive() or not context.desktop and utils.getConfigValue("MiniSpamVisible") == true end,
    },
    resolve = function(definition)
      if definition.action == "manualSpam" and not context.desktop then
        definition.key = "MiniSpamVisible"
      end
      if definition.action == "manualSpam" or definition.action == "upDash" then
        definition.silentShortcut = true
      end
    end,
  }
end

GameUI.definition = {
  createActions = createActions,
  input = {
    primary = { visibleKey = "MiniSpamVisible", bindingKey = "SpamKeybind", modeKey = "ManualSpamMode", read = "isManualSpamActive", write = "setManualSpam" },
    reserved = { { enabledKey = "DynamicParry", bindingKey = "DynamicParryKey" } },
  },
  miniBalls = {
    {
      id = "parry",
      label = "PARRY",
      key = "AutoParry",
      visibleKey = "ParryBallVisible",
      xKey = "ParryBallX",
      yKey = "ParryBallY",
      textSize = 14,
      defaultX = 14,
      offsetY = -104,
    },
    {
      id = "clash",
      onText = "ON",
      offText = "OFF",
      key = "AutoSpam",
      visibleKey = "ClashBallVisible",
      xKey = "ClashBallX",
      yKey = "ClashBallY",
      onTextSize = 18,
      offTextSize = 16,
      pulse = true,
      defaultX = 14,
      offsetY = -32,
    },
    {
      id = "dark",
      onText = "ON",
      offText = "OFF",
      key = "AutoDark",
      visibleKey = "DarkBallVisible",
      xKey = "DarkBallX",
      yKey = "DarkBallY",
      ability = "dark",
      onColor = "darkOn",
      offColor = "darkOff",
      onTextSize = 18,
      offTextSize = 16,
      pulse = true,
      defaultX = 14,
      offsetY = 40,
    },
    {
      id = "jump",
      label = "JUMP",
      key = "AutoJump",
      visibleKey = "JumpBallVisible",
      xKey = "JumpBallX",
      yKey = "JumpBallY",
      onColor = "jumpOn",
      offColor = "jumpOff",
      textSize = 15,
      defaultX = 86,
      offsetY = -32,
    },
    {
      id = "dash",
      label = "DASH\n↑",
      action = "onUpDash",
      visibleKey = "UpDashBallVisible",
      xKey = "UpDashBallX",
      yKey = "UpDashBallY",
      ability = "dash",
      offColor = "upDash",
      textSize = 15,
      pulse = true,
      defaultX = 86,
      offsetY = 40,
    },
    {
      id = "manual",
      panel = true,
      title = "Spam",
      onText = "ON",
      offText = "OFF",
      widthKey = "MiniSpamWidth",
      heightKey = "MiniSpamHeight",
      action = "setManualSpam",
      read = "isManualSpamActive",
      modeKey = "ManualSpamMode",
      visibleKey = "MiniSpamVisible",
      xKey = "MiniX",
      yKey = "MiniY",
      scaleKey = "MiniSpamScale",
      invisibleKey = "MiniSpamInvisible",
    },
  },
  combatUI = true,
  abilityKeys = { AutoDark = "dark", DarkBallVisible = "dark", AutoFierce = "fierce", AutoClashUpDash = "dash", UpDashBallVisible = "dash" },
  pageOrder = { "main", "settings", "utilities", "antilag", "automatic", "indeed", "assists", "config" },
  pages = {
    {
      id = "main",
      integrationOnly = true,
      title = "Main",
      columns = 2,
      sections = {
        {
          title = "Combat",
          column = 1,
          components = {
            { kind = "toggle", title = "Auto Parry", key = "AutoParry", shortcutKey = "ParryKeybind" },
            { kind = "toggle", title = "Auto Spam", key = "AutoSpam", shortcutKey = "ClashKeybind" },
            {
              kind = "toggle",
              title = "Mini Parry UI",
              description = "Mostra o botão de parry.",
              key = "ParryBallVisible",
              mobileOnly = true,
            },
            {
              kind = "toggle",
              title = "Mini Clash UI",
              description = "Mostra o botão de spam.",
              key = "ClashBallVisible",
              mobileOnly = true,
            },
          },
        },
        {
          title = "Spam",
          column = 2,
          components = {
            { kind = "rate_selector", title = "Spam Rate" },
            {
              kind = "dropdown",
              title = "Click Method",
              key = "ClickMethod",
              options = {
                { value = "Deflect", label = "Standard" },
                { value = "Direct", label = "Direct remote" },
                { value = "Input", label = "Key input" },
              },
            },
          },
        },
        {
          title = "Manual Spam",
          column = 2,
          components = {
            { kind = "toggle", title = "Manual Spam", action = "manualSpam", shortcutKey = "SpamKeybind" },
            {
              kind = "segmented",
              title = "Spam activation",
              key = "ManualSpamMode",
              options = { { value = "Toggle", label = "Toggle" }, { value = "Hold", label = "Hold" } },
            },
            {
              kind = "slider",
              title = "Manual Spam Size",
              key = "MiniSpamScale",
              compact = true,
              mobileOnly = true,
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
            },

            {
              kind = "slider",
              title = "Manual Spam Width",
              key = "MiniSpamWidth",
              compact = true,
              mobileOnly = true,
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
            },
            {
              kind = "slider",
              title = "Manual Spam Height",
              key = "MiniSpamHeight",
              compact = true,
              mobileOnly = true,
              min = 0.5,
              max = 2,
              increment = 0.05,
              valueName = "x",
            },
          },
        },
        {
          title = "Dynamic Parry",
          column = 2,
          components = {
            { kind = "toggle", title = "Dynamic Parry", key = "DynamicParry" },
            { kind = "toggle", title = "Dynamic Deactivation", key = "DynamicParryDeactivation", parentKey = "DynamicParry" },
            {
              kind = "segmented",
              title = "Activation Mode",
              key = "DynamicParryMode",
              options = { { value = "Toggle", label = "Toggle" }, { value = "Hold", label = "Hold" } },
            },
            { kind = "keybind", title = "PC / Controller Button", key = "DynamicParryKey", desktopOnly = true },
          },
        },
        {
          title = "Shortcuts",
          column = 2,
          desktopOnly = true,
          components = {
            { kind = "button", title = "Stop Functions", action = "panic", shortcutPriority = 0, shortcutKey = "Keybind" },
          },
        },
      },
    },
    {
      id = "settings",
      integrationOnly = true,
      title = "Settings",
      columns = 1,
      sections = {
        {
          title = "Clash Indicators",
          column = 1,
          components = {
            { kind = "toggle", title = "Clash Distance", key = "ClashDistanceVisible", shortcutKey = "DistanceInfoKeybind" },
            { kind = "toggle", title = "Ball travel time", key = "ClashTravelTimeVisible", shortcutKey = "TravelInfoKeybind" },
            { kind = "toggle", title = "AutoSpam Gates", key = "ClashGateInfoVisible", shortcutKey = "GateInfoKeybind" },
            { kind = "toggle", title = "AP Max CPS", key = "APMaxCpsVisible" },
          },
        },
      },
    },
    {
      id = "utilities",
      integrationOnly = true,
      title = "Utilities",
      columns = 1,
      sections = {
        {
          title = "Utilities",
          components = {
            { kind = "toggle", title = "Sword", action = "spinSword", shortcutKey = "SwordKeybind" },
            { kind = "toggle", title = "Emote", action = "spinEmote", shortcutKey = "EmoteKeybind" },
            { kind = "toggle", title = "Explosion", action = "spinExplosion", shortcutKey = "ExplosionKeybind" },
          },
        },
      },
    },
    {
      id = "automatic",
      integrationOnly = true,
      title = "Automatic",
      columns = 2,
      sections = {
        {
          title = "Automatic Abilities",
          column = 1,
          components = {
            { kind = "toggle", title = "Auto Dark", key = "AutoDark", shortcutKey = "DarkKeybind" },
            { kind = "toggle", title = "Auto Fierce", key = "AutoFierce", shortcutKey = "FierceKeybind" },
            { kind = "toggle", title = "Auto Dash (clash)", key = "AutoClashUpDash", shortcutKey = "AutoDashKeybind" },
          },
        },
        {
          title = "Quick Controls",
          column = 2,
          components = {
            { kind = "button", title = "Up Dash", action = "upDash", shortcutKey = "UpDashKeybind", desktopOnly = true },
            {
              kind = "toggle",
              title = "Mini Dark UI",
              description = "Mostra o botão de Auto Dark.",
              key = "DarkBallVisible",
              mobileOnly = true,
            },
            {
              kind = "toggle",
              title = "Mini Auto Jump",
              description = "Mostra o botão de Auto Jump.",
              key = "JumpBallVisible",
              mobileOnly = true,
            },
            {
              kind = "toggle",
              title = "Mini Up Dash",
              description = "Mostra o botão de Up Dash.",
              key = "UpDashBallVisible",
              mobileOnly = true,
            },
          },
        },
      },
    },
    {
      id = "assists",
      integrationOnly = true,
      title = "Assistências",
      columns = 1,

      utility = true,
      sections = {
        {
          title = "Phantom Ball",
          components = {
            {
              kind = "toggle",
              title = "Mostrar GUI de spam no x1",
              description = "Mostra a mini UI no x1. Não ativa o spam.",
              key = "ManualSpamUIOnDuel",
              mobileOnly = true,
            },
            {
              kind = "toggle",
              title = "Religar AP ao morrer",
              description = "Religa o Auto Parry ao morrer.",
              key = "ParryOnDeath",
            },
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
        { kind = "toggle", title = "Remover som da espada", key = "AntiLagRemoveSwordSounds", parentKey = "AntiLagEnabled" },
      },
    },
  },
}
GameUI.__config = {
  legacy = {
    "AutoClash",
    "AutoClashActivationMs",
    "AutoClashDeactivationMs",
    "ClashMaxDistance",
    "AutoSpamClashPrediction",
    "AutoSpamPredictionMargin",
    "ClashGrace",
    "ClashMaxAge",
  },
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
for _, mini in ipairs(GameUI.definition.miniBalls) do
  mini.mobileOnly = true
  mini.scaleKey = mini.scaleKey or "MiniUIScale"
  mini.squareKey = "MiniUISquare"
end
function GameUI.setup() return true end
GameUI.__contract = { provides = { "setup" }, data = { "definition" }, requires = {} }

return GameUI
