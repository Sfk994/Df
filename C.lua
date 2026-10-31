-- ========================================
-- Havvk科技 | WindUI 主框架 (模块化加载版)
-- ==========================================

-- 1. 加载 WindUI 库
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- 2. 创建主窗口
local Window = WindUI:CreateWindow({
    Title = "Havvk科技",
    Icon = "eye",
    Author = "Admin",
    Size = UDim2.fromOffset(450, 500), -- 移动端如果太宽可以改成 350
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightShift, -- 按右Shift隐藏/显示UI
})

-- 3. 创建标签页
local MainTab = Window:Tab({
    Title = "主功能",
    Icon = "home",
})

local SettingTab = Window:Tab({
    Title = "设置",
    Icon = "settings",
})

-- ==========================================
-- 模块 1：按钮形式加载
-- ==========================================
MainTab:Button({
    Title = "飞行",
    Desc = "点击运行飞行",
    Callback = function()
        -- ⚠️ 预留位置：把你分开做的功能A的 Raw 链接填到这里
        local url = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/fly.lua"
        
        -- 如果链接还没做好，先弹个提示
        if string.find(url, "你的用户名") then
            return game:GetService("StarterGui"):SetCore("SendNotification", {Title="提示", Text="功能A链接尚未配置", Duration=3})
        end
        
        -- 异步加载，防止卡死菜单
        task.spawn(function()
            local success, err = pcall(function()
                loadstring(game:HttpGet(url))()
            end)
            if not success then
                WindUI:Notify({
                    Title = "加载失败",
                    Content = "功能加载出错: " .. tostring(err),
                    Duration = 5,
                })
            end
        end)
    end
})

MainTab:Button({
    Title = "自瞄",
    Desc = "点击运行自瞄",
    Callback = function()
        -- ⚠️ 预留位置：把你分开做的功能B的 Raw 链接填到这里
        local url = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/zimiao.lua"
        
        if string.find(url, "你的用户名") then
            return game:GetService("StarterGui"):SetCore("SendNotification", {Title="提示", Text="功能B链接尚未配置", Duration=3})
        end

        task.spawn(function()
            pcall(function()
                loadstring(game:HttpGet(url))()
            end)
        end)
    end
})

MainTab:Button({
    Title = "加载功能 B",
    Desc = "点击运行独立的功能脚本 B",
    Callback = function()
        -- ⚠️ 预留位置：把你分开做的功能B的 Raw 链接填到这里
        local url = "https://raw.githubusercontent.com/你的用户名/你的仓库/main/功能B.lua?v=1"
        
        if string.find(url, "你的用户名") then
            return game:GetService("StarterGui"):SetCore("SendNotification", {Title="提示", Text="功能B链接尚未配置", Duration=3})
        end

        task.spawn(function()
            pcall(function()
                loadstring(game:HttpGet(url))()
            end)
        end)
    end
})

-- ==========================================
-- 模块 2：开关形式加载
-- ==========================================
MainTab:Toggle({
    Title = "自动执行功能 C",
    Desc = "开启时加载功能C，关闭时停止",
    Default = false,
    Callback = function(state)
        if state then
            -- ⚠️ 开启时的操作：加载功能C
            local url = "https://raw.githubusercontent.com/你的用户名/你的仓库/main/功能C.lua?v=1"
            
            if not string.find(url, "你的用户名") then
                task.spawn(function()
                    pcall(function()
                        loadstring(game:HttpGet(url))()
                    end)
                end)
            else
                WindUI:Notify({Title="提示", Content="功能C链接尚未配置", Duration=3})
            end
        else
            -- ⚠️ 关闭时的操作：如果是循环类功能，你需要在这里写停止逻辑，或者直接重载一个清理脚本
            -- 例如: loadstring(game:HttpGet("关闭清理C的链接"))()
            print("功能C 已关闭")
        end
    end
})

-- ==========================================
-- 设置页：重载 UI
-- ==========================================
SettingTab:Button({
    Title = "重载界面 (Reload)",
    Desc = "如果界面卡住可以点这里重载",
    Callback = function()
        -- 这里可以写重载当前入口脚本的逻辑
        -- loadstring(game:HttpGet("你的A.lua链接?v=新数字"))()
    end
})
