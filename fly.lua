--[[
	==============================================================
	  飞行模块 (瞬移版) · Havvk  v2.0
	  视觉风格：深色面板 / 彩虹细描边 / mac 圆点窗口按钮
	==============================================================
	  功能（与原版一致，未做任何改动）：
	    · 飞行开关（BodyVelocity 悬浮移动，WASD 控制方向）
	    · 穿墙开关（飞行中关闭角色碰撞）
	    · 垂直瞬移（上升 / 下降 25 米）
	    · 移动速度调节（10 ~ 200，步进 10）

	  交互：
	    · 拖拽标题栏或底部小白条移动窗口
	    · 右下角半透明三角拖拽缩放
	    · 右上角三个圆点（mac 风）：黄 = 最小化，绿 = 放大 / 还原，红 = 关闭
	    · 最小化后收缩成小胶囊，显示「飞行模块」而不是时间
	    · 窗口边框是一圈缓慢旋转的细彩虹线
	==============================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if playerGui:FindFirstChild("Havvk_FlyModule") then
	playerGui.Havvk_FlyModule:Destroy()
end

--=============================================================
-- 配置
--=============================================================
local CONFIG = {
	Width = 300,
	Height = 440,
	MinWidth = 272,
	MinHeight = 280,
	HeaderHeight = 52,
	BottomBarHeight = 16,
	MinimizedWidth = 156,
	MinimizedHeight = 30,
	CardHeight = 66,
	SpeedCardHeight = 76,
	TeleportHeight = 44,

	FlySpeed = 50,
	MinSpeed = 10,
	MaxSpeed = 200,
	SpeedStep = 10,
	TeleportDistance = 25,
}

local THEME = {
	Background = Color3.fromRGB(20, 22, 28),
	Header     = Color3.fromRGB(24, 27, 34),
	Card       = Color3.fromRGB(33, 37, 47),
	CardHover  = Color3.fromRGB(38, 43, 54),
	Stroke     = Color3.fromRGB(46, 52, 64),
	Text       = Color3.fromRGB(232, 236, 244),
	SubText    = Color3.fromRGB(138, 147, 164),
	Accent     = Color3.fromRGB(88, 132, 255),
	Green      = Color3.fromRGB(78, 201, 132),
	Yellow     = Color3.fromRGB(240, 190, 90),
	Red        = Color3.fromRGB(240, 96, 96),
	DotRed     = Color3.fromRGB(255, 95, 87),
	DotYellow  = Color3.fromRGB(254, 188, 46),
	DotGreen   = Color3.fromRGB(40, 200, 64),
}

--=============================================================
-- 工具
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

-- 细彩虹描边：UIGradient 挂在 UIStroke 上，靠旋转 Rotation 让颜色沿边框流动
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 96, 128)),
	ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 170, 96)),
	ColorSequenceKeypoint.new(0.32, Color3.fromRGB(246, 226, 116)),
	ColorSequenceKeypoint.new(0.48, Color3.fromRGB(112, 224, 152)),
	ColorSequenceKeypoint.new(0.64, Color3.fromRGB(96, 200, 255)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(150, 140, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 96, 128)),
})

local function rainbowStroke(parent, thickness)
	local s = new("UIStroke", {
		Color = Color3.fromRGB(255, 96, 128),
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
	local grad = new("UIGradient", {
		Color = RAINBOW,
		Rotation = 0,
		Parent = s,
	})
	return s, grad
end

--=============================================================
-- 根节点
--=============================================================
local gui = new("ScreenGui", {
	Name = "Havvk_FlyModule",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = playerGui,
})

local window = new("Frame", {
	Name = "Window",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
	Parent = gui,
})
corner(window, 12)
local rainbowLine, rainbowGrad = rainbowStroke(window, 1.2)

local uiScale = new("UIScale", { Scale = 1, Parent = window })

--=============================================================
-- 顶部标题栏（mac 风格圆点，置于右侧）
--=============================================================
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
	BackgroundColor3 = THEME.Header,
	BorderSizePixel = 0,
	Active = true,
	Parent = window,
})
corner(header, 12)
new("Frame", {
	Size = UDim2.new(1, -24, 0, 1),
	Position = UDim2.new(0, 12, 0, CONFIG.HeaderHeight - 1),
	BackgroundColor3 = THEME.Stroke,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = header,
})

