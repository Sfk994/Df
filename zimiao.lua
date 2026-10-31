-- ==========================================
-- Havvk科技 | 高级透视与自瞄模块 (区分队友/变速)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_ESP_Aimbot") then
    PlayerGui.Havvk_ESP_Aimbot:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_ESP_Aimbot"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

-- ==========================================
-- 1. 屏幕中心锁定圈
-- ==========================================
local lockCircle = Instance.new("Frame")
lockCircle.Name = "LockCircle"
lockCircle.Size = UDim2.new(0, 40, 0, 40)
lockCircle.Position = UDim2.new(0.5, -20, 0.5, -20)
lockCircle.BackgroundTransparency = 1
lockCircle.Visible = false -- 自瞄开启后才显示
lockCircle.Parent = gui

local circleStroke = Instance.new("UIStroke")
circleStroke.Color = Color3.fromRGB(255, 255, 255)
circleStroke.Thickness = 2
circleStroke.Transparency = 0.5
circleStroke.Parent = lockCircle

Instance.new("UICorner", lockCircle).CornerRadius = UDim.new(1, 0)

-- ==========================================
-- 2. 主界面 UI
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 250)
main.Position = UDim2.new(0.5, -120, 0.5, -125)
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
title.Text = " 视觉与战斗模块"
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
-- 3. 功能逻辑变量
-- ==========================================
local espEnabled = false
local aimbotEnabled = false
local aimSpeedMode = 1 -- 1:秒锁, 2:平滑(0.1s), 3:慢速(0.2s)
local activeHighlights = {}

-- 判断是否队友
local function isTeammate(player)
    if not LocalPlayer.Team or not player.Team then return false end
    return LocalPlayer.Team == player.Team
end

-- 生成高光
local function createHighlight(char, player)
    if not char then return end
    if activeHighlights[char] then
        activeHighlights[char]:Destroy()
        activeHighlights[char] = nil
    end
    
    local hl = Instance.new("Highlight")
    -- 区分队友和敌人颜色
    if isTeammate(player) then
        hl.FillColor = Color3.fromRGB(0, 255, 0) -- 队友绿色
        hl.OutlineColor = Color3.fromRGB(0, 150, 0)
    else
        hl.FillColor = Color3.fromRGB(255, 0, 0) -- 敌人红色
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Parent = char
    activeHighlights[char] = hl
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if espEnabled and player.Character then
                createHighlight(player.Character, player)
            else
                if player.Character and activeHighlights[player.Character] then
                    activeHighlights[player.Character]:Destroy()
                    activeHighlights[player.Character] = nil
                end
            end
        end
    end
end

-- 监听玩家重生
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if espEnabled then createHighlight(char, player) end
    end)
end)

-- 获取最近敌人 (过滤队友)
local function getClosestEnemy()
    local closestDist = math.huge
    local target = nil
    local camPos = workspace.CurrentCamera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and not isTeammate(player) then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            
            if humanoid and humanoid.Health > 0 and head then
                local dist = (head.Position - camPos).Magnitude
                if dist < closestDist and dist < 300 then
                    closestDist = dist
                    target = head
                end
            end
        end
    end
    return target
end

-- 自瞄循环
local aimbotConnection = RunService.RenderStepped:Connect(function()
    if not aimbotEnabled then 
        lockCircle.Visible = false
        return 
    end
    
    lockCircle.Visible = true
    local targetHead = getClosestEnemy()
    
    if targetHead then
        -- 锁定到人，锁定圈变黄
        circleStroke.Color = Color3.fromRGB(255, 255, 0)
        circleStroke.Transparency = 0
        
        local camera = workspace.CurrentCamera
        local targetPos = targetHead.Position
        local camPos = camera.CFrame.Position
        local targetCFrame = CFrame.lookAt(camPos, targetPos)
        
        -- 根据档位设置平滑度
        if aimSpeedMode == 1 then
            -- 1档：没有等待，瞬间锁死
            camera.CFrame = targetCFrame
        elseif aimSpeedMode == 2 then
            -- 2档：大约 0.1s 的平滑
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.6)
        else
            -- 3档：大约 0.2s 的平滑，非常丝滑
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.25)
        end
    else
        -- 没锁到人，锁定圈变白且半透明
        circleStroke.Color = Color3.fromRGB(255, 255, 255)
        circleStroke.Transparency = 0.5
    end
end)

-- ==========================================
-- 4. UI 按钮事件
-- ==========================================
local espBtn = Instance.new("TextButton", main)
espBtn.Size = UDim2.new(1, -20, 0, 40)
espBtn.Position = UDim2.new(0, 10, 0, 45)
espBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
espBtn.Text = "玩家高光 (ESP) [关]"
espBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
espBtn.Font = Enum.Font.Gotham
espBtn.TextSize = 14
Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 4)

local aimBtn = Instance.new("TextButton", main)
aimBtn.Size = UDim2.new(1, -20, 0, 40)
aimBtn.Position = UDim2.new(0, 10, 0, 95)
aimBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
aimBtn.Text = "自动瞄准 (Aimbot) [关]"
aimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
aimBtn.Font = Enum.Font.Gotham
aimBtn.TextSize = 14
Instance.new("UICorner", aimBtn).CornerRadius = UDim.new(0, 4)

local speedBtn = Instance.new("TextButton", main)
speedBtn.Size = UDim2.new(1, -20, 0, 40)
speedBtn.Position = UDim2.new(0, 10, 0, 145)
speedBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
speedBtn.Text = "自瞄速度: 1档 (秒锁)"
speedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBtn.Font = Enum.Font.Gotham
speedBtn.TextSize = 14
Instance.new("UICorner", speedBtn).CornerRadius = UDim.new(0, 4)

-- 按钮点击逻辑
espBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    espBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    espBtn.Text = espEnabled and "玩家高光 (ESP) [开]" or "玩家高光 (ESP) [关]"
    updateESP()
end)

aimBtn.MouseButton1Click:Connect(function()
    aimbotEnabled = not aimbotEnabled
    aimBtn.BackgroundColor3 = aimbotEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    aimBtn.Text = aimbotEnabled and "自动瞄准 (Aimbot) [开]" or "自动瞄准 (Aimbot) [关]"
    if not aimbotEnabled then lockCircle.Visible = false end
end)

speedBtn.MouseButton1Click:Connect(function()
    aimSpeedMode = aimSpeedMode + 1
    if aimSpeedMode > 3 then aimSpeedMode = 1 end
    
    if aimSpeedMode == 1 then
        speedBtn.Text = "自瞄速度: 1档 (秒锁)"
    elseif aimSpeedMode == 2 then
        speedBtn.Text = "自瞄速度: 2档 (平滑)"
    else
        speedBtn.Text = "自瞄速度: 3档 (慢速)"
    end
end)

-- ==========================================
-- 5. 清理逻辑
-- ==========================================
local function cleanup()
    espEnabled = false
    aimbotEnabled = false
    if aimbotConnection then aimbotConnection:Disconnect() end
    for char, hl in pairs(activeHighlights) do
        if hl then hl:Destroy() end
    end
    gui:Destroy()
end

closeBtn.MouseButton1Click:Connect(cleanup)

LocalPlayer.CharacterAdded:Connect(function()
    if aimbotEnabled then
        aimbotEnabled = false
        aimBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        aimBtn.Text = "自动瞄准 (Aimbot) [关]"
        lockCircle.Visible = false
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
