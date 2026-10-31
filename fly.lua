-- ==========================================
-- Havvk科技 | 飞行+穿墙 (绝对防弹版)
-- ==========================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- 安全获取 PlayerGui
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
if not PlayerGui then
    PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
end
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_FlyModule") then
    PlayerGui:FindFirstChild("Havvk_FlyModule"):Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Havvk_FlyModule"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 240, 0, 230)
mainFrame.Position = UDim2.new(0.5, -120, 0.5, -115)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = mainFrame

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 35)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = " 飞行模块"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -35, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = topBar

local flying = false
local isNoclip = false
local flySpeed = 50
local bv, bg
local RenderConnection

local function stopFlying()
    flying = false
    if bv then pcall(function() bv:Destroy() end) bv = nil end
    if bg then pcall(function() bg:Destroy() end) bg = nil end
    if RenderConnection then pcall(function() RenderConnection:Disconnect() end) RenderConnection = nil end
end

closeBtn.MouseButton1Click:Connect(function()
    stopFlying()
    screenGui:Destroy()
end)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 40)
toggleBtn.Position = UDim2.new(0, 10, 0, 45)
toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleBtn.Text = "开启飞行 [关]"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.Gotham
toggleBtn.TextSize = 14
toggleBtn.Parent = mainFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 4)
btnCorner.Parent = toggleBtn

local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(1, -20, 0, 40)
noclipBtn.Position = UDim2.new(0, 10, 0, 90)
noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
noclipBtn.Text = "旋转穿墙 [关]"
noclipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
noclipBtn.Font = Enum.Font.Gotham
noclipBtn.TextSize = 14
noclipBtn.Parent = mainFrame

local noclipCorner = Instance.new("UICorner")
noclipCorner.CornerRadius = UDim.new(0, 4)
noclipCorner.Parent = noclipBtn

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, -20, 0, 30)
speedLabel.Position = UDim2.new(0, 10, 0, 140)
speedLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
speedLabel.Text = "当前速度: " .. flySpeed
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.Parent = mainFrame

local labelCorner = Instance.new("UICorner")
labelCorner.CornerRadius = UDim.new(0, 4)
labelCorner.Parent = speedLabel

local minusBtn = Instance.new("TextButton")
minusBtn.Size = UDim2.new(0, 40, 0, 30)
minusBtn.Position = UDim2.new(0, 10, 0, 180)
minusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
minusBtn.Text = "-"
minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 20
minusBtn.Parent = mainFrame

local minusCorner = Instance.new("UICorner")
minusCorner.CornerRadius = UDim.new(0, 4)
minusCorner.Parent = minusBtn

local plusBtn = Instance.new("TextButton")
plusBtn.Size = UDim2.new(0, 40, 0, 30)
plusBtn.Position = UDim2.new(1, -50, 0, 180)
plusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
plusBtn.Text = "+"
plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 18
plusBtn.Parent = mainFrame

local plusCorner = Instance.new("UICorner")
plusCorner.CornerRadius = UDim.new(0, 4)
plusCorner.Parent = plusBtn

minusBtn.MouseButton1Click:Connect(function()
    if flySpeed > 10 then
        flySpeed = flySpeed - 10
        speedLabel.Text = "当前速度: " .. flySpeed
    end
end)

plusBtn.MouseButton1Click:Connect(function()
    if flySpeed < 200 then
        flySpeed = flySpeed + 10
        speedLabel.Text = "当前速度: " .. flySpeed
    end
end)

noclipBtn.MouseButton1Click:Connect(function()
    isNoclip = not isNoclip
    if isNoclip then
        noclipBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        noclipBtn.Text = "旋转穿墙 [开]"
    else
        noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        noclipBtn.Text = "旋转穿墙 [关]"
    end
end)

toggleBtn.MouseButton1Click:Connect(function()
    flying = not flying
    
    if flying then
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then 
            flying = false
            return 
        end
        
        toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        toggleBtn.Text = "开启飞行 [开]"
        
        local hrp = char.HumanoidRootPart
        
        -- 用 pcall 包裹物理实例创建，防止执行器禁用API导致崩溃
        local success = pcall(function()
            bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Velocity = Vector3.new(0,0,0)
            bv.Parent = hrp
            
            bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bg.P = 1000
            bg.Parent = hrp
        end)
        
        if not success then
            -- 如果创建失败，自动关闭并提示
            flying = false
            toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            toggleBtn.Text = "开启飞行 [关]"
            return
        end
        
        RenderConnection = RunService.RenderStepped:Connect(function()
            if not flying or not bv or not bg then return end
            local c = LocalPlayer.Character
            local cam = workspace.CurrentCamera -- 每次循环都重新获取，防止卡 nil
            if c and c:FindFirstChild("Humanoid") and cam then
                local moveDir = c.Humanoid.MoveDirection
                
                -- 解决坐标反向问题
                local finalVelocity = (cam.CFrame.LookVector * moveDir.Z + cam.CFrame.RightVector * moveDir.X) * flySpeed * -1
                bv.Velocity = finalVelocity
                
                -- 解决 tick() 为 nil 的问题，改用 os.clock()
                if isNoclip then
                    local spin = os.clock() * 10000
                    bg.CFrame = cam.CFrame * CFrame.Angles(math.rad(spin), math.rad(spin), 0)
                else
                    bg.CFrame = cam.CFrame
                end
            end
        end)
        
    else
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        toggleBtn.Text = "开启飞行 [关]"
        stopFlying()
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    if flying then
        stopFlying()
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        toggleBtn.Text = "开启飞行 [关]"
        noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        noclipBtn.Text = "旋转穿墙 [关]"
        isNoclip = false
    end
end)

local dragging, dragInput, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
topBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