local function makeDot(color, offsetX, glyph)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -offsetX, 0.5, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextSize = 9,
		TextColor3 = Color3.fromRGB(45, 45, 45),
		Parent = header,
	})
	corner(btn, 6)

	-- 悬停时像 macOS 一样浮现符号
	btn.MouseEnter:Connect(function()
		btn.Text = glyph
		btn.Size = UDim2.fromOffset(13, 13)
	end)
	btn.MouseLeave:Connect(function()
		btn.Text = ""
		btn.Size = UDim2.fromOffset(12, 12)
	end)
	return btn
end

-- 右对齐，视觉顺序（左→右）：最小化 · 放大 · 关闭
local closeDot = makeDot(THEME.DotRed, 14, "×")
local zoomDot = makeDot(THEME.DotGreen, 34, "+")
local minDot = makeDot(THEME.DotYellow, 54, "−")

local logo = new("Frame", {
	Size = UDim2.fromOffset(24, 24),
	Position = UDim2.fromOffset(14, 14),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Active = true,
	Parent = header,
})
corner(logo, 12)
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
	Text = "F",
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = logo,
})

local titleLabel = new("TextLabel", {
	Size = UDim2.new(0, 134, 0, 17),
	Position = UDim2.fromOffset(46, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "飞行模块",
	TextSize = 14,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

local subtitleLabel = new("TextLabel", {
	Size = UDim2.new(0, 134, 0, 13),
	Position = UDim2.fromOffset(46, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "待机 · 速度 50",
	TextSize = 10,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

--=============================================================
-- 最小化胶囊：只显示功能名称（不显示时间）
--=============================================================
local minimizedDot = new("Frame", {
	Size = UDim2.fromOffset(6, 6),
	Position = UDim2.fromOffset(14, 12),
	BackgroundColor3 = Color3.fromRGB(112, 121, 138),
	BorderSizePixel = 0,
	Visible = false,
	Parent = header,
})
corner(minimizedDot, 3)

local minimizedLabel = new("TextLabel", {
	Size = UDim2.new(1, -96, 1, 0),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "飞行模块",
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Visible = false,
	Active = true,
	Parent = header,
})

--=============================================================
-- 主体
--=============================================================
local body = new("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -(CONFIG.HeaderHeight + CONFIG.BottomBarHeight)),
	BackgroundTransparency = 1,
	Parent = window,
})

local scroll = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = body,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = scroll,
})

local list = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = scroll,
})
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = list,
})

local order = 0
local function nextOrder()
	order = order + 1
	return order
end

local function makeSection(text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = nextOrder(),
		Parent = list,
	})
end

--=============================================================
-- 开关（mac 风拨片）
--=============================================================
local function makeToggle(parent, state, onChange)
	local track = new("TextButton", {
		Size = UDim2.fromOffset(38, 21),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundColor3 = state and THEME.Accent or Color3.fromRGB(56, 62, 76),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	corner(track, 11)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(15, 15),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, state and 21 or 3, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(knob, 8)

	local value = state

	local function render(v, animate)
		local onColor = v and THEME.Accent or Color3.fromRGB(56, 62, 76)
		local knobPos = UDim2.new(0, v and 21 or 3, 0.5, 0)
		if animate then
			TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = onColor }):Play()
			TweenService:Create(knob, TweenInfo.new(0.15), { Position = knobPos }):Play()
		else
			track.BackgroundColor3 = onColor
			knob.Position = knobPos
		end
	end

	local api = { track = track }
	function api.get()
		return value
	end
	function api.set(v, silent)
		v = v and true or false
		if value == v then return end
		value = v
		render(v, true)
		if not silent and onChange then onChange(v) end
	end

	track.MouseButton1Click:Connect(function()
		value = not value
		render(value, true)
		if onChange then onChange(value) end
	end)

	render(value, false)
	return api
end

