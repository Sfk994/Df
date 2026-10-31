-- =========================================
-- Havvk科技 | 纯净稳如老狗开关版
-- =========================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HavvkTech_Stable"
screenGui.ResetOnSpawn = false
screenGui.Parent = game:GetService("CoreGui")

-- 主窗口
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 260)
mainFrame.Position = UDim2.new(0.5, -140, 0.5, -130)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 6)
mainCorner.Parent = mainFrame

-- 顶部标题栏
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 15, 0, 0)
title.BackgroundTransparency = 1
title.Text = " Havvk科技"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = topBar

-- 最小化按钮
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 35, 0, 40)
minBtn.Position = UDim2.new(1, -70, 0, 0)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.Parent = topBar

-- 关闭按钮
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 40)
closeBtn.Position = UDim2.new(1, -35, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Parent = topBar

-- 内容容器 (带自动排版，绝对不乱)
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -40)
content.Position = UDim2.new(0, 0, 0, 40)
content.BackgroundTransparency = 1
content.Parent = mainFrame

local uiList = Instance.new("UIListLayout")
uiList.Padding = UDim.new(0, 10)
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.Parent = content

local uiPadding = Instance.new("UIPadding")
uiPadding.PaddingTop = UDim.new(0, 10)
uiPadding.Parent = content

-- 关闭和最小化逻辑
closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)
local isMin = false
minBtn.MouseButton1Click:Connect(function()
    isMin = not isMin
    if isMin then mainFrame.Size = UDim2.new(0, 280, 0, 40) else mainFrame.Size = UDim2.new(0, 280, 0, 260) end
end)

-- ==========================================
-- 稳定的开关组件
-- ==========================================
local function createSwitch(textStr, defaultState, callback)
    local state = defaultState
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 45)
    btn.BackgroundColor3 = state and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    btn.Text = textStr .. (state and " [开]" or " [关]")
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.AutoButtonColor = false
    btn.Parent = content
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
        btn.Text = textStr .. (state and " [开]" or " [关]")
        pcall(callback, state) -- 用 pcall 保护，哪怕功能报错 UI 也不会卡死
    end)
end

-- ==========================================
-- 添加你的功能开关
-- ==========================================

-- 开关 1：极速模式
createSwitch("极速行走", false, function(state)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        if state then
            char.Humanoid.WalkSpeed = 100
        else
            char.Humanoid.WalkSpeed = 16
        end
    end
end)

-- 开关 2：超级跳
createSwitch("超级跳跃", false, function(state)
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("Humanoid") then
        if state then
            char.Humanoid.JumpPower = 100
            char.Humanoid.UseJumpPower = true
        else
            char.Humanoid.JumpPower = 50
        end
    end
end)

-- ==========================================
-- 拖拽逻辑
-- ==========================================
local dragging, dragInput, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
  
