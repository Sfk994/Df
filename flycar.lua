-- ==========================================
-- Havvk科技 | 极简飞车模式 (UI方向键版)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_CarMode") then
    PlayerGui.Havvk_CarMode:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_CarMode"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- 主界面
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 260, 0, 360)
main.Position = UDim2.new(0.5, -130, 0.5, -180)
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
title.Text = " 飞车模式 (方向键驾驶)"
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
local isDriving = false
local carSpeed = 50
local bv, bg
local driveConn

-- 方向键状态 (支持键盘和屏幕按键同时触发)
local keys = { W = false, A = false, S = false, D = false }

-- ==========================================
-- 核心物理逻辑
-- ==========================================
local function startDrive()
    isDriving = true
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local hrp = char.HumanoidRootPart
    
    -- 使用经典物理引擎，稳定不卡
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = hrp
    
    bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 5000
    bg.Parent = hrp
    
    -- 开启防摔死状态（部分游戏需要，如果这游戏不需要可以删掉这行）
    local humanoid = char:FindFirstChild("Humanoid")
    if humanoid then humanoid.PlatformStand = true end

    driveConn = RunService.Heartbeat:Connect(function()
        if not isDriving or not bv or not bg then return end
        local c = LocalPlayer.Character
        local cam = workspace.CurrentCamera
        if not c or not c:FindFirstChild("HumanoidRootPart") or not cam then return end

        -- 根据相机视野计算移动方向 (剔除Y轴，纯平面飞车)
        local moveDir = Vector3.new(0, 0, 0)
        
        if keys.W then moveDir = moveDir + cam.CFrame.LookVector end
        if keys.S then moveDir = moveDir - cam.CFrame.LookVector end
        if keys.D then moveDir = moveDir + cam.CFrame.RightVector end
        if keys.A then moveDir = moveDir - cam.CFrame.RightVector end

        -- 剔除爬坡时的上下方向分量，保持纯水平飞车
        moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)

        if moveDir.Magnitude > 0 then
            -- 归一化并乘以速度
            bv.Velocity = moveDir.Unit * carSpeed
        else
            -- 没按方向键时悬停
            bv.Velocity = Vector3.new(0, 0, 0)
        end
        
        -- 强制视角水平，防止车翻
        bg.CFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + cam.CFrame.LookVector)
    end)
end

local function stopDrive()
    isDriving = false
    keys.W, keys.A, keys.S, keys.D = false, false, false, false
    if bv then bv:Destroy() bv = nil end
    if bg then bg:Destroy() bg = nil end
    if driveConn then driveConn:Disconnect() driveConn = nil end
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.PlatformStand = false
    end
end

-- ==========================================
-- UI 按钮生成
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

-- 开关和速度控制
local driveBtn = createUIButton("开启飞车 [关]", UDim2.new(0, 10, 0, 45), UDim2.new(1, -20, 0, 40))
local spdLabel = createUIButton("当前速度: " .. carSpeed, UDim2.new(0, 10, 0, 95), UDim2.new(1, -20, 0, 30), Color3.fromRGB(40, 40, 40))
local minusBtn = createUIButton("-", UDim2.new(0, 10, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))
local plusBtn = createUIButton("+", UDim2.new(1, -60, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))

-- 方向键按钮 (十字布局)
local wBtn = createUIButton("W (前)", UDim2.new(0.5, -40, 0, 190), UDim2.new(0, 80, 0, 40), Color3.fromRGB(80, 80, 80))
local aBtn = createUIButton("A (左)", UDim2.new(0, 25, 0, 240), UDim2.new(0, 60, 0, 40), Color3.fromRGB(80, 80, 80))
local sBtn = createUIButton("S (后)", UDim2.new(0.5, -40, 0, 240), UDim2.new(0, 80, 0, 40), Color3.fromRGB(80, 80, 80))
local dBtn = createUIButton("D (右)", UDim2.new(1, -85, 0, 240), UDim2.new(0, 60, 0, 40), Color3.fromRGB(80, 80, 80))

-- ==========================================
-- 交互逻辑
-- ==========================================

-- 绑定屏幕按键 (支持触摸和鼠标按住)
local function bindDriveBtn(btn, key)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            keys[key] = true
            btn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            keys[key] = false
            btn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        end
    end)
end

bindDriveBtn(wBtn, "W")
bindDriveBtn(aBtn, "A")
bindDriveBtn(sBtn, "S")
bindDriveBtn(dBtn, "D")

-- 绑定键盘按键
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not isDriving then return end
    if input.KeyCode == Enum.KeyCode.W then keys.W = true end
    if input.KeyCode == Enum.KeyCode.A then keys.A = true end
    if input.KeyCode == Enum.KeyCode.S then keys.S = true end
    if input.KeyCode == Enum.KeyCode.D then keys.D = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then keys.W = false end
    if input.KeyCode == Enum.KeyCode.A then keys.A = false end
    if input.KeyCode == Enum.KeyCode.S then keys.S = false end
    if input.KeyCode == Enum.KeyCode.D then keys.D = false end
end)

-- 主开关
driveBtn.MouseButton1Click:Connect(function()
    isDriving = not isDriving
    driveBtn.BackgroundColor3 = isDriving and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    driveBtn.Text = isDriving and "开启飞车 [开]" or "开启飞车 [关]"
    
    if isDriving then
        startDrive()
    else
        stopDrive()
    end
end)

-- 速度加减
minusBtn.MouseButton1Click:Connect(function()
    if carSpeed > 10 then carSpeed = carSpeed - 10; spdLabel.Text = "当前速度: " .. carSpeed end
end)
plusBtn.MouseButton1Click:Connect(function()
    if carSpeed < 300 then carSpeed = carSpeed + 10; spdLabel.Text = "当前速度: " .. carSpeed end
end)
-- ==========================================
-- 清理与拖拽
-- ==========================================
local function cleanup()
    stopDrive()
    gui:Destroy()
end

closeBtn.MouseButton1Click:Connect(cleanup)
LocalPlayer.CharacterAdded:Connect(function()
    if isDriving then
        stopDrive()
        driveBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        driveBtn.Text = "开启飞车 [关]"
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