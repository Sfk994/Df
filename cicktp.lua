--[[
	==============================================================
	  传送模块 (点击传送 + 上帝视角) · Havvk  v1.0
	  视觉风格与「飞行模块」保持一致
	==============================================================
	  功能：
	    · 点击传送（原脚本行为完整保留）
	        - 开启后点击地图任意位置即可传送
	        - 落点自动抬高 3 格，避免卡进地面
	        - 乘坐载具时传送载具本体，并保持原朝向
	        - 0.5 秒冷却，防止连点
	    · 上帝视角（新增）
	        - 相机升到高空垂直俯视，屏幕中心即落点
	        - 拖拽屏幕平移视野（内容跟随手指）
	        - 左下角虚拟摇杆：推杆持续移动落点，适配触摸屏
	        - 摇杆右侧「快 / 慢」按钮：调摇杆移速 0.4×–3.0×，可长按连发
	        - 滚轮 / 双指捏合 / 面板按钮调整高度
	        - 地面光环 + 屏幕十字准星提示精确落点
	        - 底部独立「传送到此」按钮确认，无落点时自动禁用

	  交互：
	    · 拖拽标题栏或底部小白条移动窗口
	    · 右上角圆点：绿 = 最小化 / 还原（同一个点），红 = 关闭
	    · 最小化后收缩成小胶囊，显示「传送模块」而不是时间
	    · 窗口边框是一圈缓慢旋转的细彩虹线
	    · 不提供界面缩放，窗口大小固定，小屏自动整体适配
	==============================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if playerGui:FindFirstChild("Havvk_TeleportModule") then
	playerGui.Havvk_TeleportModule:Destroy()
end

--=============================================================
-- 配置
--=============================================================
local CONFIG = {
	Width = 264,
	Height = 272,
	PadRight = 20,
	HeaderHeight = 48,
	BottomBarHeight = 14,
	MinimizedWidth = 148,
	MinimizedHeight = 28,

	PadX = 16,
	PadY = 12,
	Gap = 7,
	SectionHeight = 13,
	CardHeight = 50,
	RowHeight = 32,

	LandOffset = 3,
	Cooldown = 0.5,
}

local GOD = {
	Height = 260,
	MinHeight = 120,
	MaxHeight = 640,
	HeightStep = 60,
	PanLimit = 4096,
	RayTop = 4000,
	RayBottom = 2000,
	JoySpeed = 1.15,   -- 摇杆满推时每秒移动的高度倍数（基准）
	JoyMin = 0.4,      -- 摇杆速度倍率下限
	JoyMax = 3.0,      -- 上限
	JoyStep = 0.2,     -- 每次点击的步进
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
	Name = "Havvk_TeleportModule",
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
	ZIndex = 10,
	Parent = gui,
})
corner(window, 12)
local _, rainbowGrad = rainbowStroke(window, 1.2)

local uiScale = new("UIScale", { Scale = 1, Parent = window })

--=============================================================
-- 尺寸 / 适配（先定义，后面逻辑要用）
--=============================================================
local pos = Vector2.new(0, 0)
local winW, winH = CONFIG.Width, CONFIG.Height
local minimized = false
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

-- 只做「小屏整体适配」，不提供放大 / 缩放功能
local function updateScale()
	local vp = viewportSize()
	local fit = math.min(
		(vp.Y - 32) / CONFIG.Height,
		(vp.X - 32) / CONFIG.Width
	)
	uiScale.Scale = math.clamp(math.min(1, fit), 0.6, 1)
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
-- 状态（前向声明）
--=============================================================
local clickTP, godActive = false, false
local godHeight = GOD.Height
local tpCooldown = false
local godTarget, godValid = nil, false
local clickToggle, godToggle
local godHint, godCardDesc
local updateStatus, setGodMode, setGodHeight, setMinimized, resetJoy
local godCoordLabel, godInfoLabel, godStateLabel, tpBtn

--=============================================================
-- 顶部标题栏
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

local dotGlyphs = {}

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

	dotGlyphs[btn] = glyph

	btn.MouseEnter:Connect(function()
		btn.Text = dotGlyphs[btn] or glyph
		btn.Size = UDim2.fromOffset(13, 13)
	end)
	btn.MouseLeave:Connect(function()
		btn.Text = ""
		btn.Size = UDim2.fromOffset(12, 12)
	end)
	return btn
end

local closeDot = makeDot(THEME.DotRed, 16, "×")
-- 绿点：展开时 = 最小化，最小化时 = 还原（同一个按钮，不再有放大 / 缩放）
local minDot = makeDot(THEME.DotGreen, 35, "−")

local logo = new("Frame", {
	Size = UDim2.fromOffset(22, 22),
	Position = UDim2.fromOffset(16, 13),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Active = true,
	Parent = header,
})
corner(logo, 11)
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
	Text = "T",
	TextSize = 11,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = logo,
})

