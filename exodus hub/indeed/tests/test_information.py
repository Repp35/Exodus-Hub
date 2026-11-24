"""Information sources, optional fields and server-only geolocation."""
import unittest
import test_ui_layout as layout


class InformationTests(unittest.TestCase):
    def run_luau(self, modules, body):
        layout.UILayout.run_luau(self, modules, body)

    def test_location_uses_current_peer_and_handles_provider_failure(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Location': 'core/server_location.luau'}, r'''
local timers, pending, calls = {}, {}, {}
task.delay = function(_, callback) timers[#timers + 1] = callback end
task.spawn = function(callback) pending[#pending + 1] = callback end
local function drain()
  while #pending > 0 do local current = pending; pending = {}; for _, callback in ipairs(current) do callback() end end
end
local world, replicated = instance('Workspace'), instance('ReplicatedStorage')
for _, object in ipairs({world, replicated}) do
 function object:GetAttributeChangedSignal(name) return self:GetPropertyChangedSignal('Attribute_' .. name) end
 local setter = object.SetAttribute
 function object:SetAttribute(name, value) setter(self, name, value); self:GetAttributeChangedSignal(name):Fire() end
end
local logs = {
 {message = "! Joining game 'old-job' place 123 at 128.116.4.33"},
 {message = 'UDMUX Address = 128.116.4.33, Port = 123'},
 {message = "! Joining game 'current-job' place 123 at 10.12.1.1"},
 {message = 'UDMUX Address = 128.116.45.33, Port = 456'},
}
local services = {
 Workspace = world, ReplicatedStorage = replicated, NetworkClient = {ConnectionAccepted = signal()},
 LogService = {GetLogHistory = function() return logs end},
 HttpService = {JSONDecode = function(_, raw)
   if raw == 'wrong' then return {success = true, ip = '1.1.1.1', country = 'Wrong', city = 'Wrong'} end
   return {ip = '128.116.45.33', country_name = 'United States', city = 'Miami'}
 end},
}
local environment = {request = function(request)
 calls[#calls + 1] = request.Url
 return {StatusCode = 200, Body = request.Url:find('ipwho.is', 1, true) and 'wrong' or 'valid'}
end}
getgenv = function() return environment end
game.JobId = 'current-job'; game.GetService = function(_, name) return assert(services[name]) end
Location.setup({Lifetime = Lifetime}); drain()
local result, err = Location.snapshot()
assert(result.country == 'United States' and result.city == 'Miami' and not err)
assert(#calls == 2)
for _, url in ipairs(calls) do assert(url:find('128.116.45.33', 1, true), 'Never query the previous job or the client IP') end
for _, timer in ipairs(timers) do timer() end
assert(select(2, Location.snapshot()) == nil)
Location.teardown()
-- A private address must not be sent to geolocation providers.
logs[4].message = 'UDMUX Address = 10.12.1.1, Port = 456'
calls, timers = {}, {}
Location.setup({Lifetime = Lifetime}); drain()
for _, timer in ipairs(timers) do timer() end
result, err = Location.snapshot()
assert(#calls == 0 and result.country == nil and err)
-- Replicated metadata can arrive after startup and clear the failure.
world:SetAttribute('ServerCountry', 'Brasil'); world:SetAttribute('ServerCity', 'São Paulo')
result, err = Location.snapshot(); assert(result.city == 'São Paulo' and not err)
Location.teardown()
''')

    def test_game_sources_deduplicate_developers_and_report_failures(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Information': 'core/information.luau'}, r'''
local pending, timers = {}, {}
task.spawn = function(callback) pending[#pending + 1] = callback end
task.delay = function(_, callback) timers[#timers + 1] = callback end
local render = signal()
local player = {Name = 'User', GetNetworkPing = function() return .04 end}
local players = {MaxPlayers=20, GetPlayers=function() return {player} end}
local utils = {getLocalPlayer=function() return player end, getPlayers=function() return players end,
 getRunService=function() return {RenderStepped=render} end, version=function() return '2.0.0' end, author=function() return 'Dev' end}
getgenv = function() return {identifyexecutor=function() return 'Delta', '1.2' end} end
version = function() return '0.748' end
game.CreatorId, game.CreatorType, game.GameId = 123, Enum.CreatorType.Group, 456
local services = {
 MarketplaceService = {GetProductInfoAsync=function() error('blocked') end, GetProductInfo=function() error('blocked') end},
 HttpService = {JSONDecode=function() return {data={{name='Actual game',creator={name='Group',type='Group',id=123}}}} end},
 GroupService = {GetGroupInfoAsync=function() return {Name='Group',Owner={Name='Owner'}} end},
}
game.HttpGet=function() return 'metadata' end
game.GetService=function(_, name) return services[name] or {} end
local deps = {Utils=utils, Lifetime=Lifetime, GameContext={getProfile=function() return {version='3.3.0',developers={'Dev','Other'}} end},
 Location={snapshot=function() return {country='Brasil',city='São Paulo'} end}}
Information.setup(deps)
for _, callback in ipairs(pending) do callback() end
render:Fire(.5)
local result, errors = Information.snapshot()
assert(result.game:find('Nome: Actual game') and result.game:find('Criador: Owner') and result.game:find('Grupo: Group'))
assert(result.session:find('Delta 1.2') and result.session:find('40 ms') and not next(errors))
assert(result.developers == 'Nome: Dev\nNome: Other', 'Developers must be a single deduplicated list')
assert(result.versions:find('Hub: 2.0.0') and result.versions:find('Script do jogo: 3.3.0'))
Information.teardown()
-- A stalled lookup must become a visible error and late work must stop on teardown.
pending, timers = {}, {}
Information.setup(deps)
for _, callback in ipairs(timers) do callback() end
result, errors = Information.snapshot()
assert(result.game:find('consulta não respondeu') and errors.game)
Information.teardown()
for _, callback in ipairs(pending) do callback() end
''')

    def test_native_region_and_replicated_metadata_need_no_http(self):
        self.run_luau({'Lifetime': 'core/lifetime.luau', 'Location': 'core/server_location.luau'}, r'''
task.spawn = function() end
local world, replicated = instance('Workspace'), instance('ReplicatedStorage')
game.ServerRegion = 'GRU'
game.GetService = function(_, name) return name == 'Workspace' and world or replicated end
Location.setup({Lifetime = Lifetime})
local result = Location.snapshot()
assert(result.country == 'Brasil' and result.city == 'São Paulo')
Location.teardown(); game.ServerRegion = nil
world:SetAttribute('ServerCountry', 'Germany'); world:SetAttribute('ServerCity', 'Frankfurt')
Location.setup({Lifetime = Lifetime})
result = Location.snapshot()
assert(result.country == 'Germany' and result.city == 'Frankfurt')
Location.teardown()
''')


if __name__ == '__main__':
    unittest.main()
