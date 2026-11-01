local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CAS = game:GetService("ContextActionService")
local Camera = workspace.CurrentCamera
local LP = Players.LocalPlayer
local Characters = workspace:WaitForChild("Characters", 10) or workspace:FindFirstChild("Characters")

-- CONFIG
_G.Config = {
    Aimbot = false, AimbotKey = nil, AimbotUseVisibleCheck = true,
    Smoothness = 20, Fov = 150, ShowFov = false, HitChance = 100,
    Esp = false, EspBoxes = true, EspNames = true, EspTeamMode = "Enemies",
    UseTeamCheck = true, EnemyColor = Color3.fromRGB(255, 68, 68),
    TeammateColor = Color3.fromRGB(68, 255, 136), EspHealthBar = true,
    EspDistance = true, EspTracers = true, EspHeadDot = true, EspWeapon = false,
    TriggerBot = false, TriggerBotKey = nil, TriggerBotDelay = 0.1,
    AngryBot = false,
    MiscBhop = false, MiscSpeed = false, SpeedAmount = 30, SpeedKey = nil,
    MiscNoclip = false, NoclipKey = nil, InfiniteJump = false,
    FlyHack = false, FlyKey = nil, FlySpeed = 50,
    MiscThirdPerson = false, ThirdPersonDistance = 12, CameraFOV = 70,
    NoFog = false, FullBright = false, AntiLag = false, MenuKey = Enum.KeyCode.Insert,
    SkinChangerEnabled = false, CustomKnifeEnabled = false, SelectedKnife = "Butterfly Knife",
    SelectedSkins = {}
}

local state = {
    bindingKey = nil, aimbotKeyHeld = false, triggerBotKeyHeld = false,
    noclipParts = {}, originalSpeeds = {}, flyActive = false,
    angryBotLastShot = 0, angryBotRemote = nil, angryBotCurrentWeapon = nil,
    knifeSpawned = false, knifeInspecting = false, knifeSwinging = false, knifeLastAttackTime = 0,
    knifeVm = nil, knifeAnimator = nil, knifeEquipAnim = nil, knifeIdleAnim = nil, knifeInspectAnim = nil,
    knifeHeavySwingAnim = nil, knifeSwing1Anim = nil, knifeSwing2Anim = nil
}

-- UTILITIES
local Utilities = {}

function Utilities.isEnemy(p)
    if p == LP or not LP.Character or not p.Character then return false end
    if not _G.Config.UseTeamCheck then return true end
    local sameTeam = (LP.Character.Parent == p.Character.Parent)
    if _G.Config.EspTeamMode == "Enemies" then return not sameTeam
    elseif _G.Config.EspTeamMode == "Teammates" then return sameTeam
    else return true end
end

function Utilities.isVisibleForAimbot(targetChar)
    if not _G.Config.AimbotUseVisibleCheck or not targetChar or not LP.Character then return true end
    local origin = LP.Character:FindFirstChild("Head") or LP.Character:FindFirstChild("HumanoidRootPart")
    if not origin then return false end
    local targetHead = targetChar:FindFirstChild("Head")
    if not targetHead then return false end
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {LP.Character, targetChar}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    return workspace:Raycast(origin.Position, targetHead.Position - origin.Position, rayParams) == nil
end

function Utilities.getMoveDirection()
    local dir = Vector3.zero
    local lookVec = Camera.CFrame.LookVector
    local rightVec = Camera.CFrame.RightVector
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + lookVec end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - lookVec end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - rightVec end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + rightVec end
    return Vector3.new(dir.X, 0, dir.Z).Unit
end

function Utilities.create(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    return obj
end

-- MOVEMENT
local Movement = {}

function Movement.updateSpeed()
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return end
    local hrp = LP.Character.HumanoidRootPart
    local hum = LP.Character:FindFirstChild("Humanoid")
    if not hum then return end
    
    local speedActive = _G.Config.MiscSpeed and (_G.Config.SpeedKey == nil or UIS:IsKeyDown(_G.Config.SpeedKey))
    
    if speedActive and hum.MoveDirection.Magnitude > 0 then
        local speedMultiplier = _G.Config.SpeedAmount / 16
        local moveDirection = hum.MoveDirection
        hrp.CFrame = hrp.CFrame + (moveDirection * (speedMultiplier - 1) * 0.3)
    end
end

function Movement.setupNoclip()
    local PhysicsService = game:GetService("PhysicsService")
    
    pcall(function()
        if not PhysicsService:IsCollisionGroupRegistered("NoClipGroup") then
            PhysicsService:RegisterCollisionGroup("NoClipGroup")
        end
        PhysicsService:CollisionGroupSetCollidable("NoClipGroup", "Default", false)
    end)
end

function Movement.updateNoclip()
    if not LP.Character then return end
    local noclipActive = _G.Config.MiscNoclip and (_G.Config.NoclipKey == nil or UIS:IsKeyDown(_G.Config.NoclipKey))
    
    for _, part in pairs(LP.Character:GetDescendants()) do
        if part:IsA("BasePart") then
            if noclipActive then
                if not state.noclipParts[part] then
                    state.noclipParts[part] = part.CanCollide
                end
                part.CanCollide = false
                pcall(function()
                    game:GetService("PhysicsService"):SetPartCollisionGroup(part, "NoClipGroup")
                end)
            else
                if state.noclipParts[part] ~= nil then
                    part.CanCollide = state.noclipParts[part]
                    state.noclipParts[part] = nil
                    pcall(function()
                        game:GetService("PhysicsService"):SetPartCollisionGroup(part, "Default")
                    end)
                end
            end
        end
    end
end

function Movement.updateFly()
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then
        state.flyActive = false
        return
    end
    
    local hrp = LP.Character.HumanoidRootPart
    local hum = LP.Character:FindFirstChild("Humanoid")
    if not hum then return end
    
    if _G.Config.FlyHack then
        state.flyActive = true
        hum.PlatformStand = true
        
        local move = Vector3.new()
        if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + Camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - Camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - Camera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + Camera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end
        
        if move.Magnitude > 0 then
            move = move.Unit * _G.Config.FlySpeed
            hrp.Velocity = move
        else
            hrp.Velocity = Vector3.new(0, 0, 0)
        end
        
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + Camera.CFrame.LookVector)
    else
        if state.flyActive then
            hum.PlatformStand = false
            hrp.Velocity = Vector3.new(0, 0, 0)
            state.flyActive = false
        end
    end
end

function Movement.updateBhop()
    if not LP.Character or not LP.Character:FindFirstChild("Humanoid") or _G.Config.FlyHack then return end
    
    if _G.Config.MiscBhop and UIS:IsKeyDown(Enum.KeyCode.Space) then
        local hrp = LP.Character:FindFirstChild("HumanoidRootPart")
        local hum = LP.Character:FindFirstChild("Humanoid")
        if hrp and hum then
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {LP.Character}
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            local groundCheck = workspace:Raycast(hrp.Position, Vector3.new(0, -4, 0), rayParams)
            if groundCheck then hum.Jump = true end
            
            local success, moveDir = pcall(Utilities.getMoveDirection)
            if success and moveDir.Magnitude > 0 then
                local bhopSpeed = 18
                local smoothness = 0.2
                local velocity = hrp.AssemblyLinearVelocity
                local targetDir = moveDir * bhopSpeed
                local newX = velocity.X + (targetDir.X - velocity.X) * smoothness
                local newZ = velocity.Z + (targetDir.Z - velocity.Z) * smoothness
                hrp.AssemblyLinearVelocity = Vector3.new(newX, velocity.Y, newZ)
            end
        end
    end
end

function Movement.updateInfiniteJump()
    if _G.Config.InfiniteJump and UIS:IsKeyDown(Enum.KeyCode.Space) then
        local c = LP.Character
        if c and c:FindFirstChild("Humanoid") then c.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end

-- 自定义刀 + 皮肤更换 (from BloxStrike)
local RS = game:GetService("ReplicatedStorage")
pcall(function()
    local k = RS.Assets and RS.Assets.Weapons and RS.Assets.Weapons:FindFirstChild("Karambit")
    if k and k.Camera and k.Camera:FindFirstChild("ViewmodelLight") then
        k.Camera.ViewmodelLight.Transparency = 1
    end
end)
local KNIFE_ACTION_INSPECT = "InspectKnifeAction"
local KNIFE_ACTION_ATTACK = "AttackKnifeAction"
local KNIFE_ATTACK_COOLDOWN = 1
local knives = {
    ["Karambit"] = {Offset = CFrame.new(0, -1.5, 1.5)},
    ["Butterfly Knife"] = {Offset = CFrame.new(0, -1.5, 1.5)},
    ["M9 Bayonet"] = {Offset = CFrame.new(0, -1.5, 1)},
    ["Flip Knife"] = {Offset = CFrame.new(0, -1.5, 1.25)},
    ["Gut Knife"] = {Offset = CFrame.new(0, -1.5, 0.5)},
}

local function isAliveKnife()
    if not Characters then return nil end
    local t = Characters:FindFirstChild("Terrorists")
    local ct = Characters:FindFirstChild("Counter-Terrorists")
    return (t and t:FindFirstChild(LP.Name)) or (ct and ct:FindFirstChild(LP.Name))
end

local function getKnifeInCamera()
    return Camera:FindFirstChild("T Knife") or Camera:FindFirstChild("CT Knife")
