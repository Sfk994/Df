-- =========================================
-- Havvk科技 | 暴力甩人 (碰撞开启+合理速度)676
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
title.Text = " 暴力甩人 (碰撞版)"
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
tipLabel.Text = "全图自动追踪并撞击敌人\n(提醒：极易被系统踢出)"
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
local flingThread = nil
local bav = nil

local function stopFling()
    isFlinging = false
    if flingThread then task.cancel(flingThread) flingThread = nil end
    if bav then bav:Destroy() bav = nil end
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CanCollide = true
        -- 恢复默认物理
        char.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
    end
end

local function startFling()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Humanoid") then return end
    
    local hrp = char.HumanoidRootPart
    local humanoid = char.Humanoid
    
    isFlinging = true
    humanoid.PlatformStand = true
    
    -- 【关键修复】：打开全身碰撞，并强制设置重量，防止游戏把你设置成没有质量的幽灵
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = true
            v.Massless = false
            v.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
        end
    end
    
    -- 极速自转
    bav = Instance.new("BodyAngularVelocity")
    bav.AngularVelocity = Vector3.new(99999, 99999, 99999)
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.Parent = hrp
    
    -- 开启一个循环协程，控制瞬移频率
    flingThread = task.spawn(function()
        while isFlinging do
            if not isFlinging then break end
            
            local target = nil
            local shortestDist = math.huge
            local myPos = hrp.Position
            
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
                    local targetHrp = player.Character.HumanoidRootPart
                    local dist = (targetHrp.Position - myPos).Magnitude
                    
                    if player.Character.Humanoid.Health > 0 and not (LocalPlayer.Team and player.Team == LocalPlayer.Team) then
                        if dist < shortestDist then
                            shortestDist = dist
                            target = targetHrp
                        end
                    end
                end
            end
            
            if target then
                -- 直接瞬移到目标身上
                hrp.CFrame = target.CFrame
                -- 【关键修复】：停留 0.3 秒！让物理引擎发生碰撞，把人甩飞
                task.wait(0.3)
            else
                -- 如果没人，原地悬停等待
                task.wait(0.5)
            end
        end
    end)
end

-- 开关事件
toggleBtn.MouseButton1Click:Connect(function()
    isFlinging = not isFlinging
    toggleBtn.BackgroundColor3 = isFlinging and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(50, 50, 50)
    toggleBtn.Text = isFlinging and "甩人中 (易被踢) [开]" or "开启甩人 [关]"
    
    if isFlinging then
        startFling()
    else
        stopFling()
    end
end)

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