local titleLabel = new("TextLabel", {
	Size = UDim2.new(0, 110, 0, 16),
	Position = UDim2.fromOffset(46, 9),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "传送模块",
	TextSize = 13,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

local subtitleLabel = new("TextLabel", {
	Size = UDim2.new(0, 116, 0, 12),
	Position = UDim2.fromOffset(46, 25),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "待机 · 点击传送 关",
	TextSize = 10,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

--=============================================================
-- 最小化胶囊：只显示功能名称
--=============================================================
local minimizedDot = new("Frame", {
	Size = UDim2.fromOffset(6, 6),
	Position = UDim2.fromOffset(16, 11),
	BackgroundColor3 = Color3.fromRGB(112, 121, 138),
	BorderSizePixel = 0,
	Visible = false,
	Parent = header,
})
corner(minimizedDot, 3)

local minimizedLabel = new("TextLabel", {
	Size = UDim2.new(1, -84, 1, 0),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "传送模块",
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
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = body,
})
-- 注意：ScrollingFrame 的 UIPadding 只会偏移、不会缩窄子项宽度，
-- 会让卡片右侧溢出被裁切，所以这里改成显式宽度
local list = new("Frame", {
	Size = UDim2.fromOffset(
		CONFIG.Width - CONFIG.PadX - CONFIG.PadRight,
		0
	),
	Position = UDim2.fromOffset(CONFIG.PadX, CONFIG.PadY),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = scroll,
})
new("UIListLayout", {
	Padding = UDim.new(0, CONFIG.Gap),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = list,
})

local order = 0
local function nextOrder()
	order = order + 1
	return order
end

local function makeSection(text, hint)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, CONFIG.SectionHeight),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = list,
	})
	new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local hintLabel
	if hint then
		hintLabel = new("TextLabel", {
			Size = UDim2.new(0, 120, 1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = hint,
			TextSize = 10,
			TextColor3 = Color3.fromRGB(108, 117, 133),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end
	return row, hintLabel
end

--=============================================================
-- 开关（mac 风拨片）
--=============================================================
local function makeToggle(parent, state, onChange)
	local track = new("TextButton", {
		Size = UDim2.fromOffset(38, 21),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
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

	new("TextLabel", {
		Size = UDim2.new(1, -90, 0, 15),
		Position = UDim2.fromOffset(13, 11),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.title,
		TextSize = 12,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local desc = new("TextLabel", {
		Size = UDim2.new(1, -90, 0, 13),
		Position = UDim2.fromOffset(13, 27),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = opts.desc or "",
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)

	local toggleInstance
	if opts.control and opts.control.kind == "toggle" then
		toggleInstance = makeToggle(card, opts.control.value or false, opts.control.onChange)
	end

	return card, toggleInstance, desc
end

--=============================================================
-- 卡片 1：点击传送（原功能）
--=============================================================
makeSection("点击传送", "落点 +3 格")

local _, clickToggleInstance = makeCard({
	title = "点击传送",
	desc = "点击即传送 · 载具同步",
	control = {
		kind = "toggle",
		value = false,
		onChange = function(state)
			clickTP = state
			updateStatus()
		end,
	},
})
clickToggle = clickToggleInstance

--=============================================================
-- 卡片 2：上帝视角
--=============================================================
local _, godHintLabel = makeSection("上帝视角", "高度 " .. GOD.Height)
godHint = godHintLabel

local _, godToggleInstance, godDesc = makeCard({
	title = "上帝视角",
	desc = "高空俯视 · 拖拽选点",
	control = {
		kind = "toggle",
		value = false,
		onChange = function(state)
			setGodMode(state)
			if godActive ~= state then
				-- 没有角色 / 相机时回弹
				if godToggle then godToggle.set(godActive, true) end
			end
			updateStatus()
		end,
	},
})
godToggle = godToggleInstance
godCardDesc = godDesc

--=============================================================
-- 视角高度：上下两栏
--=============================================================
local function makeRow()
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, CONFIG.RowHeight),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = list,
	})
end

local function makeMoveButton(parent, opts)
	local btn = new("TextButton", {
		Size = UDim2.new(0.5, -4, 1, 0),
		Position = opts.right and UDim2.new(0.5, 4, 0, 0) or UDim2.fromOffset(0, 0),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	corner(btn, 9)
	local btnStroke = stroke(btn, Color3.fromRGB(42, 47, 58), 1)

	new("TextLabel", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(11, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.glyph,
		TextSize = 13,
		TextColor3 = opts.accent or THEME.Accent,
		Parent = btn,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -42, 1, 0),
		Position = UDim2.fromOffset(29, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.title,
		TextSize = 11,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)

	if opts.onClick then
		btn.MouseButton1Click:Connect(function()
			opts.onClick()
			TweenService:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(58, 66, 86) }):Play()
			task.delay(0.1, function()
				TweenService:Create(btn, TweenInfo.new(0.18), { BackgroundColor3 = THEME.Card }):Play()
			end)
		end)
	end

	return btn, btnStroke
end

local heightRow = makeRow()
makeMoveButton(heightRow, {
	glyph = "−",
	title = "拉近视野",
	onClick = function()
		setGodHeight(godHeight - GOD.HeightStep)
	end,
})
makeMoveButton(heightRow, {
	glyph = "+",
	title = "拉远视野",
	right = true,
	onClick = function()
		setGodHeight(godHeight + GOD.HeightStep)
	end,
})

--=============================================================
-- 上帝视角遮罩层（ZIndex 低于窗口，窗口始终可点）
--=============================================================
local overlay = new("Frame", {
	Name = "GodView",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})

local godBg = new("TextButton", {
	Name = "PanArea",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 1,
	Parent = overlay,
})

-- 顶部提示胶囊
local godTop = new("Frame", {
	Size = UDim2.fromOffset(216, 38),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 16),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = overlay,
})
corner(godTop, 10)
rainbowStroke(godTop, 1)

new("TextLabel", {
	Size = UDim2.new(1, -44, 0, 14),
	Position = UDim2.fromOffset(12, 5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "上帝视角",
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = godTop,
})
new("TextLabel", {
	Size = UDim2.new(1, -24, 0, 12),
	Position = UDim2.fromOffset(12, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "拖拽或摇杆选点 · 双指缩放",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = godTop,
})

local godExit = new("TextButton", {
	Size = UDim2.fromOffset(20, 20),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 8),
	BackgroundColor3 = Color3.fromRGB(56, 62, 76),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextSize = 11,
	TextColor3 = THEME.Text,
	ZIndex = 4,
	Parent = godTop,
})
corner(godExit, 9)

-- 屏幕中心准星
local cross = new("Frame", {
	Size = UDim2.fromOffset(84, 84),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = overlay,
})

local crossRing = new("Frame", {
	Size = UDim2.fromOffset(42, 42),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = cross,
})
corner(crossRing, 21)
new("UIStroke", { Color = THEME.Accent, Thickness = 1.5, Transparency = 0.15, Parent = crossRing })

local crossDot = new("Frame", {
	Size = UDim2.fromOffset(5, 5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Parent = cross,
})
corner(crossDot, 3)

for _, tick in ipairs({
	{ Size = UDim2.fromOffset(1, 10), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2) },
	{ Size = UDim2.fromOffset(1, 10), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2) },
	{ Size = UDim2.fromOffset(10, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0) },
	{ Size = UDim2.fromOffset(10, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0) },
}) do
	new("Frame", {
		Size = tick.Size,
		AnchorPoint = tick.AnchorPoint,
		Position = tick.Position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = cross,
	})
end

--=============================================================
-- 左下角虚拟摇杆（触摸优先）
--=============================================================
local JOY_SIZE = 118
local JOY_KNOB = 48
local JOY_RADIUS = JOY_SIZE * 0.5 - JOY_KNOB * 0.5 - 5

local joyBase = new("Frame", {
	Name = "Joystick",
	Size = UDim2.fromOffset(JOY_SIZE, JOY_SIZE),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18, 1, -26),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 3,
	Parent = overlay,
})
corner(joyBase, JOY_SIZE * 0.5)
new("UIStroke", { Color = THEME.Accent, Thickness = 1, Transparency = 0.5, Parent = joyBase })

local joyRing = new("Frame", {
	Size = UDim2.fromOffset(JOY_SIZE - 32, JOY_SIZE - 32),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = joyBase,
})
corner(joyRing, (JOY_SIZE - 32) * 0.5)
new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.9, Parent = joyRing })

-- 四个方向的小刻度，暗示「推杆方向 = 落点方向」
for _, tick in ipairs({
	{ Size = UDim2.fromOffset(1, 6), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 9) },
	{ Size = UDim2.fromOffset(1, 6), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -9) },
	{ Size = UDim2.fromOffset(6, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0) },
	{ Size = UDim2.fromOffset(6, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0) },
}) do
	new("Frame", {
		Size = tick.Size,
		AnchorPoint = tick.AnchorPoint,
		Position = tick.Position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Parent = joyBase,
	})
end

local joyKnob = new("Frame", {
	Size = UDim2.fromOffset(JOY_KNOB, JOY_KNOB),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = joyBase,
})
corner(joyKnob, JOY_KNOB * 0.5)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 158, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 108, 255)),
	}),
	Rotation = 45,
	Parent = joyKnob,
})
new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.5, Parent = joyKnob })

