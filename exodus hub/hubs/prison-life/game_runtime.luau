-- [[ Prison Life runtime ]]
--!optimize 2
local Runtime = {}
function Runtime.setup() return true end
function Runtime.bind() return { mode = "prison-life" } end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    createActions = function()
      return {
        callbacks = {
          prisonTimeRestart = loaded.localclock.restart,
          prisonTimeDay = function() return loaded.localclock.setPreset("day") end,
          prisonTimeNight = function() return loaded.localclock.setPreset("night") end,
        },
      }
    end,
  }
end
Runtime.__contract = { provides = { "setup", "bind", "createAPI" }, requires = {} }
return Runtime
