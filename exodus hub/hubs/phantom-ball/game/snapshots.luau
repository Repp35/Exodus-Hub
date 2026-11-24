-- [[ ball snapshot sampling ]]
--!optimize 2

-- code
local Snapshots = {}
function Snapshots.setup() return true end
function Snapshots.create(deps)
  local builder = { cachedAt = -math.huge }
  local sampledBall, sampledPosition, sampledAt, measuredVelocity, movedAt
  local finite = deps.utils.isFiniteNumber
  local CONFIG = deps.config
  local function child(parent, name) return parent and parent:FindFirstChild(name) end
  function builder.get(time)
    local utils, world, players = deps.utils, deps.world, deps.players
    local trainingState = deps.getTrainingState()
    time = finite(time) and time or utils.now()
    if
      builder.cached
      and builder.cached.ball
      and builder.cached.ball.Parent
      and time >= builder.cachedAt
      and (deps.inEvaluation() or time - builder.cachedAt < CONFIG.SNAPSHOT_CACHE_INTERVAL)
    then
      return builder.cached
    end
    if deps.inTrainingArea() then
      local sample = trainingState
      local model = child(child(child(world, "Training"), "TrainingClient"), "TrainingBall")
      if not sample or time < sample.receivedAt or time - sample.receivedAt > 0.6 or not model or not model:IsA("BasePart") or not model.Parent then
        return nil
      end
      local age = math.clamp(world:GetServerTimeNow() - sample.serverTime, 0, 0.25)
      local target = finite(sample.goal) and sample.goal > 0 and sample.goal or -1
      local result = {
        schema = 2,
        mode = "training",
        ball = model,
        position = sample.position + sample.velocity * age,
        velocity = sample.velocity,
        speed = sample.velocity.Magnitude,
        syncSpeed = sample.speed,
        targetId = target,
        targeted = players.LocalPlayer ~= nil and target == players.LocalPlayer.UserId,
        targetUncertain = false,
        teleported = false,
        locked = false,
        grace = false,
        syncAt = sample.receivedAt,
        serverTime = sample.serverTime,
        syncSequence = sample.sequence,
        trainingRound = sample.round,
        trainingParryAt = deps.getTrainingParryAt(),
        targetSignals = deps.getTrainingSignals(model, sample.goal, players.LocalPlayer.UserId, sample.serverTime, sample.receivedAt, world:GetServerTimeNow()),
      }

      builder.cached, builder.cachedAt = result, time
      return result
    end
    local currentBall = deps.getBall()
    if not currentBall then
      return nil
    end
    local provider = deps.getReplicator()
    local position, velocity, sync = currentBall.Position, currentBall.AssemblyLinearVelocity, deps.syncData(provider or false)
    local targetReport = deps.resolveTarget(time, provider, sync, currentBall)
    local syncReceivedAt = deps.getReceivedAt()
    local syncFresh = syncReceivedAt > 0 and time >= syncReceivedAt and time - syncReceivedAt <= CONFIG.PACKET_AGE
    if not syncFresh then
      sync = nil
      syncReceivedAt = nil
    end
    local target = targetReport.targetId
    local frozen = deps.getBallFrozen() == true
    if sampledBall ~= currentBall or (sync and sync.Teleported == true) then
      sampledBall, sampledPosition, sampledAt, measuredVelocity, movedAt = currentBall, position, time, Vector3.zero, nil
    elseif sampledPosition and sampledAt and time - sampledAt >= CONFIG.SAMPLE_INTERVAL then
      local elapsed = time - sampledAt
      local displacement = position - sampledPosition
      if displacement.Magnitude > 0.001 then
        local measured, expected = displacement / elapsed, sync and tonumber(sync.Speed)
        if elapsed <= CONFIG.SAMPLE_MAX_GAP and (not expected or expected <= 0 or measured.Magnitude <= expected * 2.5 + 30) then
          measuredVelocity, movedAt = measured, time
        else
          measuredVelocity, movedAt = Vector3.zero, nil
        end
      elseif movedAt and time - movedAt > 0.1 then
        measuredVelocity = Vector3.zero
      end
      sampledPosition, sampledAt = position, time
    end
    if typeof(velocity) ~= "Vector3" or velocity.Magnitude < 0.1 then
      velocity = measuredVelocity or Vector3.zero
    end
    local result = {
      schema = 2,
      generatedAt = time,
      valid = true,
      ball = currentBall,
      ballValid = true,
      position = position,
      velocity = velocity,
      speed = velocity.Magnitude,
      syncSpeed = sync and sync.Speed or nil,
      realPosition = sync and sync.RealPosition or nil,
      syncDirection = sync and sync.ForcedDirection or nil,
      syncAcceleration = sync and sync.Accel or nil,
      syncMaxSpeed = sync and sync.MaxSpeed or nil,
      targetId = target,
      targeted = players.LocalPlayer ~= nil and target == players.LocalPlayer.UserId,
      targetSource = targetReport.source or "unavailable",
      targetSignals = targetReport,
      exchangeTargetId = sync and sync.TargetPlayerID or -1,
      targetUncertain = not targetReport.known,
      teleported = sync and sync.Teleported == true or false,
      locked = sync and sync.Locked == true or false,
      ballCanMove = not frozen and not (sync and sync.Locked == true),
      frozen = frozen,
      grace = sync and sync.Grace == true or false,
      oldGrace = sync and sync.OldGrace == true or false,
      syncAt = syncReceivedAt,
      serverTime = sync and sync.ServerTime or nil,
      syncSequence = deps.syncSequence(sync, provider),
      syncVersion = deps.getVersion(),
      highlightTargetId = sync and sync.HighlightTargetPlayerID,
    }

    builder.cached, builder.cachedAt = result, time
    return result
  end
  function builder.invalidate()
    builder.cached, builder.cachedAt = nil, -math.huge
  end
  return builder
end
Snapshots.__contract = { requires = {}, provides = { "setup", "create" } }

return Snapshots
