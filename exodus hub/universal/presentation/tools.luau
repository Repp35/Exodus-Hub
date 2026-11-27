-- [[ universal section ]]
--!optimize 2
-- @modules sectiontools
local Section = {}
Section.definition = {
  title = "Ferramentas",
  components = {
    {
      kind = "click",
      title = "Dumper",
      description = "Salva scripts acessíveis. Depende do executor.",
      action = "dumper",
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
Section.__contract = { section = 60, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
