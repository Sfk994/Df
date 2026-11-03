--[[
	MacOS_Window.lua —— macOS Finder 风格「文件管理器」窗口

	功能：
	  · 单窗口：半透明毛玻璃质感侧栏 + 内容区（Roblox 无法真模糊，用半透明叠层模拟）
	  · 无独立标题栏：顶部区域即拖动区，左上角交通灯（纯色圆点）
	  · 侧边栏目录列表：图标 + 名字默认黑色，选中后整体变蓝并带浅灰圆角底
	  · 内容区标题随所选目录同步 + 4 个空白应用占位
	  · 返回/前进箭头 = 目录选择历史的前后切换
	  · 占位图标随窗口宽度自动排列：宽 → 一行 4 个(4x1)，窄 → 一列 4 个(1x4)
	  · 玩家信息：在线玩家列表 → 详情页（游戏名/账户名/注册日期/账号年龄/坐标/距离/头像/立绘）
	          并可一键传送到该玩家（客户端 PivotTo，受游戏反作弊限制）
	  · 红/黄键 = 关闭（变成“打开窗口”按钮），绿键 / 双击顶部 = 全屏
	  · 右下角缩放，最小 380x320

	安装：
	  StarterPlayer > StarterPlayerScripts 里新建 LocalScript，粘贴本文件全部内容即可。

	字体：使用 Roblox 内置 Gotham（最接近 SF Pro）。
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=====================================================================
-- 配置
--=====================================================================

local Config = {
	Width = 860,
	Height = 560,
	MinWidth = 380,
	MinHeight = 320,
	SidebarWidth = 200,
	HeaderHeight = 46,
	CornerRadius = 12,
}

local C = {
	window = Color3.fromRGB(246, 246, 248),
	sidebar = Color3.fromRGB(255, 255, 255),
	content = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(29, 29, 31),
	dim = Color3.fromRGB(138, 138, 142),
	blue = Color3.fromRGB(0, 122, 255),
	red = Color3.fromRGB(255, 95, 86),
	yellow = Color3.fromRGB(254, 188, 46),
	green = Color3.fromRGB(40, 200, 64),
	appTop = Color3.fromRGB(233, 236, 242),
	appBottom = Color3.fromRGB(208, 214, 225),
}

local EASE = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local EASE_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local EASE_IN = TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

--=====================================================================
-- 小工具
--=====================================================================

local function new(className, props, children)
	local obj = Instance.new(className)
	local parent = nil
	if props then
		parent = props.Parent
		for key, value in pairs(props) do
			if key ~= "Parent" then
				obj[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = obj
		end
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function tween(obj, info, props)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function round(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function isClick(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

--=====================================================================
-- 根节点
--=====================================================================

local gui = new("ScreenGui", {
	Name = "FileManagerWindow",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 50,
	Parent = playerGui,
})

--=====================================================================
-- 窗口骨架
--=====================================================================

local viewport = viewportSize()
local startWidth = math.min(Config.Width, viewport.X - 24)
local startHeight = math.min(Config.Height, viewport.Y - 48)
local centerX = math.floor((viewport.X - startWidth) / 2)
local centerY = math.floor((viewport.Y - startHeight) / 2)

local window = new("CanvasGroup", {
	Name = "Window",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromOffset(centerX, centerY + 28), -- 入场动画起点：略下移
	Size = UDim2.fromOffset(startWidth, startHeight),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	BorderSizePixel = 0,
	Parent = gui,
})

new("UISizeConstraint", {
	MinSize = Vector2.new(Config.MinWidth, Config.MinHeight),
	Parent = window,
})

-- 柔和投影（两层）
for index, layer in ipairs({
	{ pad = 14, transparency = 0.9 },
	{ pad = 34, transparency = 0.958 },
}) do
	local s = new("Frame", {
		Name = "Shadow" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, layer.pad, 1, layer.pad),
		BackgroundColor3 = Color3.fromRGB(14, 14, 22),
		BackgroundTransparency = layer.transparency,
		BorderSizePixel = 0,
		ZIndex = 4 - index,
		Parent = window,
	})
	round(s, Config.CornerRadius + layer.pad * 0.35)
end

-- 窗口主体
local body = new("Frame", {
	Name = "Body",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.06, -- 近实心，不直接透出游戏世界，靠渐变+高光营造磨砂感
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 8,
	Parent = window,
})
round(body, Config.CornerRadius)
new("UIStroke", {
	Color = Color3.fromRGB(255, 255, 255),
	Thickness = 1,
	Transparency = 0.5,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = body,
})

-- 毛玻璃模拟：白 → 极淡蓝 渐变（Roblox 无真模糊，靠半透明 + 渐变 + 高光还原磨砂感）
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(246, 248, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(228, 236, 250)),
	}),
	Rotation = 90,
	Parent = body,
})

-- 斜向高光条（模拟玻璃反光）
new("Frame", {
	Name = "Sheen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.32, 0.5),
	Size = UDim2.fromScale(0.55, 1.7),
	Rotation = 22,
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	ZIndex = 7,
	Parent = body,
})

--=====================================================================
-- 顶部拖动条（覆盖整窗顶部，交通灯浮在上面）
--=====================================================================

local dragStrip = new("Frame", {
	Name = "DragStrip",
	Size = UDim2.new(1, 0, 0, Config.HeaderHeight),
	BackgroundTransparency = 1,
	ZIndex = 40,
	Active = true,
	Parent = body,
})

--=====================================================================
-- 交通灯（纯色圆点，无图标）
--=====================================================================

local lights = new("Frame", {
	Name = "TrafficLights",
	Position = UDim2.fromOffset(26, 26),
	Size = UDim2.fromOffset(82, 22),
	BackgroundTransparency = 1,
	ZIndex = 42,
	Parent = dragStrip,
})

local trafficColors = { C.red, C.yellow, C.green }
local trafficGlyphs = { "×", "−", "□" }
local trafficFrames = {}

for index = 1, 3 do
	local base = trafficColors[index]
	local hit = new("TextButton", {
		Name = "Light" .. index,
		Position = UDim2.fromOffset((index - 1) * 22, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 42,
		Parent = lights,
	})

	local dot = new("Frame", {
		Name = "Dot",
		Position = UDim2.fromOffset(4.5, 4.5),
		Size = UDim2.fromOffset(13, 13),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		ZIndex = 43,
		Parent = hit,
	})
	round(dot, 7)
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.88,
		Thickness = 1,
		Parent = dot,
	})

	-- 图例文字：× / − / □，悬停或按下时显示
	local glyph = new("TextLabel", {
		Name = "Glyph",
		Text = trafficGlyphs[index],
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextColor3 = base:Lerp(Color3.new(0, 0, 0), 0.5),
		TextTransparency = 1,
		Position = UDim2.fromOffset(0, index == 2 and -1 or 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 44,
		Parent = dot,
	})

	hit.MouseEnter:Connect(function()
		glyph.TextTransparency = 0
	end)
	hit.MouseLeave:Connect(function()
		glyph.TextTransparency = 1
	end)
	hit.InputBegan:Connect(function(input)
		if isClick(input) then
			glyph.TextTransparency = 0
		end
	end)
	hit.InputEnded:Connect(function(input)
		if isClick(input) then
			glyph.TextTransparency = 1
		end
	end)

	trafficFrames[index] = hit
end

--=====================================================================
-- 侧边栏（半透明毛玻璃质感）
--=====================================================================

local sidebar = new("Frame", {
	Name = "Sidebar",
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(0, Config.SidebarWidth, 1, -20),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	ZIndex = 10,
	Parent = body,
})
round(sidebar, 12)

-- 白 → 非常淡的蓝 渐变（悬浮面板质感，无描边）
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(228, 239, 255)),
	}),
	Rotation = 90,
	Parent = sidebar,
})

