-- [[ mcpcoordinator ]]
--!optimize 2
local Coordinator = {}
local utils, native, geometry, targeting, inventory, explosives, options, lifetime
local scope, worldScope, character, folder
local active, target, latest, projectile
local backoff = {}
local auraHits = {}
local lastPearl, nextAttack, pauseUntil, lastError = -math.huge, 0, 0, -math.huge
local lastJump = -math.huge
local swordPending
local enemyPearls = {}
local pearlContacts = {}
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
local function cancel(reason, failed, _manual)
  local job = active
  active = nil
  if not job then
    return
  end
  if job.cancel then
    pcall(job.cancel)
  end
  if job.inventory then
    native.closeInventory()
  end
  if job.needsEquip ~= false then
    native.restore(job.original, job.tool)
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
  native.closeInventory()
  target, latest, character, folder = nil, nil, nil, nil
  lastPearl, nextAttack, pauseUntil, lastJump = -math.huge, 0, 0, -math.huge
  swordPending = nil
  backoff = {}
  enemyPearls = {}
  pearlContacts = {}
  auraHits = {}
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
  if job.target then
    local human = job.target:FindFirstChildOfClass("Humanoid")
    if not job.target.Parent or not human or human.Health <= 0 then
      return false
    end
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
  job.started, job.original = snap.now, snap.equipped
  job.character, job.stage = snap.character, "equip"
  job.timeout = job.timeout or 0.8
  active = job