end

local function cleanPart(part)
    if not part:IsA("BasePart") then return end
    part.CanCollide = false
    part.Anchored = false
    part.CastShadow = false
    part.CanTouch = false
    part.CanQuery = false
end

local function disableCollisions(model)
    for _, part in model:GetDescendants() do
        cleanPart(part)
    end
end

local function hideOriginalKnife(knife)
    if not knife then return end
    for _, part in knife:GetDescendants() do
        if part:IsA("BasePart") or part:IsA("MeshPart") then
            part.Transparency = 1
        end
        if part:IsA("Texture") then
            part.Transparency = 1
        end
    end
end

local function playKnifeSound(folder, name)
    local weaponSounds = RS.Sounds:FindFirstChild(_G.Config.SelectedKnife)
    if not weaponSounds then return nil end
    local f = weaponSounds:FindFirstChild(folder)
    if not f then return nil end
    local sound = f:FindFirstChild(name)
    if not sound then return nil end
    local s = sound:Clone()
    s.Parent = Camera
    s:Play()
    s.Ended:Once(function() s:Destroy() end)
    return s
end

local function attachAsset(folder, armPartName, assetModelName, finalName, offset)
    if not state.knifeVm then return end
    local targetArm = state.knifeVm:FindFirstChild(armPartName)
    if not targetArm then return end
    local assetMesh = folder:WaitForChild(assetModelName):Clone()
    cleanPart(assetMesh)
    assetMesh.Name = finalName
    assetMesh.Parent = targetArm
    local motor = Instance.new("Motor6D")
    motor.Part0 = targetArm
    motor.Part1 = assetMesh
    motor.C0 = offset
    motor.Parent = targetArm
end

local function handleKnifeAction(actionName, inputState, inputObject)
    if inputState ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end
    if not state.knifeSpawned or not state.knifeAnimator or not isAliveKnife() then
        return Enum.ContextActionResult.Pass
    end
    if actionName == KNIFE_ACTION_INSPECT then
        if (state.knifeEquipAnim and state.knifeEquipAnim.IsPlaying) or state.knifeInspecting or state.knifeSwinging then
            return Enum.ContextActionResult.Pass
        end
        state.knifeInspecting = true
        if state.knifeIdleAnim then state.knifeIdleAnim:Stop() end
        state.knifeInspectAnim:Play()
        state.knifeInspectAnim.Stopped:Once(function() state.knifeInspecting = false end)
    elseif actionName == KNIFE_ACTION_ATTACK then
        local currentTime = os.clock()
        if (state.knifeEquipAnim and state.knifeEquipAnim.IsPlaying) or (currentTime - state.knifeLastAttackTime < KNIFE_ATTACK_COOLDOWN) then
            return Enum.ContextActionResult.Pass
        end
        state.knifeLastAttackTime = currentTime
        if state.knifeInspecting then
            state.knifeInspecting = false
            if state.knifeInspectAnim then state.knifeInspectAnim:Stop() end
        end
        state.knifeSwinging = true
        if state.knifeIdleAnim then state.knifeIdleAnim:Stop() end
        local anims = {state.knifeHeavySwingAnim, state.knifeSwing1Anim, state.knifeSwing2Anim}
        local chosenAnim = anims[math.random(1, #anims)]
        local soundFolder = (chosenAnim == state.knifeHeavySwingAnim and "HitOne") or (chosenAnim == state.knifeSwing1Anim and "HitTwo") or "HitThree"
        chosenAnim:Play()
        local s = playKnifeSound(soundFolder, "1")
        if s then s.Volume = 5 end
        chosenAnim.Stopped:Once(function() state.knifeSwinging = false end)
    end
    return Enum.ContextActionResult.Pass
end

local function removeKnifeViewmodel()
    state.knifeSpawned = false
    CAS:UnbindAction(KNIFE_ACTION_INSPECT)
    CAS:UnbindAction(KNIFE_ACTION_ATTACK)
    if state.knifeVm then
        state.knifeVm:Destroy()
        state.knifeVm = nil
    end
    state.knifeAnimator = nil
    state.knifeInspecting = false
    state.knifeSwinging = false
end

local function spawnKnifeViewmodel(knife)
    if state.knifeSpawned or not _G.Config.CustomKnifeEnabled then return end
    local myModel = isAliveKnife()
    if not myModel then return end
    local knifeTemplate = RS.Assets and RS.Assets.Weapons and RS.Assets.Weapons:FindFirstChild(_G.Config.SelectedKnife)
    if not knifeTemplate then return end
    local knifeOffset = knives[_G.Config.SelectedKnife] and knives[_G.Config.SelectedKnife].Offset or CFrame.new(0, -1.5, 1.5)
    state.knifeSpawned = true
    state.knifeVm = knifeTemplate:WaitForChild("Camera"):Clone()
    state.knifeVm.Name = _G.Config.SelectedKnife
    state.knifeVm.Parent = Camera
    disableCollisions(state.knifeVm)
    hideOriginalKnife(knife)
    if myModel.Parent.Name == "Terrorists" then
        local tGloves = RS.Assets.Weapons:FindFirstChild("T Glove")
        if tGloves then
            attachAsset(tGloves, "Left Arm", "Left Arm", "Glove", CFrame.new(0, 0, -1.5))
            attachAsset(tGloves, "Right Arm", "Right Arm", "Glove", CFrame.new(0, 0, -1.5))
        end
    else
        local sleeves = RS.Assets.Sleeves and RS.Assets.Sleeves:FindFirstChild("IDF")
        local ctGloves = RS.Assets.Weapons and RS.Assets.Weapons:FindFirstChild("CT Glove")
        if sleeves then
            attachAsset(sleeves, "Left Arm", "Left Arm", "Sleeve", CFrame.new(0, 0, 0.5))
            attachAsset(sleeves, "Right Arm", "Right Arm", "Sleeve", CFrame.new(0, 0, 0.5))
        end
        if ctGloves then
            attachAsset(ctGloves, "Left Arm", "Left Arm", "Glove", CFrame.new(0, 0, -1.5))
            attachAsset(ctGloves, "Right Arm", "Right Arm", "Glove", CFrame.new(0, 0, -1.5))
        end
    end
    local animController = state.knifeVm:FindFirstChildOfClass("AnimationController") or state.knifeVm:FindFirstChildOfClass("Animator")
    state.knifeAnimator = animController and (animController:FindFirstChildWhichIsA("Animator") or animController)
    if not state.knifeAnimator then removeKnifeViewmodel() return end
    local animFolder = RS.Assets.WeaponAnimations and RS.Assets.WeaponAnimations:FindFirstChild(_G.Config.SelectedKnife) and RS.Assets.WeaponAnimations:FindFirstChild(_G.Config.SelectedKnife):FindFirstChild("CameraAnimations")
    if not animFolder then removeKnifeViewmodel() return end
    state.knifeEquipAnim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Equip"))
    state.knifeIdleAnim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Idle"))
    state.knifeInspectAnim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Inspect"))
    state.knifeHeavySwingAnim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Heavy Swing"))
    state.knifeSwing1Anim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Swing1"))
    state.knifeSwing2Anim = state.knifeAnimator:LoadAnimation(animFolder:WaitForChild("Swing2"))
    state.knifeVm:SetPrimaryPartCFrame(Camera.CFrame * CFrame.new(0, -1.5, 5))
    TweenService:Create(state.knifeVm.PrimaryPart, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = Camera.CFrame * knifeOffset
    }):Play()
    state.knifeEquipAnim:Play()
    playKnifeSound("Equip", "1")
    CAS:BindAction(KNIFE_ACTION_INSPECT, handleKnifeAction, false, Enum.KeyCode.F)
    CAS:BindAction(KNIFE_ACTION_ATTACK, handleKnifeAction, false, Enum.UserInputType.MouseButton1)
end

local SkinChanger = {}
local SKIN_WEAR = "Factory New"
local function getSkinsFolder()
    local a = RS:FindFirstChild("Assets")
    return a and a:FindFirstChild("Skins")
end
local IgnoreFolders = {
    ["HE Grenade"] = true, ["Incendiary Grenade"] = true, ["Molotov"] = true,
    ["Smoke Grenade"] = true, ["Flashbang"] = true, ["Decoy Grenade"] = true,
    ["C4"] = true, ["CT Glove"] = true, ["T Glove"] = true
}

function SkinChanger.isAliveSkin()
    if not Characters then return false end
    local t = Characters:FindFirstChild("Terrorists")
    local ct = Characters:FindFirstChild("Counter-Terrorists")
    return (t and t:FindFirstChild(LP.Name)) or (ct and ct:FindFirstChild(LP.Name))
end

function SkinChanger.applyWeaponSkin(model)
    if not model or not _G.Config.SkinChangerEnabled or not SkinChanger.isAliveSkin() then return end
    local skinName = _G.Config.SelectedSkins[model.Name]
    if not skinName then return end
    pcall(function()
        local SkinsFolder = getSkinsFolder()
        if not SkinsFolder then return end
        local skinFolder = SkinsFolder:FindFirstChild(model.Name)
        if not skinFolder then return end
        local skinType = skinFolder:FindFirstChild(skinName)
        local sourceFolder = skinType and skinType:FindFirstChild("Camera") and skinType.Camera:FindFirstChild(SKIN_WEAR)
        if not sourceFolder then return end
        for _, obj in Camera:GetChildren() do
            local left = obj:FindFirstChild("Left Arm")
            local right = obj:FindFirstChild("Right Arm")
            if left or right then
                local gloveFolder = SkinsFolder:FindFirstChild("Sports Gloves")
                local gloveSkin = gloveFolder and gloveFolder:FindFirstChild(_G.Config.SelectedSkins["Sports Gloves"])
                local gloveSource = gloveSkin and gloveSkin:FindFirstChild("Camera") and gloveSkin.Camera:FindFirstChild(SKIN_WEAR)
                if gloveSource then
                    for _, side in {"Left Arm", "Right Arm"} do
                        local arm = obj:FindFirstChild(side)
                        local src = gloveSource:FindFirstChild(side)
                        if arm and src then
                            local gloveMesh = arm:FindFirstChild("Glove")
                            if gloveMesh then
                                local existing = gloveMesh:FindFirstChildOfClass("SurfaceAppearance")
                                if existing then existing:Destroy() end
                                local clone = src:Clone()
                                clone.Name = "SurfaceAppearance"
                                clone.Parent = gloveMesh
                            end
                        end
                    end
                end
            end
        end
        local GLOVES = { ["Sports Gloves"] = true }
        if not GLOVES[model.Name] then
            local weaponFolder = model:FindFirstChild("Weapon")
            if weaponFolder then
                for _, part in weaponFolder:GetDescendants() do
                    if part:IsA("BasePart") then
                        local newSkin = sourceFolder:FindFirstChild(part.Name)
                        if newSkin then
                            local existing = part:FindFirstChildOfClass("SurfaceAppearance")
                            if existing then existing:Destroy() end
                            local clone = newSkin:Clone()
                            clone.Name = "SurfaceAppearance"
                            clone.Parent = part
                        end
                    end
                end
            end
        end
        model:SetAttribute("SkinApplied", skinName)
    end)
end

-- VISUALS
local Visuals = {}
local Lighting = game:GetService("Lighting")
local originalLightingSettings = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient
}

