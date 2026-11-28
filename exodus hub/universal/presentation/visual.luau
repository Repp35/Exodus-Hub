-- [[ universal section ]]
--!optimize 2
-- @modules sectionvisual
local Section = {}
Section.definition = {
  column = 2,
  title = "Visual",
  components = {
    { kind = "toggle", title = "Fullbright", key = "UniversalFullbright" },
    { kind = "toggle", title = "Remover neblina", key = "UniversalNoFog" },
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
Section.__contract = { section = 40, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