--=============================================================
-- 摇杆移速：快 / 慢（摇杆右侧竖排）
--=============================================================
local joySpeedMul = 1.0
local joySpeedHold = 0          -- -1 慢 / 1 快 / 0 松手
local joySpeedHoldT = 0
local joySpeedAccT = 0

local SPEED_BOX_W = 46
local SPEED_BOX_H = JOY_SIZE

local speedBox = new("Frame", {
	Name = "JoySpeed",
	Size = UDim2.fromOffset(SPEED_BOX_W, SPEED_BOX_H),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 18 + JOY_SIZE + 10, 1, -26),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 3,
	Parent = overlay,
})
corner(speedBox, 20)
new("UIStroke", { Color = THEME.Stroke, Thickness = 1, Transparency = 0.25, Parent = speedBox })

local joySpeedValue = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 22),
	Position = UDim2.fromOffset(0, SPEED_BOX_H * 0.5 - 11),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "1.0×",
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 4,
	Parent = speedBox,
})

local function makeSpeedBtn(textText, y, color)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(SPEED_BOX_W - 10, 36),
		Position = UDim2.fromOffset(5, y),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = textText,
		TextSize = 11,
		TextColor3 = color,
		ZIndex = 4,
		Parent = speedBox,
	})
	corner(btn, 9)
	stroke(btn, Color3.fromRGB(42, 47, 58), 1)
	return btn
