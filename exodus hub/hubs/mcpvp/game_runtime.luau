-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
function Runtime.setup() return true end
function Runtime.bind(loaded)
  loaded.mcpcoordinator.start()
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    resetState = function() loaded.mcpcoordinator.reset() end,
    updateBlockers = { function() return loaded.mcpcoordinator.busy() end },
    readouts = {},
  }
end
Runtime.__contract = { provides = { "setup", "bind", "createAPI" }, requires = { "gameui", "mcpcoordinator" } }
return Runtime
