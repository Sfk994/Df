-- ==========================================
-- Havvk科技 | 高级透视与智能吸附自瞄 (最终版)
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
-- 1. 屏幕中心锁定圈
-- ==========================================
local lockCircle = Instance.new("Frame")
lockCircle.Name = "LockCircle"
lockCircle.Size = UDim2.new(0, 40, 0, 40)
lockCircle.Position = UDim2.new(0.5, -20, 0.5, -20)
lockCircle.BackgroundTransparency = 1
lockCircle.Visible = false
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
title.Text = " 视觉与战斗 (智能吸附)"
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
local activeHighlights = {}

-- 正确区分阵营
local function isTeammate(player)
    if not teamCheckEnabled then return false end
    -- 兼容有队伍和没队伍的游戏
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
        hl.FillColor = Color3.fromRGB(0, 255, 0) -- 队友绿
        hl.OutlineColor = Color3.fromRGB(0, 150, 0)
    else
        hl.FillColor = Color3.fromRGB(255, 0, 0) -- 敌人红
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Parent = char
    activeHighlights[char] = hl
end

local function updateESP()
    if not espEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            -- 如果没有高光，或者阵营状态变了，就重新生成
            local existing = activeHighlights[player.Character]
            if not existing or not existing.Parent then
                createHighlight(player.Character, player)
            else
                -- 更新颜色
                if isTeammate(player) and existing.FillColor ~= Color3.fromRGB(0, 255, 0) then
                    createHighlight(player.Character, player)
                elseif not isTeammate(player) and existing.FillColor ~= Color3.fromRGB(255, 0, 0) then
                    createHighlight(player.Character, player)
                end
            end
        end
    end
end

-- 自动刷新 ESP 定时器 (每 1 秒扫一次全场)
task.spawn(function()
    while task.wait(1) do
        updateESP()
    end
end)

-- ==========================================
-- 4. 智能吸附自瞄逻辑 (FOV)
-- ==========================================
local function getClosestEnemyInFOV()
    local closestDist = math.huge
    local target = nil
    local cam = workspace.CurrentCamera
    local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local fovRadius = 150 -- 【吸附范围】屏幕中心 150 像素内

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and not isTeammate(player) then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            
            if humanoid and humanoid.Health > 0 and head then
                -- 计算敌人在屏幕上的位置
                local screenPos, onScreen = cam:WorldToViewportPoint(head.Position)
                if onScreen then
                    -- 计算敌人与屏幕中心的距离
                    local distToCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    -- 如果在吸附圈内，且是最近的一个
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

-- 自瞄循环
local aimbotConnection = RunService.RenderStepped:Connect(function()
    if not aimbotEnabled then 
        lockCircle.Visible = false
        return 
    end
    
    lockCircle.Visible = true
    local targetHead = getClosestEnemyInFOV()
    
    if targetHead then
        circleStroke.Color = Color3.fromRGB(255, 255, 0) -- 吸附生效，变黄
        circleStroke.Transparency = 0
        
        local camera = workspace.CurrentCamera
        local targetPos = targetHead.Position
        local camPos = camera.CFrame.Position
        local targetCFrame = CFrame.lookAt(camPos, targetPos)
        
        -- 你依然可以划视角，这里只是把你往目标身上“吸”
        if aimSpeedMode == 1 then
            camera.CFrame = targetCFrame
        elseif aimSpeedMode == 2 then
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.6) 
        else
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.3)
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

espBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    espBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    espBtn.Text = espEnabled and "玩家高光 (ESP) [开]" or "玩家高光 (ESP) [关]"
    
    if espEnabled then
        updateESP() -- 开启瞬间扫一次
    else
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
    elseif aimSpeedMode == 2 then speedBtn.Text = "自瞄速度: 2档 (平滑)"
    else speedBtn.Text = "自瞄速度: 3档 (慢速)" end
end)

teamBtn.MouseButton1Click:Connect(function()
    teamCheckEnabled = not teamCheckEnabled
    teamBtn.BackgroundColor3 = teamCheckEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
    teamBtn.Text = teamCheckEnabled and "阵营区分: [开] (队友绿)" or "阵营区分: [关] (全红)"
    updateESP() -- 切换立刻刷新全场
end)

-- ==========================================
-- 6. 清理
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

-- 拖拽
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