--=====================================================================
-- 侧边栏图标（英文首字母缩写，随选中变色）
--=====================================================================

local function makeAbbr(abbr, parent)
	local label = new("TextLabel", {
		Name = "Abbr",
		Text = abbr,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(2, 0),
		Size = UDim2.fromOffset(22, 30),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 13,
		Parent = parent,
	})
	return label, function(c)
		label.TextColor3 = c
	end
end

--=====================================================================
-- 侧边栏目录列表
--=====================================================================

local NAV = {
	{ abbr = "Re", name = "最近使用" },
	{ abbr = "Sh", name = "共享" },
	{ header = "个人收藏" },
	{ abbr = "Ap", name = "应用程序" },
	{ abbr = "De", name = "桌面" },
	{ abbr = "Do", name = "文稿" },
	{ abbr = "Dl", name = "下载" },
	{ abbr = "Mo", name = "影片" },
	{ abbr = "Pi", name = "图片" },
	{ abbr = "Pr", name = "进行中项目" },
	{ abbr = "Dv", name = "Dev" },
	{ header = "位置" },
	{ abbr = "Pl", name = "玩家信息" },
	{ abbr = "iC", name = "iCloud 云盘" },
}

local navList = new("ScrollingFrame", {
	Name = "NavList",
	Position = UDim2.fromOffset(0, Config.HeaderHeight + 6),
	Size = UDim2.new(1, 0, 1, -(Config.HeaderHeight + 6)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageTransparency = 0.7,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 12,
	Parent = sidebar,
})
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = navList })
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	Parent = navList,
})

local navRows = {}
local selectedIndex = nil
local history = {}
local historyIndex = 0
local titleLabel
local backBtn
local fwdBtn
local selectFolder = function() end -- 内容区定义后赋值

-- 玩家信息：详情页状态（内容区定义后赋值）
local playerDetailOpen = false
local playerDetailTitle = nil
local closePlayerDetail

local function refreshHeader()
	if titleLabel and selectedIndex then
		if playerDetailOpen and playerDetailTitle then
			titleLabel.Text = playerDetailTitle
		else
			titleLabel.Text = navRows[selectedIndex].name
		end
	end
	if backBtn then
		backBtn.TextTransparency = ((historyIndex > 1) or playerDetailOpen) and 0.45 or 0.72
	end
	if fwdBtn then
		fwdBtn.TextTransparency = ((not playerDetailOpen) and historyIndex < #history) and 0.45 or 0.72
	end
end

local function applySelection(index)
	selectedIndex = index
	for i, item in ipairs(navRows) do
		local on = (i == index)
		item.row.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		item.row.BackgroundTransparency = on and 0.94 or 1
		item.label.TextColor3 = on and C.blue or C.text
		item.setColor(on and C.blue or C.text)
	end
	refreshHeader()
	if selectFolder then
		selectFolder(navRows[index].name)
	end
end

local function goTo(index, push)
	if push then
		-- 截断前进历史
		local newHistory = {}
		for i = 1, historyIndex do
			newHistory[i] = history[i]
		end
		newHistory[#newHistory + 1] = index
		history = newHistory
		historyIndex = #history
	end
	applySelection(index)
end

local order = 0
for _, def in ipairs(NAV) do
	order = order + 1
	if def.header then
		new("TextLabel", {
			Name = "Section",
			Text = def.header,
			TextSize = 11,
			Font = Enum.Font.GothamMedium,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 12,
			Parent = navList,
		})
	else
		local row = new("TextButton", {
			Name = "Nav_" .. def.name,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 12,
			Parent = navList,
		})
		round(row, 6)

		local _, setIconColor = makeAbbr(def.abbr, row)

		local label = new("TextLabel", {
			Name = "Label",
			Text = def.name,
			TextSize = 13,
			Font = Enum.Font.GothamMedium,
			TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(1, -40, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 13,
			Parent = row,
		})

		local entry = { row = row, label = label, name = def.name, setColor = setIconColor }
		navRows[#navRows + 1] = entry

		row.Activated:Connect(function()
			goTo(table.find(navRows, entry), true)
		end)
	end
end

-- 默认选中「下载」
for i, item in ipairs(navRows) do
	if item.label.Text == "下载" then
		goTo(i, true)
		break
	end
end

--=====================================================================
-- 内容区
--=====================================================================

local content = new("Frame", {
	Name = "Content",
	Position = UDim2.fromOffset(Config.SidebarWidth + 18, 10),
	Size = UDim2.new(1, -(Config.SidebarWidth + 28), 1, -20),
	BackgroundColor3 = C.content,
	BackgroundTransparency = 0.22,
	BorderSizePixel = 0,
	ZIndex = 10,
	Parent = body,
})
round(content, 12)

-- 内容区顶栏：标题随所选目录同步；返回/前进按钮置于顶部拖动条上以便点击
titleLabel = new("TextLabel", {
	Name = "Title",
	Text = "下载",
	TextSize = 14,
	Font = Enum.Font.GothamSemibold,
	TextColor3 = C.text,
	TextTransparency = 0.2,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Position = UDim2.fromOffset(74, 0),
	Size = UDim2.new(1, -90, 0, Config.HeaderHeight),
	BackgroundTransparency = 1,
	ZIndex = 12,
	Parent = content,
})

backBtn = new("TextButton", {
	Name = "Back",
	Text = "‹",
	TextSize = 24,
	Font = Enum.Font.Gotham,
	TextColor3 = C.text,
	TextTransparency = 0.72,
	Position = UDim2.fromOffset(Config.SidebarWidth + 18 + 14, 0),
	Size = UDim2.fromOffset(26, Config.HeaderHeight),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 43,
	Parent = dragStrip,
})
fwdBtn = new("TextButton", {
	Name = "Forward",
	Text = "›",
	TextSize = 24,
	Font = Enum.Font.Gotham,
	TextColor3 = C.text,
	TextTransparency = 0.72,
	Position = UDim2.fromOffset(Config.SidebarWidth + 18 + 40, 0),
	Size = UDim2.fromOffset(26, Config.HeaderHeight),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 43,
	Parent = dragStrip,
})

backBtn.Activated:Connect(function()
	if playerDetailOpen and closePlayerDetail then
		closePlayerDetail()
		return
	end
	if historyIndex > 1 then
		historyIndex = historyIndex - 1
		applySelection(history[historyIndex])
	end
end)
fwdBtn.Activated:Connect(function()
	if playerDetailOpen then
		return
	end
	if historyIndex < #history then
		historyIndex = historyIndex + 1
		applySelection(history[historyIndex])
	end
end)

-- 网格区域
local gridArea = new("Frame", {
	Name = "GridArea",
	Position = UDim2.new(0, 0, 0, Config.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -Config.HeaderHeight),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 11,
	Parent = content,
})

local grid = new("Frame", {
	Name = "Grid",
	Position = UDim2.fromOffset(20, 8),
	Size = UDim2.new(1, -40, 1, -28),
	BackgroundTransparency = 1,
	ZIndex = 12,
	Parent = gridArea,
})

local gridLayout = new("UIGridLayout", {
	CellPadding = UDim2.fromOffset(14, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Parent = grid,
})

-- 4 个空白应用占位
for index = 1, 4 do
	local app = new("Frame", {
		Name = "App" .. index,
		BackgroundColor3 = C.appTop,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 13,
		Parent = grid,
	})
	round(app, 18)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.appTop),
			ColorSequenceKeypoint.new(1, C.appBottom),
		}),
		Rotation = 90,
		Parent = app,
	})
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.93,
		Thickness = 1,
		Parent = app,
	})
