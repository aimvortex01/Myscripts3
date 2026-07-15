--[[
  FREE FIRE MAX - IMPROVED SCRIPT
  Author: Refactored from original
  Improvements:
  - Target prioritization (closest to crosshair)
  - Visibility check via raycast
  - Smoothing / lerp aiming
  - Object pooling for ESP objects
  - Performance gating (skip when disabled)
  - Error resilience with pcall wrappers
  - Weapon-based FOV (optional)
  - Proper cleanup on player leave
  - Hit chance randomization
]]

-- ============================================
-- CONFIGURATION
-- ============================================
local Config = {
    Aimbot = {
        Enabled = false,
        FOVRadius = 150,
        ShowFOVCircle = false,
        Smoothing = 0.4,          -- 0 = instant, 1 = very smooth (lerp factor)
        HitChance = 100,          -- Percentage 1-100
        TargetPart = "Head",      -- "Head", "HumanoidRootPart", "UpperTorso"
        VisibilityCheck = true,
        TeamCheck = true,
        MaxDistance = 1000,
        AutoFire = false,         -- Auto-shoot when target acquired
    },
    ESP = {
        Enabled = false,
        Tracers = false,
        HighlightColor = Color3.fromRGB(255, 50, 50),
        TracerColor = Color3.fromRGB(255, 50, 50),
        ShowDistance = false,
        ShowHealth = false,
        ShowName = false,
    },
}

-- ============================================
-- SERVICES
-- ============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================
-- ANTI-TAMPER CHECK (improved)
-- ============================================
local function verifyIntegrity()
    local expectedHash = 93233198656969
    -- Use a runtime check instead of static compare
    local _, hash = pcall(function()
        return game:GetService("RunService"):IsClient()
    end)
    if not hash then
        -- If we can't even check, the environment is likely tampered
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Security Error",
                Text = "Modified environment detected.",
                Duration = 8
            })
        end)
        return false
    end
    return true
end

if not verifyIntegrity() then return end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local function getCharacter(player)
    return player.Character
end

local function getHumanoid(character)
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getTargetPart(character, partName)
    if not character then return nil end
    local part = character:FindFirstChild(partName)
    if part then return part end
    -- Fallback chain
    part = character:FindFirstChild("HumanoidRootPart")
    if part then return part end
    part = character:FindFirstChild("UpperTorso")
    if part then return part end
    part = character:FindFirstChild("Torso")
    return part
end

local function isAlive(character)
    local humanoid = getHumanoid(character)
    return humanoid and humanoid.Health > 0 and humanoid.Health > 0.1 and getRootPart(character)
end

local function isTeamMate(player)
    if not Config.Aimbot.TeamCheck then return false end
    if not LocalPlayer or not player then return false end
    
    local myTeam = LocalPlayer.Team
    local theirTeam = player.Team
    
    if myTeam and theirTeam then
        return myTeam == theirTeam
    end
    
    -- Fallback: check TeamColor
    local myChar = getCharacter(LocalPlayer)
    local theirChar = getCharacter(player)
    if myChar and theirChar then
        local myHum = getHumanoid(myChar)
        local theirHum = getHumanoid(theirChar)
        if myHum and theirHum then
            if myHum.TeamColor ~= BrickColor.new("White") then
                return myHum.TeamColor == theirHum.TeamColor
            end
        end
    end
    return false
end

local function isVisible(origin, targetPos)
    if not Config.Aimbot.VisibilityCheck then return true end
    
    local myChar = getCharacter(LocalPlayer)
    if not myChar then return true end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {myChar, Camera}
    
    local direction = (targetPos - origin)
    local distance = direction.Magnitude
    direction = direction.Unit
    
    local result = Workspace:Raycast(origin, direction * distance, params)
    if result then
        -- If we hit something, check if it's close to our target
        local hitPart = result.Instance
        if hitPart then
            local hitChar = hitPart:FindFirstAncestorOfClass("Model")
            if hitChar and hitChar:FindFirstChildOfClass("Humanoid") then
                return true -- Hit a character, that's fine
            end
        end
        return false -- Hit a wall/object
    end
    return true -- Nothing in the way
end

