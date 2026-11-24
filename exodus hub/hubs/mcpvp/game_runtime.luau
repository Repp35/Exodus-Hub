-- [[ gameruntime ]]
--!optimize 2

local Runtime = {}

function Runtime.setup() return true end

function Runtime.bind() return { mode = "mcpvp" } end

function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
  }
end

Runtime.__contract = { provides = { "setup", "bind", "createAPI" }, requires = { "gameui" } }

return Runtime
