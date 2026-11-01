--[[
	====================================================================
	环形零件面板 · Super Ring Parts — DebugUI 版
	====================================================================
	原脚本：Super Ring Parts V6 by lukas（英文原版）
	本版本：翻译为中文 + 升级为深色圆角调试面板（DebugUI）风格

	功能一览
	────────
	1. 龙卷风 / 环形零件：把场景里的散落零件卷起来、绕着你旋转
	   · 半径 / 高度 / 旋转速度 / 吸引力强度，四项均可实时调节
	2. 工具箱（7 个快捷按钮）
	   · 飞行 · 无摔落伤害 · 穿墙 · 无限跳跃
	   · 无限 Yield · Nameless 管理 · FPS
	3. 配置自动保存到本地（需要 Executor 环境）
	4. 面板可拖动、可最小化、可关闭

	运行环境
	────────
	· 飞行 / 无限 Yield / Nameless / FPS 依赖 loadstring + game:HttpGet，
	  需要 Executor（如 Synapse / Krnl / Fluxus 等）才能生效；
	· 配置保存依赖 writefile / readfile，普通环境会自动跳过；
	· 龙卷风、无摔落伤害、穿墙、无限跳跃在客户端即可运行。
	====================================================================
]]

--=============================================================
-- 服务
--=============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--=============================================================
-- 配色（深色调试面板风格）
--=============================================================
local C = {
	BG = Color3.fromRGB(24, 26, 33),      -- 面板背景
	BG2 = Color3.fromRGB(34, 37, 47),     -- 次级背景（输入框 / 按钮）
	CARD = Color3.fromRGB(42, 45, 56),    -- 卡片
	LINE = Color3.fromRGB(54, 58, 72),    -- 描边
	ACCENT = Color3.fromRGB(79, 140, 255),-- 主色（蓝）
	GREEN = Color3.fromRGB(63, 191, 130), -- 成功（绿）
	RED = Color3.fromRGB(224, 92, 92),    -- 危险（红）
	YELLOW = Color3.fromRGB(240, 185, 60),-- 提示（黄）
	TEXT = Color3.fromRGB(232, 234, 240), -- 主文字
	SUB = Color3.fromRGB(138, 144, 163),  -- 次级文字
}

--=============================================================
-- 声音
--=============================================================
local function playSound(soundId)
	pcall(function()
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. tostring(soundId)
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end)
end

-- 启动音效
playSound(2865227271)

--=============================================================
-- 配置（保存 / 加载）
--   writefile / readfile / isfile 是 Executor 提供的全局函数，
--   普通 Luau 环境没有，这里统一用 pcall 包裹，缺了就静默跳过。
--=============================================================
local config = {
	radius = 50,              -- 半径
	height = 100,             -- 高度
	rotationSpeed = 10,       -- 旋转速度
	attractionStrength = 1000,-- 吸引力强度
}

local function saveConfig()
	pcall(function()
		local str = HttpService:JSONEncode(config)
		writefile("SuperRingPartsConfig.txt", str)
	end)
end

local function loadConfig()
	pcall(function()
		if isfile("SuperRingPartsConfig.txt") then
			local str = readfile("SuperRingPartsConfig.txt")
			local loaded = HttpService:JSONDecode(str)
			if type(loaded) == "table" then
				for k, v in pairs(loaded) do
					if config[k] ~= nil and type(v) == "number" then
						config[k] = v
					end
				end
			end
		end
	end)
end

loadConfig()

--=============================================================
-- 环形零件核心逻辑（龙卷风）
--   · 收集场景里所有「可被卷入」的零件（不锚定、不属于自己、非角色部件）
--   · 每帧以自己为圆心，按配置把零件绕圈 + 吸向目标位置
--=============================================================
local ringEnabled = false -- 龙卷风开关

-- 判断一个零件是否该被卷入
local function retainPart(part)
	if not (part:IsA("BasePart") and not part.Anchored and part:IsDescendantOf(Workspace)) then
		return false
	end
	-- 跳过自己角色身上的部件
	if part.Parent == LocalPlayer.Character or part:IsDescendantOf(LocalPlayer.Character) then
		return false
	end
	-- 去掉碰撞与物理属性，方便被拽着走
	pcall(function()
		part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
		part.CanCollide = false
	end)
	return true
end

-- 收集到的零件表
local parts = {}

local function addPart(part)
	if retainPart(part) then
		local found = false
		for _, p in ipairs(parts) do
			if p == part then found = true break end
		end
		if not found then
			table.insert(parts, part)
		end
	end
end

local function removePart(part)
	for i, p in ipairs(parts) do
		if p == part then
			table.remove(parts, i)
			break
		end
	end
end

-- 初次扫描 + 监听新增 / 移除
for _, part in ipairs(Workspace:GetDescendants()) do
	addPart(part)
