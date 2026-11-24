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
    checkPermissions = true,
    permissions = true,
    modules = {
      { name = "autodark", path = "hubs/phantom-ball/combat/auto_dark.luau" },
      { name = "autodash", path = "hubs/phantom-ball/combat/auto_dash.luau" },
      { name = "autofierce", path = "hubs/phantom-ball/combat/auto_fierce.luau" },
      { name = "autoparry", path = "hubs/phantom-ball/combat/auto_parry.luau" },
      { name = "autospam", path = "hubs/phantom-ball/combat/auto_spam.luau" },
      { name = "dynamicparry", path = "hubs/phantom-ball/combat/dynamic_parry.luau" },
      { name = "spam", path = "hubs/phantom-ball/combat/spam.luau" },
      { name = "combatloop", path = "hubs/phantom-ball/combat_loop.luau" },
      { name = "ballsync", path = "hubs/phantom-ball/game/ball_sync.luau" },
      { name = "cooldown", path = "hubs/phantom-ball/game/cooldown.luau" },
      { name = "gameinfo", path = "hubs/phantom-ball/game/game_info.luau" },
      { name = "movement", path = "hubs/phantom-ball/game/movement.luau" },
      { name = "nativevisuals", path = "hubs/phantom-ball/game/native_visuals.luau" },
      { name = "playerregistry", path = "hubs/phantom-ball/game/player_registry.luau" },
      { name = "presence", path = "hubs/phantom-ball/game/presence.luau" },
      { name = "remote", path = "hubs/phantom-ball/game/remote.luau" },
      { name = "snapshots", path = "hubs/phantom-ball/game/snapshots.luau" },
      { name = "targeting", path = "hubs/phantom-ball/game/targeting.luau" },
      { name = "gameruntime", path = "hubs/phantom-ball/game_runtime.luau" },
      { name = "gameui", path = "hubs/phantom-ball/game_ui.luau" },
      { name = "clashstats", path = "hubs/phantom-ball/prediction/clash_stats.luau" },
      { name = "dash", path = "hubs/phantom-ball/prediction/dash.luau" },
      { name = "deflectgeometry", path = "hubs/phantom-ball/prediction/deflect_geometry.luau" },
    },
  },
}