--=============================================================
-- 卡片
--=============================================================
local function makeCard(opts)
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, opts.height or CONFIG.CardHeight),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = list,
	})
	corner(card, 10)
	stroke(card, Color3.fromRGB(42, 47, 58), 1)

	local reserved = opts.reserved or 78
	new("TextLabel", {
		Size = UDim2.new(1, -reserved, 0, 16),
		Position = UDim2.fromOffset(14, 13),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.title,
		TextSize = 13,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local descLabel = new("TextLabel", {
		Size = UDim2.new(1, -reserved, 0, 30),
		Position = UDim2.fromOffset(14, 33),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = opts.desc or "",
		TextSize = 11,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = card,
	})
	descLabel.Visible = (opts.desc ~= nil)

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)

	local control = opts.control
	local toggleInstance
	if control and control.kind == "toggle" then
		toggleInstance = makeToggle(card, control.value or false, control.onChange)
	end

	return card, toggleInstance
end

--=============================================================
-- 状态（前向声明）
--=============================================================
local flying, noclipOn = false, false
local flySpeed = CONFIG.FlySpeed
local bv, renderConn

local updateStatus
local startFly, stopFly, setNoclipState
local flyToggle, noclipToggle
local speedValueLabel, speedFill

--=============================================================
-- 飞行控制区
--=============================================================
makeSection("飞行控制")

local flyCard, flyToggleInstance = makeCard({
	title = "飞行",
	desc = "悬浮移动，WASD 控制方向",
	control = {
		kind = "toggle",
		value = false,
		onChange = function(state)
			if state then
				if not startFly() then
					-- 没有角色时回弹开关，避免状态与实物不一致
					task.defer(function()
						if flyToggle then flyToggle.set(false, true) end
						updateStatus()
					end)
					return
				end
			else
				stopFly()
			end
			updateStatus()
		end,
	},
})
flyToggle = flyToggleInstance

local noclipCard, noclipToggleInstance = makeCard({
	title = "穿墙",
	desc = "关闭角色碰撞 · 飞行中生效",
	control = {
		kind = "toggle",
		value = false,
		onChange = function(state)
			noclipOn = state
			if flying then
				setNoclipState(state)
			elseif not state then
				setNoclipState(false)
			end
			updateStatus()
		end,
	},
})
noclipToggle = noclipToggleInstance

--=============================================================
-- 垂直瞬移
--=============================================================
makeSection("垂直瞬移")

local teleportRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, CONFIG.TeleportHeight),
	BackgroundTransparency = 1,
	LayoutOrder = nextOrder(),
	Parent = list,
})

local function makeActionButton(parent, opts)
	local btn = new("TextButton", {
		Size = opts.size,
		Position = opts.position,
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	corner(btn, 10)
	stroke(btn, Color3.fromRGB(42, 47, 58), 1)

	new("TextLabel", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(10, 13),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.glyph,
		TextSize = 15,
		TextColor3 = THEME.Accent,
		Parent = btn,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -72, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.title,
		TextSize = 12,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})
	new("TextLabel", {
		Size = UDim2.new(0, 40, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = opts.hint,
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = btn,
	})

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if opts.onClick then opts.onClick() end
	end)
	return btn
end

makeActionButton(teleportRow, {
	size = UDim2.new(0.5, -5, 1, 0),
	position = UDim2.fromOffset(0, 0),
	glyph = "↑",
	title = "上升",
	hint = "25m",
	onClick = function()
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = char.HumanoidRootPart.CFrame
				+ Vector3.new(0, CONFIG.TeleportDistance, 0)
		end
	end,
})

makeActionButton(teleportRow, {
	size = UDim2.new(0.5, -5, 1, 0),
	position = UDim2.new(0.5, 5, 0, 0),
	glyph = "↓",
	title = "下降",
	hint = "25m",
	onClick = function()
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = char.HumanoidRootPart.CFrame
				- Vector3.new(0, CONFIG.TeleportDistance, 0)
		end
	end,
})

--=============================================================
-- 速度
--=============================================================
local speedCard = new("Frame", {
	Size = UDim2.new(1, 0, 0, CONFIG.SpeedCardHeight),
	BackgroundColor3 = THEME.Card,
	BorderSizePixel = 0,
	LayoutOrder = nextOrder(),
	Parent = list,
})
corner(speedCard, 10)
stroke(speedCard, Color3.fromRGB(42, 47, 58), 1)

new("TextLabel", {
	Size = UDim2.new(1, -70, 0, 16),
	Position = UDim2.fromOffset(14, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "移动速度",
	TextSize = 13,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = speedCard,
})

new("TextLabel", {
	Size = UDim2.new(1, -70, 0, 12),
	Position = UDim2.fromOffset(14, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "范围 10 – 200，步进 10",
	TextSize = 10,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = speedCard,
})

speedValueLabel = new("TextLabel", {
	Size = UDim2.new(0, 56, 0, 16),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = tostring(CONFIG.FlySpeed),
	TextSize = 13,
	TextColor3 = THEME.Accent,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = speedCard,
})

local function makeStepButton(text, anchorRight)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(anchorRight and 1 or 0, 0),
		Position = anchorRight and UDim2.new(1, -14, 0, 40) or UDim2.fromOffset(14, 40),
		BackgroundColor3 = Color3.fromRGB(44, 49, 61),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 15,
		TextColor3 = THEME.Text,
		Parent = speedCard,
	})
	corner(btn, 8)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(54, 60, 74) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(44, 49, 61) }):Play()
	end)
	return btn
