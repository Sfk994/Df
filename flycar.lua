-- ==========================================
-- Havvk科技 | 真实载具飞行 (直接开游戏里的车)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_VehicleFly") then
    PlayerGui.Havvk_VehicleFly:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_VehicleFly"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- 主界面 UI
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 260, 0, 380)
main.Position = UDim2.new(0.5, -130, 0.5, -190)
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
title.Text = " 真实载具飞行"
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
local isFlying = false
local flySpeed = 60
local vBv, vBg
local driveConn
local currentVehicleRoot = nil

local keys = { W = false, A = false, S = false, D = false, Up = false, Down = false }

-- ==========================================
-- 核心载具飞行逻辑
-- ==========================================
local function stopVehicleFly()
    isFlying = false
    keys.W, keys.A, keys.S, keys.D, keys.Up, keys.Down = false, false, false, false, false, false
    
    if vBv then vBv:Destroy() vBv = nil end
    if vBg then vBg:Destroy() vBg = nil end
    if driveConn then driveConn:Disconnect() driveConn = nil end
    
    currentVehicleRoot = nil
end

local function startVehicleFly()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChild("Humanoid")
    
    -- 检测是否坐进了载具
    if not humanoid or not humanoid.SeatPart then
        return game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "提示"; Text = "请先坐进一辆车！"; Duration = 3
        })
    end

    -- 获取载具的本体 (AssemblyRootPart 是最稳的受力点)
    local seat = humanoid.SeatPart
    local vehicleRoot = seat.AssemblyRootPart or seat
    currentVehicleRoot = vehicleRoot

    isFlying = true

    -- 给车加上飞行物理
    vBv = Instance.new("BodyVelocity")
    vBv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    vBv.Velocity = Vector3.new(0, 0, 0)
    vBv.Parent = vehicleRoot
    
    vBg = Instance.new("BodyGyro")
    vBg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    vBg.P = 10000
    vBg.D = 500
    vBg.Parent = vehicleRoot

    -- 核心飞行循环
    driveConn = RunService.Heartbeat:Connect(function()
        if not isFlying or not vBv or not vBg or not currentVehicleRoot or not currentVehicleRoot.Parent then 
            return 
        end
        
        local cam = workspace.CurrentCamera
        if not cam then return end

        local moveDir = Vector3.new(0, 0, 0)
        
        -- 水平方向 (基于相机视角)
        if keys.W then moveDir = moveDir + cam.CFrame.LookVector end
        if keys.S then moveDir = moveDir - cam.CFrame.LookVector end
        if keys.D then moveDir = moveDir + cam.CFrame.RightVector end
        if keys.A then moveDir = moveDir - cam.CFrame.RightVector end
        
        -- 垂直方向
        if keys.Up then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if keys.Down then moveDir = moveDir - Vector3.new(0, 1, 0) end

        if moveDir.Magnitude > 0 then
            vBv.Velocity = moveDir.Unit * flySpeed
        else
            vBv.Velocity = Vector3.new(0, 0, 0) -- 悬停
        end
        
        -- 强制车身保持水平，防侧翻
        vBg.CFrame = CFrame.new(currentVehicleRoot.Position, currentVehicleRoot.Position + cam.CFrame.LookVector)
    end)
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

local flyBtn = createUIButton("检测载具并起飞 [关]", UDim2.new(0, 10, 0, 45), UDim2.new(1, -20, 0, 40))
local spdLabel = createUIButton("速度: " .. flySpeed, UDim2.new(0, 10, 0, 95), UDim2.new(1, -20, 0, 30), Color3.fromRGB(40, 40, 40))
local minusBtn = createUIButton("-", UDim2.new(0, 10, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))
local plusBtn = createUIButton("+", UDim2.new(1, -60, 0, 135), UDim2.new(0, 50, 0, 30), Color3.fromRGB(60, 60, 60))

