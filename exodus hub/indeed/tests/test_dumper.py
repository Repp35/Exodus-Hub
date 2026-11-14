"""Exercise dumper discovery and output with a lightweight Lua/Roblox shim."""
import ctypes
import re
import unittest
from pathlib import Path


class DumperTests(unittest.TestCase):
    def test_collects_scripts_without_per_instance_or_retry_delays(self):
        source = (Path(__file__).resolve().parents[2] / 'modules/logic/extras/universal/dumper.luau').read_text()
        source = re.sub(r'\b([A-Za-z_]\w*)\s*([+-])=\s*1\b', r'\1 = \1 \2 1', source)
        lua = r'''
        table.clear = function(t) for k in pairs(t) do t[k] = nil end end
        table.clone = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
        typeof = function(v) return type(v) == 'table' and v._instance and 'Instance' or type(v) end
        local waits, calls, files, finished = 0, 0, {}, nil
        task = { wait = function() waits = waits + 1 end, spawn = function(f) f() end }
        makefolder = function() end
        isfolder = function() return false end
        writefile = function(path, contents) files[path] = contents end
        local function object(name, class, parent, source)
          return { _instance=true, Name=name, ClassName=class, Parent=parent, Source=source,
            GetFullName=function(self) return self.Name end, GetAttributes=function() return {} end }
        end
        game = object('game', 'DataModel')
        game.PlaceId, game.GameId, game.JobId = 42, 7, 'job'
        local direct = object('Direct', 'LocalScript', game, 'return 123')
        local failed = object('Failed', 'ModuleScript', game)
        local remote = object('Remote', 'RemoteEvent', game)
        local detached = object('Detached', 'ModuleScript', nil, 'return 456')
        local objects = {direct, failed, remote}
        for i=1,12000 do objects[#objects+1] = object('Part', 'Part', game) end
        game.GetDescendants = function() return objects end
        game.GetService = function(_, name)
          if name == 'CollectionService' then return { GetTags=function() return {} end } end
          if name == 'MarketplaceService' then
            assert(next(files) ~= nil, 'scripts must be written before marketplace lookup')
            return { GetProductInfo=function() return {Name='Test'} end }
          end
        end
        getnilinstances = function() return {detached, direct} end
        decompile = function() calls = calls + 1; return 'failed to decompile' end
        local module = (function()
        ''' + source + r'''
        end)()
        assert(module.start({onComplete=function(result) finished=result end,
          onError=function(err) error(err) end}))
        assert(finished and finished.total == 3 and finished.saved == 2 and finished.failed == 1)
        assert(calls == 1, 'failed scripts should not be retried repeatedly')
        assert(waits <= 3, 'discovery should not pause for every small group of instances')
        local scriptFiles, tree = 0, nil
        for path, contents in pairs(files) do
          if path:find('/scripts/', 1, true) then scriptFiles=scriptFiles+1 end
          if path:find('/tree.txt', 1, true) then tree=contents end
        end
        assert(scriptFiles == 2 and tree and tree:find('Remote', 1, true))
        assert(not tree:find('[Part]', 1, true), 'irrelevant objects should not be catalogued')
        '''
        lib = ctypes.CDLL('liblua5.4.so.0')
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_close.argtypes = [ctypes.c_void_p]
        state = lib.luaL_newstate()
        try:
            lib.luaL_openlibs(state)
            result = lib.luaL_loadstring(state, lua.encode())
            if not result:
                result = lib.lua_pcallk(state, 0, 0, 0, 0, None)
            if result:
                self.fail(lib.lua_tolstring(state, -1, None).decode())
        finally:
            lib.lua_close(state)


if __name__ == '__main__':
    unittest.main()
