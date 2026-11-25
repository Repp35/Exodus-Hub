-- [[ mcpcoordinator ]]
--!optimize 2
local Coordinator = {}
local utils, native, geometry, targeting, inventory, explosives, options, lifetime
local scope, worldScope, character, folder
local active, target, latest, projectile
local backoff = {}
local lastPearl, nextAttack, pauseUntil, lastError = -math.huge, 0, 0, -math.huge
local lastJump, lastTick = -math.huge, 0
local focused = true
local status = "Aguardando ativação"
local statusDetails = ""
local function cfg(key)
  local tuning = options.tuning[key]
  if tuning ~= nil then
    return tuning
  end
  return utils.getConfigValue(key)
end
local function cancel(reason, failed, manual)
  local job = active
  active = nil
  if not job then
    return
  end
  if job.cancel then
    pcall(job.cancel)
  end
  if job.needsEquip ~= false then
    native.restore(job.original, job.tool)
  end
  if job.point and not manual and latest and latest.character == job.character and job.view then
    local camera = latest.camera
    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + job.view.LookVector)
  end
  if failed then
    backoff[job.id] = os.clock() + 1
  end
  status = reason or "Pronto"
end
function Coordinator.reset()
  if worldScope then
    worldScope.destroy()
    worldScope = nil
  end
  cancel("Aguardando combate")
  target, latest, character, folder = nil, nil, nil, nil
  lastPearl, nextAttack, pauseUntil, lastJump = -math.huge, 0, 0, -math.huge
  backoff = {}
  targeting.reset()
  inventory.reset()
  explosives.reset()
end
local function allowed(job) return job and (not job.feature or cfg(job.feature)) and (backoff[job.id] or 0) <= os.clock() end
local function choose(a, b)
  if not allowed(a) then
    return allowed(b) and b or nil
  end
  return allowed(b) and b.priority > a.priority and b or a
end
local function valid(job, snap)
  if job.feature and not cfg(job.feature) then
    return false
  end
  if job.target and (not target or target.character ~= job.target or target.humanoid.Health <= 0) then
    return false
  end
  return not job.valid or job.valid(snap, target)
end
local function start(job, snap)
  if not allowed(job) then
    return
  end
  local capabilities = native.capabilities()
  if job.native and not capabilities[job.native] then
    status = "Rotina nativa indisponível: " .. job.native
    backoff[job.id] = snap.now + 3
    return
  end
  job.started, job.original, job.view = snap.now, snap.equipped, snap.camera.CFrame
  job.character, job.stage = snap.character, "equip"
  job.timeout = job.timeout or 0.8
  active = job
end
local function advance(snap)
  local job = active
  if not job then
    return
  end
  if job.character ~= snap.character or (job.feature and not cfg(job.feature)) then
    cancel("Condição do assistente mudou")
    return
  end
  if job.stage == "confirm" then
    if job.confirm and job.confirm(snap, target) then
      if job.success then
        job.success(snap, target)
      end
      backoff[job.id] = snap.now + 0.05
      cancel("Concluído: " .. job.id)
    elseif snap.now - job.sent > job.timeout then
      cancel("Sem confirmação: " .. job.id, true)
    end
    return
  end
  if not valid(job, snap) then
    cancel("Condição do assistente mudou")
    return
  end
  if snap.now - job.started > 1.8 then
    cancel("Preparação interrompida", true)
    return
  end
  if job.stage == "equip" then
    if job.needsEquip ~= false then
      if not job.tool or not job.tool.Parent or not native.equip(job.tool) then
        cancel("Item indisponível", true)
        return
      end
    end
    job.stage, job.equippedAt = "aim", snap.now
    return
  end
  if job.needsEquip ~= false and native.equipped() ~= job.tool then
    cancel("Controle manual do item")
    return
  end
  if snap.now - job.equippedAt < (job.delay or 0.1) then
    return
  end
  local point = job.point and job.point(snap, target)
  if point then
    local delta = point - snap.camera.CFrame.Position
    if delta.Magnitude < 0.01 or snap.camera.CFrame.LookVector:Dot(delta.Unit) < math.cos(math.rad(2)) then
      return
    end
  end
  if not valid(job, snap) then
    cancel("Oportunidade encerrada")
    return
  end
  if (job.native or job.cooldown) and not native.canAct(job.native or job.cooldown) then
    return
  end
  if job.before then
    job.before(snap, target)
  end
  local ok = job.perform and job.perform(snap, target) or (job.native and native.action(job.native, point))
  if not ok then
    cancel("Ação indisponível: " .. job.id, true)
    return
  end
  job.sent, job.stage = snap.now, "confirm"
  status = "Confirmando: " .. job.id
