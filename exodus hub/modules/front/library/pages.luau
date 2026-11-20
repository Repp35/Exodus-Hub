-- [[ uipages ]]

-- module
local Pages = {}

-- configuration
local CONFIG = { COLUMNS = { [1] = true, [2] = true } }

-- setup
function Pages.setup() return true end

-- validation
function Pages.validate(definitions, components)
  assert(type(definitions) == "table" and #definitions > 0, "UI pages must be a non-empty ordered list"); local ids, normal = {}, 0
  for _, page in ipairs(definitions) do
    assert(type(page.id) == "string" and page.id ~= "" and not ids[page.id], "UI page id must be unique")
    assert(type(page.title) == "string" and type(page.sections) == "table", "UI page requires title and sections: " .. page.id)
    assert(CONFIG.COLUMNS[page.columns], "UI page columns must be 1 or 2: " .. page.id); ids[page.id] = true
    if not page.utility then normal += 1 end
    local keys, parents = {}, {}
    for _, section in ipairs(page.sections) do
      assert((section.column or 1) >= 1 and (section.column or 1) <= page.columns, "Invalid column in " .. page.id)
      for _, definition in ipairs(section.components or {}) do
        assert(type(components[definition.kind]) == "function", "Unknown UI component: " .. tostring(definition.kind) .. " in " .. page.id)
        if definition.key then assert(not keys[definition.key], "Duplicate UI key in " .. page.id .. ": " .. definition.key); keys[definition.key] = true end
        if definition.parentKey then parents[definition.key or definition] = definition.parentKey end
      end
    end
    for key, parent in pairs(parents) do
      local visited = { [key] = true }
      while parent do
        assert(keys[parent] and not visited[parent], "Missing or cyclic parentKey in " .. page.id); visited[parent] = true
        parent = parents[parent]
      end
    end
  end
  assert(normal > 0, "UI needs at least one primary page"); return true
end

-- rendering
function Pages.create(kit, parent, definitions, context)
  context = context or {}; context.read = context.read or kit.read
  Pages.validate(definitions, kit.Components); local T, inst = kit.Theme, kit.instance
  local width = T.PANEL_W - T.PAD * 2; local height = T.PANEL_H - T.TITLE_H - 60
  local origin = UDim2.fromOffset(T.PAD, T.TITLE_H + T.PAD); local registry, normal, rows, bindings = {}, {}, {}, {}
  local active, returnId, generation = nil, nil, 0; local tweens, transitioning = {}, false
  local alive = true; local controller = {}
  local lifetime = kit.scope.child(); local motion = kit.createMotion(lifetime)
  local refreshDisclosure
  local function list(parent, gap)
    return inst(
      "UIListLayout",
      { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or T.CARD_GAP), HorizontalAlignment = Enum.HorizontalAlignment.Center },
      parent
    )
  end
  local function stack(parent, name)
    local root =
      inst("Frame", { Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 6 }, parent)
    list(root); return root
  end
  local function included(definition)
    if definition.requiresCapability and not (context.capabilities and context.capabilities[definition.requiresCapability]) then return false end
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
    local page = { Root = root, definition = definition, columns = {}, rows = {} }; registry[definition.id] = page
    if not definition.utility then normal[#normal + 1] = definition.id end
    local pageWidth = definition.width or width; local columnWidth = (pageWidth - T.GAP * (definition.columns - 1)) / definition.columns
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
      list(scroll); page.columns[column] = scroll
    end
    local keyed, pending = {}, {}
    for sectionIndex, section in ipairs(definition.sections) do
      if included(section) then
        local sectionRoot = stack(page.columns[section.column or 1], "Section" .. sectionIndex); sectionRoot.LayoutOrder = sectionIndex
        if section.title then local label = kit.Components.label(sectionRoot, { text = section.title }); label.Root.LayoutOrder = 0 end
        for index, source in ipairs(section.components or {}) do
          if included(source) then
            local options = table.clone(source)
            if context.resolve then options = context.resolve(options) or options end
            local row = stack(sectionRoot, "Row_" .. tostring(source.key or source.action or index)); row.LayoutOrder = index
            local handle = kit.Components[options.kind](row, options); handle.Root.LayoutOrder = 0
            local entry = { Root = row, handle = handle, definition = source, parentKey = source.parentKey }; rows[#rows + 1] = entry
            page.rows[#page.rows + 1] = entry
            if source.key then keyed[source.key] = entry; bindings[source.key] = handle end
            if source.parentKey then pending[#pending + 1] = entry end
            if context.onComponent then context.onComponent(source, handle) end
          end
        end
      end
    end
    for _, entry in ipairs(pending) do
      local owner = keyed[entry.parentKey]; assert(owner, "Visible child requires a visible parent: " .. entry.parentKey)
      if not owner.children then
        owner.children = inst("Frame", {
          Name = "Children",
          Size = UDim2.new(1, -12, 0, 0),
          BackgroundTransparency = 1,
          Visible = false,
          ClipsDescendants = false,
          LayoutOrder = 1,
          ZIndex = 6,
        }, owner.Root)
        owner.childContent = stack(owner.children, "Content"); local layout = owner.childContent:FindFirstChildOfClass("UIListLayout")
        lifetime.connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
          if refreshDisclosure then refreshDisclosure(entry.parentKey, owner) end
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
      page.Root.Visible = id == active; page.Root.Position = origin
      page.Root.GroupTransparency = id == active and 0 or 1
    end
    transitioning = false; shield.Visible = false
  end
  local function notify()
    if context.onNavigate then context.onNavigate(controller.state()) end
  end
  function controller.state()
    local index = table.find(normal, active); return { id = active, title = registry[active].definition.title, index = index, count = #normal, utility = index == nil, transitioning = transitioning }
  end
  function controller.select(id, animated)
    assert(registry[id], "Unknown UI page: " .. tostring(id))
    if not alive or kit.suspended or (id == active and animated ~= false) then return end
    kit.dismiss(); cancel()
    local old = active; local oldIndex, nextIndex = table.find(normal, old), table.find(normal, id)
    local direction = oldIndex and nextIndex and (nextIndex < oldIndex and -1 or 1) or (oldIndex and 1 or -1)
    if oldIndex and not nextIndex then returnId = old end
    local outgoing
    for _, page in pairs(registry) do
      if page.Root.Visible then
        if not outgoing then outgoing = page.Root else page.Root.Visible = false end
      end
    end
    active = id
    if not outgoing or animated == false or outgoing == registry[id].Root then
      settle(); notify()
      return
    end
    transitioning = true; shield.Visible = true
    notify(); local revision = generation
    local function reveal()
      if not alive or revision ~= generation then return end
      for _, page in pairs(registry) do
        page.Root.Visible = false; page.Root.GroupTransparency = 1
        page.Root.Position = origin
      end
      local incoming = registry[active].Root; incoming.Position = UDim2.fromOffset(origin.X.Offset + T.PAGE_OFFSET * direction, origin.Y.Offset)
      incoming.Visible = true
      local tween = motion.play(incoming, "page", { GroupTransparency = 0, Position = origin }, function()
        if alive and revision == generation then
          tweens = {}; settle()
          notify()
        end
      end)
      if tween then tweens[#tweens + 1] = tween end
    end
    local tween = motion.play(
      outgoing,
      "page",
      { GroupTransparency = 1, Position = UDim2.fromOffset(origin.X.Offset - T.PAGE_OFFSET * direction, origin.Y.Offset) },
      reveal
    )
    if tween then tweens[#tweens + 1] = tween end
    task.delay(0.8, function()
      if alive and revision == generation and transitioning then
        cancel(); settle()
        notify()
      end
    end)
  end
  function controller.step(direction)
    local index = table.find(normal, active)
    if index then controller.select(normal[math.clamp(index + direction, 1, #normal)]) end
  end
  function controller.toggle(id)
    if active == id then controller.select(returnId or normal[1]) else controller.select(id) end
  end
  local function fadeDisclosure(owner, expanded, entering)
    local bases = owner.fadeBases or {}; owner.fadeBases = bases
    owner.fadeTweens = owner.fadeTweens or {}
    for _, tween in ipairs(owner.fadeTweens) do
      motion.cancel(tween)
    end
    owner.fadeTweens = {}
    for _, item in ipairs(owner.childContent:GetDescendants()) do
      local properties = {}
      if item:IsA("GuiObject") then properties[#properties + 1] = "BackgroundTransparency" end
      if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then properties[#properties + 1] = "TextTransparency"; properties[#properties + 1] = "TextStrokeTransparency" end
      if item:IsA("ImageLabel") or item:IsA("ImageButton") then properties[#properties + 1] = "ImageTransparency" end
      if item:IsA("UIStroke") then properties[#properties + 1] = "Transparency" end
      if #properties > 0 then
        local values = bases[item] or {}; bases[item] = values
        local goals = {}
        for _, property in ipairs(properties) do
          if values[property] == nil then values[property] = item[property] end
          if entering then item[property] = 1 end
          goals[property] = expanded and values[property] or 1
        end
        local tween = motion.play(item, "control", goals)
        if tween then owner.fadeTweens[#owner.fadeTweens + 1] = tween end
      end
    end
  end
  refreshDisclosure = function(key, owner, immediate)
    local expanded = context.read and context.read(key) == true or false; local layout = owner.childContent:FindFirstChildOfClass("UIListLayout")
    local height, count = 0, 0
    if expanded then
      for _, entry in ipairs(rows) do
        if entry.Root.Parent == owner.childContent and entry.Root.Visible then
          local rowHeight = entry.handle.Root.Visible and entry.handle.Root.Size.Y.Offset or 0
          if entry.children and entry.children.Visible and entry.children.Size.Y.Offset > 0 then
            if rowHeight > 0 then rowHeight += T.CARD_GAP end
            rowHeight += entry.children.Size.Y.Offset
          end
          if rowHeight > 0 then
            if count > 0 then height += layout.Padding.Offset end
            height += rowHeight; count += 1
          end
        end
      end
    end
    if not immediate and owner.expanded == expanded and owner.targetHeight == height then return end
    local entering = expanded and not owner.children.Visible; owner.expanded, owner.targetHeight = expanded, height
    owner.revision = (owner.revision or 0) + 1; local revision = owner.revision
    if owner.disclosureTween then motion.cancel(owner.disclosureTween); owner.disclosureTween = nil end
    if owner.disclosureSlide then motion.cancel(owner.disclosureSlide); owner.disclosureSlide = nil end
    if immediate then
      owner.children.Size = UDim2.new(1, -12, 0, height); owner.children.Visible = expanded
      owner.childContent.Position = UDim2.fromOffset(0, 0); return
    end
    if expanded then
      if not owner.children.Visible then owner.childContent.Position = UDim2.fromOffset(0, -6) end
      owner.children.Visible = true
    end
    local faded = pcall(fadeDisclosure, owner, expanded, entering)
    if not faded and owner.fadeBases then
      for _, tween in ipairs(owner.fadeTweens or {}) do
        motion.cancel(tween)
      end
      for item, values in pairs(owner.fadeBases) do
        if item.Parent then
          for property, value in pairs(values) do
            item[property] = value
          end
        end
      end
      owner.fadeBases, owner.fadeTweens = nil, nil
    end
    owner.disclosureSlide = motion.play(owner.childContent, "control", { Position = UDim2.fromOffset(0, expanded and 0 or -6) })
    local function finish()
      if not alive or revision ~= owner.revision then return end
      owner.children.Size = UDim2.new(1, -12, 0, height); owner.children.Visible = expanded
      if owner.fadeBases then
        for _, tween in ipairs(owner.fadeTweens or {}) do
          motion.cancel(tween)
        end
        for item, values in pairs(owner.fadeBases) do
          if item.Parent then
            for property, value in pairs(values) do
              item[property] = value
            end
          end
        end
      end
      owner.fadeBases, owner.fadeTweens = nil, nil; owner.disclosureTween, owner.disclosureSlide = nil, nil
    end
    owner.disclosureTween = motion.play(owner.children, "control", { Size = UDim2.new(1, -12, 0, height) }, finish)
    if not owner.disclosureTween then
      finish()
    else
      task.delay(0.8, function()
        if alive and revision == owner.revision and owner.disclosureTween then motion.cancel(owner.disclosureTween); finish() end
      end)
    end
  end
  function controller.refresh()
    for _, entry in ipairs(rows) do
      local definition = entry.definition; local visible = not definition.abilityOnly or not context.abilitiesEnabled or context.abilitiesEnabled()
      if definition.visibleWhen and context.read then visible = visible and context.read(definition.visibleWhen) == true end
      entry.Root.Visible = visible
    end
    for _, page in pairs(registry) do
      for key, owner in pairs(page.keyed) do
        if owner.children then refreshDisclosure(key, owner, owner.expanded == nil) end
      end
    end
  end
  function controller.get(id) return registry[id] end
  function controller.getControl(key) return bindings[key] end
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
    if not snapshot then return end
    if snapshot.page and registry[snapshot.page] then controller.select(snapshot.page, false) end
    if snapshot.returnId and registry[snapshot.returnId] then returnId = snapshot.returnId end
    for id, columns in pairs(snapshot.scroll or {}) do
      if registry[id] then
        for index, position in ipairs(columns) do
          if registry[id].columns[index] and typeof(position) == "Vector2" then registry[id].columns[index].CanvasPosition = position end
        end
      end
    end
  end
  function controller.suspend()
    cancel(); settle()
    for _, page in pairs(registry) do
      for key, owner in pairs(page.keyed) do
        if owner.children then refreshDisclosure(key, owner, true) end
      end
    end
  end
  function controller.destroy()
    if not alive then return end
    alive = false; cancel()
    lifetime.destroy(); kit.scope.remove(controller.destroy)
    for _, page in pairs(registry) do
      for _, entry in ipairs(page.rows) do
        entry.handle.destroy()
      end
      page.Root:Destroy()
    end
    shield:Destroy()
  end
  lifetime.add(kit.observe(controller.refresh)); kit.scope.add(controller.destroy)
  controller.select(context.initialPage or normal[1], false); controller.refresh()
  return controller
end

-- contract
Pages.__contract = { provides = { "setup", "validate", "create" }, requires = {} }

return Pages
