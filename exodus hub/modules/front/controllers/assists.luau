-- [[ assists ]]

-- code
local Controller = {}
function Controller.setup() return true end
function Controller.create() return {} end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
