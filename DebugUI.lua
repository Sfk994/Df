--[[
	==============================================================
	  DebugUI · Roblox 调试面板 v1.4
	==============================================================
	  使用方法：
	    1. 在 StarterGui 里新建一个 LocalScript
	    2. 把本文件内容整体粘贴进去
	    3. 运行游戏

	  交互：
	    · 底部小白条长按拖动窗口（标题栏也可以拖），拖动时不会带动镜头
	    · 右下角半透明三角拖拽可自由缩放窗口大小
	    · 右上角三个圆点（mac 风）：黄 = 最小化，绿 = 最大化 / 还原，红 = 关闭
	    · 窗口边框是一圈缓慢旋转的细彩虹线
	    · 最小化后收缩成一个小胶囊，只留时间 + 放大 + 关闭
	    · 左侧「主功能 / 设置」切换右侧内容；主功能为 2×2 卡片，窗口变窄自动变 1×4

	  对外接口：
	    _G.DebugUI:Log("消息", "info")       -- info / success / warn / error
	    _G.DebugUI:SetVisible(true)
	    _G.DebugUI:OpenLog()
	    _G.DebugUI.OnReload = function() end
	==============================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=============================================================
-- 配置
--=============================================================
local CONFIG = {
	Title = "调试面板",
	Subtitle = "管理员 · v1.4",
	Width = 560,
	Height = 400,
	MinWidth = 300,
	MinHeight = 280,
	HeaderHeight = 52,
	BottomBarHeight = 16,
	MinimizedHeight = 30,
	MinimizedWidth = 152,
	CardHeight = 66,
	MaxLogLines = 150,
}

local THEME = {
	Background = Color3.fromRGB(20, 22, 28),
	Header     = Color3.fromRGB(24, 27, 34),
	Sidebar    = Color3.fromRGB(23, 26, 33),
	Card       = Color3.fromRGB(33, 37, 47),
	CardHover  = Color3.fromRGB(38, 43, 54),
	NavActive  = Color3.fromRGB(35, 40, 51),
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

local LEVEL_COLORS = {
	info    = Color3.fromRGB(196, 203, 217),
	success = THEME.Green,
	warn    = THEME.Yellow,
	error   = THEME.Red,
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

local API = {}
local log, showPage, openLog, closeLog, reloadPanel, setNavActive -- 前向声明

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

-- 右对齐，视觉顺序（左→右）：最小化 · 最大化 · 关闭
local closeDot = makeDot(THEME.DotRed, 14, "×")
local maxDot = makeDot(THEME.DotGreen, 34, "+")
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
	Text = "D",
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = logo,
})

local titleLabel = new("TextLabel", {
	Size = UDim2.new(1, -126, 0, 17),
	Position = UDim2.fromOffset(46, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = CONFIG.Title,
	TextSize = 14,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

local subtitleLabel = new("TextLabel", {
	Size = UDim2.new(1, -126, 0, 13),
	Position = UDim2.fromOffset(46, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = CONFIG.Subtitle,
	TextSize = 10,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Active = true,
	Parent = header,
})

-- 最小化胶囊里显示的时间
local clockLabel = new("TextLabel", {
	Size = UDim2.new(1, -78, 1, 0),
	Position = UDim2.fromOffset(16, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	Text = os.date("%H:%M:%S"),
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	Active = true,
	Parent = header,
})

--=============================================================
-- 主体：左侧目录 + 右侧内容
--=============================================================
local body = new("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -(CONFIG.HeaderHeight + CONFIG.BottomBarHeight)),
	BackgroundTransparency = 1,
	Parent = window,
})

local sidebar = new("Frame", {
	Name = "Sidebar",
	Size = UDim2.new(0, 132, 1, 0),
	BackgroundColor3 = THEME.Sidebar,
	BorderSizePixel = 0,
	Parent = body,
})
new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = THEME.Stroke,
	BorderSizePixel = 0,
	Parent = sidebar,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	Parent = sidebar,
})

local navList = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = sidebar,
})
new("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = navList,
})

local sideStats = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Parent = sidebar,
})
new("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Color3.fromRGB(36, 41, 51),
	BorderSizePixel = 0,
	Parent = sideStats,
})

local function makeSideStat(title, order)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 4 + (order - 1) * 16),
		BackgroundTransparency = 1,
		Parent = sideStats,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -50, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = title,
		TextSize = 10,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "--",
		TextSize = 10,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
end

local fpsValue = makeSideStat("FPS", 1)
local pingValue = makeSideStat("PING", 2)

