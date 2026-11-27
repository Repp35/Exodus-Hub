-- [[ mm2 visuals ]]
--!optimize 2

-- module
local Visuals = {}
function Visuals.setup() return true end

-- instance
function Visuals.create(deps)
  local services, player, runtime = deps.services, deps.player, deps.runtime
  local esp = {
    Enabled = false,
    ShowIdentity = true,
    ShowUsername = true,
    ShowSelf = true,
    ShowDistance = true,
    Filters = { Murderer = true, Sheriff = true, Innocent = true, Player = true, Self = true, CandyCoin = false, Gun = true },
    Colors = {
      Murderer = Color3.fromRGB(255, 65, 65),
      Sheriff = Color3.fromRGB(70, 155, 255),
      Innocent = Color3.fromRGB(70, 220, 120),
      Player = Color3.fromRGB(235, 235, 235),
      Self = Color3.fromRGB(235, 235, 235),
      CandyCoin = Color3.fromRGB(255, 185, 70),
      Gun = Color3.fromRGB(70, 225, 255),
    },
  }
  local markers, thread, render, host, generation = {}, nil, nil, nil, 0
  local roleLabels = { Murderer = "Assassino", Sheriff = "Xerife", Hero = "Herói", Innocent = "Inocente" }

  -- markers
  local function remove(key)
    local marker = markers[key]
    if not marker then
      return
    end
    deps.util.DestroySafely(marker.gui)
    deps.util.DestroySafely(marker.highlight)
    markers[key] = nil
  end
  local function partFor(object)
    if object:IsA("BasePart") then
      return object
    end
    return object:FindFirstChildWhichIsA("BasePart", true)
  end
  local function markerFor(key, object, part, category, colorCategory, identity, username, own)
    local marker = markers[key]
    if marker and (marker.object ~= object or marker.part ~= part or not marker.gui.Parent or not marker.highlight.Parent) then
      remove(key)
      marker = nil
    end
    if not marker then
      local highlight = Instance.new("Highlight")
      highlight.Name = "ExodusMM2Highlight"
      highlight.Adornee = object
      highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
      highlight.FillTransparency = 0.82
      highlight.OutlineTransparency = 0
      highlight.Parent = host
      local gui = Instance.new("BillboardGui")
      gui.Name = "ExodusMM2Label"
      gui.Adornee = part
      gui.AlwaysOnTop = true
      gui.LightInfluence = 0
      gui.Size = UDim2.fromOffset(260, 64)
      gui.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 1.2, 0)
      gui.Parent = host
      local label = Instance.new("TextLabel")
      label.BackgroundTransparency = 1
      label.Size = UDim2.fromScale(1, 1)
      label.Font = Enum.Font.GothamBold
      label.TextSize = 13
      label.TextStrokeTransparency = 0
      label.TextStrokeColor3 = Color3.new(0, 0, 0)
      label.Parent = gui
      marker = { object = object, part = part, gui = gui, label = label, highlight = highlight }
      markers[key] = marker
    end
    marker.category, marker.identity, marker.username, marker.own = category, identity, username, own
    local color = esp.Colors[colorCategory or category]
    marker.highlight.FillColor = color
    marker.highlight.OutlineColor = color
    marker.label.TextColor3 = color
    return marker
  end
  local function labels()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    for key, marker in pairs(markers) do
      if not marker.part.Parent then
        remove(key)
        continue
      end
      local lines = {}
      if esp.ShowIdentity and marker.identity then
        table.insert(lines, marker.identity)
      end
      if esp.ShowUsername and marker.username then
        table.insert(lines, marker.username)
      end
      if esp.ShowDistance and root and not marker.own then
        local distance = (root.Position - marker.part.Position).Magnitude
        table.insert(lines, tostring(math.floor(distance * 0.28 + 0.5)) .. " m")
        marker.label.TextSize = math.floor(12 + math.clamp((distance - 24) / 216, 0, 1) * 5)
      end
      marker.label.Text = table.concat(lines, "\n")
      marker.gui.Enabled = #lines > 0
    end
  end

  -- refresh
  function esp:Refresh()
    if not self.Enabled or runtime.ShuttingDown then
      return
    end
    local serial = generation
    local active, map, container = deps.match:GetRoundContext()
    local data = active and deps.match:GetPlayerData() or nil
    if not self.Enabled or runtime.ShuttingDown or serial ~= generation then
      return
    end
    if not host then
      host = Instance.new("Folder")
      host.Name = "ExodusMM2ESP"
      host.Parent = deps.util.GetHost()
    end
    local keep = {}
    for _, target in ipairs(services.Players:GetPlayers()) do
      local own = target == player
      if own and not self.ShowSelf then
        continue
      end
      local character = target.Character
      local humanoid = character and character:FindFirstChildOfClass("Humanoid")
      local root = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not character:IsDescendantOf(services.Workspace) or not humanoid or humanoid.Health <= 0 or not root then
        continue
      end
      local profile = data and data[target.Name]
      local live = active and target:GetAttribute("Alive") == true and type(profile) == "table" and profile.Dead ~= true and profile.Killed ~= true
      local role = live and profile.Role or nil
      local category = role == "Hero" and "Sheriff" or roleLabels[role] and role or "Player"
      local filter = own and "Self" or category
      if self.Filters[filter] then
        keep[target] = true
        local identity = roleLabels[role] or "Sem papel"
        if own then
          identity = "Você · " .. identity
        end
        markerFor(target, character, character:FindFirstChild("Head") or root, filter, category, identity, target.Name, own)
      end
    end
    if active and self.Filters.CandyCoin and container then
      for _, coin in ipairs(deps.coin:GetCollectableParts(container)) do
        local visual = coin:FindFirstChild("CoinVisual")
        local object = visual and (visual:IsA("Model") or visual:IsA("BasePart")) and visual or coin
        keep[coin] = true
        markerFor(coin, object, partFor(object) or coin, "CandyCoin", nil, deps.coin:GetKind(coin) == "candy" and "Candy" or "Coin")
      end
    end
    if active and self.Filters.Gun then
      for _, gun in ipairs(services.CollectionService:GetTagged("GunDrop")) do
        local part = gun.Parent and gun:IsDescendantOf(map) and partFor(gun)
        if part then
          keep[gun] = true
          markerFor(gun, (gun:IsA("Model") or gun:IsA("BasePart")) and gun or part, part, "Gun", nil, "Arma")
        end
      end
    end
    for key in pairs(markers) do
      if not keep[key] then
        remove(key)
      end
    end
    labels()
  end

  -- controls
  function esp:SetFilter(category, enabled)
    if self.Filters[category] ~= nil then
      self.Filters[category] = enabled == true
    end
  end
  function esp:SetShowSelf(enabled)
    self.ShowSelf = enabled == true
    self.Filters.Self = self.ShowSelf
  end
  function esp:Start()
    if self.Enabled or runtime.ShuttingDown then
      return
    end
    self.Enabled = true
    generation += 1
    local serial = generation
    local lastFrame, lastError = 0, -math.huge
    render = services.RunService.PreRender:Connect(function()
      if not self.Enabled or os.clock() - lastFrame < 0.05 then
        return
      end
      lastFrame = os.clock()
      labels()
    end)
    thread = task.defer(function()
      while self.Enabled and generation == serial and not runtime.ShuttingDown do
        local ok, reason = pcall(self.Refresh, self)
        if not ok and os.clock() - lastError >= 5 then
          lastError = os.clock()
          warn("[Exodus MM2] ESP: " .. tostring(reason))
        end
        task.wait(0.5)
      end
    end)
  end
  function esp:Stop()
    self.Enabled = false
    generation += 1
    if render then
      render:Disconnect()
      render = nil
    end
    if thread then
      pcall(task.cancel, thread)
      thread = nil
    end
    for key in pairs(markers) do
      remove(key)
    end
    deps.util.DestroySafely(host)
    host = nil
  end
  runtime:OnShutdown(function() esp:Stop() end)
  return esp
end

-- contract
Visuals.__contract = { provides = { "setup", "create" }, requires = {} }
return Visuals
