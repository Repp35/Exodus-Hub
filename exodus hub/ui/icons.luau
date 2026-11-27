-- [[ icons ]]
--!optimize 2
-- @modules uiicons

-- module
local Icons = {}
local Theme

-- configuration
local CONFIG = {
  VERSION = "b920884bb033",
  IMAGES = {
    assists = {
      png = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADaElEQVR42u2ZS2gUQRCGMzMbVzEuig8UcxAJ4gO8qDEKohcPweDFg+Sgt1w8avBqPAR8n2URBYUo3jQnAyaIBMSbYhBF8BAUHyBqUNDM7vg3VmHR9EzPZqd3Z3EbPvbB7E79VdXV1T0dURR1tDJ5NcwHXisLaNkI+PS6G2yg916zBHhp00AQ0Os4OEnvC60SARa7FPwAD7SoNEwA37APHNM8m0SBftsf/R1fwVr6zm+kAA55Gbwlz/oJXg+E8eq7G9G/wQ7o1K5xJoDzXqXBOzJipzDUlv/7wCdQJR6DLY1MIfb+oPBiOSaNlDdXgQPgPHgemcdv8AicAjtASRYHF/mvmKKbKy9+BqtFdDilVoDT4INmcDXmvRovwFFKKS9rAZyfPWCebj5PNz6eUBKXgUPgGpgVhjMz4BzoNf3eRfqcISOU8SEZ8TCmJOrrhIrKayHitiH1PBcCODWWgDdkQEUYosRsSxChjCzS5wsidfrpuyJd47mKAHtpQDM+Eml02bKysoG76Pr3lF6JK3rW+T9ONw8NE1EZ1GUxyCOBqpTeSbMIZpX7io3gp5h8crCgQRJbjBHB0bkqJr4TAZ4hJ89qKWMSMGUw2DNM0PVguYtu1Dd4ZDu4COZivB9ppfEWOKj9T5CyX1qQAPa2rB4lCvGElu+2IcU9A8Og23CvIIsdmcnbm8GIWHBkpammFBFq134H18EeQ1Xys4jAInAY3AO/NEPCGgzXR8UwX6bBEFhTTwpxGFU9vgJeWTxY76ga/lP1R2O0kC2udR3gWjxAXaDuNVcC9LmkeqATtsUsTZg2Ud7PGCIR1mF4xfD7WWq/+7KoQvpWrkDl7yb4ZkkB2yQOtQIwQVWtZEjluiexqRp102SbriMCL6lz3WqoPkHk4FzIi/nzvRT2OUoL20J2n6pa0bKyOz3YMt1wxNJKKOMnF1LrXTdznWRIT8KCFoqdWVIz17SjRZ7wkzHttGlvnKuzUf00IjRsaMo1HHI1XAB7tYs2LrJxqxC9aUtjs06nOQqXtE29Gk9sR4R5EBCIo/GK1qwNpzlpzsPzAfbyUzF51fqwLs3uKg8C2MNDYhKPuZi8rg93V4KPJGB/KwmQht4FX2p5YJcnAcrgI2DUpfddP2IKqM34L58T50aA145AW0BbQFtAIn8AralreVll6l8AAAAASUVORK5CYII=",
      fallback = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png",
    },
    settings = {
      png = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAADQUlEQVR42u2by05UQRCGCSSgYeLOKLA3YYjyDGqC+CaaERBfYLzwCMPlJeYRFFkoLlw5JgxblC3hMJjAqqwORYghTPc5p9u+/ZX8yUSg0tZ3pk93df8jRDQC+ROKAAAAAAEAAEAAAAAQAAAABAAAACUCYIK1yNpg7bD6rFNRX/5tXX5nAgDsaZq1xToh8yhYm6wpAKiuW6w11h+qHurb8V5yAUAJqSf3G9mL3Vy+DTaSzLN+k/34xXoEAMN1XwrlKg5ZMwBw85y/S+7jO+s2AFzXB/p/8RYAri81Tw2L94O1zGqyJkXq8wqrZ5hjINMdAIi2DIp2xnrJGh2SR/2sxTo3yLcBAFc73BOD4j8ukfOJAQS1WRsHAKLnBk/riwp5WwZ5nwHAxVSgm/NHK+QdK/FO8Bnq299lPfAFYEczwKUaA3pN8cSRDQhV/mhfM7DZGgOao7ii6wPAQDOoRo0BNSIDUKQG4A4A1J+CmpiC3AL4rBnUSo0BvcFLuP4ytCdLyirL0J9Yhuq1aDDIVoW8SwZ5F7ARu2hFFJpCnUt7wTTnU4NWxDFaEVfaNHhaVUFfaaajMXnyTZpx62jG/XsGbNqO7skOd06WqA35vFpizkc72vOBTBsHMv6OJL9Qwhe3bBzKHzg+lJ/GofxwqasjLm5GKLAPUy6+LQBKdw3a1GXia6ovXVcALt8J70qsjm5a7bQpo8u6LpJOSbuiKFH4Y1nn38ul8C4BXGpcWgcd1jZrT57wgXzelp8tpLjDDQEABAAAAAEAAEAAAAAQAABAaArCx5xj4YPyMedU+CB9zLkUP1gfcw7FD9rHnHrxg/cxpz7nB+9jThlAFD7mlJeaUfiYUwUQjY851R1uND7mFAFE5WO29Z9WZoVuye29r3DpY+74AKCKf0TxhEsf8ycfALoUV7j0Mfd9ACgiA+DSxzwAALcAdD7mAlOQPpqpTUGxvYRd+pg/YhmqD5c+5g5hIxaXjznVVkQ0PuZUm3HR+JhTPgOOwseMAxk70caBTKQ+5hwO5YP2MedwLSVoH3MuF7OC9THndjUxOB9zjpdzg/Ix53w9PQgfM0wSMGgAAAQAAAABAABAAAAAEAAAAAQA+egvqpN4KSMBBHQAAAAASUVORK5CYII=",
      fallback = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png",
    },
    chevron = {
      png = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABVElEQVR42u2YPQrCQBCFk2gjgvdQsNPCu1io4J3Ec1l5AEst7PxJHGEXRllxkrwplBd4uFi8fd/kbyZZVVXZLysjAAEIQAACEIAABCCAWXmQV6Da/nXMC7XuOIRv5F+nMtG4n9gQFV775yiAaD4R7UQH0Sr81wWEjx5T5b+0Fsl6TfZE++r1WAMgdPij8r6LRhYI66UzEJ1EN9E1/LaFSIV/el/Cema5HywbRYNFML6FCrWBSIWPxXkem1C8AnUTR6M1AOJb+K3aM0c+RrsACGv4DvIphIKAh2/aSjSBcAnfpheqA+EWvm0zZ4VwC4/oRr9BzEXj8A6Bh0e1058g4hv1rNbQ8Mh5IAVRqtag9AiPHmg+nYlStQfQ8B4T2TuEW+U9R0oNcVG9DTy850wcG8Ch6ipdxlHPgbtItOU/91WicJqf+V2IAAQgAAEIQAACEOAfAB6X5n3BjU9wiwAAAABJRU5ErkJggg==",
      fallback = "rbxasset://textures/ui/Settings/DropDown/DropDown.png",
    },
    minimize = {
      png = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAA1ElEQVR42u3WTQ7BQBiH8bZshLiGxL4LO5yES7kNt2BhLbbWiEz/kplEmmbUR9+SPE2exMa0P32nlTjnkn8uAQAAAAAAAAAAAAAAAAAAPw5IfVYXVvt8dRbLSp8tCufrfApIHxYaGN6BruqXruFlQPglcrVVB7VWG4N26qiWFVNQCxBmsKf2rr3jpsYxxLPRGaqTX+xi2NV3Pyax/RAbofCFhTq3dAdWFRv7rU08UnM1VTOj8iYeo9al33qRZX6krOOvBAAAAAAAAAAAAAAAAAAAaKoC/b1kd0qdb08AAAAASUVORK5CYII=",
      fallback = "rbxasset://textures/ui/Settings/Slider/Less.png",
    },
  },
}