end

local fastBtn = makeSpeedBtn("快", 6, THEME.Green)
local slowBtn = makeSpeedBtn("慢", SPEED_BOX_H - 42, THEME.SubText)

local function applyJoySpeed()
	joySpeedValue.Text = string.format("%.1f×", joySpeedMul)
	local maxed = joySpeedMul >= GOD.JoyMax - 0.001
	local mined = joySpeedMul <= GOD.JoyMin + 0.001
	fastBtn.TextColor3 = maxed and THEME.SubText or THEME.Green
	slowBtn.TextColor3 = mined and THEME.SubText or THEME.Text
end

local function nudgeJoySpeed(dir)
	joySpeedMul = math.clamp(
		math.floor((joySpeedMul + dir * GOD.JoyStep) * 10 + 0.5) / 10,
		GOD.JoyMin, GOD.JoyMax
	)
	applyJoySpeed()
end

local function bindSpeedBtn(btn, dir)
	local down = btn.MouseButton1Down
	if down then
		down:Connect(function()
			joySpeedHold = dir
			joySpeedHoldT = 0
			joySpeedAccT = 0
			nudgeJoySpeed(dir)
			TweenService:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(58, 66, 86) }):Play()
			task.delay(0.1, function()
				TweenService:Create(btn, TweenInfo.new(0.18), { BackgroundColor3 = THEME.Card }):Play()
			end)
		end)
	end
	local up = btn.MouseButton1Up
	if up then
		up:Connect(function()
			joySpeedHold = 0
		end)
	end
end

bindSpeedBtn(fastBtn, 1)
bindSpeedBtn(slowBtn, -1)
applyJoySpeed()

-- 底部操作条
local godBar = new("Frame", {
	Size = UDim2.fromOffset(268, 60),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -26),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = overlay,
})
corner(godBar, 12)
stroke(godBar, THEME.Stroke, 1)