end
local function applePastHalf(snap)
  local tool = snap.character:FindFirstChild("Gold Apple")
  if not tool or not snap.character:GetAttribute("EatingApple") then
    return false
  end
  local started = tonumber(tool:GetAttribute("EatingStarted"))
  local untilAt = tonumber(tool:GetAttribute("EatingUntil"))
  local duration = tonumber(tool:GetAttribute("EatingDuration")) or (started and untilAt and untilAt - started)
  return started ~= nil and untilAt ~= nil and duration ~= nil and duration > 0 and snap.server < untilAt and snap.server - started >= duration / 2
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
  if job.result == false or (job.inventory and job.stage ~= "equip" and not native.inventoryOpen()) then
    cancel("Transação de inventário interrompida", true)
    return
  end
  if job.id == "apple" and job.valid and not job.valid(snap, target) and not applePastHalf(snap) then
    cancel("Pausa das maçãs após combate")
    return
  end
  if job.stage == "confirm" then
    if job.confirm and job.confirm(snap, target) then
      if job.success then
        job.success(snap, target)
      end
      if job.target and (job.feature == "MCDTap" or job.feature == "MCCrystal" or job.feature == "MCAnchor") then
        targeting.hold(job.target, snap.now)
      end
      backoff[job.id] = snap.now
      cancel("Concluído: " .. job.id)
      if job.id == "anchor_charge" then
        local fresh = native.snapshot()
        if fresh then
          local follow = explosives.propose(fresh, target, cfg, targeting.combatNearby(fresh.now))
          if follow and follow.id == "anchor_detonate" then
            start(follow, fresh)
            advance(fresh)
          end
        end
      end
    elseif snap.now - job.sent > job.timeout then
      cancel("Nova tentativa: " .. job.id, not job.repeatFast)
    end
    return
  end
  if not valid(job, snap) then
    job.invalidSince = job.invalidSince or snap.now
    job.suspended = true
    if snap.now - job.invalidSince > 0.25 then
      cancel("Oportunidade temporariamente indisponível")
    end
    return
  end
  job.invalidSince, job.suspended = nil, false
  if snap.now - job.started > 5 then
    cancel("Preparação interrompida", true)
    return
  end
  if job.stage == "equip" then
    if job.inventory then
      if not native.openInventory() then
        cancel("Inventário indisponível", true)
        return
      end
      job.openedAt = snap.now
    end
    if job.needsEquip ~= false then
      if not job.tool or not job.tool.Parent or not native.equip(job.tool) then
        cancel("Item indisponível", true)
        return
      end
    end
    job.stage, job.equippedAt = "perform", snap.now
  end
  if job.needsEquip ~= false and native.equipped() ~= job.tool then
    cancel("Controle manual do item")
    return
  end
  if job.inventory and (not native.inventoryOpen() or snap.now <= job.openedAt) then
    return
  end
  if snap.now - job.equippedAt < (job.delay or 0) then
    return
  end
  local point = job.point and job.point(snap, target)
  if not valid(job, snap) then
    cancel("Oportunidade encerrada")
    return
  end
  if job.ready and not job.ready(snap, target) then
    return
  end
  if (job.native or job.cooldown) and not native.canAct(job.native or job.cooldown) then
    return
  end
  if job.before then
    job.before(snap, target)
  end
  local ok
  if job.perform then
    ok = job.perform(snap, target)
  else
    ok = job.native and native.action(job.native, point)
  end
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
  if
    target.player.Character ~= target.character
    or target.humanoid.Health <= 0
    or not target.root.Parent
    or target.player:GetAttribute("InArena") == false
    or target.player:GetAttribute("ArenaProtected") == true
  then
    return nil
  end
  local contact = targeting.lastContact(target.character)
  if snap.now - contact > 4 or (pearlContacts[target.character] or -math.huge) >= contact then
    return nil
  end
  local mode = explosives.mode() or (cfg("MCDTap") and "dtap" or cfg("MCCrystal") and "crystal" or cfg("MCAnchor") and "anchor" or nil)
  local permitted = mode == "dtap" and (cfg("MCDTapPearl") or cfg("MCCrystalAutoCombo") and cfg("MCCrystalPearl"))
    or mode == "crystal" and cfg("MCCrystalPearl")
    or mode == "anchor" and cfg("MCAnchorPearl")
    or not mode and cfg("MCSwordPearl")
  local crystalMode = mode == "crystal" or mode == "dtap"
  local swordItem = native.find("sword", true)
  local hitReach = swordItem and native.stats(swordItem.tool).reach or 9.6
  local gap = crystalMode and (hitReach + 0.32) or (mode and cfg("MCExplosivePearlGap") or cfg("MCSwordPearlGap")) * 3.2
  local enemyPearl = enemyPearls[target.character]
  if enemyPearl and snap.now - enemyPearl.at > 5 then
    enemyPearls[target.character] = nil
    enemyPearl = nil
  end
  if not permitted or (not enemyPearl and target.distance < gap) or target.distance > cfg("MCSwordPearlMax") * 3.2 then
    return nil
  end
  if target.distance < gap then
    return nil
  end
  if enemyPearl and (enemyPearl.landing - snap.root.Position).Magnitude < gap then
    return nil
  end
  local relative = target.root.AssemblyLinearVelocity - snap.root.AssemblyLinearVelocity
  local displacement = target.root.Position - snap.root.Position
  local awaySpeed = crystalMode and 0.8 or 2
  local relativeSpeed = crystalMode and 0.35 or 1
  if
    not enemyPearl
    and not crystalMode
    and (
      displacement.Magnitude < 0.1
      or target.root.AssemblyLinearVelocity:Dot(displacement.Unit) < awaySpeed
      or relative:Dot(displacement.Unit) < relativeSpeed
    )
  then
    return nil
  end
  local item = native.find("Pearl", true)
  if not item or item.count <= cfg("MCPearlReserve") then
    return nil
  end
  if (tonumber(snap.player:GetAttribute("ItemCooldown_Pearl")) or 0) > snap.server then
    return nil
  end
  local point = geometry.pearl(snap, target, cfg, projectile, enemyPearl and enemyPearl.landing)
  if not point then
    return nil
  end
  local before = item.count
  local opponent = target.character
  local planned, plannedAt = point, snap.now
  return {
    id = "pearl_follow",
    feature = mode == "dtap" and (cfg("MCDTapPearl") and "MCDTapPearl" or "MCCrystalPearl")
      or mode == "crystal" and "MCCrystalPearl"
      or mode == "anchor" and "MCAnchorPearl"
      or "MCSwordPearl",
    target = target.character,
    priority = 65,
    tool = item.tool,
    native = "use",
    delay = 0.12,
    timeout = 1,
    point = function() return planned end,
    valid = function(s, t)
      if
        not t
        or t.character ~= opponent
        or t.player.Character ~= opponent
        or t.humanoid.Health <= 0
        or t.player:GetAttribute("ArenaProtected") == true
        or t.player:GetAttribute("InArena") == false
        or s.now - contact > 4
        or (pearlContacts[opponent] or -math.huge) >= contact
      then
        return false
      end
      if s.now - plannedAt >= 0.1 then
        planned, plannedAt = geometry.pearl(s, t, cfg, projectile, enemyPearl and enemyPearl.landing), s.now
      end
      local delta = t.root.Position - s.root.Position
      local motion = t.root.AssemblyLinearVelocity - s.root.AssemblyLinearVelocity
      local fleeing = delta.Magnitude > 0.01 and t.root.AssemblyLinearVelocity:Dot(delta.Unit) >= awaySpeed and motion:Dot(delta.Unit) >= relativeSpeed
      return t.engaged and (crystalMode or enemyPearl ~= nil or fleeing) and t.distance >= gap and t.distance <= cfg("MCSwordPearlMax") * 3.2 and planned ~= nil
    end,
    before = function(s)
      lastPearl = s.now
      pearlContacts[opponent] = contact
    end,
    success = function(s)
      if explosives.follow(s, opponent, cfg) then
        targeting.resume(opponent, s.now, math.max(cfg("MCComboLifetime"), 12))
      end
      if enemyPearls[opponent] == enemyPearl then
        enemyPearls[opponent] = nil
      end
    end,
    confirm = function(s)
      return not item.tool.Parent
        or (tonumber(item.tool:GetAttribute("Count")) or 0) < before
        or (tonumber(s.player:GetAttribute("ItemCooldown_Pearl")) or 0) > s.server
    end,
  }