function Visuals.updateFullBright()
    if _G.Config.FullBright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    else
        Lighting.Brightness = originalLightingSettings.Brightness
        Lighting.ClockTime = originalLightingSettings.ClockTime
        Lighting.GlobalShadows = originalLightingSettings.GlobalShadows
        Lighting.Ambient = originalLightingSettings.Ambient
    end
end

function Visuals.updateNoFog()
    if _G.Config.NoFog then
        Lighting.FogEnd = 100000
        for _, v in pairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") then v.Density = 0 end
        end
    else
        Lighting.FogEnd = originalLightingSettings.FogEnd
    end
end

function Visuals.updateAntiLag()
    local Terrain = workspace:FindFirstChildOfClass("Terrain")
    if _G.Config.AntiLag then
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                v.Enabled = false
            end
            if v:IsA("MeshPart") or v:IsA("UnionOperation") then
                v.Material = Enum.Material.SmoothPlastic
                v.CastShadow = false
            end
        end
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 0
        end
    end
end

function Visuals.updateThirdPerson()
    if _G.Config.MiscThirdPerson and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character:FindFirstChild("Humanoid") then
        local root = LP.Character.HumanoidRootPart
        local hum = LP.Character.Humanoid
        
        local distance = _G.Config.ThirdPersonDistance
        local cameraCFrame = Camera.CFrame
        
        local rayOrigin = root.Position
        local rayDirection = -cameraCFrame.LookVector * distance
        
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {LP.Character}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        
        local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)
        local finalDistance = rayResult and (rayResult.Position - rayOrigin).Magnitude - 0.5 or distance
        
        local targetPos = root.Position - cameraCFrame.LookVector * finalDistance + Vector3.new(0, 1.5, 0)
        Camera.CFrame = CFrame.new(targetPos, root.Position + Vector3.new(0, 1.5, 0))
        
        hum.CameraOffset = Vector3.new(0, 0, 0)
    end
end

function Visuals.updateCameraFOV()
    if _G.Config.CameraFOV ~= 70 then
        Camera.FieldOfView = _G.Config.CameraFOV
    end
end

-- ESP
local ESP = {}
local ESP_Table = {}

function ESP.createESP()
    return {
        -- Main box (full outline)
        BoxOutline = Drawing.new("Square"),
        BoxMain = Drawing.new("Square"),
        
        -- Corner accents
        CornerTL1 = Drawing.new("Line"), CornerTL2 = Drawing.new("Line"),
        CornerTR1 = Drawing.new("Line"), CornerTR2 = Drawing.new("Line"),
        CornerBL1 = Drawing.new("Line"), CornerBL2 = Drawing.new("Line"),
        CornerBR1 = Drawing.new("Line"), CornerBR2 = Drawing.new("Line"),
        
        -- Text elements
        Name = Drawing.new("Text"),
        NameShadow = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        HealthText = Drawing.new("Text"),
        WeaponText = Drawing.new("Text"),
        
        -- Health bar system
        HealthBarBg = Drawing.new("Square"),
        HealthBarMain = Drawing.new("Square"),
        HealthBarOutline = Drawing.new("Square"),
        
        -- Armor bar
        ArmorBarBg = Drawing.new("Square"),
        ArmorBarMain = Drawing.new("Square"),
        
        -- Tracer and effects
        Tracer = Drawing.new("Line"),
        HeadDot = Drawing.new("Circle"),
        HeadDotOutline = Drawing.new("Circle"),
        
        -- Skeleton lines
        SkeletonLines = {}
    }
end