local contentHolder = new("Frame", {
	Name = "ContentHolder",
	Position = UDim2.new(0, 133, 0, 0),
	Size = UDim2.new(1, -133, 1, 0),
	BackgroundTransparency = 1,
	Parent = body,
})

--=============================================================
-- 左侧目录项
--=============================================================
local navItems = {}
local navOrder = 0

-- 目录图标：用纯 GUI 拼出来，不依赖任何图片资源
local ICON_IDLE = Color3.fromRGB(112, 121, 138)

local function makeNavIcon(parent, kind)
	local holder = new("Frame", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.new(0, 10, 0.5, -6.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local parts = {}
	local function block(x, y, w, h, radius)
		local f = new("Frame", {
			Size = UDim2.fromOffset(w, h),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = ICON_IDLE,
			BorderSizePixel = 0,
			Parent = holder,
		})
		corner(f, radius or 1.5)
		parts[#parts + 1] = f
		return f
	end

	if kind == "grid" then
		-- 四宫格
		local s, gap = 5, 3
		for i = 0, 3 do
			block((i % 2) * (s + gap), math.floor(i / 2) * (s + gap), s, s, 1.5)
		end
	elseif kind == "sliders" then
		-- 两条滑杆
		block(0, 3, 13, 1.5, 1)
		block(8, 1.5, 4.5, 4.5, 2.2)
		block(0, 8.5, 13, 1.5, 1)
		block(2, 7, 4.5, 4.5, 2.2)
	end

	return { holder = holder, parts = parts }
end

local function makeNavItem(key, text, iconKind)
	navOrder += 1
	local row = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.NavActive,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = navOrder,
		Parent = navList,
	})
	corner(row, 8)

	local icon = makeNavIcon(row, iconKind)

	local label = new("TextLabel", {
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = 12,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local dot = new("Frame", {
		Size = UDim2.fromOffset(6, 6),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = THEME.Red,
		BorderSizePixel = 0,
		Visible = false,
		Parent = row,
	})
	corner(dot, 3)

	local item = { row = row, icon = icon, label = label, dot = dot, active = false }
	navItems[key] = item

	row.MouseEnter:Connect(function()
		if not item.active then
			TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.6 }):Play()
		end
	end)
	row.MouseLeave:Connect(function()
		if not item.active then
			TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		end
	end)

	row.MouseButton1Click:Connect(function()
		if key == "settings" then
			showPage("settings")
		else
			showPage("main")
		end
	end)

	return item
end

makeNavItem("main", "主功能", "grid")
makeNavItem("settings", "设置", "sliders")

function setNavActive(key)
	for k, item in pairs(navItems) do
		local active = (k == key)
		item.active = active
		item.row.BackgroundTransparency = active and 0 or 1
		item.label.TextColor3 = active and THEME.Text or THEME.SubText
		for _, part in ipairs(item.icon.parts) do
			part.BackgroundColor3 = active and THEME.Accent or ICON_IDLE
		end
	end
end

--=============================================================
-- 卡片
--=============================================================
local function makePill(parent, text, onClick)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(52, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(44, 49, 61),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = 11,
		TextColor3 = THEME.Text,
		Parent = parent,
	})
	corner(btn, 7)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(54, 60, 74) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(44, 49, 61) }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if onClick then onClick() end
	end)
	return btn
end

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
	track.MouseButton1Click:Connect(function()
		value = not value
		TweenService:Create(track, TweenInfo.new(0.15), {
			BackgroundColor3 = value and THEME.Accent or Color3.fromRGB(56, 62, 76),
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = UDim2.new(0, value and 21 or 3, 0.5, 0),
		}):Play()
		if onChange then onChange(value) end
	end)

	return { track = track, get = function() return value end }
end