end

local minusBtn = makeStepButton("−", false)
local plusBtn = makeStepButton("+", true)

local barTrack = new("Frame", {
	Position = UDim2.new(0, 48, 0, 53),
	Size = UDim2.new(1, -96, 0, 6),
	BackgroundColor3 = Color3.fromRGB(44, 49, 61),
	BorderSizePixel = 0,
	Parent = speedCard,
})
corner(barTrack, 3)

speedFill = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Parent = barTrack,
})
corner(speedFill, 3)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 158, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 108, 255)),
	}),
	Rotation = 0,
	Parent = speedFill,
})

--=============================================================
-- 逻辑：穿墙 / 飞行
--=============================================================
function setNoclipState(state)
	local char = player.Character
	if not char then return end
	for _, v in pairs(char:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CanCollide = not state
		end
	end
	local humanoid = char:FindFirstChild("Humanoid")
	if humanoid then
		-- 开启飞行时强制悬浮，防止物理引擎卡住角色
		humanoid.PlatformStand = state
	end
end

function stopFly()
	flying = false
	if bv then
		bv:Destroy()
		bv = nil
	end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	setNoclipState(false)
end

function startFly()
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("Humanoid") then
		return false
	end

	flying = true
	local hrp = char.HumanoidRootPart

	-- 开启穿墙和悬浮
	setNoclipState(noclipOn)

	bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Velocity = Vector3.zero
	bv.Parent = hrp

	-- 使用 Heartbeat 处理稳定移动
	renderConn = RunService.Heartbeat:Connect(function()
		if not flying or not bv then return end
		local c = player.Character
		if not c or not c:FindFirstChild("Humanoid") then return end

		-- 飞行中开启穿墙时，实时确认碰撞已关闭
		if noclipOn then
			for _, v in pairs(c:GetDescendants()) do
				if v:IsA("BasePart") and v.CanCollide then
					v.CanCollide = false
				end
			end
		end

		local dir = c.Humanoid.MoveDirection
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		local horizontalVel = Vector3.zero
		if flatDir.Magnitude > 0.05 then
			horizontalVel = flatDir.Unit * flySpeed
		end
		bv.Velocity = horizontalVel
	end)

	return true
end

--=============================================================
-- 状态刷新
--=============================================================
function updateStatus()
	local stateText = flying and "飞行中" or "待机"
	subtitleLabel.Text = string.format("%s · 速度 %d", stateText, flySpeed)
	minimizedDot.BackgroundColor3 = flying and THEME.Green or Color3.fromRGB(112, 121, 138)
	speedValueLabel.Text = tostring(flySpeed)

	local ratio = (flySpeed - CONFIG.MinSpeed) / (CONFIG.MaxSpeed - CONFIG.MinSpeed)
	TweenService:Create(speedFill, TweenInfo.new(0.12), {
		Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0),
	}):Play()
