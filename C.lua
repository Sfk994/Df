game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "加载成功";
    Text = "你成功穿过了 A1 -> B -> C 三层跳板，且链接永久有效！";
})

local currentTime = os.date("%Y-%m-%d %H:%M:%S")

game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "系统提示";
    Text = "加载成功！\n当前时间: " .. currentTime;
    Duration = 5; -- 弹窗停留时间（秒），5秒后自动消失
    Icon = "rbxassetid://6023426926" -- 可选：加个小图标（这是 Roblox 官方的信息图标）
})