function ESP.update()
    for _, p in pairs(Players:GetPlayers()) do
        if not _G.Config.Esp or p == LP then
            if ESP_Table[p] then 
                for _, d in pairs(ESP_Table[p]) do 
                    if typeof(d) == "table" then
                        for _, line in pairs(d) do
                            line.Visible = false
                        end
                    else
                        d.Visible = false 
                    end
                end 
            end
        else
            local show = Utilities.isEnemy(p) or (_G.Config.EspTeamMode ~= "Enemies")
            if show and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
                if not ESP_Table[p] then ESP_Table[p] = ESP.createESP() end
                local data = ESP_Table[p]
                local root = p.Character.HumanoidRootPart
                local head = p.Character:FindFirstChild("Head")
                local humanoid = p.Character.Humanoid
                local pos, vis = Camera:WorldToViewportPoint(root.Position)
                
                if vis and pos.Z > 0 then
                    local isEnemy = Utilities.isEnemy(p)
                    local color = isEnemy and _G.Config.EnemyColor or _G.Config.TeammateColor
                    local accentColor = isEnemy and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(75, 150, 255)
                    
                    local distance = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") 
                        and (LP.Character.HumanoidRootPart.Position - root.Position).Magnitude or 0
                    local alpha = math.clamp(1 - (distance / 600), 0.4, 1)
                    local size = math.clamp(2400 / pos.Z, 18, 90)
                    
                    -- Box dimensions
                    local boxW = size
                    local boxH = size * 1.8
                    local boxX = pos.X - boxW/2
                    local boxY = pos.Y - boxH * 0.52
                    
                    -- Modern box with outline
                    if _G.Config.EspBoxes then
                        -- Outer outline (darker)
                        data.BoxOutline.Visible = true
                        data.BoxOutline.Size = Vector2.new(boxW + 4, boxH + 4)
                        data.BoxOutline.Position = Vector2.new(boxX - 2, boxY - 2)
                        data.BoxOutline.Color = Color3.new(0, 0, 0)
                        data.BoxOutline.Thickness = 3
                        data.BoxOutline.Transparency = alpha * 0.8
                        data.BoxOutline.Filled = false
                        
                        -- Main box
                        data.BoxMain.Visible = true
                        data.BoxMain.Size = Vector2.new(boxW, boxH)
                        data.BoxMain.Position = Vector2.new(boxX, boxY)
                        data.BoxMain.Color = color
                        data.BoxMain.Thickness = 1
                        data.BoxMain.Transparency = alpha
                        data.BoxMain.Filled = false
                        
                        -- Corner accents (CS2 style)
                        local cornerLen = boxW * 0.2
                        local cornerThick = 2.5
                        
                        -- Top-left corners
                        data.CornerTL1.Visible, data.CornerTL2.Visible = true, true
                        data.CornerTL1.From = Vector2.new(boxX - 1, boxY - 1)
                        data.CornerTL1.To = Vector2.new(boxX + cornerLen, boxY - 1)
                        data.CornerTL2.From = Vector2.new(boxX - 1, boxY - 1)
                        data.CornerTL2.To = Vector2.new(boxX - 1, boxY + cornerLen)
                        data.CornerTL1.Color, data.CornerTL2.Color = accentColor, accentColor
                        data.CornerTL1.Thickness, data.CornerTL2.Thickness = cornerThick, cornerThick
                        data.CornerTL1.Transparency, data.CornerTL2.Transparency = alpha, alpha
                        
                        -- Top-right corners
                        data.CornerTR1.Visible, data.CornerTR2.Visible = true, true
                        data.CornerTR1.From = Vector2.new(boxX + boxW - cornerLen, boxY - 1)
                        data.CornerTR1.To = Vector2.new(boxX + boxW + 1, boxY - 1)
                        data.CornerTR2.From = Vector2.new(boxX + boxW + 1, boxY - 1)
                        data.CornerTR2.To = Vector2.new(boxX + boxW + 1, boxY + cornerLen)
                        data.CornerTR1.Color, data.CornerTR2.Color = accentColor, accentColor
                        data.CornerTR1.Thickness, data.CornerTR2.Thickness = cornerThick, cornerThick
                        data.CornerTR1.Transparency, data.CornerTR2.Transparency = alpha, alpha
                        
                        -- Bottom-left corners
                        data.CornerBL1.Visible, data.CornerBL2.Visible = true, true
                        data.CornerBL1.From = Vector2.new(boxX - 1, boxY + boxH + 1)
                        data.CornerBL1.To = Vector2.new(boxX + cornerLen, boxY + boxH + 1)
                        data.CornerBL2.From = Vector2.new(boxX - 1, boxY + boxH - cornerLen)
                        data.CornerBL2.To = Vector2.new(boxX - 1, boxY + boxH + 1)
                        data.CornerBL1.Color, data.CornerBL2.Color = accentColor, accentColor
                        data.CornerBL1.Thickness, data.CornerBL2.Thickness = cornerThick, cornerThick
                        data.CornerBL1.Transparency, data.CornerBL2.Transparency = alpha, alpha
                        
                        -- Bottom-right corners
                        data.CornerBR1.Visible, data.CornerBR2.Visible = true, true
                        data.CornerBR1.From = Vector2.new(boxX + boxW - cornerLen, boxY + boxH + 1)
                        data.CornerBR1.To = Vector2.new(boxX + boxW + 1, boxY + boxH + 1)
                        data.CornerBR2.From = Vector2.new(boxX + boxW + 1, boxY + boxH - cornerLen)
                        data.CornerBR2.To = Vector2.new(boxX + boxW + 1, boxY + boxH + 1)
                        data.CornerBR1.Color, data.CornerBR2.Color = accentColor, accentColor
                        data.CornerBR1.Thickness, data.CornerBR2.Thickness = cornerThick, cornerThick
                        data.CornerBR1.Transparency, data.CornerBR2.Transparency = alpha, alpha
                    else
                        data.BoxOutline.Visible = false
                        data.BoxMain.Visible = false
                        data.CornerTL1.Visible, data.CornerTL2.Visible = false, false
                        data.CornerTR1.Visible, data.CornerTR2.Visible = false, false
                        data.CornerBL1.Visible, data.CornerBL2.Visible = false, false
                        data.CornerBR1.Visible, data.CornerBR2.Visible = false, false
                    end
                    
                    -- Name with shadow (CS2 style)
                    if _G.Config.EspNames then
                        local nameSize = math.clamp(size / 3.5, 13, 18)
                        local nameY = boxY - nameSize - 6
                        
                        -- Shadow
                        data.NameShadow.Visible = true
                        data.NameShadow.Text = p.Name
                        data.NameShadow.Size = nameSize
                        data.NameShadow.Center = true
                        data.NameShadow.Outline = false
                        data.NameShadow.Color = Color3.new(0, 0, 0)
                        data.NameShadow.Transparency = alpha * 0.8
                        data.NameShadow.Font = 3
                        data.NameShadow.Position = Vector2.new(pos.X + 1, nameY + 1)
                        
                        -- Main text
                        data.Name.Visible = true
                        data.Name.Text = p.Name
                        data.Name.Size = nameSize
                        data.Name.Center = true
                        data.Name.Outline = false
                        data.Name.Color = Color3.new(1, 1, 1)
                        data.Name.Transparency = alpha
                        data.Name.Font = 3
                        data.Name.Position = Vector2.new(pos.X, nameY)
                    else
                        data.Name.Visible = false
                        data.NameShadow.Visible = false
                    end
                    
                    -- CS2-style health bar (left side)
                    if _G.Config.EspHealthBar then
                        local hp = humanoid.Health / humanoid.MaxHealth
                        local barW = 3
                        local barH = boxH
                        local barX = boxX - 8
                        local barY = boxY
                        
                        -- Background
                        data.HealthBarBg.Visible = true
                        data.HealthBarBg.Size = Vector2.new(barW, barH)
                        data.HealthBarBg.Position = Vector2.new(barX, barY)
                        data.HealthBarBg.Color = Color3.new(0.1, 0.1, 0.1)
                        data.HealthBarBg.Filled = true
                        data.HealthBarBg.Transparency = 0.6
                        
                        -- Outline
                        data.HealthBarOutline.Visible = true
                        data.HealthBarOutline.Size = Vector2.new(barW + 2, barH + 2)
                        data.HealthBarOutline.Position = Vector2.new(barX - 1, barY - 1)
                        data.HealthBarOutline.Color = Color3.new(0, 0, 0)
                        data.HealthBarOutline.Filled = false
                        data.HealthBarOutline.Thickness = 1
                        data.HealthBarOutline.Transparency = alpha * 0.7
                        
                        -- Health gradient (green to red)
                        local healthColor
                        if hp > 0.6 then
                            healthColor = Color3.fromRGB(100, 255, 100)
                        elseif hp > 0.3 then
                            healthColor = Color3.fromRGB(255, 200, 50)
                        else
                            healthColor = Color3.fromRGB(255, 50, 50)
                        end
                        
                        data.HealthBarMain.Visible = true
                        data.HealthBarMain.Size = Vector2.new(barW, barH * hp)
                        data.HealthBarMain.Position = Vector2.new(barX, barY + barH * (1 - hp))
                        data.HealthBarMain.Color = healthColor
                        data.HealthBarMain.Filled = true
                        data.HealthBarMain.Transparency = alpha
                        
                        -- Health text
                        if hp < 1 then
                            data.HealthText.Visible = true
                            data.HealthText.Text = tostring(math.floor(hp * 100))
                            data.HealthText.Size = 12
                            data.HealthText.Center = false
                            data.HealthText.Outline = true
                            data.HealthText.OutlineColor = Color3.new(0, 0, 0)
                            data.HealthText.Color = healthColor
                            data.HealthText.Transparency = alpha
                            data.HealthText.Font = 2
                            data.HealthText.Position = Vector2.new(barX - 24, barY + barH * (1 - hp) - 6)
                        else
                            data.HealthText.Visible = false
                        end
                    else
                        data.HealthBarBg.Visible = false
                        data.HealthBarMain.Visible = false
                        data.HealthBarOutline.Visible = false
                        data.HealthText.Visible = false
                    end
                    
                    -- Distance indicator
                    if _G.Config.EspDistance then
                        data.Distance.Visible = true
                        data.Distance.Text = string.format("%dm", math.floor(distance))
                        data.Distance.Size = math.clamp(size / 4.5, 11, 14)
                        data.Distance.Center = true
                        data.Distance.Outline = true
                        data.Distance.OutlineColor = Color3.new(0, 0, 0)
                        data.Distance.Color = Color3.fromRGB(220, 220, 220)
                        data.Distance.Transparency = alpha
                        data.Distance.Font = 2
                        data.Distance.Position = Vector2.new(pos.X, boxY + boxH + 4)
                    else
                        data.Distance.Visible = false
                    end
                    
                    -- Weapon text (if you want to add this feature)
                    if _G.Config.EspWeapon then
                        local weapon = p.Character:FindFirstChildOfClass("Tool")
                        if weapon then
                            data.WeaponText.Visible = true
                            data.WeaponText.Text = weapon.Name
                            data.WeaponText.Size = 11
                            data.WeaponText.Center = true
                            data.WeaponText.Outline = true
                            data.WeaponText.OutlineColor = Color3.new(0, 0, 0)
                            data.WeaponText.Color = Color3.fromRGB(200, 200, 255)
                            data.WeaponText.Transparency = alpha
                            data.WeaponText.Font = 2
                            data.WeaponText.Position = Vector2.new(pos.X, boxY + boxH + 18)
                        else
                            data.WeaponText.Visible = false
                        end
                    else
                        data.WeaponText.Visible = false
                    end
                    
                    -- Tracers (from bottom center)
                    if _G.Config.EspTracers then
                        data.Tracer.Visible = true
                        data.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                        data.Tracer.To = Vector2.new(pos.X, boxY + boxH)
                        data.Tracer.Color = accentColor
                        data.Tracer.Thickness = 1.2
                        data.Tracer.Transparency = alpha * 0.4
                    else
                        data.Tracer.Visible = false
                    end
                    
                    -- Head dot with outline
                    if _G.Config.EspHeadDot and head then
                        local hPos, hVis = Camera:WorldToViewportPoint(head.Position)
                        if hVis and hPos.Z > 0 then
                            local dotSize = math.clamp(size / 10, 4, 8)
                            
                            -- Outline
                            data.HeadDotOutline.Visible = true
                            data.HeadDotOutline.Radius = dotSize + 1
                            data.HeadDotOutline.Position = Vector2.new(hPos.X, hPos.Y)
                            data.HeadDotOutline.Color = Color3.new(0, 0, 0)
                            data.HeadDotOutline.Filled = true
                            data.HeadDotOutline.Transparency = alpha * 0.8
                            
                            -- Main dot
                            data.HeadDot.Visible = true
                            data.HeadDot.Radius = dotSize
                            data.HeadDot.Position = Vector2.new(hPos.X, hPos.Y)
                            data.HeadDot.Color = accentColor
                            data.HeadDot.Filled = true
                            data.HeadDot.Transparency = alpha
                        else
                            data.HeadDot.Visible = false
                            data.HeadDotOutline.Visible = false
                        end
                    else
                        data.HeadDot.Visible = false
                        data.HeadDotOutline.Visible = false
                    end
                else
                    -- Hide all when not visible
                    for k, d in pairs(data) do
                        if typeof(d) == "table" then
                            for _, line in pairs(d) do
                                line.Visible = false
                            end
                        else
                            d.Visible = false
                        end
                    end
                end
            elseif ESP_Table[p] then
                for k, d in pairs(ESP_Table[p]) do
                    if typeof(d) == "table" then
                        for _, line in pairs(d) do
                            line.Visible = false
                        end
                    else
                        d.Visible = false
                    end
                end
            end
        end
    end
    
    -- Cleanup disconnected players
    for p, data in pairs(ESP_Table) do
        if not p or not p.Parent or not Players:FindFirstChild(p.Name) then
            for k, d in pairs(data) do
                if typeof(d) == "table" then
                    for _, line in pairs(d) do
                        line.Visible = false
                        line:Remove()
                    end
                else
                    d.Visible = false
                    d:Remove()
                end
            end
            ESP_Table[p] = nil
        end
    end
