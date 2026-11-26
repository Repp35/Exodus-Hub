-- [[ hub access lists ]]
--!strict
--!optimize 2

-- public: everyone; allowlist: listed accounts; disabled: nobody.
-- Prefer stable Roblox user IDs. Usernames preserve existing entries until migrated.
-- Exodus denial stops startup. Game denial selects Universal.
return {
  exodus = { mode = "public", userIds = {}, usernames = {}, blockedUserIds = {}, blockedUsernames = {} },
  games = {
    universal = { mode = "public" },
    ["phantom-ball"] = { mode = "public" },
    mcpvp = { mode = "allowlist", userIds = {}, usernames = { "renannnhh" } },
  },
}