local function makeCard(parent, opts)
	local card = new("TextButton", {
		Size = UDim2.new(1, 0, 0, CONFIG.CardHeight),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.order or 1,
		Parent = parent,
	})
	corner(card, 10)
	stroke(card, Color3.fromRGB(42, 47, 58), 1)

	local reserved = 78
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
	new("TextLabel", {
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

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)
	card.MouseButton1Click:Connect(function()
		if opts.onClick then opts.onClick() end
	end)

	local control = opts.control
	if control then
		if control.kind == "pill" then
			makePill(card, control.text or "运行", control.onClick)
		elseif control.kind == "toggle" then
			makeToggle(card, control.value or false, control.onChange)
		end
	end

	return card
end

--=============================================================
-- 页面容器
--=============================================================
local mainGrid -- 主功能的网格布局（随窗口宽度重排）

local function makePage(name, layoutKind)
	local page = new("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = contentHolder,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = page,
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
		Parent = page,
	})
	local list = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = scroll,
	})

	if layoutKind == "grid" then
		mainGrid = new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4.5, 0, CONFIG.CardHeight),
			CellPadding = UDim2.new(0, 9, 0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
	else
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
	end

	return page, list
end

local pageMain, listMain = makePage("Main", "grid")
local pageSettings, listSettings = makePage("Settings", "list")

-- 主功能：四个功能卡片
for i = 1, 4 do
	local index = i
	local isToggle = (i == 4)
	local control

	if isToggle then
		control = {
			kind = "toggle",
			value = false,
			onChange = function(state)
				log(string.format("「功能占位 %d」自动执行已%s", index, state and "开启" or "关闭"), "info")
			end,
		}
	else
		control = {
			kind = "pill",
			text = "运行",
			onClick = function()
				log(string.format("「功能占位 %d」尚未绑定功能", index), "warn")
			end,
		}
	end

	makeCard(listMain, {
		order = i,
		title = string.format("功能占位 %d", i),
		desc = isToggle and "开关式：开启执行，关闭停止" or "点击运行脚本",
		control = control,
		onClick = function()
			log(string.format("「功能占位 %d」尚未绑定功能", index), "warn")
		end,
	})
end

-- 设置：重载 + 日志
makeCard(listSettings, {
	order = 1,
	title = "重载",
	desc = "重新载入面板与配置，清空未读",
	control = { kind = "pill", text = "执行", onClick = function() reloadPanel() end },
	onClick = function() reloadPanel() end,
})

local logCard = makeCard(listSettings, {
	order = 2,
	title = "日志",
	desc = "查看脚本输出记录",
	control = { kind = "pill", text = "打开", onClick = function() openLog() end },
	onClick = function() openLog() end,
})

local logCardDot = new("Frame", {
	Size = UDim2.fromOffset(7, 7),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	BackgroundColor3 = THEME.Red,
	BorderSizePixel = 0,
	Visible = false,
	Parent = logCard,
})
corner(logCardDot, 4)

--=============================================================
-- 日志页
--=============================================================
local logPane = new("Frame", {
	Name = "LogPane",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = contentHolder,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = logPane,
})

local backBtn = new("TextButton", {
	Size = UDim2.fromOffset(62, 22),
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamMedium,
	Text = "← 返回",
	TextSize = 11,
	TextColor3 = THEME.SubText,
	Parent = logPane,
})
corner(backBtn, 6)
backBtn.MouseEnter:Connect(function() backBtn.TextColor3 = THEME.Text end)
backBtn.MouseLeave:Connect(function() backBtn.TextColor3 = THEME.SubText end)

local clearBtn = new("TextButton", {
	Size = UDim2.fromOffset(50, 22),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(44, 49, 61),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamMedium,
	Text = "清空",
	TextSize = 11,
	TextColor3 = THEME.Text,
	Parent = logPane,
})
corner(clearBtn, 6)

local logScroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 30),
	Size = UDim2.new(1, 0, 1, -30),
	BackgroundColor3 = Color3.fromRGB(15, 17, 22),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = logPane,
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
-- 日志逻辑
--=============================================================
local logLines = {}
local unread = 0
local logVisible = false
local booting = true -- 启动阶段的日志不算未读

local function refreshUnread()
	local show = unread > 0 and not logVisible
	logCardDot.Visible = show
	navItems.settings.dot.Visible = show and not pageSettings.Visible
end

local function scrollLogToBottom()
	task.defer(function()
		if logScroll.Parent then
			local maxY = logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteWindowSize.Y
			logScroll.CanvasPosition = Vector2.new(0, math.max(0, maxY))
		end
	end)
end

function log(message, level)
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

	if logVisible then
		scrollLogToBottom()
	elseif not booting then
		unread += 1
		refreshUnread()
	end
end

clearBtn.MouseButton1Click:Connect(function()
	for _, line in ipairs(logLines) do
		line:Destroy()
	end
	logLines = {}
	unread = 0
	refreshUnread()
	log("日志已清空", "warn")
end)

--=============================================================
-- 页面切换
--=============================================================
function showPage(key)
	logVisible = false
	logPane.Visible = false
	pageMain.Visible = (key == "main")
	pageSettings.Visible = (key == "settings")
	setNavActive(key)
	refreshUnread()
end

function openLog()
	logVisible = true
	unread = 0
	pageMain.Visible = false
	pageSettings.Visible = false
	logPane.Visible = true
	setNavActive("settings")
	refreshUnread()
	scrollLogToBottom()
