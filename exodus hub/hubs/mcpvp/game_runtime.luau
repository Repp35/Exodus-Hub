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
    readouts = {
      {
        id = "mcpvp_status",
        key = "MCEnabled",
        anchor = Vector2.new(0, 0.5),
        position = UDim2.new(0, 0, 0.5, 0),
        read = function() return loaded.mcpcoordinator.state() end,
      },
    },
  }
end
Runtime.__contract = { provides = { "setup", "bind", "createAPI" }, requires = { "gameui", "mcpcoordinator" } }
return Runtime
