-- [[ universal section ]]
--!optimize 2
-- @modules sectionmovement
local Section = {}
Section.definition = {
  column = 2,
  title = "Movimento",
  components = {
    { kind = "toggle", title = "Auto Jump", key = "AutoJump", shortcutKey = "JumpKeybind" },
    {
      kind = "toggle",
      title = "Speed",
      description = "Usa a velocidade definida abaixo.",
      key = "UniversalSpeedEnabled",
      desktopExpanded = true,
      shortcutKey = "SpeedKeybind",
    },
    {
      kind = "scroll",
      title = "Speed",
      description = "Define a velocidade.",
      key = "UniversalSpeed",
      parentKey = "UniversalSpeedEnabled",
      min = 0,
      max = 200,
      increment = 1,
      valueName = "WalkSpeed",
    },
    {
      kind = "toggle",
      title = "Jump Power",
      key = "UniversalJumpPowerEnabled",
      shortcutKey = "JumpPowerKeybind",
      description = "Altera a força do pulo.",
    },
    {
      kind = "scroll",
      title = "Jump Power",
      key = "UniversalJumpPower",
      parentKey = "UniversalJumpPowerEnabled",
      min = 0,
      max = 300,
      increment = 1,
    },
    {
      kind = "toggle",
      title = "Infinite Jump",
      description = "Pula no ar.",
      key = "UniversalInfiniteJump",
      shortcutKey = "InfiniteJumpKeybind",
    },
    { kind = "toggle", title = "Fly", description = "Permite voar.", key = "UniversalFly", shortcutKey = "FlyKeybind" },
    {
      kind = "scroll",
      title = "Fly Speed",
      description = "1x = 50 studs/s.",
      key = "UniversalFlySpeed",
      parentKey = "UniversalFly",
      min = 0.1,
      max = 10,
      increment = 0.1,
      valueName = "x",
    },
    {
      kind = "toggle",
      title = "Gravity",
      description = "Usa a gravidade definida abaixo.",
      key = "UniversalGravityEnabled",
      shortcutKey = "GravityKeybind",
    },
    {
      kind = "scroll",
      title = "Gravity",
      description = "Define a gravidade.",
      key = "UniversalGravity",
      parentKey = "UniversalGravityEnabled",
      min = 0,
      max = 400,
      increment = 1,
      valueName = "studs/s²",
    },
    {
      kind = "toggle",
      title = "Noclip",
      description = "Atravessa objetos.",
      key = "UniversalNoclip",
      shortcutKey = "NoclipKeybind",
    },
  },
}
Section.__config = { schema = {}, defaults = {} }
for _, component in ipairs(Section.definition.components) do
  if component.shortcutKey then
    Section.__config.schema[component.shortcutKey] = "keyCode"
    Section.__config.defaults[component.shortcutKey] = component.shortcutKey == "JumpKeybind" and Enum.KeyCode.J or Enum.KeyCode.Unknown
  end
end
function Section.setup() return true end
Section.__contract = { section = 20, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
