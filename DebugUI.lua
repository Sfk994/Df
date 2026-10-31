--[[
	==============================================================
	  DebugUI · Roblox 简易调试面板
	==============================================================
	  使用方法：
	    1. 在 StarterGui 里新建一个 LocalScript（放在任意位置也可以）
	    2. 把本文件内容整体粘贴进去
	    3. 运行游戏，面板出现在屏幕中央

	  快捷键：
	    F2 —— 显示 / 隐藏面板

	  对外接口：
	    _G.DebugUI:Log("消息内容", "info")     -- info / success / warn / error
	    _G.DebugUI:SetVisible(true / false)
	==============================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=============================================================
-- 配置区：改这里就能调整外观与文案
--=============================================================
local CONFIG = {
	Title = "调试面板",
	Subtitle = "Debug Console · v1.0",
	Width = 480,
	Height = 332,
	TitleBarHeight = 44,
	MaxLogLines = 80,
}

local THEME = {
	Background = Color3.fromRGB(20, 22, 28),
	TitleBar   = Color3.fromRGB(27, 30, 38),
	Card       = Color3.fromRGB(33, 37, 47),
	Stroke     = Color3.fromRGB(48, 54, 66),
	Text       = Color3.fromRGB(232, 236, 244),
	SubText    = Color3.fromRGB(138, 147, 164),
	Accent     = Color3.fromRGB(88, 132, 255),
	Green      = Color3.fromRGB(78, 201, 132),
	Yellow     = Color3.fromRGB(240, 190, 90),
	Red        = Color3.fromRGB(240, 96, 96),
}

local LEVEL_COLORS = {
	info    = Color3.fromRGB(196, 203, 217),
	success = THEME.Green,
	warn    = THEME.Yellow,
	error   = THEME.Red,
}

--=============================================================
-- 小工具
--=============================================================
local function new(className, props)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(parent, color, thickness)
	return new("UIStroke", {
		Color = color or THEME.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

--=============================================================
-- 根节点
--=============================================================
local old = playerGui:FindFirstChild("DebugUI")
if old then old:Destroy() end

local gui = new("ScreenGui", {
	Name = "DebugUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = playerGui,
})

--=============================================================
-- 主窗口
--=============================================================
local window = new("Frame", {
	Name = "Window",
	Position = UDim2.new(0.5, -CONFIG.Width / 2, 0.5, -CONFIG.Height / 2),
	Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = gui,
})
corner(window, 10)
stroke(window, THEME.Stroke, 1)

--=============================================================
-- 标题栏
--=============================================================
local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, CONFIG.TitleBarHeight),
	BackgroundColor3 = THEME.TitleBar,
	BorderSizePixel = 0,
	Parent = window,
})
corner(titleBar, 10)

-- 标题栏底部 1px 分割线（盖住下方圆角）
new("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 0, CONFIG.TitleBarHeight - 1),
	BackgroundColor3 = THEME.Stroke,
	BorderSizePixel = 0,
	Parent = titleBar,
})

-- 左上角图标
local logo = new("Frame", {
	Size = UDim2.fromOffset(20, 20),
	Position = UDim2.fromOffset(14, 12),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Parent = titleBar,
})
corner(logo, 6)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 158, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 108, 255)),
	}),
	Rotation = 45,
	Parent = logo,
})
new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "D",
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = logo,
})

-- 标题 / 副标题
local titleLabel = new("TextLabel", {
	Size = UDim2.new(1, -320, 0, 18),
	Position = UDim2.fromOffset(44, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = CONFIG.Title,
	TextSize = 14,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = titleBar,
})

local subtitleLabel = new("TextLabel", {
	Size = UDim2.new(1, -320, 0, 14),
	Position = UDim2.fromOffset(44, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = CONFIG.Subtitle,
	TextSize = 11,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = titleBar,
})

-- 窗口按钮（悬停变色）
local function makeWindowButton(text, anchorX, hoverColor)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, anchorX, 0.5, 0),
		BackgroundColor3 = hoverColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 15,
		TextColor3 = THEME.SubText,
		Parent = titleBar,
	})
	corner(btn, 6)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
		btn.TextColor3 = THEME.Text
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		btn.TextColor3 = THEME.SubText
	end)
	return btn
