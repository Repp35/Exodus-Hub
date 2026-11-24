-- [[ targeting ]]
--!optimize 2

-- code
local Targeting = {}
function Targeting.setup() return true end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Targeting.create(deps)
  local resolver = {}
  function resolver.resolve(context)
    local me = context.player and context.player.UserId
    local report = { mode = "match", targeted = false, known = false, targetId = -1, conflict = false, positive = {}, signals = {} }
    local function add(name, family, read)
      local signal = { name = name, family = family, available = false, state = "unavailable" }
      report.signals[#report.signals + 1] = signal
      if context.active == false then
        signal.reason = "round_inactive"
        return
      end
      local ok, value, reason = pcall(read)
      if not ok then
        signal.reason = "read_failed"
        return
      end
      signal.reason = reason
      if finite(value) and value % 1 == 0 then
        signal.targetId, signal.targeted = value, value > 0 and value == me
      elseif type(value) == "boolean" then
        signal.targeted = value
        if value then
          signal.targetId = me
        end
      else
        return
      end
      signal.available, signal.state, report.known = true, signal.targeted and "yes" or "no", true
      if signal.targeted then
        report.targeted = true
        report.positive[#report.positive + 1] = name
      end
    end
    report.serverNow, report.receivedAt, report.attributeAt = context.serverNow, context.receivedAt, context.attributeAt
    report.serverTime = context.sync and context.sync.ServerTime
    local sync, provider = context.sync, context.provider
    local function freshSync() return context.syncFresh == true end
    local history = provider and provider.history
    local latest = type(history) == "table" and history[#history]
    local function freshProvider()
      if not provider or provider.hasState ~= true then
        return false
      end
      if finite(context.sequence) and finite(provider.lastSeq) then
        local delta = (context.sequence - provider.lastSeq) % 65536
        if delta > 0 and delta < 32768 then
          return false
        end
      end
      if latest and finite(latest.serverTime) and finite(context.serverNow) then
        local age = context.serverNow - latest.serverTime
        return age >= -0.02 and age <= context.maxAge
      end
      return freshSync()
    end
    report.apProviderSuppressed = freshSync() and sync and (sync.TargetPlayerID == me or sync.HighlightTargetPlayerID == me) or false
    add("replicator.IsLocalTarget", "network", function()
      if freshProvider() and type(provider.IsLocalTarget) == "function" then
        return provider:IsLocalTarget()
      end
    end)
    add("workspace.GameBallTarget", "attribute", function() return context.world:GetAttribute("GameBallTarget") end)
    add("ball.targetColor", "visual", function()
      local ball = context.ball
      if not ball or not ball:IsA("BasePart") or ball.Transparency == 1 or ball.LocalTransparencyModifier == 1 then
        return nil
      end
      local color = ball.Color
      local red = Color3.fromRGB(202, 56, 30)
      local function same(a, b) return math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005 end
      local normal = ball:GetAttribute("SkinNormalColor")
      if typeof(normal) == "Color3" and same(normal, red) then
        return nil
      end
      if same(color, red) then
        return true
      end
      if same(color, typeof(normal) == "Color3" and normal or Color3.fromRGB(153, 153, 153)) then
        return false
      end
      return nil
    end)
    add("sync.TargetPlayerID", "network", function() return freshSync() and sync and sync.TargetPlayerID or nil end)
    add("sync.HighlightTargetPlayerID", "network", function() return freshSync() and sync and sync.HighlightTargetPlayerID or nil end)
    add("character.PlayerBallHighlight", "visual", function()
      local character = context.player and context.player.Character
      local mark = character and character:FindFirstChild("PlayerBallHighlight")
      if mark and mark:IsA("Highlight") and mark.Parent == character then
        return mark.Enabled == true
      end
    end)
    local function validId(id) return finite(id) and id > 0 and id % 1 == 0 and id or nil end
    local packet = freshSync() and sync and validId(sync.TargetPlayerID) or nil
    local ok, attribute = pcall(function() return context.world:GetAttribute("GameBallTarget") end)
    attribute = ok and validId(attribute) or nil
    local selected = packet or attribute
    report.conflict = packet ~= nil and attribute ~= nil and packet ~= attribute
    if context.active == false then
      report.targeted, report.known, report.targetId, report.conflict, report.source = false, false, -1, false, "round_inactive"
      return report
    end
    if report.conflict then
      if finite(context.receivedAt) and finite(context.attributeAt) then
        selected = context.attributeAt > context.receivedAt and attribute or packet
      else
        report.targeted, report.known, report.targetId, report.source = false, false, -1, "target_transition"
        return report
      end
    end
    if selected then
      report.targetId, report.targeted, report.known = selected, selected == me, true
      report.source = selected == packet and "sync.target" or "workspace.GameBallTarget"
      return report
    end
    if freshProvider() and not packet and not attribute then
      for _, signal in ipairs(report.signals) do
        if signal.name == "replicator.IsLocalTarget" and signal.targeted then
          report.targeted, report.known, report.targetId, report.source = true, true, me, signal.name
          return report
        end
      end
    end
    local highlighted, multiple
    for _, player in ipairs(context.players and context.players:GetPlayers() or {}) do
      local character = player.Character
      local mark = character and character:FindFirstChild("PlayerBallHighlight")
      if mark and mark.Enabled then
        if highlighted then
          multiple = true
        end
        highlighted = player.UserId
      end
    end
    local redBall = false
    for _, signal in ipairs(report.signals) do
      if signal.name == "ball.targetColor" and signal.targeted then
        redBall = true
      end
    end
    report.targeted = not multiple and highlighted == me and redBall
    report.known = not multiple and highlighted ~= nil and (highlighted ~= me or redBall)
    report.targetId = report.known and highlighted or -1
    report.source = report.known and "visual.highlight_and_ball" or "unavailable"
    return report
  end
  function resolver.training(ball, goal, me, serverTime, receivedAt, serverNow)
    local signals = { { name = "sync.TargetPlayerID", available = finite(goal) and goal >= 0, targeted = goal == me } }
    local function same(a, b) return math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005 end
    local visible = ball and ball.Parent and ball.Transparency < 1 and ball.LocalTransparencyModifier < 1
    if visible then
      local normal, red = ball:GetAttribute("SkinNormalColor"), Color3.fromRGB(202, 56, 30)
      if typeof(normal) ~= "Color3" or not same(normal, red) then
        local own, other = same(ball.Color, red), same(ball.Color, typeof(normal) == "Color3" and normal or Color3.fromRGB(153, 153, 153))
        signals[#signals + 1] = { name = "ball.targetColor", available = own or other, targeted = own }
      end
      if not finite(goal) or goal < 0 then
        local trails = ball:FindFirstChild("Trails")
        local trail = trails and trails:FindFirstChild("BallTrail")
        local target, ordinary = trails and trails:FindFirstChild("BallTrailTarget"), trails and trails:FindFirstChild("BallTrail2")
        local function equal(a, b)
          if typeof(a) ~= "ColorSequence" or typeof(b) ~= "ColorSequence" then
            return false
          end
          local left, right = a.Keypoints, b.Keypoints
          if #left ~= #right then
            return false
          end
          for index, point in ipairs(left) do
            if math.abs(point.Time - right[index].Time) > 0.001 or not same(point.Value, right[index].Value) then
              return false
            end
          end
          return true
        end
        if trail and trail.Enabled and target and ordinary and not equal(target.Color, ordinary.Color) then
          local own, other = equal(trail.Color, target.Color), equal(trail.Color, ordinary.Color)
          signals[#signals + 1] = { name = "character.PlayerBallHighlight", available = own or other, targeted = own }
        end
      end
    end
    return { signals = signals, serverTime = serverTime, receivedAt = receivedAt, serverNow = serverNow, training = true }
  end
  return resolver
end
function Targeting.createParryTracker()
  local tracker = { epoch = 0, floor = -math.huge }
  local sources = {
    ["sync.TargetPlayerID"] = 1,
    ["sync.HighlightTargetPlayerID"] = 2,
    ["replicator.IsLocalTarget"] = 3,
    ["workspace.GameBallTarget"] = 4,
    ["ball.targetColor"] = 5,
    ["character.PlayerBallHighlight"] = 6,
  }

  local slots = {}
  for index = 1, 6 do
    slots[index] = {}
  end
  local serial, cutoff, episode, strong = 0, -math.huge, nil, false
  function tracker.reset()
    serial, cutoff, episode, strong = 0, -math.huge, nil, false
    tracker.floor = -math.huge
    tracker.epoch += 1
    for _, slot in ipairs(slots) do
      table.clear(slot)
    end
  end
  function tracker.rearm(floor)
    serial += 1
    cutoff, episode, strong = serial, nil, false
    tracker.floor = math.max(tracker.floor, floor or -math.huge)
    for index = 1, 3 do
      table.clear(slots[index])
    end
  end
  function tracker.observe(report, now, frame, ping)
    if type(report) ~= "table" then
      return
    end
    tracker.training = report.training == true
    for _, signal in ipairs(report.signals or {}) do
      local index = sources[signal.name]
      if index then
        local slot, weak = slots[index], index >= 5
        local available = signal.available and not (index == 3 and report.apProviderSuppressed)
        local value = available and signal.targeted
        local at = index <= 3 and report.receivedAt or now
        local serverTime = index <= 3 and report.serverTime or (report.serverNow and report.serverNow - (ping or 0) - 0.02)
        if
          not available
          or type(value) ~= "boolean"
          or not finite(at)
          or (
            index <= 3
            and (
              not finite(serverTime)
              or serverTime < tracker.floor
              or (finite(report.serverNow) and (report.serverNow - serverTime < -0.02 or report.serverNow - serverTime > (report.training and 0.6 or 0.25)))
            )
          )
        then
          slot.pending, slot.at = nil, -math.huge
        else
          local accepted = true
          if weak then
            if slot.pending ~= value then
              serial += 1
              slot.pending, slot.frame, slot.count, slot.pendingOrder = value, frame, 1, serial
              accepted = false
            else
              if slot.frame ~= frame then
                slot.frame, slot.count = frame, (slot.count or 0) + 1
              end
              accepted = (slot.count or 0) >= 2
            end
          end
          if accepted then
            slot.at = at
            if value ~= slot.value then
              local old, oldEntry = slot.value, slot.entry
              serial += 1
              slot.value, slot.entry = value, weak and value and slot.pendingOrder or serial
              slot.serverTime = serverTime
              if value == false and old == true and episode and oldEntry >= episode and not (weak and strong) then
                cutoff, episode, strong = serial, nil, false
                tracker.floor = math.max(tracker.floor, serverTime or -math.huge)
              end
            end
          end
        end
      end
    end
  end
  function tracker.resolve(now)
    local oldest, selected
    for index, slot in ipairs(slots) do
      local lifetime = index == 4 and math.huge or (index >= 5 and 0.1 or (tracker.training and 0.6 or 0.25))
      if slot.value == true and slot.entry >= cutoff and slot.at and now >= slot.at and now - slot.at <= lifetime then
        if index < 5 then
          strong = true
        end
        if not oldest or slot.entry < oldest then
          oldest, selected = slot.entry, index
        end
      end
    end
    if not selected then
      return false, tracker.epoch
    end
    if not episode then
      episode = oldest
      tracker.epoch += 1
      tracker.floor = math.max(tracker.floor, slots[selected].serverTime or -math.huge)
    end
    return true, tracker.epoch
  end
  tracker.reset()
  return tracker
end
Targeting.__contract = {
  access = { default = "internal.read" },
  provides = { "setup", "create", "createParryTracker" },
  requires = {},
}

return Targeting
