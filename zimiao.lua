-- ==========================================
-- Havvk科技 | 高级透视与智能吸附自瞄 (距离可调版)
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
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- 1. 屏幕中心锁定圈 (扩大至 225 像素)
-- ==========================================
local lockCircle = Instance.new("Frame")
lockCircle.Name = "LockCircle"
-- 225 像素半径，直径就是 450
lockCircle.Size = UDim2.new(0, 450, 0, 450)
lockCircle.Position = UDim2.new(0.5, -225, 0.5, -225)
lockCircle.BackgroundTransparency = 1
lockCircle.Visible = false
lockCircle.Parent = gui

local circleStroke = Instance.new("UIStroke")
circleStroke.Color = Color3.fromRGB(255, 255, 255)
circleStroke.Thickness = 2
circleStroke.Transparency = 0.5
circleStroke.Parent = lockCircle

Instance.new("UICorner", lockCircle).CornerRadius = UDim.new(1, 0)

-- 内部小准星（可选，更好看）
local centerDot = Instance.new("Frame")
centerDot.Size = UDim2.new(0, 4, 0, 4)
centerDot.Position = UDim2.new(0.5, -2, 0.5, -2)
centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
centerDot.BackgroundTransparency = 0.5
centerDot.Parent = lockCircle
Instance.new("UICorner", centerDot).CornerRadius = UDim.new(1, 0)

-- ==========================================
-- 2. 主界面 UI (加高版)
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 300)
main.Position = UDim2.new(0.5, -120, 0.5, -150)
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
title.Text = " 视觉与战斗 V3"
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
-- 3. 状态逻辑
-- ==========================================
local espEnabled = false
local aimbotEnabled = false
local teamCheckEnabled = false
local aimSpeedMode = 1
local espDistanceMode = 1 -- 1:300, 2:800, 3:1500
local activeHighlights = {}

-- 获取当前设定的透视距离
local function getCurrentEspDist()
    if espDistanceMode == 1 then return 300 
    elseif espDistanceMode == 2 then return 800 
    else return 1500 end
end

local function isTeammate(player)
    if not teamCheckEnabled then return false end
    if LocalPlayer.Team and player.Team then
        return LocalPlayer.Team == player.Team
    end
    return false
end

local function createHighlight(char, player)
    if not char then return end
    if activeHighlights[char] then activeHighlights[char]:Destroy() end
    
    local hl = Instance.new("Highlight")
    if isTeammate(player) then
        hl.FillColor = Color3.fromRGB(0, 255, 0) 
        hl.OutlineColor = Color3.fromRGB(0, 150, 0)
    else
        hl.FillColor = Color3.fromRGB(255, 0, 0) 
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Parent = char
    activeHighlights[char] = hl
end

-- 自动刷新与距离检测逻辑
local function updateESP()
    if not espEnabled or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    local myPos = LocalPlayer.Character.HumanoidRootPart.Position
    local maxDist = getCurrentEspDist()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local char = player.Character
            local dist = (char.HumanoidRootPart.Position - myPos).Magnitude
            
            -- 如果超出距离，销毁高光
            if dist > maxDist then
                if activeHighlights[char] then
                    activeHighlights[char]:Destroy()
                    activeHighlights[char] = nil
                end
            else
                -- 如果在距离内，没有高光就创建，有但颜色不对就刷新
                local existing = activeHighlights[char]
                if not existing or not existing.Parent then
                    createHighlight(char, player)
                else
                    if isTeammate(player) and existing.FillColor ~= Color3.fromRGB(0, 255, 0) then
                        createHighlight(char, player)
                    elseif not isTeammate(player) and existing.FillColor ~= Color3.fromRGB(255, 0, 0) then
                        createHighlight(char, player)
                    end
                end
            end
        end
    end
end

-- 每 1 秒自动扫描全场
task.spawn(function()
    while task.wait(1) do
        updateESP()
    end
end)