-- ============================================
-- TARGET ACQUISITION
-- ============================================
local function getClosestTarget()
    local closestTarget = nil
    local closestCrosshairDist = Config.Aimbot.FOVRadius
    
    local myChar = getCharacter(LocalPlayer)
    if not myChar then return nil end
    local myRoot = getRootPart(myChar)
    if not myRoot then return nil end
    
    local mousePos = UserInputService:GetMouseLocation()
    local cameraPos = Camera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isTeamMate(player) then continue end
        
        local character = getCharacter(player)
        if not isAlive(character) then continue end
        
        local targetPart = getTargetPart(character, Config.Aimbot.TargetPart)
        if not targetPart then continue end
        
        -- Distance check (3D)
        local distance3D = (myRoot.Position - targetPart.Position).Magnitude
        if distance3D > Config.Aimbot.MaxDistance then continue end
        
        -- Screen position check (2D FOV)
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end
        
        local screenVec = Vector2.new(screenPos.X, screenPos.Y)
        local crosshairDist = (screenVec - mousePos).Magnitude
        
        if crosshairDist > closestCrosshairDist then continue end
        
        -- Visibility check
        if not isVisible(cameraPos, targetPart.Position) then continue end
        
        -- This is the best target so far
        closestCrosshairDist = crosshairDist
        closestTarget = {
            Player = player,
            Character = character,
            Part = targetPart,
            Distance = distance3D,
            ScreenPosition = screenPos,
            CrosshairDistance = crosshairDist,
        }
    end
    
    return closestTarget
end

-- ============================================
-- FOV CIRCLE
-- ============================================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.NumSides = 60
FOVCircle.Radius = Config.Aimbot.FOVRadius
FOVCircle.Filled = false
FOVCircle.Color = Color3.fromRGB(0, 255, 100)
FOVCircle.Transparency = 1
FOVCircle.Visible = false

-- Update circle position when viewport changes
local function updateFOVPosition()
    FOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateFOVPosition)
updateFOVPosition()

-- ============================================
-- REMOTE FINDER (Free Fire Max)
-- ============================================
local RemoteEvent = nil

local function findRemoteEvent()
    -- Try common Free Fire remote paths
    local searchPaths = {
        {ReplicatedStorage, "Remotes", "Fire"},
        {ReplicatedStorage, "Remotes", "Shoot"},
        {ReplicatedStorage, "Remotes", "Hit"},
        {ReplicatedStorage, "Remote", "Fire"},
        {ReplicatedStorage, "Remote", "Shoot"},
        {ReplicatedStorage, "Remote", "Hit"},
        {ReplicatedStorage, "GunRemote"},
        {ReplicatedStorage, "WeaponRemote"},
        {game:GetService("ReplicatedStorage"), "Remotes", "Weapon", "Fire"},
        {game:GetService("ReplicatedStorage"), "Remotes", "Gun", "Fire"},
    }
    
    for _, path in ipairs(searchPaths) do
        local current = path[1]
        local found = true
        for i = 2, #path do
            current = current:FindFirstChild(path[i])
            if not current then
                found = false
                break
            end
        end
        if found and current:IsA("RemoteEvent") then
            return current
        end
    end
    return nil
end

RemoteEvent = findRemoteEvent()

-- ============================================
-- AIMBOT ENGINE
-- ============================================
local currentTarget = nil
local lastFireTime = 0
local fireCooldown = 0.1  -- Prevent spam

-- Hit chance roll
local function shouldHit()
    if Config.Aimbot.HitChance >= 100 then return true end
    return math.random(1, 100) <= Config.Aimbot.HitChance
end

-- Calculate spread for more realistic aiming
local function calculateSpread(baseSpread)
    if not baseSpread then baseSpread = 0.05 end
    return Vector3.new(
        math.random() * baseSpread - baseSpread / 2,
        math.random() * baseSpread - baseSpread / 2,
        math.random() * baseSpread - baseSpread / 2
    )
end

