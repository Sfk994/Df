-- ==========================================
-- Havvk科技 | 高级透视与自瞄模块 (居中/刷新/变速箱
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
gui.IgnoreGuiInset = true -- 【关键修复】：忽略顶部栏，保证锁定圈绝对居中
gui.Parent = PlayerGui

-- ==========================================
-- 1. 屏幕中心里锁定圈
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
-- 2. 主界面 UI (加高以容纳新按钮)
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 310)
main.Position = UDim2.new(0.5, -120, 0.5, -155)
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
title.Text = " 自瞄Nhavvk科技 V2"
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
-- 3. 功能逻辑与变量
-- ==========================================
local espEnabled = false
local aimbotEnabled = false
local teamCheckEnabled = false -- 阵营区分开关 (默认关，全部标红)
local aimSpeedMode = 1 -- 1:秒锁, 2:快速平滑, 3:慢速
local activeHighlights = {}

local function isTeammate(player)
    if not teamCheckEnabled then return false end -- 如果关了阵营区分，全部视为敌人(红色)
    if not LocalPlayer.Team or not player.Team then return false end
    return LocalPlayer.Team == player.Team
end

local function createHighlight(char, player)
    if not char then return end
    if activeHighlights[char] then
        activeHighlights[char]:Destroy()
        activeHighlights[char] = nil
    end
    
    local hl = Instance.new("Highlight")
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

-- 刷新 ESP 逻辑
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

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if espEnabled then createHighlight(char, player) end
    end)
end)

local function getClosestEnemy()
    local closestDist = math.huge
    local target = nil
    local camPos = workspace.CurrentCamera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        -- 自瞄逻辑：如果开启了阵营区分，则忽略队友；没开则全部锁定
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
        circleStroke.Color = Color3.fromRGB(255, 255, 0) -- 锁定时变黄
        circleStroke.Transparency = 0
        
        local camera = workspace.CurrentCamera
        local targetPos = targetHead.Position
        local camPos = camera.CFrame.Position
        local targetCFrame = CFrame.lookAt(camPos, targetPos)
        
        -- 优化后的速度档位
        if aimSpeedMode == 1 then
            camera.CFrame = targetCFrame -- 秒锁
        elseif aimSpeedMode == 2 then
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.8) -- 【拉高】明显更快
        else
            camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.5) -- 【拉高】不再慢吞吞
        end
    else
        circleStroke.Color = Color3.fromRGB(255, 255, 255)
        circleStroke.Transparency = 0.5
    end
end)

-- ==========================================
-- 4. UI 按钮事件
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
local refreshBtn = createUIButton("刷新高光 (Refresh)", 245, Color3.fromRGB(100, 100, 100))

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
        speedBtn.Text = "自瞄速度: 2档 (高速)"
    else
        speedBtn.Text = "自瞄速度: 3档 (中速)"
    end
end)

teamBtn.MouseButton1Click:Connect(function()
    teamCheckEnabled = not teamCheckEnabled
    if teamCheckEnabled then
        teamBtn.Text = "阵营区分: [开] (队友绿)"
        teamBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
    else
        teamBtn.Text = "阵营区分: [关] (全红)"
        teamBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end
    updateESP() -- 切换后立刻刷新颜色
end)

refreshBtn.MouseButton1Click:Connect(function()
    updateESP()
    -- 按钮闪烁反馈
    refreshBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
    task.wait(0.2)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
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
