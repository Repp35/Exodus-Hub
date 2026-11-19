-- [[ targeting ]]

-- code
local Targeting = {}
function Targeting.setup() return true end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Targeting.create(deps)
  local resolver = {}
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
    add("replicator.IsLocalTarget", "network", function()
      if freshProvider() and type(provider.IsLocalTarget) == "function" then return provider:IsLocalTarget() end
    end)
    add("workspace.GameBallTarget", "attribute", function() return context.world:GetAttribute("GameBallTarget") end)
    add("ball.targetColor", "visual", function()
      local ball = context.ball
      if not ball or not ball:IsA("BasePart") or ball.Transparency == 1 or ball.LocalTransparencyModifier == 1 then return nil end
      local color = ball.Color
      local red = Color3.fromRGB(202, 56, 30)
      local function same(a, b) return math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005 end
      local normal = ball:GetAttribute("SkinNormalColor")
      if typeof(normal) == "Color3" and same(normal, red) then return nil end
      if same(color, red) then return true end
      if same(color, typeof(normal) == "Color3" and normal or Color3.fromRGB(153, 153, 153)) then return false end
      return nil
    end)
    local function validId(id) return finite(id) and id > 0 and id % 1 == 0 and id or nil end
    local packet = freshSync() and sync and validId(sync.TargetPlayerID) or nil
    local ok, attribute = pcall(function() return context.world:GetAttribute("GameBallTarget") end)
    attribute = ok and validId(attribute) or nil; local selected = packet or attribute
    report.conflict = packet ~= nil and attribute ~= nil and packet ~= attribute
    if context.active == false then selected = nil; report.conflict = false end
    if report.conflict then report.targeted, report.known, report.targetId, report.source = false, false, -1, "target_transition"; return report end
    if selected then
      report.targetId, report.targeted, report.known = selected, selected == me, true; report.source = packet and "sync.target" or "workspace.GameBallTarget"
      return report
    end
    local highlighted, multiple
    for _, player in ipairs(context.players and context.players:GetPlayers() or {}) do
      local character = player.Character; local mark = character and character:FindFirstChild("PlayerBallHighlight")
      if mark and mark.Enabled then
        if highlighted then multiple = true end
        highlighted = player.UserId
      end
    end
    local redBall = false
    for _, signal in ipairs(report.signals) do
      if signal.name == "ball.targetColor" and signal.targeted then redBall = true end
    end
    report.targeted = not multiple and highlighted == me and redBall; report.known = not multiple and highlighted ~= nil and (highlighted ~= me or redBall)
    report.targetId = report.known and highlighted or -1; report.source = report.known and "visual.highlight_and_ball" or "unavailable"
    return report
  end
  return resolver
end
Targeting.__contract = { provides = { "setup", "create" }, requires = {} }

return Targeting