end

local minimizeBtn = makeWindowButton("−", -40, Color3.fromRGB(58, 64, 78))
local closeBtn = makeWindowButton("×", -10, Color3.fromRGB(186, 66, 66))

--=============================================================
-- 内容区
--=============================================================
local body = new("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, CONFIG.TitleBarHeight),
	Size = UDim2.new(1, 0, 1, -CONFIG.TitleBarHeight),
	BackgroundTransparency = 1,
	Parent = window,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = body,
})

---------------------------------------------------------------
-- 顶部数据卡片
---------------------------------------------------------------
local statsRow = new("Frame", {
	Name = "Stats",
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundTransparency = 1,
	Parent = body,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 9),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Parent = statsRow,
})

local function makeStatCard(title, order)
	local card = new("Frame", {
		Size = UDim2.new(1 / 3, -6, 1, 0),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = statsRow,
	})
	corner(card, 8)
	new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 12),
		Position = UDim2.fromOffset(10, 9),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = title,
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local value = new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 25),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "--",
		TextSize = 17,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	return value
end

local fpsValue = makeStatCard("FPS", 1)
local pingValue = makeStatCard("延迟", 2)
local memValue = makeStatCard("内存", 3)

---------------------------------------------------------------
-- 日志区
---------------------------------------------------------------
local logScroll = new("ScrollingFrame", {
	Name = "Log",
	Position = UDim2.fromOffset(0, 66),
	Size = UDim2.new(1, 0, 1, -108),
	BackgroundColor3 = Color3.fromRGB(15, 17, 22),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
	ScrollBarImageTransparency = 0,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = body,
})
corner(logScroll, 8)
stroke(logScroll, Color3.fromRGB(36, 41, 51), 1)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	Parent = logScroll,
})
new("UIListLayout", {
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = logScroll,
})

---------------------------------------------------------------
-- 底部工具栏
---------------------------------------------------------------
local footer = new("Frame", {
	Name = "Footer",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Parent = body,
})

new("TextLabel", {
	Size = UDim2.new(1, -190, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "F2 隐藏面板 · 按住标题栏拖动",
	TextSize = 11,
	TextColor3 = Color3.fromRGB(110, 118, 133),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = footer,
})

local function makeToolButton(text, width, anchorX)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(width, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, anchorX, 0.5, 0),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = 12,
		TextColor3 = THEME.Text,
		Parent = footer,
	})
	corner(btn, 6)
	stroke(btn, THEME.Stroke, 1)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(43, 48, 60) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)
	return btn
end

local autoScroll = true
local clearBtn = makeToolButton("清空日志", 68, 0)
local autoBtn = makeToolButton("自动滚动：开", 92, -76)

autoBtn.TextColor3 = THEME.Green
autoBtn.MouseButton1Click:Connect(function()
	autoScroll = not autoScroll
	autoBtn.Text = autoScroll and "自动滚动：开" or "自动滚动：关"
	autoBtn.TextColor3 = autoScroll and THEME.Green or THEME.SubText
end)

--=============================================================
-- 日志逻辑
--=============================================================
local logLines = {}

local function log(message, level)
	level = level or "info"
	local color = LEVEL_COLORS[level] or LEVEL_COLORS.info

	local line = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(message)),
		Parent = logScroll,
	})

	table.insert(logLines, line)
	while #logLines > CONFIG.MaxLogLines do
		local removed = table.remove(logLines, 1)
		if removed then removed:Destroy() end
	end

	if autoScroll then
		task.defer(function()
			if logScroll.Parent then
				local maxY = logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteWindowSize.Y
				logScroll.CanvasPosition = Vector2.new(0, math.max(0, maxY))
			end
		end)
	end
end

