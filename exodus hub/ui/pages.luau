-- [[ pages ]]
--!optimize 2
-- @modules uipages

-- module
local Pages = {}

-- configuration
local CONFIG = { COLUMNS = { [1] = true, [2] = true } }

-- setup
function Pages.setup() return true end

-- validation
function Pages.validate(definitions, components)
  assert(type(definitions) == "table" and #definitions > 0, "UI pages must be a non-empty ordered list")
  local ids, normal = {}, 0
  for _, page in ipairs(definitions) do
    assert(type(page.id) == "string" and page.id ~= "" and not ids[page.id], "UI page id must be unique")
    assert(type(page.title) == "string" and type(page.sections) == "table", "UI page requires title and sections: " .. page.id)
    assert(CONFIG.COLUMNS[page.columns], "UI page columns must be 1 or 2: " .. page.id)
    ids[page.id] = true
    if not page.utility then
      normal += 1
    end
    local keys, parents = {}, {}
    for _, section in ipairs(page.sections) do
      assert((section.column or 1) >= 1 and (section.column or 1) <= page.columns, "Invalid column in " .. page.id)
      for _, definition in ipairs(section.components or {}) do
        assert(type(components[definition.kind]) == "function", "Unknown UI component: " .. tostring(definition.kind) .. " in " .. page.id)
        if definition.key then
          assert(not keys[definition.key], "Duplicate UI key in " .. page.id .. ": " .. definition.key)
          keys[definition.key] = true
        end
        if definition.parentKey then
          parents[definition.key or definition] = definition.parentKey
        end
      end
    end
    for key, parent in pairs(parents) do
      local visited = { [key] = true }
      while parent do
        assert(keys[parent] and not visited[parent], "Missing or cyclic parentKey in " .. page.id)
        visited[parent] = true
        parent = parents[parent]
      end
    end
  end
  assert(normal > 0, "UI needs at least one primary page")
  return true
end
function Pages.forGame(definitions, integrated)
  local pages = {}
  for _, sourcePage in ipairs(definitions) do
    if sourcePage.integrationOnly and not integrated then
      continue
    end
    local page = table.clone(sourcePage)
    page.sections = {}
    for _, sourceSection in ipairs(sourcePage.sections) do
      if sourceSection.integrationOnly and not integrated then
        continue
      end
      local section = table.clone(sourceSection)
      section.components = {}
      for _, definition in ipairs(sourceSection.components or {}) do
        if not definition.integrationOnly or integrated then
          section.components[#section.components + 1] = table.clone(definition)
        end
      end
      if #section.components > 0 then
        page.sections[#page.sections + 1] = section
      end
    end
    if #page.sections > 0 then
      pages[#pages + 1] = page
    end
  end
  return pages
end

-- rendering
function Pages.create(kit, parent, definitions, context)
  context = context or {}
  context.read = context.read or kit.read
  Pages.validate(definitions, kit.Components)
  local T, inst = kit.Theme, kit.instance
  local width = T.PANEL_W - T.PAD * 2
  local height = T.PANEL_H - T.TITLE_H - 60
  local origin = UDim2.fromOffset(T.PAD, T.TITLE_H + T.PAD)
  local registry, normal, rows, bindings, readouts = {}, {}, {}, {}, {}
  local readoutRows, sections = {}, {}
  local active, returnId, generation = nil, nil, 0
  local tweens, transitioning = {}, false
  local alive = true
  local controller = {}
  local lifetime = kit.scope.child()
  local motion = kit.createMotion(lifetime)
  local bleed = T.CONTROL_BLEED
  local refreshDisclosure
  local function list(parent, gap)
    return inst(
      "UIListLayout",
      { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or T.CARD_GAP), HorizontalAlignment = Enum.HorizontalAlignment.Center },
      parent
    )
  end
  local function stack(parent, name, row)
    local root =
      inst("Frame", { Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 6 }, parent)
    list(root, row and math.max(0, T.CARD_GAP - bleed) or math.max(0, T.CARD_GAP - bleed * 2))
    if row then
      inst("UIPadding", { PaddingTop = UDim.new(0, bleed), PaddingBottom = UDim.new(0, bleed) }, root)
    end
    return root
  end
  local function included(definition)
    if definition.requiresCapability and not (context.capabilities and context.capabilities[definition.requiresCapability]) then
      return false
    end
    return not (context.desktop and definition.mobileOnly) and not (not context.desktop and definition.desktopOnly)
  end
  for _, definition in ipairs(definitions) do
    local root = inst("CanvasGroup", {
      GroupTransparency = 1,
      Name = "Page_" .. definition.id,
      Size = UDim2.fromOffset(width, height),
      Position = origin,
      BackgroundTransparency = 1,
      Visible = false,
      ClipsDescendants = true,
      ZIndex = 6,
    }, parent)
    local page = { Root = root, definition = definition, columns = {}, rows = {} }
    registry[definition.id] = page
    if not definition.utility then
      normal[#normal + 1] = definition.id
    end
    local pageWidth = definition.columns == 1 and math.min(width, T.SINGLE_COLUMN_W) or width
    local columnWidth = (pageWidth - T.GAP * (definition.columns - 1)) / definition.columns
    for column = 1, definition.columns do
      local scroll = inst("ScrollingFrame", {
        Name = "Column" .. column,
        Size = UDim2.fromOffset(columnWidth, height),
        Position = UDim2.fromOffset((width - pageWidth) / 2 + (column - 1) * (columnWidth + T.GAP), 0),
        BackgroundTransparency = 1,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = T.SCROLLBAR,
        ScrollBarImageColor3 = T.COLORS.accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
        Active = true,
        ZIndex = 6,
      }, root)
      inst(
        "UIPadding",
        { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, T.CARD_GAP) },
        scroll
      )
      list(scroll, math.max(0, T.CARD_GAP - bleed * 2))
      page.columns[column] = scroll
    end
    local keyed, pending = {}, {}
    for sectionIndex, section in ipairs(definition.sections) do
      if included(section) then
        local sectionRoot = stack(page.columns[section.column or 1], "Section" .. sectionIndex)
        sections[sectionRoot] = {}
        sectionRoot.LayoutOrder = sectionIndex
        if section.title then
          local label = kit.Components.label(sectionRoot, { text = section.title })
          label.Root.LayoutOrder = 0
        end
        for index, source in ipairs(section.components or {}) do
          if included(source) then
            local options = table.clone(source)
            local row = stack(sectionRoot, "Row_" .. tostring(source.key or source.action or index), true)
            row.LayoutOrder = index
            local ok, handle = pcall(function()
              if context.resolve then
                options = context.resolve(options) or options
              end
              if options.kind ~= "readout" and options.kind ~= "divider" and options.kind ~= "progressBar" then
                local caption = options.title or options.text
                assert(type(caption) == "string" and caption:match("%S"), "Component text is missing")
              end
              local control = kit.Components[options.kind](row, options)
              assert(control and control.Root and control.Root.Parent == row, "Component did not mount")
              if options.kind ~= "readout" and (options.title or options.text) then
                local title = control.Root:FindFirstChild("Title")
                assert(not title or title.Text ~= "", "Component title is empty")
              end
              return control
            end)
            if not ok then
              local reason = handle
              for _, child in ipairs(row:GetChildren()) do
                if child:IsA("GuiObject") then
                  child:Destroy()
                end
              end
              handle = kit.Components.readout(row, { kind = "readout" })
              handle.setValue("Erro: " .. tostring(source.title or source.key or source.kind) .. " não carregou.")
              if context.onError then
                context.onError(source.key or source.info or source.kind, reason, source.title or source.text or "componente")
              end
            end
            handle.Root.LayoutOrder = 0
            local entry = { Root = row, handle = handle, definition = source, parentKey = source.parentKey }
            sections[sectionRoot][#sections[sectionRoot] + 1] = entry
            rows[#rows + 1] = entry
            page.rows[#page.rows + 1] = entry
            if source.info then
              readouts[source.info] = handle
              readoutRows[source.info] = entry
            end
            if source.key then
              keyed[source.key] = entry
              bindings[source.key] = handle
            end
            if source.parentKey then
              pending[#pending + 1] = entry
            end
            if ok and context.onComponent then
              context.onComponent(source, handle)
            end
          end
        end
      end
    end
    for _, entry in ipairs(pending) do
      local owner = keyed[entry.parentKey]
      assert(owner, "Visible child requires a visible parent: " .. entry.parentKey)
      if not owner.children then
        owner.children = inst("Frame", {
          Name = "Children",
          Size = UDim2.new(1, -12, 0, 0),
          BackgroundTransparency = 1,
          Visible = false,
          ClipsDescendants = true,
          LayoutOrder = 1,
          ZIndex = 6,
        }, owner.Root)
        owner.childContent = stack(owner.children, "Content")
        local layout = owner.childContent:FindFirstChildOfClass("UIListLayout")
        lifetime.connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
          if refreshDisclosure then
            refreshDisclosure(entry.parentKey, owner)
          end
        end)
      end
      entry.Root.Parent = owner.childContent
    end
    page.keyed = keyed
  end
  local shield = inst("TextButton", {
    Name = "PageInputShield",
    Size = UDim2.fromOffset(width, height),
    Position = origin,
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 20,
  }, parent)
  local function cancel()
    generation += 1
    for _, tween in ipairs(tweens) do
      motion.cancel(tween)
    end
    tweens = {}
  end
  local function settle()
    for id, page in pairs(registry) do
      page.Root.Visible = id == active
      page.Root.Position = origin
      page.Root.GroupTransparency = id == active and 0 or 1
    end
    transitioning = false
    shield.Visible = false
  end
  local function notify()
    if context.onNavigate then
      context.onNavigate(controller.state())
    end
  end
  function controller.state()
    local index = table.find(normal, active)
    return { id = active, title = registry[active].definition.title, index = index, count = #normal, utility = index == nil, transitioning = transitioning }
  end
  function controller.select(id, animated)
    assert(registry[id], "Unknown UI page: " .. tostring(id))
    if not alive or kit.suspended or (id == active and animated ~= false) then
      return
    end
    kit.dismiss()
    cancel()
    local old = active
    local oldIndex, nextIndex = table.find(normal, old), table.find(normal, id)
    local direction = oldIndex and nextIndex and (nextIndex < oldIndex and -1 or 1) or (oldIndex and 1 or -1)
    if oldIndex and not nextIndex then
      returnId = old
    end
    local outgoing = old and registry[old].Root
    for _, page in pairs(registry) do
      if page.Root ~= outgoing and page.Root ~= registry[id].Root then
        page.Root.Visible = false
      end
    end
    active = id
    if not outgoing or animated == false or outgoing == registry[id].Root then
      settle()
      notify()
      return
    end
    transitioning = true
    shield.Visible = true
    notify()
    local revision = generation
    local incoming = registry[active].Root
    if not incoming.Visible then
      incoming.Position = UDim2.fromOffset(origin.X.Offset + T.PAGE_OFFSET * direction, origin.Y.Offset + 8)
      incoming.GroupTransparency = 1
    end
    incoming.Visible = true
    local exit = motion.play(outgoing, "page", {
      GroupTransparency = 1,
      Position = UDim2.fromOffset(origin.X.Offset - T.PAGE_OFFSET * direction, origin.Y.Offset - 8),
    })
    if exit then
      tweens[#tweens + 1] = exit
    end
    local enter = motion.play(incoming, "page", { GroupTransparency = 0, Position = origin }, function()
      if alive and revision == generation then
        tweens = {}
        settle()
        notify()
      end
    end)
    if enter then
      tweens[#tweens + 1] = enter
    end
    task.delay(0.8, function()
      if alive and revision == generation and transitioning then
        cancel()
        settle()
        notify()
      end
    end)
  end
  function controller.step(direction)
    local index = table.find(normal, active)
    if index then
      controller.select(normal[math.clamp(index + direction, 1, #normal)])
    end
  end
  function controller.toggle(id)
    if active == id then
      controller.select(returnId or normal[1])
    else
      controller.select(id)
    end
  end
  local function disclosureHeight(owner)
    local layout = owner.childContent:FindFirstChildOfClass("UIListLayout")
    local height, count = 0, 0
    for _, entry in ipairs(rows) do
      if entry.Root.Parent == owner.childContent and entry.Root.Visible then
        local rowHeight = entry.handle.Root.Visible and entry.handle.Root.Size.Y.Offset or 0
        local nested = entry.children and context.read(entry.definition.key) == true and disclosureHeight(entry) or 0
        if nested > 0 then
          if rowHeight > 0 then
            rowHeight += T.CARD_GAP - bleed
          end
          rowHeight += nested
        end
        if rowHeight > 0 then
          if count > 0 then
            height += layout.Padding.Offset
          end
          height += rowHeight + bleed * (nested > 0 and 1 or 2)
          count += 1
        end
      end
    end
    return height
  end
  refreshDisclosure = function(key, owner, immediate)
    local expanded = context.read and context.read(key) == true or false
    local height = expanded and disclosureHeight(owner) or 0
    local padding = owner.Root:FindFirstChildOfClass("UIPadding")
    padding.PaddingBottom = UDim.new(0, expanded and 0 or bleed)
    if not immediate and owner.expanded == expanded and owner.targetHeight == height then
      return
    end
    owner.expanded, owner.targetHeight = expanded, height
    owner.revision = (owner.revision or 0) + 1
    local revision = owner.revision
    if owner.disclosureTween then
      motion.cancel(owner.disclosureTween)
      owner.disclosureTween = nil
    end
    if owner.disclosureSlide then
      motion.cancel(owner.disclosureSlide)
      owner.disclosureSlide = nil
    end
    if immediate then
      owner.children.Size = UDim2.new(1, -12, 0, height)
      owner.children.Visible = expanded
      owner.childContent.Position = UDim2.fromOffset(0, 0)
      return
    end
    if expanded then
      if not owner.children.Visible then
        owner.childContent.Position = UDim2.fromOffset(0, -14)
      end
      owner.children.Visible = true
    end
    owner.disclosureSlide = motion.play(owner.childContent, "control", { Position = UDim2.fromOffset(0, expanded and 0 or -14) })
    local function finish()
      if not alive or revision ~= owner.revision then
        return
      end
      owner.children.Size = UDim2.new(1, -12, 0, height)
      owner.children.Visible = expanded
      owner.disclosureTween, owner.disclosureSlide = nil, nil
    end
    owner.disclosureTween = motion.play(owner.children, "control", { Size = UDim2.new(1, -12, 0, height) }, finish)
    if not owner.disclosureTween then
      finish()
    else
      task.delay(0.8, function()
        if alive and revision == owner.revision and owner.disclosureTween then
          motion.cancel(owner.disclosureTween)
          finish()
        end
      end)
    end
  end
  function controller.refresh()
    for _, entry in ipairs(rows) do
      local definition = entry.definition
      local visible = entry.available ~= false and (not definition.abilityOnly or not context.abilitiesEnabled or context.abilitiesEnabled())
      if definition.visibleWhen and context.read then
        visible = visible and context.read(definition.visibleWhen) == true
      end
      if entry.shown ~= visible then
        entry.shown = visible
        entry.visibilityRevision = (entry.visibilityRevision or 0) + 1
        local revision = entry.visibilityRevision
        if visible then
          entry.Root.Visible = true
        end
        motion.fade(entry.Root, "control", visible and 0 or 1, function()
          if alive and revision == entry.visibilityRevision then
            entry.Root.Visible = visible
          end
        end)
      end
    end
    for root, entries in pairs(sections) do
      local visible = false
      for _, entry in ipairs(entries) do
        visible = visible or entry.shown
      end
      root.Visible = visible
    end
    for _, page in pairs(registry) do
      local occupied = {}
      for _, entry in ipairs(page.rows) do
        if entry.shown and not entry.parentKey then
          local column = entry.Root.Parent and entry.Root.Parent.Parent
          occupied[column] = true
        end
      end
      local columnWidth = page.definition.columns == 1 and math.min(width, T.SINGLE_COLUMN_W) or (width - T.GAP) / 2
      for index, column in ipairs(page.columns) do
        column.Visible = occupied[column] == true
        column.Position = UDim2.fromOffset(page.definition.columns == 1 and (width - columnWidth) / 2 or (index - 1) * (columnWidth + T.GAP), 0)
      end
      for key, owner in pairs(page.keyed) do
        if owner.children then
          refreshDisclosure(key, owner, owner.expanded == nil)
        end
      end
    end
  end
  function controller.get(id) return registry[id] end
  function controller.getControl(key) return bindings[key] end
  function controller.getReadout(key) return readouts[key] end
  function controller.setReadout(key, value)
    local entry = assert(readoutRows[key], "Missing information component: " .. tostring(key))
    entry.available = type(value) == "string" and value:match("%S") ~= nil
    if entry.available then
      entry.handle.setValue(value)
    end
  end
  function controller.snapshot()
    local snapshot = { page = active, returnId = returnId, scroll = {} }
    for id, page in pairs(registry) do
      snapshot.scroll[id] = {}
      for index, column in ipairs(page.columns) do
        snapshot.scroll[id][index] = column.CanvasPosition
      end
    end
    return snapshot
  end
  function controller.restore(snapshot)
    if not snapshot then
      return
    end
    if snapshot.page and registry[snapshot.page] then
      controller.select(snapshot.page, false)
    end
    if snapshot.returnId and registry[snapshot.returnId] then
      returnId = snapshot.returnId
    end
    for id, columns in pairs(snapshot.scroll or {}) do
      if registry[id] then
        for index, position in ipairs(columns) do
          if registry[id].columns[index] and typeof(position) == "Vector2" then
            registry[id].columns[index].CanvasPosition = position
          end
        end
      end
    end
  end
  function controller.suspend()
    cancel()
    settle()
    for _, page in pairs(registry) do
      for key, owner in pairs(page.keyed) do
        if owner.children then
          refreshDisclosure(key, owner, true)
        end
      end
    end
  end
  function controller.destroy()
    if not alive then
      return
    end
    alive = false
    cancel()
    lifetime.destroy()
    kit.scope.remove(controller.destroy)
    for _, page in pairs(registry) do
      for _, entry in ipairs(page.rows) do
        entry.handle.destroy()
      end
      page.Root:Destroy()
    end
    shield:Destroy()
  end
  lifetime.add(kit.observe(controller.refresh))
  kit.scope.add(controller.destroy)
  controller.select(context.initialPage or normal[1], false)
  controller.refresh()
  return controller
end

-- contract
Pages.__contract = { provides = { "setup", "validate", "create", "forGame" }, requires = {} }

return Pages