-- setup
function Icons.setup(deps)
  Theme = deps.Theme.tokens
  return true
end

-- assets
local cache = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits = {}
for index = 1, #alphabet do
  digits[string.byte(alphabet, index)] = index - 1
end
local function decode(payload)
  local bytes = {}
  for index = 1, #payload, 4 do
    local a, b, c, d = string.byte(payload, index, index + 3)
    local value = digits[a] * 262144 + digits[b] * 4096 + (digits[c] or 0) * 64 + (digits[d] or 0)
    bytes[#bytes + 1] = string.char(math.floor(value / 65536) % 256)
    if c ~= 61 then
      bytes[#bytes + 1] = string.char(math.floor(value / 256) % 256)
    end
    if d ~= 61 then
      bytes[#bytes + 1] = string.char(value % 256)
    end
  end
  return table.concat(bytes)
end
local function resolve(name)
  local definition = assert(CONFIG.IMAGES[name], "Unknown UI icon: " .. tostring(name))
  if cache[name] then
    return cache[name]
  end
  local image = definition.fallback
  local asset = getcustomasset or getsynasset
  if type(writefile) == "function" and type(asset) == "function" then
    local ok, result = pcall(function()
      local folder = "exodus hub"
      if type(makefolder) == "function" and (type(isfolder) ~= "function" or not isfolder(folder)) then
        pcall(makefolder, folder)
      end
      local path = folder .. "/ui_" .. name .. "_" .. CONFIG.VERSION .. ".png"
      if type(isfile) ~= "function" or not isfile(path) then
        writefile(path, decode(definition.png))
      end
      return asset(path)
    end)
    if ok and type(result) == "string" and result ~= "" then
      image = result
    end
  end
  cache[name] = image
  return image
end

-- public-api
function Icons.create(parent, name, properties)
  if name == "information" then
    local icon = Instance.new("Frame")
    icon.Name = "Icon_information"
    icon.BackgroundTransparency = 1
    icon.BorderSizePixel = 0
    icon.Active = false
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.Size = UDim2.fromOffset(18, 18)
    icon.ZIndex = parent.ZIndex + 1
    for key, value in pairs(properties or {}) do
      icon[key] = value
    end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = icon
    local outline = Instance.new("UIStroke")
    outline.Color = Theme.COLORS.icon
    outline.Thickness = 1.5
    outline.Parent = icon
    for _, shape in ipairs({ { 3, 3, 0.28 }, { 2, 6, 0.62 } }) do
      local mark = Instance.new("Frame")
      mark.AnchorPoint = Vector2.new(0.5, 0.5)
      mark.Position = UDim2.fromScale(0.5, shape[3])
      mark.Size = UDim2.fromOffset(shape[1], shape[2])
      mark.BackgroundColor3 = Theme.COLORS.icon
      mark.BorderSizePixel = 0
      mark.ZIndex = icon.ZIndex
      local radius = Instance.new("UICorner")
      radius.CornerRadius = UDim.new(0.5, 0)
      radius.Parent = mark
      mark.Parent = icon
    end
    icon.Parent = parent
    return icon
  end
  local icon = Instance.new("ImageLabel")
  icon.Name = "Icon_" .. name
  icon.BackgroundTransparency = 1
  icon.Active = false
  icon.Selectable = false
  icon.BorderSizePixel = 0
  icon.Image = resolve(name)
  icon.ImageColor3 = Theme.COLORS.icon
  icon.ScaleType = Enum.ScaleType.Fit
  icon.AnchorPoint = Vector2.new(0.5, 0.5)
  icon.Position = UDim2.fromScale(0.5, 0.5)
  icon.Size = UDim2.fromOffset(18, 18)
  icon.ZIndex = parent.ZIndex + 1
  for key, value in pairs(properties or {}) do
    icon[key] = value
  end
  icon.ImageColor3 = Theme.COLORS.icon
  icon.Parent = parent
  return icon
end

-- contract
Icons.__contract = {
  provides = { "setup", "create" },
  requires = { Theme = "uitheme" },
  requiresData = { Theme = { "tokens" } },
}

return Icons