end
local function pearl(snap)
  if not target or not target.engaged or snap.now - lastPearl < cfg("MCPearlInterval") then
    return nil
  end
  local mode = explosives.mode()
  local permitted = mode == "dtap" and cfg("MCDTapPearl")
    or mode == "crystal" and cfg("MCCrystalPearl")
    or mode == "anchor" and cfg("MCAnchorPearl")
    or not mode and cfg("MCSwordPearl")
  if not permitted or target.distance < cfg("MCSwordPearlGap") * 3.2 or target.distance > cfg("MCSwordPearlMax") * 3.2 then
    return nil
  end
  local relative = target.root.AssemblyLinearVelocity - snap.root.AssemblyLinearVelocity
  local displacement = target.root.Position - snap.root.Position
  if displacement.Magnitude < 0.1 or relative:Dot(displacement.Unit) < 1.5 then
    return nil
  end
  local item = native.find("Pearl", true)
  if not item or item.count <= cfg("MCPearlReserve") then
    return nil
  end
  if (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > snap.server then
    return nil
  end
  local point = geometry.pearl(snap, target, cfg, projectile)
  if not point then
    return nil
  end
  local before = item.count
  local planned, plannedAt = point, snap.now
  return {
    id = "pearl_follow",
    feature = mode == "dtap" and "MCDTapPearl" or mode == "crystal" and "MCCrystalPearl" or mode == "anchor" and "MCAnchorPearl" or "MCSwordPearl",
    target = target.character,
    priority = 65,
    tool = item.tool,
    native = "use",
    delay = 0.12,
    timeout = 1,
    point = function() return planned end,
    valid = function(s, t)
      if not t then
        return false
      end
      if s.now - plannedAt >= 0.1 then
        planned, plannedAt = geometry.pearl(s, t, cfg, projectile), s.now
      end
      return t.engaged and t.distance >= cfg("MCSwordPearlGap") * 3.2 and t.distance <= cfg("MCSwordPearlMax") * 3.2 and planned ~= nil
    end,
    before = function(s) lastPearl = s.now end,
    confirm = function(s)
      return not item.tool.Parent
        or (tonumber(item.tool:GetAttribute("Count")) or 0) < before
        or (tonumber(s.player:GetAttribute("ItemCooldown_Pearl")) or 0) > s.server
    end,
  }
end
local function sword(snap)
  if not cfg("MCAttack") or not target or not target.engaged or not snap.equipped then
    return
  end
  local stats = native.stats(snap.equipped)
  if stats.type ~= "sword" or snap.now < nextAttack or snap.player:GetAttribute("OffhandUsing") == true then
    return
  end
  if snap.character:GetAttribute("EatingApple") or snap.character:GetAttribute("DrinkingPotion") or snap.character:GetAttribute("BowDrawStarted") then
    return
  end
  local swing = tonumber(snap.character:GetAttribute("LocalAttackSwing")) or 0
  local recharge = cfg("MCAttackCharge") / 100 / math.max(0.05, stats.speed)
  if snap.now - swing < recharge then
    return
  end
  local reach = math.min(stats.reach, cfg("MCAttackRange") * 3.2)
  if not targeting.canHit(snap, target, reach) then
    return
  end
  local falling = snap.root.AssemblyLinearVelocity.Y < -0.2 and snap.humanoid.FloorMaterial == Enum.Material.Air
  if
    cfg("MCCrit")
    and snap.humanoid.FloorMaterial ~= Enum.Material.Air
    and snap.now - lastJump > 1
    and not snap.humanoid.Sit
    and not snap.character:GetAttribute("Sneaking")
  then
    local ceiling = native.raycast(snap.eye, Vector3.new(0, 5, 0))
    if not ceiling then
      snap.humanoid.Jump = true
      lastJump = snap.now
      nextAttack = snap.now + 0.1
      return
    end
  end
  if cfg("MCCrit") and not falling and snap.now - lastJump < 0.65 then
    return
  end
  if cfg("MCCrit") and falling then
    native.prepareCritical()
  end
  if native.action("attack") then
    nextAttack = snap.now + recharge
  end
end
local function observeWorld(snap)
  local blocks = snap.world:FindFirstChild("PlayerBlocks")
  if blocks == folder then
    return
  end
  folder = blocks
  if blocks then
    for _, block in ipairs(blocks:GetChildren()) do
      explosives.mark(block, -math.huge)
    end
    if worldScope then
      worldScope.destroy()
    end
    worldScope = scope.child()
    worldScope.connect(blocks.ChildAdded, function(block) explosives.mark(block, os.clock()) end)
    worldScope.connect(blocks.ChildRemoved, function(block) explosives.mark(block, nil) end)
  end
end
local function tick()
  native.discover()
  local snap = native.snapshot()
  if not snap or not cfg("MCEnabled") or not focused then
    if active then
      cancel("Assistentes pausados")
    end
    if latest then
      Coordinator.reset()
    end
    status = cfg("MCEnabled") and "Aguardando arena" or "Assistentes desligados"
    return
  end
  if character ~= snap.character then
    Coordinator.reset()
    character = snap.character
  end
  latest = snap
  observeWorld(snap)
  if active then
    snap.targetCFrame = active.view
  end
  target = targeting.update(snap, cfg)
  if snap.now < pauseUntil then
    return
  end
  local survival = inventory.propose(snap, target, cfg)
  local emergency = choose(survival, explosives.defense(snap, cfg))
  local manuallyUsing = snap.player:GetAttribute("OffhandUsing") == true
    or snap.character:GetAttribute("EatingApple")
    or snap.character:GetAttribute("DrinkingPotion")
  if manuallyUsing and not active then
    if allowed(survival) and survival.priority == 100 then
      start(survival, snap)
    end
    status = "Respeitando uso manual"
    return
  end
  if active then
    if allowed(emergency) and emergency.priority > active.priority and (active.stage ~= "confirm" or emergency.priority >= 90) then
      cancel("Prioridade de sobrevivência")
      start(emergency, snap)
    elseif allowed(survival) and survival.priority == 100 and active.priority < 100 and active.mode ~= "offhand" then
      cancel("Reposição urgente de totem")
      start(survival, snap)
    end
    advance(snap)
    return
  end
  local proposal = emergency
  if target then
    local explosive = explosives.propose(snap, target, cfg)
    if explosive then
      explosive.target = target.character
    end
    proposal = choose(proposal, explosive)
    proposal = choose(proposal, pearl(snap))
  end
  if proposal then
    start(proposal, snap)
    return
  end
  if snap.player:GetAttribute("OffhandUsing") == true or snap.character:GetAttribute("EatingApple") or snap.character:GetAttribute("DrinkingPotion") then
    status = "Respeitando uso manual"
    return
  end
  sword(snap)
  status = target and (target.engaged and "Combate: " or "Alvo: ") .. target.player.DisplayName or "Aguardando alvo próximo da mira"
end
function Coordinator.start()
  if scope then
    scope.destroy()
  end
  scope = lifetime.scope()
  local input = game:GetService("UserInputService")
  focused = true
  scope.connect(input.WindowFocusReleased, function()
    focused = false
    cancel("Janela sem foco", false, true)
  end)
  if input.WindowFocused then
    scope.connect(input.WindowFocused, function() focused = true end)
  end
  scope.connect(input.InputBegan, function(event, processed)
    if processed then
      return
    end
    local kind = event.UserInputType
    if
      kind == Enum.UserInputType.MouseButton1
      or kind == Enum.UserInputType.MouseButton2
      or kind == Enum.UserInputType.Touch
      or kind == Enum.UserInputType.Keyboard
      or kind == Enum.UserInputType.Gamepad1
    then
      -- Movement remains usable; explicit item/action input cancels an automatic transaction.
      local key = event.KeyCode
      if key == Enum.KeyCode.W or key == Enum.KeyCode.A or key == Enum.KeyCode.S or key == Enum.KeyCode.D or key == Enum.KeyCode.Space then
        return
      end
      pauseUntil = os.clock() + cfg("MCManualPause")
      cancel("Controle manual", false, true)
    end
  end)
  scope.connect(input.InputChanged, function(event)
    if event.UserInputType == Enum.UserInputType.MouseMovement and event.Delta.Magnitude > 35 then
      pauseUntil = os.clock() + cfg("MCManualPause")
      cancel("Movimento manual da câmera", false, true)
    end
  end)
  scope.connect(utils.getRunService().Heartbeat, function()
    if os.clock() - lastTick < 1 / 30 then
      return
    end
    lastTick = os.clock()
    local ok, err = pcall(tick)
    if not ok then
      cancel("Falha no assistente", true)
      if os.clock() - lastError > 2 then
        lastError = os.clock()
        utils.recordError("MCPVP", tostring(err))
      end
    end
  end)
  scope.connect(utils.getRunService().RenderStepped, function(dt)
    if not latest or not native.ready() or not cfg("MCEnabled") or not focused or os.clock() < pauseUntil then
      return
    end
    if active and active.stage == "aim" and active.point then
      local point = active.point(latest, target)
      if point then
        native.aim(point, dt, 540)
      end
    elseif not active and cfg("MCAim") and target then
      native.aim(targeting.point(latest, target, cfg("MCAimTolerance")), dt, cfg("MCAimSpeed"))
    end
  end)
  local storage = game:GetService("ReplicatedStorage")
  local remotes = storage:FindFirstChild("Remotes")
  local event = remotes and remotes:FindFirstChild("ItemAction")
  if event and event:IsA("RemoteEvent") then
    scope.connect(event.OnClientEvent, function(action, _, kind, _, velocity, gravity, drag)
      if action == "Projectile" and kind == "Pearl" and typeof(velocity) == "Vector3" and velocity.Magnitude > 0 then
        projectile = { speed = velocity.Magnitude, gravity = tonumber(gravity) or 38.4, drag = tonumber(drag) or 0.99 }
      end
    end)
  end
  scope.connect(utils.getLocalPlayer().CharacterRemoving, function() Coordinator.reset() end)
  return true
end
function Coordinator.setup(deps)
  utils, native, geometry, targeting, inventory, explosives, options, lifetime =
    deps.Utils, deps.Native, deps.Geometry, deps.Target, deps.Inventory, deps.Explosives, deps.Options, deps.Lifetime
  return true
end
function Coordinator.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  Coordinator.reset()
end
function Coordinator.busy() return active ~= nil end
function Coordinator.state()
  local caps = native.capabilities()
  local missing = {}
  for _, name in ipairs({ "attack", "use", "place", "inventory" }) do
    if not caps[name] then
      missing[#missing + 1] = name
    end
  end
  statusDetails = #missing > 0 and "\nExecutor: indisponível " .. table.concat(missing, ", ") or ""
  return status .. statusDetails
end
Coordinator.__contract = {
  requires = {
    Utils = "utils",
    Native = "mcpnative",
    Geometry = "mcpgeometry",
    Target = "mcptarget",
    Inventory = "mcpinventory",
    Explosives = "mcpexplosives",
    Options = "mcpoptions",
    Lifetime = "lifetime",
  },
  requiresMethods = { Utils = { "getConfigValue", "getRunService", "getLocalPlayer", "recordError" }, Lifetime = { "scope" } },
  provides = { "setup", "start", "reset", "teardown", "busy", "state" },
}
return Coordinator
