loadstring(game:HttpGet("https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/C.lua"))()
-- 获取当前时间
local currentTime = os.date("%Y-%m-%d %H:%M:%S")

-- 发送系统通知
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "系统提示";
    Text = "加载成功！\n当前时间: " .. currentTime;
    Duration = 5; -- 弹窗停留时间（秒），5秒后自动消失
    Icon = "rbxassetid://6023426926" -- 可选：加个小图标（这是 Roblox 官方的信息图标）
})