end

-- AIMBOT
local Aimbot = {}
local FovCircle = Drawing.new("Circle")
FovCircle.Color = Color3.fromRGB(255, 68, 68)
FovCircle.Thickness = 2
FovCircle.NumSides = 64
FovCircle.Transparency = 0.6
FovCircle.Filled = false

function Aimbot.updateFOV()
    FovCircle.Visible = _G.Config.ShowFov
    FovCircle.Radius = _G.Config.Fov
    FovCircle.Position = UIS:GetMouseLocation()
end

function Aimbot.update()
    local aimbotActive = _G.Config.Aimbot and (_G.Config.AimbotKey == nil or state.aimbotKeyHeld)
    if aimbotActive and mousemoverel then
        local target, dist = nil, _G.Config.Fov
        local mousePos = UIS:GetMouseLocation()
        for _, p in pairs(Players:GetPlayers()) do
            if Utilities.isEnemy(p) and p.Character and p.Character:FindFirstChild("Head") and p.Character.Humanoid.Health > 0 then
                if Utilities.isVisibleForAimbot(p.Character) then
                    local pos, vis = Camera:WorldToViewportPoint(p.Character.Head.Position)
                    if vis then
                        local mag = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                        if mag < dist and math.random(100) <= _G.Config.HitChance then dist, target = mag, p end
                    end
                end
            end
        end
        if target and target.Character:FindFirstChild("Head") then
            local targetPos = Camera:WorldToViewportPoint(target.Character.Head.Position)
            local currentPos = UIS:GetMouseLocation()
            local smooth = math.max(_G.Config.Smoothness / 10, 0.1)
            mousemoverel((targetPos.X - currentPos.X) / smooth, (targetPos.Y - currentPos.Y) / smooth)
        end
    end
end

-- TRIGGERBOT
local TriggerBot = {}

function TriggerBot.update()
    local triggerBotActive = _G.Config.TriggerBot and (_G.Config.TriggerBotKey == nil or state.triggerBotKeyHeld)
    if triggerBotActive then
        local mouse = LP:GetMouse()
        if mouse.Target and mouse.Target.Parent then
            local hum = mouse.Target.Parent:FindFirstChild("Humanoid")
            if hum and Utilities.isEnemy(Players:GetPlayerFromCharacter(hum.Parent)) and mouse1click then mouse1click() end
        end
    end
end

-- ANGRYBOT
local AngryBot = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ws = workspace
local chr = ws:WaitForChild("Characters", 10) or ws:FindFirstChild("Characters")

function AngryBot.getTeam()
    if not chr then return nil end
    for _, v in next, chr:GetChildren() do
        if v:IsA("Folder") and v:FindFirstChild(LP.Name) then return v.Name end
    end
    return nil
end

function AngryBot.getNearestEnemy(mp)
    local mt = AngryBot.getTeam()
    if not mt then return nil end
    local nr, nd = nil, math.huge
    for _, f in next, chr:GetChildren() do
        if f:IsA("Folder") and f.Name ~= mt then
            for _, e in next, f:GetChildren() do
                local eh = e:FindFirstChild("HumanoidRootPart")
                local hm = e:FindFirstChildOfClass("Humanoid")
                local hd = e:FindFirstChild("Head")
                if eh and hm and hm.Health > 0 then
                    local tp = hd and hd.Position or eh.Position
                    local d = (tp - mp).Magnitude
                    if d < nd then nd, nr = d, {p = tp, h = hd or eh, char = e} end
                end
            end
        end
    end
    return nr
end

function AngryBot.isVisible(targetData)
    if not targetData or not targetData.p or not targetData.char then return false end
    local origin = Camera.CFrame.Position
    local dir = (targetData.p - origin).Unit
    local dist = (targetData.p - origin).Magnitude
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {LP.Character, targetData.char}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local result = workspace:Raycast(origin, dir * dist, rayParams)
    return result == nil
end

function AngryBot.updateWeapon()
    if getgc then
        for _, v in next, getgc(true) do
            if type(v) == "table" then
                local ok, r = pcall(rawget, v, "IsEquipped")
                if ok and r and rawget(v, "Identifier") and rawget(v, "Player") == LP then
                    state.angryBotCurrentWeapon = v
                    return
                end
            end
        end
    end
    state.angryBotCurrentWeapon = nil
end

function AngryBot.initRemote()
    if state.angryBotRemote then return end
    if getgc then
        for _, v in next, getgc(true) do
            if type(v) == "table" and rawget(v, "ShootWeapon") then
                state.angryBotRemote = v
                break
            end
        end
    end
end

function AngryBot.createBeam(st, ed)
    local p1 = Instance.new("Part")
    p1.Anchored, p1.CanCollide, p1.Transparency = true, false, 1
    p1.Size, p1.Position, p1.Parent = Vector3.new(0.1, 0.1, 0.1), st, ws

    local p2 = Instance.new("Part")
    p2.Anchored, p2.CanCollide, p2.Transparency = true, false, 1
    p2.Size, p2.Position, p2.Parent = Vector3.new(0.1, 0.1, 0.1), ed, ws

    local at1, at2 = Instance.new("Attachment", p1), Instance.new("Attachment", p2)

    local bm1 = Instance.new("Beam")
    bm1.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(75, 0, 130)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(138, 43, 226)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 112))
    })
    bm1.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 0.3)})
    bm1.Width0, bm1.Width1, bm1.Texture, bm1.TextureSpeed = 0.6, 0.6, "rbxassetid://446111271", 1.5
    bm1.TextureMode, bm1.TextureLength, bm1.Brightness, bm1.LightEmission = Enum.TextureMode.Wrap, 2, 2, 0.4
    bm1.FaceCamera, bm1.Attachment0, bm1.Attachment1, bm1.Parent = true, at1, at2, p1

    local bm2 = Instance.new("Beam")
    bm2.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 130, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 180, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 150, 255))
    })
    bm2.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0.7)})
    bm2.Width0, bm2.Width1, bm2.Texture, bm2.TextureSpeed = 0.25, 0.25, "rbxassetid://446111271", 2.2
    bm2.TextureMode, bm2.TextureLength, bm2.Brightness, bm2.LightEmission = Enum.TextureMode.Wrap, 1.5, 3, 1
    bm2.FaceCamera, bm2.Attachment0, bm2.Attachment1, bm2.Parent = true, at1, at2, p1

    task.delay(math.random(8, 18) / 10, function()
        for i = 0, 1, 0.08 do
            if not p1.Parent then break end
            bm1.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, i * 0.6), NumberSequenceKeypoint.new(0.5, 0.1 + i * 0.5), NumberSequenceKeypoint.new(1, 0.3 + i * 0.7)})
            bm2.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2 + i * 0.6), NumberSequenceKeypoint.new(0.5, 0.4 + i * 0.5), NumberSequenceKeypoint.new(1, 0.7 + i * 0.3)})
            task.wait(0.02)
        end
        p1:Destroy()
        p2:Destroy()
    end)
end

function AngryBot.playSound(tl)
    local s = Instance.new("Sound")
    s.Volume = 1
    s.Parent = Camera
    local sn = tl and tl:FindFirstChild("Hold") and tl.Hold:FindFirstChild("Sounds") and tl.Hold.Sounds:FindFirstChild("Shoot")
    s.SoundId = sn and sn.SoundId or "rbxassetid://88387457337661"
    s:Play()
    Debris:AddItem(s, 3)
end

