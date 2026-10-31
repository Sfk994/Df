local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

local wallCache = {}
local isXray = true

print("【Havvk】开始寻找墙体并缓存...")

-- 第一阶段：只扫描一次地图，找出所有的墙
for _, obj in pairs(Workspace:GetDescendants()) do
    if obj:IsA("BasePart") and not obj:IsDescendantOf(LocalPlayer.Character) then
        local name = string.lower(obj.Name)
        -- 之前你截图里扫出来的名字（Siding, Inner, Board 等）
        if string.find(name, "wall") or string.find(name, "siding") or string.find(name, "inner") or string.find(name, "board") or string.find(name, "door") or string.find(name, "floor") then
            table.insert(wallCache, obj)
        end
    end
end

print("【Havvk】找到", #wallCache, "个墙体，开始循环透视！")

-- 第二阶段：高频但低消耗的循环（只处理缓存里的墙）
task.spawn(function()
    while isXray do
        for i = 1, #wallCache do
            local wall = wallCache[i]
            if wall and wall.Parent then
                -- 强行修改本地透明度，并且把材质设为玻璃或减小厚度防渲染穿透
                wall.LocalTransparencyModifier = 1
            end
        end
        task.wait(0.2) -- 每秒检查 5 次，响应极快，而且完全不卡
    end
end)