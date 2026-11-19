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
      if not ball or not ball:IsA("BasePart") then return nil end
      local color = ball.Color
      local red = Color3.fromRGB(202, 56, 30)
      local function same(a, b) return math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005 end
      local normal = ball:GetAttribute("SkinNormalColor")
      if typeof(normal) == "Color3" and same(normal, red) then return nil end
      if same(color, red) then return true end
      if same(color, typeof(normal) == "Color3" and normal or Color3.fromRGB(153, 153, 153)) then return false end
      return nil
    end)
    report.conflict = report.targeted and negative; report.targetId = report.targeted and me or fallback or -1
    report.source = report.positive[1] or fallbackSource or firstKnown; return report
  end
  return resolver
end
Targeting.__contract = { provides = { "setup", "create" }, requires = {} }

return Targeting