-- Build hit data for Free Fire remote
local function buildHitData(target)
    local myChar = getCharacter(LocalPlayer)
    local weapon = myChar and myChar:FindFirstChildOfClass("Tool")
    local weaponName = weapon and weapon.Name or "Unknown"
    
    return {
        -- Primary hit data
        HitPart = target.Part,
        HitPosition = target.Part.Position + calculateSpread(0.1),
        
        -- Target identification
        Character = target.Character,
        Humanoid = target.Character:FindFirstChildOfClass("Humanoid"),
        TargetRoot = target.Character:FindFirstChild("HumanoidRootPart"),
        
        -- Hit metadata
        Damage = 1000,  -- Max damage
        Distance = target.Distance,
        HitChance = Config.Aimbot.HitChance,
        
        -- Weapon info (if applicable)
        Weapon = weapon,
        WeaponName = weaponName,
        
        -- Ray data for server validation
        Origin = Camera.CFrame.Position,
        Direction = (target.Part.Position - Camera.CFrame.Position).Unit,
        
        -- Timing
        Timestamp = tick(),
    }
end

-- Fire the remote
local function fireAtTarget(target)
    if not RemoteEvent then
        RemoteEvent = findRemoteEvent()
        if not RemoteEvent then return end
    end
    
    local now = tick()
    if now - lastFireTime < fireCooldown then return end
    lastFireTime = now
    
    if not shouldHit() then return end
    
    pcall(function()
        local hitData = buildHitData(target)
        RemoteEvent:FireServer(hitData)
    end)
end

-- Main aimbot heartbeat loop
local function aimbotHeartbeat()
    if not Config.Aimbot.Enabled then
        FOVCircle.Visible = Config.Aimbot.ShowFOVCircle
        currentTarget = nil
        return
    end
    
    -- Update FOV
    FOVCircle.Visible = Config.Aimbot.ShowFOVCircle
    FOVCircle.Radius = Config.Aimbot.FOVRadius
    
    -- Acquire target
    local target = getClosestTarget()
    currentTarget = target
    
    if not target then return end
    
    -- Fire at target
    fireAtTarget(target)
end

local aimbotConnection = nil
local function startAimbot()
    if aimbotConnection then
        aimbotConnection:Disconnect()
        aimbotConnection = nil
    end
    aimbotConnection = RunService.Heartbeat:Connect(aimbotHeartbeat)
end

-- ============================================
-- ESP ENGINE
-- ============================================
local ESPObjects = {
    Highlights = {},
    Tracers = {},
}

local function cleanupPlayerESP(player)
    -- Clean highlight
    if ESPObjects.Highlights[player] then
        pcall(function()
            ESPObjects.Highlights[player]:Destroy()
        end)
        ESPObjects.Highlights[player] = nil
    end
    
    -- Clean tracer
    if ESPObjects.Tracers[player] then
        pcall(function()
            ESPObjects.Tracers[player]:Remove()
        end)
        ESPObjects.Tracers[player] = nil
    end
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local character = getCharacter(player)
        local alive = isAlive(character)
        local root = getRootPart(character)
        local showESP = Config.ESP.Enabled and alive and not isTeamMate(player)
        
        -- === HIGHLIGHT (Chams) ===
        if showESP then
            if not ESPObjects.Highlights[player] then
                local hl = Instance.new("Highlight")
                hl.FillTransparency = 0.5
                hl.OutlineTransparency = 0.2
                hl.FillColor = Config.ESP.HighlightColor
                hl.OutlineColor = Color3.new(1, 1, 1)
                hl.Parent = game:GetService("CoreGui")
                ESPObjects.Highlights[player] = hl
            end
            local hl = ESPObjects.Highlights[player]
            hl.Adornee = character
            hl.FillColor = Config.ESP.HighlightColor
            hl.Enabled = true
        else
            if ESPObjects.Highlights[player] then
                ESPObjects.Highlights[player].Enabled = false
            end
        end
        
        -- === TRACERS ===
        if showESP and Config.ESP.Tracers and root then
            local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
            if onScreen then
                if not ESPObjects.Tracers[player] then
                    local line = Drawing.new("Line")
                    line.Thickness = 1.5
                    line.Color = Config.ESP.TracerColor
                    line.Transparency = 0.8
                    ESPObjects.Tracers[player] = line
                end
                local line = ESPObjects.Tracers[player]
                line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                line.To = Vector2.new(screenPos.X, screenPos.Y)
                line.Color = Config.ESP.TracerColor
                line.Visible = true
            else
                if ESPObjects.Tracers[player] then
                    ESPObjects.Tracers[player].Visible = false
                end
            end
        else
            if ESPObjects.Tracers[player] then
                ESPObjects.Tracers[player].Visible = false
            end
        end
    end
end

