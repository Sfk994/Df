--[[
	MacDesktopUI — 一个 Roblox 风格的 macOS 桌面界面
	=====================================================
	设计依据: emilkowalski/skills → apple-design
	  · 材质: 半透明层 + 亮边(光打在材质上) + 柔和投影，而不是 1px 实色边框
	  · 排版: 字号越大字距越紧(标题 -0.02em)，正文接近 0
	  · 交互: pointer-down 即刻反馈，按压缩放 0.97，100ms ease-out
	  · 运动: 临界阻尼弹簧 damping 1.0 / response 0.3–0.4；手势动量仅在手势本身带速度时回弹
	  · 无障碍: "减弱动态效果" 开关 → 用交叉淡化替代位移/弹簧

	安装: 把本文件放入 StarterPlayerScripts，类型为 LocalScript，直接运行。
	所有尺寸基于 1280x720 设计画布，通过 UIScale 等比适配任意分辨率。
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
	designWidth = 1280,
	designHeight = 720,
	timeOffsetHours = 8,
	accent = Color3.fromRGB(10, 132, 255),
	-- 触屏设备：优先按短边适配，保证文字与点击目标不被缩得太小
	touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled,
	compact = false,
}

---------------------------------------------------------------------------
-- 01 · 设计令牌
---------------------------------------------------------------------------

local Palette = {
	text = Color3.fromRGB(29, 29, 31),
	textSecondary = Color3.fromRGB(110, 110, 115),
	textTertiary = Color3.fromRGB(155, 155, 160),
	window = Color3.fromRGB(250, 250, 252),
	toolbar = Color3.fromRGB(246, 246, 248),
	sidebar = Color3.fromRGB(238, 238, 241),
	hairline = Color3.fromRGB(0, 0, 0),
	red = Color3.fromRGB(255, 95, 87),
	yellow = Color3.fromRGB(254, 188, 46),
	green = Color3.fromRGB(40, 200, 64),
	terminal = Color3.fromRGB(30, 30, 32),
	terminalText = Color3.fromRGB(235, 235, 240),
}

local Theme = {
	accent = CONFIG.accent,
	reduceMotion = false,
	touch = CONFIG.touch,
	compact = false,
	topInset = 0,
	menuBarHeight = 26,
	titleBarHeight = 38,
}

local Font = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	mono = Enum.Font.Code,
}

-- Apple 的弹簧参数（damping / response），单位秒
local SpringSpec = {
	window = { damping = 1.0, response = 0.34 },
	dock = { damping = 0.74, response = 0.28 },
	press = { damping = 1.0, response = 0.18 },
	popover = { damping = 1.0, response = 0.26 },
	slide = { damping = 1.0, response = 0.4 },
}

local EASE_OUT = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EASE_PRESS = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

---------------------------------------------------------------------------
-- 02 · 基础工具
---------------------------------------------------------------------------

local function create(className, props)
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			elseif value ~= nil then
				inst[key] = value
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function round(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function padding(inst, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = inst
	return p
end

local function label(props)
	props = props or {}
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Font.regular,
		TextColor3 = Palette.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return create("TextLabel", defaults)
end

local function clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function tween(inst, props, info)
	local t = TweenService:Create(inst, info or EASE_OUT, props)
	t:Play()
	return t
end

-- 鼠标左键与手指按下走同一条逻辑：触屏没有 hover，所有交互必须按下即生效
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

-- 长按：触屏上替代右键菜单（桌面端右键仍保留）
local function longPress(gui, duration, callback)
	local activeInput = nil
	local deadline = 0
	local fired = false

	gui.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		activeInput = input
		fired = false
		deadline = os.clock() + duration
		local stamp = deadline
		task.delay(duration, function()
			if activeInput == input and not fired and deadline == stamp then
				fired = true
				callback(input)
			end
		end)
	end)
	gui.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
		end
	end)
end

-- 拖拽时只跟随最初按下的手/指针：鼠标移动事件的 InputObject 与按下时不同，
-- 触屏则复用同一对象，所以两种事件要分开判断
local function followsInput(input, active)
	if not active then
		return false
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		return active.UserInputType == Enum.UserInputType.MouseButton1
	end
	return input == active
end

local function endsInput(input, active)
	if not active then
		return false
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
		return active.UserInputType == Enum.UserInputType.MouseButton1
	end
	return input == active
end

---------------------------------------------------------------------------
-- 03 · 弹簧引擎（临界阻尼，无过冲为默认）
---------------------------------------------------------------------------

local springs = {}

local Spring = {}
Spring.__index = Spring

local function newSpring(initial, apply, spec)
	local self = setmetatable({
		values = {},
		targets = {},
		velocity = {},
		apply = apply,
		resting = false,
		onRest = nil,
	}, Spring)

	spec = spec or SpringSpec.window
	self.damping = spec.damping or 1.0
	self.response = spec.response or 0.34
	self.stiffness = 0

	for key, value in pairs(initial) do
		self.values[key] = value
		self.targets[key] = value
		self.velocity[key] = 0
	end
	self:configure(self.damping, self.response)
	springs[#springs + 1] = self
	return self
end

function Spring:configure(damping, response)
	self.damping = damping
	self.response = response
	local omega = (math.pi * 2) / math.max(response, 0.05)
	self.stiffness = omega * omega
	self.omega = omega
end

function Spring:to(targets, damping, response)
	if damping then
		self:configure(damping, response or self.response)
	end
	for key, value in pairs(targets) do
		if self.values[key] == nil then
			self.values[key] = value
			self.velocity[key] = 0
		end
		self.targets[key] = value
	end
	self.resting = false
	return self
end

function Spring:jump(values)
	for key, value in pairs(values) do
		self.values[key] = value
		self.targets[key] = value
		self.velocity[key] = 0
	end
	self.resting = true
	self.apply(self.values, 0)
	return self
end

function Spring:isResting()
	return self.resting
end

function Spring:step(dt)
	if self.resting then
		return
	end
	local dampingCoef = 2 * self.damping * self.omega
	local resting = true

	for key, target in pairs(self.targets) do
		local x = self.values[key]
		local v = self.velocity[key]
		local delta = x - target

		if math.abs(v) > 0.004 or math.abs(delta) > 0.0008 then
			local accel = -self.stiffness * delta - dampingCoef * v
			v = v + accel * dt
			x = x + v * dt
			self.values[key] = x
			self.velocity[key] = v
			resting = false
		else
			self.values[key] = target
			self.velocity[key] = 0
		end
	end

	if resting then
		self.resting = true
	end

	self.apply(self.values, dt)
end

RunService.RenderStepped:Connect(function(dt)
	local step = math.min(dt, 1 / 30)
	for i = 1, #springs do
		springs[i]:step(step)
	end
end)

---------------------------------------------------------------------------
-- 04 · 材质：柔和投影 + 光晕
---------------------------------------------------------------------------

-- 用多层同心圆角矩形叠出接近高斯的柔和阴影（Roblox 没有 box-shadow）
local function makeShadow(parent, radius, opts)
	opts = opts or {}
	local count = opts.layers or 14
	local spread = opts.spread or 2
	local alpha = opts.alpha or 0.05
	local dy = opts.dy or 12
	local layers = {}
	local weights = {}

	for i = 1, count do
		local weight = (1 - (i - 1) / count) ^ 1.9
		weights[i] = weight
		local frame = create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1 - alpha * weight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, i * spread * 2, 1, i * spread * 2),
			Position = UDim2.new(0.5, 0, 0.5, (i / count) * dy),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 1,
			Parent = parent,
		})
		round(frame, radius + i * spread)
		layers[i] = frame
	end

	return {
		setAlpha = function(value, animate)
			for i = 1, #layers do
				local target = 1 - value * weights[i]
				if animate then
					tween(layers[i], { BackgroundTransparency = target }, TweenInfo.new(0.3, Enum.EasingStyle.Quad))
				else
					layers[i].BackgroundTransparency = target
				end
			end
		end,
	}
end

-- 用同心圆叠出径向光晕（做壁纸的柔和光斑）
local function makeGlow(parent, cfg)
	local steps = cfg.steps or 6
	local total = cfg.intensity or 0.5
	local perLayer = 1 - (1 - total) ^ (1 / steps)
	local frames = {}

	for i = 1, steps do
		local shrink = 1 - ((i - 1) / steps) * 0.9
		local size = cfg.size * shrink
		local frame = create("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(cfg.x, cfg.y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = cfg.color,
			BackgroundTransparency = 1 - perLayer,
			BorderSizePixel = 0,
			ZIndex = cfg.zIndex or 1,
			Parent = parent,
		})
		round(frame, math.floor(size / 2))
		frames[i] = frame
	end

	return {
		frames = frames,
		setColor = function(color, animate)
			for i = 1, #frames do
				if animate then
					tween(frames[i], { BackgroundColor3 = color }, TweenInfo.new(0.55, Enum.EasingStyle.Quad))
				else
					frames[i].BackgroundColor3 = color
				end
			end
		end,
	}
end

---------------------------------------------------------------------------
-- 05 · 屏幕适配与桌面
---------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "MacDesktopUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	Parent = playerGui,
})

local canvas = create("Frame", {
	Name = "Canvas",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(CONFIG.designWidth, CONFIG.designHeight),
	Parent = gui,
})

local uiScale = Instance.new("UIScale")
uiScale.Parent = canvas

local canvasScale = 1
local canvasSize = Vector2.new(CONFIG.designWidth, CONFIG.designHeight)
local layoutListeners = {}
local refreshLayout = function() end

-- 桌面：保持 1280x720 设计画布等比缩放
-- 触屏：按短边适配，优先保证字号与点按区域，宁可牺牲一点横向内容
local function computeScale(viewport)
	if CONFIG.touch then
		return clamp(math.min(viewport.X, viewport.Y) / 540, 0.62, 1.2)
	end
	return clamp(math.min(viewport.X / CONFIG.designWidth, viewport.Y / CONFIG.designHeight), 0.5, 1.6)
end

local function measure()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = computeScale(viewport)
	uiScale.Scale = scale
	canvasScale = scale
	canvasSize = Vector2.new(viewport.X / scale, viewport.Y / scale)
	canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	Theme.touch = CONFIG.touch
	Theme.compact = CONFIG.touch or canvasSize.X < 940
	Theme.titleBarHeight = CONFIG.touch and 44 or 38
	-- 手机顶部有 Roblox 菜单按钮，菜单栏必须让开，否则会被盖住
	Theme.topInset = 0
	if CONFIG.touch then
		local ok, inset = pcall(function()
			return game:GetService("GuiService"):GetGuiInset()
		end)
		Theme.topInset = ok and math.max(36, inset.Y) or 36
	end
end

local function onLayout(fn)
	layoutListeners[#layoutListeners + 1] = fn
end

local function refit()
	measure()
	refreshLayout()
	for _, fn in ipairs(layoutListeners) do
		fn()
	end
end

refit()

local viewportConnection
local function bindViewport()
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	end
end
bindViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	bindViewport()
	refit()
end)

local wallpaper = create("Frame", {
	Name = "Wallpaper",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 16, 44),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 1,
	Parent = canvas,
})

local glowLayer = create("Frame", {
	Name = "GlowLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = wallpaper,
})

local WallpaperThemes = {
	aurora = {
		name = "极光",
		base = Color3.fromRGB(10, 14, 40),
		glows = {
			{ x = 0.18, y = 0.06, size = 900, color = Color3.fromRGB(46, 108, 255), intensity = 0.52 },
			{ x = 0.86, y = 0.22, size = 780, color = Color3.fromRGB(196, 74, 232), intensity = 0.4 },
			{ x = 0.62, y = 0.98, size = 960, color = Color3.fromRGB(255, 108, 138), intensity = 0.34 },
			{ x = 0.02, y = 0.88, size = 620, color = Color3.fromRGB(40, 200, 220), intensity = 0.26 },
		},
	},
	midnight = {
		name = "午夜",
		base = Color3.fromRGB(8, 10, 18),
		glows = {
			{ x = 0.24, y = 0.12, size = 880, color = Color3.fromRGB(36, 62, 120), intensity = 0.5 },
			{ x = 0.82, y = 0.34, size = 720, color = Color3.fromRGB(48, 44, 96), intensity = 0.36 },
			{ x = 0.52, y = 1.02, size = 900, color = Color3.fromRGB(20, 74, 96), intensity = 0.3 },
			{ x = 0.02, y = 0.72, size = 640, color = Color3.fromRGB(30, 40, 90), intensity = 0.26 },
		},
	},
	sunrise = {
		name = "日出",
		base = Color3.fromRGB(32, 18, 30),
		glows = {
			{ x = 0.7, y = 0.1, size = 900, color = Color3.fromRGB(255, 138, 92), intensity = 0.5 },
			{ x = 0.28, y = 0.4, size = 820, color = Color3.fromRGB(255, 86, 128), intensity = 0.4 },
			{ x = 0.9, y = 0.9, size = 860, color = Color3.fromRGB(255, 190, 110), intensity = 0.32 },
			{ x = 0.1, y = 0.95, size = 700, color = Color3.fromRGB(120, 60, 180), intensity = 0.28 },
		},
	},
}

local activeGlows = {}
local currentTheme = "aurora"

local function buildWallpaper(themeKey, animate)
	local theme = WallpaperThemes[themeKey]
	currentTheme = themeKey
	if not animate then
		wallpaper.BackgroundColor3 = theme.base
	else
		tween(wallpaper, { BackgroundColor3 = theme.base }, TweenInfo.new(0.55, Enum.EasingStyle.Quad))
	end

	if #activeGlows == 0 then
		for _, cfg in ipairs(theme.glows) do
			activeGlows[#activeGlows + 1] = makeGlow(glowLayer, {
				x = cfg.x * canvasSize.X,
				y = cfg.y * canvasSize.Y,
				size = cfg.size,
				color = cfg.color,
				intensity = cfg.intensity,
				steps = Theme.touch and 4 or 6,
				zIndex = 2,
			})
		end
		return
	end

	for index, cfg in ipairs(theme.glows) do
		local glow = activeGlows[index]
		if glow then
			glow.setColor(cfg.color, animate)
			for _, frame in ipairs(glow.frames) do
				local target = UDim2.fromOffset(cfg.x * canvasSize.X, cfg.y * canvasSize.Y)
				if animate then
					tween(frame, { Position = target }, TweenInfo.new(0.6, Enum.EasingStyle.Quad))
				else
					frame.Position = target
				end
			end
		end
	end
end

buildWallpaper("aurora", false)

-- 窗口尺寸变化后重新把光斑铺到新画布上
local function layoutWallpaper()
	local theme = WallpaperThemes[currentTheme]
	if not theme then
		return
	end
	for index, cfg in ipairs(theme.glows) do
		local glow = activeGlows[index]
		if glow then
			for _, frame in ipairs(glow.frames) do
				frame.Position = UDim2.fromOffset(cfg.x * canvasSize.X, cfg.y * canvasSize.Y)
			end
		end
	end
end
refreshLayout = layoutWallpaper

---------------------------------------------------------------------------
-- 06 · 桌面命中层 + 右键菜单
---------------------------------------------------------------------------

local overlayLayer = create("Frame", {
	Name = "Overlays",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 400,
	Parent = canvas,
})

local windowLayer = create("Frame", {
	Name = "Windows",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = canvas,
})

local desktopHit = create("TextButton", {
	Name = "DesktopHit",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 3,
	Parent = canvas,
})

local closeOverlays -- 前置声明

local function dismissAll()
	if closeOverlays then
		closeOverlays()
	end
end

---------------------------------------------------------------------------
-- 07 · 玻璃材质组件
---------------------------------------------------------------------------

local function glassPanel(parent, opts)
	opts = opts or {}
	local panel = create("Frame", {
		BackgroundColor3 = opts.color or Color3.fromRGB(28, 28, 32),
		BackgroundTransparency = opts.transparency or 0.28,
		BorderSizePixel = 0,
		Size = opts.size or UDim2.fromOffset(200, 100),
		Position = opts.position or UDim2.fromOffset(0, 0),
		AnchorPoint = opts.anchor or Vector2.new(0, 0),
		ClipsDescendants = opts.clip ~= false,
		ZIndex = opts.zIndex or 410,
		Parent = parent,
	})
	round(panel, opts.radius or 12)

	-- 亮边：光打在材质上边缘（apple-design: bright top edge = light catching the material）
	local topEdge = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -(opts.radius or 12) * 2, 0, 1),
		Position = UDim2.new(0, opts.radius or 12, 0, 0),
		ZIndex = (opts.zIndex or 410) + 1,
		Parent = panel,
	})
	topEdge.Name = "TopEdge"

	if opts.stroke ~= false then
		stroke(panel, Color3.fromRGB(255, 255, 255), 1, 0.86)
	end
	return panel
end

---------------------------------------------------------------------------
-- 08 · 菜单栏
---------------------------------------------------------------------------

local menubar = create("Frame", {
	Name = "MenuBar",
	Size = UDim2.new(1, 0, 0, Theme.menuBarHeight),
	Position = UDim2.fromOffset(0, Theme.topInset),
	BackgroundColor3 = Color3.fromRGB(10, 10, 14),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 300,
	Parent = canvas,
})

local menubarEdge = create("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 1, -1),
	ZIndex = 301,
	Parent = menubar,
})

local appleHolder = create("Frame", {
	Size = UDim2.fromOffset(28, 26),
	BackgroundTransparency = 1,
	ZIndex = 302,
	Parent = menubar,
})