godCoordLabel = new("TextLabel", {
	Size = UDim2.new(0, 150, 0, 15),
	Position = UDim2.fromOffset(14, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "X 0   Y 0   Z 0",
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = godBar,
})

godInfoLabel = new("TextLabel", {
	Size = UDim2.new(0, 150, 0, 12),
	Position = UDim2.fromOffset(14, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "高度 260 · 拖拽平移",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = godBar,
})

godStateLabel = new("TextLabel", {
	Size = UDim2.new(0, 150, 0, 12),
	Position = UDim2.fromOffset(14, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "摇杆或拖拽选择落点",
	TextSize = 9,
	TextColor3 = Color3.fromRGB(108, 117, 133),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = godBar,
})

tpBtn = new("TextButton", {
	Size = UDim2.fromOffset(88, 36),
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "传送到此",
	TextSize = 12,
	TextColor3 = Color3.fromRGB(12, 34, 24),
	ZIndex = 4,
	Parent = godBar,
})
corner(tpBtn, 9)

tpBtn.MouseEnter:Connect(function()
	if godValid then
		TweenService:Create(tpBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(96, 220, 152) }):Play()
	end
end)
tpBtn.MouseLeave:Connect(function()
	TweenService:Create(tpBtn, TweenInfo.new(0.12), {
		BackgroundColor3 = godValid and THEME.Green or Color3.fromRGB(52, 58, 70),
	}):Play()
end)

local toast = new("TextLabel", {
	Size = UDim2.fromOffset(150, 26),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -122),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextSize = 12,
	TextColor3 = THEME.Green,
	TextTransparency = 1,
	ZIndex = 4,
	Parent = overlay,
})
corner(toast, 8)

--=============================================================
-- 传送核心（步行 / 载具）
--=============================================================
local function characterFilter()
	local list_ = {}
	if player.Character then
		table.insert(list_, player.Character)
	end
	return list_
end

local function teleportTo(targetPosition)
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return false end

	-- 防卡墙：往天上抬 3 格
	local finalPos = targetPosition + Vector3.new(0, CONFIG.LandOffset, 0)

	if humanoid.SeatPart then
		-- 载具：传送车身，保持朝向
		local vehicleRoot = humanoid.SeatPart.AssemblyRootPart or humanoid.SeatPart
		if vehicleRoot then
			vehicleRoot.CFrame = CFrame.new(finalPos) * (vehicleRoot.CFrame - vehicleRoot.CFrame.Position)
		end
	else
		hrp.CFrame = CFrame.new(finalPos)
	end
	return true
end

-- 点击是否落在本脚本的 UI 上
local function isClickingUI(x, y)
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(x, y)
	end)
	if not ok or not objects then return false end
	for _, obj in ipairs(objects) do
		if obj:IsA("GuiObject") and obj:FindFirstAncestorOfClass("ScreenGui") == gui then
			return true
		end
	end
	return false
end

--=============================================================
-- 地面光环标记
--=============================================================
local marker = new("Part", {
	Name = "Havvk_TpMarker",
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	Transparency = 1,
	Size = Vector3.new(1, 1, 1),
})
marker.CFrame = CFrame.new(0, 0, 0)

local markerBill = new("BillboardGui", {
	Name = "Marker",
	Size = UDim2.fromOffset(72, 72),
	AlwaysOnTop = true,
	LightInfluence = 0,
	MaxDistance = 8000,
	Parent = marker,
})

local markerRing = new("Frame", {
	Size = UDim2.fromOffset(44, 44),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
	Parent = markerBill,
})
corner(markerRing, 22)
new("UIStroke", { Color = THEME.Accent, Thickness = 2, Transparency = 0.1, Parent = markerRing })

local markerDot = new("Frame", {
	Size = UDim2.fromOffset(5, 5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	Parent = markerBill,
})
corner(markerDot, 3)

for _, tick in ipairs({
	{ Size = UDim2.fromOffset(1, 9), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3) },
	{ Size = UDim2.fromOffset(1, 9), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3) },
	{ Size = UDim2.fromOffset(9, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0) },
	{ Size = UDim2.fromOffset(9, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0) },
}) do
	new("Frame", {
		Size = tick.Size,
		AnchorPoint = tick.AnchorPoint,
		Position = tick.Position,
		BackgroundColor3 = THEME.Accent,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = markerBill,
	})
end