end

-- 占位图标随窗口宽度自动排列：1x4 ↔ 4x1
local function updateGrid()
	local w = grid.AbsoluteSize.X
	if w <= 0 then
		return
	end
	local gap = 14
	local cols = math.clamp(math.floor((w + gap) / (96 + gap)), 1, 4)
	local cell = math.min(96, math.floor((w - (cols - 1) * gap) / cols))
	gridLayout.CellSize = UDim2.fromOffset(cell, cell)
end

--=====================================================================
-- iCloud 云盘：GitHub 文件列表（竖条单行排列）
--=====================================================================

local REPO_API = "https://data.jsdelivr.com/v1/packages/gh/Sfk994/Df"
local RAW_BASE = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/"

local function formatSize(bytes)
	if bytes >= 1048576 then
		return string.format("%.1f MB", bytes / 1048576)
	elseif bytes >= 1024 then
		return string.format("%.1f KB", bytes / 1024)
	end
	return tostring(bytes) .. " B"
end

local fileArea = new("ScrollingFrame", {
	Name = "FileArea",
	Position = UDim2.new(0, 0, 0, Config.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -Config.HeaderHeight),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageTransparency = 0.6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false,
	ZIndex = 11,
	Parent = content,
})
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = fileArea })

-- 列表头：名称 | 类型 | 大小
local head = new("Frame", {
	Name = "Head",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	ZIndex = 12,
	Parent = fileArea,
})
new("TextLabel", {
	Text = "名称",
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -226, 1, 0),
	BackgroundTransparency = 1,
	Parent = head,
})
new("TextLabel", {
	Text = "类型",
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(1, -150, 0, 0),
	Size = UDim2.fromOffset(62, 30),
	BackgroundTransparency = 1,
	Parent = head,
})
new("TextLabel", {
	Text = "大小",
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(1, -84, 0, 0),
	Size = UDim2.fromOffset(68, 30),
	BackgroundTransparency = 1,
	Parent = head,
})

local statusLabel = new("TextButton", {
	Name = "Status",
	Text = "",
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Position = UDim2.fromOffset(20, 0),
	Size = UDim2.new(1, -40, 0, 28),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	LayoutOrder = 2,
	ZIndex = 12,
	Parent = fileArea,
})

local fileRows = {}
local filesLoaded = false

local function clearFileRows()
	for _, r in ipairs(fileRows) do
		r.row:Destroy()
	end
	fileRows = {}
end

-- 双击运行：loadstring(game:HttpGet(rawUrl))()
local function runFile(rawUrl)
	task.spawn(function()
		local ok, err = pcall(function()
			local source = game:HttpGet(rawUrl)
			local fn = loadstring(source)
			if fn then
				fn()
			else
				warn("[文件管理器] loadstring 失败：", rawUrl)
			end
		end)
		if not ok then
			warn("[文件管理器] 运行失败：", err)
		end
	end)
end

local recordRecent -- 前置声明：双击执行文件后记录到「最近使用」

