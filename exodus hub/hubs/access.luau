-- [[ access ]]
--!strict
--!optimize 2

return {
  exodus = { mode = "public", userIds = {}, usernames = {}, blockedUserIds = {}, blockedUsernames = {} },
  games = {
    universal = { mode = "public" },
    ["phantom-ball"] = { mode = "public" },
    mcpvp = { mode = "allowlist", userIds = {}, usernames = { "renannnhh" } },
  },
}