end
local function selectSwordTarget(snap, reach, forCombo)
  local chosen, oldest = nil, math.huge
  for _, candidate in ipairs(targeting.nearby()) do
    if not forCombo and not targeting.active(snap.now) then
      continue
    end
    if forCombo and not explosives.needsStrike(snap, candidate, cfg) then
      continue
    end
    local delta = candidate.root.Position - snap.eye
    if delta.Magnitude > 0.01 and targeting.canHit(snap, candidate, reach, forCombo and delta.Unit or nil) then
      local last = auraHits[candidate.character] or -math.huge
      if last < oldest then
        chosen, oldest = candidate, last
      end
    end
  end
  return chosen
end
local function sword(snap, forCombo)
  if (not forCombo and not cfg("MCAttack")) or snap.now < nextAttack then
    return false
  end
  if
    snap.player:GetAttribute("OffhandUsing") == true
    or snap.character:GetAttribute("EatingApple")
    or snap.character:GetAttribute("DrinkingPotion")
    or snap.character:GetAttribute("BowDrawStarted")
  then
    return false
  end
  local weapons = native.data().weapons
  local function isSword(tool)
    return tool ~= nil
      and weapons ~= nil
      and type(weapons.IsWeapon) == "function"
      and weapons.IsWeapon(tool)
      and (tool:GetAttribute("WeaponType") == "sword" or tool:GetAttribute("WeaponType") == nil)
      and native.stats(tool).type == "sword"
  end
  local weapon = native.equipped()
  if not isSword(weapon) then
    if not forCombo and not explosives.mode() then
      return false
    end
    weapon = nil
    for _, item in ipairs(native.items()) do
      if item.slot and item.slot <= 9 and isSword(item.tool) then
        weapon = item.tool
        break
      end
    end
  end
  if not weapon then
    return false
  end
  local stats = native.stats(weapon)
  local recharge = cfg("MCAttackCharge") / 100 / math.max(0.05, stats.speed)
  local reach = math.min(stats.reach, cfg("MCAttackRange") * 3.2)
  local chosen = selectSwordTarget(snap, reach, forCombo)
  if not chosen then
    if swordPending then
      native.restore(swordPending.previous, swordPending.weapon)
      swordPending = nil
    end
    return false
  end
  if not native.canAct("attack") then
    return swordPending ~= nil
  end
  if not forCombo and snap.now - (tonumber(snap.character:GetAttribute("LocalAttackSwing")) or 0) < recharge then
    return false
  end
  if not forCombo and cfg("MCCrit") then
    local falling = snap.root.AssemblyLinearVelocity.Y < -0.2 and snap.humanoid.FloorMaterial == Enum.Material.Air
    if
      snap.humanoid.FloorMaterial ~= Enum.Material.Air
      and snap.now - lastJump > 1
      and not snap.humanoid.Sit
      and not snap.character:GetAttribute("Sneaking")
      and not native.raycast(snap.eye, Vector3.new(0, 5, 0))
    then
      snap.humanoid.Jump = true
      lastJump = snap.now
      return false
    end
    if not falling and snap.now - lastJump < 0.65 then
      return false
    end
    if falling then
      native.prepareCritical()
    end
  end
  local previous = swordPending and swordPending.previous or native.equipped()
  if swordPending and (not forCombo or swordPending.character ~= chosen.character or native.equipped() ~= swordPending.weapon) then
    native.restore(swordPending.previous, swordPending.weapon)
    swordPending = nil
    return false
  end
  if swordPending and snap.now < swordPending.ready then
    return true
  end
  local previousClass = previous and previous:GetAttribute("ClassItem")
  local previousBlock = previous and previous:GetAttribute("BlockKey")
  local returnItem = previousClass == "EndCrystal" or previousClass == "RespawnAnchor" or previousBlock == "respawn_anchor" or previousBlock == "obsidian"
  explosives.release()
  if not native.equip(weapon) then
    if returnItem then
      native.restore(previous, native.equipped())
    end
    return false
  end
  if forCombo and previous ~= weapon and not swordPending then
    swordPending = { previous = previous, weapon = weapon, character = chosen.character, ready = snap.now + 0.08 }
    return true
  end
  swordPending = nil
  local current = native.snapshot()
  if not current then
    if returnItem then
      native.restore(previous, weapon)
    end
    return false
  end
  if current.equipped ~= weapon or not isSword(current.equipped) then
    return false
  end
  targeting.noteAttack(current, chosen, forCombo)
  local hit = forCombo and native.strike(chosen.root.Position) or not forCombo and native.action("attack")
  if returnItem then
    native.restore(previous, weapon)
  end
  if not hit then
    return false
  end
  auraHits[chosen.character] = snap.now
  targeting.hold(chosen.character, snap.now)
  nextAttack = snap.now + recharge
  explosives.struck(snap, chosen, cfg)
  -- Start placement in the same heartbeat as the sword hit, including before knockback replicates.
  explosives.pulse(snap, targeting.combatNearby(snap.now), cfg)
  status = "Ataque: " .. chosen.player.DisplayName
  return true