local function addFileRow(item, layoutOrder)
	local row = new("TextButton", {
		Name = "File_" .. item.name,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = C.blue,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = layoutOrder,
		ZIndex = 12,
		Parent = fileArea,
	})
	round(row, 6)

	-- 底部分隔线（细淡黑色，左右留白）
	new("Frame", {
		Name = "Divider",
		Position = UDim2.new(0, 16, 1, -1),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 14,
		Parent = row,
	})

	-- 文件图标（Frame 拼绘的小文档）
	local ic = new("Frame", {
		Name = "FileIcon",
		Position = UDim2.fromOffset(18, 9),
		Size = UDim2.fromOffset(16, 18),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local sheet = new("Frame", {
		Position = UDim2.fromOffset(2, 1),
		Size = UDim2.fromOffset(12, 16),
		BackgroundTransparency = 1,
		ZIndex = 14,
		Parent = ic,
	})
	round(sheet, 2)
	local iconStroke = new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.55,
		Thickness = 1.2,
		Parent = sheet,
	})
	local fold = new("Frame", {
		Position = UDim2.fromOffset(9, 1),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.55,
		ZIndex = 15,
		Parent = ic,
	})
	round(fold, 1)

	local nameLabel = new("TextLabel", {
		Name = "Name",
		Text = item.name,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -192, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local typeLabel = new("TextLabel", {
		Name = "Type",
		Text = tostring(item.type or "file"),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -150, 0, 0),
		Size = UDim2.fromOffset(62, 34),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local sizeLabel = new("TextLabel", {
		Name = "Size",
		Text = formatSize(item.size or 0),
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -84, 0, 0),
		Size = UDim2.fromOffset(68, 34),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})

	local function setRowSelected(on)
		row.BackgroundTransparency = on and 0 or 1
		nameLabel.TextColor3 = on and Color3.new(1, 1, 1) or C.text
		typeLabel.TextColor3 = on and Color3.new(1, 1, 1) or C.dim
		sizeLabel.TextColor3 = on and Color3.new(1, 1, 1) or C.dim
		if on then
			iconStroke.Color = Color3.new(1, 1, 1)
			iconStroke.Transparency = 0
			fold.BackgroundColor3 = Color3.new(1, 1, 1)
			fold.BackgroundTransparency = 0
		else
			iconStroke.Color = Color3.fromRGB(0, 0, 0)
			iconStroke.Transparency = 0.55
			fold.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			fold.BackgroundTransparency = 0.55
		end
	end

	-- 单击选中，双击执行（Activated：按下和抬起都在行内才触发，滚动列表不会误触）
	local lastClick = 0
	row.Activated:Connect(function()
		for _, r in ipairs(fileRows) do
			r.setRowSelected(false)
		end
		setRowSelected(true)
		local now = tick()
		if now - lastClick < 0.45 and item.type == "file" then
			runFile(item.rawUrl)
			recordRecent(item.name)
		end
		lastClick = now
	end)

	local entry = { row = row, setRowSelected = setRowSelected }
	fileRows[#fileRows + 1] = entry
	return entry
end

local function loadFileList()
	clearFileRows()
	statusLabel.Visible = true
	statusLabel.Text = "正在加载文件列表…"
	task.spawn(function()
		-- 第一步：拿到版本 self 链接
		local ok1, pkg = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(REPO_API))
		end)
		if not ok1 or type(pkg) ~= "table" then
			local err = tostring(pkg)
			if string.find(err, "not enabled", 1, true) or string.find(err, "HttpEnabled", 1, true) then
				statusLabel.Text = "加载失败：此游戏未开启 HTTP 请求（HttpService），请在游戏设置中启用后重试"
			elseif string.find(err, "429", 1, true) or string.find(err, "403", 1, true) then
				statusLabel.Text = "加载失败：请求被拒绝（可能限流），点此重试"
			else
				statusLabel.Text = "加载失败：" .. err .. "（点此重试）"
			end
			filesLoaded = false -- 允许重试
			return
		end

		local selfUrl = nil
		if pkg.versions and pkg.versions[1] and pkg.versions[1].links and pkg.versions[1].links.self then
			selfUrl = pkg.versions[1].links.self
		end
		if not selfUrl then
			statusLabel.Text = "加载失败：未找到版本信息（点此重试）"
			filesLoaded = false
			return
		end

		-- 第二步：用 self 链接获取文件列表
		local ok2, data = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(selfUrl))
		end)
		if not ok2 or type(data) ~= "table" or type(data.files) ~= "table" then
			local err = tostring(data)
			if string.find(err, "not enabled", 1, true) or string.find(err, "HttpEnabled", 1, true) then
				statusLabel.Text = "加载失败：此游戏未开启 HTTP 请求（HttpService），请在游戏设置中启用后重试"
			elseif string.find(err, "429", 1, true) or string.find(err, "403", 1, true) then
				statusLabel.Text = "加载失败：请求被拒绝（可能限流），点此重试"
			else
				statusLabel.Text = "加载失败：" .. err .. "（点此重试）"
			end
			filesLoaded = false
			return
		end

		local files = {}
		for _, item in ipairs(data.files) do
			if item.name then
				item.rawUrl = RAW_BASE .. tostring(item.name)
				files[#files + 1] = item
			end
		end
		-- 保持 jsDelivr 返回顺序（已按名称排序）
		table.sort(files, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)

		if #files == 0 then
			statusLabel.Text = "目录为空"
			return
		end

		statusLabel.Visible = false

		-- 渲染：名称 | 类型 | 大小
		for i, item in ipairs(files) do
			addFileRow(item, i + 2)
		end
	end)
end

-- 加载失败后点击状态文字重试
statusLabel.InputBegan:Connect(function(input)
	if not isClick(input) then
		return
	end
	if not filesLoaded then
		loadFileList()
	end
end)

--=====================================================================
-- 最近使用：文件网格（脚本文件 = 黑底绿框 + 类型字，双击执行）
--=====================================================================

local recentGridArea = new("Frame", {
	Name = "RecentArea",
	Position = UDim2.new(0, 0, 0, Config.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -Config.HeaderHeight),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Visible = false,
	ZIndex = 11,
	Parent = content,
})

local recentGrid = new("Frame", {
	Name = "RecentGrid",
	Position = UDim2.fromOffset(20, 8),
	Size = UDim2.new(1, -40, 1, -28),
	BackgroundTransparency = 1,
	ZIndex = 12,
	Parent = recentGridArea,
})

local recentLayout = new("UIGridLayout", {
	CellPadding = UDim2.fromOffset(14, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Parent = recentGrid,
})

-- 预置几个脚本文件作为初始「最近使用」
local recentFiles = { "B.lua", "box.lua", "C.lua", "fly.lua" }
local recentCells = {}

local function isScript(name)
	return string.sub(name, -4) == ".lua"
end

local function fileTypeLabel(name)
	local ext = string.match(name or "", "%.(%w+)$")
	if ext then
		return string.upper(ext)
	end
	return "FILE"
end

local function clearRecent()
	for _, c in ipairs(recentCells) do
		c:Destroy()
	end
	recentCells = {}
end

local function makeRecentCell(name, order)
	local cell = new("Frame", {
		Name = "Recent_" .. name,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 13,
		Parent = recentGrid,
	})

	local icon = new("TextButton", {
		Name = "Icon",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 1, -24),
		BackgroundColor3 = Color3.fromRGB(20, 20, 22),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 14,
		Parent = cell,
	})
	round(icon, 17)

	if isScript(name) then
		-- 脚本文件：黑底 + 绿色边框 + 类型字
		new("UIStroke", {
			Color = Color3.fromRGB(40, 200, 64),
			Thickness = 1.6,
			Parent = icon,
		})
		new("TextLabel", {
			Name = "Type",
			Text = fileTypeLabel(name),
			TextSize = 13,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(120, 255, 150),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 15,
			Parent = icon,
		})
	else
		-- 非脚本文件：浅灰渐变块
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C.appTop),
				ColorSequenceKeypoint.new(1, C.appBottom),
			}),
			Rotation = 90,
			Parent = icon,
		})
		new("UIStroke", {
			Color = Color3.fromRGB(0, 0, 0),
			Transparency = 0.93,
			Thickness = 1,
			Parent = icon,
		})
		new("TextLabel", {
			Name = "Type",
			Text = fileTypeLabel(name),
			TextSize = 12,
			Font = Enum.Font.GothamBold,
			TextColor3 = C.dim,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 15,
			Parent = icon,
		})
	end

	local nameLabel = new("TextLabel", {
		Name = "Name",
		Text = name,
		TextSize = 11,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 0, 1, -22),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 14,
		Parent = cell,
	})

	-- 双击执行（仅脚本文件）
	local lastClick = 0
	icon.Activated:Connect(function()
		local now = tick()
		if now - lastClick < 0.45 and isScript(name) then
			runFile(RAW_BASE .. name)
			recordRecent(name)
		end
		lastClick = now
	end)

	recentCells[#recentCells + 1] = cell
end

local function renderRecent()
	clearRecent()
	for i, name in ipairs(recentFiles) do
		makeRecentCell(name, i)
	end
end

recordRecent = function(name)
	local newList = { name }
	for _, n in ipairs(recentFiles) do
		if n ~= name then
			newList[#newList + 1] = n
		end
	end
	while #newList > 8 do
		newList[#newList] = nil
	end
	recentFiles = newList
	renderRecent()
end

--=====================================================================
-- 玩家信息：在线玩家列表
--=====================================================================

local playerArea = new("ScrollingFrame", {
	Name = "PlayerArea",
	Position = UDim2.new(0, 0, 0, Config.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -Config.HeaderHeight),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageTransparency = 0.6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false,
	ZIndex = 11,
	Parent = content,
})
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = playerArea })

-- 列表头：玩家 | 距离 | 状态
local playerHead = new("Frame", {
	Name = "Head",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	ZIndex = 12,
	Parent = playerArea,
})
local function playerHeadLabel(text, position, size, align)
	return new("TextLabel", {
		Text = text,
		TextSize = 11,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
		TextXAlignment = align,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = playerHead,
	})
end
playerHeadLabel("玩家", UDim2.fromOffset(18, 0), UDim2.new(1, -214, 1, 0), Enum.TextXAlignment.Left)
local playerHeadDist = playerHeadLabel("距离", UDim2.new(1, -196, 0, 0), UDim2.fromOffset(100, 30), Enum.TextXAlignment.Right)
local playerHeadState = playerHeadLabel("状态", UDim2.new(1, -96, 0, 0), UDim2.fromOffset(78, 30), Enum.TextXAlignment.Right)

-- 头像缓存与加载（GetUserThumbnailAsync 会阻塞，放 task.spawn）
local thumbCache = {}

local function userThumb(userId, kind, size)
	local key = tostring(userId) .. "_" .. kind.Name .. "_" .. size.Name
	local cached = thumbCache[key]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached
	end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(userId, kind, size)
	end)
	if ok and type(url) == "string" and url ~= "" then
		thumbCache[key] = url
		return url
	end
	thumbCache[key] = false
	return nil