--=============================================================
-- 上帝视角：相机
--=============================================================
local camCenter = Vector3.new(0, 0, 0)
local joyVec = Vector2.new(0, 0)
local godConn = nil
local godClock = 0
local godTextTimer = 0
local savedCamType, savedCamSubject, savedCamCFrame
local posBeforeGod = nil
local tpVisualOn = nil

local godRayParams = RaycastParams.new()
godRayParams.FilterType = Enum.RaycastFilterType.Exclude
godRayParams.IgnoreWater = true

local function refreshRayFilter()
	godRayParams.FilterDescendantsInstances = characterFilter()
end
refreshRayFilter()

local function groundBelow()
	return workspace:Raycast(
		Vector3.new(camCenter.X, GOD.RayTop, camCenter.Z),
		Vector3.new(0, -(GOD.RayTop + GOD.RayBottom), 0),
		godRayParams
	)
end

local function clampCenter(c)
	return Vector3.new(
		math.clamp(c.X, -GOD.PanLimit, GOD.PanLimit),
		0,
		math.clamp(c.Z, -GOD.PanLimit, GOD.PanLimit)
	)
end

local function worldPerPixel()
	local cam = workspace.CurrentCamera
	if not cam then return 1 end
	local fov = math.rad(cam.FieldOfView)
	return (2 * godHeight * math.tan(fov * 0.5)) / math.max(1, cam.ViewportSize.Y)
end

local function setTpVisual(on)
	on = on and true or false
	if tpVisualOn == on then return end
	tpVisualOn = on
	tpBtn.Text = on and "传送到此" or "无落点"
	tpBtn.BackgroundColor3 = on and THEME.Green or Color3.fromRGB(52, 58, 70)
	tpBtn.TextColor3 = on and Color3.fromRGB(12, 34, 24) or Color3.fromRGB(130, 138, 152)
	tpBtn.AutoButtonColor = false
	godStateLabel.Text = on and "摇杆或拖拽选择落点" or "此处没有可站立的地面"
	godStateLabel.TextColor3 = on and Color3.fromRGB(108, 117, 133) or THEME.Yellow
end

