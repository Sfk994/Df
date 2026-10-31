local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_FlyModule") then
    PlayerGui.Havvk_FlyModule:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_FlyModule"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

-- 主界面
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 290)
main.Position = UDim2.new(0.5, -120, 0.5, -145)
main.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Active = true
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

local top = Instance.new("Frame", main)
top.Size = UDim2.new(1, 0, 0, 35)
top.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
top.BorderSizePixel = 0

local title = Instance.new("TextLabel", top)
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = " 飞行模块 (瞬移版)"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 14

local closeBtn = Instance.new("TextButton", top)
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -35, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14

local flying, isNoclip = false, false
local flySpeed = 50
local bv, renderConn

-- 关闭碰撞并设置悬浮状态
local function setNoclipState(state)
    if LocalPlayer.Character then
        for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = not state
            end
        end
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            -- 开启飞行时强制悬浮，防止物理引擎卡住角色
            humanoid.PlatformStand = state
        end
    end
end

local function stopFly()
    flying = false
    if bv then bv:Destroy() bv = nil end
    if renderConn then renderConn:Disconnect() renderConn = nil end
    setNoclipState(false)
end

closeBtn.MouseButton1Click:Connect(function()
    stopFly()
    gui:Destroy()
end)

-- 飞行开关
local flyBtn = Instance.new("TextButton", main)
flyBtn.Size = UDim2.new(1, -20, 0, 40)
flyBtn.Position = UDim2.new(0, 10, 0, 45)
flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
flyBtn.Text = "开启飞行 [关]"
flyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
flyBtn.Font = Enum.Font.Gotham
flyBtn.TextSize = 14
Instance.new("UICorner", flyBtn).CornerRadius = UDim.new(0, 4)

-- 穿墙开关
local noclipBtn = Instance.new("TextButton", main)
noclipBtn.Size = UDim2.new(1, -20, 0, 40)
noclipBtn.Position = UDim2.new(0, 10, 0, 90)
noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
noclipBtn.Text = "穿墙模式 [关]"
noclipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
noclipBtn.Font = Enum.Font.Gotham
noclipBtn.TextSize = 14
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 4)

-- 上下瞬移按钮
local upBtn = Instance.new("TextButton", main)
upBtn.Size = UDim2.new(0.5, -15, 0, 40)
upBtn.Position = UDim2.new(0, 10, 0, 140)
upBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
upBtn.Text = "↑ 向上瞬移"
upBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
upBtn.Font = Enum.Font.GothamBold
upBtn.TextSize = 14
Instance.new("UICorner", upBtn).CornerRadius = UDim.new(0, 4)

local downBtn = Instance.new("TextButton", main)
downBtn.Size = UDim2.new(0.5, -15, 0, 40)
downBtn.Position = UDim2.new(0.5, 5, 0, 140)
downBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
downBtn.Text = "↓ 向下瞬移"
downBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
downBtn.Font = Enum.Font.GothamBold
downBtn.TextSize = 14
Instance.new("UICorner", downBtn).CornerRadius = UDim.new(0, 4)

-- 速度显示与加减
local spdLabel = Instance.new("TextLabel", main)
spdLabel.Size = UDim2.new(1, -20, 0, 30)
spdLabel.Position = UDim2.new(0, 10, 0, 190)
spdLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
spdLabel.Text = "当前速度: " .. flySpeed
spdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
spdLabel.Font = Enum.Font.Gotham
spdLabel.TextSize = 13
Instance.new("UICorner", spdLabel).CornerRadius = UDim.new(0, 4)

local minusBtn = Instance.new("TextButton", main)
minusBtn.Size = UDim2.new(0, 40, 0, 30)
minusBtn.Position = UDim2.new(0, 10, 0, 240)
minusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
minusBtn.Text = "-"
minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 20
Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 4)

local plusBtn = Instance.new("TextButton", main)
plusBtn.Size = UDim2.new(0, 40, 0, 30)
plusBtn.Position = UDim2.new(1, -50, 0, 240)
plusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
plusBtn.Text = "+"
plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 18
Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 4)

minusBtn.MouseButton1Click:Connect(function()
    if flySpeed > 10 then flySpeed = flySpeed - 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)

plusBtn.MouseButton1Click:Connect(function()
    if flySpeed < 200 then flySpeed = flySpeed + 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)

-- =======================
-- 瞬移逻辑
-- =======================
local teleportDistance = 25

upBtn.MouseButton1Click:Connect(function()
    local c = LocalPlayer.Character
    if c and c:FindFirstChild("HumanoidRootPart") then
        c.HumanoidRootPart.CFrame = c.HumanoidRootPart.CFrame + Vector3.new(0, teleportDistance, 0)
    end
end)

downBtn.MouseButton1Click:Connect(function()
    local c = LocalPlayer.Character
    if c and c:FindFirstChild("HumanoidRootPart") then
        c.HumanoidRootPart.CFrame = c.HumanoidRootPart.CFrame - Vector3.new(0, teleportDistance, 0)
    end
end)

-- 穿墙开关逻辑
noclipBtn.MouseButton1Click:Connect(function()
    isNoclip = not isNoclip
    noclipBtn.BackgroundColor3 = isNoclip and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    noclipBtn.Text = isNoclip and "穿墙模式 [开]" or "穿墙模式 [关]"
    
    -- 如果在飞行中，更新物理状态；如果没飞，确保恢复
    if flying then
        setNoclipState(isNoclip)
    else
        if not isNoclip then setNoclipState(false) end
    end
end)

-- 飞行开关逻辑
flyBtn.MouseButton1Click:Connect(function()
    flying = not flying
    if flying then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then flying = false; return end
        
        flyBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        flyBtn.Text = "开启飞行 [开]"
        local hrp = char.HumanoidRootPart
        
        -- 开启穿墙和悬浮
        setNoclipState(isNoclip)
        
        bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Parent = hrp
        
        -- 使用 Heartbeat 处理稳定移动
        renderConn = RunService.Heartbeat:Connect(function()
            if not flying or not bv then return end
            local c = LocalPlayer.Character
            if not c or not c:FindFirstChild("Humanoid") then return end
            
            -- 如果在飞行中开启了穿墙，实时循环确认碰撞已关闭
            if isNoclip then
                for _, v in pairs(c:GetDescendants()) do
                    if v:IsA("BasePart") and v.CanCollide then
                        v.CanCollide = false
                    end
                end
            end

            local dir = c.Humanoid.MoveDirection
            local flatDir = Vector3.new(dir.X, 0, dir.Z)
            local horizontalVel = Vector3.new(0, 0, 0)
            
            if flatDir.Magnitude > 0.05 then
                horizontalVel = flatDir.Unit * flySpeed
            end
            
            bv.Velocity = horizontalVel
        end)
        
    else
        flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        flyBtn.Text = "开启飞行 [关]"
        stopFly()
    end
end)

-- 死亡自动清理
LocalPlayer.CharacterAdded:Connect(function()
    if flying then
        stopFly()
        flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        flyBtn.Text = "开启飞行 [关]"
        noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        noclipBtn.Text = "穿墙模式 [关]"
        isNoclip = false
    end
end)

-- 拖拽逻辑
local drag, dragStart, startPos
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        drag = true; dragStart = input.Position; startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then drag = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
