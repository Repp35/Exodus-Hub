-- [[ universal section ]]
--!optimize 2
-- @modules sectioncamera
local Section = {}
Section.definition = {
  title = "Câmera",
  components = {
    { kind = "number", title = "Camera Sensitivity", key = "CameraSensitivity", min = 0 },
    {
      kind = "toggle",
      title = "Infinite Zoom",
      description = "Libera o zoom da câmera.",
      key = "UniversalInfiniteZoom",
    },
    { kind = "toggle", title = "FOV", key = "UniversalFOVEnabled" },
    {
      kind = "scroll",
      title = "Field of View",
      key = "UniversalFOV",
      parentKey = "UniversalFOVEnabled",
      min = 1,
      max = 120,
      increment = 1,
      valueName = "°",
    },
    {
      kind = "toggle",
      title = "Invisicam",
      description = "Torna transparentes os obstáculos entre a câmera e o personagem.",
      key = "UniversalInvisicam",
      shortcutKey = "InvisicamKeybind",
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
Section.__contract = { section = 30, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
