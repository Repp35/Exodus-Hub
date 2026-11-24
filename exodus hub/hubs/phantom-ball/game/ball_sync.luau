-- [[ ballsync ]]

-- code
local BallSync = {}
function BallSync.setup() return true end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function validBallSpeed(value) return finite(value) and value >= 0 and value <= 1000 end
local function finiteVector(value) return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z) end
function BallSync.create(deps)
  local Sync = {}
  local getReplicator, invalidateSnapshotCache = deps.getReplicator, deps.invalidateSnapshotCache
  local CONFIG = { PACKET_AGE = deps.packetAge }
  local lastSync, packet, packetAt, syncReceivedAt = nil, nil, 0, 0
  local receivedSequence
  local version, lastServerTime = 0, nil
  local nativeEntry
  local function syncData(provider)
    if provider == nil then
      provider = getReplicator()
    end
    if packet and os.clock() - packetAt > CONFIG.PACKET_AGE then
      packet = nil
    end
    if packet then
      local sequence = provider and provider.hasState == true and provider.lastSeq
      if type(sequence) ~= "number" or (packet.Sequence ~= sequence and (packet.Sequence - sequence) % 65536 < 32768) then
        return packet
      end
      packet = nil
    end
    local sequence = provider and provider.hasState == true and provider.lastSeq
    if lastSync and receivedSequence and (not finite(sequence) or (receivedSequence ~= sequence and (receivedSequence - sequence) % 65536 < 32768)) then
      return lastSync
    end
    local data = provider and provider.hasState == true and provider.syncData or lastSync
    if type(data) ~= "table" then
      data = provider and provider.syncData
    end
    return type(data) == "table" and data or nil
  end
  local function syncSequence(current, provider)
    if packet and current == packet then
      return packet.Sequence
    end
    local sequence = provider and provider.hasState == true and provider.lastSeq or nil
    if not finite(sequence) then
      return receivedSequence
    end
    if receivedSequence and (receivedSequence - sequence) % 65536 < 32768 then
      return receivedSequence
    end
    return sequence
  end
  function Sync.applyPacket(value)
    if type(value) ~= "table" then
      return false
    end
    if value.Speed ~= nil and not validBallSpeed(value.Speed) then
      return false
    end
    if value.MaxSpeed ~= nil and not validBallSpeed(value.MaxSpeed) then
      return false
    end
    if value.RealPosition ~= nil and not finiteVector(value.RealPosition) then
      return false
    end
    if value.ServerTime ~= nil and (not finite(value.ServerTime) or (lastServerTime and value.ServerTime < lastServerTime)) then
      return false
    end
    local sequence = value.Sequence
    if not finite(sequence) or sequence < 0 or sequence >= 65536 or sequence % 1 ~= 0 then
      return false
    end
    if receivedSequence ~= nil then
      local delta = (sequence - receivedSequence) % 65536
      if delta == 0 or delta >= 32768 then
        return false
      end
    end
    local provider = getReplicator()
    local previous = provider and provider.hasState == true and provider.lastSeq
    if finite(previous) and (sequence - previous) % 65536 >= 32768 then
      return false
    end
    packet, packetAt = table.clone(value), os.clock()
    syncReceivedAt = packetAt
    receivedSequence, lastSync = sequence, packet
    lastServerTime = value.ServerTime or lastServerTime
    version += 1
    invalidateSnapshotCache()
    return true
  end
  local function decodeBallPacketFallback(value)
    if typeof(value) ~= "buffer" or buffer.len(value) < 92 then
      return nil
    end
    local flags = buffer.readu8(value, 0)
    local serverTime = buffer.readf64(value, 3)
    local x, y, z = buffer.readf32(value, 11), buffer.readf32(value, 15), buffer.readf32(value, 19)
    local dx, dy, dz = buffer.readf32(value, 23), buffer.readf32(value, 27), buffer.readf32(value, 31)
    local speed, accel, maximum = buffer.readf32(value, 35), buffer.readf32(value, 39), buffer.readf32(value, 43)
    local curve, curveMax = buffer.readf32(value, 47), buffer.readf32(value, 51)
    local target, highlight, possessor = buffer.readf64(value, 55), buffer.readf64(value, 63), buffer.readf64(value, 83)
    if
      not finite(serverTime)
      or not finite(x)
      or not finite(y)
      or not finite(z)
      or not finite(dx)
      or not finite(dy)
      or not finite(dz)
      or not validBallSpeed(speed)
      or not finite(accel)
      or not validBallSpeed(maximum)
      or not finite(curve)
      or curve < 0
      or not finite(curveMax)
      or curveMax < 0
      or not finite(target)
      or not finite(highlight)
      or not finite(possessor)
    then
      return nil
    end
    return {
      seq = buffer.readu16(value, 1),
      serverTime = serverTime,
      position = Vector3.new(x, y, z),
      direction = Vector3.new(dx, dy, dz),
      speed = speed,
      accel = accel,
      maxSpeed = maximum,
      targetId = target,
      highlightId = highlight,
      possessorId = possessor,
      teleported = bit32.btest(flags, 1),
      locked = bit32.btest(flags, 2),
      grace = bit32.btest(flags, 4),
      oldGrace = bit32.btest(flags, 8),
      possessed = bit32.btest(flags, 32),
      forceDirection = bit32.btest(flags, 16),
      curveTime = curve,
      curveTimeMax = curveMax,
      curveAxis = Vector3.new(buffer.readf32(value, 71), buffer.readf32(value, 75), buffer.readf32(value, 79)),
      bouncesLeft = buffer.readu8(value, 91),
      flightTime = buffer.len(value) >= 96 and buffer.readf32(value, 92) or nil,
      noSpeedFeel = bit32.btest(flags, 128),
    }
  end
  function Sync.decodeBallPacket(value)
    local ok, provider = pcall(getReplicator)
    local decoded
    if ok and provider and type(provider.Decode) == "function" then
      local success, result = pcall(provider.Decode, provider, value)
      if success then
        decoded = result
      else
        decoded = decodeBallPacketFallback(value)
      end
    else
      decoded = decodeBallPacketFallback(value)
    end
    if type(decoded) ~= "table" then
      decoded = decodeBallPacketFallback(value)
    end
    if type(decoded) ~= "table" then
      return nil
    end
    if not finiteVector(decoded.position) or not finiteVector(decoded.direction) or not validBallSpeed(decoded.speed) then
      return nil
    end
    if decoded.maxSpeed ~= nil and not validBallSpeed(decoded.maxSpeed) then
      return nil
    end
    return {
      Sequence = decoded.seq,
      ServerTime = decoded.serverTime,
      TeleportSequence = decoded.seq,
      Teleported = decoded.teleported,
      Locked = decoded.locked,
      Grace = decoded.grace,
      OldGrace = decoded.oldGrace,
      TargetPlayerID = decoded.targetId,
      HighlightTargetPlayerID = decoded.highlightId,
      PossessorId = decoded.possessed and decoded.possessorId or 0,
      RealPosition = decoded.position,
      ForcedDirection = decoded.direction,
      Speed = decoded.speed,
      Accel = decoded.accel,
      MaxSpeed = decoded.maxSpeed,
      ForceDirection = decoded.forceDirection,
      CurveTime = decoded.curveTime,
      CurveTimeMax = decoded.curveTimeMax,
      CurveAxis = decoded.curveAxis,
      BouncesLeft = decoded.bouncesLeft,
      FlightTime = decoded.flightTime,
      NoSpeedFeel = decoded.noSpeedFeel,
    }
  end
  function Sync.applySync(value)
    local explicit = value ~= nil
    if type(value) == "table" and type(value.syncData) == "table" then
      value = value.syncData
    end
    local provider = getReplicator()
    if type(value) ~= "table" then
      value = provider and provider.syncData
    end
    if type(value) ~= "table" then
      return nil
    end
    if value.Speed ~= nil and not validBallSpeed(value.Speed) then
      return nil
    end
    if value.MaxSpeed ~= nil and not validBallSpeed(value.MaxSpeed) then
      return nil
    end
    if value.RealPosition ~= nil and not finiteVector(value.RealPosition) then
      return nil
    end
    if value.Sequence ~= nil and not finite(value.Sequence) then
      return nil
    end
    if value.ServerTime ~= nil and (not finite(value.ServerTime) or (lastServerTime and value.ServerTime < lastServerTime)) then
      return nil
    end
    local sequence = value.Sequence or (provider and provider.hasState == true and provider.lastSeq)
    if finite(sequence) then
      if sequence < 0 or sequence >= 65536 or sequence % 1 ~= 0 then
        return nil
      end
      if receivedSequence ~= nil then
        local delta = (sequence - receivedSequence) % 65536
        if delta >= 32768 then
          return nil
        end
        if delta == 0 then
          return nil
        end
      end
      receivedSequence = sequence
    elseif not explicit then
      return syncData(provider)
    end
    lastSync, packet, syncReceivedAt = table.clone(value), nil, os.clock()
    if finite(sequence) then
      lastSync.Sequence = sequence
    end
    lastServerTime = value.ServerTime or lastServerTime
    version += 1
    invalidateSnapshotCache()
    return lastSync
  end
  local function detachNative()
    local entry = nativeEntry
    nativeEntry = nil
    if not entry then
      return
    end
    entry.active, entry.handler, entry.serverNow, entry.report = false, nil, nil, nil
    if entry.provider.ApplySnapshot == entry.wrapper then
      entry.provider.ApplySnapshot = entry.original
    end
  end
  function Sync.bindNative(handler)
    local provider = getReplicator()
    if nativeEntry and nativeEntry.provider == provider then
      nativeEntry.handler = handler
      return true
    end
    detachNative()
    if not provider or type(provider.ApplySnapshot) ~= "function" then
      return false
    end
    local entry = { provider = provider, original = provider.ApplySnapshot, active = true, handler = handler, serverNow = deps.serverNow, report = deps.report }
    local function freshNative(sample)
      if type(sample) ~= "table" or not finite(sample.serverTime) then
        return false
      end
      local now = entry.serverNow and entry.serverNow()
      return finite(now) and now - sample.serverTime >= -0.02 and now - sample.serverTime <= 0.25
    end
    local function receive(sample, ...)
      if
        entry.active
        and entry.handler
        and freshNative(sample)
        and finite(sample.serverTime)
        and finiteVector(sample.position)
        and validBallSpeed(sample.speed)
        and (sample.direction == nil or finiteVector(sample.direction))
      then
        local packet = {
          Sequence = sample.seq,
          ServerTime = sample.serverTime,
          RealPosition = sample.position,
          ForcedDirection = sample.direction,
          Speed = sample.speed,
          TargetPlayerID = sample.targetId,
          HighlightTargetPlayerID = sample.highlightId,
          MaxSpeed = sample.maxSpeed,
          Accel = sample.accel,
          Teleported = sample.teleported,
          Locked = sample.locked,
          Grace = sample.grace,
          OldGrace = sample.oldGrace,
          PossessorId = sample.possessed and (sample.possessorId or 1) or 0,
          CurveTime = sample.curveTime,
          CurveTimeMax = sample.curveTimeMax,
          CurveAxis = sample.curveAxis,
          BouncesLeft = sample.bouncesLeft,
          FlightTime = sample.flightTime,
          NoSpeedFeel = sample.noSpeedFeel,
        }

        local ok, detail = pcall(entry.handler, packet)
        if not ok and entry.report then
          entry.report(detail)
        end
      end
      return ...
    end
    entry.wrapper = function(self, sample, ...) return receive(sample, entry.original(self, sample, ...)) end
    provider.ApplySnapshot = entry.wrapper
    nativeEntry = entry
    local history = provider.history
    local latest = type(history) == "table" and history[#history]
    if latest then
      receive(latest)
    end
    return true
  end
  function Sync.destroy() detachNative() end
  function Sync.getVersion() return version end
  Sync.getData = syncData
  Sync.getSequence = syncSequence
  function Sync.getReceivedAt() return syncReceivedAt end
  return Sync
end
BallSync.__contract = { provides = { "setup", "create" }, requires = {} }

return BallSync