-- 控制方向键
local wBtn = createUIButton("W (前)", UDim2.new(0.5, -40, 0, 185), UDim2.new(0, 80, 0, 35), Color3.fromRGB(80, 80, 80))
local aBtn = createUIButton("A (左)", UDim2.new(0, 25, 0, 230), UDim2.new(0, 60, 0, 35), Color3.fromRGB(80, 80, 80))
local sBtn = createUIButton("S (后)", UDim2.new(0.5, -40, 0, 230), UDim2.new(0, 80, 0, 35), Color3.fromRGB(80, 80, 80))
local dBtn = createUIButton("D (右)", UDim2.new(1, -85, 0, 230), UDim2.new(0, 60, 0, 35), Color3.fromRGB(80, 80, 80))

-- 垂直升降键
local upBtn = createUIButton("↑ 上升", UDim2.new(0, 25, 0, 285), UDim2.new(0, 95, 0, 35), Color3.fromRGB(0, 120, 200))
local downBtn = createUIButton("↓ 下降", UDim2.new(1, -120, 0, 285), UDim2.new(0, 95, 0, 35), Color3.fromRGB(200, 80, 80))

-- ==========================================
-- 交互逻辑
-- ==========================================

-- 绑定屏幕按钮
local function bindBtn(btn, key, activeColor)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            keys[key] = true
            btn.BackgroundColor3 = activeColor or Color3.fromRGB(0, 150, 80)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            keys[key] = false
            btn.BackgroundColor3 = (key == "Up" and Color3.fromRGB(0, 120, 200)) or (key == "Down" and Color3.fromRGB(200, 80, 80)) or Color3.fromRGB(80, 80, 80)
        end
    end)
end

bindBtn(wBtn, "W")
bindBtn(aBtn, "A")
bindBtn(sBtn, "S")
bindBtn(dBtn, "D")
bindBtn(upBtn, "Up")
bindBtn(downBtn, "Down")

-- 键盘绑定
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not isFlying then return end
    if input.KeyCode == Enum.KeyCode.W then keys.W = true end
    if input.KeyCode == Enum.KeyCode.A then keys.A = true end
    if input.KeyCode == Enum.KeyCode.S then keys.S = true end
    if input.KeyCode == Enum.KeyCode.D then keys.D = true end
    if input.KeyCode == Enum.KeyCode.Space then keys.Up = true end
    if input.KeyCode == Enum.KeyCode.LeftShift then keys.Down = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then keys.W = false end
    if input.KeyCode == Enum.KeyCode.A then keys.A = false end
    if input.KeyCode == Enum.KeyCode.S then keys.S = false end
    if input.KeyCode == Enum.KeyCode.D then keys.D = false end
    if input.KeyCode == Enum.KeyCode.Space then keys.Up = false end
    if input.KeyCode == Enum.KeyCode.LeftShift then keys.Down = false end
end)

-- 主开关
flyBtn.MouseButton1Click:Connect(function()
    if not isFlying then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChild("Humanoid")
        
        -- 如果不在车上，拦截并提示
        if not humanoid or not humanoid.SeatPart then
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "操作失败"; Text = "你必须先坐进游戏里的载具！"; Duration = 3
            })
            return
        end
        
        startVehicleFly()
        flyBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        flyBtn.Text = "飞行中 [开]"
    else
        stopVehicleFly()
        flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        flyBtn.Text = "检测载具并起飞 [关]"
    end
end)

minusBtn.MouseButton1Click:Connect(function()
    if flySpeed > 10 then flySpeed = flySpeed - 10; spdLabel.Text = "速度: " .. flySpeed end
end)
plusBtn.MouseButton1Click:Connect(function()
    if flySpeed < 300 then flySpeed = flySpeed + 10; spdLabel.Text = "速度: " .. flySpeed end
end)
-- ==========================================
-- 清理与拖拽
-- ==========================================
local function cleanup()
    stopVehicleFly()
    gui:Destroy()
end

closeBtn.MouseButton1Click:Connect(cleanup)
LocalPlayer.CharacterAdded:Connect(function()
    if isFlying then
        stopVehicleFly()
        flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        flyBtn.Text = "检测载具并起飞 [关]"
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