end

local function makeAvatar(parent, sizePx, x, y, name)
	local holder = new("Frame", {
		Name = "Avatar",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(sizePx, sizePx),
		BackgroundColor3 = Color3.fromRGB(233, 237, 245),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 13,
		Parent = parent,
	})
	round(holder, math.floor(sizePx / 2))
	local img = new("ImageLabel", {
		Name = "Image",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 14,
		Parent = holder,
	})
	new("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.92,
		Thickness = 1,
		Parent = holder,
	})
	local initial = new("TextLabel", {
		Name = "Initial",
		Text = string.upper(string.sub(name or "", 1, 1)),
		TextSize = math.floor(sizePx * 0.42),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(122, 127, 138),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 14,
		Parent = holder,
	})
	return holder, img, initial
end

local function loadAvatar(img, initial, plr, kind, size, delay)
	task.spawn(function()
		if delay and delay > 0 then
			task.wait(delay)
		end
		local url = userThumb(plr.UserId, kind, size)
		if url and img.Parent then
			img.Image = url
			initial.Visible = false
		end
	end)
end

local function rootOf(plr)
	local char = plr.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function positionOf(plr)
	local root = rootOf(plr)
	if root then
		return root.Position
	end
	return nil
end

local function distanceTo(plr)
	if plr == player then
		return 0
	end
	local a = rootOf(player)
	local b = rootOf(plr)
	if a and b then
		return math.floor((a.Position - b.Position).Magnitude + 0.5)
	end
	return nil
end

--=====================================================================
-- 玩家信息：详情页
--=====================================================================

local detailArea = new("ScrollingFrame", {
	Name = "PlayerDetail",
	Position = UDim2.new(0, 0, 0, Config.HeaderHeight),
	Size = UDim2.new(1, 0, 1, -Config.HeaderHeight),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageTransparency = 0.6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false,
	ZIndex = 11,
	Parent = content,
})

local detailInner = new("Frame", {
	Name = "Inner",
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -32, 0, 0),
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
	Parent = detailArea,
})
new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim2.fromOffset(0, 10),
	Parent = detailInner,
})

-- 顶部：头像 + 游戏名 + 账户名
local dHead = new("Frame", {
	Name = "Head",
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	ZIndex = 12,
	Parent = detailInner,
})
local dFaceHolder, dFaceImage, dFaceInitial = makeAvatar(dHead, 56, 0, 0, "")
local dName = new("TextLabel", {
	Name = "DisplayName",
	Text = "",
	TextSize = 17,
	Font = Enum.Font.GothamSemibold,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(68, 4),
	Size = UDim2.new(1, -68, 0, 22),
	BackgroundTransparency = 1,
	ZIndex = 13,
	Parent = dHead,
})
local dSub = new("TextLabel", {
	Name = "AccountName",
	Text = "",
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(68, 29),
	Size = UDim2.new(1, -68, 0, 18),
	BackgroundTransparency = 1,
	ZIndex = 13,
	Parent = dHead,
})

-- 立绘卡片
local dHero = new("Frame", {
	Name = "Hero",
	Size = UDim2.new(1, 0, 0, 200),
	BackgroundColor3 = Color3.fromRGB(246, 249, 255),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	LayoutOrder = 2,
	ZIndex = 12,
	Parent = detailInner,
})
round(dHero, 14)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(249, 251, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(229, 237, 252)),
	}),
	Rotation = 90,
	Parent = dHero,
})
new("UIStroke", {
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.93,
	Thickness = 1,
	Parent = dHero,
})
local dBody = new("ImageLabel", {
	Name = "Body",
	Position = UDim2.fromOffset(14, 6),
	Size = UDim2.new(1, -28, 1, -12),
	BackgroundTransparency = 1,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 13,
	Parent = dHero,
})
local dPill = new("TextLabel", {
	Name = "DistancePill",
	Text = "",
	TextSize = 11,
	Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.fromRGB(58, 74, 104),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.18,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Position = UDim2.new(0, 12, 1, -36),
	Size = UDim2.fromOffset(116, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	ZIndex = 15,
	Parent = dHero,
})
round(dPill, 12)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	Parent = dPill,
})
new("UIStroke", {
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.94,
	Thickness = 1,
	Parent = dPill,
})

-- 信息卡片
local dCard = new("Frame", {
	Name = "Info",
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 3,
	ZIndex = 12,
	Parent = detailInner,
})
round(dCard, 12)
new("UIStroke", {
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.93,
	Thickness = 1,
	Parent = dCard,
})
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = dCard })

