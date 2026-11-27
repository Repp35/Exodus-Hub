-- [[ universal section ]]
--!optimize 2
-- @modules sectionantilag
local Section = {}
Section.definition = {
  title = "Anti Lag",
  components = {
    { kind = "toggle", title = "Ativar Anti Lag", key = "AntiLagEnabled", description = "Gráfico mínimo, sem luzes, sombras ou pós-processamento." },
    {
      kind = "toggle",
      title = "Limitar renderização distante",
      key = "AntiLagDistanceCull",
      parentKey = "AntiLagEnabled",
      description = "Oculta apenas geometria distante. Nunca destrói objetos.",
    },
    {
      kind = "slider",
      title = "Distância de renderização",
      key = "AntiLagRenderDistance",
      parentKey = "AntiLagDistanceCull",
      min = 300,
      max = 6000,
      increment = 50,
      valueName = "studs",
    },
    {
      kind = "slider",
      title = "Preservar objetos próximos",
      key = "AntiLagKeepNear",
      parentKey = "AntiLagEnabled",
      min = 64,
      max = 512,
      increment = 16,
      valueName = "studs",
    },
    { kind = "toggle", title = "Simplificar objetos distantes", key = "AntiLagSimplifyFar", parentKey = "AntiLagEnabled" },
    { kind = "toggle", title = "Remover efeitos", key = "AntiLagRemoveEffects", parentKey = "AntiLagEnabled" },
    {
      kind = "toggle",
      title = "Remover texturas",
      key = "AntiLagRemoveTextures",
      parentKey = "AntiLagEnabled",
      description = "Opcional. Desativado por padrão.",
    },
    { kind = "toggle", title = "Materiais simples", key = "AntiLagFlatMaterials", parentKey = "AntiLagEnabled" },
    { kind = "toggle", title = "Qualidade gráfica mínima", key = "AntiLagLowestGraphics", parentKey = "AntiLagEnabled" },
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
Section.__contract = { section = 10, provides = { "setup" }, data = { "definition" }, requires = {} }
return Section