end
Workspace.DescendantAdded:Connect(addPart)
Workspace.DescendantRemoving:Connect(removePart)

-- 龙卷风主循环
RunService.Heartbeat:Connect(function()
	if not ringEnabled then return end

	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local center = root.Position
	for _, part in ipairs(parts) do
		if part.Parent and not part.Anchored then
			local pos = part.Position
			-- 只算水平距离（高度单独处理）
			local distance = (Vector3.new(pos.X, center.Y, pos.Z) - center).Magnitude
			local angle = math.atan2(pos.Z - center.Z, pos.X - center.X)
			local newAngle = angle + math.rad(config.rotationSpeed)

			local targetPos = Vector3.new(
				center.X + math.cos(newAngle) * math.min(config.radius, distance),
				center.Y + (config.height * math.abs(math.sin((pos.Y - center.Y) / config.height))),
				center.Z + math.sin(newAngle) * math.min(config.radius, distance)
			)

			local directionToTarget = (targetPos - part.Position).unit
			part.Velocity = directionToTarget * config.attractionStrength
		end
	end
end)

--=============================================================
-- Executor 专用：防止被卷零件被服务器网络同步回收
--   getgenv / sethiddenproperty 仅 Executor 环境存在，pcall 保护
--=============================================================
pcall(function()
	if not getgenv().Network then
		getgenv().Network = {
			BaseParts = {},
			Velocity = Vector3.new(14.46262424, 14.46262424, 14.46262424),
		}
	end

	local Network = getgenv().Network
	Network.RetainPart = function(part)
		if typeof(part) == "Instance" and part:IsA("BasePart") and part:IsDescendantOf(Workspace) then
			table.insert(Network.BaseParts, part)
			part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
			part.CanCollide = false
		end
	end

	LocalPlayer.ReplicationFocus = Workspace
	RunService.Heartbeat:Connect(function()
		sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
		for _, part in ipairs(Network.BaseParts) do
			if part:IsDescendantOf(Workspace) then
				part.Velocity = Network.Velocity
			end
		end
	end)
end)

--=============================================================
-- UI 构建（深色圆角 DebugUI 风格）
--=============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "RingPartsDebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- 面板
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(320, 520)
panel.Position = UDim2.new(0.5, -160, 0.5, -260)
panel.BackgroundColor3 = C.BG
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 16)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = C.LINE
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- 标题栏（也是拖动手柄）
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 46)
titleBar.Position = UDim2.fromOffset(0, 0)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -120, 0, 24)
title.Position = UDim2.fromOffset(16, 12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "环形零件面板"
title.TextSize = 16
title.TextColor3 = C.TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -120, 0, 14)
subtitle.Position = UDim2.fromOffset(16, 34)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "SUPER RING PARTS · V6"
subtitle.TextSize = 9
subtitle.TextColor3 = C.SUB
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = titleBar

-- 最小化按钮
local minBtn = Instance.new("TextButton")
minBtn.Name = "Minimize"
minBtn.Size = UDim2.fromOffset(30, 30)
minBtn.Position = UDim2.fromOffset(320 - 78, 8)
minBtn.BackgroundColor3 = C.BG2
minBtn.BorderSizePixel = 0
minBtn.Font = Enum.Font.GothamBold
minBtn.Text = "—"
minBtn.TextSize = 15
minBtn.TextColor3 = C.TEXT
minBtn.AutoButtonColor = false
minBtn.Parent = titleBar

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 8)
minCorner.Parent = minBtn

-- 关闭按钮
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.fromOffset(320 - 42, 8)
closeBtn.BackgroundColor3 = C.BG2
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Text = "×"
closeBtn.TextSize = 16
closeBtn.TextColor3 = C.RED
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

-- 分隔线
local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -32, 0, 1)
divider.Position = UDim2.fromOffset(16, 47)
divider.BackgroundColor3 = C.LINE
divider.BorderSizePixel = 0
divider.Parent = panel

-- 龙卷风开关
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.Size = UDim2.new(1, -32, 0, 46)
toggleBtn.Position = UDim2.fromOffset(16, 56)
toggleBtn.BackgroundColor3 = C.GREEN
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Text = "开启龙卷风"
toggleBtn.TextSize = 14
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = panel

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 12)
toggleCorner.Parent = toggleBtn

toggleBtn.MouseButton1Click:Connect(function()
	ringEnabled = not ringEnabled
	toggleBtn.Text = ringEnabled and "关闭龙卷风" or "开启龙卷风"
	toggleBtn.BackgroundColor3 = ringEnabled and C.RED or C.GREEN
	playSound(12221967)
end)