end
local function observeWorld(snap)
  local blocks = snap.world:FindFirstChild("PlayerBlocks")
  if blocks == folder then
    return
  end
  folder = blocks
  if worldScope then
    worldScope.destroy()
    worldScope = nil
  end
  if blocks then
    for _, block in ipairs(blocks:GetChildren()) do
      explosives.mark(block, -math.huge)
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
    explosives.release()
    status = cfg("MCEnabled") and "Aguardando arena" or "Assistentes desligados"
    return
  end
  if character ~= snap.character then
    Coordinator.reset()
    character = snap.character
  end
  latest = snap
  observeWorld(snap)
  target = targeting.update(snap, cfg)
  local manualTarget = explosives.observe(snap, targeting.nearby(), cfg)
  if not target and manualTarget then
    target = manualTarget
  end
  if snap.now < pauseUntil then
    explosives.release()
    return
  end
  local survival = inventory.propose(snap, target, cfg, explosives.mode())
  if active and active.id == "apple" and active.valid and not active.valid(snap, target) and not applePastHalf(snap) then
    cancel("Pausa das maçãs após combate")
  end
  local emergency = survival
  local manuallyUsing = snap.player:GetAttribute("OffhandUsing") == true
    or snap.character:GetAttribute("EatingApple")
    or snap.character:GetAttribute("DrinkingPotion")
  if manuallyUsing and not active then
    if applePastHalf(snap) then
      status = "Terminando maçã"
      return
    end
    if allowed(survival) and survival.priority == 100 then
      start(survival, snap)
    end
    status = "Respeitando uso manual"
    return
  end
  if active then
    if active.id == "apple" and applePastHalf(snap) then
      advance(snap)
      return
    end
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
  if allowed(emergency) and emergency.priority >= 90 then
    explosives.release()
    start(emergency, snap)
    advance(snap)
    return
  end
  if sword(snap, true) then
    return
  end
  local base = explosives.resumeBase(snap, target, cfg)
  if allowed(base) then
    explosives.release()
    start(base, snap)
    advance(snap)
    return
  end
  local explosive = explosives.propose(snap, target, cfg, targeting.combatNearby(snap.now))
  if allowed(explosive) and explosive.priority >= 80 then
    explosives.release()
    start(explosive, snap)
    advance(snap)
    return
  end
  if sword(snap, false) then
    return
  end
  local pursuit = pearl(snap)
  if allowed(pursuit) then
    explosives.release()
    start(pursuit, snap)
    advance(snap)
    return
  end
  local pulsing, victim = explosives.pulse(snap, targeting.combatNearby(snap.now), cfg)
  if pulsing then
    if victim then
      targeting.hold(victim.character, snap.now)
    end
    status = "Combo de cristais"
    return
  end
  local proposal = choose(emergency, explosive)
  if proposal then
    explosives.release()
    start(proposal, snap)
    advance(snap)
    return
  end
  status = target and (target.engaged and "Combate: " or "Alvo: ") .. target.player.DisplayName or "Aguardando oponente"
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
    explosives.release()
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
      if kind == Enum.UserInputType.Keyboard and key.Value >= Enum.KeyCode.One.Value and key.Value <= Enum.KeyCode.Nine.Value then
        swordPending = nil
        cancel("Troca manual de slot", false, true)
        explosives.clearCombo()
        pauseUntil = os.clock() + 0.15
        return
      end
      local tool = native.equipped()
      local class = tool and tool:GetAttribute("ClassItem")
      local combatInput = native.stats(tool).type == "sword"
        or class == "EndCrystal"
        or class == "RespawnAnchor"
        or class == "Glowstone"
        or (tool and tool:GetAttribute("BlockKey") == "obsidian")
      if combatInput and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch) then
        return
      end
      swordPending = nil
      pauseUntil = os.clock() + cfg("MCManualPause")
      cancel("Controle manual", false, true)
      explosives.release()
    end
  end)
  scope.add(native.observeAttacks(function()
    if not cfg("MCEnabled") then
      return
    end
    local snap = native.snapshot()
    targeting.noteAttack(snap, nil, true)
    if not snap or not cfg("MCCrystal") then
      return
    end
    local folder = snap.world:FindFirstChild("EndCrystals")
    local melee = native.data().geometry
    local reach = native.stats(snap.equipped).reach
    if not folder or not melee or type(melee.Box) ~= "function" then
      return
    end
    local chosen, closest
    for _, crystal in ipairs(folder:GetChildren()) do
      local point = geometry.blastPosition(crystal)
      if point then
        local distance = melee.Box(snap.eye, snap.camera.CFrame.LookVector, point - Vector3.new(3.2, 0, 3.2), point + Vector3.new(3.2, 6.4, 3.2), reach)
        if distance and (not closest or distance < closest) and native.visible(snap.eye, snap.eye + snap.camera.CFrame.LookVector * distance, crystal) then
          chosen, closest = crystal, distance
        end
      end
    end
    if chosen then
      targeting.noteCrystal(snap, chosen, geometry.blastPosition(chosen))
    end
  end))
  scope.connect(utils.getRunService().Heartbeat, function()
    local ok, err = pcall(tick)
    if not ok then
      cancel("Falha no assistente", true)
      explosives.release()
      native.closeInventory()
      if os.clock() - lastError > 2 then
        lastError = os.clock()
        utils.recordError("MCPVP", tostring(err))
      end
    end
  end)
  scope.connect(utils.getRunService().RenderStepped, function(dt)
    if not cfg("MCEnabled") or not cfg("MCAim") or not focused or active or os.clock() < pauseUntil then
      return
    end
    if not target or not target.engaged or not target.character.Parent or target.humanoid.Health <= 0 or explosives.mode() then
      return
    end
    local snap = native.snapshot()
    if not snap or not latest or snap.character ~= latest.character or native.stats(snap.equipped).type ~= "sword" then
      return
    end
    if
      native.usingHeld()
      or snap.player:GetAttribute("OffhandUsing") == true
      or snap.character:GetAttribute("EatingApple")
      or snap.character:GetAttribute("DrinkingPotion")
      or snap.character:GetAttribute("BowDrawStarted")
    then
      return
    end
    if
      (target.root.Position - snap.root.Position).Magnitude > cfg("MCSwordLockRange") * 3.2
      or not native.visible(snap.eye, target.root.Position, target.character)
      or explosives.needsStrike(snap, target, cfg)
    then
      return
    end
    -- Only the optional sword lock changes the view; explosive actions keep their silent directions.
    native.aim(targeting.point(snap, target, cfg("MCAimTolerance")), dt, cfg("MCAimSpeed"))
  end)
  local storage = game:GetService("ReplicatedStorage")
  local remotes = storage:FindFirstChild("Remotes")
  local event = remotes and remotes:FindFirstChild("ItemAction")
  if event and event:IsA("RemoteEvent") then
    scope.connect(event.OnClientEvent, function(action, id, kind, position, velocity, gravity, drag)
      if action == "Projectile" and kind == "Pearl" and typeof(velocity) == "Vector3" and velocity.Magnitude > 0 then
        projectile = { speed = velocity.Magnitude, gravity = tonumber(gravity) or 38.4, drag = tonumber(drag) or 0.99 }
        local snap = native.snapshot()
        if not snap or typeof(position) ~= "Vector3" then
          return
        end
        -- This packet has no owner ID. Attribute only a uniquely close launch, never our own.
        local owner, nearest, runnerUp = nil, math.huge, math.huge
        for _, candidate in ipairs(targeting.nearby()) do
          local distance = (position - (candidate.root.Position + Vector3.new(0, 1.184, 0))).Magnitude
          if distance < nearest then
            owner, runnerUp, nearest = candidate, nearest, distance
          else
            runnerUp = math.min(runnerUp, distance)
          end
        end
        if not owner or not owner.engaged or nearest > 5 or nearest + 1 >= math.min(runnerUp, (position - snap.eye).Magnitude) then
          return
        end
        if owner then
          local landing = geometry.projectileLanding(snap, position, velocity, projectile, { owner.character })
          if landing then
            enemyPearls[owner.character] = { id = id, landing = landing, at = snap.now }
          end
        end
      elseif action == "ProjectileMove" and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
        local snap = native.snapshot()
        if snap then
          for char, entry in pairs(enemyPearls) do
            if entry.id == id then
              entry.landing = geometry.projectileLanding(snap, position, velocity, projectile, { char }) or entry.landing
            end
          end
        end
      elseif action == "ProjectileEnd" and typeof(kind) == "Vector3" then
        for _, entry in pairs(enemyPearls) do
          if entry.id == id then
            entry.landing = kind
          end
        end
      end
    end)
  end
  local combat = storage:FindFirstChild("VoxelCombat")
  local feedback = combat and combat:FindFirstChild("Feedback")
  local swing = combat and combat:FindFirstChild("Swing")
  if feedback and feedback:IsA("RemoteEvent") then
    scope.connect(feedback.OnClientEvent, function(kind, blocked)
      if kind == "HitConfirm" and not blocked then
        targeting.confirmHit(os.clock())
      end
    end)
  end
  if swing and swing:IsA("RemoteEvent") then
    scope.connect(swing.OnClientEvent, function(object)
      if typeof(object) ~= "Instance" then
        return
      end
      local char = object:IsA("Player") and object.Character or object:IsA("Model") and object or nil
      targeting.noteSwing(char, os.clock())
    end)
  end
  local flash = storage:FindFirstChild("ConfirmedMeleeFlash")
  if flash and flash:IsA("RemoteEvent") then
    scope.connect(flash.OnClientEvent, function(victim) targeting.noteVictim(victim, os.clock()) end)
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
function Coordinator.busy() return active ~= nil or explosives.mode() ~= nil end
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
