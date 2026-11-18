-- [[ targeting ]]

-- code
local Targeting = {}
function Targeting.setup() return true end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function child(object, name) return object and object:FindFirstChild(name) end
local function sameColor(a, b)
  return typeof(a) == "Color3" and typeof(b) == "Color3" and math.abs(a.R - b.R) < 1 / 510 and math.abs(a.G - b.G) < 1 / 510 and math.abs(a.B - b.B) < 1 / 510
end
local function sameSequence(a, b)
  if typeof(a) ~= "ColorSequence" or typeof(b) ~= "ColorSequence" or #a.Keypoints ~= #b.Keypoints then return false end
  for index, key in ipairs(a.Keypoints) do
    local other = b.Keypoints[index]
    if math.abs(key.Time - other.Time) > 0.001 or not sameColor(key.Value, other.Value) then return false end
  end
  return true
end
function Targeting.create(deps)
  local resolver = {}
  local skinId, skinModule, skinData
  local red = Color3.fromRGB(202, 56, 30); local arrowRed, white = Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 255, 255)
  local function skin(ball)
    local id = ball:GetAttribute("BallSkin")
    if id ~= skinId then skinId, skinModule, skinData = id, nil, nil end
    if type(id) ~= "string" then return nil end
    local module = child(child(child(deps.storage(), "Inventory"), "BallSkins"), id)
    if module and module ~= skinModule then
      skinModule = module
      task.defer(function()
        local ok, data = pcall(require, module)
        if skinModule == module and skinId == id then skinData = ok and type(data) == "table" and data or nil end
      end)
    end
    return skinData
  end
  function resolver.resolve(context)
    local me = context.player and context.player.UserId; local report = { mode = "match", targeted = false, known = false, targetId = -1, conflict = false, positive = {}, signals = {} }
    local negative, fallback, fallbackSource, firstKnown = false, nil, nil, nil
    local function add(name, family, read)
      local signal = { name = name, family = family, available = false, state = "unavailable" }; report.signals[#report.signals + 1] = signal
      if context.active == false then signal.reason = "round_inactive"; return end
      local ok, value, reason = pcall(read)
      if not ok then signal.reason = "read_failed"; return end
      signal.reason = reason
      if finite(value) and value % 1 == 0 then
        signal.targetId, signal.targeted = value, value > 0 and value == me
      elseif type(value) == "boolean" then
        signal.targeted = value
        if value then signal.targetId = me end
      else
        return
      end
      signal.available, signal.state, report.known = true, signal.targeted and "yes" or "no", true; firstKnown = firstKnown or name
      if signal.targetId and signal.targetId > 0 and not fallback then fallback, fallbackSource = signal.targetId, name end
      if signal.targeted then report.targeted = true; report.positive[#report.positive + 1] = name else negative = true end
    end
    local sync, provider = context.sync, context.provider
    local function freshSync() return context.syncFresh == true end
    local history = provider and provider.history; local latest = type(history) == "table" and history[#history]
    local function freshProvider()
      if not provider or provider.hasState ~= true then return false end
      if finite(context.sequence) and finite(provider.lastSeq) then
        local delta = (context.sequence - provider.lastSeq) % 65536
        if delta > 0 and delta < 32768 then return false end
      end
      if latest and finite(latest.serverTime) and finite(context.serverNow) then local age = context.serverNow - latest.serverTime; return age >= -0.02 and age <= context.maxAge end
      return freshSync()
    end
    local function syncField(name)
      if freshSync() then return sync and sync[name] end
      return nil, "stale_sync"
    end
    local function providerField(name)
      if freshProvider() then return provider.syncData and provider.syncData[name] end
      return nil, "stale_replicator"
    end
    add("sync.target", "network", function() return syncField("TargetPlayerID") end)
    add("sync.highlight", "network", function() return syncField("HighlightTargetPlayerID") end)
    add("replicator.target", "network", function() return providerField("TargetPlayerID") end)
    add("replicator.highlight", "network", function() return providerField("HighlightTargetPlayerID") end)
    add("replicator.latestTargetId", "network", function()
      if freshProvider() then return provider.latestTargetId end
      return nil, "stale_replicator"
    end)
    add("replicator.IsLocalTarget", "network", function()
      if freshProvider() and type(provider.IsLocalTarget) == "function" then return provider:IsLocalTarget() end
    end)
    add("history.target", "network", function()
      if freshProvider() and latest and latest.seq == provider.lastSeq then return latest.targetId end
    end)
    add("history.highlight", "network", function()
      if freshProvider() and latest and latest.seq == provider.lastSeq then return latest.highlightId end
    end)
    add("workspace.GameBallTarget", "attribute", function() return context.world:GetAttribute("GameBallTarget") end)
    add("character.PlayerBallHighlight", "visual", function()
      local people = context.players:GetPlayers()
      local other
      for _, player in ipairs(people) do
        local highlight = child(player.Character, "PlayerBallHighlight")
        if highlight and highlight:IsA("Highlight") and highlight.Enabled then
          local adornee = highlight.Adornee or highlight.Parent
          for _, owner in ipairs(people) do
            local character = owner.Character
            if character and (adornee == character or (adornee and adornee:IsDescendantOf(character))) then
              if owner.UserId == me then return me end
              other = other or owner.UserId
            end
          end
        end
      end
      return other
    end)
    local ball = context.ball
    local function visibleBall() return ball and ball.Parent and ball.Transparency < 1 and ball.LocalTransparencyModifier < 1 end
    add("ball.color", "visual", function()
      if not visibleBall() then return nil, "ball_hidden" end
      local normal = ball:GetAttribute("SkinNormalColor")
      if sameColor(normal, red) then return nil, "ambiguous_skin_color" end
      if sameColor(ball.Color, red) then return true end
      if sameColor(ball.Color, normal) or sameColor(ball.Color, Color3.fromRGB(153, 153, 153)) then return false end
      return nil, "unrecognized_color"
    end)
    add("ball.trail", "visual", function()
      if not visibleBall() then return nil, "ball_hidden" end
      local trails = child(ball, "Trails"); local current, target, normal = child(trails, "BallTrail"), child(trails, "BallTrailTarget"), child(trails, "BallTrail2")
      if not current or not target or not normal or not current.Enabled then return nil, "trail_unavailable" end
      if sameSequence(target.Color, normal.Color) then return nil, "ambiguous_trail" end
      if sameSequence(current.Color, target.Color) then return true end
      if sameSequence(current.Color, normal.Color) then return false end
    end)
    add("ui.BallIndicator", "visual", function()
      local gui = child(context.player, "PlayerGui"); local indicator = child(child(child(gui, "Interface"), "BallIndicatorUI"), "Indicator")
      if not indicator then return nil, "indicator_missing" end
      local ancestor = indicator
      while ancestor and ancestor ~= gui do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return nil, "indicator_hidden" end
        if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return nil, "indicator_hidden" end
        ancestor = ancestor.Parent
      end
      if sameColor(indicator.ImageColor3, arrowRed) then return true end
      if sameColor(indicator.ImageColor3, white) then return false end
    end)
    add("ball.skinFace", "visual", function()
      if not visibleBall() then return nil, "ball_hidden" end
      local face = child(ball, "SkinFace"); local decal = face and face:FindFirstChildOfClass("Decal")
      if not decal or decal.Transparency >= 1 then return nil, "face_hidden" end
      local data = skin(ball); local faces = data and data.Faces
      if type(faces) ~= "table" then return nil, "skin_unavailable" end
      local texture = decal.Texture; local targetFace = false
      for name, asset in pairs(faces) do
        if asset == texture then
          if name == "serious_1" or name == "evil" or name == "crazy" or name == "crazy_talking" then targetFace = true else return nil, "transient_or_ambiguous_face" end
        end
      end
      if targetFace then return true end
    end)
    report.conflict = report.targeted and negative; report.targetId = report.targeted and me or fallback or -1
    report.source = report.positive[1] or fallbackSource or firstKnown; return report
  end
  return resolver
end
Targeting.__contract = { provides = { "setup", "create" }, requires = {} }

return Targeting