-- 参数区标题
local paramTitle = Instance.new("TextLabel")
paramTitle.Size = UDim2.new(1, -32, 0, 18)
paramTitle.Position = UDim2.fromOffset(16, 110)
paramTitle.BackgroundTransparency = 1
paramTitle.Font = Enum.Font.GothamBold
paramTitle.Text = "参数调节"
paramTitle.TextSize = 11
paramTitle.TextColor3 = C.SUB
paramTitle.TextXAlignment = Enum.TextXAlignment.Left
paramTitle.Parent = panel

-- 生成一个参数行：标签 + [−] 数值输入框 [+]
local function makeControl(y, name, key)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -32, 0, 46)
	row.Position = UDim2.fromOffset(16, y)
	row.BackgroundColor3 = C.CARD
	row.BorderSizePixel = 0
	row.Parent = panel

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	-- 标签
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 120, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = name
	label.TextSize = 13
	label.TextColor3 = C.TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	-- 减号
	local dec = Instance.new("TextButton")
	dec.Size = UDim2.fromOffset(30, 30)
	dec.Position = UDim2.fromOffset(158, 8)
	dec.BackgroundColor3 = C.BG2
	dec.BorderSizePixel = 0
	dec.Font = Enum.Font.GothamBold
	dec.Text = "−"
	dec.TextSize = 18
	dec.TextColor3 = C.TEXT
	dec.AutoButtonColor = false
	dec.Parent = row
	local decCorner = Instance.new("UICorner")
	decCorner.CornerRadius = UDim.new(0, 8)
	decCorner.Parent = dec

	-- 数值输入框（显示当前值，点击可直接编辑）
	local value = Instance.new("TextBox")
	value.Size = UDim2.fromOffset(52, 30)
	value.Position = UDim2.fromOffset(194, 8)
	value.BackgroundColor3 = C.BG2
	value.BorderSizePixel = 0
	value.Font = Enum.Font.GothamBold
	value.Text = tostring(config[key])
	value.PlaceholderText = "输入" .. name
	value.TextSize = 13
	value.TextColor3 = C.ACCENT
	value.Parent = row
	local valueCorner = Instance.new("UICorner")
	valueCorner.CornerRadius = UDim.new(0, 8)
	valueCorner.Parent = value

	-- 加号
	local inc = Instance.new("TextButton")
	inc.Size = UDim2.fromOffset(30, 30)
	inc.Position = UDim2.fromOffset(250, 8)
	inc.BackgroundColor3 = C.BG2
	inc.BorderSizePixel = 0
	inc.Font = Enum.Font.GothamBold
	inc.Text = "+"
	inc.TextSize = 18
	inc.TextColor3 = C.TEXT
	inc.AutoButtonColor = false
	inc.Parent = row
	local incCorner = Instance.new("UICorner")
	incCorner.CornerRadius = UDim.new(0, 8)
	incCorner.Parent = inc

	-- 应用一个数值：更新 config + 显示 + 保存
	local function apply(newValue)
		newValue = math.clamp(math.floor(newValue + 0.5), 0, 10000)
		config[key] = newValue
		value.Text = tostring(newValue)
		saveConfig()
	end

	-- 步进：按当前数值的 10% 或最小 1 步进
	local function step(dir)
		local cur = tonumber(value.Text) or config[key]
		local delta = math.max(1, math.floor(cur * 0.1 + 0.5))
		apply(cur + dir * delta)
	end

	dec.MouseButton1Click:Connect(function()
		step(-1)
		playSound(12221967)
	end)
	inc.MouseButton1Click:Connect(function()
		step(1)
		playSound(12221967)
	end)

	value.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local newValue = tonumber(value.Text)
			if newValue then
				apply(newValue)
				playSound(12221967)
			else
				value.Text = tostring(config[key])
			end
		end
	end)

	return value
end

local radiusValue = makeControl(134, "半径", "radius")
local heightValue = makeControl(186, "高度", "height")
local rotationValue = makeControl(238, "旋转速度", "rotationSpeed")
local attractionValue = makeControl(290, "吸引力强度", "attractionStrength")

-- 工具箱标题
local toolTitle = Instance.new("TextLabel")
toolTitle.Size = UDim2.new(1, -32, 0, 18)
toolTitle.Position = UDim2.fromOffset(16, 344)
toolTitle.BackgroundTransparency = 1
toolTitle.Font = Enum.Font.GothamBold
toolTitle.Text = "工具箱"
toolTitle.TextSize = 11
toolTitle.TextColor3 = C.SUB
toolTitle.TextXAlignment = Enum.TextXAlignment.Left
toolTitle.Parent = panel

-- 工具箱按钮网格（3 列）
local toolGrid = Instance.new("UIGridLayout")
toolGrid.CellSize = UDim2.fromOffset(88, 40)
toolGrid.CellPadding = UDim2.fromOffset(8, 8)
toolGrid.SortOrder = Enum.SortOrder.LayoutOrder
toolGrid.Parent = panel