clearBtn.MouseButton1Click:Connect(function()
	for _, line in ipairs(logLines) do
		line:Destroy()
	end
	logLines = {}
	log("日志已清空", "warn")
end)

--=============================================================
-- 拖动
--=============================================================
local function screenSize()
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if ok and size and size.X > 0 and size.Y > 0 then
		return size
	end
	return workspace.CurrentCamera.ViewportSize
end

local dragState = nil

local function bindDrag(object)
	object.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local ok, guiPos = pcall(function()
			return gui.AbsolutePosition
		end)
		dragState = {
			startInput = input.Position,
			startPos = window.AbsolutePosition - (ok and guiPos or Vector2.new(0, 0)),
		}

		local changedConn
		changedConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragState = nil
				changedConn:Disconnect()
			end
		end)
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if not dragState then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local delta = input.Position - dragState.startInput
	local size = window.AbsoluteSize
	local screen = screenSize()

	local x = math.clamp(dragState.startPos.X + delta.X, 0, math.max(0, screen.X - size.X))
	local y = math.clamp(dragState.startPos.Y + delta.Y, 0, math.max(0, screen.Y - size.Y))
	window.Position = UDim2.fromOffset(x, y)
end)

bindDrag(titleBar)
bindDrag(logo)
bindDrag(titleLabel)
bindDrag(subtitleLabel)

--=============================================================
-- 最小化
--=============================================================
local minimized = false

local function setMinimized(state)
	minimized = state
	body.Visible = not state
	minimizeBtn.Text = state and "+" or "−"

	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(window, info, {
		Size = UDim2.fromOffset(window.AbsoluteSize.X, state and CONFIG.TitleBarHeight or CONFIG.Height),
	}):Play()
end

minimizeBtn.MouseButton1Click:Connect(function()
	setMinimized(not minimized)
end)

--=============================================================
-- 关闭 / 重新打开
--=============================================================
local pill = new("TextButton", {
	Name = "Reopen",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(112, 32),
	BackgroundColor3 = THEME.TitleBar,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamMedium,
	Text = "调试面板 (F2)",
	TextSize = 12,
	TextColor3 = THEME.Text,
	Visible = false,
	Parent = gui,
})
corner(pill, 8)
stroke(pill, THEME.Stroke, 1)

local function setVisible(state)
	window.Visible = state
	pill.Visible = not state
end

closeBtn.MouseButton1Click:Connect(function()
	setVisible(false)
	print("[DebugUI] 面板已关闭，按 F2 可重新打开")
end)

pill.MouseButton1Click:Connect(function()
	setVisible(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F2 then
		setVisible(not window.Visible)
	end
end)

--=============================================================
-- 实时数据
--=============================================================
local frames, elapsed = 0, 0

RunService.RenderStepped:Connect(function(dt)
	frames += 1
	elapsed += dt
	if elapsed < 0.5 then return end

	local fps = math.floor(frames / elapsed + 0.5)
	fpsValue.Text = tostring(fps)
	fpsValue.TextColor3 = fps >= 50 and THEME.Green or (fps >= 30 and THEME.Yellow or THEME.Red)

	local okPing, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if okPing and typeof(ping) == "number" then
		pingValue.Text = string.format("%d ms", math.floor(ping * 1000 + 0.5))
	else
		pingValue.Text = "N/A"
	end

	memValue.Text = string.format("%.0f MB", gcinfo() / 1024)

	frames, elapsed = 0, 0
end)

--=============================================================
-- 对外接口
--=============================================================
local API = {}

function API:Log(message, level)
	log(message, level)
end

function API:SetVisible(state)
	setVisible(state and true or false)
end

API.Theme = THEME
API.Window = window

_G.DebugUI = API

--=============================================================
-- 启动演示日志
--=============================================================
log("调试面板已启动", "success")
log("拖动标题栏可移动窗口，右上角可最小化 / 关闭", "info")
task.delay(1, function()
	log("F2 可快速隐藏 / 显示面板", "info")
end)
