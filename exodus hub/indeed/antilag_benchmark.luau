-- [[ anti lag benchmark ]]

-- manual-validation

return function(options)
  options = options or {}; local duration = math.clamp(tonumber(options.duration) or 30, 10, 60)
  local warmup = math.clamp(tonumber(options.warmup) or 5, 0, 30); local runService, players = game:GetService("RunService"), game:GetService("Players")
  local stats, http = game:GetService("Stats"), game:GetService("HttpService")
  local function memory()
    local ok, value = pcall(function() return stats:GetTotalMemoryUsageMb() end)
    return if ok then value else nil
  end
  local function status()
    local modules = _G.ExodusModules; local antiLag = modules and modules.antilag
    return antiLag and antiLag.getStatus() or nil
  end
  task.wait(warmup); local frames, sum, worst, over33, over50 = table.create(8192), 0, 0, 0, 0
  local memoryStart, playersStart, optimizerStart = memory(), #players:GetPlayers(), status()
  local connection = runService.RenderStepped:Connect(function(dt)
    if dt <= 0 or #frames >= 65536 then return end
    frames[#frames + 1] = dt; sum += dt
    worst = math.max(worst, dt)
    if dt > 1 / 30 then over33 += 1 end
    if dt > 0.05 then over50 += 1 end
  end)
  task.delay(duration + 1, function() connection:Disconnect() end)
  task.wait(duration); connection:Disconnect()
  table.sort(frames)
  local function percentile(fraction) return (#frames > 0 and frames[math.clamp(math.ceil(#frames * fraction), 1, #frames)] or 0) * 1000 end
  local report = {
    label = tostring(options.label or "AntiLag"),
    revision = _G.Exodus and _G.Exodus.Revision or nil,
    duration = duration,
    samples = #frames,
    playersStart = playersStart,
    playersEnd = #players:GetPlayers(),
    averageFPS = if sum > 0 then #frames / sum else 0,
    frameMs = {
      p50 = percentile(0.5),
      p95 = percentile(0.95),
      p99 = percentile(0.99),
      worst = worst * 1000,
    },
    framesOver33ms = over33,
    framesOver50ms = over50,
    memoryMBStart = memoryStart,
    memoryMBEnd = memory(),
    optimizerStart = optimizerStart,
    optimizerEnd = status(),
  }

  print("[Exodus AntiLag benchmark] " .. http:JSONEncode(report)); return report
end
