-- [[ mm2 pickup ]]
--!optimize 2

-- module
local Pickup = {}
function Pickup.setup() return true end

-- instance
function Pickup.create(deps)
  local services, player, runtime, match = deps.services, deps.player, deps.runtime, deps.match
  local pickup = { Enabled = false, Busy = false, SafetyEnabled = false }
  local thread, generation, nextAttempt, lastWarning = nil, 0, 0, -math.huge

  -- inventory
  local function hasTool(character, name)
    local backpack = player:FindFirstChildOfClass("Backpack")
    return character:FindFirstChild(name) ~= nil or backpack ~= nil and backpack:FindFirstChild(name) ~= nil
  end
  local function gunPart(gun)
    if gun:IsA("BasePart") then
      return gun
    end
    return gun:FindFirstChildWhichIsA("BasePart", true)
  end

  -- safety
  local function safe(root, part, profiles)
    if not pickup.SafetyEnabled then
      return true
    end
    if type(profiles) ~= "table" then
      return false
    end
    for name, profile in pairs(profiles) do
      if type(profile) ~= "table" or profile.Role ~= "Murderer" or profile.Dead == true or profile.Killed == true then
        continue
      end
      local target = services.Players:FindFirstChild(name)
      local character = target and target.Character
      local humanoid = character and character:FindFirstChildOfClass("Humanoid")
      local threat = character and character:FindFirstChild("HumanoidRootPart")
      if not target or target:GetAttribute("Alive") ~= true or not humanoid or humanoid.Health <= 0 or not threat or not threat:IsA("BasePart") then
        continue
      end
      local params = RaycastParams.new()
      params.FilterType = Enum.RaycastFilterType.Exclude
      params.FilterDescendantsInstances = { player.Character, character }
      params.RespectCanCollide = true
      for _, point in ipairs({ root.Position, part.Position }) do
        local delta = point - threat.Position
        if delta.Magnitude < 45 then
          return false
        end
        if delta.Magnitude < 70 and not services.Workspace:Raycast(threat.Position, delta, params) then
          return false
        end
      end
    end
    return true
  end

  -- collection
  function pickup:TryPickup()
    if not self.Enabled or self.Busy or runtime.ShuttingDown or os.clock() < nextAttempt then
      return false
    end
    local serial = generation
    local ready, character, humanoid, root = match:GetContext()
    if not ready or hasTool(character, "Gun") or hasTool(character, "Knife") then
      return false
    end
    local profiles = match:GetPlayerData()
    local profile = profiles and profiles[player.Name]
    if
      not self.Enabled
      or generation ~= serial
      or runtime.ShuttingDown
      or player.Character ~= character
      or humanoid.Health <= 0
      or player:GetAttribute("Alive") ~= true
      or type(profile) ~= "table"
      or profile.Role ~= "Innocent"
      or profile.Dead == true
      or profile.Killed == true
    then
      return false
    end
    local _, map = match:GetRoundContext()
    if not map then
      return false
    end
    local nearest, distance = nil, math.huge
    for _, gun in ipairs(services.CollectionService:GetTagged("GunDrop")) do
      local part = gun.Parent and gun:IsDescendantOf(map) and gunPart(gun)
      if part then
        local gap = (root.Position - part.Position).Magnitude
        if gap < distance and safe(root, part, profiles) then
          nearest, distance = part, gap
        end
      end
    end
    local touch = getfenv().firetouchinterest
    if not nearest or type(touch) ~= "function" then
      return false
    end
    self.Busy = true
    nextAttempt = os.clock() + 0.4
    local enterOk, reason = pcall(touch, root, nearest, 0)
    local exitOk, exitReason = pcall(touch, root, nearest, 1)
    self.Busy = false
    if not enterOk or not exitOk then
      error(reason or exitReason, 0)
    end
    return true
  end

  -- lifecycle
  function pickup:SetSafetyEnabled(value) self.SafetyEnabled = value == true end
  function pickup:Start()
    if self.Enabled or runtime.ShuttingDown then
      return
    end
    self.Enabled = true
    generation += 1
    nextAttempt = 0
    local serial = generation
    thread = task.defer(function()
      while self.Enabled and generation == serial and not runtime.ShuttingDown do
        local ok, reason = pcall(self.TryPickup, self)
        if not ok and os.clock() - lastWarning >= 5 then
          lastWarning = os.clock()
          warn("[Exodus MM2] Gun pickup: " .. tostring(reason))
        end
        task.wait(0.12)
      end
    end)
  end
  function pickup:Stop()
    self.Enabled, self.Busy = false, false
    generation += 1
    if thread then
      pcall(task.cancel, thread)
      thread = nil
    end
  end
  runtime:OnShutdown(function() pickup:Stop() end)
  return pickup
end

-- contract
Pickup.__contract = { provides = { "setup", "create" }, requires = {} }
return Pickup
