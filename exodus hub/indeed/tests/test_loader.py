"""Run the real HTTP loader against a local, deterministic repository snapshot."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def literal(value):
    return '[=====[' + value + ']=====]'


class LoaderBehavior(unittest.TestCase):
    def test_reload_reuses_sources_and_rejects_invalid_contracts_before_stopping(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        prelude = (ROOT / 'indeed/checks/engine_api.luau').read_text()
        # The transport test replaces only rendering. All infrastructure and features are real modules.
        files = {str(path.relative_to(ROOT)): path.read_text() for path in ROOT.rglob('*.luau') if 'indeed' not in path.relative_to(ROOT).parts}
        files['ui/interface.luau'] = 'return {setup = function() return true end, notify = function() end, __contract = {requires = {}, provides = {"setup", "notify"}}}'
        broken = re.sub(r'(path = "core/bootstrap.luau",\s*hash = ")[a-f0-9]+', r'\g<1>' + 'd' * 64, files['core/catalog.luau'])
        code = prelude + '\nlocal sources = {}\n'
        for path, source in files.items():
            code += 'sources[ ' + literal(path) + ' ] = ' + literal(source) + '\n'
        code += '''
local revision, requests = string.rep("a", 40), 0
local limited, now, retries, cooldown = true, 1000, {}, "2490"
local mirrors, rawLimited = {}, false
task.delay = function(seconds, callback) retries[#retries + 1] = {seconds = seconds, callback = callback} end
local environment = setmetatable({}, {__index = getfenv()})
local nativeLoadstring = loadstring
local function compile(source, name)
  local chunk, reason = nativeLoadstring(source, name)
  if chunk then setfenv(chunk, environment) end
  return chunk, reason
end
local function request(options)
  requests += 1
  if limited then return {StatusCode = 403, Headers = {["Retry-After"] = cooldown}, Body = "rate limit"} end
  if rawLimited and options.Url:find("raw.githubusercontent.com",1,true) then return {StatusCode=429,Headers={["Retry-After"]="2490"},Body="rate limit"} end
  if options.Url:find("cdn.jsdelivr.net",1,true) then mirrors[1]=true; return {StatusCode=429,Headers={["Retry-After"]="2490"},Body="rate limit"} end
  if options.Url:find("rawcdn.githack.com",1,true) then mirrors[2]=true; assert(options.Url:find(revision,1,true),"CDNs must preserve the revision") end
  if options.Url:find("api.github.com", 1, true) then
    return {StatusCode = 200, Body = options.Url:find("/git/ref/heads/", 1, true) and "head" or "metadata"}
  end
  local path = options.Url:match("/exodus%%20hub/(.+)$")
  assert(path and sources[path], "Unexpected request: " .. options.Url)
  return {StatusCode = 200, Body = sources[path]}
end
local http = game:GetService("HttpService")
function http:JSONDecode(value)
  if value == "metadata" then return {id = 1334849119, full_name = "Repp35/Exodus-Hub", owner = {id = 222319587}, default_branch = "main"} end
  if value == "head" then return {object = {sha = revision}} end
  error("Unexpected JSON")
end
function http:UrlEncode(value) return value end
for key, value in pairs({game = game, workspace = workspace, Enum = Enum, Color3 = Color3,
  Vector3 = Vector3, Vector2 = Vector2, UDim = UDim, UDim2 = UDim2, CFrame = CFrame,
  NumberSequence = NumberSequence, ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint,
  NumberRange = NumberRange, TweenInfo = TweenInfo, _G = _G, task = task, typeof = typeof,
  warn = warn, print = function() end, request = request, loadstring = compile}) do environment[key] = value end
environment.getgenv = function() return environment end
environment.os = setmetatable({time = function() return now end}, {__index = os})
local function start() return assert(compile(sources["loader.luau"], "loader"))() end
assert(pcall(start), "Rate limiting must never throw")
assert(requests == 2 and _G.Exodus.StartError, "Rate limiting must defer the entire startup")
for _, timer in ipairs(retries) do assert(timer.seconds ~= 2490, "Long waits must not schedule a retry") end
assert(_G.ExodusLoaderRecoveryToken == nil, "Long rate limits must cancel recovery")
now, cooldown = 3490, "30"
start()
local retry
for _, timer in ipairs(retries) do if timer.seconds == 30 then retry = timer.callback end end
assert(retry, "Short waits must schedule a retry")
limited, now = false, 3520
retry()
assert(_G.Exodus.Started and _G.Exodus.Utils.isActive())
local first = requests
revision = string.rep("b", 40)
start()
assert(_G.Exodus.Revision == revision)
assert(requests - first <= 5, "Unchanged modules were downloaded again")
rawLimited = true
_G.ExodusSourceCache = {sources={},bytes=0}
revision = string.rep("e",40)
start()
assert(_G.Exodus.Revision==revision and mirrors[1] and mirrors[2],"Must fail over to a second CDN and finish loading")
rawLimited = false
_G.ExodusRequestState.cooldowns = {}
local session = _G.Exodus.Context
revision = string.rep("c", 40)
sources["core/bootstrap.luau"] = 'return {__contract = {requires = {}, provides = {"setup"}}}'
sources["core/catalog.luau"] = BROKEN_CATALOG
assert(pcall(start), "Failed loads must not throw into auto execute")
assert(_G.Exodus.StartError, "Invalid module must be rejected")
assert(_G.Exodus.Context == session and session.utils.isActive(), "Working session was stopped before contract validation")
'''.replace('BROKEN_CATALOG', literal(broken))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'loader_behavior.luau'
            path.write_text(code)
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