end

local function setSpeed(delta)
	local nextSpeed = math.clamp(flySpeed + delta, CONFIG.MinSpeed, CONFIG.MaxSpeed)
	if nextSpeed == flySpeed then return end
	flySpeed = nextSpeed
	updateStatus()
end

minusBtn.MouseButton1Click:Connect(function()
	setSpeed(-CONFIG.SpeedStep)
end)

plusBtn.MouseButton1Click:Connect(function()
	setSpeed(CONFIG.SpeedStep)
end)

-- 死亡自动清理
player.CharacterAdded:Connect(function()
	if flying then
		stopFly()
	end
	noclipOn = false
	if flyToggle then flyToggle.set(false, true) end
	if noclipToggle then noclipToggle.set(false, true) end
	updateStatus()
end)

--=============================================================
-- 底部小白条（拖动窗口）
--=============================================================
local bottomBar = new("Frame", {
	Name = "BottomBar",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, CONFIG.BottomBarHeight),
	BackgroundTransparency = 1,
	Parent = window,
})

local dragHandle = new("TextButton", {
	Name = "DragHandle",
	Size = UDim2.fromOffset(96, CONFIG.BottomBarHeight),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Active = true,
	Parent = bottomBar,
})

local dragPill = new("Frame", {
	Size = UDim2.fromOffset(40, 4),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Parent = dragHandle,
})
corner(dragPill, 2)

dragHandle.MouseEnter:Connect(function()
	TweenService:Create(dragPill, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
end)
dragHandle.MouseLeave:Connect(function()
	TweenService:Create(dragPill, TweenInfo.new(0.12), { BackgroundTransparency = 0.35 }):Play()
end)

--=============================================================
-- 尺寸 / 适配
--=============================================================
local pos = Vector2.new(0, 0)
local winW, winH, winScale = CONFIG.Width, CONFIG.Height, 1
local minimized = false
local zoomed = false
local restoreW, restoreH = CONFIG.Width, CONFIG.Height

local function viewportSize()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function clampPos(p)
	local vp = viewportSize()
	local scale = uiScale.Scale
	local w, h = winW * scale, winH * scale
	local margin = 6
	return Vector2.new(
		math.clamp(p.X, margin, math.max(margin, vp.X - w - margin)),
		math.clamp(p.Y, margin, math.max(margin, vp.Y - h - margin))
	)
end

local function apply()
	window.Size = UDim2.fromOffset(winW, winH)
	window.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
end

local function updateScale()
	local vp = viewportSize()
	local base = math.clamp(math.min(
		1,
		(vp.Y - 32) / CONFIG.Height,
		(vp.X - 32) / CONFIG.Width
	), 0.6, 1)

	-- 放大后的上限：不能超出视口，也不超过 1.3 倍
	local maxAllowed = math.max(0.6, math.min(
		1.3,
		(vp.Y - 24) / CONFIG.Height,
		(vp.X - 24) / CONFIG.Width
	))

	winScale = base
	uiScale.Scale = math.clamp(base * (zoomed and 1.22 or 1), 0.6, maxAllowed)
end

local function relayout(center)
	if minimized then
		winW, winH = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	else
		winW, winH = restoreW, restoreH
	end

	updateScale()

	local vp = viewportSize()
	if center then
		pos = Vector2.new((vp.X - winW * uiScale.Scale) / 2, (vp.Y - winH * uiScale.Scale) / 2)
	end

	pos = clampPos(pos)
	apply()
end

--=============================================================
-- 拖动 / 缩放
--=============================================================
local dragState = nil
local resizeState = nil

-- 关键：InputObject.Position 是 Vector3，统一取 XY
local function inputXY(input)
	local p = input.Position
	return Vector2.new(p.X, p.Y)
end

local function bindDrag(object)
	object.Active = true
	object.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragState = { startInput = inputXY(input), origin = pos }
		resizeState = nil
	end)
end

