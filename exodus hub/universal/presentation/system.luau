-- [[ universal section ]]
--!optimize 2
-- @modules sectionsystem
local Section = {}
Section.definition = {
  column = 2,
  title = "Sistema",
  components = {
    { kind = "toggle", title = "Anti AFK", key = "AntiAFK", shortcutKey = "AntiAFKKeybind" },
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
Section.__contract = { section = 50, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
