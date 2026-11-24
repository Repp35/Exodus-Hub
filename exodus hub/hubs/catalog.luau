-- [[ catalog ]]

-- code

return {
  {
    id = "phantom-ball",
    title = "Phantom Ball",
    author = "deltapolinha_2915",
    placeIds = { 12979690461 },
    universeIds = { 4538598064 },
    notification = "Exodus Hub · Phantom Ball carregado.",
    modules = {
      { name = "uiassists", path = "hubs/phantom-ball/front/uiassists.luau" },
      { name = "uifloating", path = "hubs/phantom-ball/front/uifloating.luau" },
      { name = "uitelemetry", path = "hubs/phantom-ball/front/uitelemetry.luau" },
      { name = "autodark", path = "hubs/phantom-ball/modules/combat/autodark.luau" },
      { name = "autodash", path = "hubs/phantom-ball/modules/combat/autodash.luau" },
      { name = "autofierce", path = "hubs/phantom-ball/modules/combat/autofierce.luau" },
      { name = "autoparry", path = "hubs/phantom-ball/modules/combat/autoparry.luau" },
      { name = "autospam", path = "hubs/phantom-ball/modules/combat/autospam.luau" },
      { name = "clashstats", path = "hubs/phantom-ball/modules/combat/clashstats.luau" },
      { name = "cooldown", path = "hubs/phantom-ball/modules/combat/cooldown.luau" },
      { name = "dash", path = "hubs/phantom-ball/modules/combat/dash.luau" },
      { name = "deflectgeometry", path = "hubs/phantom-ball/modules/combat/deflectgeometry.luau" },
      { name = "dynamicparry", path = "hubs/phantom-ball/modules/combat/dynamicparry.luau" },
      { name = "movement", path = "hubs/phantom-ball/modules/combat/movement.luau" },
      { name = "remote", path = "hubs/phantom-ball/modules/combat/remote.luau" },
      { name = "spam", path = "hubs/phantom-ball/modules/combat/spam.luau" },
      { name = "combatloop", path = "hubs/phantom-ball/modules/core/combatloop.luau" },
      { name = "autojump", path = "hubs/phantom-ball/modules/features/autojump.luau" },
      { name = "camera", path = "hubs/phantom-ball/modules/features/camera.luau" },
      { name = "ballsync", path = "hubs/phantom-ball/modules/game/ballsync.luau" },
      { name = "gameinfo", path = "hubs/phantom-ball/modules/game/gameinfo.luau" },
      { name = "playerregistry", path = "hubs/phantom-ball/modules/game/playerregistry.luau" },
      { name = "presence", path = "hubs/phantom-ball/modules/game/presence.luau" },
      { name = "snapshots", path = "hubs/phantom-ball/modules/game/snapshots.luau" },
      { name = "targeting", path = "hubs/phantom-ball/modules/game/targeting.luau" },
      { name = "nativevisuals", path = "hubs/phantom-ball/render/nativevisuals.luau" },
      { name = "runtime", path = "hubs/phantom-ball/runtime.luau" },
      { name = "uiconfig", path = "hubs/phantom-ball/uiconfig.luau" },
    },
  },
}
