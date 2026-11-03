local RunService = game:GetService("RunService")
local activeHighlights = {}

_G.RainbowESP = true

print("【Havvk】丧尸彩虹高亮已启动！")

-- 独立循环：只负责扫描和清理，不负责变色
task.spawn(function()
    while _G.RainbowESP do
        task.wait(0.5) -- 每半秒扫一次，抓新刷出来的怪
        local hushLocal = workspace:FindFirstChild("HushLocal")
        local zombieFolder = hushLocal and hushLocal:FindFirstChild("Zombies")
        if not zombieFolder then continue end

        for _, zombie in pairs(zombieFolder:GetChildren()) do
            if zombie:IsA("Model") then
                local hum = zombie:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 then
                    if not activeHighlights[zombie] then
                        local hl = Instance.new("Highlight")
                        hl.Name = "Havvk_Rainbow"
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillTransparency = 0.5
                        hl.OutlineTransparency = 0
                        hl.Parent = zombie
                        activeHighlights[zombie] = hl
                    end
                else
                    if activeHighlights[zombie] then
                        activeHighlights[zombie]:Destroy()
                        activeHighlights[zombie] = nil
                    end
                end
            end
        end
        
        -- 清理内存垃圾
        for obj, hl in pairs(activeHighlights) do
            if not obj or not obj.Parent then
                if hl and hl.Parent then hl:Destroy() end
                activeHighlights[obj] = nil
            end
        end
    end
end)

-- 渲染循环：每一帧负责变色和闪烁
RunService.RenderStepped:Connect(function()
    if not _G.RainbowESP then return end
    
    local t = tick()
    -- 计算彩虹色相：时间 * 0.5 (控制变色速度)，% 1 保证在 0-1 之间循环
    local hue = (t * 0.5) % 1 
    local rainbowColor = Color3.fromHSV(hue, 1, 1)
    
    -- 计算闪烁透明度：使用 sin 函数让透明度在 0.2 到 0.8 之间波动
    local flashTransparency = 0.5 + math.sin(t * 10) * 0.3 

    for obj, hl in pairs(activeHighlights) do
        if hl and hl.Parent then
            hl.FillColor = rainbowColor
            hl.OutlineColor = rainbowColor
            hl.FillTransparency = flashTransparency
        end
    end
end)