local infoValues = {}
local function addInfoRow(labelText, order, isLast)
	local row = new("Frame", {
		Name = "Row" .. order,
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 13,
		Parent = dCard,
	})
	new("TextLabel", {
		Text = labelText,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 14,
		Parent = row,
	})
	local value = new("TextLabel", {
		Text = "",
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 14,
		Parent = row,
	})
	if not isLast then
		new("Frame", {
			Position = UDim2.new(0, 14, 1, -1),
			Size = UDim2.new(1, -28, 0, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			ZIndex = 14,
			Parent = row,
		})
	end
	return value
end

infoValues.created = addInfoRow("账号创建时间", 1, false)
infoValues.age = addInfoRow("账号存在时间", 2, false)
infoValues.pos = addInfoRow("坐标 (X, Y, Z)", 3, false)
infoValues.dist = addInfoRow("与你的距离", 4, true)

-- 传送按钮
local tpButton = new("TextButton", {
	Name = "Teleport",
	Text = "传送到该玩家",
	TextSize = 13,
	Font = Enum.Font.GothamSemibold,
	TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = C.blue,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Size = UDim2.new(1, 0, 0, 42),
	LayoutOrder = 4,
	ZIndex = 13,
	Parent = detailInner,
})
round(tpButton, 10)

-- 轻提示
local toast = new("TextLabel", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, -26),
	Size = UDim2.fromOffset(60, 32),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(28, 28, 32),
	BackgroundTransparency = 1,
	Text = "",
	TextSize = 12,
	Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Visible = false,
	ZIndex = 55,
	Parent = body,
})
round(toast, 9)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
	Parent = toast,
})

local toastToken = 0
local toastTween = nil
local function showToast(message)
	toastToken = toastToken + 1
	local token = toastToken
	if toastTween then
		toastTween:Cancel()
		toastTween = nil
	end
	toast.Text = message
	toast.Visible = true
	toast.BackgroundTransparency = 0.12
	toast.TextTransparency = 0
	task.delay(1.6, function()
		if toastToken ~= token then
			return
		end
		toastTween = tween(toast, EASE_FAST, { BackgroundTransparency = 1, TextTransparency = 1 })
		task.delay(0.22, function()
			if toastToken == token then
				toast.Visible = false
			end
		end)
	end)
end

-- 日期 / 账号年龄
local function formatCreatedDate(accountAge)
	local t = os.date("*t", os.time() - math.max(0, math.floor(accountAge)) * 86400)
	return string.format("%d年%d月%d日", t.year, t.month, t.day)
end

local function formatAccountAge(accountAge)
	local days = math.max(0, math.floor(accountAge))
	local years = math.floor(days / 365)
	local months = math.floor((days % 365) / 30)
	if years > 0 then
		if months > 0 then
			return string.format("%d 年 %d 个月", years, months)
		end
		return string.format("%d 年", years)
	elseif months > 0 then
		return string.format("%d 个月", months)
	end
	return string.format("%d 天", days)
end

local detailPlayer = nil

local function refreshDetailDynamic()
	if not detailPlayer then
		return
	end
	if detailPlayer ~= player and not detailPlayer.Parent then
		infoValues.pos.Text = "已离开"
		infoValues.dist.Text = "—"
		dPill.Text = "已离开"
		return
	end
	local isSelf = (detailPlayer == player)
	local pos = positionOf(detailPlayer)
	if pos then
		infoValues.pos.Text = string.format("%d, %d, %d", math.round(pos.X), math.round(pos.Y), math.round(pos.Z))
	else
		infoValues.pos.Text = "不在场景中"
	end
	local d = distanceTo(detailPlayer)
	if isSelf then
		infoValues.dist.Text = "—"
		dPill.Text = "你的位置"
	elseif d then
		infoValues.dist.Text = string.format("%d studs", d)
		dPill.Text = string.format("距离 %d studs", d)
	else
		infoValues.dist.Text = "—"
		dPill.Text = "距离未知"
	end
end

local function openPlayerDetail(plr)
	detailPlayer = plr
	playerDetailOpen = true
	playerDetailTitle = plr.DisplayName
	playerArea.Visible = false
	detailArea.Visible = true
	detailArea.CanvasPosition = Vector2.new(0, 0)
	refreshHeader()

	dName.Text = plr.DisplayName
	dSub.Text = string.format("@%s  ·  ID %d", plr.Name, plr.UserId)
	dFaceInitial.Text = string.upper(string.sub(plr.DisplayName, 1, 1))
	dFaceInitial.Visible = true
	dFaceImage.Image = ""
	dBody.Image = ""
	infoValues.created.Text = formatCreatedDate(plr.AccountAge)
	infoValues.age.Text = formatAccountAge(plr.AccountAge)
	refreshDetailDynamic()

	if plr == player then
		tpButton.Text = "这是你自己"
		tpButton.BackgroundColor3 = Color3.fromRGB(233, 236, 242)
		tpButton.TextColor3 = Color3.fromRGB(154, 154, 160)
	else
		tpButton.Text = "传送到该玩家"
		tpButton.BackgroundColor3 = C.blue
		tpButton.TextColor3 = Color3.new(1, 1, 1)
	end

	task.spawn(function()
		local head = userThumb(plr.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		if head and dFaceImage.Parent and detailPlayer == plr then
			dFaceImage.Image = head
			dFaceInitial.Visible = false
		end
		local full = userThumb(plr.UserId, Enum.ThumbnailType.AvatarFullBody, Enum.ThumbnailSize.Size420x420)
		if full and dBody.Parent and detailPlayer == plr then
			dBody.Image = full
		end
	end)
end

closePlayerDetail = function()
	playerDetailOpen = false
	playerDetailTitle = nil
	detailPlayer = nil
	detailArea.Visible = false
	if navRows[selectedIndex] and navRows[selectedIndex].name == "玩家信息" then
		playerArea.Visible = true
	end
	refreshHeader()
end

local function teleportToPlayer(plr)
	if plr == player then
		return
	end
	if not plr.Parent then
		showToast("玩家已离开")
		return
	end
	local char = player.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	local targetRoot = rootOf(plr)
	if not myRoot or not targetRoot then
		showToast("无法传送：你或目标不在地图中")
		return
	end
	local ok, err = pcall(function()
		char:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 3))
	end)
	if ok then
		showToast("已传送到 " .. plr.DisplayName)
	else
		showToast("传送失败：游戏可能禁止")
		warn("[文件管理器] 传送失败：", err)
	end
end

tpButton.Activated:Connect(function()
	if detailPlayer then
		teleportToPlayer(detailPlayer)
	end
end)

tpButton.MouseEnter:Connect(function()
	if detailPlayer and detailPlayer ~= player and detailPlayer.Parent then
		tpButton.BackgroundColor3 = Color3.fromRGB(0, 108, 228)
	end
end)
tpButton.MouseLeave:Connect(function()
	if detailPlayer and detailPlayer ~= player and detailPlayer.Parent then
		tpButton.BackgroundColor3 = C.blue
	end
end)

--=====================================================================
-- 玩家信息：列表渲染
--=====================================================================

local playerRows = {}

local function clearPlayerRows()
	for _, entry in ipairs(playerRows) do
		entry.row:Destroy()
	end
	playerRows = {}
end