end

function closeLog()
	showPage("settings")
end

function reloadPanel()
	log("正在重载面板...", "warn")
	showPage("settings")
	unread = 0
	refreshUnread()

	if type(API.OnReload) == "function" then
		local ok, err = pcall(API.OnReload)
		if not ok then
			log("重载回调出错：" .. tostring(err), "error")
		else
			log("自定义重载逻辑已执行", "success")
		end
	end

	task.delay(0.15, function()
		log("面板重载完成", "success")
	end)
end

backBtn.MouseButton1Click:Connect(function()
	closeLog()
end)

--=============================================================
-- 尺寸 / 适配
--=============================================================
local pos = Vector2.new(0, 0)
local winW, winH, winScale = CONFIG.Width, CONFIG.Height, 1
local minimized = false
local maximized = false
local restoreW, restoreH = CONFIG.Width, CONFIG.Height
local restorePos = Vector2.new(0, 0)
local maximizedW, maximizedH = CONFIG.Width, CONFIG.Height

local function viewportSize()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function clampPos(p)
	local vp = viewportSize()
	local w, h = winW * winScale, winH * winScale
	local margin = 6
	return Vector2.new(
		math.clamp(p.X, margin, math.max(margin, vp.X - w - margin)),
		math.clamp(p.Y, margin, math.max(margin, vp.Y - h - margin))
	)
end

local function sidebarWidth()
	return winW < 470 and 104 or 132
end

-- 卡片排列：宽 → 2×2，窄 → 1×4
local function updateLayout()
	local w = sidebarWidth()
	sidebar.Size = UDim2.new(0, w, 1, 0)
	contentHolder.Position = UDim2.new(0, w + 1, 0, 0)
	contentHolder.Size = UDim2.new(1, -(w + 1), 1, 0)

	local contentW = winW - w - 24
	if mainGrid then
		if contentW >= 310 then
			mainGrid.CellSize = UDim2.new(0.5, -4.5, 0, CONFIG.CardHeight)
			mainGrid.CellPadding = UDim2.new(0, 9, 0, 9)
		else
			mainGrid.CellSize = UDim2.new(1, 0, 0, CONFIG.CardHeight)
			mainGrid.CellPadding = UDim2.new(0, 0, 0, 8)
		end
	end
end

local function apply()
	window.Size = UDim2.fromOffset(winW, winH)
	window.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
	updateLayout()
end

local function relayout(center)
	local vp = viewportSize()
	local maxW = math.max(240, vp.X - 24)

	if minimized then
		winW, winH = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	else
		winW = math.min(CONFIG.Width, maxW)
		winH = CONFIG.Height
	end

	-- 高度不够时整体等比缩小（手机横屏等）
	winScale = math.clamp(math.min(1, (vp.Y - 40) / CONFIG.Height), 0.6, 1)
	uiScale.Scale = winScale

	if center then
		pos = Vector2.new((vp.X - winW * winScale) / 2, (vp.Y - winH * winScale) / 2)
	end

	if not minimized and not maximized then
		restoreW, restoreH = winW, winH
	end

	pos = clampPos(pos)
	apply()
end

--=============================================================
-- 拖动 / 缩放
--=============================================================
local dragState = nil
local resizeState = nil

local function bindDrag(object)
	object.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		dragState = { startInput = input.Position, origin = pos }
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragState = nil
				conn:Disconnect()
			end
		end)
	end)
end

-- 右下角缩放手柄：旋转 45° 的正方形被窗口裁掉，剩下的就是半透明直角三角形
local GRIP_SIZE = 30
local grip = new("TextButton", {
	Name = "Grip",
	Size = UDim2.fromOffset(GRIP_SIZE, GRIP_SIZE),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, 0, 1, 0),
	Rotation = 45,
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Parent = window,
})

grip.MouseEnter:Connect(function()
	TweenService:Create(grip, TweenInfo.new(0.12), { BackgroundTransparency = 0.58 }):Play()
end)
grip.MouseLeave:Connect(function()
	TweenService:Create(grip, TweenInfo.new(0.12), { BackgroundTransparency = 0.8 }):Play()
end)