function AngryBot.update()
    if not _G.Config.AngryBot then return end
    if tick() - state.angryBotLastShot < 0.1 then return end

    local mc = LP.Character
    if not mc or mc:GetAttribute("Dead") then return end
    local hrp = mc:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if not state.angryBotCurrentWeapon or not state.angryBotCurrentWeapon.IsEquipped then
        AngryBot.updateWeapon()
    end
    if not state.angryBotCurrentWeapon or state.angryBotCurrentWeapon.Rounds <= 0 then return end

    AngryBot.initRemote()
    if not state.angryBotRemote or not state.angryBotRemote.ShootWeapon then return end

    local tg = AngryBot.getNearestEnemy(hrp.Position)
    if not tg then return end
    if not AngryBot.isVisible(tg) then return end

    state.angryBotLastShot = tick()
    local og = Camera.CFrame.Position
    local dr = (tg.p - og).Unit

    state.angryBotCurrentWeapon.Rounds = state.angryBotCurrentWeapon.Rounds - 1
    state.angryBotRemote.ShootWeapon.Send({
        IsSniperScoped = false,
        ShootingHand = "Right",
        Identifier = state.angryBotCurrentWeapon.Identifier,
        Capacity = state.angryBotCurrentWeapon.Capacity,
        Rounds = state.angryBotCurrentWeapon.Rounds,
        Bullets = {{
            Direction = dr,
            Origin = og,
            Hits = {{
                Instance = tg.h,
                Position = tg.p,
                Normal = -dr,
                Material = "Plastic",
                Distance = (tg.p - og).Magnitude,
                Exit = false
            }}
        }}
    })

    AngryBot.createBeam(og, tg.p)
    local tool = mc and mc:FindFirstChildOfClass("Tool")
    if tool then AngryBot.playSound(tool) end
end

-- GUI
local GUI = {}