local function addPlayerRow(plr, order)
	local isSelf = (plr == player)
	local row = new("TextButton", {
		Name = "Player_" .. plr.Name,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.blue,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		ZIndex = 12,
		Parent = playerArea,
	})
	round(row, 6)

	new("Frame", {
		Name = "Divider",
		Position = UDim2.new(0, 16, 1, -1),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 14,
		Parent = row,
	})

	local _, img, initial = makeAvatar(row, 28, 16, 9, plr.DisplayName)
	loadAvatar(img, initial, plr, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size48x48, order * 0.04)

	local nameLabel = new("TextLabel", {
		Name = "Name",
		Text = plr.DisplayName,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextColor3 = isSelf and C.blue or C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(52, 5),
		Size = UDim2.new(1, -268, 0, 18),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local userLabel = new("TextLabel", {
		Name = "Account",
		Text = "@" .. plr.Name,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(52, 23),
		Size = UDim2.new(1, -268, 0, 15),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local distLabel = new("TextLabel", {
		Name = "Distance",
		Text = "—",
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.new(1, -196, 0, 0),
		Size = UDim2.fromOffset(100, 46),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})
	local stateLabel = new("TextLabel", {
		Name = "State",
		Text = isSelf and "本人" or "在线",
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = isSelf and C.dim or Color3.fromRGB(31, 170, 75),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.new(1, -96, 0, 0),
		Size = UDim2.fromOffset(78, 46),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = row,
	})

	if not isSelf then
		local d = distanceTo(plr)
		if d then
			distLabel.Text = string.format("%d studs", d)
		end
	end

	row.Activated:Connect(function()
		openPlayerDetail(plr)
	end)

	local entry = {
		row = row,
		player = plr,
		nameLabel = nameLabel,
		userLabel = userLabel,
		distLabel = distLabel,
		stateLabel = stateLabel,
	}
	playerRows[#playerRows + 1] = entry
	return entry
end

-- 窄窗口：隐藏距离 / 状态列，避免名字被挤扁
local function updatePlayerColumns()
	local w = playerArea.AbsoluteSize.X
	local narrow = w > 0 and w < 380
	playerHeadDist.Visible = not narrow
	playerHeadState.Visible = not narrow
	for _, entry in ipairs(playerRows) do
		entry.distLabel.Visible = not narrow
		entry.stateLabel.Visible = not narrow
		entry.nameLabel.Size = narrow and UDim2.new(1, -70, 0, 18) or UDim2.new(1, -268, 0, 18)
		entry.userLabel.Size = narrow and UDim2.new(1, -70, 0, 15) or UDim2.new(1, -268, 0, 15)
	end
end

local function renderPlayerList()
	clearPlayerRows()
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if a == player then
			return true
		end
		if b == player then
			return false
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	for i, plr in ipairs(list) do
		addPlayerRow(plr, i + 1)
	end
	updatePlayerColumns()
end

playerArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePlayerColumns)

-- 距离实时刷新（列表 + 详情，每 0.5s）
task.spawn(function()
	while true do
		task.wait(0.5)
		if playerArea.Visible then
			for _, entry in ipairs(playerRows) do
				if entry.row.Parent then
					if entry.player == player then
						entry.distLabel.Text = "—"
					else
						local d = distanceTo(entry.player)
						entry.distLabel.Text = d and string.format("%d studs", d) or "—"
					end
				end
			end
		end
		if playerDetailOpen and detailPlayer then
			refreshDetailDynamic()
		end
	end
end)

-- 玩家加入 / 离开时刷新列表；详情页对象离开时给出提示
Players.PlayerAdded:Connect(function()
	task.defer(function()
		if playerArea.Visible and not playerDetailOpen then
			renderPlayerList()
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	if playerDetailOpen and detailPlayer == plr then
		dSub.Text = string.format("@%s  ·  已离开", plr.Name)
		infoValues.pos.Text = "已离开"
		infoValues.dist.Text = "—"
		dPill.Text = "已离开"
		tpButton.Text = "玩家已离开"
		tpButton.BackgroundColor3 = Color3.fromRGB(233, 236, 242)
		tpButton.TextColor3 = Color3.fromRGB(154, 154, 160)
	end
	task.defer(function()
		if playerArea.Visible and not playerDetailOpen then
			renderPlayerList()
		end
	end)
end)

local function updateRecentGrid()
	local w = recentGrid.AbsoluteSize.X
	if w <= 0 then
		return
	end
	local gap = 14
	local cols = math.clamp(math.floor((w + gap) / (96 + gap)), 1, 4)
	local cell = math.min(96, math.floor((w - (cols - 1) * gap) / cols))
	recentLayout.CellSize = UDim2.fromOffset(cell, cell + 24)
end

-- 选中目录时切换内容视图
selectFolder = function(name)
	if playerDetailOpen then
		closePlayerDetail()
	end
	if name == "iCloud 云盘" then
		gridArea.Visible = false
		recentGridArea.Visible = false
		playerArea.Visible = false
		detailArea.Visible = false
		fileArea.Visible = true
		if not filesLoaded then
			filesLoaded = true
			loadFileList()
		end
	elseif name == "最近使用" then
		gridArea.Visible = false
		recentGridArea.Visible = true
		fileArea.Visible = false
		playerArea.Visible = false
		detailArea.Visible = false
		task.defer(updateRecentGrid)
	elseif name == "玩家信息" then
		gridArea.Visible = false
		recentGridArea.Visible = false
		fileArea.Visible = false
		detailArea.Visible = false
		playerArea.Visible = true
		renderPlayerList()
		task.defer(function()
			playerArea.CanvasPosition = Vector2.new(0, 0)
		end)
	else
		gridArea.Visible = true
		recentGridArea.Visible = false
		fileArea.Visible = false
		playerArea.Visible = false
		detailArea.Visible = false
		task.defer(updateGrid)
	end
end

-- 初始视图与默认选中项同步
selectFolder(navRows[selectedIndex].name)

--=====================================================================
-- 右下角缩放手柄
--=====================================================================

local resizeHandle = new("Frame", {
	Name = "ResizeHandle",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(1, 1),
	Size = UDim2.fromOffset(44, 44),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Active = true,
	Parent = body,
})

local function makeResizeLine(position)
	return new("Frame", {
		Position = position,
		Size = UDim2.fromOffset(11, 1.2),
		Rotation = -45,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = resizeHandle,
	})
end
makeResizeLine(UDim2.new(1, -16, 1, -14))
makeResizeLine(UDim2.new(1, -21, 1, -14))

--=====================================================================
-- 关闭 / 重开按钮
--=====================================================================

local reopenButton = new("Frame", {
	Name = "Reopen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(120, 34),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
	Active = true,
	ZIndex = 60,
	Parent = gui,
})
round(reopenButton, 10)
new("UIStroke", {
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.86,
	Thickness = 1,
	Parent = reopenButton,
})
new("TextLabel", {
	Text = "打开窗口",
	TextSize = 12.5,
	Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.fromRGB(30, 30, 30),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Parent = reopenButton,
})

local reopenScale = new("UIScale", { Scale = 0.9, Parent = reopenButton })

local function showWindow(show)
	if show then
		window.Visible = true
		tween(window, EASE, { GroupTransparency = 0 })
		tween(window, EASE, {
			Position = UDim2.fromOffset(window.Position.X.Offset, window.Position.Y.Offset - 24),
		})
	else
		local pos = window.Position
		tween(window, EASE_IN, { GroupTransparency = 1 })
		tween(window, EASE_IN, {
			Position = UDim2.fromOffset(pos.X.Offset, pos.Y.Offset + 24),
		})
		task.delay(0.28, function()
			if window.GroupTransparency > 0.99 then
				window.Visible = false
			end
		end)
	end
end

--=====================================================================
-- 拖动 / 缩放 / 全屏
--=====================================================================

local toggleFullscreen -- 前置声明，双击时使用
local keepWindowOnScreen

local isFullscreenFlag = false
local savedSize = nil
local savedPos = nil
local dragging = false
local dragStartPos = nil
local dragStartMouse = nil
local resizing = false
local resizeStartSize = nil
local resizeStartMouse = nil

dragStrip.InputBegan:Connect(function(input)
	if not isClick(input) then
		return
	end
	if isFullscreenFlag then
		return
	end
	dragging = true
	dragStartPos = window.Position
	dragStartMouse = input.Position
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging then
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStartMouse
			window.Position = UDim2.new(
				dragStartPos.X.Scale,
				dragStartPos.X.Offset + delta.X,
				dragStartPos.Y.Scale,
				dragStartPos.Y.Offset + delta.Y
			)
		end
		return
	end
	if resizing then
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - resizeStartMouse
			local vp = viewportSize()
			local newW = math.clamp(resizeStartSize.X.Offset + delta.X, Config.MinWidth, vp.X - 16)
			local newH = math.clamp(resizeStartSize.Y.Offset + delta.Y, Config.MinHeight, vp.Y - 32)
			window.Size = UDim2.fromOffset(newW, newH)
			updateGrid()
		end
	end
end)

-- 双击顶部拖动条 → 全屏（仅鼠标双击；触屏拖动不触发，避免误判）
local lastClick = 0
local lastClickPos = nil
dragStrip.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local now = tick()
	local dbl = false
	if lastClickPos and now - lastClick < 0.4 then
		dbl = (input.Position - lastClickPos).Magnitude < 18
	end
	lastClick = now
	lastClickPos = input.Position
	if dbl then
		toggleFullscreen()
	end
end)

-- 右下角缩放
resizeHandle.InputBegan:Connect(function(input)
	if not isClick(input) then
		return
	end
	if isFullscreenFlag then
		return
	end
	resizing = true
	resizeStartSize = window.Size
	resizeStartMouse = input.Position
end)

UserInputService.InputEnded:Connect(function(input)
	if isClick(input) then
		dragging = false
		resizing = false
		if not isFullscreenFlag then
			keepWindowOnScreen()
			updateGrid()
			updateRecentGrid()
		end
	end
end)

-- 保证顶部拖动条不会完全拖出屏幕
keepWindowOnScreen = function()
	local vp = viewportSize()
	local pos = window.Position
	local size = window.Size
	local x = math.clamp(pos.X.Offset, -(size.X.Offset - 140), vp.X - 140)
	local y = math.clamp(pos.Y.Offset, 0, vp.Y - Config.HeaderHeight - 8)
	window.Position = UDim2.fromOffset(x, y)
end

--=====================================================================
-- 交通灯动作：红/黄 = 关闭（变成“打开窗口”），绿 = 全屏
--=====================================================================

local function closeWindow()
	showWindow(false)
	reopenButton.Visible = true
	reopenScale.Scale = 0.9
	tween(reopenScale, EASE, { Scale = 1 })
end

trafficFrames[1].Activated:Connect(function()
	closeWindow()
end)

trafficFrames[2].Activated:Connect(function()
	closeWindow()
end)

toggleFullscreen = function()
	isFullscreenFlag = not isFullscreenFlag
	local vp = viewportSize()
	if isFullscreenFlag then
		savedSize = window.Size
		savedPos = window.Position
		tween(window, TweenInfo.new(0.38, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.fromOffset(vp.X - 32, vp.Y - 32),
		})
	else
		tween(window, TweenInfo.new(0.38, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = savedPos or UDim2.fromOffset(
				math.floor((vp.X - Config.Width) / 2),
				math.floor((vp.Y - Config.Height) / 2)
			),
			Size = savedSize or UDim2.fromOffset(Config.Width, Config.Height),
		})
	end
	task.delay(0.4, function()
		updateGrid()
		updateRecentGrid()
	end)
end

trafficFrames[3].Activated:Connect(function()
	toggleFullscreen()
end)

-- 「打开窗口」按钮：可拖动 + 点击重开（拖动超过阈值不算点击）
local reopenDragging = false
local reopenMoved = false
local reopenDragStartPos = nil
local reopenDragStartMouse = nil

reopenButton.InputBegan:Connect(function(input)
	if not isClick(input) then
		return
	end
	reopenDragging = true
	reopenMoved = false
	reopenDragStartPos = reopenButton.Position
	reopenDragStartMouse = input.Position
end)

reopenButton.InputEnded:Connect(function(input)
	if not isClick(input) or not reopenDragging then
		return
	end
	reopenDragging = false
	if not reopenMoved then
		-- 未拖动：视为点击，重新打开窗口
		tween(reopenScale, EASE_FAST, { Scale = 0.9 })
		reopenButton.Visible = false
		showWindow(true)
	else
		-- 拖动结束：约束在屏幕内
		local vp = viewportSize()
		local p = reopenButton.Position
		local cx = vp.X * p.X.Scale + p.X.Offset
		local cy = vp.Y * p.Y.Scale + p.Y.Offset
		reopenButton.Position = UDim2.fromOffset(
			math.clamp(cx, 60, vp.X - 60),
			math.clamp(cy, 60, vp.Y - 60)
		)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not reopenDragging then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - reopenDragStartMouse
		if delta.Magnitude > 6 then
			reopenMoved = true
		end
		reopenButton.Position = UDim2.new(
			reopenDragStartPos.X.Scale,
			reopenDragStartPos.X.Offset + delta.X,
			reopenDragStartPos.Y.Scale,
			reopenDragStartPos.Y.Offset + delta.Y
		)
	end
end)

--=====================================================================
-- 入场动画
--=====================================================================

task.defer(function()
	tween(window, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	})
	tween(window, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(centerX, centerY),
	})
	renderRecent()
	updateGrid()
	task.delay(0.12, function()
		updateGrid()
		updateRecentGrid()
	end)
end)