grip.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if minimized then return end

	resizeState = { startInput = input.Position, w = winW, h = winH }
	local conn
	conn = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			resizeState = nil
			conn:Disconnect()
		end
	end)
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if dragState then
		local delta = input.Position - dragState.startInput
		pos = clampPos(dragState.origin + delta)
		apply()
	elseif resizeState then
		local vp = viewportSize()
		local delta = (input.Position - resizeState.startInput) / winScale
		local maxW = (vp.X - 12) / winScale
		local maxH = (vp.Y - 12) / winScale

		winW = math.clamp(resizeState.w + delta.X, math.min(CONFIG.MinWidth, maxW), maxW)
		winH = math.clamp(resizeState.h + delta.Y, math.min(CONFIG.MinHeight, maxH), maxH)
		winW = math.floor(winW)
		winH = math.floor(winH)
		maximized = false
		restoreW, restoreH = winW, winH
		pos = clampPos(pos)
		apply()
	end
end)

bindDrag(header)
bindDrag(logo)
bindDrag(titleLabel)
bindDrag(subtitleLabel)
bindDrag(dragHandle)

--=============================================================
-- 关闭 / 唤回
--=============================================================
local pill = new("TextButton", {
	Name = "Reopen",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(112, 32),
	BackgroundColor3 = THEME.Header,
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

pill.MouseButton1Click:Connect(function()
	window.Visible = true
	pill.Visible = false
end)

--=============================================================
-- 最小化 / 最大化
--=============================================================
local function setMinimized(state)
	minimized = state

	logo.Visible = not state
	titleLabel.Visible = not state
	subtitleLabel.Visible = not state
	clockLabel.Visible = state
	body.Visible = not state
	bottomBar.Visible = not state
	grip.Visible = not state
	minDot.Visible = not state

	local headerH = state and CONFIG.MinimizedHeight or CONFIG.HeaderHeight
	TweenService:Create(header, TweenInfo.new(0.18), { Size = UDim2.new(1, 0, 0, headerH) }):Play()

	if state then
		winW, winH = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	elseif maximized then
		winW, winH = maximizedW, maximizedH
	else
		winW, winH = restoreW, restoreH
	end

	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(window, info, { Size = UDim2.fromOffset(winW, winH) }):Play()

	pos = clampPos(pos)
	TweenService:Create(window, info, { Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y)) }):Play()

	updateLayout()
end

local function setMaximized(state)
	local vp = viewportSize()

	if state then
		if not maximized then
			restoreW, restoreH = winW, winH
			restorePos = pos
		end
		maximized = true
		winW = math.floor((vp.X - 24) / winScale)
		winH = math.floor((vp.Y - 24) / winScale)
		maximizedW, maximizedH = winW, winH
		pos = Vector2.new((vp.X - winW * winScale) / 2, (vp.Y - winH * winScale) / 2)
	else
		maximized = false
		winW = math.min(restoreW, (vp.X - 24) / winScale)
		winH = math.min(restoreH, (vp.Y - 24) / winScale)
		pos = clampPos(restorePos)
	end

	apply()
end

closeDot.MouseButton1Click:Connect(function()
	window.Visible = false
	pill.Visible = true
end)

minDot.MouseButton1Click:Connect(function()
	setMinimized(true)
end)

maxDot.MouseButton1Click:Connect(function()
	if minimized then
		setMinimized(false)
	else
		setMaximized(not maximized)
	end
end)

task.spawn(function()
	while gui.Parent do
		clockLabel.Text = os.date("%H:%M:%S")
		task.wait(0.5)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F2 then
		window.Visible = not window.Visible
		pill.Visible = not window.Visible
	end
end)

--=============================================================
-- 实时数据
--=============================================================
local frames, elapsed = 0, 0

RunService.RenderStepped:Connect(function(dt)
	-- 彩虹描边缓慢旋转
	if rainbowGrad then
		rainbowGrad.Rotation = (rainbowGrad.Rotation + dt * 42) % 360
	end

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

	frames, elapsed = 0, 0
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if not maximized and not minimized then
			relayout(false)
		end
	end)
end

--=============================================================
-- 对外接口
--=============================================================
function API:Log(message, level)
	log(message, level)
end

function API:SetVisible(state)
	window.Visible = state and true or false
	pill.Visible = not window.Visible
end

function API:OpenLog()
	window.Visible = true
	pill.Visible = false
	openLog()
end

function API:Reload()
	reloadPanel()
end

API.Theme = THEME
API.Window = window

_G.DebugUI = API

--=============================================================
-- 初始化
--=============================================================
relayout(true)
showPage("main")

log("调试面板已启动", "success")
log("拖动标题栏或底部小白条移动窗口，右下三角缩放", "info")
log("设置 → 日志 查看输出记录", "info")
task.delay(1, function()
	log("F2 可快速隐藏 / 显示面板", "info")
end)
task.delay(2, function()
	booting = false
end)