-- ==========================================
-- 4. 智能吸附自瞄 (FOV 225)
-- ==========================================
local function getClosestEnemyInFOV()
    local closestDist = math.huge
    local target = nil
    local cam = workspace.CurrentCamera
    local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local fovRadius = 225 -- 【修改】：吸附范围 225 像素

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and not isTeammate(player) then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            
            if humanoid and humanoid.Health > 0 and head then
                local screenPos, onScreen = cam:WorldToViewportPoint(head.Position)
                if onScreen then
                    local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if distToCenter < fovRadius and distToCenter < closestDist then
                        closestDist = distToCenter
                        target = head
                    end
                end
            end
        end
    end
    return target
end

local aimbotConnection = RunService.RenderStepped:Connect(function()
    if not aimbotEnabled then 
        lockCircle.Visible = false
        return 
    end
    
    lockCircle.Visible = true
    local targetHead = getClosestEnemyInFOV()
    
    if targetHead then
        circleStroke.Color = Color3.fromRGB(255, 255, 0)
        circleStroke.Transparency = 0
        
        local camera = workspace.CurrentCamera
        local targetCFrame = CFrame.lookAt(camera.CFrame.Position, targetHead.Position)
        
        -- 【修改】：大幅提高吸附速度
        if aimSpeedMode == 1 then
            camera.CFrame = targetCFrame -- 秒锁
        elseif aimSpeedMode == 2 then
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.85) -- 极快
        else
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.6) -- 较快
        end
    else
        circleStroke.Color = Color3.fromRGB(255, 255, 255)
        circleStroke.Transparency = 0.5
    end
end)

-- ==========================================
-- 5. UI 事件
-- ==========================================
local function createUIButton(text, yPos, color)
    local btn = Instance.new("TextButton", main)
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = color or Color3.fromRGB(50, 50, 50)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    return btn
end

local espBtn = createUIButton("玩家高光 (ESP) [关]", 45)
local aimBtn = createUIButton("自动瞄准 (Aimbot) [关]", 95)
local speedBtn = createUIButton("自瞄速度: 1档 (秒锁)", 145, Color3.fromRGB(60, 60, 60))
local teamBtn = createUIButton("阵营区分: [关] (全红)", 195, Color3.fromRGB(60, 60, 60))
local distBtn = createUIButton("高光距离: 300", 245, Color3.fromRGB(60, 60, 60)) -- 新按钮

espBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    espBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    espBtn.Text = espEnabled and "玩家高光 (ESP) [开]" or "玩家高光 (ESP) [关]"
    if espEnabled then updateESP() else
        for char, hl in pairs(activeHighlights) do hl:Destroy() end
        table.clear(activeHighlights)
    end
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
    if aimSpeedMode == 1 then speedBtn.Text = "自瞄速度: 1档 (秒锁)"
    elseif aimSpeedMode == 2 then speedBtn.Text = "自瞄速度: 2档 (极快)"
    else speedBtn.Text = "自瞄速度: 3档 (较快)" end
end)

teamBtn.MouseButton1Click:Connect(function()
    teamCheckEnabled = not teamCheckEnabled
    teamBtn.BackgroundColor3 = teamCheckEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
    teamBtn.Text = teamCheckEnabled and "阵营区分: [开] (队友绿)" or "阵营区分: [关] (全红)"
    updateESP()
end)

-- 高光距离切换逻辑
distBtn.MouseButton1Click:Connect(function()
    espDistanceMode = espDistanceMode + 1
    if espDistanceMode > 3 then espDistanceMode = 1 end
    
    if espDistanceMode == 1 then distBtn.Text = "高光距离: 300"
    elseif espDistanceMode == 2 then distBtn.Text = "高光距离: 800"
    else distBtn.Text = "高光距离: 1500" end
    
    updateESP() -- 切换后立刻刷新
end)

-- ==========================================
-- 6. 清理与拖拽
-- ==========================================
local function cleanup()
    espEnabled = false
    aimbotEnabled = false
    if aimbotConnection then aimbotConnection:Disconnect() end
    for char, hl in pairs(activeHighlights) do hl:Destroy() end
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
