"""Run production visibility/scheduling functions with deterministic engine doubles.

Uses Lua 5.4 for the portable controllers. EXODUS_LUAU additionally executes the
complete untransformed Luau module, including its incremental property journal.
These checks measure work and lifecycle correctness, not live Roblox FPS.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import test_ui_library as ui

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'modules/logic/extras/antilag.luau').read_text()
MOCK = (Path(__file__).parent / 'fixtures/antilag_runtime.lua').read_text()
CONTROLLERS = SOURCE[SOURCE.index('local function worldHalf('):SOURCE.index('local function applyScenePolicy(')]


def run_lua(source):
    state = ui.LIB.luaL_newstate()
    ui.LIB.luaL_openlibs(state)
    try:
        encoded = source.encode()
        status = ui.LIB.luaL_loadbufferx(state, encoded, len(encoded), b'@antilag-test', None)
        if not status:
            status = ui.LIB.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise AssertionError(ui.LIB.lua_tolstring(state, -1, None).decode())
    finally:
        ui.LIB.lua_close(state)


class AntiLagRuntimeTests(unittest.TestCase):
    def run_controller(self, code):
        run_lua(MOCK + '\n' + CONTROLLERS + '\n' + code)

    def test_frustum_bounds_distance_and_rotated_geometry(self):
        self.run_controller('''
local state=cameraState(camera,160)
assert(boundsReason(vec(0,0,-50),vec(2,2,2),state)==nil)
assert(boundsReason(vec(0,0,50),vec(2,2,2),state)=='view')
assert(boundsReason(vec(100,0,-20),vec(2,2,2),state)=='view')
assert(boundsReason(vec(0,80,-20),vec(2,2,2),state)=='view')
assert(boundsReason(vec(0,0,-200),vec(2,2,2),state)=='distance')
assert(boundsReason(vec(0,0,-200),vec(100,10,100),state)==nil,'large visible floor must remain')
local half=worldHalf(frame(vec(),math.pi/4),vec(100,4,4))
assert(half.X>36 and half.Z>36 and half.Y==2)
assert(boundsReason(vec(0,0,0),vec(4,4,4),state)==nil,'camera inside bounds')
''')

    def test_wall_floor_roof_and_partial_visibility(self):
        self.run_controller('''
assert(boxOccludes(frame(vec(0,0,-20)),vec(20,20,1),vec(),vec(0,0,-60),vec(3,3,3)))
assert(not boxOccludes(frame(vec(0,0,-20)),vec(1,1,1),vec(),vec(0,0,-60),vec(12,12,3)),'centre hit cannot hide exposed edges')
assert(not boxOccludes(frame(vec(0,0,-60)),vec(20,20,1),vec(),vec(0,0,-60),vec(3,3,3)),'cannot occlude itself')
assert(not boxOccludes(frame(vec()),vec(20,20,1),vec(),vec(0,0,-60),vec(3,3,3)),'camera inside blocker')
assert(boxOccludes(frame(vec(0,0,0)),vec(30,1,30),vec(0,10,0),vec(0,-30,0),vec(3,3,3)),'underground behind floor')
assert(boxOccludes(frame(vec(0,10,0)),vec(30,1,30),vec(),vec(0,30,0),vec(3,3,3)),'above opaque roof')
assert(not boxOccludes(frame(vec(0,10,0)),vec(30,1,30),vec(),vec(0,30,0),vec(3,30,3)),'object crosses roof')
assert(boxOccludes(frame(vec(-14,0,-14),math.pi/4),vec(20,20,1),vec(),vec(-40,0,-40),vec(2,2,2)),'rotated wall')
''')

    def test_occlusion_cache_budget_and_blocker_removal(self):
        self.run_controller('''
local wall=node('Part','Wall',workspace,vec(0,0,-20),vec(40,40,2))
local rays=0
workspace.Raycast=function() rays=rays+1;if wall.Parent then return {Instance=wall} end end
local test=createOcclusionTester(workspace)
local state=cameraState(camera,160)
test:BeginFrame({})
local entry={}
assert(test:Test(entry,state,vec(0,0,-60),vec(3,3,3)))
for i=1,30 do assert(test:Test(entry,state,vec(0,0,-60),vec(3,3,3))) end
assert(rays==1,'cached solid needs no extra raycast')
wall.Transparency=1
assert(not test:Test(entry,state,vec(0,0,-60),vec(3,3,3)))
wall.Transparency=0;wall.Parent=nil
assert(not test:Test(entry,state,vec(0,0,-60),vec(3,3,3)))
wall.Parent=workspace;wall.Shape='Cylinder'
assert(not test:Test({},state,vec(0,0,-60),vec(3,3,3)), 'nonconvex/unknown shapes cannot be box blockers')
for i=1,100 do test:Test({},state,vec(0,0,-60),vec(3,3,3)) end
assert(test:GetStatus().RaysThisFrame==8 and rays==8)
test:BeginFrame({})
assert(test:GetStatus().RaysThisFrame==0)
''')

    def test_solid_terrain_cache_and_carved_opening(self):
        self.run_controller('''
local terrain=node('Terrain','Terrain',workspace)
local reads,full=0,true
terrain.ReadVoxels=function()
 reads=reads+1
 local materials,occupancy={},{}
 for x=1,3 do
  materials[x],occupancy[x]={},{}
  for y=1,3 do
   materials[x][y],occupancy[x][y]={},{}
   for z=1,3 do materials[x][y][z]=Enum.Material.Rock;occupancy[x][y][z]=full and 1 or 0 end
  end
 end
 return materials,occupancy
end
workspace.Raycast=function() return {Instance=terrain,Position=vec(2,0,2),Normal=vec(0,1,0)} end
local tester=createOcclusionTester(workspace)
camera.CFrame=frame(vec(2,2,2))
local state=cameraState(camera,160)
tester:BeginFrame({})
local entry={}
assert(tester:Test(entry,state,vec(2,-100,2),vec(0.5,0.5,0.5)))
assert(tester:Test({},state,vec(2,-110,2),vec(0.5,0.5,0.5)))
assert(reads==1,'adjacent hidden regions must reuse the same solid voxel')
full=false;advance(0.11);tester:BeginFrame({})
assert(not tester:Test(entry,state,vec(2,-100,2),vec(0.5,0.5,0.5)),'terrain edits must expire the cached blocker')
assert(reads==2)
''')

    def test_camera_turn_during_partial_region_update_restores_every_member(self):
        self.run_controller('''
local map=node('Model','Map',workspace)
local parts={}
for i=1,300 do parts[i]=node('Part','Tile'..i,map,vec(4,4,-48)) end
local test=createOcclusionTester(workspace)
local spatial=createSpatialController({Workspace=workspace,Player=player,RunService=runService,Occlusion=test,
 BeginFrame=function() test:BeginFrame({}) end,OnHidden=onHidden,OnLobbyHidden=function() end},getOption)
spatial:SetEnabled(true)
for i=1,30 do advance();runService.Heartbeat:Fire(0.1) end
assert(spatial:GetStatus().Chunks==1 and not masks[parts[1]])
camera.CFrame=frame(vec(),math.pi);advance();runService.Heartbeat:Fire(0.1)
assert(masks[parts[1]] and not masks[parts[300]],'fixture needs a partially applied job')
camera.CFrame=frame()
for i=1,10 do advance();runService.Heartbeat:Fire(0.1) end
for _,part in ipairs(parts) do assert(not masks[part],'turn left an early region member hidden') end
spatial:Destroy()
''')

    def test_region_transitions_index_reuse_streaming_and_teardown(self):
        self.run_controller('''
local gameRoot=node('Folder','Game',workspace)
local maps=node('Folder','Maps',gameRoot)
local map=node('Model','Crossroads',maps)
local lobby=node('Model','Lobby',gameRoot)
local lobbyPart=node('Part','LobbyFloor',lobby,vec(0,0,-30))
local visible=node('Part','Near',map,vec(0,0,-50))
local far=node('Part','Far',map,vec(0,0,-600))
local back=node('Part','Behind',map,vec(0,0,60))
local unknown=node('Folder','TBI',workspace)
local asset=node('Part','Asset',unknown,vec(0,0,-900))
local ball=node('Part','GameBall',workspace,vec(0,0,-900))
local protectedPart=node('Part','Important',map,vec(0,0,-900));protectedPart:SetAttribute('AntiLagKeepVisible',true)
local test=createOcclusionTester(workspace)
local lobbyMask=false
local baseline=liveConnections
local spatial=createSpatialController({Workspace=workspace,Player=player,RunService=runService,Occlusion=test,
 BeginFrame=function() test:BeginFrame({}) end,OnHidden=onHidden,OnLobbyHidden=function(value) lobbyMask=value end},getOption)
spatial:SetEnabled(true)
for i=1,12 do advance();runService.Heartbeat:Fire(0.1) end
assert(not masks[visible] and masks[far] and masks[back] and masks[asset])
assert(not masks[ball] and not masks[protectedPart])
assert(spatial:GetStatus().Tracked==5)
options.CullDistance=1000;spatial:Refresh()
for i=1,10 do advance();runService.Heartbeat:Fire(0.1) end
assert(not masks[far] and spatial:GetStatus().Tracked==5 and not spatial:GetStatus().Indexing)
workspace:SetAttribute('MatchStatus',6);player:SetAttribute('Lives',1)
advance();runService.Heartbeat:Fire(0.1);assert(lobbyMask)
workspace:SetAttribute('MatchStatus',0);advance();runService.Heartbeat:Fire(0.1);assert(not lobbyMask)
camera.CFrame=frame(vec(),math.pi)
for i=1,10 do advance();runService.Heartbeat:Fire(0.1) end
assert(not masks[back] and masks[visible])
-- Moving an anchored platform must restore/reindex it, not blacklist it forever.
far.CFrame=frame(vec(0,0,30))
for i=1,30 do advance();runService.Heartbeat:Fire(0.1) end
assert(not masks[far])
reparent(asset,nil)
for i=1,10 do advance();runService.Heartbeat:Fire(0.1) end
assert(not masks[asset] and spatial:GetStatus().Tracked==4)
spatial:Destroy()
assert(next(masks)==nil and liveConnections==baseline)
''')

    def test_fourteen_players_cached_relevance_and_no_listener_leaks(self):
        self.run_controller('''
local baseline=liveConnections
local test=createOcclusionTester(workspace)
local relevance=createRelevanceController({Players=players,Player=player,Occlusion=test,OnHidden=onHidden},getOption)
relevance:SetEnabled(true)
local remotes={}
for id=2,14 do remotes[#remotes+1]=addRemote(id,vec(0,0,id==2 and -30 or 600)) end
local scans,rosterReads=stats.getDescendants,stats.getPlayers
for i=1,120 do advance(1/60);relevance:BeginFrame(os.clock(),camera) end
assert(relevance:GetStatus().Players==13 and relevance:GetStatus().Hidden==12)
assert(stats.getDescendants==scans and stats.getPlayers==rosterReads,'frame callbacks must not scan rosters/subtrees')
assert(relevance:Interval(player)==0 and relevance:Interval(remotes[1])==1/30)
assert(relevance:Interval(remotes[2])==math.huge)
local replacement=node('Model','Respawn',workspace)
node('Humanoid','Humanoid',replacement)
node('Part','HumanoidRootPart',replacement,vec(0,0,-20))
remotes[2].CharacterRemoving:Fire(remotes[2].Character)
remotes[2].Character=replacement;remotes[2].CharacterAdded:Fire(replacement)
for i=1,10 do advance();relevance:BeginFrame(os.clock(),camera) end
assert(relevance:Interval(remotes[2])==1/30)
players.PlayerRemoving:Fire(remotes[3])
assert(relevance:GetStatus().Players==12)
relevance:Destroy()
assert(next(masks)==nil and liveConnections==baseline)
''')

    def test_native_scheduler_skips_hidden_sword_work_and_restores_callbacks(self):
        self.run_controller('''
local scripts=node('Folder','PlayerScripts',player)
local client=node('Folder','Client',scripts)
local gameplay=node('Folder','Gameplay',client)
local vfx=node('Folder','VFX',client)
local head=node('LocalScript','HeadLook',gameplay)
local animate=node('LocalScript','Animate',gameplay)
local chroma=node('LocalScript','ChromaWeapon',vfx)
local envs,values={},{ }
getconnections=function(s) return s.list end
getfenv=function(fn) return envs[fn] end
getupvalues=function(fn) return values[fn] end
local headCalls,chromaCalls,heavy=0,0,0
local class={UpdateSwordThing=function() end,UpdateAutomaticGrip=function() end,BlendGrip=function() end,
 Update=function(_,dt) heavy=heavy+1;assert(dt>0) end}
local h=function() headCalls=headCalls+1 end
local c=function() chromaCalls=chromaCalls+1 end
local a=function() end
envs[h]={script=head};envs[c]={script=chroma};envs[a]={script=animate};values[a]={class}
local hConnection=runService.RenderStepped:Connect(h)
local cConnection=runService.Heartbeat:Connect(c)
runService.RenderStepped:Connect(a)
local remote=addRemote(2)
local invisible=addRemote(3,vec(0,0,600))
local original=class.Update
local scheduler=createVisualScheduler({Player=player,PlayerScripts=scripts,RunService=runService,
 Relevance={Interval=function(_,owner) return owner==invisible and math.huge or 1/30 end}},getOption)
scheduler:SetEnabled(true);flush()
assert(not hConnection.Enabled and not cConnection.Enabled)
local near=setmetatable({Owner=remote,PrevChar=remote.Character},{__index=class})
local far=setmetatable({Owner=invisible,PrevChar=invisible.Character},{__index=class})
for i=1,60 do advance(1/60);near:Update(1/60);far:Update(1/60) end
assert(heavy==30 and scheduler:GetStatus().SkippedUpdates==90)
-- Local animation is never throttled, including a local SwordAnimator using the class.
local own=setmetatable({Owner=player,PrevChar=player.Character},{__index=class})
for i=1,60 do own:Update(1/60) end
assert(heavy==90)
scheduler:Destroy()
assert(class.Update==original and hConnection.Enabled and cConnection.Enabled)
runService.RenderStepped:Fire(1/60);runService.Heartbeat:Fire(1/60)
assert(headCalls==1 and chromaCalls==1)
''')

    def test_fourteen_player_heavy_work_matches_one_when_remotes_are_invisible(self):
        self.run_controller('''
local scripts=node('Folder','PlayerScripts',player)
local client=node('Folder','Client',scripts)
local gameplay=node('Folder','Gameplay',client)
local native=node('LocalScript','Animate',gameplay)
local test=createOcclusionTester(workspace)
local relevance=createRelevanceController({Players=players,Player=player,Occlusion=test,OnHidden=onHidden},getOption)
relevance:SetEnabled(true)
local remotes={}
for id=2,14 do remotes[#remotes+1]=addRemote(id,vec(0,0,600)) end
for i=1,20 do advance(1/60);relevance:BeginFrame(os.clock(),camera) end
local heavy,cleared=0,0
local class={UpdateSwordThing=function() end,UpdateAutomaticGrip=function() end,BlendGrip=function() end,
 ClearConnections=function() cleared=cleared+1 end,Update=function() heavy=heavy+1 end}
local callback=function() end
local external=runService.RenderStepped:Connect(callback)
getconnections=function(s) return s.list end
getfenv=function() return {script=native} end
getupvalues=function() return {class} end
local scheduler=createVisualScheduler({Player=player,Players=players,PlayerScripts=scripts,RunService=runService,Relevance=relevance},getOption)
scheduler:SetEnabled(true);flush()
local animators={}
for _,remote in ipairs(remotes) do animators[#animators+1]=setmetatable({Owner=remote,PrevChar=remote.Character},{__index=class}) end
local own=setmetatable({Owner=player,PrevChar=player.Character},{__index=class})
for i=1,60 do
 own:Update(1/60)
 for _,animator in ipairs(animators) do animator:Update(1/60) end
end
assert(heavy==60 and scheduler:GetStatus().SkippedUpdates==780,'13 invisible remotes must add zero heavy sword updates')
-- All visible: share a fixed procedural budget instead of 13 x 60 updates/s.
for _,remote in ipairs(remotes) do remote.Character:FindFirstChild('HumanoidRootPart').CFrame=frame(vec(0,0,-30)) end
for i=1,20 do advance(1/60);relevance:BeginFrame(os.clock(),camera) end
local before=heavy
for i=1,60 do for _,animator in ipairs(animators) do animator:Update(1/60) end end
assert(heavy-before<=130 and heavy-before>0,'visible sword budget scales excessively')
players.PlayerRemoving:Fire(remotes[1]);assert(cleared==1,'departed player retains animation marker listeners')
scheduler:Destroy();relevance:Destroy();external:Disconnect()
assert(liveConnections==0)
''')

    def test_portable_aura_loop_shutdown_without_introspection(self):
        self.run_controller('''
getconnections=nil
local scripts=node('Folder','PlayerScripts',player)
local client=node('Folder','Client',scripts)
local vfx=node('Folder','VFX',client)
local aura=node('LocalScript','AuraVisibility',vfx)
local scheduler=createVisualScheduler({Player=player,PlayerScripts=scripts,RunService=runService,Relevance={}},getOption)
scheduler:SetEnabled(true);flush()
assert(not scheduler:GetStatus().Supported and not aura.Enabled and scheduler:GetStatus().SuspendedScripts==1)
scheduler:Destroy()
assert(aura.Enabled and liveConnections==0)
''')

    @unittest.skipUnless(os.environ.get('EXODUS_LUAU'), 'set EXODUS_LUAU for full Luau journal integration')
    def test_complete_luau_property_journal_reversibility_and_removed_objects(self):
        exported = SOURCE.rsplit('return AntiLag', 1)[0] + '''
return { createOptimizer=createOptimizer, profile=PROFILE, applyScenePolicy=applyScenePolicy, createGameAdapter=createGameAdapter }
'''
        script = MOCK + '\nlocal internal=(function()\n' + exported + '\nend)()\n' + '''
local profile=table.clone(internal.profile)
local mesh=node('MeshPart','Mesh',workspace,vec(0,0,-50))
local texture=node('Texture','Texture',mesh);texture.Texture='custom-texture'
local pbr=node('SurfaceAppearance','PBR',mesh)
local hiddenVisuals=node('Folder','HiddenVisuals')
local engine=internal.createOptimizer({Workspace=workspace,Lighting=lighting,RunService=runService,CollectionService=collection,HiddenVisuals=hiddenVisuals,Roots={workspace,lighting,hiddenVisuals},
 ExtraPolicy=function(o,t,w,opts) return internal.applyScenePolicy(o,t,w,opts,masks,false,nil) end},profile)
engine:SetEnabled(true);flush()
assert(mesh.TextureID=='' and mesh.CastShadow==false and texture.Texture=='' and texture.Transparency==1)
assert(mesh.CanCollide and mesh.CanQuery and mesh.CanTouch,'graphics changes cannot change physical/query behavior')
assert(lighting.FogEnd==160 and lighting.GlobalShadows==false and pbr.Parent==hiddenVisuals)
masks[mesh]=true;engine:RefreshSubtree(mesh);flush();assert(mesh.LocalTransparencyModifier==1)
mesh.LocalTransparencyModifier=0;flush();assert(mesh.LocalTransparencyModifier==1,'camera scripts overwrote the mask')
masks[mesh]=nil;engine:RefreshSubtree(mesh);flush();assert(mesh.LocalTransparencyModifier==0)
engine:SetOption('CullDistance',80);flush();assert(lighting.FogEnd==80)
engine:SetOption('DisableTextures',false);flush();assert(mesh.TextureID=='original-texture' and texture.Texture=='custom-texture' and pbr.Parent==mesh)
engine:SetOption('DisableTextures',true);flush()
-- DescendantRemoving occurs before the object leaves the scope.
reparent(mesh,nil);flush()
assert(mesh.TextureID=='original-texture' and mesh.CastShadow and texture.Texture=='custom-texture' and pbr.Parent==mesh)
engine:Destroy();flush()
assert(not engine:GetStatus().Alive and engine:GetStatus().Properties==0)
assert(engine:GetStatus().RuntimeFailures==0 and engine:GetStatus().RestoreFailures==0)
assert(liveConnections==0)
print('PASS full property journal lifecycle')
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'journal.luau'
            path.write_text(script)
            result = subprocess.run([os.environ['EXODUS_LUAU'], str(path)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr + '\n' + '\n'.join(f'{i+1}: {line}' for i,line in enumerate(script.splitlines()) if i >= len(script.splitlines())-35))


if __name__ == '__main__':
    unittest.main()