local function updateGod(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- 按住快 / 慢按钮超过 0.4s 后连续步进
	if joySpeedHold ~= 0 then
		joySpeedHoldT = joySpeedHoldT + dt
		if joySpeedHoldT > 0.4 then
			joySpeedAccT = joySpeedAccT + dt
			while joySpeedAccT >= 0.07 do
				joySpeedAccT = joySpeedAccT - 0.07
				nudgeJoySpeed(joySpeedHold)
			end
		end
	end

	-- 摇杆：推杆方向 = 落点移动方向，推得越远越快
	local joyMag = joyVec.Magnitude
	if joyMag > 0.05 then
		local speed = godHeight * GOD.JoySpeed * joySpeedMul * math.min(joyMag, 1)
		camCenter = clampCenter(camCenter + Vector3.new(joyVec.X, 0, joyVec.Y) * (speed * dt))
	end

	local hit = groundBelow()
	if hit and hit.Position then
		godTarget = hit.Position
		godValid = true
	else
		godTarget = Vector3.new(camCenter.X, 0, camCenter.Z)
		godValid = false
	end

	local groundY = godTarget.Y
	cam.CFrame = CFrame.lookAt(
		Vector3.new(camCenter.X, groundY + godHeight, camCenter.Z),
		Vector3.new(camCenter.X, groundY, camCenter.Z),
		Vector3.new(0, 0, -1)
	)

	if marker.Parent ~= cam then
		marker.Parent = cam
	end
	marker.CFrame = CFrame.new(godTarget + Vector3.new(0, 0.1, 0))

	godClock = godClock + dt
	local pulse = 1 + math.sin(godClock * 3) * 0.07
	markerBill.Size = UDim2.fromOffset(72 * pulse, 72 * pulse)

	godTextTimer = godTextTimer + dt
	if godTextTimer >= 0.06 then
		godTextTimer = 0
		godCoordLabel.Text = string.format("X %d   Y %d   Z %d",
			math.floor(godTarget.X), math.floor(godTarget.Y), math.floor(godTarget.Z))
		godInfoLabel.Text = string.format("高度 %d · 摇杆 %.1f×",
			math.floor(godHeight), joySpeedMul)
		setTpVisual(godValid)
	end
end

--=============================================================
-- 上帝视角：开关
--=============================================================
local function windowCoversCenter()
	local vp = viewportSize()
	local s = uiScale.Scale
	local cx, cy = vp.X * 0.5, vp.Y * 0.5
	return cx > pos.X - 30 and cx < pos.X + winW * s + 30
		and cy > pos.Y - 30 and cy < pos.Y + winH * s + 30
end

function setGodMode(on)
	on = on and true or false
	if godActive == on then return end

	if on then
		local cam = workspace.CurrentCamera
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not cam or not hrp then
			if godToggle then godToggle.set(false, true) end
			updateStatus()
			return
		end

		camCenter = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		godHeight = GOD.Height
		godActive = true
		godClock = 0
		refreshRayFilter()

		savedCamType = cam.CameraType
		savedCamSubject = cam.CameraSubject
		savedCamCFrame = cam.CFrame
		cam.CameraType = Enum.CameraType.Scriptable

		marker.Parent = cam
		overlay.Visible = true

		updateGod(0)
		godConn = RunService.RenderStepped:Connect(updateGod)

		-- 窗口挡住中心时先让开，避免遮住准星
		posBeforeGod = pos
		if windowCoversCenter() then
			pos = clampPos(Vector2.new(12, 12))
			apply()
		end
	else
		godActive = false
		if godConn then
			godConn:Disconnect()
			godConn = nil
		end
		overlay.Visible = false
		marker.Parent = nil
		tpVisualOn = nil
		if resetJoy then resetJoy() end
		joySpeedHold = 0

		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = savedCamType or Enum.CameraType.Custom
			if savedCamSubject then
				cam.CameraSubject = savedCamSubject
			end
			if savedCamCFrame then
				cam.CFrame = savedCamCFrame
			end
		end

		if posBeforeGod then
			pos = clampPos(posBeforeGod)
			posBeforeGod = nil
			apply()
		end
	end

	if godToggle then godToggle.set(godActive, true) end
	updateStatus()
end

function setGodHeight(value)
	godHeight = math.clamp(value, GOD.MinHeight, GOD.MaxHeight)
	updateStatus()
end

--=============================================================
-- 状态刷新
--=============================================================
function updateStatus()
	if godActive then
		subtitleLabel.Text = string.format("俯视中 · 高度 %d", math.floor(godHeight))
	elseif clickTP then
		subtitleLabel.Text = "点击传送 · 已开启"
	else
		subtitleLabel.Text = "待机 · 点击传送 关"
	end

	minimizedDot.BackgroundColor3 = (clickTP or godActive)
		and THEME.Green or Color3.fromRGB(112, 121, 138)

	if godHint then
		godHint.Text = string.format("高度 %d", math.floor(godHeight))
	end
	if godCardDesc then
		godCardDesc.Text = godActive and "俯视中 · 拖动屏幕选点" or "高空俯视 · 拖拽选点"
	end
end

--=============================================================
-- 输入：点击传送（保留原脚本行为）
--=============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not clickTP or godActive or gameProcessed or tpCooldown then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local p = input.Position
	if isClickingUI(p.X, p.Y) then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	local ray = cam:ViewportPointToRay(p.X, p.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter()
	params.IgnoreWater = true

	local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if not result or not result.Position then return end
	if not teleportTo(result.Position) then return end

	tpCooldown = true
	task.delay(CONFIG.Cooldown, function()
		tpCooldown = false
	end)
end)

--=============================================================
-- 输入：上帝视角 —— 摇杆 / 拖拽平移 / 缩放
--=============================================================
local panning = false
local panLast = nil
local lastPinch = nil
local joyActive = false
local joyInput = nil

local function joyCenter()
	local absPos = joyBase.AbsolutePosition
	local absSize = joyBase.AbsoluteSize
	return Vector2.new(absPos.X + absSize.X * 0.5, absPos.Y + absSize.Y * 0.5)
end

local function moveJoy(pos)
	local d = Vector2.new(pos.X, pos.Y) - joyCenter()
	local m = d.Magnitude
	if m > JOY_RADIUS then
		d = d * (JOY_RADIUS / m)
	end
	joyKnob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)

	local v = Vector2.new(d.X / JOY_RADIUS, d.Y / JOY_RADIUS)
	if v.Magnitude > 1 then
		v = v.Unit
	end
	joyVec = v
end

function resetJoy()
	joyActive = false
	joyInput = nil
	joyVec = Vector2.new(0, 0)
	joyKnob.Position = UDim2.fromScale(0.5, 0.5)