local function makeToolButton(text, color, layoutOrder, onClick)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(88, 40)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = text
	btn.TextSize = 11
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.AutoButtonColor = false
	btn.LayoutOrder = layoutOrder
	btn.Parent = panel
	btn.Position = UDim2.fromOffset(16, 372) -- 网格布局会接管位置，这里只给一个初始锚点

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		playSound(12221967)
		onClick()
	end)
	return btn
end

--=============================================================
-- 工具箱功能实现
--=============================================================

-- 1. 飞行（loadstring 远程脚本）
makeToolButton("飞行", C.ACCENT, 1, function()
	pcall(function()
		loadstring(game:HttpGet("https://pastebin.com/raw/YSL3xKYU"))()
	end)
end)

-- 2. 无摔落伤害（内联实现）
makeToolButton("无摔落伤害", C.RED, 2, function()
	local char = LocalPlayer.Character
	if not char then return end

	local root = char:WaitForChild("HumanoidRootPart")
	if not root then return end

	local zero = Vector3.zero
	local heartbeat = RunService.Heartbeat
	local renderStepped = RunService.RenderStepped

	local con
	con = heartbeat:Connect(function()
		if not root.Parent then
			con:Disconnect()
			return
		end
		-- 每帧先把速度归零，渲染完再恢复，抵消摔落伤害
		local oldVel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = zero
		renderStepped:Wait()
		root.AssemblyLinearVelocity = oldVel
	end)
end)

-- 3. 穿墙（切换式）
local noclipEnabled = false
local noclipCon = nil
makeToolButton("穿墙", C.YELLOW, 3, function()
	noclipEnabled = not noclipEnabled
	if noclipEnabled then
		noclipCon = RunService.Stepped:Connect(function()
			local char = LocalPlayer.Character
			if not char then return end
			for _, v in ipairs(char:GetDescendants()) do
				if v:IsA("BasePart") and v.CanCollide then
					v.CanCollide = false
				end
			end
		end)
	else
		if noclipCon then
			noclipCon:Disconnect()
			noclipCon = nil
		end
	end
end)

-- 4. 无限跳跃（切换式）
local infJumpEnabled = false
UserInputService.JumpRequest:Connect(function()
	if not infJumpEnabled then return end
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)
makeToolButton("无限跳跃", C.GREEN, 4, function()
	infJumpEnabled = not infJumpEnabled
end)

-- 5. 无限 Yield（loadstring 远程脚本）
makeToolButton("无限 Yield", C.ACCENT, 5, function()
	pcall(function()
		loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
	end)
end)

-- 6. Nameless 管理（loadstring 远程脚本）
makeToolButton("Nameless", C.RED, 6, function()
	pcall(function()
		loadstring(game:HttpGet("https://scriptblox.com/raw/Universal-Script-Nameless-Admin-FE-11243"))()
	end)
end)

-- 7. FPS（loadstring 远程脚本）
makeToolButton("FPS", C.YELLOW, 7, function()
	pcall(function()
		loadstring(game:HttpGet("https://pastebin.com/raw/ySHJdZpb", true))()
	end)
end)

--=============================================================
-- 最小化 / 关闭 / 拖动
--=============================================================
local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		panel:TweenSize(UDim2.fromOffset(320, 46), "Out", "Quad", 0.3, true)
		minBtn.Text = "+"
		for _, child in ipairs(panel:GetChildren()) do
			if child:IsA("GuiObject") and child ~= titleBar and child ~= divider then
				child.Visible = false
			end
		end
	else
		panel:TweenSize(UDim2.fromOffset(320, 520), "Out", "Quad", 0.3, true)
		minBtn.Text = "—"
		for _, child in ipairs(panel:GetChildren()) do
			if child:IsA("GuiObject") then
				child.Visible = true
			end
		end
	end
	playSound(12221967)
end)

closeBtn.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

-- 拖动（只拖标题栏）
local dragging = false
local dragStart = nil
local startPos = nil

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

--=============================================================
-- 通知（头像获取失败时静默跳过）
--=============================================================
pcall(function()
	local userId = Players:GetUserIdFromNameAsync("Robloxlukasgames")
	local content = Players:GetUserThumbnailAsync(
		userId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size420x420
	)

	StarterGui:SetCore("SendNotification", {
		Title = "环形零件面板",
		Text = "祝你玩得开心！",
		Icon = content,
		Duration = 5,
	})
	StarterGui:SetCore("SendNotification", {
		Title = "小提示",
		Text = "点击数值框可直接输入任意参数",
		Icon = content,
		Duration = 5,
	})
	StarterGui:SetCore("SendNotification", {
		Title = "致谢",
		Text = "原脚本 Super Ring Parts V6 by lukas",
		Icon = content,
		Duration = 5,
	})
end)

--=============================================================
-- 结束
--=============================================================