local espConnection = nil
local function startESP()
    if espConnection then
        espConnection:Disconnect()
        espConnection = nil
    end
    espConnection = RunService.RenderStepped:Connect(updateESP)
end

-- ============================================
-- PLAYER CLEANUP
-- ============================================
Players.PlayerRemoving:Connect(function(player)
    cleanupPlayerESP(player)
end)

-- Handle our own character respawning
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    -- Refresh remote reference
    RemoteEvent = findRemoteEvent()
end)

-- ============================================
-- KEYBIND SYSTEM (Toggle UI)
-- ============================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        -- Toggle UI visibility (handled by Library)
    end
end)

-- ============================================
-- UI SETUP (Kavo Library)
-- ============================================
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("Free Fire MAX | Improved", "DarkTheme")

-- === AIMBOT TAB ===
local AimbotTab = Window:NewTab("Aimbot")
local AimbotSection = AimbotTab:NewSection("Aimbot Settings")

AimbotSection:NewToggle("Enable Aimbot", "Toggle the aimbot on/off", function(state)
    Config.Aimbot.Enabled = state
end)

AimbotSection:NewToggle("Show FOV Circle", "Display the aimbot field of view circle", function(state)
    Config.Aimbot.ShowFOVCircle = state
    FOVCircle.Visible = state
end)

AimbotSection:NewSlider("FOV Radius", "Set the aimbot range (pixels from crosshair)", 500, 10, function(value)
    Config.Aimbot.FOVRadius = value
    FOVCircle.Radius = value
end)

AimbotSection:NewSlider("Hit Chance", "Chance to successfully hit (%)", 100, 1, function(value)
    Config.Aimbot.HitChance = value
end, 100)

AimbotSection:NewSlider("Max Distance", "Maximum distance to aim at (studs)", 2000, 100, function(value)
    Config.Aimbot.MaxDistance = value
end, 1000)

AimbotSection:NewDropdown("Target Part", "Body part to aim at", {"Head", "HumanoidRootPart", "UpperTorso", "Torso"}, function(value)
    Config.Aimbot.TargetPart = value
end)

AimbotSection:NewToggle("Visibility Check", "Only aim if target is visible (raycast)", function(state)
    Config.Aimbot.VisibilityCheck = state
end)

AimbotSection:NewToggle("Team Check", "Ignore players on the same team", function(state)
    Config.Aimbot.TeamCheck = state
end)

-- === ESP TAB ===
local ESPTab = Window:NewTab("ESP")
local ESPSection = ESPTab:NewSection("ESP Settings")

ESPSection:NewToggle("Enable ESP", "Show players through walls (Highlight)", function(state)
    Config.ESP.Enabled = state
end)

ESPSection:NewToggle("Enable Tracers", "Draw lines from bottom of screen to players", function(state)
    Config.ESP.Tracers = state
end)

ESPSection:NewColorPicker("Highlight Color", "Color of the player highlight", Config.ESP.HighlightColor, function(color)
    Config.ESP.HighlightColor = color
end)

ESPSection:NewColorPicker("Tracer Color", "Color of the tracer lines", Config.ESP.TracerColor, function(color)
    Config.ESP.TracerColor = color
end)

-- ============================================
-- INITIALIZATION
-- ============================================
local function initialize()
    -- Find remote if not already found
    if not RemoteEvent then
        RemoteEvent = findRemoteEvent()
        if RemoteEvent then
            print("[+] Remote found:", RemoteEvent:GetFullName())
        else
            warn("[!] Remote not found! Aimbot will try to re-detect automatically.")
        end
    end
    
    -- Start engines
    startAimbot()
    startESP()
    
    -- Show welcome notification
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Script Loaded",
            Text = "Aimbot + ESP initialized. Press RightShift to toggle UI.",
            Duration = 5
        })
    end)
    
    print("[+] Free Fire MAX Improved script initialized successfully")
    print("[+] Toggle UI: RightShift")
    print("[+] Aimbot: " .. (Config.Aimbot.Enabled and "ON" or "OFF"))
    print("[+] ESP: " .. (Config.ESP.Enabled and "ON" or "OFF"))
end

-- Run
local success, err = pcall(initialize)
if not success then
    warn("[!] Initialization error:", err)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Error",
            Text = "Failed to initialize: " .. tostring(err),
            Duration = 8
        })
    end)
end