local function drawApple(parent, size)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Parent = parent,
	})
	local white = Color3.fromRGB(255, 255, 255)

	local body = create("Frame", {
		Size = UDim2.fromOffset(size * 0.76, size * 0.68),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(body, size * 0.3)

	local lobeLeft = create("Frame", {
		Size = UDim2.fromOffset(size * 0.38, size * 0.3),
		Position = UDim2.new(0.34, 0, 0.32, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(lobeLeft, size * 0.16)

	local lobeRight = create("Frame", {
		Size = UDim2.fromOffset(size * 0.38, size * 0.3),
		Position = UDim2.new(0.66, 0, 0.32, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(lobeRight, size * 0.16)

	local stem = create("Frame", {
		Size = UDim2.fromOffset(math.max(1, size * 0.07), size * 0.2),
		Position = UDim2.new(0.52, 0, 0.13, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Rotation = -12,
		Parent = holder,
	})
	round(stem, size * 0.04)

	local leaf = create("Frame", {
		Size = UDim2.fromOffset(size * 0.34, size * 0.16),
		Position = UDim2.new(0.7, 0, 0.14, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Rotation = -26,
		Parent = holder,
	})
	round(leaf, size * 0.08)
end

drawApple(appleHolder, 14)

local menuRoot = create("Frame", {
	Size = UDim2.new(1, -(28 + 300), 1, 0),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	ZIndex = 302,
	Parent = menubar,
})

local menuList = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 302,
	Parent = menuRoot,
})

create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = menuList,
})

local menuBarMenus = { "访达", "文件", "编辑", "显示", "前往", "窗口", "帮助" }
local menuButtons = {}

local MenuItems = {
	["访达"] = {
		{ "关于本机", "", "about" },
		{ "-" },
		{ "系统设置…", "", "settings" },
		{ "App Store…", "" },
		{ "-" },
		{ "睡眠", "" },
		{ "重新启动…", "" },
		{ "关机…", "" },
	},
	["文件"] = {
		{ "新建访达窗口", "Cmd N", "finder" },
		{ "新建文件夹", "Shift Cmd N", "newfolder" },
		{ "-" },
		{ "打开", "Cmd O" },
		{ "关闭窗口", "Cmd W", "close" },
		{ "-" },
		{ "显示简介", "Cmd I" },
		{ "移到废纸篓", "Cmd Del" },
	},
	["编辑"] = {
		{ "撤销", "Cmd Z" },
		{ "重做", "Shift Cmd Z" },
		{ "-" },
		{ "剪切", "Cmd X" },
		{ "拷贝", "Cmd C" },
		{ "粘贴", "Cmd V" },
		{ "-" },
		{ "全选", "Cmd A" },
	},
	["显示"] = {
		{ "以图标显示", "Cmd 1", "viewIcons" },
		{ "以列表显示", "Cmd 2", "viewList" },
		{ "-" },
		{ "隐藏侧边栏", "Ctrl Cmd S" },
		{ "显示预览", "Shift Cmd P" },
	},
	["前往"] = {
		{ "最近使用的项目", "Cmd Shift F" },
		{ "文稿", "Cmd Shift O", "finder" },
		{ "桌面", "Cmd Shift D", "finder" },
		{ "下载", "Opt Cmd L", "finder" },
		{ "-" },
		{ "实用工具", "Cmd Shift U" },
	},
	["窗口"] = {
		{ "最小化", "Cmd M", "minimize" },
		{ "缩放", "", "zoom" },
		{ "-" },
		{ "前置全部窗口", "Opt Cmd F" },
	},
	["帮助"] = {
		{ "macOS 使用手册", "" },
		{ "-" },
		{ "致谢", "", "credits" },
	},
}

local activeDropdown
local activeMenuItem

local function closeDropdown()
	if activeDropdown then
		local panel = activeDropdown
		activeDropdown = nil
		if activeMenuItem and activeMenuItem.Parent then
			tween(activeMenuItem, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
		end
		activeMenuItem = nil
		local t = tween(panel, { BackgroundTransparency = 1 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad))
		for _, child in ipairs(panel:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, { TextTransparency = 1 }, TweenInfo.new(0.1, Enum.EasingStyle.Quad))
			elseif child:IsA("Frame") and child.Name ~= "TopEdge" then
				tween(child, { BackgroundTransparency = 1 }, TweenInfo.new(0.1, Enum.EasingStyle.Quad))
			end
		end
		t.Completed:Connect(function()
			panel:Destroy()
		end)
	end
end

local showToast -- 前置声明（后续实现）

local function runMenuAction(action)
	if not action then
		return
	end
	if action == "about" then
		if _G.__MacOpenAbout then
			_G.__MacOpenAbout()
		end
	elseif action == "settings" then
		if _G.__MacOpenApp then
			_G.__MacOpenApp("settings")
		end
	elseif action == "finder" then
		if _G.__MacOpenApp then
			_G.__MacOpenApp("finder")
		end
	elseif action == "newfolder" then
		if showToast then
			showToast("已创建文件夹", "未命名文件夹 已添加到桌面")
		end
	elseif action == "close" then
		if _G.__MacCloseFocused then
			_G.__MacCloseFocused()
		end
	elseif action == "minimize" then
		if _G.__MacMinimizeFocused then
			_G.__MacMinimizeFocused()
		end
	elseif action == "zoom" then
		if _G.__MacZoomFocused then
			_G.__MacZoomFocused()
		end
	elseif action == "viewIcons" or action == "viewList" then
		if showToast then
			showToast("显示方式", action == "viewIcons" and "已切换为图标视图" or "已切换为列表视图")
		end
	elseif action == "credits" then
		if showToast then
			showToast("致谢", "界面灵感来自 Apple HIG 与 emilkowalski/skills")
		end
	end
end

local function openDropdown(menuButton, menuName, items)
	if activeMenuItem == menuButton then
		closeDropdown()
		return
	end
	closeDropdown()
	activeMenuItem = menuButton

	local buttonAbs = menuButton.AbsolutePosition
	local canvasAbs = canvas.AbsolutePosition
	local x = (buttonAbs.X - canvasAbs.X) / canvasScale - 10
	local y = Theme.topInset + Theme.menuBarHeight

	local width = 214
	local height = 8
	for _, item in ipairs(items) do
		if item[1] == "-" then
			height = height + 9
		else
			height = height + 26
		end
	end
	height = height + 6

	local panel = glassPanel(canvas, {
		color = Color3.fromRGB(38, 38, 42),
		transparency = 0.12,
		size = UDim2.fromOffset(width, height),
		position = UDim2.fromOffset(math.min(x, canvasSize.X - width - 8), y),
		radius = 9,
		zIndex = 420,
	})
	activeDropdown = panel
	panel.BackgroundTransparency = 1

	local list = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 421,
		Parent = panel,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	padding(list, 5)

	for index, item in ipairs(items) do
		if item[1] == "-" then
			local sep = create("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				LayoutOrder = index,
				ZIndex = 422,
				Parent = list,
			})
			local holder = create("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = index,
				ZIndex = 422,
				Parent = list,
			})
			sep.Parent = holder
			sep.Position = UDim2.new(0, 8, 0.5, 0)
			sep.Size = UDim2.new(1, -16, 0, 1)
		else
			local row = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				ZIndex = 422,
				Parent = list,
			})
			round(row, 5)
			label({
				Text = item[1],
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -84, 1, 0),
				TextSize = 13,
				TextColor3 = Color3.fromRGB(245, 245, 248),
				ZIndex = 423,
				Parent = row,
			})
			if item[2] and item[2] ~= "" then
				label({
					Text = item[2],
					Size = UDim2.new(0, 74, 1, 0),
					Position = UDim2.new(1, -76, 0, 0),
					TextSize = 10.5,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextTransparency = 0.45,
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 423,
					Parent = row,
				})
			end

			row.MouseEnter:Connect(function()
				tween(row, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.08))
			end)
			row.MouseLeave:Connect(function()
				tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end)
			row.Activated:Connect(function()
				runMenuAction(item[3])
				closeDropdown()
			end)
		end
	end

	local bgTarget = 0.1
	panel.BackgroundTransparency = 1
	for _, obj in ipairs(panel:GetDescendants()) do
		if obj:IsA("TextLabel") then
			obj.TextTransparency = 1
		end
	end
	tween(panel, { BackgroundTransparency = bgTarget }, TweenInfo.new(0.14, Enum.EasingStyle.Quad))
	for _, obj in ipairs(panel:GetDescendants()) do
		if obj:IsA("TextLabel") then
			tween(obj, { TextTransparency = 0 }, TweenInfo.new(0.16, Enum.EasingStyle.Quad))
		end
	end
end

for index, name in ipairs(menuBarMenus) do
	local isApp = index == 1
	local width = isApp and 52 or (#name * 13 + 18)
	local button = create("TextButton", {
		Size = UDim2.fromOffset(width, 26),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = index,
		ZIndex = 303,
		Parent = menuList,
	})
	button:SetAttribute("w", width)
	menuButtons[#menuButtons + 1] = button
	round(button, 0)
	label({
		Text = name,
		Size = UDim2.fromScale(1, 1),
		TextSize = 13,
		Font = isApp and Font.bold or Font.regular,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 304,
		Parent = button,
	})

	button.MouseEnter:Connect(function()
		if activeDropdown and activeMenuItem and activeMenuItem ~= button then
			openDropdown(button, name, MenuItems[name])
		else
			tween(button, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.08))
		end
	end)
	button.MouseLeave:Connect(function()
		if activeMenuItem ~= button then
			tween(button, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
		end
	end)
	button.Activated:Connect(function()
		openDropdown(button, name, MenuItems[name])
	end)
end

-- 右侧状态区
local statusBarWidth = 310
local statusBar = create("Frame", {
	Size = UDim2.fromOffset(statusBarWidth, Theme.menuBarHeight),
	Position = UDim2.new(1, -statusBarWidth, 0, 0),
	BackgroundTransparency = 1,
	ZIndex = 303,
	Parent = menubar,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = statusBar,
})

local clockButton = create("TextButton", {
	Size = UDim2.fromOffset(140, Theme.menuBarHeight),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	LayoutOrder = 10,
	ZIndex = 304,
	Parent = statusBar,
})
local clockLabel = label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	TextSize = 12.5,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 305,
	Parent = clockButton,
})
clockButton.MouseEnter:Connect(function()
	tween(clockButton, { BackgroundTransparency = 0.86 }, TweenInfo.new(0.08))
end)
clockButton.MouseLeave:Connect(function()
	tween(clockButton, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
end)
clockButton.Activated:Connect(function()
	if _G.__MacToggleWidgets then
		_G.__MacToggleWidgets()
	end
end)

local weekdays = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

local function refreshClock()
	local stamp = os.time() + CONFIG.timeOffsetHours * 3600
	local t = os.date("*t", stamp)
	if Theme.compact then
		clockLabel.Text = string.format("%02d:%02d", t.hour, t.min)
	else
		clockLabel.Text = string.format("%d月%d日 %s %02d:%02d", t.month, t.day, weekdays[(t.wday % 7) + 1], t.hour, t.min)
	end
end
refreshClock()
task.spawn(function()
	while gui.Parent do
		task.wait(1)
		refreshClock()
	end
end)

-- 电池
local batteryHolder = create("Frame", {
	Size = UDim2.fromOffset(26, 26),
	BackgroundTransparency = 1,
	LayoutOrder = 5,
	ZIndex = 304,
	Parent = statusBar,
})
local batteryBody = create("Frame", {
	Size = UDim2.fromOffset(21, 10),
	Position = UDim2.new(0.5, -1, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.75,
	BorderSizePixel = 0,
	Parent = batteryHolder,
})
round(batteryBody, 3)
stroke(batteryBody, Color3.fromRGB(255, 255, 255), 1, 0.45)
create("Frame", {
	Size = UDim2.new(0.72, 0, 0.6, 0),
	Position = UDim2.new(0, 2, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Parent = batteryBody,
}).Name = "Fill"
round(batteryBody.Fill, 1.5)
create("Frame", {
	Size = UDim2.fromOffset(2, 4),
	Position = UDim2.new(1, 1, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = batteryHolder,
})

-- Wi-Fi（三段递减圆角条，读作扇形信号）
local wifiHolder = create("Frame", {
	Size = UDim2.fromOffset(20, 26),
	BackgroundTransparency = 1,
	LayoutOrder = 4,
	ZIndex = 304,
	Parent = statusBar,
})
for i = 1, 3 do
	local w = 15 - (i - 1) * 5
	create("Frame", {
		Size = UDim2.fromOffset(w, 1.8),
		Position = UDim2.new(0.5, 0, 0.5, -6 + (i - 1) * 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = wifiHolder,
	})
end

-- 控制中心
local controlButton = create("TextButton", {
	Size = UDim2.fromOffset(24, 26),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	LayoutOrder = 2,
	ZIndex = 304,
	Parent = statusBar,
})
for i = 1, 2 do
	local pill = create("Frame", {
		Size = UDim2.fromOffset(17, 7),
		Position = UDim2.new(0.5, 0, 0.5, -4 + (i - 1) * 7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = controlButton,
	})
	round(pill, 4)
	stroke(pill, Color3.fromRGB(255, 255, 255), 1, 0.2)
	local knob = create("Frame", {
		Size = UDim2.fromOffset(5, 5),
		Position = UDim2.new(0, 1.5 + (i - 1) * 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = pill,
	})
	round(knob, 3)
end
controlButton.MouseEnter:Connect(function()
	tween(controlButton, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.08))
end)
controlButton.MouseLeave:Connect(function()
	tween(controlButton, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
end)

-- 聚焦搜索（放大镜）
local spotlightButton = create("TextButton", {
	Size = UDim2.fromOffset(24, 26),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	LayoutOrder = 9,
	ZIndex = 304,
	Parent = statusBar,
})
local lens = create("Frame", {
	Size = UDim2.fromOffset(10, 10),
	Position = UDim2.new(0.5, -1.5, 0.5, -1.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 305,
	Parent = spotlightButton,
})
round(lens, 5)
stroke(lens, Color3.fromRGB(255, 255, 255), 1.3, 0.1)
create("Frame", {
	Size = UDim2.fromOffset(5, 1.3),
	Position = UDim2.new(1, 2, 1, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Rotation = 45,
	ZIndex = 305,
	Parent = lens,
})
spotlightButton.MouseEnter:Connect(function()
	tween(spotlightButton, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.08))
end)
spotlightButton.MouseLeave:Connect(function()
	tween(spotlightButton, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
end)
spotlightButton.Activated:Connect(function()
	if _G.__MacToggleSpotlight then
		_G.__MacToggleSpotlight()
	end
end)

-- 菜单栏与状态区随屏幕形态重排（桌面/手机横竖屏）
local function applyChrome()
	local h = Theme.compact and 32 or 26
	Theme.menuBarHeight = h
	menubar.Size = UDim2.new(1, 0, 0, h)
	menubar.Position = UDim2.fromOffset(0, Theme.topInset)

	local appleWidth = Theme.compact and 32 or 28
	appleHolder.Size = UDim2.fromOffset(appleWidth, h)

	local statusWidth = Theme.compact and 206 or 310
	statusBar.Size = UDim2.fromOffset(statusWidth, h)
	statusBar.Position = UDim2.new(1, -statusWidth, 0, 0)
	menuRoot.Size = UDim2.new(1, -(appleWidth + statusWidth), 1, 0)
	menuRoot.Position = UDim2.fromOffset(appleWidth, 0)

	clockButton.Size = UDim2.fromOffset(Theme.compact and 54 or 140, h)
	spotlightButton.Size = UDim2.fromOffset(24, h)
	controlButton.Size = UDim2.fromOffset(24, h)
	batteryHolder.Size = UDim2.fromOffset(26, h)
	wifiHolder.Size = UDim2.fromOffset(20, h)

	for index, btn in ipairs(menuButtons) do
		btn.Visible = (not Theme.compact) or index == 1
		btn.Size = UDim2.fromOffset(Theme.compact and 56 or (btn:GetAttribute("w") or 60), h)
	end

	-- 手机只保留顶部菜单按钮，其余菜单通过长按桌面 / 聚焦搜索使用
	refreshClock()
end

onLayout(applyChrome)
applyChrome()

---------------------------------------------------------------------------
-- 09 · 程序坞
---------------------------------------------------------------------------

local DockItems = {}
local Dock = {
	base = CONFIG.touch and 42 or 44,
	slotExtra = CONFIG.touch and 12 or 14,
	gap = 6,
	height = CONFIG.touch and 68 or 72,
	bottomInset = CONFIG.touch and 9 or 8,
	hovered = nil,
	magnify = not CONFIG.touch,
	-- 屏幕过窄时整体等比收缩，保证程序坞不会顶出画布
	fit = 1,
}

local dockWrap = create("Frame", {
	Name = "Dock",
	Size = UDim2.fromOffset(400, Dock.height),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -Dock.bottomInset),
	BackgroundTransparency = 1,
	ZIndex = 279,
	Parent = canvas,
})

local dockShadow = makeShadow(dockWrap, 22, { alpha = 0.1, dy = 10, spread = 1.8, layers = 12 })

local dock = create("Frame", {
	Name = "DockGlass",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.72,
	BorderSizePixel = 0,
	ZIndex = 281,
	Parent = dockWrap,
})
round(dock, 20)
stroke(dock, Color3.fromRGB(255, 255, 255), 1, 0.82)

local dockGradient = Instance.new("UIGradient")
dockGradient.Rotation = 90
dockGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 230))
dockGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(1, 0.86),
})
dockGradient.Parent = dock

local dockEdge = create("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -40, 0, 1),
	Position = UDim2.new(0, 20, 0, 0),
	ZIndex = 282,
	Parent = dock,
})

local dockList = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	ZIndex = 283,
	Parent = dock,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, Dock.gap),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = dockList,
})
create("UIPadding", {
	PaddingBottom = UDim.new(0, Dock.bottomInset),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
	Parent = dockList,
})

local function gradientFill(parent, c1, c2, rotation)
	local bg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = c1,
		BorderSizePixel = 0,
		ZIndex = 284,
		Parent = parent,
	})
	round(bg, Dock.base * 0.24)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c1, c2)
	g.Rotation = rotation or 135
	g.Parent = bg
	return bg
end

local iconPainters = {}

