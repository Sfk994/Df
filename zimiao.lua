-- ==========================================
-- Havvk科技 | 玩家高光(ESP) + 自瞄模块
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

-- 主界面
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 190)
main.Position = UDim2.new(0.5, -120, 0.5, -95)
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
-- 功能状态与逻辑变量
-- ==========================================
local espEnabled = false
local aimbotEnabled = false

-- ESP 逻辑
local activeHighlights = {}

local function createHighlight(char)
    if not char then return end
    -- 移除旧的
    if activeHighlights[char] then
        activeHighlights[char]:Destroy()
        activeHighlights[char] = nil
    end
    
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 0, 0) -- 内部红色
    hl.OutlineColor = Color3.fromRGB(255, 255, 255) -- 边框白色
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Parent = char
    activeHighlights[char] = hl
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if espEnabled and player.Character then
                createHighlight(player.Character)
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
        task.wait(0.5) -- 等角色加载完
        if espEnabled then createHighlight(char) end
    end)
end)

-- ==========================================
-- 自瞄逻辑 (Aimbot)
-- ==========================================
local function getClosestEnemy()
    local closestDist = math.huge
    local target = nil
    local camPos = workspace.CurrentCamera.CFrame.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            
            -- 确保敌人活着，且不是队友（如果有队伍系统）
            if humanoid and humanoid.Health > 0 and head then
                local isTeammate = false
                if LocalPlayer.Team and player.Team == LocalPlayer.Team then
                    isTeammate = true
                end
                
                if not isTeammate then
                    local dist = (head.Position - camPos).Magnitude
                    -- 限制自瞄距离，防止隔着半个地图锁人（这里设为 300 距离内）
                    if dist < closestDist and dist < 300 then
                        closestDist = dist
                        target = head
                    end
                end
            end
        end
    end
    return target
end

-- 使用 RenderStepped 实现丝滑自瞄
local aimbotConnection = RunService.RenderStepped:Connect(function()
    if not aimbotEnabled then return end
    local targetHead = getClosestEnemy()
    
    if targetHead then
        local camera = workspace.CurrentCamera
        local targetPos = targetHead.Position
        local camPos = camera.CFrame.Position
        
        -- 用 CFrame.lookAt 将相机锁定在目标头部
        local newCFrame = CFrame.lookAt(camPos, targetPos)
        
        -- 使用 Lerp 平滑过渡，数值越大锁得越死，越小越顺滑(防止晕3D)
        camera.CFrame = camera.CFrame:Lerp(newCFrame, 0.3)
    end
end)

-- ==========================
-- ==========================================
-- UI 按钮
-- ==========================================
local espBtn = Instance.new("TextButton", main)
espBtn.Size = UDim2.new(1, -20, 0, 45)
espBtn.Position = UDim2.new(0, 10, 0, 50)
espBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
espBtn.Text = "玩家高光 (ESP) [关]"
espBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
espBtn.Font = Enum.Font.Gotham
espBtn.TextSize = 14
Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 4)

local aimBtn = Instance.new("TextButton", main)
aimBtn.Size = UDim2.new(1, -20, 0, 45)
aimBtn.Position = UDim2.new(0, 10, 0, 105)
aimBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
aimBtn.Text = "自动瞄准 (Aimbot) [关]"
aimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
aimBtn.Font = Enum.Font.Gotham
aimBtn.TextSize = 14
Instance.new("UICorner", aimBtn).CornerRadius = UDim.new(0, 4)

-- 按钮点击事件
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
end)

-- ==========================================
-- 关闭与清理逻辑
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

-- 死亡时自动关闭自瞄（防止复活后视角乱飞）
LocalPlayer.CharacterAdded:Connect(function()
    if aimbotEnabled then
        aimbotEnabled = false
        aimBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        aimBtn.Text = "自动瞄准 (Aimbot) [关]"
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
