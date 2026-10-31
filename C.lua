-- ==========================================
-- Havvk科技 | 极简多列移动端版
-- ==========================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HavvkTech_Mobile"
screenGui.ResetOnSpawn = false
screenGui.Parent = game:GetService("CoreGui")

-- 主窗口 (放大版)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 320, 0, 330)
mainFrame.Position = UDim2.new(0.5, -160, 0.5, -165)
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
title.Size = UDim2.new(1, -60, 1, 0)
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
minBtn.Size = UDim2.new(0, 40, 0, 40)
minBtn.Position = UDim2.new(1, -80, 0, 0)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.Parent = topBar

-- 关闭按钮
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -40, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Parent = topBar

-- 内容容器
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -40)
content.Position = UDim2.new(0, 0, 0, 40)
content.BackgroundTransparency = 1
content.Parent = mainFrame

-- 关闭和最小化逻辑
closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)
local isMin = false
minBtn.MouseButton1Click:Connect(function()
    isMin = not isMin
    if isMin then mainFrame.Size = UDim2.new(0, 320, 0, 40) else mainFrame.Size = UDim2.new(0, 320, 0, 330) end
end)

-- ==========================================
-- 通用组件生成函数 (适配移动端)
-- ==========================================

-- 普通按钮
local function createButton(text, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Parent = content
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn
    
    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- 速度滑块 (支持移动端触摸拖动)
local function createSlider(yPos)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, 50)
    frame.Position = UDim2.new(0, 10, 0, yPos)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.Parent = content
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = frame

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 0, 20)
    text.BackgroundTransparency = 1
    text.Text = "移动速度: 16"
    text.TextColor3 = Color3.fromRGB(200, 200, 200)
    text.Font = Enum.Font.Gotham
    text.TextSize = 12
    text.Parent = frame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 280, 0, 6)
    bar.Position = UDim2.new(0, 10, 0, 30)
    bar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bar.Parent = frame

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    fill.Parent = bar
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local isDragging = false
    
    local function updateSlider(input)
        local posX = math.clamp(input.Position.X - bar.AbsolutePosition.X, 0, bar.AbsoluteSize.X)
        local percent = posX / bar.AbsoluteSize.X
        fill.Size = UDim2.new(percent, 0, 1, 0)
        local speed = math.floor(16 + (percent * 184)) -- 范围 16 到 200
        text.Text = "移动速度: " .. speed
        
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.WalkSpeed = speed
        end
    end

    bar.InputBegan:Connect(function(input)
    
