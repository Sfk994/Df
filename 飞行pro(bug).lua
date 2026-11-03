-- ==========================================
-- Havvk科技 | 飞行 2.0 (防回拉/防撞墙版)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_Fly2") then
    PlayerGui.Havvk_Fly2:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_Fly2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- 主界面 UI
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 270)
main.Position = UDim2.new(0.5, -120, 0.5, -135)
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
title.Text = " 飞行 2.0 (防回拉)"
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

-- ==========================================
-- 状态变量
-- ==========================================
local flying = false
local flySpeed = 100
local velocity, align, attachment
local renderConn

-- 关闭飞行并恢复状态
local function stopFly()
    flying = false
    if velocity then velocity:Destroy() velocity = nil end
    if align then align:Destroy() align = nil end
    if attachment then attachment:Destroy() attachment = nil end
    if renderConn then renderConn:Disconnect() renderConn = nil end
    
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then humanoid.PlatformStand = false end
        -- 恢复碰撞
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then v.CanCollide = true end
        end
    end
end

local function startFly()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Humanoid") then return end
    
    local hrp = char.HumanoidRootPart
    local humanoid = char.Humanoid
    
    flying = true
    humanoid.PlatformStand = true
    
    -- 防回拉核心：强制关掉碰撞，撞墙也不会被拉回
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then v.CanCollide = false end
    end
    
    -- 使用新版 LinearVelocity
    attachment = Instance.new("Attachment")
    attachment.Parent = hrp
    
    velocity = Instance.new("LinearVelocity")
    velocity.Attachment0 = attachment
    velocity.MaxForce = math.huge
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.Parent = hrp
    
    align = Instance.new("AlignOrientation")
    align.MaxTorque = math.huge
    align.PrimaryAxisOnly = false
    align.Parent = hrp

    renderConn = RunService.RenderStepped:Connect(function()
        if not flying or not velocity or not align then return end
        local c = LocalPlayer.Character
        local cam = workspace.CurrentCamera
        if c and c:FindFirstChild("Humanoid") and cam then
            local moveDir = c.Humanoid.MoveDirection
            -- 剔除垂直方向的干扰，只做水平移动
            local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
            
            local finalVelocity = Vector3.new(0,0,0)
            if flatDir.Magnitude > 0.05 then
                finalVelocity = flatDir.Unit * flySpeed
            end
            
            velocity.VectorVelocity = finalVelocity
            align.CFrame = cam.CFrame
        end
    end)
end

-- ==========================================
-- UI 按钮
-- ==========================================
local function createUIButton(text, pos, size, color)
    local btn = Instance.new("TextButton", main)
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color or Color3.fromRGB(50, 50, 50)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    return btn
end

local flyBtn = createUIButton("开启飞行 [关]", UDim2.new(0, 10, 0, 45), UDim2.new(1, -20, 0, 40))
local spdLabel = createUIButton("当前速度: " .. flySpeed, UDim2.new(0, 10, 0, 95), UDim2.new(1, -20, 0, 30), Color3.fromRGB(40, 40, 40))
local minusBtn = createUIButton("-", UDim2.new(0, 10, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))
local plusBtn = createUIButton("+", UDim2.new(1, -60, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))

-- 垂直升降键
local upBtn = createUIButton("↑ 上升 (防回拉)", UDim2.new(0, 10, 0, 180), UDim2.new(1, -20, 0, 35), Color3.fromRGB(0, 120, 200))
local downBtn = createUIButton("↓ 下降 (防回拉)", UDim2.new(0, 10, 0, 225), UDim2.new(1, -20, 0, 35), Color3.fromRGB(200, 80, 80))

-- 升降状态
local keys = { Up = false, Down = false }

upBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        keys.Up = true
    end
end)
upBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        keys.Up = false
    end
end)

downBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        keys.Down = true
    end
end)
downBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        keys.Down = false
    end
end)

-- 主开关
flyBtn.MouseButton1Click:Connect(function()
    flying = not flying
    flyBtn.BackgroundColor3 = flying and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    flyBtn.Text = flying and "飞行中 [开]" or "开启飞行 [关]"
    
    if flying then
        startFly()
    else
        stopFly()
    end
end)

-- 速度加减
minusBtn.MouseButton1Click:Connect(function()
    if flySpeed > 10 then flySpeed = flySpeed - 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)
plusBtn.MouseButton1Click:Connect(function()
    if flySpeed < 300 then flySpeed = flySpeed + 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)

-- 结合升降的循环
RunService.Heartbeat:Connect(function()
    if flying and velocity then
        local c = LocalPlayer.Character
        if c and c:FindFirstChild("Humanoid") then
            local moveDir = c.Humanoid.MoveDirection
            local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
            
            local finalVel = Vector3.new(0, 0, 0)
            if flatDir.Magnitude > 0.05 then
                finalVel = flatDir.Unit * flySpeed
            end
            
            -- 垂直升降
            if keys.Up then finalVel = finalVel + Vector3.new(0, flySpeed, 0) end
            if keys.Down then finalVel = finalVel - Vector3.new(0, flySpeed, 0) end
            
            velocity.VectorVelocity = finalVel
        end
    end
end)

-- 清理与拖拽
local function cleanup()
    stopFly()
    gui:Destroy()
end
closeBtn.MouseButton1Click:Connect(cleanup)
LocalPlayer.CharacterAdded:Connect(function()
    if flying then
        stopFly()
        flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        flyBtn.Text = "开启飞行 [关]"
    end
end)

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
