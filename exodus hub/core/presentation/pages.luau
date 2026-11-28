-- [[ deterministic page composition ]]
--!optimize 2
-- @modules uiconfig
local UIConfig = {}
local pages = {}
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = copy(item)
  end
  return result
end
function UIConfig.configure(definitions, universal)
  pages = copy(definitions)
  for _, page in ipairs(pages) do
    if page.id == "indeed" then
      page.sections = copy(universal or {})
    end
  end
  UIConfig.pages = pages
end
function UIConfig.getPages(definition)
  definition = definition or {}
  local result, own, host = {}, {}, {}
  for _, page in ipairs(pages) do
    host[page.id] = true
  end
  for _, page in ipairs(definition.pages or {}) do
    assert(not own[page.id] and not host[page.id], "Duplicate game page: " .. tostring(page.id))
    own[page.id] = copy(page)
  end
  for _, id in ipairs(definition.pageOrder or {}) do
    assert(own[id], "Unknown or repeated game page: " .. tostring(id))
    result[#result + 1], own[id] = own[id], nil
  end
  for _, page in ipairs(definition.pages or {}) do
    if own[page.id] then
      result[#result + 1], own[page.id] = own[page.id], nil
    end
  end
  local byId = {}
  for _, page in ipairs(pages) do
    local value = copy(page)
    result[#result + 1], byId[value.id] = value, value
  end
  for _, addition in ipairs(definition.additions or {}) do
    assert(addition.page == "indeed" and addition.sectionTitle, "Only named universal extensions are supported")
    local page = assert(byId[addition.page], "Unknown extension page")
    page.sections[#page.sections + 1] = { title = addition.sectionTitle, column = 2, components = copy(addition.components or {}) }
  end
  return result
end
function UIConfig.migrateConfig(data)
  local changed = false
  for _, key in ipairs({ "MiniUISquare", "MiniUIRoundDefaultRestored", "AntiLagFloorCull", "AntiLagRemoveSwordSounds" }) do
    if data[key] ~= nil then
      data[key], changed = nil, true
    end
  end
  return changed
end
UIConfig.pages = pages
UIConfig.__config = {
  schema = {
    MobileNotifications = "boolean",
    DesktopNotifications = "boolean",
    DesktopShortcutNotifications = "boolean",
    ForcePCUI = "boolean",
    MiniUIScale = "miniScale",
    CameraSensitivity = "rate",
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
    MiniUIScale = 1,
    CameraSensitivity = 1,
  },
  constraints = { CameraSensitivity = { min = 0, max = 10 } },
}
UIConfig.__contract =
  { access = { methods = { configure = "infrastructure.write" } }, provides = { "configure", "getPages", "migrateConfig" }, data = { "pages" }, requires = {} }
return UIConfig
