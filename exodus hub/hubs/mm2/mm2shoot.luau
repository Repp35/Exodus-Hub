--!optimize 2
-- @modules mm2shoot
-- [[ shootmurder ]]

-- code

local function create(API)
  local Players = API.Roblox.Players
  local Services = API.Roblox
  local Workspace = API.Roblox.Workspace
  local Player = API.Player
  local Runtime = API.Runtime
  local MatchService = API.Services.Match
  local Randomizer = Random.new()
  local ShootMurder = {
    ManualEnabled = false,
    AutoEnabled = false,
    ManualAccuracy = 100,
    AutoAccuracy = 100,
    WaitForKnife = false,
    RoleData = nil,
    RoleDataAt = 0,
    NextRoleRefreshAt = 0,
    Destroyed = false,
  }

  local function getAliveCharacter(target, profile)
    if type(profile) ~= "table" or profile.Dead == true or profile.Killed == true or not target or target:GetAttribute("Alive") == false then
      return nil
    end
    local character = target.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not character:IsDescendantOf(Workspace) or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
      return nil
    end
    return character, humanoid, root
  end
  function ShootMurder:RefreshRoleData()
    self.RoleData = MatchService:GetPlayerData()
    self.RoleDataAt = os.clock()
    return self.RoleData
  end
  function ShootMurder:HasSheriffRole()
    local profile = self.RoleData and self.RoleData[Player.Name]
    return type(profile) == "table" and (profile.Role == "Sheriff" or profile.Role == "Hero") and profile.Dead ~= true and profile.Killed ~= true
  end
  function ShootMurder:IsLocalMurderer()
    local profile = self.RoleData and self.RoleData[Player.Name]
    return type(profile) == "table" and profile.Role == "Murderer"
  end
  function ShootMurder:GetLocalContext()
    local inRound = MatchService:GetRoundContext()
    if not inRound or Player:GetAttribute("Alive") == false then
      return nil
    end
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local profile = self.RoleData and self.RoleData[Player.Name]
    local roleCanShoot = type(profile) == "table" and (profile.Role == "Sheriff" or profile.Role == "Hero")
    local backpack = Player:FindFirstChildOfClass("Backpack")
    local hasGun = character and character:FindFirstChild("Gun") ~= nil or backpack and backpack:FindFirstChild("Gun") ~= nil
    if
      (not roleCanShoot and not hasGun)
      or type(profile) == "table" and (profile.Dead == true or profile.Killed == true)
      or not character
      or not humanoid
      or humanoid.Health <= 0
      or not root
      or not root:IsA("BasePart")
      or not character:IsDescendantOf(Workspace)
    then
      return nil
    end
    return character, humanoid, root
  end
  function ShootMurder:GetMurderer()
    if not self.RoleData then
      return nil
    end
    for _, target in ipairs(Players:GetPlayers()) do
      local profile = self.RoleData[target.Name]
      if target ~= Player and type(profile) == "table" and profile.Role == "Murderer" then
        local character, humanoid, root = getAliveCharacter(target, profile)
        if character then
          return target, character, humanoid, root
        end
      end
    end
    return nil
  end
  function ShootMurder:FindGun(character, humanoid)
    local gun = character:FindFirstChild("Gun")
    if gun and gun:IsA("Tool") then
      return gun
    end
    local backpack = Player:FindFirstChildOfClass("Backpack")
    gun = backpack and backpack:FindFirstChild("Gun")
    if gun then
      pcall(function() humanoid:EquipTool(gun) end)
      if gun.Parent == character then
        return gun
      end
    end
    return nil
  end
  function ShootMurder:GetShotOrigin(localCharacter, gun, root)
    local attachment = root:FindFirstChild("GunRaycastAttachment")
      or gun:FindFirstChild("GunRaycastAttachment", true)
      or localCharacter:FindFirstChild("GunRaycastAttachment", true)
    if attachment and attachment:IsA("Attachment") then
      return attachment.WorldCFrame
    end
    local handle = gun:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
      return handle.CFrame
    end
    return root.CFrame * CFrame.new(0, 1.2, 0)
  end
  function ShootMurder:GetClearAim(character, root, gun, localCharacter, shotOrigin)
    local _, _, coinContainer = MatchService:GetRoundContext()
    local ignored = { localCharacter, gun }
    if coinContainer then
      table.insert(ignored, coinContainer)
    end
    for _, instance in ipairs(Services.CollectionService:GetTagged("WeaponPassthrough")) do
      table.insert(ignored, instance)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local origin = shotOrigin.Position
    local points = {}
    for _, name in ipairs({ "UpperTorso", "Torso", "Head", "LowerTorso", "HumanoidRootPart" }) do
      local part = character:FindFirstChild(name)
      if part and part:IsA("BasePart") then
        table.insert(points, part.Position)
      end
    end
    for _, part in ipairs(character:GetChildren()) do
      if part:IsA("BasePart") and part.CanQuery then
        table.insert(points, part.Position)
      end
    end
    for _, point in ipairs(points) do
      local direction = point - origin
      if direction.Magnitude > 0.05 then
        local rayIgnored = table.clone(ignored)
        for _ = 1, 32 do
          params.FilterDescendantsInstances = rayIgnored
          local hit = Workspace:Raycast(origin, direction, params)
          if not hit or hit.Instance:IsDescendantOf(character) then
            return point
          end
          if not hit.Instance:IsA("BasePart") or hit.Instance.Transparency ~= 1 then
            break
          end
          table.insert(rayIgnored, hit.Instance)
        end
      end
    end
    return nil
  end
  function ShootMurder:GetShotPoint(hitPosition, accuracy)
    accuracy = math.clamp(tonumber(accuracy) or 100, 0, 100)
    local inaccuracy = (100 - accuracy) / 100
    if inaccuracy <= 0 then
      return hitPosition
    end
    local likelyMiss = Randomizer:NextNumber() < inaccuracy * 0.45
    local radius = likelyMiss and (2 + inaccuracy * 6) or (inaccuracy * 0.65)
    local direction = Vector3.new(Randomizer:NextNumber(-1, 1), Randomizer:NextNumber(-1, 1), Randomizer:NextNumber(-1, 1))
    if direction.Magnitude <= 0.001 then
      direction = Vector3.xAxis
    end
    return hitPosition + direction.Unit * radius
  end
  function ShootMurder:TryShoot(automatic)
    if self.Destroyed or Runtime.ShuttingDown or not API.IsActive() then
      return false
    end
    if os.clock() < (self.NextShotAt or 0) then
      return false
    end
    if not automatic then
      self:RefreshRoleData(true)
    end
    if not self:HasSheriffRole() then
      return false
    end
    local localCharacter, humanoid, localRoot = self:GetLocalContext()
    if not localCharacter then
      return false
    end
    local target, targetCharacter, _, targetRoot = self:GetMurderer()
    if not target then
      return false
    end
    if self.WaitForKnife and not targetCharacter:FindFirstChild("Knife") then
      return false
    end
    local gun = self:FindGun(localCharacter, humanoid)
    if not gun or gun.Parent ~= localCharacter or gun:GetAttribute("Disabled") == true then
      return false
    end
    local shootRemote = gun:FindFirstChild("Shoot")
    if not shootRemote or not shootRemote:IsA("RemoteEvent") then
      return false
    end
    local shotOrigin = self:GetShotOrigin(localCharacter, gun, localRoot)
    local hitPosition = self:GetClearAim(targetCharacter, targetRoot, gun, localCharacter, shotOrigin)
    if not hitPosition then
      return false
    end
    local shotPoint = self:GetShotPoint(hitPosition, automatic and self.AutoAccuracy or self.ManualAccuracy)
    local ok = pcall(function() shootRemote:FireServer(shotOrigin, CFrame.new(shotPoint)) end)
    if not ok then
      return false
    end
    self.NextShotAt = os.clock() + math.clamp(tonumber(gun:GetAttribute("FireCooldown")) or 0.3, 0.1, 5)
    return true
  end
  function ShootMurder:Update()
    if self.Destroyed then
      return
    end
    if not self.ManualEnabled and not self.AutoEnabled then
      self.RoleData = nil
      self.RoleDataAt = 0
      self.NextRoleRefreshAt = 0
      return
    end
    local inRound = MatchService:GetRoundContext()
    if not inRound then
      self.RoleData = nil
      self.RoleDataAt = 0
      self.NextRoleRefreshAt = 0
      return
    end
    self:RefreshRoleData(false)
    local localCharacter = self:GetLocalContext()
    local canShoot = localCharacter ~= nil and self:HasSheriffRole()
    if self.AutoEnabled and canShoot then
      self:TryShoot(true)
    end
  end
  function ShootMurder:SetManualEnabled(enabled) self.ManualEnabled = enabled == true end
  function ShootMurder:SetAutoEnabled(enabled) self.AutoEnabled = enabled == true end
  function ShootMurder:SetWaitForKnife(enabled) self.WaitForKnife = enabled == true end
  function ShootMurder:SetManualAccuracy(value) self.ManualAccuracy = math.clamp(tonumber(value) or 100, 0, 100) end
  function ShootMurder:SetAutoAccuracy(value) self.AutoAccuracy = math.clamp(tonumber(value) or 100, 0, 100) end
  function ShootMurder:Destroy()
    self.Destroyed, self.ManualEnabled, self.AutoEnabled = true, false, false
  end
  Runtime:Track(Services.RunService.Heartbeat:Connect(function()
    if ShootMurder.Destroyed or not API.IsActive() or os.clock() < (ShootMurder.NextUpdateAt or 0) then
      return
    end
    ShootMurder.NextUpdateAt = os.clock() + 0.05
    local ok, errorMessage = pcall(function() ShootMurder:Update() end)
    if not ok then
      warn("[Exodus MM2] Shoot Murder: " .. tostring(errorMessage))
    end
  end))
  Runtime:OnShutdown(function() ShootMurder:Destroy() end)
  return ShootMurder
end
local Module = { create = create }
function Module.setup() return true end
Module.__contract = { provides = { "setup", "create" }, requires = {} }
return Module
