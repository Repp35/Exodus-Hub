-- [[ read-only information page ]]
--!optimize 2
-- @modules uidetails

local Details = {}
function Details.setup() return true end
function Details.create(context)
  local reported = {}
  local labels = { session = "Sessão", game = "Jogo", server = "Servidor", versions = "Versões", developers = "Desenvolvedores" }
  local function report(key, reason)
    local id = tostring(key) .. ":" .. tostring(reason)
    if reported[id] then
      return
    end
    reported[id] = true
    context.deps.Utils.recordError("Information." .. tostring(key), reason)
    context.notifications.toast(tostring(reason), true)
  end
  local function refresh()
    local ok, values, errors = pcall(context.deps.Information.snapshot)
    if not ok or type(values) ~= "table" then
      report("snapshot", "Informações: falha ao consultar os dados.")
      values = { session = "Erro: falha ao consultar as informações." }
    end
    for _, key in ipairs({ "session", "game", "server", "versions", "developers" }) do
      local rendered, reason = pcall(context.pages.setReadout, key, values[key])
      if not rendered then
        report(key, "Falha ao exibir " .. labels[key] .. ".")
        warn(tostring(reason))
      end
    end
    context.pages.refresh()
    if context.state.panelOpen and context.pages.state().id == "information" then
      for key, reason in pairs(type(errors) == "table" and errors or {}) do
        report(key, reason)
      end
    end
  end
  refresh()
  local elapsed = 0
  context.trackConn(context.services.RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed >= 0.5 and context.state.panelOpen and context.pages.state().id == "information" then
      elapsed = 0
      refresh()
    end
  end))
  return {}
end
Details.__contract = { provides = { "setup", "create" }, requires = {} }
return Details