-- 右下角缩放手柄：热区是透明的正方形按钮，视觉是旋转 45° 被裁出来的三角形
local GRIP_HIT = 26
local grip = new("TextButton", {
	Name = "Grip",
	Size = UDim2.fromOffset(GRIP_HIT, GRIP_HIT),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Parent = window,
})

local gripVisual = new("Frame", {
	Name = "GripVisual",
	Size = UDim2.fromOffset(30, 30),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, 0, 1, 0),
	Rotation = 45,
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 5,
	Parent = window,
})
grip.ZIndex = 6

grip.MouseEnter:Connect(function()
	TweenService:Create(gripVisual, TweenInfo.new(0.12), { BackgroundTransparency = 0.55 }):Play()
end)
grip.MouseLeave:Connect(function()
	TweenService:Create(gripVisual, TweenInfo.new(0.12), { BackgroundTransparency = 0.8 }):Play()
end)

grip.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if minimized then return end

	resizeState = { startInput = inputXY(input), w = winW, h = winH }
	dragState = nil
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if dragState then
		local delta = inputXY(input) - dragState.startInput
		pos = clampPos(dragState.origin + delta)
		apply()
	elseif resizeState then
		local vp = viewportSize()
		local scale = math.max(uiScale.Scale, 0.01)
		local delta = (inputXY(input) - resizeState.startInput) / scale
		local maxW = math.max(240, (vp.X - 12) / scale)
		local maxH = math.max(200, (vp.Y - 12) / scale)

		winW = math.clamp(resizeState.w + delta.X, math.min(CONFIG.MinWidth, maxW), maxW)
		winH = math.clamp(resizeState.h + delta.Y, math.min(CONFIG.MinHeight, maxH), maxH)
		winW = math.floor(winW)
		winH = math.floor(winH)
		restoreW, restoreH = winW, winH
		pos = clampPos(pos)
		apply()
	end
end)

-- 抬起手指 / 松开鼠标时统一收尾，避免状态卡住导致「拖一次以后再也拖不动」
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragState = nil
		resizeState = nil
	end
end)

bindDrag(header)
bindDrag(logo)
bindDrag(titleLabel)
bindDrag(subtitleLabel)
bindDrag(minimizedLabel)
bindDrag(dragHandle)

--=============================================================
-- 最小化 / 放大 / 关闭
--=============================================================
local function setMinimized(state)
	minimized = state

	logo.Visible = not state
	titleLabel.Visible = not state
	subtitleLabel.Visible = not state
	minimizedLabel.Visible = state
	minimizedDot.Visible = state
	body.Visible = not state
	bottomBar.Visible = not state
	grip.Visible = not state
	gripVisual.Visible = not state
	minDot.Visible = not state

	local headerH = state and CONFIG.MinimizedHeight or CONFIG.HeaderHeight
	TweenService:Create(header, TweenInfo.new(0.18), { Size = UDim2.new(1, 0, 0, headerH) }):Play()

	if state then
		winW, winH = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	else
		winW, winH = restoreW, restoreH
	end

	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(window, info, { Size = UDim2.fromOffset(winW, winH) }):Play()

	pos = clampPos(pos)
	TweenService:Create(window, info, { Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y)) }):Play()
end

closeDot.MouseButton1Click:Connect(function()
	stopFly()
	gui:Destroy()
end)

minDot.MouseButton1Click:Connect(function()
	if not minimized then
		setMinimized(true)
	end
end)

zoomDot.MouseButton1Click:Connect(function()
	-- 最小化时绿点负责还原，展开时负责放大 / 还原
	if minimized then
		setMinimized(false)
		return
	end
	zoomed = not zoomed
	updateScale()
	pos = clampPos(pos)
	apply()
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateScale()
		pos = clampPos(pos)
		apply()
	end)
end

--=============================================================
-- 每帧：彩虹描边缓慢旋转
--=============================================================
local rainbowConn
rainbowConn = RunService.RenderStepped:Connect(function(dt)
	if not window.Parent then
		rainbowConn:Disconnect()
		return
	end
	if rainbowGrad then
		rainbowGrad.Rotation = (rainbowGrad.Rotation + dt * 42) % 360
	end
end)

--=============================================================
-- 初始化
--=============================================================
updateStatus()
relayout(true)
