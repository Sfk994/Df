-- ==========================================
-- Havvk科技 | 点击传送 (支持步行/载具)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_ClickTP") then
    PlayerGui.Havvk_ClickTP:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_ClickTP"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true 
gui.Parent = PlayerGui

-- ==========================================
-- UI 界面
-- ==========================================
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 120)
main.Position = UDim2.new(0.5, -100, 0.5, -60)
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
title.Text = " 点击传送 (Click TP)"
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

-- 提示文字
local tipLabel = Instance.new("TextLabel", main)
tipLabel.Size = UDim2.new(1, -20, 0, 30)
tipLabel.Position = UDim2.new(0, 10, 0, 35)
tipLabel.BackgroundTransparency = 1
tipLabel.Text = "开启后，点击地图任意位置即可传送"
tipLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
tipLabel.Font = Enum.Font.Gotham
tipLabel.TextSize = 11
tipLabel.TextWrapped = true

-- 开关按钮
local toggleBtn = Instance.new("TextButton", main)
toggleBtn.Size = UDim2.new(1, -20, 0, 35)
toggleBtn.Position = UDim2.new(0, 10, 0, 75)
toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleBtn.Text = "传送功能 [关]"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

-- ==========================================
-- 核心逻辑变量
-- ==========================================
local isTPEnabled = false
local tpCooldown = false -- 防连点冷却

-- 检测点击是不是点在 UI 上了（防止点菜单把自己传走）
local function isClickingUI(x, y)
    local guiObjects = PlayerGui:GetGuiObjectsAtPosition(x, y)
    for _, obj in ipairs(guiObjects) do
        -- 只要点到的是我们的 UI，就返回 true
        if obj:IsA("GuiObject") and obj:FindFirstAncestorOfClass("ScreenGui") == gui then
            return true
        end
    end
    return false
end

-- 执行传送逻辑
local function doTeleport(targetPosition)
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChild("Humanoid")
    if not hrp or not humanoid then return end

    -- 防卡墙：稍微往天上抬 3 格
    local finalPos = targetPosition + Vector3.new(0, 3, 0)
    
    -- 【核心】：检测是否在载具里
    if humanoid.SeatPart then
        -- 如果在车上，传送车的主体（AssemblyRootPart）
        local vehicleRoot = humanoid.SeatPart.AssemblyRootPart or humanoid.SeatPart
        if vehicleRoot then
            -- 保持载具原朝向，只改变位置
            vehicleRoot.CFrame = CFrame.new(finalPos) * (vehicleRoot.CFrame - vehicleRoot.CFrame.Position)
        end
    else
        -- 步行状态，直接传送角色
        hrp.CFrame = CFrame.new(finalPos)
    end
end

-- 监听全局点击
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- 如果不在开启状态，或者是在聊天框打字，直接返回
    if not isTPEnabled or gameProcessed then return end
    -- 如果处于冷却状态，返回
    if tpCooldown then return end

    -- 判断输入类型（左键点击或触摸屏幕）
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        
        -- 防止点 UI 触发传送
        if isClickingUI(input.Position.X, input.Position.Y) then
            return
        end

        local camera = workspace.CurrentCamera
        local mousePos = input.Position
        
        -- 发射射线检测
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {LocalPlayer.Character} -- 忽略自己
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        
        local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, raycastParams)
        
          -- 如果射线击中了地面/建筑物
        if result and result.Position then
            -- 执行传送
            doTeleport(result.Position)
            
            -- 加个 0.5 秒冷却，防止疯狂连点导致游戏卡死
            tpCooldown = true
            task.wait(0.5)
            tpCooldown = false
        end
    end
end)

-- ==========================================
-- 开关与清理
-- ==========================================
toggleBtn.MouseButton1Click:Connect(function()
    isTPEnabled = not isTPEnabled
    toggleBtn.BackgroundColor3 = isTPEnabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    toggleBtn.Text = isTPEnabled and "传送功能 [开]" or "传送功能 [关]"
end)

closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
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