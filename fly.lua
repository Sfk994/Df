local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not PlayerGui then return end

if PlayerGui:FindFirstChild("Havvk_FlyModule") then
    PlayerGui.Havvk_FlyModule:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Havvk_FlyModule"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, 230)
main.Position = UDim2.new(0.5, -120, 0.5, -115)
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
title.Text = " 飞行模块"
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

local flying, isNoclip = false, false
local flySpeed = 50
local bv, bg, renderConn

-- 恢复碰撞体积的函数
local function restoreCollision()
    if LocalPlayer.Character then
        for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = true
            end
        end
    end
end

local function stopFly()
    flying = false
    if bv then bv:Destroy() bv = nil end
    if bg then bg:Destroy() bg = nil end
    if renderConn then renderConn:Disconnect() renderConn = nil end
    restoreCollision() -- 关闭飞行时恢复碰撞
end

closeBtn.MouseButton1Click:Connect(function()
    stopFly()
    gui:Destroy()
end)

local flyBtn = Instance.new("TextButton", main)
flyBtn.Size = UDim2.new(1, -20, 0, 40)
flyBtn.Position = UDim2.new(0, 10, 0, 45)
flyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
flyBtn.Text = "开启飞行 [关]"
flyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
flyBtn.Font = Enum.Font.Gotham
flyBtn.TextSize = 14
Instance.new("UICorner", flyBtn).CornerRadius = UDim.new(0, 4)

local noclipBtn = Instance.new("TextButton", main)
noclipBtn.Size = UDim2.new(1, -20, 0, 40)
noclipBtn.Position = UDim2.new(0, 10, 0, 90)
noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
noclipBtn.Text = "穿墙模式 [关]"
noclipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
noclipBtn.Font = Enum.Font.Gotham
noclipBtn.TextSize = 14
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 4)

local spdLabel = Instance.new("TextLabel", main)
spdLabel.Size = UDim2.new(1, -20, 0, 30)
spdLabel.Position = UDim2.new(0, 10, 0, 140)
spdLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
spdLabel.Text = "当前速度: " .. flySpeed
spdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
spdLabel.Font = Enum.Font.Gotham
spdLabel.TextSize = 13
Instance.new("UICorner", spdLabel).CornerRadius = UDim.new(0, 4)

local minusBtn = Instance.new("TextButton", main)
minusBtn.Size = UDim2.new(0, 40, 0, 30)
minusBtn.Position = UDim2.new(0, 10, 0, 180)
minusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
minusBtn.Text = "-"
minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 20
Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 4)

local plusBtn = Instance.new("TextButton", main)
plusBtn.Size = UDim2.new(0, 40, 0, 30)
plusBtn.Position = UDim2.new(1, -50, 0, 180)
plusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
plusBtn.Text = "+"
plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 18
Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 4)

minusBtn.MouseButton1Click:Connect(function()
    if flySpeed > 10 then flySpeed = flySpeed - 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)

plusBtn.MouseButton1Click:Connect(function()
    if flySpeed < 200 then flySpeed = flySpeed + 10; spdLabel.Text = "当前速度: " .. flySpeed end
end)

noclipBtn.MouseButton1Click:Connect(function()
    isNoclip = not isNoclip
    noclipBtn.BackgroundColor3 = isNoclip and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(50, 50, 50)
    noclipBtn.Text = isNoclip and "穿墙模式 [开]" or "穿墙模式 [关]"
    if not isNoclip then restoreCollision() end
end)

flyBtn.MouseButton1Click:Connect(function()
    flying = not flying
    if flying then
        local char = LocalPlayer.Character
        if not char or not char:Fi