iconPainters.finder = function(parent, size)
	gradientFill(parent, Color3.fromRGB(150, 218, 255), Color3.fromRGB(22, 108, 216), 135)
	local face = create("Frame", {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = parent,
	})
	round(face, size * 0.2)
	for i = 0, 1 do
		create("Frame", {
			Size = UDim2.fromOffset(size * 0.055, size * 0.085),
			Position = UDim2.new(0.38 + i * 0.24, 0, 0.42, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(24, 82, 160),
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = face,
		}).Name = "Eye"
	end
	for i = 0, 4 do
		local angle = math.rad(28 + i * 31)
		create("Frame", {
			Size = UDim2.fromOffset(size * 0.045, size * 0.045),
			Position = UDim2.new(0.5 + math.cos(angle) * 0.2, 0, 0.58 + math.sin(angle) * 0.16, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(24, 82, 160),
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = face,
		}).Name = "Smile"
	end
end

iconPainters.launchpad = function(parent, size)
	gradientFill(parent, Color3.fromRGB(242, 244, 250), Color3.fromRGB(202, 208, 220), 135)
	local colors = {
		Color3.fromRGB(255, 105, 120),
		Color3.fromRGB(255, 168, 76),
		Color3.fromRGB(255, 214, 82),
		Color3.fromRGB(96, 210, 128),
		Color3.fromRGB(72, 200, 208),
		Color3.fromRGB(84, 150, 250),
		Color3.fromRGB(160, 120, 240),
		Color3.fromRGB(224, 110, 210),
		Color3.fromRGB(150, 156, 168),
	}
	local cell = size * 0.17
	local step = size * 0.23
	local origin = size * 0.5 - step
	for index = 1, 9 do
		local col = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local tile = create("Frame", {
			Size = UDim2.fromOffset(cell, cell),
			Position = UDim2.fromOffset(origin + col * step, origin + row * step),
			BackgroundColor3 = colors[index],
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = parent,
		})
		round(tile, cell * 0.28)
	end
end

iconPainters.safari = function(parent, size)
	gradientFill(parent, Color3.fromRGB(250, 252, 255), Color3.fromRGB(150, 200, 240), 160)
	local ring = create("Frame", {
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = parent,
	})
	round(ring, size * 0.36)
	stroke(ring, Color3.fromRGB(160, 190, 220), 1, 0.6)

	local needle = create("Frame", {
		Size = UDim2.fromScale(0.5, 0.12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Rotation = -45,
		ZIndex = 286,
		Parent = parent,
	})
	local red = create("Frame", {
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 69, 58),
		BorderSizePixel = 0,
		ZIndex = 287,
		Parent = needle,
	})
	round(red, size * 0.03)
	local white = create("Frame", {
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(232, 238, 245),
		BorderSizePixel = 0,
		ZIndex = 287,
		Parent = needle,
	})
	round(white, size * 0.03)
	create("Frame", {
		Size = UDim2.fromOffset(size * 0.08, size * 0.08),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 288,
		Parent = parent,
	}).Name = "Pivot"
end

iconPainters.notes = function(parent, size)
	gradientFill(parent, Color3.fromRGB(255, 232, 140), Color3.fromRGB(255, 196, 30), 135)
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0.28, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = parent,
	})
	local headerMask = Instance.new("UICorner")
	headerMask.CornerRadius = UDim.new(0, math.floor(size * 0.24))
	headerMask.Parent = header
	create("Frame", {
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = header,
	})
	for i = 1, 4 do
		create("Frame", {
			Size = UDim2.new(0.72 - i * 0.06, 0, 0, 2),
			Position = UDim2.new(0.14, 0, 0.36 + (i - 1) * 0.14, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = parent,
		})
	end
end

iconPainters.terminal = function(parent, size)
	gradientFill(parent, Color3.fromRGB(64, 64, 68), Color3.fromRGB(20, 20, 22), 135)
	local bar = create("Frame", {
		Size = UDim2.new(1, 0, 0.2, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = parent,
	})
	local mask = Instance.new("UICorner")
	mask.CornerRadius = UDim.new(0, math.floor(size * 0.24))
	mask.Parent = bar
	create("Frame", {
		Size = UDim2.new(1, 0, 0.6, 0),
		Position = UDim2.new(0, 0, 0.4, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = bar,
	})
	label({
		Text = ">_",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, size * 0.08),
		TextSize = math.floor(size * 0.3),
		Font = Font.mono,
		TextColor3 = Color3.fromRGB(140, 255, 170),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 287,
		Parent = parent,
	})
end

iconPainters.music = function(parent, size)
	gradientFill(parent, Color3.fromRGB(255, 108, 148), Color3.fromRGB(226, 32, 74), 135)
	local white = Color3.fromRGB(255, 255, 255)

	local head = create("Frame", {
		Size = UDim2.fromScale(0.28, 0.21),
		Position = UDim2.fromScale(0.3, 0.68),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Rotation = -18,
		ZIndex = 286,
		Parent = parent,
	})
	round(head, size * 0.1)

	create("Frame", {
		Size = UDim2.new(0, math.max(1.5, size * 0.055), 0.44, 0),
		Position = UDim2.fromScale(0.59, 0.66),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 286,
		Parent = parent,
	})

	local flag = create("Frame", {
		Size = UDim2.fromScale(0.26, 0.09),
		Position = UDim2.fromScale(0.68, 0.26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		Rotation = 18,
		ZIndex = 286,
		Parent = parent,
	})
	round(flag, size * 0.05)
end

iconPainters.settings = function(parent, size)
	gradientFill(parent, Color3.fromRGB(180, 180, 188), Color3.fromRGB(88, 88, 96), 135)
	for i = 1, 3 do
		local y = 0.32 + (i - 1) * 0.18
		create("Frame", {
			Size = UDim2.new(0.54, 0, 0, 2),
			Position = UDim2.new(0.23, 0, y, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			ZIndex = 285,
			Parent = parent,
		})
		create("Frame", {
			Size = UDim2.fromOffset(size * 0.11, size * 0.11),
			Position = UDim2.new(0.3 + (i % 2) * 0.26, 0, y, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = parent,
		}).Name = "Knob"
	end
end

iconPainters.trash = function(parent, size)
	local body = create("Frame", {
		Size = UDim2.fromScale(0.56, 0.62),
		Position = UDim2.fromScale(0.5, 0.58),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(235, 240, 248),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 285,
		Parent = parent,
	})
	round(body, size * 0.08)
	stroke(body, Color3.fromRGB(255, 255, 255), 1, 0.35)
	for i = 1, 3 do
		create("Frame", {
			Size = UDim2.new(0, 1, 0.62, 0),
			Position = UDim2.new(i * 0.25, 0, 0.16, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 286,
			Parent = body,
		})
	end
	create("Frame", {
		Size = UDim2.new(0.72, 0, 0, 2),
		Position = UDim2.fromScale(0.5, 0.2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 286,
		Parent = parent,
	})
	create("Frame", {
		Size = UDim2.new(0.2, 0, 0, 2),
		Position = UDim2.fromScale(0.5, 0.14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 286,
		Parent = parent,
	})
end

local DockApps = {
	{ key = "finder", name = "访达", paint = "finder" },
	{ key = "launchpad", name = "启动台", paint = "launchpad" },
	{ key = "safari", name = "Safari 浏览器", paint = "safari" },
	{ key = "notes", name = "备忘录", paint = "notes" },
	{ key = "terminal", name = "终端", paint = "terminal" },
	{ key = "music", name = "音乐", paint = "music" },
	{ key = "settings", name = "系统设置", paint = "settings" },
	{ separator = true },
	{ key = "trash", name = "废纸篓", paint = "trash" },
}

local tooltip = create("Frame", {
	Size = UDim2.fromOffset(120, 24),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, -8),
	BackgroundColor3 = Color3.fromRGB(36, 36, 40),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 320,
	Parent = dockWrap,
})
round(tooltip, 6)
stroke(tooltip, Color3.fromRGB(255, 255, 255), 1, 1)
local tooltipLabel = label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 321,
	Parent = tooltip,
})

local function updateMagnification()
	for index, item in ipairs(DockItems) do
		local target = 1
		local lift = 0
		if Dock.hovered and not item.isSeparator and Dock.magnify and not Theme.touch then
			local distance = math.abs(index - Dock.hovered)
			local influence = 0
			if distance == 0 then
				influence = 1
			elseif distance == 1 then
				influence = 0.42
			elseif distance == 2 then
				influence = 0.14
			end
			target = 1 + 0.4 * influence
			lift = 13 * influence
		end
		if Theme.reduceMotion then
			item.spring:jump({ s = target, lift = lift })
		else
			item.spring:to({ s = target, lift = lift })
		end
	end
end

local function renderDockItem(item)
	local s = item.spring.values
	item.uiScale.Scale = s.s * Dock.fit * (item.pressed and 0.94 or 1)
	item.icon.Position = UDim2.new(0.5, 0, 1, -(Dock.bottomInset + (s.lift + item.bounce) * Dock.fit))
	item.icon.Size = UDim2.fromOffset(item.base, item.base)
end

local function bounceItem(item)
	local value = item.bounceValue
	value.Value = 0
	local up = TweenService:Create(value, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 16 })
	up:Play()
	up.Completed:Connect(function()
		TweenService:Create(value, TweenInfo.new(0.42, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = 0 }):Play()
	end)
end

local function showTooltip(item)
	if item.isSeparator or Theme.touch then
		return
	end
	tooltipLabel.Text = item.name
	tooltip.Size = UDim2.fromOffset(#item.name * 12 + 22, 24)
	local slotPos = item.slot.AbsolutePosition
	local slotSize = item.slot.AbsoluteSize
	local x = (slotPos.X + slotSize.X / 2 - canvas.AbsolutePosition.X) / canvasScale
	tooltip.Position = UDim2.new(0, x, 0, -10)
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tween(tooltip, { BackgroundTransparency = 0.12 }, TweenInfo.new(0.12))
	tween(tooltipLabel, { TextTransparency = 0 }, TweenInfo.new(0.12))
	tween(tooltip, { Position = UDim2.new(0, x, 0, -14) }, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

local function hideTooltip()
	tween(tooltip, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
	tween(tooltipLabel, { TextTransparency = 1 }, TweenInfo.new(0.1))
end

local function openApp(key)
	if key == "launchpad" then
		if _G.__MacToggleLaunchpad then
			_G.__MacToggleLaunchpad()
		end
		return
	end
	if key == "trash" then
		if showToast then
			showToast("废纸篓", "废纸篓是空的")
		end
		return
	end
	if _G.__MacOpenApp then
		_G.__MacOpenApp(key)
	end
end

local function layoutDock()
	local natural = 16 + Dock.gap * math.max(#DockItems - 1, 0)
	for _, item in ipairs(DockItems) do
		if item.isSeparator then
			natural = natural + 9
		else
			natural = natural + item.base + Dock.slotExtra
		end
	end

	local fit = clamp((canvasSize.X - 14) / math.max(natural, 1), 0.62, 1)
	Dock.fit = fit

	dockWrap.Size = UDim2.fromOffset(natural * fit, Dock.height)
	local listLayout = dockList:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.Padding = UDim.new(0, Dock.gap * fit)
	end

	for _, item in ipairs(DockItems) do
		if item.isSeparator then
			item.slot.Size = UDim2.fromOffset(9 * fit, Dock.height)
		else
			item.slot.Size = UDim2.fromOffset((item.base + Dock.slotExtra) * fit, Dock.height)
			item.uiScale.Scale = item.spring.values.s * fit * (item.pressed and 0.94 or 1)
		end
	end
end

local separatorItem

local function slotAnchorPoint(slot)
	local pos = slot.AbsolutePosition
	local size = slot.AbsoluteSize
	return Vector2.new(
		(pos.X + size.X / 2 - canvas.AbsolutePosition.X) / canvasScale,
		(pos.Y + size.Y * 0.35 - canvas.AbsolutePosition.Y) / canvasScale
	)
end

for index, app in ipairs(DockApps) do
	if app.separator then
		local slot = create("Frame", {
			Size = UDim2.fromOffset(9, Dock.height),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			ZIndex = 284,
			Parent = dockList,
		})
		create("Frame", {
			Size = UDim2.new(0, 1, 0.44, 0),
			Position = UDim2.new(0.5, 0, 0.46, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 285,
			Parent = slot,
		})
		DockItems[index] = { isSeparator = true, slot = slot }
	else
		local slot = create("TextButton", {
			Size = UDim2.fromOffset(Dock.base + Dock.slotExtra, Dock.height),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = index,
			ClipsDescendants = false,
			ZIndex = 284,
			Parent = dockList,
		})

		local icon = create("Frame", {
			Size = UDim2.fromOffset(Dock.base, Dock.base),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Dock.bottomInset),
			BackgroundTransparency = 1,
			ZIndex = 285,
			Parent = slot,
		})

		local uiS = Instance.new("UIScale")
		uiS.Parent = icon

		iconPainters[app.paint](icon, Dock.base)

		local dot = create("Frame", {
			Size = UDim2.fromOffset(3, 3),
			Position = UDim2.new(0.5, 0, 1, -2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 290,
			Parent = slot,
		})
		round(dot, 2)

		local bounceValue = Instance.new("NumberValue")
		bounceValue.Parent = slot

		local item = {
			key = app.key,
			name = app.name,
			slot = slot,
			icon = icon,
			uiScale = uiS,
			dot = dot,
			base = Dock.base,
			bounce = 0,
			bounceValue = bounceValue,
			isSeparator = false,
		}

		item.spring = newSpring({ s = 1, lift = 0 }, function(values)
			item.uiScale.Scale = values.s * (item.pressed and 0.94 or 1)
			item.icon.Position = UDim2.new(0.5, 0, 1, -(Dock.bottomInset + values.lift + item.bounce))
		end, SpringSpec.dock)

		bounceValue.Changed:Connect(function(value)
			item.bounce = value
			item.icon.Position = UDim2.new(0.5, 0, 1, -(Dock.bottomInset + item.spring.values.lift + value))
		end)

		local function setPressed(state)
			if item.isSeparator then
				return
			end
			item.pressed = state
			item.uiScale.Scale = item.spring.values.s * Dock.fit * (state and 0.94 or 1)
		end

		local function openAppMenu()
			if _G.__MacAppMenu then
				_G.__MacAppMenu(app.key, app.name, slotAnchorPoint(slot))
			end
		end

		slot.MouseEnter:Connect(function()
			Dock.hovered = index
			updateMagnification()
			showTooltip(item)
		end)
		slot.MouseLeave:Connect(function()
			if Dock.hovered == index then
				Dock.hovered = nil
			end
			setPressed(false)
			updateMagnification()
			hideTooltip()
		end)
		slot.InputBegan:Connect(function(input)
			if isPress(input) then
				setPressed(true)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				closeDropdown()
				openAppMenu()
			end
		end)
		slot.InputEnded:Connect(function(input)
			if isPress(input) then
				setPressed(false)
			end
		end)
		longPress(slot, 0.5, function()
			setPressed(false)
			hideTooltip()
			openAppMenu()
		end)
		slot.Activated:Connect(function()
			bounceItem(item)
			openApp(app.key)
		end)

		DockItems[index] = item
	end
end

layoutDock()

local function setDockIconSize(size)
	Dock.base = size
	for _, item in ipairs(DockItems) do
		if not item.isSeparator then
			item.base = size
			tween(item.icon, { Size = UDim2.fromOffset(size, size) }, TweenInfo.new(0.2, Enum.EasingStyle.Quad))
			tween(item.slot, { Size = UDim2.fromOffset(size + Dock.slotExtra, Dock.height) }, TweenInfo.new(0.2, Enum.EasingStyle.Quad))
		end
	end
	layoutDock()
end

local function setRunning(key, running)
	for _, item in ipairs(DockItems) do
		if item.key == key then
			tween(item.dot, { BackgroundTransparency = running and 0.15 or 1 }, TweenInfo.new(0.2))
		end
	end
end

onLayout(function()
	layoutDock()
end)
---------------------------------------------------------------------------
-- 10 · 窗口管理
---------------------------------------------------------------------------

local windows = {}
local focusedWindow = nil
local focusCounter = 100

-- 菜单栏底部：窗口的可用区域从这里开始
local function chromeTop()
	return Theme.topInset + Theme.menuBarHeight
end

local function toCanvasPoint(point)
	local origin = canvas.AbsolutePosition
	return Vector2.new((point.X - origin.X) / canvasScale, (point.Y - origin.Y) / canvasScale)
end

local function clampCenter(center, size)
	local halfW = size.X / 2
	local halfH = size.Y / 2
	local minX = math.min(halfW - 44, canvasSize.X / 2)
	local maxX = math.max(canvasSize.X - halfW + 44, canvasSize.X / 2)
	local minY = math.min(chromeTop() + halfH - 18, canvasSize.Y / 2)
	local maxY = math.max(canvasSize.Y - halfH + 36, canvasSize.Y / 2)
	return Vector2.new(clamp(center.X, minX, maxX), clamp(center.Y, minY, maxY))
end

local function focusWindow(win)
	if focusedWindow == win then
		return
	end
	if focusedWindow then
		focusedWindow.setFocused(false)
	end
	focusedWindow = win
	focusCounter = focusCounter + 1
	win.group.ZIndex = focusCounter
	win.setFocused(true)
end

-- 贴边分屏：macOS Sequoia 的拖到边缘平铺
local snapPreview = create("Frame", {
	Name = "SnapPreview",
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.84,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 49,
	Parent = windowLayer,
})
round(snapPreview, 10)
local previewStroke = stroke(snapPreview, Color3.fromRGB(255, 255, 255), 1, 0.45)

local function snapRect(mode)
	local top = chromeTop() + 6
	local height = canvasSize.Y - top - 8
	if mode == "left" then
		return { x = 8, y = top, w = canvasSize.X / 2 - 12, h = height }
	elseif mode == "right" then
		return { x = canvasSize.X / 2 + 4, y = top, w = canvasSize.X / 2 - 12, h = height }
	end
	return { x = 8, y = top, w = canvasSize.X - 16, h = height }
end

local function showSnapPreview(mode)
	local rect = snapRect(mode)
	snapPreview.Position = UDim2.fromOffset(rect.x, rect.y)
	snapPreview.Size = UDim2.fromOffset(rect.w, rect.h)
	if not snapPreview.Visible then
		snapPreview.Visible = true
		snapPreview.BackgroundTransparency = 1
		tween(snapPreview, { BackgroundTransparency = 0.84 }, TweenInfo.new(0.14, Enum.EasingStyle.Quad))
	end
end

local function hideSnapPreview()
	if snapPreview.Visible then
		snapPreview.Visible = false
	end
end

local function createWindow(opts)
	opts = opts or {}
	local designSize = opts.size or Vector2.new(680, 420)
	local titleHeight = Theme.titleBarHeight
	local minSize = opts.minSize or Vector2.new(360, 240)
	local designHeight = math.max(designSize.Y - titleHeight, 120)

	-- 先按画布收缩一次，保证手机竖屏也能完整放进屏幕
	local frameW = math.min(designSize.X, canvasSize.X - (Theme.compact and 12 or 28))
	local frameH = math.min(designSize.Y, canvasSize.Y - chromeTop() - (Theme.compact and 14 or 44))
	frameW = math.max(frameW, math.min(minSize.X, canvasSize.X - 8))
	frameH = math.max(frameH, math.min(minSize.Y, canvasSize.Y - chromeTop() - 8))

	local center = opts.center or Vector2.new(canvasSize.X / 2, canvasSize.Y / 2 - 10)
	center = clampCenter(center, Vector2.new(frameW, frameH))

	local group = create("CanvasGroup", {
		Name = opts.name or "Window",
		Size = UDim2.fromOffset(frameW, frameH),
		Position = UDim2.fromOffset(center.X, center.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = focusCounter,
		Parent = windowLayer,
	})

	local shadowHolder = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = group,
	})
	local shadow = makeShadow(shadowHolder, 12, { alpha = 0.05, dy = 18, spread = 2.2, layers = 14 })

	local shell = create("Frame", {
		Name = "Shell",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = opts.dark and Palette.terminal or Palette.window,
		BackgroundTransparency = opts.dark and 0.04 or 0.02,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 2,
		Parent = group,
	})
	round(shell, 11)

	local topEdge = create("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.fromOffset(12, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = opts.dark and 0.86 or 0.55,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = shell,
	})

	local titlebar = create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, titleHeight),
		BackgroundColor3 = opts.dark and Color3.fromRGB(46, 46, 49) or Palette.toolbar,
		BackgroundTransparency = opts.dark and 0.65 or 0.55,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 10,
		Parent = shell,
	})
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = opts.dark and 0.9 or 0.92,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = titlebar,
	})

	local titleLabel = label({
		Text = opts.title or "窗口",
		Size = UDim2.new(1, -220, 1, 0),
		Position = UDim2.fromOffset(110, 0),
		TextSize = Theme.touch and 14 or 13,
		Font = Font.medium,
		TextColor3 = opts.dark and Color3.fromRGB(235, 235, 240) or Palette.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12,
		Parent = titlebar,
	})

	-- 固定版式应用：内容按设计尺寸绘制，窗口小于设计尺寸时整体等比缩小并居中
	local contentHolder
	local content
	local contentScale
	if opts.scaleContent then
		contentHolder = create("Frame", {
			Name = "ContentHolder",
			Size = UDim2.new(1, 0, 1, -titleHeight),
			Position = UDim2.fromOffset(0, titleHeight),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 5,
			Parent = shell,
		})
		content = create("Frame", {
			Name = "Content",
			Size = UDim2.fromOffset(designSize.X, designHeight),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = contentHolder,
		})
		contentScale = Instance.new("UIScale")
		contentScale.Parent = content
	else
		content = create("Frame", {
			Name = "Content",
			Size = UDim2.new(1, 0, 1, -titleHeight),
			Position = UDim2.fromOffset(0, titleHeight),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = shell,
		})
	end

	local adapters = {}

	-- 交通灯：触屏用更大的命中区，但视觉尺寸仍保持 macOS 比例
	local lightColors = { Palette.red, Palette.yellow, Palette.green }
	local lightGlyphs = { "×", "-", "+" }
	local lights = {}
	local lightSize = Theme.touch and 17 or 12
	local hitSize = Theme.touch and 32 or 20
	local spacing = lightSize + (Theme.touch and 12 or 8)
	local startX = Theme.touch and 16 or 13

	for i = 1, 3 do
		local button = create("TextButton", {
			Size = UDim2.fromOffset(hitSize, hitSize),
			Position = UDim2.fromOffset(startX + (i - 1) * spacing - (hitSize - lightSize) / 2, (titleHeight - hitSize) / 2),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 14,
			Parent = titlebar,
		})
		local circle = create("Frame", {
			Size = UDim2.fromOffset(lightSize, lightSize),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = lightColors[i],
			BorderSizePixel = 0,
			ZIndex = 15,
			Parent = button,
		})
		round(circle, lightSize / 2)
		stroke(circle, Color3.new(0, 0, 0), 1, 0.85)

		local glyph = label({
			Text = lightGlyphs[i],
			Size = UDim2.fromScale(1, 1),
			TextSize = Theme.touch and 11 or 8,
			Font = Font.bold,
			TextColor3 = Color3.fromRGB(60, 30, 20),
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 16,
			Parent = circle,
		})
		lights[i] = { button = button, glyph = glyph, circle = circle }

		button.MouseEnter:Connect(function()
			tween(glyph, { TextTransparency = 0.3 }, TweenInfo.new(0.1))
		end)
		button.MouseLeave:Connect(function()
			tween(glyph, { TextTransparency = 1 }, TweenInfo.new(0.1))
		end)
	end

	titlebar.MouseEnter:Connect(function()
		for _, light in ipairs(lights) do
			tween(light.glyph, { TextTransparency = 0.55 }, TweenInfo.new(0.12))
		end
	end)
	titlebar.MouseLeave:Connect(function()
		for _, light in ipairs(lights) do
			tween(light.glyph, { TextTransparency = 1 }, TweenInfo.new(0.12))
		end
	end)

	local win = {
		group = group,
		shell = shell,
		titlebar = titlebar,
		content = content,
		titleLabel = titleLabel,
		size = Vector2.new(frameW, frameH),
		center = center,
		minSize = minSize,
		maximized = false,
		minimized = false,
		closed = false,
		appKey = opts.appKey,
		name = opts.name,
		designSize = designSize,
		titleHeight = titleHeight,
		onClose = opts.onClose,
		adapters = adapters,
	}

	local lastW, lastH = -1, -1

	local function fitContent(w, h)
		if contentScale then
			contentScale.Scale = clamp(math.min(w / designSize.X, h / math.max(designHeight, 1)), 0.4, 1)
		end
		local roundedW = math.floor(w / 2) * 2
		local roundedH = math.floor(h / 2) * 2
		if roundedW == lastW and roundedH == lastH then
			return
		end
		lastW, lastH = roundedW, roundedH
		for _, fn in ipairs(adapters) do
			fn(w, h)
		end
	end

	local function applyGeometry(values)
		local w = math.max(values.w, 40)
		local h = math.max(values.h, 34)
		group.Size = UDim2.fromOffset(w, h)
		group.Position = UDim2.fromOffset(values.cx, values.cy)
		group.GroupTransparency = clamp(values.alpha, 0, 1)
		fitContent(w, h - titleHeight)
	end

	win.spring = newSpring({
		w = frameW * 0.96,
		h = frameH * 0.96,
		cx = center.X,
		cy = center.Y,
		alpha = 1,
	}, applyGeometry, SpringSpec.window)

	win.setFocused = function(focused)
		shadow.setAlpha(focused and 0.075 or 0.05, true)
		tween(shell, { BackgroundTransparency = opts.dark and 0.04 or (focused and 0.0 or 0.04) }, TweenInfo.new(0.2))
		tween(titleLabel, { TextColor3 = opts.dark and Color3.fromRGB(240, 240, 245) or (focused and Palette.text or Palette.textSecondary) }, TweenInfo.new(0.2))
	end
	win.focus = function()
		focusWindow(win)
	end

	win.onLayout = function(fn)
		adapters[#adapters + 1] = fn
		fn(win.spring.values.w, win.spring.values.h - titleHeight)
	end

	win.setCenter = function(newCenter)
		win.center = clampCenter(newCenter, win.size)
		win.spring:jump({ cx = win.center.X, cy = win.center.Y })
	end

	win.setFrame = function(w, h, cx, cy, animate)
		w = math.max(w, 120)
		h = math.max(h, 80)
		win.size = Vector2.new(w, h)
		win.center = clampCenter(Vector2.new(cx, cy), win.size)
		if animate and not Theme.reduceMotion then
			win.spring:to({ w = w, h = h, cx = win.center.X, cy = win.center.Y }, 1.0, 0.32)
		else
			win.spring:jump({ w = w, h = h, cx = win.center.X, cy = win.center.Y })
		end
	end

	win.open = function()
		win.closed = false
		group.Visible = true
		focusWindow(win)

		local autoFull = Theme.touch and canvasSize.X < 780
		if autoFull then
			local rect = snapRect("full")
			win.maximized = true
			win.spring:jump({ w = rect.w, h = rect.h, cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2, alpha = 1 })
			return
		end

		if Theme.reduceMotion then
			win.spring:jump({ w = win.size.X, h = win.size.Y, alpha = 0 })
		else
			applyGeometry({
				w = win.size.X * 0.96,
				h = win.size.Y * 0.96,
				cx = center.X,
				cy = center.Y,
				alpha = 0.9,
			})
			win.spring:to({ w = win.size.X, h = win.size.Y, alpha = 0 }, SpringSpec.window.damping, SpringSpec.window.response)
		end
	end

	win.close = function()
		if win.closed then
			return
		end
		win.closed = true
		if win.onClose then
			win.onClose()
		end
		if Theme.reduceMotion then
			tween(group, { GroupTransparency = 1 }, TweenInfo.new(0.12)).Completed:Connect(function()
				group:Destroy()
			end)
		else
			win.spring:to({ w = win.spring.values.w * 0.94, h = win.spring.values.h * 0.94, alpha = 1 }, 1.0, 0.24)
			task.delay(0.26, function()
				group:Destroy()
			end)
		end
		for index = #windows, 1, -1 do
			if windows[index] == win then
				table.remove(windows, index)
			end
		end
		if focusedWindow == win then
			focusedWindow = nil
		end
		if win.appKey then
			local anyOpen = false
			for _, other in ipairs(windows) do
				if other.appKey == win.appKey then
					anyOpen = true
				end
			end
			if not anyOpen then
				setRunning(win.appKey, false)
			end
		end
	end

	win.zoom = function()
		if win.maximized then
			win.maximized = false
			win.center = clampCenter(win.center, win.size)
			win.spring:to({ w = win.size.X, h = win.size.Y, cx = win.center.X, cy = win.center.Y }, 1.0, 0.38)
		else
			win.maximized = true
			local rect = snapRect("full")
			win.spring:to({ w = rect.w, h = rect.h, cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2 }, 1.0, 0.38)
		end
	end

	win.minimize = function()
		if win.minimized then
			win.minimized = false
			group.Visible = true
			local targetW, targetH = win.size.X, win.size.Y
			if win.maximized then
				local rect = snapRect("full")
				targetW, targetH = rect.w, rect.h
			end
			if Theme.reduceMotion then
				win.spring:jump({ w = targetW, h = targetH, alpha = 0 })
			else
				win.spring:to({ w = targetW, h = targetH, alpha = 0 }, 0.9, 0.3)
			end
			focusWindow(win)
			return
		end
		win.minimized = true
		local target = Vector2.new(canvasSize.X / 2, canvasSize.Y - Dock.height + 10)
		for _, item in ipairs(DockItems) do
			if item.key == win.appKey then
				local abs = item.icon.AbsolutePosition
				local absSize = item.icon.AbsoluteSize
				target = toCanvasPoint(Vector2.new(abs.X + absSize.X / 2, abs.Y + absSize.Y / 2))
			end
		end
		win.spring:to({ w = 46, h = 34, cx = target.X, cy = target.Y, alpha = 0.85 }, 0.9, 0.3)
		task.delay(0.32, function()
			if win.minimized then
				group.Visible = false
			end
		end)
	end

	-- 屏幕旋转 / 分辨率变化：最大化跟随画布，普通窗口收进画布内
	win.refit = function()
		if win.closed or win.minimized then
			return
		end
		if win.maximized then
			local rect = snapRect("full")
			win.spring:jump({ w = rect.w, h = rect.h, cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2 })
			return
		end
		local maxW = canvasSize.X - 16
		local maxH = canvasSize.Y - chromeTop() - 16
		local w = math.min(win.size.X, maxW)
		local h = math.min(win.size.Y, maxH)
		win.size = Vector2.new(w, h)
		win.center = clampCenter(win.center, win.size)
		win.spring:jump({ w = w, h = h, cx = win.center.X, cy = win.center.Y })
	end

	------------------------------------------------------------------------
	-- 拖拽移动 + 贴边分屏
	------------------------------------------------------------------------
	local dragging = false
	local dragInput = nil
	local dragStart = Vector2.new(0, 0)
	local dragOffset = Vector2.new(0, 0)
	local dragMoved = false
	local snapMode = nil

	local function updateSnap(point)
		local mode = nil
		if point.Y <= chromeTop() + 8 then
			mode = "full"
		elseif point.X <= 16 then
			mode = "left"
		elseif point.X >= canvasSize.X - 16 then
			mode = "right"
		end
		if mode then
			snapMode = mode
			showSnapPreview(mode)
		else
			snapMode = nil
			hideSnapPreview()
		end
	end

	local function applySnap(mode)
		local rect = snapRect(mode)
		if mode == "full" then
			win.maximized = true
		else
			win.maximized = false
			win.size = Vector2.new(rect.w, rect.h)
			win.center = Vector2.new(rect.x + rect.w / 2, rect.y + rect.h / 2)
		end
		local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
		if mode ~= "full" then
			cx, cy = win.center.X, win.center.Y
		end
		win.spring:to({ w = rect.w, h = rect.h, cx = cx, cy = cy }, 1.0, 0.3)
	end

	titlebar.InputBegan:Connect(function(input)
		if win.minimized or not isPress(input) then
			return
		end
		focusWindow(win)
		closeDropdown()
		dragging = true
		dragInput = input
		dragStart = toCanvasPoint(Vector2.new(input.Position.X, input.Position.Y))
		dragOffset = dragStart - Vector2.new(win.spring.values.cx, win.spring.values.cy)
		dragMoved = false
		snapMode = nil
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging or not followsInput(input, dragInput) then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local point = toCanvasPoint(Vector2.new(input.Position.X, input.Position.Y))

		if not dragMoved and (point - dragStart).Magnitude > 4 then
			dragMoved = true
			if win.maximized then
				-- 从最大化拖出：按抓取位置的比例还原窗口，避免窗口跳到手指下面
				local ratio = clamp((dragStart.X - win.spring.values.cx) / math.max(win.spring.values.w, 1) + 0.5, 0.2, 0.8)
				win.maximized = false
				local w = win.size.X
				local h = win.size.Y
				win.spring:jump({ w = w, h = h })
				win.center = clampCenter(Vector2.new(point.X - w * ratio, point.Y - 20), Vector2.new(w, h))
				win.spring:jump({ cx = win.center.X, cy = win.center.Y })
				dragOffset = point - Vector2.new(win.center.X, win.center.Y)
			end
		end

		if dragMoved then
			local cx = point.X - dragOffset.X
			local cy = point.Y - dragOffset.Y
			win.center = Vector2.new(cx, cy)
			win.spring:jump({ cx = cx, cy = cy })
			updateSnap(point)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging or not followsInput(input, dragInput) then
			return
		end
		dragging = false
		dragInput = nil
		hideSnapPreview()
		if dragMoved and snapMode then
			applySnap(snapMode)
		end
		snapMode = nil
	end)

	local lastClick = 0
	titlebar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local now = os.clock()
			if now - lastClick < 0.36 then
				win.zoom()
				lastClick = 0
			else
				lastClick = now
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			closeDropdown()
		end
	end)

	------------------------------------------------------------------------
	-- 八向缩放
	------------------------------------------------------------------------
	local resizeHandles = {}
	local resizing = false
	local resizeInput = nil
	local resizeMode = nil
	local resizeStartPoint = Vector2.new(0, 0)
	local resizeStart = { w = frameW, h = frameH, cx = center.X, cy = center.Y }

	local edge = Theme.touch and 18 or 8
	local corner = Theme.touch and 26 or 16

	local function addHandle(name, mode, position, size, z)
		local handle = create("TextButton", {
			Name = name,
			Size = size,
			Position = position,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = z or 40,
			Parent = group,
		})
		if Theme.touch then
			-- 触屏不依赖 hover，给一个极淡的边缘提示，便于发现可缩放
			handle.MouseEnter:Connect(function()
				tween(handle, { BackgroundTransparency = 0.9 }, TweenInfo.new(0.12))
			end)
			handle.MouseLeave:Connect(function()
				tween(handle, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end)
		else
			handle.MouseEnter:Connect(function()
				tween(handle, { BackgroundTransparency = 0.86 }, TweenInfo.new(0.12))
			end)
			handle.MouseLeave:Connect(function()
				tween(handle, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end)
		end
		handle.InputBegan:Connect(function(input)
			if not isPress(input) or win.minimized then
				return
			end
			focusWindow(win)
			win.maximized = false
			resizing = true
			resizeInput = input
			resizeMode = mode
			resizeStartPoint = toCanvasPoint(Vector2.new(input.Position.X, input.Position.Y))
			local values = win.spring.values
			resizeStart = { w = values.w, h = values.h, cx = values.cx, cy = values.cy }
			win.size = Vector2.new(values.w, values.h)
		end)
		resizeHandles[#resizeHandles + 1] = handle
		return handle
	end

	addHandle("ResizeLeft", "l", UDim2.fromOffset(0, titleHeight), UDim2.new(0, edge, 1, -titleHeight))
	addHandle("ResizeRight", "r", UDim2.new(1, -edge, 0, titleHeight), UDim2.new(0, edge, 1, -titleHeight))
	local topStart = startX + spacing * 2 + hitSize / 2 + 4
	addHandle("ResizeTop", "t", UDim2.fromOffset(topStart, 0), UDim2.new(1, -topStart, 0, edge))
	addHandle("ResizeBottom", "b", UDim2.new(0, 1, -edge), UDim2.new(1, 0, 0, edge))
	addHandle("ResizeBottomLeft", "bl", UDim2.new(0, 1, -corner), UDim2.fromOffset(corner, corner), 41)
	addHandle("ResizeBottomRight", "br", UDim2.new(1, -corner, 1, -corner), UDim2.fromOffset(corner, corner), 41)

	local function updateResize(point)
		local dx = point.X - resizeStartPoint.X
		local dy = point.Y - resizeStartPoint.Y
		local left = resizeStart.cx - resizeStart.w / 2
		local right = resizeStart.cx + resizeStart.w / 2
		local top = resizeStart.cy - resizeStart.h / 2
		local bottom = resizeStart.cy + resizeStart.h / 2

		if string.find(resizeMode, "l", 1, true) then
			left = math.min(left + dx, right - win.minSize.X)
		end
		if string.find(resizeMode, "r", 1, true) then
			right = math.max(right + dx, left + win.minSize.X)
		end
		if string.find(resizeMode, "t", 1, true) then
			top = math.min(top + dy, bottom - win.minSize.Y)
		end
		if string.find(resizeMode, "b", 1, true) then
			bottom = math.max(bottom + dy, top + win.minSize.Y)
		end

		-- 不把窗口拖出画布
		local limitTop = chromeTop() + 2
		left = math.max(left, 4)
		right = math.min(right, canvasSize.X - 4)
		top = math.max(top, limitTop)
		bottom = math.min(bottom, canvasSize.Y - 4)

		if right - left < win.minSize.X then
			if string.find(resizeMode, "l", 1, true) then
				left = right - win.minSize.X
			else
				right = left + win.minSize.X
			end
		end
		if bottom - top < win.minSize.Y then
			if string.find(resizeMode, "t", 1, true) then
				top = bottom - win.minSize.Y
			else
				bottom = top + win.minSize.Y
			end
		end

		local w = right - left
		local h = bottom - top
		local cx = (left + right) / 2
		local cy = (top + bottom) / 2
		win.size = Vector2.new(w, h)
		win.center = Vector2.new(cx, cy)
		win.spring:jump({ w = w, h = h, cx = cx, cy = cy })
	end

	UserInputService.InputChanged:Connect(function(input)
		if not resizing or not followsInput(input, resizeInput) then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		updateResize(toCanvasPoint(Vector2.new(input.Position.X, input.Position.Y)))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if resizing and followsInput(input, resizeInput) then
			resizing = false
			resizeInput = nil
			win.center = clampCenter(win.center, win.size)
			win.spring:jump({ cx = win.center.X, cy = win.center.Y })
		end
	end)

	lights[1].button.Activated:Connect(function()
		win.close()
	end)
	lights[2].button.Activated:Connect(function()
		win.minimize()
	end)
	lights[3].button.Activated:Connect(function()
		win.zoom()
	end)

	shell.InputBegan:Connect(function(input)
		if isPress(input) then
			focusWindow(win)
			closeDropdown()
		end
	end)

	windows[#windows + 1] = win
	if opts.appKey then
		setRunning(opts.appKey, true)
	end
	win.open()

	_G.__MacCloseFocused = function()
		if focusedWindow then
			focusedWindow.close()
		end
	end
	_G.__MacMinimizeFocused = function()
		if focusedWindow then
			focusedWindow.minimize()
		end
	end
	_G.__MacZoomFocused = function()
		if focusedWindow then
			focusedWindow.zoom()
		end
	end
	_G.__MacCycleWindow = function()
		local visible = {}
		for _, other in ipairs(windows) do
			if not other.closed and not other.minimized then
				visible[#visible + 1] = other
			end
		end
		if #visible == 0 then
			return
		end
		local index = table.find(visible, focusedWindow) or 0
		local target = visible[(index % #visible) + 1]
		if target then
			target.focus()
		end
	end

	return win
end

onLayout(function()
	for _, win in ipairs(windows) do
		win.refit()
	end
end)

---------------------------------------------------------------------------
-- 11 · 通用控件
---------------------------------------------------------------------------

local accentListeners = {}

local function bindAccent(fn)
	accentListeners[#accentListeners + 1] = fn
	fn(Theme.accent)
end

local function setAccent(color)
	Theme.accent = color
	for _, fn in ipairs(accentListeners) do
		fn(color)
	end
end

local UI = {}

function UI.button(parent, opts)
	opts = opts or {}
	local primary = opts.primary ~= false
	local baseColor = opts.color or (primary and Theme.accent or Color3.fromRGB(232, 232, 236))
	local textColor = opts.textColor or (primary and Color3.fromRGB(255, 255, 255) or Palette.text)
	local button = create("TextButton", {
		Size = opts.size or UDim2.fromOffset(96, 30),
		Position = opts.position,
		AnchorPoint = opts.anchor or Vector2.new(0, 0),
		BackgroundColor3 = baseColor,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = opts.order or 0,
		ZIndex = opts.zIndex or 20,
		Parent = parent,
	})
	round(button, opts.radius or 7)
	if not primary then
		stroke(button, Color3.fromRGB(0, 0, 0), 1, 0.9)
	end

	local text = label({
		Text = opts.text or "按钮",
		Size = UDim2.fromScale(1, 1),
		TextSize = opts.textSize or 13,
		Font = Font.medium,
		TextColor3 = textColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = (opts.zIndex or 20) + 1,
		Parent = button,
	})

	if primary and not opts.color then
		bindAccent(function(color)
			baseColor = color
			button.BackgroundColor3 = color
		end)
	end

	local function press()
		tween(button, { BackgroundColor3 = baseColor:Lerp(Color3.new(0, 0, 0), 0.16) }, EASE_PRESS)
		tween(text, { TextTransparency = 0.15 }, EASE_PRESS)
	end
	local function release()
		tween(button, { BackgroundColor3 = baseColor }, TweenInfo.new(0.18, Enum.EasingStyle.Quad))
		tween(text, { TextTransparency = 0 }, TweenInfo.new(0.18, Enum.EasingStyle.Quad))
	end

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press()
		end
	end)
	button.InputEnded:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		if opts.onClick then
			opts.onClick()
		end
	end)
	return button
end

function UI.toggle(parent, opts)
	opts = opts or {}
	local w, h = 38, 22
	local value = opts.value and true or false

	local track = create("TextButton", {
		Size = UDim2.fromOffset(w, h),
		Position = opts.position,
		BackgroundColor3 = value and Theme.accent or Color3.fromRGB(210, 210, 214),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = parent,
	})
	round(track, h / 2)

	local knob = create("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(value and (w - 20) or 2, 2),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = track,
	})
	round(knob, 9)
	stroke(knob, Color3.new(0, 0, 0), 1, 0.94)

	local dragging = false
	local function apply(v, animate, silent)
		value = v
		local target = UDim2.fromOffset(v and (w - 20) or 2, 2)
		if animate and not Theme.reduceMotion then
			tween(knob, { Position = target }, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
			tween(track, { BackgroundColor3 = v and Theme.accent or Color3.fromRGB(210, 210, 214) }, TweenInfo.new(0.24))
		else
			knob.Position = target
			track.BackgroundColor3 = v and Theme.accent or Color3.fromRGB(210, 210, 214)
		end
		if not silent and opts.onChange then
			opts.onChange(v)
		end
	end

	bindAccent(function(color)
		if value then
			track.BackgroundColor3 = color
		end
	end)

	track.Activated:Connect(function()
		apply(not value, true)
	end)

	return { set = apply, get = function() return value end }
end

function UI.slider(parent, opts)
	opts = opts or {}
	local width = opts.width or 200
	local height = 28
	local minValue = opts.min or 0
	local maxValue = opts.max or 1
	local value = opts.value or minValue

	local holder = create("Frame", {
		Size = UDim2.fromOffset(width, height),
		Position = opts.position,
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local track = create("Frame", {
		Size = UDim2.new(1, 0, 0, opts.trackHeight or 5),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = opts.trackColor or Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = opts.trackTransparency or 0.86,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(track, (opts.trackHeight or 5) / 2)

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = opts.fillColor or Theme.accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	round(fill, (opts.trackHeight or 5) / 2)

	local knob = create("Frame", {
		Size = UDim2.fromOffset(opts.knobSize or 16, opts.knobSize or 16),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = holder,
	})
	round(knob, (opts.knobSize or 16) / 2)
	stroke(knob, Color3.new(0, 0, 0), 1, 0.86)

	local hit = create("TextButton", {
		Size = UDim2.new(1, 12, 1, 0),
		Position = UDim2.new(0, -6, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = holder,
	})

	local function render()
		local t = (value - minValue) / math.max(maxValue - minValue, 0.0001)
		fill.Size = UDim2.fromScale(clamp(t, 0, 1), 1)
		knob.Position = UDim2.new(clamp(t, 0, 1), 0, 0.5, 0)
	end

	local function setFromInput(positionX, silent)
		local origin = track.AbsolutePosition.X
		local span = track.AbsoluteSize.X
		local t = clamp((positionX - origin) / math.max(span, 1), 0, 1)
		value = minValue + t * (maxValue - minValue)
		render()
		if not silent and opts.onChange then
			opts.onChange(value)
		end
	end

	local dragging = false
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromInput(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromInput(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	if opts.fillColor == nil then
		bindAccent(function(color)
			fill.BackgroundColor3 = color
		end)
	end

	render()
	return {
		set = function(v, silent)
			value = v
			render()
			if not silent and opts.onChange then
				opts.onChange(value)
			end
		end,
		get = function()
			return value
		end,
	}
end

function UI.caption(parent, text, opts)
	opts = opts or {}
	return label({
		Text = text,
		Size = UDim2.new(1, 0, 0, opts.height or 16),
		Position = opts.position,
		TextSize = opts.textSize or 11,
		Font = Font.medium,
		TextColor3 = opts.color or Palette.textTertiary,
		LayoutOrder = opts.order or 0,
		ZIndex = opts.zIndex or 20,
		Parent = parent,
	})
end

function UI.clickRow(parent, opts)
	local row = create("TextButton", {
		Size = opts.size or UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Theme.accent,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = opts.order or 0,
		ZIndex = opts.zIndex or 20,
		Parent = parent,
	})
	round(row, 6)
	local text = label({
		Text = opts.text or "",
		Size = UDim2.new(1, -(opts.inset or 10) * 2, 1, 0),
		Position = UDim2.fromOffset(opts.inset or 10, 0),
		TextSize = opts.textSize or 13,
		Font = opts.bold and Font.medium or Font.regular,
		TextColor3 = opts.textColor or Palette.text,
		ZIndex = (opts.zIndex or 20) + 1,
		Parent = row,
	})
	row.MouseEnter:Connect(function()
		if opts.hoverColor then
			row.BackgroundColor3 = opts.hoverColor
		end
		tween(row, { BackgroundTransparency = opts.hoverTransparency or 0.92 }, TweenInfo.new(0.08))
	end)
	row.MouseLeave:Connect(function()
		tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
	end)
	row.Activated:Connect(function()
		if opts.onClick then
			opts.onClick()
		end
	end)
	return { row = row, label = text }
end

---------------------------------------------------------------------------
-- 12 · 通知
---------------------------------------------------------------------------

local toastLayer = create("Frame", {
	Name = "Toasts",
	Size = UDim2.new(1, -16, 1, -60),
	Position = UDim2.fromOffset(8, 40),
	BackgroundTransparency = 1,
	ZIndex = 600,
	Parent = canvas,
})
create("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = toastLayer,
})

local toastCount = 0

showToast = function(title, message, tint)
	toastCount = toastCount + 1
	local order = toastCount

	local card = create("Frame", {
		Size = UDim2.fromOffset(300, 64),
		BackgroundColor3 = Color3.fromRGB(252, 252, 254),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 601,
		Parent = toastLayer,
	})
	round(card, 14)
	stroke(card, Color3.new(0, 0, 0), 1, 0.92)

	local icon = create("Frame", {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(14, 14),
		BackgroundColor3 = tint or Theme.accent,
		BorderSizePixel = 0,
		ZIndex = 602,
		Parent = card,
	})
	round(icon, 9)
	local dot = create("Frame", {
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 603,
		Parent = icon,
	})
	round(dot, 7)

	label({
		Text = title,
		Size = UDim2.new(1, -80, 0, 18),
		Position = UDim2.fromOffset(60, 13),
		TextSize = 13,
		Font = Font.medium,
		TextColor3 = Palette.text,
		ZIndex = 602,
		Parent = card,
	})
	label({
		Text = message or "",
		Size = UDim2.new(1, -76, 0, 18),
		Position = UDim2.fromOffset(60, 31),
		TextSize = 12,
		TextColor3 = Palette.textSecondary,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 602,
		Parent = card,
	})

	card.Position = UDim2.fromOffset(40, 0)
	card.BackgroundTransparency = 1
	local startTransparency = 0.1
	local texts = {}
	for _, obj in ipairs(card:GetDescendants()) do
		if obj:IsA("TextLabel") then
			texts[#texts + 1] = obj
			obj.TextTransparency = 1
		end
	end
	if Theme.reduceMotion then
		card.Position = UDim2.fromOffset(0, 0)
		card.BackgroundTransparency = startTransparency
		for _, obj in ipairs(texts) do
			obj.TextTransparency = 0
		end
	else
		tween(card, {
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = startTransparency,
		}, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		for _, obj in ipairs(texts) do
			tween(obj, { TextTransparency = 0 }, TweenInfo.new(0.24, Enum.EasingStyle.Quad))
		end
	end

	task.delay(3, function()
		if card.Parent then
			tween(card, { BackgroundTransparency = 1 }, TweenInfo.new(0.2))
			for _, child in ipairs(card:GetDescendants()) do
				if child:IsA("TextLabel") then
					tween(child, { TextTransparency = 1 }, TweenInfo.new(0.2))
				elseif child:IsA("Frame") then
					tween(child, { BackgroundTransparency = 1 }, TweenInfo.new(0.2))
				end
			end
			task.delay(0.24, function()
				card:Destroy()
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- 13 · 控制中心
---------------------------------------------------------------------------

local controlCenter
local brightnessOverlay = create("Frame", {
	Name = "Brightness",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 900,
	Active = false,
	Parent = gui,
})

local controlCenterOpen = false

local function closeControlCenter()
	if controlCenter then
		local panel = controlCenter
		controlCenter = nil
		controlCenterOpen = false
		tween(panel, { BackgroundTransparency = 1 }, TweenInfo.new(0.14))
		for _, child in ipairs(panel:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, { TextTransparency = 1 }, TweenInfo.new(0.12))
			elseif child:IsA("Frame") or child:IsA("TextButton") then
				tween(child, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end
		end
		task.delay(0.18, function()
			panel:Destroy()
		end)
	end
end

local function buildTile(parent, opts)
	local tile = create("Frame", {
		Size = opts.size,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 631,
		Parent = parent,
	})
	round(tile, 12)
	local dot = create("Frame", {
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = opts.on and opts.color or Color3.fromRGB(120, 120, 128),
		BorderSizePixel = 0,
		ZIndex = 632,
		Parent = tile,
	})
	round(dot, 13)
	label({
		Text = opts.title,
		Size = UDim2.new(1, -50, 0, 16),
		Position = UDim2.fromOffset(44, 10),
		TextSize = 12.5,
		Font = Font.medium,
		TextColor3 = Color3.fromRGB(245, 245, 250),
		ZIndex = 632,
		Parent = tile,
	})
	label({
		Text = opts.subtitle or (opts.on and "已开启" or "已关闭"),
		Size = UDim2.new(1, -50, 0, 16),
		Position = UDim2.fromOffset(44, 27),
		TextSize = 11,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.4,
		ZIndex = 632,
		Parent = tile,
	})
	return tile
end

local function openControlCenter()
	if controlCenterOpen then
		closeControlCenter()
		return
	end
	closeDropdown()

	local width = 300
	local height = 276
	local x = canvasSize.X - width - 10
	local y = 32

	local panel = glassPanel(canvas, {
		color = Color3.fromRGB(30, 30, 34),
		transparency = 0.2,
		size = UDim2.fromOffset(width, height),
		position = UDim2.fromOffset(x, y),
		radius = 16,
		zIndex = 620,
	})
	controlCenter = panel
	controlCenterOpen = true
	panel.BackgroundTransparency = 1

	local inner = create("Frame", {
		Size = UDim2.new(1, -24, 1, -24),
		Position = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ZIndex = 621,
		Parent = panel,
	})

	buildTile(inner, {
		size = UDim2.fromOffset(130, 54),
		title = "Wi-Fi",
		subtitle = "Roblox-5G",
		color = Theme.accent,
		on = true,
	})
	local bluetooth = buildTile(inner, {
		size = UDim2.fromOffset(130, 54),
		title = "蓝牙",
		subtitle = "已开启",
		color = Theme.accent,
		on = true,
	})
	bluetooth.Position = UDim2.fromOffset(138, 0)

	local airdrop = buildTile(inner, {
		size = UDim2.fromOffset(268, 54),
		title = "隔空投送",
		subtitle = "仅限联系人",
		color = Theme.accent,
		on = true,
	})
	airdrop.Position = UDim2.fromOffset(0, 62)

	label({
		Text = "显示器",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(2, 130),
		TextSize = 11,
		Font = Font.medium,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.45,
		ZIndex = 621,
		Parent = inner,
	})
	UI.slider(inner, {
		width = 268,
		position = UDim2.fromOffset(0, 148),
		value = 0.82,
		trackColor = Color3.new(1, 1, 1),
		trackTransparency = 0.8,
		knobSize = 18,
		onChange = function(value)
			brightnessOverlay.BackgroundTransparency = 1 - value * 0.55
		end,
	})

	label({
		Text = "声音",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(2, 182),
		TextSize = 11,
		Font = Font.medium,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.45,
		ZIndex = 621,
		Parent = inner,
	})
	UI.slider(inner, {
		width = 268,
		position = UDim2.fromOffset(0, 200),
		value = 0.55,
		trackColor = Color3.new(1, 1, 1),
		trackTransparency = 0.8,
		knobSize = 18,
	})

	local reduceLabel = label({
		Text = "减弱动态效果",
		Size = UDim2.fromOffset(150, 24),
		Position = UDim2.fromOffset(2, 228),
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.15,
		ZIndex = 621,
		Parent = inner,
	})
	local reduceToggle = UI.toggle(inner, {
		value = Theme.reduceMotion,
		position = UDim2.fromOffset(230, 228),
		onChange = function(value)
			Theme.reduceMotion = value
		end,
	})

	tween(panel, { BackgroundTransparency = 0.2 }, TweenInfo.new(0.16, Enum.EasingStyle.Quad))
	for _, obj in ipairs(panel:GetDescendants()) do
		if obj:IsA("TextLabel") then
			local target = obj.TextTransparency
			obj.TextTransparency = 1
			tween(obj, { TextTransparency = target }, TweenInfo.new(0.2, Enum.EasingStyle.Quad))
		elseif obj:IsA("Frame") or obj:IsA("TextButton") then
			if obj ~= panel and obj.Name ~= "TopEdge" then
				local target = obj.BackgroundTransparency
				if target < 0.98 then
					obj.BackgroundTransparency = 1
					tween(obj, { BackgroundTransparency = target }, TweenInfo.new(0.2, Enum.EasingStyle.Quad))
				end
			end
		end
	end
end

controlButton.Activated:Connect(openControlCenter)

---------------------------------------------------------------------------
-- 14 · 桌面图标与右键菜单
---------------------------------------------------------------------------

local desktopIcons = create("Frame", {
	Size = UDim2.new(0, 100, 1, -100),
	Position = UDim2.new(1, -110, 0, 40),
	BackgroundTransparency = 1,
	ZIndex = 4,
	Parent = canvas,
})
create("UIListLayout", {
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = desktopIcons,
})

local function makeDesktopItem(parent, opts)
	local holder = create("TextButton", {
		Size = UDim2.fromOffset(88, 84),
		BackgroundColor3 = Theme.accent,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = opts.order or 1,
		ZIndex = 4,
		Parent = parent,
	})
	round(holder, 8)

	local iconArea = create("Frame", {
		Size = UDim2.fromOffset(52, 46),
		Position = UDim2.new(0.5, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = holder,
	})
	opts.paint(iconArea, 46)

	local text = label({
		Text = opts.name,
		Size = UDim2.new(1, -6, 0, 30),
		Position = UDim2.fromOffset(3, 50),
		TextSize = 11.5,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 5,
		Parent = holder,
	})
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.new(0, 0, 0)
	textStroke.Transparency = 0.55
	textStroke.Thickness = 1
	textStroke.Parent = text

	holder.MouseEnter:Connect(function()
		if not holder:GetAttribute("selected") then
			tween(holder, { BackgroundTransparency = 0.86 }, TweenInfo.new(0.1))
		end
	end)
	holder.MouseLeave:Connect(function()
		if not holder:GetAttribute("selected") then
			tween(holder, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
		end
	end)

	local lastClick = 0
	holder.Activated:Connect(function()
		local now = os.clock()
		if now - lastClick < 0.35 then
			lastClick = 0
			holder:SetAttribute("selected", false)
			tween(holder, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			if opts.onOpen then
				opts.onOpen()
			end
		else
			lastClick = now
			holder:SetAttribute("selected", true)
			tween(holder, { BackgroundTransparency = 0.72 }, TweenInfo.new(0.1))
		end
	end)
	return holder
end

local function paintDrive(parent, size)
	local body = create("Frame", {
		Size = UDim2.fromOffset(size, size * 0.62),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(226, 232, 245),
		BorderSizePixel = 0,
		Parent = parent,
	})
	round(body, 6)
	stroke(body, Color3.fromRGB(255, 255, 255), 1, 0.3)
	create("Frame", {
		Size = UDim2.new(1, -8, 0, 6),
		Position = UDim2.new(0, 4, 1, -10),
		BackgroundColor3 = Color3.fromRGB(180, 190, 210),
		BorderSizePixel = 0,
		Parent = body,
	})
	label({
		Text = "Macintosh HD",
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.12),
		TextSize = 7,
		TextColor3 = Color3.fromRGB(90, 100, 120),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	})
end

local function paintFolder(parent, size)
	local folder = create("Frame", {
		Size = UDim2.fromOffset(size, size * 0.72),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(108, 168, 245),
		BorderSizePixel = 0,
		Parent = parent,
	})
	round(folder, 5)
	local tab = create("Frame", {
		Size = UDim2.new(0.42, 0, 0.2, 0),
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(108, 168, 245),
		BorderSizePixel = 0,
		Parent = folder,
	})
	round(tab, 3)
end

makeDesktopItem(desktopIcons, { name = "Macintosh HD", paint = paintDrive, order = 1, onOpen = function() openApp("finder") end })
makeDesktopItem(desktopIcons, { name = "项目", paint = paintFolder, order = 2, onOpen = function() openApp("finder") end })

local contextMenu

local function closeContextMenu()
	if contextMenu then
		local menu = contextMenu
		contextMenu = nil
		tween(menu, { BackgroundTransparency = 1 }, TweenInfo.new(0.1))
		for _, child in ipairs(menu:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, { TextTransparency = 1 }, TweenInfo.new(0.1))
			elseif child:IsA("Frame") then
				tween(child, { BackgroundTransparency = 1 }, TweenInfo.new(0.1))
			end
		end
		task.delay(0.14, function()
			menu:Destroy()
		end)
	end
end

local function openContextMenu(position)
	closeContextMenu()
	closeDropdown()
	closeControlCenter()

	local items = {
		{ "新建文件夹", "Shift Cmd N" },
		{ "显示简介", "Cmd I" },
		{ "-" },
		{ "更改壁纸…", "", function()
			local keys = { "aurora", "midnight", "sunrise" }
			local index = table.find(keys, currentTheme) or 1
			local nextKey = keys[(index % #keys) + 1]
			buildWallpaper(nextKey, true)
			showToast("桌面与程序坞", "已切换壁纸：" .. WallpaperThemes[nextKey].name, Color3.fromRGB(120, 90, 220))
		end },
		{ "使用堆栈", "" },
		{ "-" },
		{ "关于本机", "", function()
			openApp("about")
		end },
	}

	local width = 200
	local height = 10
	for _, item in ipairs(items) do
		height = height + (item[1] == "-" and 9 or 26)
	end

	local x = clamp(position.X, 8, canvasSize.X - width - 8)
	local y = clamp(position.Y, 30, canvasSize.Y - height - 8)

	local panel = glassPanel(canvas, {
		color = Color3.fromRGB(40, 40, 44),
		transparency = 0.1,
		size = UDim2.fromOffset(width, height),
		position = UDim2.fromOffset(x, y),
		radius = 10,
		zIndex = 660,
	})
	contextMenu = panel

	local list = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 661,
		Parent = panel,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	padding(list, 5)

	for index, item in ipairs(items) do
		if item[1] == "-" then
			local holder = create("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = index,
				ZIndex = 662,
				Parent = list,
			})
			create("Frame", {
				Size = UDim2.new(1, -16, 0, 1),
				Position = UDim2.new(0, 8, 0.5, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				Parent = holder,
			})
		else
			local row = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				ZIndex = 662,
				Parent = list,
			})
			round(row, 5)
			label({
				Text = item[1],
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -84, 1, 0),
				TextSize = 13,
				TextColor3 = Color3.fromRGB(245, 245, 248),
				ZIndex = 663,
				Parent = row,
			})
			if item[2] and item[2] ~= "" then
				label({
					Text = item[2],
					Size = UDim2.new(0, 74, 1, 0),
					Position = UDim2.new(1, -76, 0, 0),
					TextSize = 10.5,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextTransparency = 0.5,
					TextXAlignment = Enum.TextXAlignment.Right,
					ZIndex = 663,
					Parent = row,
				})
			end
			row.MouseEnter:Connect(function()
				tween(row, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.08))
			end)
			row.MouseLeave:Connect(function()
				tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end)
			row.Activated:Connect(function()
				closeContextMenu()
				if item[3] then
					item[3]()
				end
			end)
		end
	end
end

local desktopDragging = false
local desktopStart = Vector2.new(0, 0)

desktopHit.Activated:Connect(function()
	dismissAll()
	closeContextMenu()
end)

desktopHit.MouseButton2Click:Connect(function()
	openContextMenu(toCanvasPoint(Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)))
end)

---------------------------------------------------------------------------
-- 15 · 应用注册与窗口复用
---------------------------------------------------------------------------

local builders = {}
local appWindows = {}

local appNames = {
	finder = "访达",
	safari = "Safari 浏览器",
	notes = "备忘录",
	terminal = "终端",
	music = "音乐",
	settings = "系统设置",
	about = "关于本机",
}

openApp = function(key)
	local builder = builders[key]
	if not builder then
		showToast(appNames[key] or "应用", "该应用暂未安装", Color3.fromRGB(140, 140, 150))
		return
	end
	local existing = appWindows[key]
	if existing and not existing.closed then
		if existing.minimized then
			existing.minimize()
		else
			existing.focus()
		end
		return
	end
	appWindows[key] = builder()
end

_G.__MacOpenApp = openApp
_G.__MacOpenAbout = function()
	openApp("about")
end

closeOverlays = function()
	closeDropdown()
	closeControlCenter()
	closeContextMenu()
end

---------------------------------------------------------------------------
-- 16 · 图标绘制（文件 / 侧边栏）
---------------------------------------------------------------------------

local function clearChildren(inst)
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function paintFolderSmall(parent, size)
	local base = create("Frame", {
		Size = UDim2.fromOffset(size, size * 0.7),
		Position = UDim2.new(0.5, 0, 0.5, size * 0.06),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(104, 166, 245),
		BorderSizePixel = 0,
		Parent = parent,
	})
	round(base, size * 0.1)
	create("Frame", {
		Size = UDim2.new(0.44, 0, 0.24, 0),
		Position = UDim2.new(0.06, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(104, 166, 245),
		BorderSizePixel = 0,
		Parent = base,
	})
	local sheen = create("Frame", {
		Size = UDim2.new(1, 0, 0.34, 0),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = base,
	})
	round(sheen, size * 0.1)
end

local docColors = {
	doc = Color3.fromRGB(90, 140, 220),
	pdf = Color3.fromRGB(235, 92, 86),
	image = Color3.fromRGB(120, 190, 130),
	code = Color3.fromRGB(150, 120, 220),
	audio = Color3.fromRGB(240, 150, 90),
}

local function paintDocIcon(parent, size, kind)
	local tint = docColors[kind] or docColors.doc
	local page = create("Frame", {
		Size = UDim2.fromOffset(size * 0.74, size * 0.92),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = parent,
	})
	round(page, size * 0.07)
	stroke(page, Color3.fromRGB(0, 0, 0), 1, 0.9)

	local corner = create("Frame", {
		Size = UDim2.fromOffset(size * 0.2, size * 0.2),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(240, 242, 246),
		BorderSizePixel = 0,
		Parent = page,
	})
	corner.Rotation = 0
	local tri = Instance.new("UICorner")
	tri.CornerRadius = UDim.new(0, 0)
	tri.Parent = corner

	for i = 1, 3 do
		create("Frame", {
			Size = UDim2.new(0.6 - i * 0.06, 0, 0, math.max(1, size * 0.045)),
			Position = UDim2.new(0.16, 0, 0.3 + (i - 1) * 0.14, 0),
			BackgroundColor3 = Color3.fromRGB(190, 194, 202),
			BorderSizePixel = 0,
			Parent = page,
		})
	end

	create("Frame", {
		Size = UDim2.new(0.36, 0, 0, math.max(2, size * 0.09)),
		Position = UDim2.new(0.16, 0, 0.82, 0),
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		Parent = page,
	})
end

-- 侧边栏符号
local function sidebarGlyph(parent, kind, size, color)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local c = color or Color3.fromRGB(110, 110, 120)

	if kind == "clock" then
		local ring = create("Frame", {
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		round(ring, size)
		stroke(ring, c, 1.4, 0.15)
		create("Frame", {
			Size = UDim2.new(0, 1.2, 0.26, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = ring,
		})
		create("Frame", {
			Size = UDim2.new(0.24, 0, 0, 1.2),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = ring,
		})
	elseif kind == "apps" then
		for i = 0, 3 do
			local cell = create("Frame", {
				Size = UDim2.fromScale(0.34, 0.34),
				Position = UDim2.fromScale(0.12 + (i % 2) * 0.42, 0.12 + math.floor(i / 2) * 0.42),
				BackgroundColor3 = c,
				BorderSizePixel = 0,
				Parent = holder,
			})
			round(cell, size * 0.06)
		end
	elseif kind == "desktop" then
		local screen = create("Frame", {
			Size = UDim2.new(0.9, 0, 0.64, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		round(screen, size * 0.12)
		stroke(screen, c, 1.4, 0.1)
		create("Frame", {
			Size = UDim2.new(0.34, 0, 0, 1.4),
			Position = UDim2.new(0.5, 0, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = holder,
		})
	elseif kind == "doc" then
		local page = create("Frame", {
			Size = UDim2.new(0.64, 0, 0.84, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		round(page, size * 0.1)
		stroke(page, c, 1.4, 0.1)
		for i = 1, 2 do
			create("Frame", {
				Size = UDim2.new(0.56, 0, 0, 1.2),
				Position = UDim2.new(0.22, 0, 0.34 + (i - 1) * 0.22, 0),
				BackgroundColor3 = c,
				BorderSizePixel = 0,
				Parent = page,
			})
		end
	elseif kind == "download" then
		create("Frame", {
			Size = UDim2.new(0, 1.4, 0.44, 0),
			Position = UDim2.new(0.5, 0, 0.06, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = holder,
		})
		local chevronL = create("Frame", {
			Size = UDim2.new(0.34, 0, 0, 1.6),
			Position = UDim2.new(0.5, -size * 0.09, 0.5, -size * 0.12),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Rotation = 45,
			Parent = holder,
		})
		chevronL.Name = "ChevronL"
		local chevronR = create("Frame", {
			Size = UDim2.new(0.34, 0, 0, 1.6),
			Position = UDim2.new(0.5, size * 0.09, 0.5, -size * 0.12),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Rotation = -45,
			Parent = holder,
		})
		chevronR.Name = "ChevronR"
		create("Frame", {
			Size = UDim2.new(0.5, 0, 0, 1.4),
			Position = UDim2.new(0.5, 0, 0.88, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = holder,
		})
	elseif kind == "airdrop" then
		local ring = create("Frame", {
			Size = UDim2.fromScale(0.84, 0.84),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		round(ring, size)
		stroke(ring, c, 1.4, 0.1)
		local dot = create("Frame", {
			Size = UDim2.fromOffset(2.4, 2.4),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			Parent = ring,
		})
		round(dot, 2)
	end

	return holder
end

---------------------------------------------------------------------------
-- 17 · 访达
---------------------------------------------------------------------------

local FinderData = {
	["最近项目"] = {
		{ name = "Roblox 项目", type = "folder" },
		{ name = "界面设计.fig", type = "file", kind = "code" },
		{ name = "会议记录.md", type = "file", kind = "doc" },
		{ name = "封面.png", type = "file", kind = "image" },
		{ name = "发布会.key", type = "file", kind = "doc" },
		{ name = "预算表.numbers", type = "file", kind = "doc" },
	},
	["桌面"] = {
		{ name = "Roblox 项目", type = "folder" },
		{ name = "截图", type = "folder" },
		{ name = "界面设计.fig", type = "file", kind = "code" },
		{ name = "简历.pdf", type = "file", kind = "pdf" },
		{ name = "封面.png", type = "file", kind = "image" },
		{ name = "灵感.md", type = "file", kind = "doc" },
	},
	["文稿"] = {
		{ name = "设计系统", type = "folder" },
		{ name = "合同", type = "folder" },
		{ name = "项目提案.pdf", type = "file", kind = "pdf" },
		{ name = "组件清单.md", type = "file", kind = "doc" },
		{ name = "演示.key", type = "file", kind = "doc" },
		{ name = "配乐.mp3", type = "file", kind = "audio" },
		{ name = "数据.csv", type = "file", kind = "code" },
		{ name = "截图.png", type = "file", kind = "image" },
	},
	["下载"] = {
		{ name = "macOS 图标包", type = "folder" },
		{ name = "installer.dmg", type = "file", kind = "doc" },
		{ name = "字体.zip", type = "file", kind = "doc" },
		{ name = "壁纸 4K.png", type = "file", kind = "image" },
	},
	["应用程序"] = {
		{ name = "访达", type = "file", kind = "doc" },
		{ name = "Safari", type = "file", kind = "doc" },
		{ name = "备忘录", type = "file", kind = "doc" },
		{ name = "终端", type = "file", kind = "code" },
		{ name = "音乐", type = "file", kind = "audio" },
		{ name = "系统设置", type = "file", kind = "doc" },
	},
	["Roblox 项目"] = {
		{ name = "界面原型.rbxm", type = "file", kind = "code" },
		{ name = "组件库.rbxm", type = "file", kind = "code" },
		{ name = "素材", type = "folder" },
		{ name = "说明.md", type = "file", kind = "doc" },
		{ name = "演示.mp4", type = "file", kind = "audio" },
	},
	["截图"] = {
		{ name = "屏幕快照 1.png", type = "file", kind = "image" },
		{ name = "屏幕快照 2.png", type = "file", kind = "image" },
		{ name = "屏幕快照 3.png", type = "file", kind = "image" },
	},
	["素材"] = {
		{ name = "图标", type = "folder" },
		{ name = "壁纸.png", type = "file", kind = "image" },
		{ name = "字体授权.pdf", type = "file", kind = "pdf" },
	},
	["设计系统"] = {
		{ name = "颜色规范.md", type = "file", kind = "doc" },
		{ name = "动效曲线.md", type = "file", kind = "doc" },
		{ name = "组件清单.csv", type = "file", kind = "code" },
		{ name = "标注.png", type = "file", kind = "image" },
	},
	["合同"] = {
		{ name = "服务协议.pdf", type = "file", kind = "pdf" },
		{ name = "保密协议.pdf", type = "file", kind = "pdf" },
	},
	["macOS 图标包"] = {
		{ name = "Finder.icns", type = "file", kind = "image" },
		{ name = "Safari.icns", type = "file", kind = "image" },
		{ name = "Notes.icns", type = "file", kind = "image" },
		{ name = "说明.txt", type = "file", kind = "doc" },
	},
	["图标"] = {
		{ name = "app-icon.png", type = "file", kind = "image" },
		{ name = "dock.png", type = "file", kind = "image" },
	},
}

local function buildFinder()
	local win = createWindow({
		name = "Finder",
		title = "文稿",
		appKey = "finder",
		size = Vector2.new(720, 452),
		center = Vector2.new(canvasSize.X / 2, canvasSize.Y / 2 - 16),
	})
	win.titleLabel.Text = ""

	local root = win.content
	local sidebarWidth = 178

	local sidebar = create("Frame", {
		Size = UDim2.new(0, sidebarWidth, 1, 0),
		BackgroundColor3 = Palette.sidebar,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	create("Frame", {
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = sidebar,
	})

	local sidebarList = create("Frame", {
		Size = UDim2.new(1, -16, 1, -24),
		Position = UDim2.fromOffset(8, 12),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = sidebar,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sidebarList,
	})

	local sections = {
		{ "个人收藏", {
			{ name = "隔空投送", glyph = "airdrop" },
			{ name = "最近项目", glyph = "clock" },
			{ name = "应用程序", glyph = "apps" },
			{ name = "桌面", glyph = "desktop" },
			{ name = "文稿", glyph = "doc", selected = true },
			{ name = "下载", glyph = "download" },
		} },
		{ "标签", {
			{ name = "重要", dot = Color3.fromRGB(255, 96, 92) },
			{ name = "进行中", dot = Color3.fromRGB(254, 188, 46) },
			{ name = "归档", dot = Color3.fromRGB(120, 200, 120) },
		} },
	}

	local selectionRows = {}
	local currentSelection

	local function selectRow(rowInfo)
		for _, info in ipairs(selectionRows) do
			info.setActive(info == rowInfo)
		end
		currentSelection = rowInfo
	end

	local order = 0
	for _, section in ipairs(sections) do
		order = order + 1
		local header = label({
			Text = section[1],
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 10.5,
			Font = Font.medium,
			TextColor3 = Palette.textTertiary,
			LayoutOrder = order,
			ZIndex = 8,
			Parent = sidebarList,
		})
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = "  " .. section[1]

		for _, entry in ipairs(section[2]) do
			order = order + 1
			local row = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = Theme.accent,
				BackgroundTransparency = entry.selected and 0.86 or 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = order,
				ZIndex = 8,
				Parent = sidebarList,
			})
			round(row, 6)

			local iconHolder = create("Frame", {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(8, 6),
				BackgroundTransparency = 1,
				ZIndex = 9,
				Parent = row,
			})
			if entry.glyph then
				sidebarGlyph(iconHolder, entry.glyph, 15, Color3.fromRGB(104, 112, 128))
			elseif entry.dot then
				local dot = create("Frame", {
					Size = UDim2.fromOffset(9, 9),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = entry.dot,
					BorderSizePixel = 0,
					ZIndex = 9,
					Parent = iconHolder,
				})
				round(dot, 5)
			end

			local text = label({
				Text = entry.name,
				Size = UDim2.new(1, -40, 1, 0),
				Position = UDim2.fromOffset(30, 0),
				TextSize = 12.5,
				TextColor3 = entry.selected and Theme.accent or Palette.text,
				ZIndex = 9,
				Parent = row,
			})

			local info = {}
			info.setActive = function(active)
				tween(row, { BackgroundTransparency = active and 0.86 or 1 }, TweenInfo.new(0.12))
				text.TextColor3 = active and Theme.accent or Palette.text
			end
			selectionRows[#selectionRows + 1] = info

			row.MouseEnter:Connect(function()
				if currentSelection ~= info then
					tween(row, { BackgroundTransparency = 0.94 }, TweenInfo.new(0.08))
				end
			end)
			row.MouseLeave:Connect(function()
				if currentSelection ~= info then
					tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
				end
			end)
			row.Activated:Connect(function()
				selectRow(info)
				if FinderData[entry.name] then
					-- 由下方导航逻辑接管
				end
			end)
			info.row = row
			info.name = entry.name
			info.text = text
		end
	end

	local toolbar = create("Frame", {
		Size = UDim2.new(1, -sidebarWidth, 0, 46),
		Position = UDim2.fromOffset(sidebarWidth, 0),
		BackgroundColor3 = Palette.toolbar,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = toolbar,
	})

	local navGroup = create("Frame", {
		Size = UDim2.fromOffset(56, 28),
		Position = UDim2.fromOffset(12, 9),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.94,
		ZIndex = 8,
		Parent = toolbar,
	})
	round(navGroup, 6)

	local backBtn = create("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Text = "<",
		Font = Font.medium,
		TextSize = 18,
		TextColor3 = Palette.textSecondary,
		AutoButtonColor = false,
		ZIndex = 9,
		Parent = navGroup,
	})
	local forwardBtn = create("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(28, 0),
		BackgroundTransparency = 1,
		Text = ">",
		Font = Font.medium,
		TextSize = 18,
		TextColor3 = Palette.textTertiary,
		AutoButtonColor = false,
		ZIndex = 9,
		Parent = navGroup,
	})

	local pathLabel = label({
		Text = "文稿",
		Size = UDim2.new(0, 220, 1, 0),
		Position = UDim2.fromOffset(80, 0),
		TextSize = 13,
		Font = Font.medium,
		TextColor3 = Palette.text,
		ZIndex = 8,
		Parent = toolbar,
	})

	local searchField = create("Frame", {
		Size = UDim2.fromOffset(160, 26),
		Position = UDim2.new(1, -172, 0, 10),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.92,
		ZIndex = 8,
		Parent = toolbar,
	})
	round(searchField, 7)
	local magnifier = create("Frame", {
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.fromOffset(8, 7),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = searchField,
	})
	round(magnifier, 5)
	stroke(magnifier, Palette.textTertiary, 1.3, 0.2)
	create("Frame", {
		Size = UDim2.fromOffset(5, 1.3),
		Position = UDim2.new(1, 1, 1, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Palette.textTertiary,
		BorderSizePixel = 0,
		Rotation = 45,
		ZIndex = 9,
		Parent = magnifier,
	})
	label({
		Text = "搜索",
		Size = UDim2.new(1, -26, 1, 0),
		Position = UDim2.fromOffset(23, 0),
		TextSize = 12,
		TextColor3 = Palette.textTertiary,
		ZIndex = 9,
		Parent = searchField,
	})

	local grid = create("ScrollingFrame", {
		Size = UDim2.new(1, -sidebarWidth - 24, 1, -90),
		Position = UDim2.fromOffset(sidebarWidth + 12, 46 + 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
		Parent = root,
	})
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(104, 92),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local statusBar = create("Frame", {
		Size = UDim2.new(1, -sidebarWidth, 0, 26),
		Position = UDim2.new(0, sidebarWidth, 1, -26),
		BackgroundColor3 = Palette.toolbar,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	local countLabel = label({
		Text = "",
		Size = UDim2.new(1, -150, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		TextSize = 11,
		TextColor3 = Palette.textTertiary,
		ZIndex = 7,
		Parent = statusBar,
	})
	label({
		Text = "128.4 GB 可用",
		Size = UDim2.new(0, 140, 1, 0),
		Position = UDim2.new(1, -150, 0, 0),
		TextSize = 11,
		TextColor3 = Palette.textTertiary,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
		Parent = statusBar,
	})

	local history = { "文稿" }
	local historyIndex = 1
	local selectedCard
	local cardSelectors = {}
	local lastClickCard
	local lastClickTime = 0

	local function pushPath(name)
		for i = #history, historyIndex + 1, -1 do
			table.remove(history, i)
		end
		table.insert(history, name)
		historyIndex = #history
	end

	local function renderPath()
		local path = history[historyIndex]
		pathLabel.Text = path
		for _, item in ipairs(selectionRows) do
			if item.name == path then
				selectRow(item)
			end
		end
	end

	local function renderFiles()
		clearChildren(grid)
		selectedCard = nil
		cardSelectors = {}
		local path = history[historyIndex]
		local files = FinderData[path] or FinderData["文稿"]
		countLabel.Text = string.format("%d 个项目，128.4 GB 可用", #files)

		for index, file in ipairs(files) do
			local card = create("TextButton", {
				Size = UDim2.fromOffset(104, 92),
				BackgroundColor3 = Theme.accent,
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				ZIndex = 7,
				Parent = grid,
			})
			round(card, 8)

			local iconArea = create("Frame", {
				Size = UDim2.fromOffset(48, 48),
				Position = UDim2.new(0.5, 0, 0, 8),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				ZIndex = 8,
				Parent = card,
			})
			if file.type == "folder" then
				paintFolderSmall(iconArea, 48)
			else
				paintDocIcon(iconArea, 48, file.kind)
			end

			local nameLabel = label({
				Text = file.name,
				Size = UDim2.new(1, -8, 0, 30),
				Position = UDim2.fromOffset(4, 58),
				TextSize = 11.5,
				TextColor3 = Palette.text,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				ZIndex = 8,
				Parent = card,
			})

			local function setSelected(state)
				tween(card, { BackgroundTransparency = state and 0.86 or 1 }, TweenInfo.new(0.12))
				nameLabel.TextColor3 = state and Theme.accent or Palette.text
				card:SetAttribute("selected", state)
				if state then
					selectedCard = card
				elseif selectedCard == card then
					selectedCard = nil
				end
			end
			cardSelectors[card] = setSelected

			card.MouseEnter:Connect(function()
				if not card:GetAttribute("selected") then
					tween(card, { BackgroundTransparency = 0.94 }, TweenInfo.new(0.08))
				end
			end)
			card.MouseLeave:Connect(function()
				if not card:GetAttribute("selected") then
					tween(card, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
				end
			end)

			card.Activated:Connect(function()
				local now = os.clock()
				local doubleClick = lastClickCard == card and (now - lastClickTime) < 0.35
				lastClickCard = card
				lastClickTime = now

				if selectedCard and selectedCard ~= card and cardSelectors[selectedCard] then
					cardSelectors[selectedCard](false)
				end
				setSelected(true)

				if doubleClick then
					if file.type == "folder" then
						pushPath(file.name)
						renderFiles()
						renderPath()
					else
						showToast(file.name, "已在预览中打开", Color3.fromRGB(120, 130, 150))
					end
				end
			end)
		end
	end

	for _, info in ipairs(selectionRows) do
		info.row.Activated:Connect(function()
			if FinderData[info.name] and history[historyIndex] ~= info.name then
				pushPath(info.name)
				renderFiles()
				renderPath()
			end
		end)
	end

	backBtn.Activated:Connect(function()
		if historyIndex > 1 then
			historyIndex = historyIndex - 1
			renderFiles()
			renderPath()
		end
	end)
	forwardBtn.Activated:Connect(function()
		if historyIndex < #history then
			historyIndex = historyIndex + 1
			renderFiles()
			renderPath()
		end
	end)

	renderFiles()
	renderPath()

	-- 窗口缩放：窄窗口收起侧边栏，网格与工具栏跟着重排
	win.onLayout(function(w, h)
		local narrow = w < 560
		local side = narrow and 0 or math.min(sidebarWidth, math.floor(w * 0.3))
		sidebar.Visible = not narrow
		sidebar.Size = UDim2.new(0, side, 1, 0)
		toolbar.Position = UDim2.fromOffset(side, 0)
		toolbar.Size = UDim2.new(1, -side, 0, 46)
		grid.Position = UDim2.fromOffset(side + 12, 56)
		grid.Size = UDim2.new(1, -side - 24, 1, -90)
		statusBar.Position = UDim2.new(0, side, 1, -26)
		statusBar.Size = UDim2.new(1, -side, 0, 26)
		pathLabel.Size = UDim2.new(0, math.max(60, w - side - 200), 1, 0)
		searchField.Visible = (w - side) > 430
		local layout = grid:FindFirstChildOfClass("UIGridLayout")
		if layout then
			layout.CellSize = UDim2.fromOffset(w < 420 and 90 or 104, w < 420 and 86 or 92)
		end
	end)

	win.onClose = function()
		appWindows.finder = nil
	end
	return win
end

builders.finder = buildFinder

---------------------------------------------------------------------------
-- 18 · 备忘录
---------------------------------------------------------------------------

local NotesData = {
	{
		title = "设计评审要点",
		preview = "把动效当作信息层级的一部分，而不是装饰…",
		date = "今天 06:12",
		body = "把动效当作信息层级的一部分，而不是装饰。\n\n1. 入场用 ease-out，出场用 ease-in。\n2. 大表面移动时降低透明度，稳定后再恢复。\n3. 按压缩放 0.97，100ms 内完成，指针按下即反馈。\n4. 阴影用半透明黑色堆叠，不要用实色边框。",
	},
	{
		title = "Dock 放大算法",
		preview = "影响范围按与指针的距离衰减，0.42 / 0.14…",
		date = "昨天 22:40",
		body = "影响范围按与指针的距离衰减：\n\nscale = 1 + 0.40 * influence\ninfluence: d=0 → 1, d=1 → 0.42, d=2 → 0.14\n\n用临界阻尼弹簧（damping 0.74，response 0.28）避免机械感；\n指针离开后回落不要有回弹。",
	},
	{
		title = "颜色规范",
		preview = "文字不要用纯黑，深灰更耐看…",
		date = "10月31日",
		body = "文字：#1D1D1F\n次级：#6E6E73\n分隔线：黑色 8% 透明度\n强调色：跟随系统 Accent Color\n\n玻璃材质：白色 60–75% 透明度 + 顶部 1px 亮边。\n不要把浅色半透明叠在另一层浅色半透明上。",
	},
}

local function buildNotes()
	local win = createWindow({
		name = "Notes",
		title = "备忘录",
		appKey = "notes",
		size = Vector2.new(680, 440),
		center = Vector2.new(canvasSize.X / 2 + 30, canvasSize.Y / 2 - 26),
	})
	win.titleLabel.Text = ""

	local root = win.content
	local sidebarWidth = 208
	local currentIndex = 1
	local rowRefreshers = {}

	local sidebar = create("Frame", {
		Size = UDim2.new(0, sidebarWidth, 1, 0),
		BackgroundColor3 = Palette.sidebar,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	create("Frame", {
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = sidebar,
	})

	label({
		Text = "备忘录",
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.fromOffset(16, 14),
		TextSize = 15,
		Font = Font.bold,
		ZIndex = 8,
		Parent = sidebar,
	})

	local newButton = create("TextButton", {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -36, 0, 14),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.94,
		Text = "+",
		Font = Font.medium,
		TextSize = 15,
		TextColor3 = Palette.textSecondary,
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = sidebar,
	})
	round(newButton, 6)

	local search = create("Frame", {
		Size = UDim2.new(1, -28, 0, 24),
		Position = UDim2.fromOffset(14, 44),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.93,
		ZIndex = 8,
		Parent = sidebar,
	})
	round(search, 6)
	label({
		Text = "搜索",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextSize = 11.5,
		TextColor3 = Palette.textTertiary,
		ZIndex = 9,
		Parent = search,
	})

	local list = create("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -84),
		Position = UDim2.fromOffset(8, 76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.new(0, 0, 0),
		ScrollBarImageTransparency = 0.75,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 8,
		Parent = sidebar,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	-- 编辑器
	local editor = create("Frame", {
		Size = UDim2.new(1, -sidebarWidth, 1, 0),
		Position = UDim2.fromOffset(sidebarWidth, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})

	local titleBox = create("TextBox", {
		Size = UDim2.new(1, -48, 0, 26),
		Position = UDim2.fromOffset(24, 18),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Font.bold,
		TextSize = 18,
		TextColor3 = Palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		Text = "",
		ZIndex = 7,
		Parent = editor,
	})

	local metaLabel = label({
		Text = "",
		Size = UDim2.new(1, -48, 0, 14),
		Position = UDim2.fromOffset(24, 46),
		TextSize = 10.5,
		TextColor3 = Palette.textTertiary,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
		Parent = editor,
	})

	local bodyBox = create("TextBox", {
		Size = UDim2.new(1, -48, 1, -86),
		Position = UDim2.fromOffset(24, 68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Font.regular,
		TextSize = 13.5,
		TextColor3 = Palette.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		PlaceholderText = "开始输入…",
		PlaceholderColor3 = Palette.textTertiary,
		Text = "",
		ZIndex = 7,
		Parent = editor,
	})

	local function saveCurrent()
		local note = NotesData[currentIndex]
		if note then
			note.title = titleBox.Text
			note.body = bodyBox.Text
			note.preview = string.gsub(bodyBox.Text, "\n", " ")
		end
	end

	local function selectNote(index)
		if index == currentIndex then
			return
		end
		saveCurrent()
		currentIndex = index
		local note = NotesData[index]
		titleBox.Text = note.title
		bodyBox.Text = note.body
		metaLabel.Text = note.date .. "  ·  " .. tostring(#note.body) .. " 个字符"
		for _, refresh in ipairs(rowRefreshers) do
			refresh()
		end
	end

	local function buildRows()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowRefreshers = {}

		for index, note in ipairs(NotesData) do
			local row = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 62),
				BackgroundColor3 = Theme.accent,
				BackgroundTransparency = index == currentIndex and 0.88 or 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				ZIndex = 9,
				Parent = list,
			})
			round(row, 7)

			local title = label({
				Text = note.title,
				Size = UDim2.new(1, -24, 0, 18),
				Position = UDim2.fromOffset(10, 8),
				TextSize = 12.5,
				Font = Font.medium,
				TextColor3 = Palette.text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 10,
				Parent = row,
			})
			local preview = label({
				Text = note.preview,
				Size = UDim2.new(1, -24, 0, 14),
				Position = UDim2.fromOffset(10, 26),
				TextSize = 10.5,
				TextColor3 = Palette.textTertiary,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 10,
				Parent = row,
			})
			local date = label({
				Text = note.date,
				Size = UDim2.new(1, -24, 0, 14),
				Position = UDim2.fromOffset(10, 42),
				TextSize = 10,
				TextColor3 = Palette.textTertiary,
				ZIndex = 10,
				Parent = row,
			})

			local function refresh()
				local active = index == currentIndex
				row.BackgroundTransparency = active and 0.88 or 1
				title.TextColor3 = active and Theme.accent or Palette.text
			end
			rowRefreshers[#rowRefreshers + 1] = refresh
			refresh()

			row.MouseEnter:Connect(function()
				if index ~= currentIndex then
					tween(row, { BackgroundTransparency = 0.95 }, TweenInfo.new(0.08))
				end
			end)
			row.MouseLeave:Connect(function()
				if index ~= currentIndex then
					tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
				end
			end)
			row.Activated:Connect(function()
				selectNote(index)
			end)
		end
	end

	titleBox.Text = NotesData[1].title
	bodyBox.Text = NotesData[1].body
	metaLabel.Text = NotesData[1].date .. "  ·  " .. tostring(#NotesData[1].body) .. " 个字符"
	buildRows()

	newButton.Activated:Connect(function()
		saveCurrent()
		table.insert(NotesData, 1, {
			title = "新建备忘录",
			preview = "",
			date = "刚刚",
			body = "",
		})
		currentIndex = 1
		titleBox.Text = NotesData[1].title
		bodyBox.Text = ""
		metaLabel.Text = "刚刚"
		buildRows()
		titleBox:CaptureFocus()
	end)

	-- 窗口缩放：窄窗口隐藏列表，编辑器占满
	win.onLayout(function(w, h)
		local narrow = w < 560
		local side = narrow and 0 or math.min(sidebarWidth, math.floor(w * 0.34))
		sidebar.Visible = not narrow
		sidebar.Size = UDim2.new(0, side, 1, 0)
		editor.Position = UDim2.fromOffset(side, 0)
		editor.Size = UDim2.new(1, -side, 1, 0)
	end)

	win.onClose = function()
		saveCurrent()
		appWindows.notes = nil
	end
	return win
end

builders.notes = buildNotes

---------------------------------------------------------------------------
-- 19 · 终端
---------------------------------------------------------------------------

local function escapeRich(text)
	local result = string.gsub(text, "&", "&amp;")
	result = string.gsub(result, "<", "&lt;")
	result = string.gsub(result, ">", "&gt;")
	return result
end

local function buildTerminal()
	local win = createWindow({
		name = "Terminal",
		title = "roblox — zsh — 80×24",
		appKey = "terminal",
		dark = true,
		size = Vector2.new(640, 392),
		center = Vector2.new(canvasSize.X / 2 - 40, canvasSize.Y / 2 + 16),
	})

	local root = win.content
	root.BackgroundColor3 = Color3.fromRGB(26, 26, 28)
	root.BackgroundTransparency = 0.04

	local lines = {}

	local scroll = create("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -58),
		Position = UDim2.fromOffset(14, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
		Parent = root,
	})

	local output = create("TextLabel", {
		Size = UDim2.new(1, -6, 0, 0),
		BackgroundTransparency = 1,
		Font = Font.mono,
		TextSize = 12.5,
		TextColor3 = Palette.terminalText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		ZIndex = 7,
		Parent = scroll,
	})

	local function render()
		output.Text = table.concat(lines, "\n")
		task.defer(function()
			scroll.CanvasPosition = Vector2.new(0, math.max(0, output.AbsoluteSize.Y - scroll.AbsoluteSize.Y + 20))
		end)
	end

	local function push(text)
		lines[#lines + 1] = text
		render()
	end

	local promptRow = create("Frame", {
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.new(0, 14, 1, -34),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})

	local promptLabel = label({
		Text = "roblox@macbook ~ %",
		Size = UDim2.fromOffset(148, 26),
		TextSize = 12.5,
		Font = Font.mono,
		TextColor3 = Color3.fromRGB(120, 220, 160),
		ZIndex = 7,
		Parent = promptRow,
	})

	local input = create("TextBox", {
		Size = UDim2.new(1, -152, 1, 0),
		Position = UDim2.fromOffset(152, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Font.mono,
		TextSize = 12.5,
		TextColor3 = Color3.fromRGB(240, 240, 245),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		Text = "",
		ZIndex = 7,
		Parent = promptRow,
	})

	local commands = {}

	local function run(raw)
		local trimmed = string.gsub(raw, "^%s+", "")
		trimmed = string.gsub(trimmed, "%s+$", "")
		push('<font color="#8be9b0">roblox@macbook</font> <font color="#7aa2f7">~</font> % ' .. escapeRich(raw))
		if trimmed == "" then
			return
		end

		local rawName, rawRest = string.match(trimmed, "^(%S+)%s*(.*)$")
		local name = rawName and string.lower(rawName) or ""
		local rest = rawRest or ""

		if name == "help" then
			push("可用命令：")
			push("  help            显示帮助")
			push("  ls              列出当前目录")
			push("  whoami          当前用户")
			push("  date            系统时间")
			push("  neofetch        系统信息")
			push("  open <app>      打开应用 (finder/notes/settings/music)")
			push("  echo <text>     回显文本")
			push("  clear           清屏")
		elseif name == "ls" then
			push("Desktop    Documents  Downloads  Projects")
			push("design.fig notes.md   README.md  wallpaper.png")
		elseif name == "pwd" then
			push("/Users/roblox")
		elseif name == "whoami" then
			push("roblox")
		elseif name == "date" then
			push(os.date("%a %b %d %H:%M:%S %Y", os.time() + CONFIG.timeOffsetHours * 3600))
		elseif name == "clear" then
			lines = {}
			render()
		elseif name == "echo" then
			push(escapeRich(rest))
		elseif name == "open" then
			local app = string.match(rest, "^(%S+)")
			if app and builders[app] then
				openApp(app)
				push("正在打开 " .. app .. " …")
			else
				push('<font color="#ff7b72">open: 找不到应用 "' .. escapeRich(rest) .. '"</font>')
			end
		elseif name == "neofetch" then
			push('<font color="#7ee787">        .:\'</font>      <font color="#7aa2f7">roblox@macbook</font>')
			push('<font color="#7ee787">    __ :\'__</font>      ----------------')
			push('<font color="#7ee787"> .\'`  `-\'  ``.</font>   OS: macOS 15.1 Sequoia')
			push('<font color="#7ee787">:          .-\'</font>   Shell: rbxsh 1.0')
			push('<font color="#7ee787">:         :</font>      DE: Aqua (Roblox)')
			push('<font color="#7ee787"> :         `-;</font>   Resolution: 1280x720')
			push('<font color="#7ee787">  `.__.-.__.\'</font>    GPU: Roblox Renderer')
		elseif name == "about" then
			openApp("about")
		else
			push('<font color="#ff7b72">zsh: command not found: ' .. escapeRich(name) .. "</font>")
		end
	end

	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			run(input.Text)
			input.Text = ""
			input:CaptureFocus()
		end
	end)

	push('<font color="#9aa0a6">Last login: ' .. os.date("%a %b %d %H:%M:%S", os.time() + CONFIG.timeOffsetHours * 3600) .. " on ttys001</font>")
	push('<font color="#9aa0a6">macOS 15.1 · Roblox Edition — 输入 <font color="#7aa2f7">help</font> 查看命令</font>')
	push("")

	win.onClose = function()
		appWindows.terminal = nil
	end
	return win
end

builders.terminal = buildTerminal

---------------------------------------------------------------------------
-- 20 · 系统设置
---------------------------------------------------------------------------

local AccentSwatches = {
	Color3.fromRGB(10, 132, 255),
	Color3.fromRGB(191, 90, 242),
	Color3.fromRGB(255, 55, 95),
	Color3.fromRGB(255, 69, 58),
	Color3.fromRGB(255, 159, 10),
	Color3.fromRGB(255, 214, 10),
	Color3.fromRGB(48, 209, 88),
	Color3.fromRGB(142, 142, 147),
}

local function buildSettings()
	local win = createWindow({
		name = "Settings",
		title = "系统设置",
		appKey = "settings",
		scaleContent = true,
		size = Vector2.new(660, 470),
		center = Vector2.new(canvasSize.X / 2 - 20, canvasSize.Y / 2 - 10),
	})
	win.titleLabel.Text = ""

	local root = win.content
	local sidebarWidth = 186
	local pageKey = "appearance"
	local pageRefreshers = {}

	local sidebar = create("Frame", {
		Size = UDim2.new(0, sidebarWidth, 1, 0),
		BackgroundColor3 = Palette.sidebar,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	create("Frame", {
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = sidebar,
	})

	label({
		Text = "系统设置",
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(16, 16),
		TextSize = 14,
		Font = Font.bold,
		ZIndex = 8,
		Parent = sidebar,
	})

	local pane = create("Frame", {
		Size = UDim2.new(1, -sidebarWidth, 1, 0),
		Position = UDim2.fromOffset(sidebarWidth, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})

	local pages = {
		{ key = "appearance", name = "外观", glyph = "apps" },
		{ key = "dock", name = "桌面与程序坞", glyph = "desktop" },
		{ key = "access", name = "辅助功能", glyph = "airdrop" },
	}
	local pageRows = {}

	local function renderPage()
		clearChildren(pane)
		pageRefreshers = {}

		local title = label({
			Text = "外观",
			Size = UDim2.new(1, -48, 0, 30),
			Position = UDim2.fromOffset(24, 20),
			TextSize = 21,
			Font = Font.bold,
			ZIndex = 8,
			Parent = pane,
		})

		local paneWidth = 660 - sidebarWidth

		if pageKey == "appearance" then
			title.Text = "外观"

			UI.caption(pane, "壁纸", {
				position = UDim2.fromOffset(24, 66),
				zIndex = 8,
				order = 1,
			})

			local themeKeys = { "aurora", "midnight", "sunrise" }
			for index, key in ipairs(themeKeys) do
				local theme = WallpaperThemes[key]
				local swatch = create("TextButton", {
					Size = UDim2.fromOffset(120, 72),
					Position = UDim2.fromOffset(24 + (index - 1) * 130, 86),
					BackgroundColor3 = theme.base,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 8,
					Parent = pane,
				})
				round(swatch, 9)

				local bloom = create("Frame", {
					Size = UDim2.fromOffset(78, 78),
					Position = UDim2.fromOffset(74, -16),
					BackgroundColor3 = theme.glows[1].color,
					BackgroundTransparency = 0.25,
					BorderSizePixel = 0,
					ZIndex = 9,
					Parent = swatch,
				})
				round(bloom, 40)
				local bloom2 = create("Frame", {
					Size = UDim2.fromOffset(64, 64),
					Position = UDim2.fromOffset(-14, 34),
					BackgroundColor3 = theme.glows[2].color,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					ZIndex = 9,
					Parent = swatch,
				})
				round(bloom2, 32)

				local ring = stroke(swatch, Theme.accent, 2, 1)
				ring.Transparency = (currentTheme == key) and 0 or 1

				label({
					Text = theme.name,
					Size = UDim2.new(1, 0, 0, 16),
					Position = UDim2.fromOffset(0, 76),
					TextSize = 11,
					TextColor3 = Palette.textSecondary,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 9,
					Parent = swatch,
				})

				swatch.Activated:Connect(function()
					buildWallpaper(key, true)
					for _, refresh in ipairs(pageRefreshers) do
						refresh()
					end
					showToast("桌面与程序坞", "壁纸已切换为" .. theme.name, Color3.fromRGB(120, 90, 220))
				end)

				pageRefreshers[#pageRefreshers + 1] = function()
					ring.Transparency = (currentTheme == key) and 0 or 1
				end
			end

			UI.caption(pane, "强调色", {
				position = UDim2.fromOffset(24, 178),
				zIndex = 8,
			})

			for index, color in ipairs(AccentSwatches) do
				local dot = create("TextButton", {
					Size = UDim2.fromOffset(22, 22),
					Position = UDim2.fromOffset(24 + (index - 1) * 28, 200),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 8,
					Parent = pane,
				})
				round(dot, 11)
				local inner = create("Frame", {
					Size = UDim2.fromOffset(8, 8),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 9,
					Parent = dot,
				})
				round(inner, 4)

				local function refresh()
					inner.BackgroundTransparency = (Theme.accent == color) and 0 or 1
				end
				refresh()
				pageRefreshers[#pageRefreshers + 1] = refresh

				dot.Activated:Connect(function()
					setAccent(color)
					for _, item in ipairs(pageRefreshers) do
						item()
					end
				end)
			end

			label({
				Text = "强调色会应用到按钮、开关、滑块与选中态。",
				Size = UDim2.new(1, -48, 0, 16),
				Position = UDim2.fromOffset(24, 234),
				TextSize = 11,
				TextColor3 = Palette.textTertiary,
				ZIndex = 8,
				Parent = pane,
			})

			local preview = create("Frame", {
				Size = UDim2.new(1, -48, 0, 92),
				Position = UDim2.fromOffset(24, 264),
				BackgroundColor3 = Color3.fromRGB(246, 246, 248),
				BorderSizePixel = 0,
				ZIndex = 8,
				Parent = pane,
			})
			round(preview, 10)
			UI.button(preview, {
				text = "主按钮",
				size = UDim2.fromOffset(96, 30),
				position = UDim2.fromOffset(18, 16),
				zIndex = 9,
			})
			UI.button(preview, {
				text = "次按钮",
				primary = false,
				size = UDim2.fromOffset(96, 30),
				position = UDim2.fromOffset(124, 16),
				zIndex = 9,
			})
			local demo = UI.toggle(preview, {
				value = true,
				position = UDim2.fromOffset(18, 56),
			})
			demo.set(true, false, true)
			label({
				Text = "预览",
				Size = UDim2.new(0, 60, 0, 20),
				Position = UDim2.fromOffset(70, 57),
				TextSize = 11,
				TextColor3 = Palette.textTertiary,
				ZIndex = 9,
				Parent = preview,
			})
		elseif pageKey == "dock" then
			title.Text = "桌面与程序坞"

			UI.caption(pane, "程序坞", {
				position = UDim2.fromOffset(24, 66),
				zIndex = 8,
			})

			label({
				Text = "图标大小",
				Size = UDim2.new(0, 120, 0, 20),
				Position = UDim2.fromOffset(24, 100),
				TextSize = 12.5,
				ZIndex = 8,
				Parent = pane,
			})
			UI.slider(pane, {
				width = paneWidth - 150,
				position = UDim2.fromOffset(130, 96),
				value = Dock.base,
				min = 34,
				max = 58,
				onChange = function(value)
					setDockIconSize(math.floor(value + 0.5))
				end,
			})

			local function settingRow(y, titleText, subtitleText)
				label({
					Text = titleText,
					Size = UDim2.new(0, 220, 0, 18),
					Position = UDim2.fromOffset(24, y),
					TextSize = 12.5,
					ZIndex = 8,
					Parent = pane,
				})
				label({
					Text = subtitleText,
					Size = UDim2.new(0, 260, 0, 16),
					Position = UDim2.fromOffset(24, y + 17),
					TextSize = 10.5,
					TextColor3 = Palette.textTertiary,
					ZIndex = 8,
					Parent = pane,
				})
			end

			settingRow(146, "放大", "指针经过时图标放大")
			UI.toggle(pane, {
				value = Dock.magnify,
				position = UDim2.fromOffset(paneWidth - 70, 150),
				onChange = function(value)
					Dock.magnify = value
					updateMagnification()
				end,
			})

			settingRow(200, "自动隐藏", "指针离开后收起程序坞")
			UI.toggle(pane, {
				value = false,
				position = UDim2.fromOffset(paneWidth - 70, 204),
				onChange = function(value)
					if value then
						showToast("程序坞", "自动隐藏已开启（演示）", Color3.fromRGB(120, 120, 130))
					end
				end,
			})

			UI.caption(pane, "细节", {
				position = UDim2.fromOffset(24, 264),
				zIndex = 8,
			})
			label({
				Text = "图标放大采用临界阻尼弹簧（damping 0.74 / response 0.28），\n指针按下即触发弹跳，抬起不等待。",
				Size = UDim2.new(1, -48, 0, 40),
				Position = UDim2.fromOffset(24, 286),
				TextSize = 11,
				TextColor3 = Palette.textTertiary,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 8,
				Parent = pane,
			})
		else
			title.Text = "辅助功能"

			label({
				Text = "减弱动态效果",
				Size = UDim2.new(0, 260, 0, 18),
				Position = UDim2.fromOffset(24, 74),
				TextSize = 12.5,
				ZIndex = 8,
				Parent = pane,
			})
			label({
				Text = "用交叉淡化替代位移与弹簧，去掉回弹",
				Size = UDim2.new(0, 320, 0, 16),
				Position = UDim2.fromOffset(24, 92),
				TextSize = 10.5,
				TextColor3 = Palette.textTertiary,
				ZIndex = 8,
				Parent = pane,
			})
			UI.toggle(pane, {
				value = Theme.reduceMotion,
				position = UDim2.fromOffset(paneWidth - 70, 78),
				onChange = function(value)
					Theme.reduceMotion = value
					showToast("辅助功能", value and "已减弱动态效果" or "已恢复完整动效", Color3.fromRGB(90, 130, 240))
				end,
			})

			create("Frame", {
				Size = UDim2.new(1, -48, 0, 1),
				Position = UDim2.fromOffset(24, 124),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.92,
				BorderSizePixel = 0,
				ZIndex = 8,
				Parent = pane,
			})

			label({
				Text = "提高对比度",
				Size = UDim2.new(0, 260, 0, 18),
				Position = UDim2.fromOffset(24, 140),
				TextSize = 12.5,
				ZIndex = 8,
				Parent = pane,
			})
			label({
				Text = "为文字与控件增加对比度",
				Size = UDim2.new(0, 320, 0, 16),
				Position = UDim2.fromOffset(24, 158),
				TextSize = 10.5,
				TextColor3 = Palette.textTertiary,
				ZIndex = 8,
				Parent = pane,
			})
			UI.toggle(pane, {
				value = false,
				position = UDim2.fromOffset(paneWidth - 70, 144),
				onChange = function(value)
					showToast("辅助功能", value and "已提高对比度" or "已恢复默认对比度", Color3.fromRGB(120, 120, 130))
				end,
			})

			create("Frame", {
				Size = UDim2.new(1, -48, 0, 1),
				Position = UDim2.fromOffset(24, 190),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.92,
				BorderSizePixel = 0,
				ZIndex = 8,
				Parent = pane,
			})

			label({
				Text = "降低透明度",
				Size = UDim2.new(0, 260, 0, 18),
				Position = UDim2.fromOffset(24, 206),
				TextSize = 12.5,
				ZIndex = 8,
				Parent = pane,
			})
			label({
				Text = "把玻璃材质替换为接近实色的背景",
				Size = UDim2.new(0, 320, 0, 16),
				Position = UDim2.fromOffset(24, 224),
				TextSize = 10.5,
				TextColor3 = Palette.textTertiary,
				ZIndex = 8,
				Parent = pane,
			})
			UI.toggle(pane, {
				value = false,
				position = UDim2.fromOffset(paneWidth - 70, 210),
				onChange = function(value)
					tween(dock, { BackgroundTransparency = value and 0.94 or 0.72 }, TweenInfo.new(0.3))
					tween(menubar, { BackgroundTransparency = value and 0.95 or 0.45 }, TweenInfo.new(0.3))
				end,
			})

			label({
				Text = "动效遵循 Apple 的弹簧参数：默认 damping 1.0 / response 0.34，\n仅在手势本身带速度时允许轻微回弹。",
				Size = UDim2.new(1, -48, 0, 40),
				Position = UDim2.fromOffset(24, 286),
				TextSize = 11,
				TextColor3 = Palette.textTertiary,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 8,
				Parent = pane,
			})
		end
	end

	local order = 0
	for _, page in ipairs(pages) do
		order = order + 1
		local row = create("TextButton", {
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.fromOffset(8, 48 + (order - 1) * 32),
			BackgroundColor3 = Theme.accent,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 7,
			Parent = sidebar,
		})
		round(row, 6)
		local iconHolder = create("Frame", {
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(8, 7),
			BackgroundTransparency = 1,
			ZIndex = 8,
			Parent = row,
		})
		sidebarGlyph(iconHolder, page.glyph, 15, Color3.fromRGB(104, 112, 128))
		local rowLabel = label({
			Text = page.name,
			Size = UDim2.new(1, -36, 1, 0),
			Position = UDim2.fromOffset(30, 0),
			TextSize = 12.5,
			TextColor3 = Palette.text,
			ZIndex = 8,
			Parent = row,
		})

		local function refreshRow()
			local active = pageKey == page.key
			row.BackgroundTransparency = active and 0.86 or 1
			rowLabel.TextColor3 = active and Theme.accent or Palette.text
		end
		refreshRow()
		pageRows[#pageRows + 1] = refreshRow

		row.MouseEnter:Connect(function()
			if pageKey ~= page.key then
				tween(row, { BackgroundTransparency = 0.95 }, TweenInfo.new(0.08))
			end
		end)
		row.MouseLeave:Connect(function()
			if pageKey ~= page.key then
				tween(row, { BackgroundTransparency = 1 }, TweenInfo.new(0.12))
			end
		end)
		row.Activated:Connect(function()
			pageKey = page.key
			for _, refresh in ipairs(pageRows) do
				refresh()
			end
			renderPage()
		end)
	end

	renderPage()

	win.onClose = function()
		appWindows.settings = nil
	end
	return win
end

builders.settings = buildSettings

---------------------------------------------------------------------------
-- 21 · 关于本机
---------------------------------------------------------------------------

local function buildAbout()
	local win = createWindow({
		name = "About",
		title = "",
		appKey = "about",
		scaleContent = true,
		size = Vector2.new(360, 408),
		center = Vector2.new(canvasSize.X / 2, canvasSize.Y / 2),
	})
	win.titleLabel.Text = ""
	win.titlebar.BackgroundTransparency = 0.55

	local root = win.content
	root.BackgroundColor3 = Color3.fromRGB(252, 252, 254)

	local logoHolder = create("Frame", {
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.new(0.5, 0, 0, 26),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = root,
	})
	local logo = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = logoHolder,
	})
	drawApple(logo, 54)
	for _, obj in ipairs(logo:GetDescendants()) do
		if obj:IsA("Frame") and obj.BackgroundColor3 == Color3.fromRGB(255, 255, 255) then
			obj.BackgroundColor3 = Color3.fromRGB(60, 60, 66)
		end
	end

	label({
		Text = "MacBook Pro",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 94),
		TextSize = 21,
		Font = Font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
		Parent = root,
	})
	label({
		Text = "14 英寸，Roblox 版",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 120),
		TextSize = 11.5,
		TextColor3 = Palette.textTertiary,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
		Parent = root,
	})

	local specs = {
		{ "芯片", "Roblox M3 Pro" },
		{ "内存", "36 GB" },
		{ "启动磁盘", "Macintosh HD" },
		{ "序列号", "C02RBX2024" },
	}

	for index, spec in ipairs(specs) do
		local y = 154 + (index - 1) * 26
		label({
			Text = spec[1],
			Size = UDim2.fromOffset(96, 24),
			Position = UDim2.fromOffset(28, y),
			TextSize = 11.5,
			TextColor3 = Palette.textTertiary,
			ZIndex = 8,
			Parent = root,
		})
		label({
			Text = spec[2],
			Size = UDim2.new(1, -140, 0, 24),
			Position = UDim2.fromOffset(120, y),
			TextSize = 11.5,
			TextColor3 = Palette.text,
			ZIndex = 8,
			Parent = root,
		})
	end

	create("Frame", {
		Size = UDim2.new(1, -56, 0, 1),
		Position = UDim2.fromOffset(28, 268),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = root,
	})

	UI.button(root, {
		text = "系统报告…",
		size = UDim2.new(1, -56, 0, 30),
		position = UDim2.fromOffset(28, 286),
		onClick = function()
			showToast("系统报告", "已生成 MacBook Pro 报告", Color3.fromRGB(120, 130, 150))
		end,
	})

	label({
		Text = "macOS 15.1 · Roblox Edition\n界面设计参考 Apple HIG 与 emilkowalski/skills",
		Size = UDim2.new(1, -48, 0, 40),
		Position = UDim2.fromOffset(24, 330),
		TextSize = 10.5,
		TextColor3 = Palette.textTertiary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 8,
		Parent = root,
	})

	win.onClose = function()
		appWindows.about = nil
	end
	return win
end

builders.about = buildAbout

---------------------------------------------------------------------------
-- 22 · 音乐
---------------------------------------------------------------------------

local function buildMusic()
	local win = createWindow({
		name = "Music",
		title = "音乐",
		appKey = "music",
		scaleContent = true,
		size = Vector2.new(430, 336),
		center = Vector2.new(canvasSize.X / 2 + 60, canvasSize.Y / 2 + 40),
	})
	win.titleLabel.Text = ""

	local root = win.content

	local cover = create("Frame", {
		Size = UDim2.fromOffset(140, 140),
		Position = UDim2.fromOffset(24, 26),
		BackgroundColor3 = Color3.fromRGB(255, 120, 160),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = root,
	})
	round(cover, 12)
	local coverGradient = Instance.new("UIGradient")
	coverGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 176, 120)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 92, 140)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 70, 220)),
	})
	coverGradient.Rotation = 55
	coverGradient.Parent = cover

	for i = 1, 3 do
		local ring = create("Frame", {
			Size = UDim2.fromOffset(96 - i * 14, 96 - i * 14),
			Position = UDim2.fromScale(0.72, 0.74),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 8,
			Parent = cover,
		})
		round(ring, 60)
		stroke(ring, Color3.fromRGB(255, 255, 255), 1, 0.7)
	end

	label({
		Text = "Aurora",
		Size = UDim2.new(1, -196, 0, 26),
		Position = UDim2.fromOffset(184, 34),
		TextSize = 17,
		Font = Font.bold,
		ZIndex = 8,
		Parent = root,
	})
	label({
		Text = "Roblox Sound Lab · 2024",
		Size = UDim2.new(1, -196, 0, 18),
		Position = UDim2.fromOffset(184, 60),
		TextSize = 11.5,
		TextColor3 = Palette.textTertiary,
		ZIndex = 8,
		Parent = root,
	})

	local progress = UI.slider(root, {
		width = 196,
		position = UDim2.fromOffset(184, 92),
		value = 0.32,
		trackHeight = 4,
	})

	label({
		Text = "1:12",
		Size = UDim2.fromOffset(40, 14),
		Position = UDim2.fromOffset(184, 112),
		TextSize = 9.5,
		TextColor3 = Palette.textTertiary,
		ZIndex = 8,
		Parent = root,
	})
	label({
		Text = "-2:41",
		Size = UDim2.fromOffset(50, 14),
		Position = UDim2.fromOffset(330, 112),
		TextSize = 9.5,
		TextColor3 = Palette.textTertiary,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 8,
		Parent = root,
	})

	local playButton = create("TextButton", {
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.fromOffset(240, 136),
		BackgroundColor3 = Theme.accent,
		BorderSizePixel = 0,
		Text = ">",
		Font = Font.medium,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = root,
	})
	round(playButton, 19)
	local playing = true
	playButton.Activated:Connect(function()
		playing = not playing
		playButton.Text = playing and ">" or "II"
		showToast("音乐", playing and "正在播放 Aurora" or "已暂停", Color3.fromRGB(255, 90, 130))
	end)

	local prev = create("TextButton", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(196, 140),
		BackgroundTransparency = 1,
		Text = "<",
		Font = Font.medium,
		TextSize = 20,
		TextColor3 = Palette.textSecondary,
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = root,
	})
	local next = create("TextButton", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(292, 140),
		BackgroundTransparency = 1,
		Text = ">",
		Font = Font.medium,
		TextSize = 20,
		TextColor3 = Palette.textSecondary,
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = root,
	})

	prev.Activated:Connect(function()
		progress.set(0.05)
	end)
	next.Activated:Connect(function()
		progress.set(0.05)
		showToast("音乐", "已跳到下一首", Color3.fromRGB(255, 90, 130))
	end)

	create("Frame", {
		Size = UDim2.new(1, -48, 0, 1),
		Position = UDim2.fromOffset(24, 194),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = root,
	})

	local queue = {
		{ "Night Drive", "3:24" },
		{ "Glass Fields", "4:02" },
		{ "Paper Planes", "2:58" },
	}

	for index, track in ipairs(queue) do
		local y = 204 + (index - 1) * 26
		label({
			Text = tostring(index) .. "  " .. track[1],
			Size = UDim2.new(1, -140, 0, 24),
			Position = UDim2.fromOffset(26, y),
			TextSize = 11.5,
			TextColor3 = index == 1 and Palette.text or Palette.textSecondary,
			ZIndex = 8,
			Parent = root,
		})
		label({
			Text = track[2],
			Size = UDim2.fromOffset(40, 24),
			Position = UDim2.new(1, -70, 0, y),
			TextSize = 10.5,
			TextColor3 = Palette.textTertiary,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 8,
			Parent = root,
		})
	end

	win.onClose = function()
		appWindows.music = nil
	end
	return win
end

builders.music = buildMusic

---------------------------------------------------------------------------
-- 23 · Safari
---------------------------------------------------------------------------

local function buildSafari()
	local win = createWindow({
		name = "Safari",
		title = "Safari 浏览器",
		appKey = "safari",
		scaleContent = true,
		size = Vector2.new(740, 470),
		center = Vector2.new(canvasSize.X / 2, canvasSize.Y / 2 - 20),
	})
	win.titleLabel.Text = ""

	local root = win.content

	local toolbar = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Palette.toolbar,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = root,
	})
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = toolbar,
	})

	for i, glyph in ipairs({ "<", ">" }) do
		local btn = create("TextButton", {
			Size = UDim2.fromOffset(26, 28),
			Position = UDim2.fromOffset(12 + (i - 1) * 26, 9),
			BackgroundTransparency = 1,
			Text = glyph,
			Font = Font.medium,
			TextSize = 18,
			TextColor3 = i == 1 and Palette.textSecondary or Palette.textTertiary,
			AutoButtonColor = false,
			ZIndex = 8,
			Parent = toolbar,
		})
		btn.Name = "Nav" .. i
	end

	local address = create("Frame", {
		Size = UDim2.new(0, 300, 0, 26),
		Position = UDim2.new(0.5, -150, 0, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.93,
		ZIndex = 8,
		Parent = toolbar,
	})
	round(address, 7)
	local lock = create("Frame", {
		Size = UDim2.fromOffset(7, 5),
		Position = UDim2.fromOffset(11, 11),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = address,
	})
	round(lock, 2)
	stroke(lock, Palette.textTertiary, 1.2, 0.2)
	create("Frame", {
		Size = UDim2.fromOffset(1.2, 3),
		Position = UDim2.new(0, 3, 0, -3),
		BackgroundColor3 = Palette.textTertiary,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = lock,
	})
	local addressBox = create("TextBox", {
		Size = UDim2.new(1, -32, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Font.regular,
		TextSize = 11.5,
		TextColor3 = Palette.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		Text = "start.roblex.dev",
		ZIndex = 9,
		Parent = address,
	})
	addressBox.FocusLost:Connect(function()
		addressBox.Text = "start.roblex.dev"
	end)

	local page = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		BackgroundColor3 = Color3.fromRGB(248, 248, 250),
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.new(0, 0, 0),
		ScrollBarImageTransparency = 0.8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
		Parent = root,
	})

	label({
		Text = "收藏",
		Size = UDim2.new(1, -80, 0, 26),
		Position = UDim2.fromOffset(40, 26),
		TextSize = 18,
		Font = Font.bold,
		ZIndex = 7,
		Parent = page,
	})

	local favorites = {
		{ "Roblox", Color3.fromRGB(226, 60, 66) },
		{ "Design", Color3.fromRGB(90, 120, 240) },
		{ "Docs", Color3.fromRGB(70, 170, 120) },
		{ "Icons", Color3.fromRGB(250, 166, 60) },
		{ "Music", Color3.fromRGB(230, 90, 150) },
		{ "Notes", Color3.fromRGB(140, 120, 220) },
	}

	for index, item in ipairs(favorites) do
		local col = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local tile = create("TextButton", {
			Size = UDim2.fromOffset(150, 78),
			Position = UDim2.fromOffset(40 + col * 168, 64 + row * 92),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 7,
			Parent = page,
		})
		round(tile, 12)
		stroke(tile, Color3.new(0, 0, 0), 1, 0.94)

		local badge = create("Frame", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(12, 12),
			BackgroundColor3 = item[2],
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = tile,
		})
		round(badge, 8)
		label({
			Text = string.sub(item[1], 1, 1),
			Size = UDim2.fromScale(1, 1),
			TextSize = 14,
			Font = Font.bold,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 9,
			Parent = badge,
		})
		label({
			Text = item[1],
			Size = UDim2.new(1, -58, 0, 16),
			Position = UDim2.fromOffset(50, 14),
			TextSize = 12,
			ZIndex = 8,
			Parent = tile,
		})
		label({
			Text = "已收藏",
			Size = UDim2.new(1, -58, 0, 14),
			Position = UDim2.fromOffset(50, 31),
			TextSize = 10,
			TextColor3 = Palette.textTertiary,
			ZIndex = 8,
			Parent = tile,
		})

		tile.Activated:Connect(function()
			showToast("Safari", "Roblox 内无法访问外部网络", Color3.fromRGB(90, 120, 240))
		end)
	end

	local privacy = create("Frame", {
		Size = UDim2.new(1, -80, 0, 110),
		Position = UDim2.fromOffset(40, 264),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = page,
	})
	round(privacy, 12)
	stroke(privacy, Color3.new(0, 0, 0), 1, 0.94)

	label({
		Text = "隐私报告",
		Size = UDim2.new(1, -32, 0, 22),
		Position = UDim2.fromOffset(16, 14),
		TextSize = 13,
		Font = Font.medium,
		ZIndex = 8,
		Parent = privacy,
	})
	label({
		Text = "过去 7 天，Safari 阻止了 128 个跟踪器。",
		Size = UDim2.new(1, -32, 0, 18),
		Position = UDim2.fromOffset(16, 38),
		TextSize = 11,
		TextColor3 = Palette.textSecondary,
		ZIndex = 8,
		Parent = privacy,
	})
	local bars = create("Frame", {
		Size = UDim2.new(1, -32, 0, 34),
		Position = UDim2.fromOffset(16, 62),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = privacy,
	})
	for i = 1, 7 do
		local height = 8 + (i * 7) % 22
		local bar = create("Frame", {
			Size = UDim2.fromOffset(18, height),
			Position = UDim2.new(0, (i - 1) * 26, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.accent,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 9,
			Parent = bars,
		})
		round(bar, 3)
	end

	win.onClose = function()
		appWindows.safari = nil
	end
	return win
end

builders.safari = buildSafari

---------------------------------------------------------------------------
-- 24 · 启动
---------------------------------------------------------------------------

local splash = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(6, 8, 16),
	BorderSizePixel = 0,
	ZIndex = 1200,
	Parent = canvas,
})

local menuBarHome = UDim2.new(0, 0, 0, 0)
local dockHome = UDim2.new(0.5, 0, 1, -8)

if not Theme.reduceMotion then
	menubar.Position = UDim2.new(0, 0, 0, -26)
	dockWrap.Position = UDim2.new(0.5, 0, 1, 84)
end

task.delay(0.1, function()
	tween(splash, { BackgroundTransparency = 1 }, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	task.delay(0.75, function()
		splash:Destroy()
	end)

	if not Theme.reduceMotion then
		tween(menubar, { Position = menuBarHome }, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		tween(dockWrap, { Position = dockHome }, TweenInfo.new(0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	end
end)

task.delay(1.15, function()
	openApp("finder")
end)

task.delay(1.6, function()
	showToast("访达", "提示：右键桌面可更换壁纸", Color3.fromRGB(90, 120, 240))
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Escape then
		closeDropdown()
		closeControlCenter()
		closeContextMenu()
		if _G.__MacCloseOverlays then
			_G.__MacCloseOverlays()
		end
	end
end)

game:GetService("GuiService").MenuOpened:Connect(function()
	dismissAll()
	if _G.__MacCloseOverlays then
		_G.__MacCloseOverlays()
	end
end)

print("[MacDesktopUI] macOS 风格桌面已加载 — 设计参考 emilkowalski/skills · apple-design")
-- Roblox（Lua 5.1）每个函数最多 200 个局部变量。主 chunk 已经很满，
-- 本模块只通过 _G 钩子对外，所以整体放进一个初始化函数，拥有独立的局部名额
local function setupOverlays()
---------------------------------------------------------------------------
-- 25 · 叠加层：启动台 / 聚焦搜索 / 通知中心 / 程序坞应用菜单
---------------------------------------------------------------------------
-- 这些面板共享同一套材质与动效约定：
--   · 半透明深色玻璃 + 顶部亮边，不用实色边框
--   · 入场用临界阻尼弹簧（damping 1.0），不做夸张回弹
--   · 触屏上点击任何空白区域即可关闭，不依赖 hover / 右键
---------------------------------------------------------------------------

local function overlayRoot(name, zIndex)
	local root = create("CanvasGroup", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = zIndex,
		Parent = overlayLayer,
	})
	local catcher = create("TextButton", {
		Name = "Catcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = zIndex,
		Parent = root,
	})
	return root, catcher
end

local function fadeIn(root, duration)
	root.GroupTransparency = 1
	tween(root, { GroupTransparency = 0 }, TweenInfo.new(duration or 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

local function fadeOutAndDestroy(root, duration)
	tween(root, { GroupTransparency = 1 }, TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	task.delay((duration or 0.16) + 0.03, function()
		if root.Parent then
			root:Destroy()
		end
	end)
end

-- 关于本机的图标（其余图标复用程序坞绘制器）
local extraPainters = {}
extraPainters.info = function(parent, size)
	gradientFill(parent, Color3.fromRGB(168, 176, 190), Color3.fromRGB(96, 104, 122), 140)
	local ring = create("Frame", {
		Size = UDim2.fromOffset(size * 0.44, size * 0.44),
		Position = UDim2.fromScale(0.5, 0.46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 287,
		Parent = parent,
	})
	round(ring, size * 0.22)
	stroke(ring, Color3.fromRGB(255, 255, 255), 1.4, 0.15)
	create("Frame", {
		Size = UDim2.fromOffset(math.max(1.6, size * 0.035), size * 0.16),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 288,
		Parent = parent,
	})
	create("Frame", {
		Size = UDim2.fromOffset(math.max(1.6, size * 0.035), size * 0.18),
		Position = UDim2.fromScale(0.5, 0.62),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 288,
		Parent = parent,
	})
end

-- 图标绘制器把 ZIndex 写死在 280–300 区间，搬到叠加层里要整体抬高，
-- 否则会被菜单栏（300）与窗口（100+）压住
local function paintAppIcon(parent, paint, size, zBase)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = zBase,
		Parent = parent,
	})
	round(holder, size * 0.22)
	local painter = iconPainters[paint] or extraPainters[paint]
	if painter then
		painter(holder, size)
		for _, obj in ipairs(holder:GetDescendants()) do
			local raw = obj.ZIndex or zBase
			obj.ZIndex = zBase + math.max(raw - 280, 0)
		end
	end
	return holder
end

-- 通知数据（通知中心可逐条清除，改动会立刻反映到面板）
local Notifications = {
	{ title = "访达", body = "下载完成：macOS 图标包.zip · 24.6 MB", time = "刚刚", tint = Color3.fromRGB(90, 140, 220) },
	{ title = "音乐", body = "正在播放 Aurora — Roblox Sound Lab", time = "2 分钟前", tint = Color3.fromRGB(236, 78, 120) },
	{ title = "系统设置", body = "软件更新已就绪，重启后生效", time = "昨天", tint = Color3.fromRGB(140, 140, 150) },
}

-- 应用目录（启动台 / 聚焦搜索共用，顺序固定，避免 pairs 乱序）
local AppCatalog = {
	{ key = "finder", name = "访达", paint = "finder" },
	{ key = "safari", name = "Safari 浏览器", paint = "safari" },
	{ key = "notes", name = "备忘录", paint = "notes" },
	{ key = "terminal", name = "终端", paint = "terminal" },
	{ key = "music", name = "音乐", paint = "music" },
	{ key = "settings", name = "系统设置", paint = "settings" },
	{ key = "about", name = "关于本机", paint = "info" },
}

---------------------------------------------------------------------------
-- 25.1 · 启动台
---------------------------------------------------------------------------

local launchpadRoot = nil
local launchpadSearch = nil
local launchpadGrid = nil
local launchpadQuery = ""
local launchpadPanel = nil
local launchpadTitle = nil

local function launchMetrics()
	local cellW = Theme.touch and 96 or 104
	local gap = Theme.touch and 8 or 10
	local usable = math.max(canvasSize.X - (Theme.compact and 28 or 96), cellW)
	local columns = math.max(1, math.floor((usable + gap) / (cellW + gap)))
	return columns, cellW, gap
end

local launchSignature = ""

local function renderLaunchpad()
	if not launchpadGrid then
		return
	end
	local columns, cellW, gap = launchMetrics()
	local query = string.lower(launchpadQuery)
	local rowHeight = Theme.touch and 116 or 124

	launchSignature = columns .. "|" .. query
	clearChildren(launchpadGrid)

	local row = nil
	local col = 0
	local rowIndex = 0
	local shown = 0

	local function newRow()
		rowIndex = rowIndex + 1
		row = create("Frame", {
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundTransparency = 1,
			LayoutOrder = rowIndex,
			ZIndex = 452,
			Parent = launchpadGrid,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = row,
		})
		col = 0
	end

	for _, app in ipairs(AppCatalog) do
		local name = string.lower(app.name)
		if query == "" or string.find(name, query, 1, true) then
			if col == 0 then
				newRow()
			end
			col = col + 1
			shown = shown + 1

			local cell = create("TextButton", {
				Size = UDim2.fromOffset(cellW, rowHeight - 6),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = col,
				ZIndex = 452,
				Parent = row,
			})
			round(cell, 14)

			local iconSize = Theme.touch and 62 or 56
			local iconHolder = create("Frame", {
				Size = UDim2.fromOffset(iconSize, iconSize),
				Position = UDim2.new(0.5, 0, 0, 6),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				ZIndex = 452,
				Parent = cell,
			})
			paintAppIcon(iconHolder, app.paint, iconSize, 452)

			label({
				Text = app.name,
				Size = UDim2.new(1, -4, 0, 34),
				Position = UDim2.fromOffset(2, iconSize + 12),
				TextSize = Theme.touch and 12.5 or 12,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 453,
				Parent = cell,
			})

			local pressScale = Instance.new("UIScale")
			pressScale.Parent = cell
			pressScale.Scale = 1
			cell.InputBegan:Connect(function(input)
				if isPress(input) then
					tween(pressScale, { Scale = 0.94 }, EASE_PRESS)
				end
			end)
			cell.InputEnded:Connect(function()
				tween(pressScale, { Scale = 1 }, TweenInfo.new(0.2, Enum.EasingStyle.Quad))
			end)
			cell.MouseEnter:Connect(function()
				tween(cell, { BackgroundTransparency = 0.9 }, TweenInfo.new(0.12))
			end)
			cell.MouseLeave:Connect(function()
				tween(cell, { BackgroundTransparency = 1 }, TweenInfo.new(0.16))
			end)
			cell.Activated:Connect(function()
				closeLaunchpad()
				openApp(app.key)
			end)

			if col >= columns then
				col = 0
			end
		end
	end

	if shown == 0 then
		label({
			Text = "没有匹配的应用",
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 13,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 452,
			Parent = launchpadGrid,
		})
	end
end

local function layoutLaunchpad()
	if not launchpadRoot then
		return
	end
	local w = canvasSize.X
	local compact = Theme.compact
	launchpadTitle.Position = UDim2.fromOffset(compact and 24 or 48, compact and 18 or 40)
	launchpadTitle.TextSize = compact and 17 or 20
	launchpadSearch.Size = UDim2.fromOffset(math.min(compact and w - 48 or 380, w - 32), compact and 30 or 34)
	launchpadSearch.Position = UDim2.fromOffset(w / 2, compact and 52 or 84)
	if launchpadGrid.Parent then
		launchpadGrid.Position = UDim2.fromOffset(compact and 14 or 48, compact and 92 or 138)
		launchpadGrid.Size = UDim2.new(1, -(compact and 28 or 96), 1, -(compact and 110 or 158))
	end
	local columns = launchMetrics()
	if launchSignature ~= (columns .. "|" .. string.lower(launchpadQuery)) then
		renderLaunchpad()
	end
end

function closeLaunchpad()
	if not launchpadRoot then
		return
	end
	local root = launchpadRoot
	launchpadRoot = nil
	launchpadSearch = nil
	launchpadGrid = nil
	launchpadPanel = nil
	launchpadTitle = nil
	if Theme.reduceMotion then
		root:Destroy()
		return
	end
	local panel = root:FindFirstChild("Panel")
	if panel then
		local scale = panel:FindFirstChildOfClass("UIScale")
		if scale then
			tween(scale, { Scale = 0.95 }, TweenInfo.new(0.14, Enum.EasingStyle.Quad))
		end
	end
	fadeOutAndDestroy(root, 0.16)
end

function openLaunchpad()
	if launchpadRoot then
		closeLaunchpad()
		return
	end
	closeAllOverlays()

	local root, catcher = overlayRoot("Launchpad", 420)
	launchpadRoot = root
	catcher.Activated:Connect(function()
		closeLaunchpad()
	end)

	launchpadPanel = create("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 421,
		Parent = root,
	})
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = launchpadPanel
	panelScale.Scale = Theme.reduceMotion and 1 or 0.96
	if not Theme.reduceMotion then
		tween(panelScale, { Scale = 1 }, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end

	launchpadTitle = label({
		Text = "启动台",
		Size = UDim2.new(0, 200, 0, 28),
		TextSize = 20,
		Font = Font.bold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 423,
		Parent = launchpadPanel,
	})

	launchpadSearch = create("TextBox", {
		Name = "Search",
		Size = UDim2.fromOffset(380, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		Text = "",
		PlaceholderText = "搜索应用",
		PlaceholderColor3 = Color3.fromRGB(255, 255, 255),
		Font = Font.regular,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		ClearTextOnFocus = false,
		ZIndex = 423,
		Parent = launchpadPanel,
	})
	round(launchpadSearch, 10)
	padding(launchpadSearch, 8)
	launchpadSearch.Focused:Connect(function()
		tween(launchpadSearch, { BackgroundTransparency = 0.78 }, TweenInfo.new(0.14))
	end)
	launchpadSearch.FocusLost:Connect(function()
		tween(launchpadSearch, { BackgroundTransparency = 0.88 }, TweenInfo.new(0.14))
	end)
	launchpadSearch:GetPropertyChangedSignal("Text"):Connect(function()
		launchpadQuery = launchpadSearch.Text
		renderLaunchpad()
	end)

	launchpadGrid = create("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, -96, 1, -158),
		Position = UDim2.fromOffset(48, 138),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 452,
		Parent = launchpadPanel,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = launchpadGrid,
	})

	launchpadQuery = ""
	renderLaunchpad()
	layoutLaunchpad()

	-- 打开时不自动聚焦：触屏弹出键盘会挡住一半图标，需要搜索再点输入框
	if not Theme.touch then
		launchpadSearch:CaptureFocus()
	end

	fadeIn(root, 0.2)
end

_G.__MacToggleLaunchpad = function()
	if launchpadRoot then
		closeLaunchpad()
	else
		openLaunchpad()
	end
end

---------------------------------------------------------------------------
-- 25.2 · 通知中心（点菜单栏时钟）
---------------------------------------------------------------------------

local widgetsRoot = nil
local widgetsPanel = nil
local widgetRows = {}

local function miniCalendar(parent, width)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(width, 96),
		BackgroundTransparency = 1,
		ZIndex = 472,
		Parent = parent,
	})
	local stamp = os.time() + CONFIG.timeOffsetHours * 3600
	local today = tonumber(os.date("%d", stamp))
	local monthStart = os.time({ year = tonumber(os.date("%Y", stamp)), month = tonumber(os.date("%m", stamp)), day = 1, hour = 12 })
	local firstWeekday = tonumber(os.date("%w", monthStart))
	local daysInMonth = tonumber(os.date("%d", os.time({ year = tonumber(os.date("%Y", stamp)), month = tonumber(os.date("%m", stamp)) + 1, day = 0, hour = 12 })))

	local labels = { "日", "一", "二", "三", "四", "五", "六" }
	local colWidth = width / 7
	for i = 1, 7 do
		label({
			Text = labels[i],
			Size = UDim2.fromOffset(colWidth, 14),
			Position = UDim2.fromOffset((i - 1) * colWidth, 0),
			TextSize = 9.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.55,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 473,
			Parent = holder,
		})
	end
	for day = 1, daysInMonth do
		local slot = firstWeekday + day - 1
		local col = slot % 7
		local row = math.floor(slot / 7)
		local cell = create("Frame", {
			Size = UDim2.fromOffset(colWidth, 18),
			Position = UDim2.fromOffset(col * colWidth, 18 + row * 18),
			BackgroundTransparency = 1,
			ZIndex = 473,
			Parent = holder,
		})
		if day == today then
			local pill = create("Frame", {
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Theme.accent,
				BorderSizePixel = 0,
				ZIndex = 474,
				Parent = cell,
			})
			round(pill, 9)
		end
		label({
			Text = tostring(day),
			Size = UDim2.fromScale(1, 1),
			TextSize = 9.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = (day == today) and 0 or 0.28,
			Font = (day == today) and Font.bold or Font.regular,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 475,
			Parent = cell,
		})
	end
	return holder
end

local function widgetCard(parent, height, order)
	local card = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Color3.fromRGB(58, 58, 64),
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 470,
		Parent = parent,
	})
	round(card, 14)
	stroke(card, Color3.fromRGB(255, 255, 255), 1, 0.86)
	return card
end

local function renderNotifications(list)
	for _, row in ipairs(widgetRows) do
		if row.Parent then
			row:Destroy()
		end
	end
	widgetRows = {}

	for index, item in ipairs(Notifications) do
		local card = widgetCard(list, 62, index)
		widgetRows[#widgetRows + 1] = card

		local badge = create("Frame", {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(14, 16),
			BackgroundColor3 = item.tint,
			BorderSizePixel = 0,
			ZIndex = 471,
			Parent = card,
		})
		round(badge, 7)

		label({
			Text = item.title,
			Size = UDim2.new(1, -96, 0, 16),
			Position = UDim2.fromOffset(52, 12),
			TextSize = 12,
			Font = Font.medium,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 471,
			Parent = card,
		})
		label({
			Text = item.body,
			Size = UDim2.new(1, -66, 0, 30),
			Position = UDim2.fromOffset(52, 28),
			TextSize = 10.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.35,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 471,
			Parent = card,
		})
		label({
			Text = item.time,
			Size = UDim2.new(0, 54, 0, 14),
			Position = UDim2.new(1, -62, 0, 12),
			TextSize = 9.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.55,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 471,
			Parent = card,
		})

		local close = create("TextButton", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(1, -26, 0, 30),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.9,
			Text = "x",
			Font = Font.bold,
			TextSize = 10,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			AutoButtonColor = false,
			ZIndex = 472,
			Parent = card,
		})
		round(close, 10)
		close.Activated:Connect(function()
			for i = #Notifications, 1, -1 do
				if Notifications[i] == item then
					table.remove(Notifications, i)
				end
			end
			if widgetsPanel then
				renderNotifications(widgetsPanel:FindFirstChild("List"))
			end
		end)
	end
end

local function layoutWidgets()
	if not widgetsPanel or not widgetsRoot then
		return
	end
	local width = math.min(Theme.touch and 320 or 330, canvasSize.X - 16)
	widgetsPanel.Size = UDim2.fromOffset(width, math.min(canvasSize.Y - chromeTop() - 12, Theme.touch and 470 or 440))
	widgetsPanel.Position = UDim2.fromOffset(canvasSize.X - width - 10, chromeTop() + 6)
end

function closeWidgets()
	if not widgetsRoot then
		return
	end
	local root = widgetsRoot
	widgetsRoot = nil
	widgetsPanel = nil
	desktopIcons.Visible = true
	if Theme.reduceMotion then
		root:Destroy()
		return
	end
	if widgetsPanel then
		widgetsPanel = nil
	end
	fadeOutAndDestroy(root, 0.14)
end

function openWidgets()
	if widgetsRoot then
		closeWidgets()
		return
	end
	closeAllOverlays()

	local root, catcher = overlayRoot("Widgets", 430)
	widgetsRoot = root
	-- 通知中心遮住桌面图标，避免图标透过玻璃卡片显形
	desktopIcons.Visible = false
	catcher.Activated:Connect(function()
		closeWidgets()
	end)

	widgetsPanel = create("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(330, 440),
		BackgroundTransparency = 1,
		ZIndex = 431,
		Parent = root,
	})
	local list = create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 431,
		Parent = widgetsPanel,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	padding(list, 2)

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		ZIndex = 432,
		Parent = list,
	})
	label({
		Text = "通知中心",
		Size = UDim2.new(0, 140, 1, 0),
		TextSize = 12.5,
		Font = Font.medium,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.2,
		ZIndex = 433,
		Parent = header,
	})
	local clearAll = create("TextButton", {
		Size = UDim2.fromOffset(46, 20),
		Position = UDim2.new(1, -46, 0, 2),
		BackgroundTransparency = 1,
		Text = "清除",
		Font = Font.regular,
		TextSize = 11,
		TextColor3 = Theme.accent,
		AutoButtonColor = false,
		ZIndex = 433,
		Parent = header,
	})
	clearAll.Activated:Connect(function()
		for i = #Notifications, 1, -1 do
			table.remove(Notifications, i)
		end
		renderNotifications(list)
	end)

	-- 日期卡
	local dateCard = widgetCard(list, 150, 1)
	local stamp = os.time() + CONFIG.timeOffsetHours * 3600
	local t = os.date("*t", stamp)
	local weekday = ({ "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" })[t.wday]
	label({
		Text = string.format("%d", t.day),
		Size = UDim2.fromOffset(96, 58),
		Position = UDim2.fromOffset(16, 10),
		TextSize = 44,
		Font = Font.bold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 471,
		Parent = dateCard,
	})
	label({
		Text = string.format("%d月 · %s", t.month, weekday),
		Size = UDim2.new(1, -110, 0, 18),
		Position = UDim2.fromOffset(16, 66),
		TextSize = 11.5,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.4,
		ZIndex = 471,
		Parent = dateCard,
	})
	miniCalendar(dateCard, 176).Position = UDim2.fromOffset(120, 22)
	dateCard.Size = UDim2.new(1, 0, 0, 150)

	-- 天气卡
	local weather = widgetCard(list, 84, 2)
	label({
		Text = "上海",
		Size = UDim2.new(0, 120, 0, 16),
		Position = UDim2.fromOffset(14, 12),
		TextSize = 11,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.35,
		ZIndex = 471,
		Parent = weather,
	})
	label({
		Text = "24°",
		Size = UDim2.fromOffset(96, 40),
		Position = UDim2.fromOffset(14, 28),
		TextSize = 32,
		Font = Font.bold,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 471,
		Parent = weather,
	})
	label({
		Text = "多云 · 最高 27° 最低 19°",
		Size = UDim2.new(1, -110, 0, 16),
		Position = UDim2.fromOffset(14, 66),
		TextSize = 10,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.4,
		ZIndex = 471,
		Parent = weather,
	})
	for i = 1, 3 do
		local hour = (t.hour + i * 2) % 24
		local col = create("Frame", {
			Size = UDim2.fromOffset(46, 62),
			Position = UDim2.new(1, -58 - (3 - i) * 50, 0, 12),
			BackgroundTransparency = 1,
			ZIndex = 471,
			Parent = weather,
		})
		label({
			Text = string.format("%02d 时", hour),
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = 9.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 472,
			Parent = col,
		})
		local dot = create("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0.5, 0, 0, 20),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(255, 214, 120),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 472,
			Parent = col,
		})
		round(dot, 7)
		label({
			Text = string.format("%d°", 22 + (i % 3)),
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(0, 40),
			TextSize = 10.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 472,
			Parent = col,
		})
	end

	renderNotifications(list)
	layoutWidgets()

	if not Theme.reduceMotion then
		local width = widgetsPanel.Size.X.Offset
		widgetsPanel.Position = UDim2.fromOffset(canvasSize.X + 4, chromeTop() + 6)
		local spring = newSpring({ x = canvasSize.X + 4 }, function(values)
			if widgetsPanel then
				widgetsPanel.Position = UDim2.fromOffset(values.x, chromeTop() + 6)
			end
		end, SpringSpec.popover)
		spring:to({ x = canvasSize.X - width - 10 })
	end

	fadeIn(root, 0.2)
end

_G.__MacToggleWidgets = function()
	if widgetsRoot then
		closeWidgets()
	else
		openWidgets()
	end
end

---------------------------------------------------------------------------
-- 25.3 · 聚焦搜索
---------------------------------------------------------------------------

local spotlightRoot = nil
local spotlightPanel = nil
local spotlightField = nil
local spotlightList = nil
local spotlightResults = {}
local spotlightIndex = 1
local spotlightOpen = false

local function collectResults(query)
	local out = {}
	local q = string.lower(query)

	local function add(entry)
		if q == "" or string.find(string.lower(entry.title), q, 1, true) or string.find(string.lower(entry.sub or ""), q, 1, true) then
			out[#out + 1] = entry
		end
	end

	if q == "" then
		for _, app in ipairs(AppCatalog) do
			out[#out + 1] = {
				title = app.name,
				sub = "应用程序",
				paint = app.paint,
				tint = Color3.fromRGB(90, 110, 220),
				run = function()
					openApp(app.key)
				end,
			}
		end
		out[#out + 1] = { title = "切换壁纸", sub = "命令", tint = Color3.fromRGB(120, 90, 220), run = function()
			local keys = { "aurora", "midnight", "sunrise" }
			local index = table.find(keys, currentTheme) or 1
			local nextKey = keys[(index % #keys) + 1]
			buildWallpaper(nextKey, true)
			showToast("桌面与程序坞", "已切换壁纸：" .. WallpaperThemes[nextKey].name, Color3.fromRGB(120, 90, 220))
		end }
		return out
	end

	for _, app in ipairs(AppCatalog) do
		add({
			title = app.name,
			sub = "应用程序",
			paint = app.paint,
			tint = Color3.fromRGB(90, 110, 220),
			run = function()
				openApp(app.key)
			end,
		})
	end

	local seen = {}
	for _, files in pairs(FinderData) do
		for _, file in ipairs(files) do
			if not seen[file.name] then
				seen[file.name] = true
				add({
					title = file.name,
					sub = "访达 · " .. (file.type == "folder" and "文件夹" or "文件"),
					tint = Color3.fromRGB(104, 166, 245),
					run = function()
						openApp("finder")
					end,
				})
			end
		end
	end

	for _, note in ipairs(NotesData) do
		add({
			title = note.title,
			sub = "备忘录",
			tint = Color3.fromRGB(240, 190, 60),
			run = function()
				openApp("notes")
			end,
		})
	end

	for _, action in ipairs({
		{ title = "切换壁纸", sub = "命令" },
		{ title = "打开系统设置", sub = "命令" },
		{ title = "关于本机", sub = "命令" },
	}) do
		local entry = { title = action.title, sub = action.sub, tint = Color3.fromRGB(120, 90, 220) }
		if action.title == "切换壁纸" then
			entry.run = function()
				local keys = { "aurora", "midnight", "sunrise" }
				local index = table.find(keys, currentTheme) or 1
				local nextKey = keys[(index % #keys) + 1]
				buildWallpaper(nextKey, true)
			end
		elseif action.title == "打开系统设置" then
			entry.run = function()
				openApp("settings")
			end
		else
			entry.run = function()
				openApp("about")
			end
		end
		add(entry)
	end

	return out
end

local function renderSpotlight()
	if not spotlightList then
		return
	end
	clearChildren(spotlightList)
	for index, entry in ipairs(spotlightResults) do
		local row = create("TextButton", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = index == spotlightIndex and 0.9 or 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = index,
			ZIndex = 446,
			Parent = spotlightList,
		})
		round(row, 7)

		local badge = create("Frame", {
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.fromOffset(8, 9),
			BackgroundColor3 = entry.tint,
			BorderSizePixel = 0,
			ZIndex = 447,
			Parent = row,
		})
		round(badge, 6)
		if entry.paint then
			local tiny = paintAppIcon(badge, entry.paint, 24, 447)
			round(tiny, 24 * 0.22)
		end

		label({
			Text = entry.title,
			Size = UDim2.new(1, -120, 1, 0),
			Position = UDim2.fromOffset(40, 0),
			TextSize = 12.5,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 447,
			Parent = row,
		})
		label({
			Text = entry.sub or "",
			Size = UDim2.fromOffset(120, 1),
			Position = UDim2.new(1, -128, 0, 0),
			TextSize = 10,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.55,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 447,
			Parent = row,
		})

		row.MouseEnter:Connect(function()
			if spotlightIndex ~= index then
				row.BackgroundTransparency = 0.94
			end
		end)
		row.MouseLeave:Connect(function()
			if spotlightIndex ~= index then
				row.BackgroundTransparency = 1
			end
		end)
		row.Activated:Connect(function()
			closeSpotlight()
			if entry.run then
				entry.run()
			end
		end)
	end
	if #spotlightResults == 0 then
		label({
			Text = "没有结果",
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 446,
			Parent = spotlightList,
		})
	end
end

local function refreshSpotlight()
	spotlightResults = collectResults(spotlightField and spotlightField.Text or "")
	spotlightIndex = math.min(spotlightIndex, math.max(#spotlightResults, 1))
	if spotlightList then
		spotlightList.Size = UDim2.new(1, 0, 0, math.min(#spotlightResults, 6) * 42 + 6)
	end
	renderSpotlight()
end

local function layoutSpotlight()
	if not spotlightRoot then
		return
	end
	local width = math.min(560, canvasSize.X - 24)
	local listHeight = spotlightList and spotlightList.Size.Y.Offset or 0
	spotlightPanel.Size = UDim2.fromOffset(width, 56 + listHeight + 8)
	spotlightPanel.Position = UDim2.fromOffset((canvasSize.X - width) / 2, chromeTop() + (Theme.compact and 14 or 48))
end

function closeSpotlight()
	if not spotlightRoot then
		return
	end
	local root = spotlightRoot
	if spotlightField then
		spotlightField:ReleaseFocus()
	end
	spotlightRoot = nil
	spotlightPanel = nil
	spotlightField = nil
	spotlightList = nil
	spotlightOpen = false
	if Theme.reduceMotion then
		root:Destroy()
		return
	end
	fadeOutAndDestroy(root, 0.12)
end

function openSpotlight()
	if spotlightRoot then
		closeSpotlight()
		return
	end
	closeAllOverlays()

	spotlightOpen = true
	local root, catcher = overlayRoot("Spotlight", 440)
	spotlightRoot = root
	catcher.Activated:Connect(function()
		closeSpotlight()
	end)

	spotlightPanel = create("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(560, 56),
		BackgroundColor3 = Color3.fromRGB(36, 36, 42),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 441,
		Parent = root,
	})
	round(spotlightPanel, 14)
	stroke(spotlightPanel, Color3.fromRGB(255, 255, 255), 1, 0.82)

	local lens = create("Frame", {
		Size = UDim2.fromOffset(13, 13),
		Position = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		ZIndex = 443,
		Parent = spotlightPanel,
	})
	round(lens, 7)
	stroke(lens, Color3.fromRGB(255, 255, 255), 1.6, 0.35)
	create("Frame", {
		Size = UDim2.fromOffset(6, 1.6),
		Position = UDim2.new(1, 1, 1, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Rotation = 45,
		ZIndex = 443,
		Parent = lens,
	})

	spotlightField = create("TextBox", {
		Size = UDim2.new(1, -90, 0, 38),
		Position = UDim2.fromOffset(42, 9),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "聚焦搜索",
		PlaceholderColor3 = Color3.fromRGB(255, 255, 255),
		Font = Font.regular,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ZIndex = 443,
		Parent = spotlightPanel,
	})
	local hintBg = create("Frame", {
		Size = UDim2.fromOffset(34, 18),
		Position = UDim2.new(1, -46, 0, 19),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 442,
		Parent = spotlightPanel,
	})
	round(hintBg, 5)
	label({
		Text = "Esc",
		Size = UDim2.fromScale(1, 1),
		TextSize = 9.5,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 0.45,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 443,
		Parent = hintBg,
	})

	spotlightList = create("ScrollingFrame", {
		Name = "Results",
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.fromOffset(0, 52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 444,
		Parent = spotlightPanel,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = spotlightList,
	})
	padding(spotlightList, 4)

	spotlightField:GetPropertyChangedSignal("Text"):Connect(function()
		spotlightIndex = 1
		refreshSpotlight()
		layoutSpotlight()
	end)
	spotlightField.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local entry = spotlightResults[spotlightIndex]
			closeSpotlight()
			if entry and entry.run then
				entry.run()
			end
		end
	end)

	spotlightIndex = 1
	refreshSpotlight()
	layoutSpotlight()
	spotlightField:CaptureFocus()
	fadeIn(root, 0.16)
end

_G.__MacToggleSpotlight = function()
	if spotlightRoot then
		closeSpotlight()
	else
		openSpotlight()
	end
end

-- 上下键选择：TextBox 聚焦时按键会被标记为已处理，这里仍然接管
UserInputService.InputBegan:Connect(function(input)
	if not spotlightOpen then
		return
	end
	if input.KeyCode == Enum.KeyCode.Down then
		spotlightIndex = math.min(spotlightIndex + 1, math.max(#spotlightResults, 1))
		renderSpotlight()
	elseif input.KeyCode == Enum.KeyCode.Up then
		spotlightIndex = math.max(spotlightIndex - 1, 1)
		renderSpotlight()
	elseif input.KeyCode == Enum.KeyCode.Return then
		local entry = spotlightResults[spotlightIndex]
		closeSpotlight()
		if entry and entry.run then
			entry.run()
		end
	end
end)

---------------------------------------------------------------------------
-- 25.4 · 程序坞应用菜单（右键 / 长按）
---------------------------------------------------------------------------

local appMenuRoot = nil

local function closeAppMenu()
	if not appMenuRoot then
		return
	end
	local root = appMenuRoot
	appMenuRoot = nil
	if Theme.reduceMotion then
		root:Destroy()
		return
	end
	fadeOutAndDestroy(root, 0.12)
end

_G.__MacAppMenu = function(key, name, anchor)
	closeAppMenu()
	closeDropdown()
	closeControlCenter()

	local root, catcher = overlayRoot("AppMenu", 450)
	appMenuRoot = root
	catcher.Activated:Connect(function()
		closeAppMenu()
	end)

	local items = {
		{ text = "打开", run = function()
			openApp(key)
		end },
		{ text = "显示所有窗口", run = function()
			if _G.__MacCycleWindow then
				_G.__MacCycleWindow()
			end
		end },
		{ text = "-" },
		{ text = "退出", run = function()
			for index = #windows, 1, -1 do
				local win = windows[index]
				if win.appKey == key and not win.closed then
					win.close()
				end
			end
			showToast(name, "已退出", Color3.fromRGB(140, 140, 150))
		end },
	}

	local width = Theme.touch and 190 or 172
	local rowHeight = Theme.touch and 34 or 28
	local height = 10
	for _, item in ipairs(items) do
		height = height + (item.text == "-" and 9 or rowHeight)
	end

	local x = clamp(anchor.X - width / 2, 8, canvasSize.X - width - 8)
	local y = clamp(anchor.Y - height - 12, chromeTop() + 4, canvasSize.Y - height - 8)

	local panel = glassPanel(root, {
		color = Color3.fromRGB(40, 40, 44),
		transparency = 0.1,
		size = UDim2.fromOffset(width, height),
		position = UDim2.fromOffset(x, y),
		radius = 11,
		zIndex = 451,
	})
	local list = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 452,
		Parent = panel,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	padding(list, 5)

	for index, item in ipairs(items) do
		if item.text == "-" then
			local holder = create("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = index,
				ZIndex = 453,
				Parent = list,
			})
			create("Frame", {
				Size = UDim2.new(1, -16, 0, 1),
				Position = UDim2.new(0, 8, 0.5, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				ZIndex = 454,
				Parent = holder,
			})
		else
			local row = create("TextButton", {
				Size = UDim2.new(1, 0, 0, rowHeight),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index,
				ZIndex = 453,
				Parent = list,
			})
			round(row, 5)
			label({
				Text = item.text,
				Size = UDim2.new(1, -20, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				TextSize = Theme.touch and 13.5 or 13,
				TextColor3 = Color3.fromRGB(245, 245, 248),
				ZIndex = 454,
				Parent = row,
			})
			row.MouseEnter:Connect(function()
				row.BackgroundTransparency = 0.88
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
			end)
			row.Activated:Connect(function()
				closeAppMenu()
				item.run()
			end)
		end
	end

	fadeIn(root, 0.12)
end

---------------------------------------------------------------------------
-- 25.5 · 键盘与手势总入口
---------------------------------------------------------------------------

-- 这些叠加层不被旧的 closeOverlays 认识，统一在这里收口
function closeAllOverlays()
	closeLaunchpad()
	closeSpotlight()
	closeWidgets()
	closeAppMenu()
end

_G.__MacCloseOverlays = closeAllOverlays
_G.__MacDismissOverlays = closeAllOverlays

local ctrlDown = false

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		ctrlDown = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		ctrlDown = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Escape then
		closeAllOverlays()
		return
	end
	if processed then
		return
	end
	local focused = nil
	if UserInputService.GetFocusedTextBox then
		focused = UserInputService:GetFocusedTextBox()
	end

	if ctrlDown and input.KeyCode == Enum.KeyCode.Space then
		_G.__MacToggleSpotlight()
		return
	end

	if ctrlDown and focused == nil then
		if input.KeyCode == Enum.KeyCode.W then
			if _G.__MacCloseFocused then
				_G.__MacCloseFocused()
			end
		elseif input.KeyCode == Enum.KeyCode.M then
			if _G.__MacMinimizeFocused then
				_G.__MacMinimizeFocused()
			end
		elseif input.KeyCode == Enum.KeyCode.Tab then
			if _G.__MacCycleWindow then
				_G.__MacCycleWindow()
			end
		elseif input.KeyCode == Enum.KeyCode.L then
			_G.__MacToggleLaunchpad()
		end
	end
end)

onLayout(function()
	layoutLaunchpad()
	layoutSpotlight()
	layoutWidgets()
end)
end

setupOverlays()