function GUI.init()
    local ScreenGui = Utilities.create("ScreenGui", {Parent = game:GetService("CoreGui"), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    local Main = Utilities.create("Frame", {Parent = ScreenGui, Size = UDim2.new(0, 580, 0, 420), Position = UDim2.new(0.5, -290, 0.5, -210), BackgroundColor3 = Color3.fromRGB(15, 15, 17), BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = Main, CornerRadius = UDim.new(0, 6)})
    Utilities.create("UIStroke", {Parent = Main, Color = Color3.fromRGB(35, 35, 40), Thickness = 1})

    -- Top Bar
    local TopBar = Utilities.create("Frame", {Parent = Main, Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Color3.fromRGB(20, 20, 23), BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = TopBar, CornerRadius = UDim.new(0, 6)})
    local TopBarFill = Utilities.create("Frame", {Parent = TopBar, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), BackgroundColor3 = Color3.fromRGB(20, 20, 23), BorderSizePixel = 0})
    
    -- Title on left with accent
    local AccentBar = Utilities.create("Frame", {Parent = TopBar, Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(88, 101, 242), BorderSizePixel = 0})
    local TitleLabel = Utilities.create("TextLabel", {Parent = TopBar, Size = UDim2.new(0, 200, 1, 0), Position = UDim2.new(0, 15, 0, 0), Text = "Atomic", TextColor3 = Color3.fromRGB(220, 220, 225), TextSize = 16, Font = Enum.Font.GothamBold, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
    
    -- Minimize and Close buttons
    local MinimizeBtn = Utilities.create("TextButton", {Parent = TopBar, Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(1, -76, 0.5, -16), BackgroundColor3 = Color3.fromRGB(25, 25, 28), Text = "_", TextColor3 = Color3.fromRGB(140, 140, 145), TextSize = 16, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = MinimizeBtn, CornerRadius = UDim.new(0, 4)})
    
    local CloseBtn = Utilities.create("TextButton", {Parent = TopBar, Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(1, -38, 0.5, -16), BackgroundColor3 = Color3.fromRGB(25, 25, 28), Text = "X", TextColor3 = Color3.fromRGB(140, 140, 145), TextSize = 16, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = CloseBtn, CornerRadius = UDim.new(0, 4)})
    
    local isMinimized = false
    local originalSize = Main.Size
    local originalPosition = Main.Position
    
    -- Sidebar
    local Sidebar = Utilities.create("Frame", {Parent = Main, Size = UDim2.new(0, 130, 1, -56), Position = UDim2.new(0, 8, 0, 48), BackgroundColor3 = Color3.fromRGB(18, 18, 21), BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = Sidebar, CornerRadius = UDim.new(0, 4)})
    Utilities.create("UIStroke", {Parent = Sidebar, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
    local SidebarLayout = Utilities.create("UIListLayout", {Parent = Sidebar, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    Utilities.create("UIPadding", {Parent = Sidebar, PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)})

    -- Content Area
    local ContentArea = Utilities.create("Frame", {Parent = Main, Size = UDim2.new(1, -150, 1, -56), Position = UDim2.new(0, 142, 0, 48), BackgroundColor3 = Color3.fromRGB(18, 18, 21), BorderSizePixel = 0})
    Utilities.create("UICorner", {Parent = ContentArea, CornerRadius = UDim.new(0, 4)})
    Utilities.create("UIStroke", {Parent = ContentArea, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})

    MinimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            local minimizedSize = UDim2.new(0, 200, 0, 42)
            TweenService:Create(Main, TweenInfo.new(0.2), {Size = minimizedSize}):Play()
            TweenService:Create(MinimizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(88, 101, 242)}):Play()
            wait(0.2)
            Sidebar.Visible = false
            ContentArea.Visible = false
        else
            Sidebar.Visible = true
            ContentArea.Visible = true
            TweenService:Create(Main, TweenInfo.new(0.2), {Size = originalSize}):Play()
            TweenService:Create(MinimizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 28)}):Play()
        end
    end)
    MinimizeBtn.MouseEnter:Connect(function()
        if not isMinimized then
            TweenService:Create(MinimizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(35, 35, 40)}):Play()
        end
    end)
    MinimizeBtn.MouseLeave:Connect(function()
        if not isMinimized then
            TweenService:Create(MinimizeBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 28)}):Play()
        end
    end)
    
    CloseBtn.MouseButton1Click:Connect(function() Main.Visible = false end)
    CloseBtn.MouseEnter:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(220, 50, 50)}):Play() end)
    CloseBtn.MouseLeave:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(25, 25, 28)}):Play() end)

    -- Scrolling content
    local ContentScroll = Utilities.create("ScrollingFrame", {Parent = ContentArea, Size = UDim2.new(1, -16, 1, -16), Position = UDim2.new(0, 8, 0, 8), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Color3.fromRGB(88, 101, 242), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y})
    
    local ContentLayout = Utilities.create("UIListLayout", {Parent = ContentScroll, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Left})

    local Tabs, currentTab = {}, nil

    local function CreateTab(name)
        local btn = Utilities.create("TextButton", {Parent = Sidebar, Size = UDim2.new(1, -16, 0, 34), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0, Text = name, TextColor3 = Color3.fromRGB(130, 130, 135), TextSize = 11, Font = Enum.Font.GothamSemibold, AutoButtonColor = false})
        Utilities.create("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 4)})
        
        local tabContainer = Utilities.create("Frame", {Parent = ContentScroll, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Visible = false})
        local tabLayout = Utilities.create("UIListLayout", {Parent = tabContainer, Padding = UDim.new(0, 8)})
        
        tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() 
            tabContainer.Size = UDim2.new(1, 0, 0, tabLayout.AbsoluteContentSize.Y) 
        end)
        
        Tabs[name] = tabContainer
        
        btn.MouseEnter:Connect(function() 
            if currentTab ~= name then 
                TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(28, 28, 33)}):Play() 
            end 
        end)
        btn.MouseLeave:Connect(function() 
            if currentTab ~= name then 
                TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(22, 22, 26)}):Play() 
            end 
        end)
        btn.MouseButton1Click:Connect(function()
            for _, t in pairs(Sidebar:GetChildren()) do 
                if t:IsA("TextButton") then 
                    TweenService:Create(t, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(22, 22, 26), TextColor3 = Color3.fromRGB(130, 130, 135)}):Play() 
                end 
            end
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(88, 101, 242), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
            for _, container in pairs(Tabs) do container.Visible = false end
            Tabs[name].Visible = true
            currentTab = name
        end)
        
        if not currentTab then
            btn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            Tabs[name].Visible = true
            currentTab = name
        end
    end

    local function CreateSection(tab, title)
        local section = Utilities.create("Frame", {Parent = Tabs[tab], Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1})
        Utilities.create("TextLabel", {Parent = section, Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = title, TextColor3 = Color3.fromRGB(150, 150, 155), TextSize = 11, Font = Enum.Font.GothamBold, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center})
        Utilities.create("Frame", {Parent = section, Size = UDim2.new(1, -12, 0, 1), Position = UDim2.new(0, 6, 1, -1), BackgroundColor3 = Color3.fromRGB(35, 35, 40), BorderSizePixel = 0})
        return Tabs[tab]
    end

    local function CreateToggle(parent, name, key)
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        
        local toggle = Utilities.create("Frame", {Parent = frame, Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(0, 8, 0.5, -9), BackgroundColor3 = _G.Config[key] and Color3.fromRGB(88, 101, 242) or Color3.fromRGB(35, 35, 40), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = toggle, CornerRadius = UDim.new(1, 0)})
        
        local knob = Utilities.create("Frame", {Parent = toggle, Size = UDim2.new(0, 14, 0, 14), Position = _G.Config[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.fromRGB(240, 240, 245), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = knob, CornerRadius = UDim.new(1, 0)})
        
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(1, -56, 1, 0), Position = UDim2.new(0, 50, 0, 0), Text = name, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        
        local btn = Utilities.create("TextButton", {Parent = frame, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = ""})
        btn.MouseButton1Click:Connect(function()
            _G.Config[key] = not _G.Config[key]
            TweenService:Create(toggle, TweenInfo.new(0.2), {BackgroundColor3 = _G.Config[key] and Color3.fromRGB(88, 101, 242) or Color3.fromRGB(35, 35, 40)}):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), {Position = _G.Config[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}):Play()
            if key == "MiscNoclip" then Movement.setupNoclip() end
            if key == "NoFog" then Visuals.updateNoFog() end
            if key == "FullBright" then Visuals.updateFullBright() end
            if key == "AntiLag" then Visuals.updateAntiLag() end
            if key == "CustomKnifeEnabled" and not _G.Config[key] then removeKnifeViewmodel() end
            if key == "SkinChangerEnabled" and not _G.Config[key] then
                for _, obj in Camera:GetChildren() do obj:SetAttribute("SkinApplied", nil) end
            end
        end)
    end

    local function CreateSlider(parent, name, min, max, key)
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(1, -60, 0, 18), Position = UDim2.new(0, 10, 0, 6), Text = name, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        
        local value = Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(0, 50, 0, 18), Position = UDim2.new(1, -58, 0, 6), Text = tostring(_G.Config[key]), TextColor3 = Color3.fromRGB(88, 101, 242), TextSize = 10, Font = Enum.Font.GothamBold, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right})
        
        local bar = Utilities.create("TextButton", {Parent = frame, Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -14), BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0, Text = "", AutoButtonColor = false})
        Utilities.create("UICorner", {Parent = bar, CornerRadius = UDim.new(1, 0)})
        
        local fill = Utilities.create("Frame", {Parent = bar, Size = UDim2.new((_G.Config[key] - min) / (max - min), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(88, 101, 242), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = fill, CornerRadius = UDim.new(1, 0)})
        
        local function update(x)
            local pos = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * pos)
            _G.Config[key] = val
            value.Text = tostring(val)
            fill.Size = UDim2.new(pos, 0, 1, 0)
        end
        local dragging = false
        bar.MouseButton1Down:Connect(function(x) dragging = true update(x) end)
        bar.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
        bar.MouseMoved:Connect(function(x) if dragging then update(x) end end)
    end

    local function CreateDropdown(parent, name, key)
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = name, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        
        local modes = {"敌人", "队友", "全部"}
        local modeKeys = {"Enemies", "Teammates", "All"}
        local function getModeText(keyValue)
            local idx = table.find(modeKeys, keyValue)
            return idx and modes[idx] or keyValue
        end
        
        local btn = Utilities.create("TextButton", {Parent = frame, Size = UDim2.new(0, 88, 0, 22), Position = UDim2.new(1, -96, 0.5, -11), BackgroundColor3 = Color3.fromRGB(30, 30, 35), Text = getModeText(_G.Config[key]), TextColor3 = Color3.fromRGB(88, 101, 242), TextSize = 9, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 4)})
        
        btn.MouseButton1Click:Connect(function()
            local currentKey = _G.Config[key]
            local idx = table.find(modeKeys, currentKey)
            idx = (idx % #modeKeys) + 1
            _G.Config[key] = modeKeys[idx]
            btn.Text = modes[idx]
        end)
    end

    local function CreateKeybind(parent, name, keyConfigKey)
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = name, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        
        local keyDisplay = Utilities.create("Frame", {Parent = frame, Size = UDim2.new(0, 88, 0, 22), Position = UDim2.new(1, -96, 0.5, -11), BackgroundColor3 = Color3.fromRGB(28, 28, 33), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = keyDisplay, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = keyDisplay, Color = Color3.fromRGB(45, 45, 52), Thickness = 1})
        
        local btn = Utilities.create("TextButton", {Parent = keyDisplay, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Text = _G.Config[keyConfigKey] and _G.Config[keyConfigKey].Name or "无", TextColor3 = Color3.fromRGB(200, 200, 205), TextSize = 9, Font = Enum.Font.GothamMedium, BorderSizePixel = 0})
        
        btn.MouseButton1Click:Connect(function()
            btn.Text = "..."
            btn.TextColor3 = Color3.fromRGB(255, 180, 80)
            state.bindingKey = {keyConfigKey = keyConfigKey, btn = btn}
        end)
        
        local clearBtn = Utilities.create("TextButton", {Parent = keyDisplay, Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(1, -18, 0, 0), BackgroundColor3 = Color3.fromRGB(35, 35, 40), Text = "×", TextColor3 = Color3.fromRGB(160, 160, 165), TextSize = 14, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = clearBtn, CornerRadius = UDim.new(0, 4)})
        clearBtn.MouseEnter:Connect(function() TweenService:Create(clearBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(220, 50, 50), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play() end)
        clearBtn.MouseLeave:Connect(function() TweenService:Create(clearBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(35, 35, 40), TextColor3 = Color3.fromRGB(160, 160, 165)}):Play() end)
        clearBtn.MouseButton1Click:Connect(function()
            _G.Config[keyConfigKey] = nil
            btn.Text = "无"
            btn.TextColor3 = Color3.fromRGB(200, 200, 205)
        end)
    end

    local function CreateOptionDropdown(parent, name, key, optionsList, onChangeCallback)
        if #optionsList == 0 then return end
        if not _G.Config[key] or not table.find(optionsList, _G.Config[key]) then
            _G.Config[key] = optionsList[1]
        end
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = name, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        local btn = Utilities.create("TextButton", {Parent = frame, Size = UDim2.new(0, 88, 0, 22), Position = UDim2.new(1, -96, 0.5, -11), BackgroundColor3 = Color3.fromRGB(30, 30, 35), Text = tostring(_G.Config[key]), TextColor3 = Color3.fromRGB(88, 101, 242), TextSize = 9, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 4)})
        local function refresh() btn.Text = tostring(_G.Config[key]) end
        btn.MouseButton1Click:Connect(function()
            local idx = table.find(optionsList, _G.Config[key])
            idx = (idx or 0) % #optionsList + 1
            _G.Config[key] = optionsList[idx]
            refresh()
            if type(onChangeCallback) == "function" then onChangeCallback() end
        end)
    end

    local function CreateSkinDropdown(parent, weaponName, optionsList)
        if #optionsList == 0 then return end
        if not _G.Config.SelectedSkins[weaponName] or not table.find(optionsList, _G.Config.SelectedSkins[weaponName]) then
            _G.Config.SelectedSkins[weaponName] = optionsList[1]
        end
        local frame = Utilities.create("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 4)})
        Utilities.create("UIStroke", {Parent = frame, Color = Color3.fromRGB(30, 30, 35), Thickness = 1})
        Utilities.create("TextLabel", {Parent = frame, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = weaponName, TextColor3 = Color3.fromRGB(180, 180, 185), TextSize = 10, Font = Enum.Font.Gotham, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left})
        local btn = Utilities.create("TextButton", {Parent = frame, Size = UDim2.new(0, 88, 0, 22), Position = UDim2.new(1, -96, 0.5, -11), BackgroundColor3 = Color3.fromRGB(30, 30, 35), Text = tostring(_G.Config.SelectedSkins[weaponName]), TextColor3 = Color3.fromRGB(88, 101, 242), TextSize = 9, Font = Enum.Font.GothamBold, BorderSizePixel = 0})
        Utilities.create("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 4)})
        local function refresh() btn.Text = tostring(_G.Config.SelectedSkins[weaponName]) end
        btn.MouseButton1Click:Connect(function()
            local idx = table.find(optionsList, _G.Config.SelectedSkins[weaponName])
            idx = (idx or 0) % #optionsList + 1
            _G.Config.SelectedSkins[weaponName] = optionsList[idx]
            refresh()
            for _, obj in Camera:GetChildren() do
                obj:SetAttribute("SkinApplied", nil)
                SkinChanger.applyWeaponSkin(obj)
            end
        end)
    end

    -- Create Tabs
    CreateTab("自瞄")
    CreateTab("视觉")
    CreateTab("战斗")
    CreateTab("移动")
    CreateTab("杂项")
    CreateTab("皮肤")

    -- Aimbot Tab
    CreateSection("自瞄", "设置")
    CreateToggle(Tabs["自瞄"], "启用自瞄", "Aimbot")
    CreateToggle(Tabs["自瞄"], "可见性检查", "AimbotUseVisibleCheck")
    CreateToggle(Tabs["自瞄"], "显示FOV圆圈", "ShowFov")
    CreateKeybind(Tabs["自瞄"], "自瞄按键", "AimbotKey")
    CreateSlider(Tabs["自瞄"], "FOV范围", 10, 400, "Fov")
    CreateSlider(Tabs["自瞄"], "平滑度", 1, 50, "Smoothness")
    CreateSlider(Tabs["自瞄"], "命中率", 0, 100, "HitChance")

    -- Visuals Tab
    CreateSection("视觉", "ESP设置")
    CreateToggle(Tabs["视觉"], "启用ESP", "Esp")
    CreateDropdown(Tabs["视觉"], "ESP模式", "EspTeamMode")
    CreateToggle(Tabs["视觉"], "团队检查", "UseTeamCheck")
    CreateToggle(Tabs["视觉"], "方框", "EspBoxes")
    CreateToggle(Tabs["视觉"], "名称", "EspNames")
    CreateToggle(Tabs["视觉"], "生命值条", "EspHealthBar")
    CreateToggle(Tabs["视觉"], "距离", "EspDistance")
    CreateToggle(Tabs["视觉"], "准星线", "EspTracers")
    CreateToggle(Tabs["视觉"], "头部标记", "EspHeadDot")
    CreateToggle(Tabs["视觉"], "武器", "EspWeapon")
    
    CreateSection("视觉", "世界")
    CreateToggle(Tabs["视觉"], "无雾", "NoFog")
    CreateToggle(Tabs["视觉"], "全亮", "FullBright")
    CreateToggle(Tabs["视觉"], "抗延迟", "AntiLag")

    -- Combat Tab
    CreateSection("战斗", "扳机机器人")
    CreateToggle(Tabs["战斗"], "启用扳机机器人", "TriggerBot")
    CreateKeybind(Tabs["战斗"], "扳机机器人按键", "TriggerBotKey")
    CreateSlider(Tabs["战斗"], "扳机延迟", 1, 100, "TriggerBotDelay")
    
    CreateSection("战斗", "愤怒机器人")
    CreateToggle(Tabs["战斗"], "愤怒机器人", "AngryBot")

    -- Movement Tab
    CreateSection("移动", "移动")
    CreateToggle(Tabs["移动"], "连跳 (按住空格)", "MiscBhop")
    CreateToggle(Tabs["移动"], "加速", "MiscSpeed")
    CreateKeybind(Tabs["移动"], "加速按键", "SpeedKey")
    CreateSlider(Tabs["移动"], "速度值", 16, 150, "SpeedAmount")
    CreateToggle(Tabs["移动"], "穿墙", "MiscNoclip")
    CreateKeybind(Tabs["移动"], "穿墙按键", "NoclipKey")
    CreateToggle(Tabs["移动"], "无限跳跃", "InfiniteJump")
    CreateToggle(Tabs["移动"], "飞行", "FlyHack")
    CreateKeybind(Tabs["移动"], "飞行按键", "FlyKey")
    CreateSlider(Tabs["移动"], "飞行速度", 10, 150, "FlySpeed")

    -- Misc Tab
    CreateSection("杂项", "相机")
    CreateToggle(Tabs["杂项"], "第三人称", "MiscThirdPerson")
    CreateSlider(Tabs["杂项"], "第三人称距离", 5, 30, "ThirdPersonDistance")
    CreateSlider(Tabs["杂项"], "相机视野", 70, 120, "CameraFOV")

    -- 皮肤 Tab
    CreateSection("皮肤", "自定义刀")
    CreateToggle(Tabs["皮肤"], "启用自定义刀", "CustomKnifeEnabled")
    CreateOptionDropdown(Tabs["皮肤"], "选择刀", "SelectedKnife", {"Butterfly Knife", "Karambit", "M9 Bayonet", "Flip Knife", "Gut Knife"}, function() removeKnifeViewmodel() end)
    CreateSection("皮肤", "皮肤更换")
    CreateToggle(Tabs["皮肤"], "启用皮肤更换", "SkinChangerEnabled")
    task.spawn(function()
        for _ = 1, 30 do
            local SkinsFolder = getSkinsFolder()
            if SkinsFolder then
                CreateSection("皮肤", "刀 / 手套 / 武器皮肤")
                local KNIVES = {"Karambit", "Butterfly Knife", "M9 Bayonet", "Flip Knife", "Gut Knife", "T Knife", "CT Knife"}
                local GLOVES = {"Sports Gloves"}
                local CT_ONLY = {"USP-S", "Five-SeveN", "MP9", "FAMAS", "M4A1-S", "M4A4", "AUG"}
                local SHARED = {"P250", "Desert Eagle", "Dual Berettas", "Negev", "P90", "Nova", "XM1014", "AWP", "SSG 08"}
                for _, name in ipairs(KNIVES) do
                    local folder = SkinsFolder:FindFirstChild(name)
                    if folder then
                        local opts = {}
                        for _, skin in folder:GetChildren() do table.insert(opts, skin.Name) end
                        if #opts > 0 then CreateSkinDropdown(Tabs["皮肤"], name, opts) end
                    end
                end
                for _, name in ipairs(GLOVES) do
                    local folder = SkinsFolder:FindFirstChild(name)
                    if folder then
                        local opts = {}
                        for _, skin in folder:GetChildren() do table.insert(opts, skin.Name) end
                        if #opts > 0 then CreateSkinDropdown(Tabs["皮肤"], name, opts) end
                    end
                end
                for _, name in ipairs(CT_ONLY) do
                    local folder = SkinsFolder:FindFirstChild(name)
                    if folder then
                        local opts = {}
                        for _, skin in folder:GetChildren() do table.insert(opts, skin.Name) end
                        if #opts > 0 then CreateSkinDropdown(Tabs["皮肤"], name, opts) end
                    end
                end
                for _, name in ipairs(SHARED) do
                    local folder = SkinsFolder:FindFirstChild(name)
                    if folder then
                        local opts = {}
                        for _, skin in folder:GetChildren() do table.insert(opts, skin.Name) end
                        if #opts > 0 then CreateSkinDropdown(Tabs["皮肤"], name, opts) end
                    end
                end
                for _, folder in SkinsFolder:GetChildren() do
                    local n = folder.Name
                    if not IgnoreFolders[n] and not table.find(KNIVES, n) and not table.find(GLOVES, n) and not table.find(CT_ONLY, n) and not table.find(SHARED, n) then
                        local opts = {}
                        for _, skin in folder:GetChildren() do table.insert(opts, skin.Name) end
                        if #opts > 0 then CreateSkinDropdown(Tabs["皮肤"], n, opts) end
                    end
                end
                break
            end
            task.wait(0.5)
        end
    end)

    -- Dragging functionality
    local dragging, dragStart, startPos
    TopBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = i.Position
            startPos = Main.Position
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = i.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Key bindings
    UIS.InputBegan:Connect(function(i)
        if i.KeyCode == _G.Config.MenuKey then Main.Visible = not Main.Visible end
        if state.bindingKey and i.KeyCode ~= Enum.KeyCode.Unknown then
            _G.Config[state.bindingKey.keyConfigKey] = i.KeyCode
            state.bindingKey.btn.Text = i.KeyCode.Name
            state.bindingKey.btn.TextColor3 = Color3.fromRGB(200, 200, 205)
            state.bindingKey = nil
        end
        if _G.Config.AimbotKey and i.KeyCode == _G.Config.AimbotKey then state.aimbotKeyHeld = true end
        if _G.Config.TriggerBotKey and i.KeyCode == _G.Config.TriggerBotKey then state.triggerBotKeyHeld = true end
        if _G.Config.FlyKey and i.KeyCode == _G.Config.FlyKey then _G.Config.FlyHack = not _G.Config.FlyHack end
    end)

    UIS.InputEnded:Connect(function(i)
        if _G.Config.AimbotKey and i.KeyCode == _G.Config.AimbotKey then state.aimbotKeyHeld = false end
        if _G.Config.TriggerBotKey and i.KeyCode == _G.Config.TriggerBotKey then state.triggerBotKeyHeld = false end
    end)
end

-- INIT
Movement.setupNoclip()
GUI.init()
RunService.RenderStepped:Connect(function()
    Aimbot.updateFOV()
    Movement.updateFly()
    Movement.updateSpeed()
    Visuals.updateCameraFOV()
    Visuals.updateThirdPerson()
    Movement.updateInfiniteJump()
    Aimbot.update()
    ESP.update()
end)
RunService.Heartbeat:Connect(function()
    Movement.updateNoclip()
    Movement.updateBhop()
    TriggerBot.update()
    AngryBot.update()
end)

-- 自定义刀 viewmodel 位置更新
RunService.RenderStepped:Connect(function()
    if not _G.Config.CustomKnifeEnabled or not state.knifeVm or not state.knifeVm.PrimaryPart then return end
    local off = knives[_G.Config.SelectedKnife]
    if off then
        state.knifeVm.PrimaryPart.CFrame = Camera.CFrame * off.Offset
    end
    if not (state.knifeEquipAnim and state.knifeEquipAnim.IsPlaying) and not state.knifeInspecting and not state.knifeSwinging then
        if state.knifeIdleAnim and not state.knifeIdleAnim.IsPlaying then
            state.knifeIdleAnim:Play()
        end
    end
end)

-- 自定义刀 生成/销毁 检测
task.spawn(function()
    while true do
        local living = isAliveKnife()
        local currentKnife = getKnifeInCamera()
        if _G.Config.CustomKnifeEnabled and living and currentKnife and not state.knifeSpawned then
            spawnKnifeViewmodel(currentKnife)
        elseif (not _G.Config.CustomKnifeEnabled or not currentKnife or not living) and state.knifeSpawned then
            removeKnifeViewmodel()
        end
        task.wait(0.1)
    end
end)

-- 皮肤：新武器加入相机时应用
Camera.ChildAdded:Connect(function(obj)
    if not _G.Config.SkinChangerEnabled or not SkinChanger.isAliveSkin() then return end
    task.wait(0.1)
    SkinChanger.applyWeaponSkin(obj)
end)

-- 皮肤：定期检查并重新应用
task.spawn(function()
    while true do
        task.wait(0.5)
        if _G.Config.SkinChangerEnabled and SkinChanger.isAliveSkin() then
            for _, obj in Camera:GetChildren() do
                if _G.Config.SelectedSkins[obj.Name] and obj:GetAttribute("SkinApplied") ~= _G.Config.SelectedSkins[obj.Name] then
                    SkinChanger.applyWeaponSkin(obj)
                end
            end
        end
    end
end)

LP.CharacterAdded:Connect(function()
    task.wait(0.2)
    Movement.setupNoclip()
    state.noclipParts = {}
end)