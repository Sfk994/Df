-- ==========================================
-- Havvk科技 | 暴力甩人 (高速旋转+全图TP)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_Fling") then
    PlayerGui.Havvk_Fling:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_Fling"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- UI 界面
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 150)
main.Position = UDim2.new(0.5, -100, 0.5, -75)
main.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

local top = Instance.new("Frame", main)
top.Size = UDim2.new(1, 0, 0, 30)
top.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
top.BorderSizePixel = 0

local title = Instance.new("TextLabel", top)
title.Size = UDim2.new(1, -30, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = " 暴力甩人 (Fling)"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 12

local closeBtn = Instance.new("TextButton", top)
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -30, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12

local tipLabel = Instance.new("TextLabel", main)
tipLabel.Size = UDim2.new(1, -20, 0, 30)
tipLabel.Position = UDim2.new(0, 10, 0, 35)
tipLabel.BackgroundTransparency = 1
tipLabel.Text = "开启后将全图巡逻并甩飞敌人\n(极易被踢出游戏)"
tipLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
tipLabel.Font = Enum.Font.Gotham
tipLabel.TextSize = 11
tipLabel.TextWrapped = true

local toggleBtn = Instance.new("TextButton", main)
toggleBtn.Size = UDim2.new(1, -20, 0, 45)
toggleBtn.Position = UDim2.new(0, 10, 0, 90)
toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleBtn.Text = "开启甩人 [关]"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

-- ==========================================
-- 核心逻辑
-- ==========================================
local isFlinging = false
local flingConnection = nil
local bav = nil -- 旋转角速度
local bv = nil -- 悬浮速度

local function stopFling()
    isFlinging = false
    if flingConnection then flingConnection:Disconnect() end
    if bav then bav:Destroy() end
    if bv then bv:Destroy() end
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CanCollide = true
        char.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
    end
end

local function startFling()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Humanoid") then return end
    
    local hrp = char.HumanoidRootPart
    local humanoid = char.Humanoid
    
    isFlinging = true
    
    -- 1. 设置无敌且不会摔死
    humanoid.PlatformStand = true
    
    -- 2. 开启极速自转
    bav = Instance.new("BodyAngularVelocity")
    bav.AngularVelocity = Vector3.new(99999, 99999, 99999)
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.Parent = hrp
    
    -- 3. 强制悬浮，防止掉下去
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = hrp
    
    -- 4. 循环TP去撞人
    flingConnection = RunService.Heartbeat:Connect(function()
        if not isFlinging then return end
        
        local target = nil
        -- 寻找最近的敌人
        local shortestDist = math.huge
        local myPos = hrp.Position
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local targetHrp = player.Character.HumanoidRootPart
                local dist = (targetHrp.Position - myPos).Magnitude
                
                -- 过滤队友（可选）
                local isTeammate = LocalPlayer.Team and player.Team == LocalPlayer.Team
                
                if not isTeammate and dist < shortestDist then
                    shortestDist = dist
                    target = targetHrp
                end
            end
        end
        
        -- 如果找到人，就瞬移贴脸
        if target then
          -- 取消锚定，加上极其暴力的速度
            hrp.CFrame = target.CFrame
        end
    end)
end

-- ==========================================
-- 开关事件
-- ==========================================
toggleBtn.MouseButton1Click:Connect(function()
    isFlinging = not isFlinging
    toggleBtn.BackgroundColor3 = isFlinging and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(50, 50, 50)
    toggleBtn.Text = isFlinging and "甩人中 (警告: 易被踢) [开]" or "开启甩人 [关]"
    
    if isFlinging then
        startFling()
    else
        stopFling()
    end
end)

-- 清理与拖拽
closeBtn.MouseButton1Click:Connect(function()
    stopFling()
    gui:Destroy()
end)

LocalPlayer.CharacterAdded:Connect(function()
    if isFlinging then
        stopFling()
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        toggleBtn.Text = "开启甩人 [关]"
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