end

-- 摇杆：按住即生效，推到边缘为满速
joyBase.InputBegan:Connect(function(input)
	if not godActive then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	joyActive = true
	joyInput = input
	panning = false
	moveJoy(input.Position)
end)

-- 空白处拖拽：抓住地图拖，内容跟手
godBg.InputBegan:Connect(function(input)
	if not godActive then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		panning = true
		panLast = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not godActive then return end

	-- 摇杆优先，其余输入忽略
	if joyActive and input == joyInput then
		moveJoy(input.Position)
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		setGodHeight(godHeight - input.Position.Z * 40)
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		local touches = UserInputService:GetTouches()
		if touches and #touches >= 2 and not joyActive and not panning then
			local a = touches[1].Position
			local b = touches[2].Position
			local d = (Vector2.new(a.X, a.Y) - Vector2.new(b.X, b.Y)).Magnitude
			if lastPinch and lastPinch > 0 and d > 0 then
				setGodHeight(godHeight * (lastPinch / d))
			end
			lastPinch = d
			return
		end
		lastPinch = nil
	end

	if not panning then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- 用绝对坐标自己算增量，触摸端不依赖 InputObject.Delta
	local now = Vector2.new(input.Position.X, input.Position.Y)
	local d = panLast and (now - panLast) or Vector2.new(0, 0)
	panLast = now

	local s = worldPerPixel()
	camCenter = clampCenter(camCenter - Vector3.new(d.X, 0, d.Y) * s)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		panning = false
		panLast = nil
		lastPinch = nil
		joySpeedHold = 0
		if joyActive and input == joyInput then
			resetJoy()
		end
	end
end)

--=============================================================
-- 上帝视角：确认传送 / 退出
--=============================================================
local toastToken = 0
local function showToast(text)
	toastToken = toastToken + 1
	local token = toastToken
	toast.Text = text
	toast.TextTransparency = 1
	toast.BackgroundTransparency = 0.15
	TweenService:Create(toast, TweenInfo.new(0.12), { TextTransparency = 0 }):Play()
	task.delay(0.85, function()
		if token ~= toastToken then return end
		TweenService:Create(toast, TweenInfo.new(0.3), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
	end)
end

tpBtn.MouseButton1Click:Connect(function()
	if not godActive or not godValid or not godTarget then return end
	if teleportTo(godTarget) then
		showToast("已传送到落点")
		TweenService:Create(tpBtn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(140, 245, 190) }):Play()
		task.delay(0.12, function()
			TweenService:Create(tpBtn, TweenInfo.new(0.2), {
				BackgroundColor3 = godValid and THEME.Green or Color3.fromRGB(52, 58, 70),
			}):Play()
		end)
	else
		showToast("当前没有角色")
	end
end)

godExit.MouseButton1Click:Connect(function()
	setGodMode(false)
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
	Size = UDim2.fromOffset(88, CONFIG.BottomBarHeight),
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
	Size = UDim2.fromOffset(38, 4),
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
-- 拖动（只移动，不缩放）
--=============================================================
local dragState = nil

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
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if not dragState then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local delta = inputXY(input) - dragState.startInput
	pos = clampPos(dragState.origin + delta)
	apply()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragState = nil
	end
end)

bindDrag(header)
bindDrag(logo)
bindDrag(titleLabel)
bindDrag(subtitleLabel)
bindDrag(minimizedLabel)
bindDrag(dragHandle)

--=============================================================
-- 最小化 / 还原 / 关闭
--=============================================================
function setMinimized(state)
	minimized = state

	logo.Visible = not state
	titleLabel.Visible = not state
	subtitleLabel.Visible = not state
	minimizedLabel.Visible = state
	minimizedDot.Visible = state
	body.Visible = not state
	bottomBar.Visible = not state
	minDot.Visible = true
	dotGlyphs[minDot] = state and "+" or "−"

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
	setGodMode(false)
	gui:Destroy()
end)

minDot.MouseButton1Click:Connect(function()
	setMinimized(not minimized)
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateScale()
		pos = clampPos(pos)
		apply()
	end)
end

-- 角色重生：退出俯视、复位状态
player.CharacterAdded:Connect(function()
	setGodMode(false)
	refreshRayFilter()
	if clickTP then
		clickTP = false
		if clickToggle then clickToggle.set(false, true) end
	end
	updateStatus()
end)

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
