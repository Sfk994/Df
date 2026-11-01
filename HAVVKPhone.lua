--[[
	==============================================================
	  HAVVK Phone · 调试面板 v2.7（iPhone 锁屏风格）
	==============================================================
	  用法：
	    1. StarterGui 里新建一个 LocalScript
	    2. 把本文件全部内容粘贴进去
	    3. 运行游戏

	  交互：
	    · 锁屏：从底部小白条向上滑动解锁（鼠标拖 / 手指上滑），点提示文字也行
	    · 上滑提示压在底部小白条上方 24px，不贴边
	    · 灵动岛：86 → 90（只加宽 5%），小锁靠左留白并播放开锁动画，收起后彻底隐藏
	    · 顶部状态栏：左边时间，右边信号 / 5G / 电池
	    · 锁屏日期：几月几日 星期几 · 农历干支年月日
	    · 主屏：四个应用 FLY / TP / CAR 加载远程脚本，PLR = 玩家列表
	    · 底部 Dock（图标版）：锁 = 回到锁屏，滑块 = 设置页，文稿 = 日志页
	    · 顶部状态栏区域按住可拖动整个面板
	    · 圆角换了画法：投影层 + 机身外框（外扩 5px）+ 内屏，三层叠出中框与圆角，
      内容再怎么换壁纸 / 切页面也顶不出边框
	    · 右上角小圆点 × 关闭，右下角按钮或 F2 重新唤出
	    · 底部上滑返回桌面：解锁后底部有小白色条，从那儿往上拖，页面跟手上升并淡出，
      松手超过 52px 就回主屏，不够则弹回原处
    · 玩家列表：头像 / 昵称 / 账号时间 / 与你的距离，右侧 TP 一键传送到对方身边
    · 面板按屏幕高度自动等比缩放，PC / 手机都适用

	  功能分布：
	    · 标题栏滚动字幕 → 锁屏通知卡片里的循环字幕
	    · 主功能三个 APP 图标 → 主屏图标（左上对齐，拉宽不居中）
	    · 运行状态（FPS / PING / 日志条数）、重载、日志 → 全部收进设置页
	    · 设置页另有「换壁纸」（8 套：渐变 + 光带 + 柔光 + 暗角，平滑过渡）与「关于本机」
	    · 关于本机：账号 / 设备 / 运行 / 面板 四组明细，滚动查看
	    · 日志阅读页从右侧滑入，未读数在 Dock 与设置行上提示
	    · 自动刷新时间 / 日期 → 锁屏大时钟

	  性能（v2.6 优化）：
	    · 字幕改用单个循环 Tween，不再每帧写 Position（原来 60 次/秒的属性复制）
	    · 帧数统计从 RenderStepped 挪到 Heartbeat，面板隐藏时直接返回
	    · FPS / PING / 时间只在对应界面可见时才写文本，值没变不重复赋值
	    · 日志页关闭时只存数据不建控件，打开时一次性重建（刷屏不再卡）
	    · 状态刷新合并为 0.12s 一次

	  对外接口（与原 DebugUI 兼容）：
	    _G.HAVVKPhone:Log("消息", "info")   -- info / success / warn / error
	    _G.HAVVKPhone:OpenLog()
	    _G.HAVVKPhone:SetVisible(false)
	    _G.HAVVKPhone.OnReload = function() end
	    _G.DebugUI -- 指向同一个对象
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=============================================================
-- 配置 / 配色
--=============================================================
local CONFIG = {
	Width = 300,
	Height = 640,
	Corner = 33,      -- 内屏圆角
	Bezel = 5,        -- 机身外框厚度（画在内屏四周，不侵占内屏布局）
	BezelCorner = 38, -- 机身圆角 = 内屏圆角 + 外框厚度
	UnlockThreshold = 62,   -- 上滑超过这个距离就解锁
	MaxLogLines = 150,
	MarqueeSpeed = 34,      -- 通知卡字幕速度（像素 / 秒）
	Title = "HAVVK科技",
}

local COLORS = {
	Screen  = Color3.fromRGB(14, 15, 24),
	Page    = Color3.fromRGB(17, 18, 27),
	White   = Color3.fromRGB(255, 255, 255),
	Text    = Color3.fromRGB(240, 243, 250),
	SubText = Color3.fromRGB(150, 158, 176),
	Accent  = Color3.fromRGB(110, 148, 255),
	Green   = Color3.fromRGB(78, 201, 132),
	Yellow  = Color3.fromRGB(240, 190, 90),
	Red     = Color3.fromRGB(240, 96, 96),
}

local LEVEL_COLORS = {
	info    = Color3.fromRGB(200, 208, 222),
	success = COLORS.Green,
	warn    = COLORS.Yellow,
	error   = COLORS.Red,
}

-- 帧数 / 延迟的配色阈值（设置页与关于页共用）
local function fpsColor(v)
	if v >= 50 then
		return COLORS.Green
	elseif v >= 30 then
		return COLORS.Yellow
	end
	return COLORS.Red
end

local function pingColor(v)
	if v < 80 then
		return COLORS.Green
	elseif v < 160 then
		return COLORS.Yellow
	end
	return COLORS.Red
end


--=============================================================
-- 工具
--=============================================================
local function new(class, props)
	local inst = Instance.new(class)
	local parent = nil
	if props then
		parent = props.Parent
		for k, v in pairs(props) do
			if k ~= "Parent" then
				inst[k] = v
			end
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

local function stroke(parent, color, transparency, thickness)
	return new("UIStroke", {
		Color = color or COLORS.White,
		Transparency = transparency == nil and 1 or transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- 带阴影的文字（先画一层偏移的暗色副本）
local function textWithShadow(parent, props, shadowAlpha, offsetY)
	local shadowProps = {}
	for k, v in pairs(props) do
		shadowProps[k] = v
	end
	shadowProps.TextColor3 = Color3.fromRGB(0, 0, 0)
	shadowProps.TextTransparency = shadowAlpha or 0.55
	shadowProps.Position = UDim2.new(
		props.Position.X.Scale,
		props.Position.X.Offset,
		props.Position.Y.Scale,
		props.Position.Y.Offset + (offsetY or 2)
	)
	shadowProps.ZIndex = (props.ZIndex or 1) - 1
	shadowProps.Parent = parent
	local shadow = new("TextLabel", shadowProps)
	return new("TextLabel", props), shadow
end

--=============================================================
-- 窗口骨架：投影 → 机身外框 → 内屏（圆角由这三层叠出来）
--   · 投影：比机身大一圈的柔和黑块，让面板从 3D 画面上「浮」起来
--   · 机身：外扩 Bezel 像素的深色圆角块，四角永远比内屏更圆
--   · 内屏：整块内容，圆角比机身小一圈，正好嵌在外框里
--=============================================================
local gui = new("ScreenGui", {
	Name = "HAVVKPhone",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local root = new("Frame", {
	Name = "Phone",
	Visible = true,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height),
	ClipsDescendants = false,
	Parent = gui,
})

local uiScale = new("UIScale", { Scale = 1, Parent = root })

-- 投影 + 机身：用完即释放，不占顶层局部变量
do
	local shadow = new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, CONFIG.Bezel * 4, 1, CONFIG.Bezel * 4),
		Position = UDim2.fromOffset(-CONFIG.Bezel * 2, -CONFIG.Bezel * 2 + 4),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = root,
	})
	corner(shadow, CONFIG.BezelCorner + 8)

	-- 机身：外扩一圈，视觉上就是手机的中框
	local bezel = new("Frame", {
		Name = "Bezel",
		Size = UDim2.new(1, CONFIG.Bezel * 2, 1, CONFIG.Bezel * 2),
		Position = UDim2.fromOffset(-CONFIG.Bezel, -CONFIG.Bezel),
		BackgroundColor3 = Color3.fromRGB(8, 9, 14),
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = root,
	})
	corner(bezel, CONFIG.BezelCorner)
end

local screen = new("Frame", {
	Name = "Screen",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, -- 底色交给壁纸层（自带圆角，见下）
	BorderSizePixel = 0,
	ClipsDescendants = true,    -- 只做矩形裁剪：锁屏上滑不会溢出面板
	ZIndex = 1,
	Parent = root,
})
corner(screen, CONFIG.Corner)

-- 前向声明：锁屏 / 主屏 / Dock 的闭包会互相引用这些函数
local unlock, lock, gesture, hintButton
local unlocked, unlocking
local log, wallpaperRow, aboutWallpaperValue
local currentFps, currentPing, updateAboutLive
local API = {}

--=============================================================
-- 壁纸：渐变底 + 三道光带 + 两团柔光 + 暗角
--   每一层都铺满整屏并各自带圆角，不依赖父级裁切，
--   所以四角永远是圆的，切换时的过渡也不会溢出面板
--=============================================================
-- 下面这块整体塞进 do ... end：里面的临时量用完即释放，
-- 避免顶层的局部变量撞到 200 个上限
local WALLPAPERS
local wallpaperIndex = 1
local setWallpaper

do
	local function rgb(r, g, b)
		return Color3.fromRGB(r, g, b)
	end

	WALLPAPERS = {
		{
			name = "极夜紫",
			rotation = 168,
			stops = { rgb(24, 22, 58), rgb(54, 36, 88), rgb(110, 46, 94), rgb(52, 26, 62) },
			bands = { rgb(120, 96, 255), rgb(255, 96, 150), rgb(64, 120, 220) },
			blooms = { rgb(148, 120, 255), rgb(255, 112, 168) },
		},
		{
			name = "深海",
			rotation = 156,
			stops = { rgb(8, 22, 50), rgb(16, 54, 92), rgb(24, 112, 142), rgb(10, 40, 66) },
			bands = { rgb(42, 138, 255), rgb(40, 214, 198), rgb(18, 84, 190) },
			blooms = { rgb(64, 190, 255), rgb(40, 224, 210) },
		},
		{
			name = "暮光",
			rotation = 190,
			stops = { rgb(44, 20, 40), rgb(112, 46, 48), rgb(196, 100, 56), rgb(70, 28, 44) },
			bands = { rgb(255, 146, 64), rgb(255, 92, 110), rgb(176, 72, 200) },
			blooms = { rgb(255, 176, 96), rgb(255, 110, 120) },
		},
		{
			name = "石墨",
			rotation = 174,
			stops = { rgb(22, 22, 27), rgb(48, 50, 60), rgb(92, 95, 110), rgb(30, 30, 38) },
			bands = { rgb(140, 152, 176), rgb(104, 112, 134), rgb(168, 176, 196) },
			blooms = { rgb(160, 172, 196), rgb(120, 128, 148) },
		},
		{
			name = "极光",
			rotation = 162,
			stops = { rgb(6, 26, 34), rgb(10, 62, 74), rgb(26, 130, 118), rgb(8, 36, 52) },
			bands = { rgb(64, 255, 190), rgb(96, 200, 255), rgb(150, 120, 255) },
			blooms = { rgb(80, 255, 200), rgb(110, 170, 255) },
		},
		{
			name = "樱花",
			rotation = 198,
			stops = { rgb(58, 28, 48), rgb(120, 60, 88), rgb(214, 122, 148), rgb(86, 40, 62) },
			bands = { rgb(255, 168, 200), rgb(255, 210, 220), rgb(190, 120, 255) },
			blooms = { rgb(255, 190, 214), rgb(230, 150, 210) },
		},
		{
			name = "午夜蓝",
			rotation = 158,
			stops = { rgb(8, 14, 40), rgb(18, 30, 78), rgb(38, 62, 140), rgb(10, 18, 48) },
			bands = { rgb(72, 108, 255), rgb(96, 152, 255), rgb(140, 92, 255) },
			blooms = { rgb(96, 140, 255), rgb(120, 100, 240) },
		},
		{
			name = "琥珀",
			rotation = 178,
			stops = { rgb(34, 22, 14), rgb(78, 46, 22), rgb(160, 96, 36), rgb(48, 28, 16) },
			bands = { rgb(255, 176, 72), rgb(230, 120, 60), rgb(255, 208, 120) },
			blooms = { rgb(255, 196, 110), rgb(220, 130, 60) },
		},
	}

	-- 光带：整屏圆角矩形 + 透明度渐变，斜着铺一层柔光，永远越不过四角
	local BAND_LAYOUT = {
		{ rotation = 18, alpha = 0.30, peak = 0.34 },
		{ rotation = -34, alpha = 0.26, peak = 0.66 },
		{ rotation = 74, alpha = 0.20, peak = 0.50 },
	}

	-- 柔光：圆心离四角都留足距离，避免光晕糊到圆角外面
	local BLOOM_LAYOUT = {
		{ x = 150, y = 170, r = 120, alpha = 0.55 },
		{ x = 90, y = 470, r = 105, alpha = 0.45 },
	}
	local BLOOM_LEVELS = 18 -- 同心圆层数：够多才看不到台阶

	local wallpaper = new("Frame", {
		Name = "Wallpaper",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WALLPAPERS[1].stops[1],
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = screen,
	})
	corner(wallpaper, CONFIG.Corner)
	wallpaper.ClipsDescendants = true -- 柔光圆再怎么大，也不会顶穿圆角

	local wallpaperGradient = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WALLPAPERS[1].stops[1]),
			ColorSequenceKeypoint.new(0.45, WALLPAPERS[1].stops[2]),
			ColorSequenceKeypoint.new(0.78, WALLPAPERS[1].stops[3]),
			ColorSequenceKeypoint.new(1, WALLPAPERS[1].stops[4]),
		}),
		Rotation = WALLPAPERS[1].rotation,
		Parent = wallpaper,
	})

	local bandFrames = {}
	for i, spec in ipairs(BAND_LAYOUT) do
		local band = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WALLPAPERS[1].bands[i],
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = wallpaper,
		})
		corner(band, CONFIG.Corner)
		new("UIGradient", {
			Rotation = spec.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(math.clamp(spec.peak - 0.26, 0.02, 0.9), 1),
				NumberSequenceKeypoint.new(spec.peak, 1 - spec.alpha),
				NumberSequenceKeypoint.new(math.clamp(spec.peak + 0.26, 0.1, 0.98), 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = band,
		})
		bandFrames[i] = band
	end

	-- 用多层同心圆叠出柔和光晕（Roblox 没有径向渐变）
	local bloomGroups = {}
	for i, spec in ipairs(BLOOM_LAYOUT) do
		local rings = {}
		for level = BLOOM_LEVELS, 1, -1 do
			local r = spec.r * (level / BLOOM_LEVELS)
			-- 外圈稀薄、内圈渐浓，叠起来就是柔光而不是同心圆
			local t = (level - 1) / (BLOOM_LEVELS - 1)
			local alpha = spec.alpha * ((1 - t) ^ 2.2) / BLOOM_LEVELS * 2.6
			local ring = new("Frame", {
				Size = UDim2.fromOffset(r * 2, r * 2),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(spec.x, spec.y),
				BackgroundColor3 = WALLPAPERS[1].blooms[i],
				BackgroundTransparency = 1 - alpha,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = wallpaper,
			})
			corner(ring, r)
			rings[level] = ring
		end
		bloomGroups[i] = rings
	end

	-- 上下压暗，画面更有纵深
	local vignette = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = wallpaper,
	})
	corner(vignette, CONFIG.Corner)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.24, 1),
			NumberSequenceKeypoint.new(0.7, 1),
			NumberSequenceKeypoint.new(1, 0.58),
		}),
		Parent = vignette,
	})

	local liveRotation = WALLPAPERS[1].rotation
	local liveStops = {
		WALLPAPERS[1].stops[1], WALLPAPERS[1].stops[2],
		WALLPAPERS[1].stops[3], WALLPAPERS[1].stops[4],
	}
	local wallpaperConn = nil

	-- 切换壁纸：渐变逐帧插值（含角度）+ 光带 / 柔光补间，0.42s 平滑过渡
	setWallpaper = function(index)
		index = ((index - 1) % #WALLPAPERS) + 1
		local preset = WALLPAPERS[index]
		local target = preset.stops

		if wallpaperConn then
			wallpaperConn:Disconnect()
			wallpaperConn = nil
		end

		local from = { liveStops[1], liveStops[2], liveStops[3], liveStops[4] }
		local fromRotation = liveRotation
		local startClock = os.clock()

		wallpaperConn = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - startClock) / 0.42, 0, 1)
			local e = 1 - (1 - k) * (1 - k)
			for i = 1, 4 do
				liveStops[i] = from[i]:Lerp(target[i], e)
			end
			wallpaperGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, liveStops[1]),
				ColorSequenceKeypoint.new(0.45, liveStops[2]),
				ColorSequenceKeypoint.new(0.78, liveStops[3]),
				ColorSequenceKeypoint.new(1, liveStops[4]),
			})
			wallpaperGradient.Rotation = fromRotation + (preset.rotation - fromRotation) * e
			wallpaper.BackgroundColor3 = liveStops[1]
			if k >= 1 then
				wallpaperConn:Disconnect()
				wallpaperConn = nil
			end
		end)

		for i, band in ipairs(bandFrames) do
			TweenService:Create(band, TweenInfo.new(0.42, Enum.EasingStyle.Quad), {
				BackgroundColor3 = preset.bands[i],
			}):Play()
		end

		for i, rings in ipairs(bloomGroups) do
			local color = preset.blooms[i]
			for _, ring in ipairs(rings) do
				TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Quad), {
					BackgroundColor3 = color,
				}):Play()
			end
		end

		wallpaperIndex = index
		liveRotation = preset.rotation
		if wallpaperRow then
			wallpaperRow.desc.Text = "当前壁纸：" .. preset.name
		end
		if aboutWallpaperValue then
			aboutWallpaperValue.Text = preset.name
		end
		log("壁纸已切换：" .. preset.name .. "（" .. index .. "/" .. #WALLPAPERS .. "）", "info")
	end

end

--=============================================================
-- 状态栏 + 灵动岛
--=============================================================
local statusBar = new("Frame", {
	Name = "StatusBar",
	Size = UDim2.new(1, -36, 0, 20),
	Position = UDim2.fromOffset(18, 13),
	BackgroundTransparency = 1,
	ZIndex = 34,
	Parent = screen,
})

-- 状态栏：左边时间，右边信号 / 5G / 电池
local statusTime = new("TextLabel", {
	Name = "StatusTime",
	Size = UDim2.fromOffset(56, 14),
	Position = UDim2.fromOffset(0, 3),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "00:00",
	TextSize = 12,
	TextColor3 = COLORS.White,
	TextTransparency = 0.08,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = statusBar,
})

-- 信号格：四格，底部对齐、逐格递增，间距收紧，越像真机
local SIGNAL_LEVEL = 4 -- 1~4 格，可自行改
local signalWrap = new("Frame", {
	Size = UDim2.fromOffset(20, 11),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -62, 0, 4.5),
	BackgroundTransparency = 1,
	Parent = statusBar,
})

for i = 1, 4 do
	local bar = new("Frame", {
		Size = UDim2.fromOffset(3, 4 + (i - 1) * 2.05),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset((i - 1) * 5.4, 11),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = i <= SIGNAL_LEVEL and 0.12 or 0.72,
		BorderSizePixel = 0,
		Parent = signalWrap,
	})
	corner(bar, 1)
end

new("TextLabel", {
	Size = UDim2.fromOffset(26, 12),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -33, 0, 4),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "5G",
	TextSize = 9,
	TextColor3 = COLORS.White,
	TextTransparency = 0.16,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = statusBar,
})

-- 电池：Roblox 没有读取设备真实电量的接口，这里内置一个可配置的模拟值；
-- 外壳描边 + 内部填充块，填充宽度随电量缩放。要接入真实数据时，
-- 调用 _G.HAVVKPhone:SetBattery(0~1)（比如从你自己的 HTTP / 遥测服务喂进来）。
local BATTERY_LEVEL = 0.82 -- 0~1，模拟电量（1 = 满）

local battery = new("Frame", {
	Size = UDim2.fromOffset(25, 12),
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	BackgroundTransparency = 1,
	Parent = statusBar,
})
corner(battery, 3.6)

-- 描边画在外壳上，内部再放一块随电量缩放的填充
stroke(battery, COLORS.White, 0.05, 1)

local batteryFill = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromOffset(1, 1),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.14,
	BorderSizePixel = 0,
	Parent = battery,
})
corner(batteryFill, 2.6)

local function setBattery(level)
	level = math.clamp(level or BATTERY_LEVEL, 0.05, 1)
	-- 左右各留 1px 内边距：宽 = level * 25 - 2，高 = 12 - 2
	batteryFill.Size = UDim2.new(level, -2, 1, -2)
end
setBattery(BATTERY_LEVEL)

local batteryCap = new("Frame", {
	Size = UDim2.fromOffset(1.8, 4.6),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(1, 1.4, 0.5, 0),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = battery,
})
corner(batteryCap, 0.9)

-- 灵动岛
local island = new("Frame", {
	Name = "Island",
	Size = UDim2.fromOffset(86, 25),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 9),
	BackgroundColor3 = Color3.fromRGB(6, 6, 10),
	BorderSizePixel = 0,
	ZIndex = 36,
	Parent = screen,
})
corner(island, 13)

-- 岛内内容：一把小锁（动画期间才显示，平时 Visible=false 彻底隐藏）
local islandContent = new("CanvasGroup", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 37,
	Parent = island,
})

local islandLock = new("Frame", {
	Size = UDim2.fromOffset(16, 18),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	Parent = islandContent,
})

local lockShackle = new("Frame", {
	Size = UDim2.fromOffset(8.4, 8.4),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, 9.2),
	BackgroundTransparency = 1,
	Parent = islandLock,
})
corner(lockShackle, 4.2)
stroke(lockShackle, COLORS.White, 0.06, 1.7)

local lockBody = new("Frame", {
	Size = UDim2.fromOffset(13, 8.8),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 9.2),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Parent = islandLock,
})
corner(lockBody, 2.6)

local ISLAND_BASE_POS = UDim2.new(0.5, 0, 0, 9)
local ISLAND_W = 86
local ISLAND_W_WIDE = 90 -- 只加宽 5%（86 → 90），高度不变
local ISLAND_H = 25
local ISLAND_BASE = UDim2.fromOffset(ISLAND_W, ISLAND_H)
local ISLAND_WIDE = UDim2.fromOffset(ISLAND_W_WIDE, ISLAND_H)

-- 展开后锁靠左：左侧留 10px 呼吸位，右侧整段留白
local ISLAND_LOCK_PAD = 10
local LOCK_POS_CLOSED = UDim2.fromScale(0.5, 0.5)
local LOCK_POS_OPEN = UDim2.fromOffset(ISLAND_LOCK_PAD + 8, 12.5)

local SHACKLE_CLOSED = UDim2.new(0.5, 0, 0, 9.2)
local SHACKLE_OPEN = UDim2.new(0.5, 2.8, 0, 6.2)

local function resetIslandLock()
	lockShackle.Position = SHACKLE_CLOSED
	lockShackle.Rotation = 0
	islandLock.Position = LOCK_POS_CLOSED
end

local function islandTween(inst, info, goal)
	return TweenService:Create(inst, info, goal)
end

-- 每次收尾都做一次硬复位：即使动画被打断，岛也一定回到原始尺寸
local function islandHardReset()
	island.Size = ISLAND_BASE
	island.Position = ISLAND_BASE_POS
	islandContent.Visible = false
	islandContent.GroupTransparency = 1
	resetIslandLock()
end

-- 灵动岛：加宽 + 锁滑到左边 → 淡入 → 锁梁弹开 → 整体收回
-- 序号令牌：连点（解锁 / 上锁交替）时旧时间线直接作废，不会两套动画互相拉扯
local islandSeq = 0

local function islandPulse(mode)
	islandSeq = islandSeq + 1
	local seq = islandSeq
	local function alive()
		return seq == islandSeq
	end

	-- 从一个确定的起点开始，避免上一轮残留
	resetIslandLock()
	island.Size = ISLAND_BASE
	islandContent.Visible = true
	islandContent.GroupTransparency = 1

	local open = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	islandTween(island, open, { Size = ISLAND_WIDE }):Play()
	islandTween(islandLock, open, { Position = LOCK_POS_OPEN }):Play()
	islandTween(islandContent, TweenInfo.new(0.15), { GroupTransparency = 0 }):Play()

	-- 锁梁向上弹开（上锁时保持闭合，只做一次呼吸）
	if mode ~= "lock" then
		task.delay(0.22, function()
			if not alive() then
				return
			end
			islandTween(lockShackle, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = SHACKLE_OPEN,
				Rotation = -26,
			}):Play()
		end)
	end

	task.delay(0.64, function()
		if not alive() then
			return
		end
		islandTween(islandContent, TweenInfo.new(0.14), { GroupTransparency = 1 }):Play()
	end)

	task.delay(0.82, function()
		if not alive() then
			return
		end
		-- 先让锁彻底消失，再收回岛身，避免缩回时夹着半个小锁
		islandContent.Visible = false
		resetIslandLock()
		local back = TweenInfo.new(0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		islandTween(island, back, { Size = ISLAND_BASE }):Play()

		task.delay(0.5, function()
			if alive() then
				islandHardReset()
			end
		end)
	end)
end

--=============================================================
-- 锁屏层
--=============================================================
local lockGroup = new("CanvasGroup", {
	Name = "Lock",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 0,
	ZIndex = 20,
	Parent = screen,
})

local WEEKDAYS = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }

--=============================================================
-- 农历（1950 ~ 2070，数据由权威历表逐日核对生成）
--   每年一个数：低 4 位 = 闰月月份（0 表示无闰月）
--   第 4~15 位 = 正月至十二月的大小月（1 = 30 天）
--   第 16 位     = 闰月是否 30 天
--=============================================================
-- 整块塞进 do ... end，只留一个 lunarText 出去，省下十几个顶层局部变量
local lunarText

do
	local LUNAR_BASE_YEAR = 1950
	local LUNAR_INFO = {
		0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8,
		0x0e950, 0x06aa0, 0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260,
		0x0f263, 0x0d950, 0x05b57, 0x056a0, 0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0,
		0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, 0x095b0, 0x049b0,
		0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
		0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60,
		0x096d5, 0x092e0, 0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0,
		0x0abb7, 0x025d0, 0x092d0, 0x0cab5, 0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50,
		0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, 0x07954, 0x06aa0,
		0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
		0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250,
		0x0d520, 0x0dd45, 0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0,
		0x0aa50, 0x1b255, 0x06d20, 0x0ada0, 0x14b63, 0x09370, 0x049f8, 0x04970,
		0x064b0, 0x168a6, 0x0ea50, 0x06aa0, 0x1a6c4, 0x0aae0, 0x092e0, 0x0d2e3,
		0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
		0x052d0,
	}

	local LUNAR_MONTH_CN = { "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二" }
	local LUNAR_DAY_CN = {
		"初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
		"十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
		"廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
	}
	local GAN = { "甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸" }
	local ZHI = { "子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥" }

	-- 取某一位是否为 1（避免依赖位运算，Luau 里用整除更稳）
	local function bitOn(v, bit)
		return math.floor(v / bit) % 2 == 1
	end

	local function lunarInfoOf(y)
		return LUNAR_INFO[y - LUNAR_BASE_YEAR + 1]
	end

	local function lunarLeapMonth(y)
		local v = lunarInfoOf(y)
		return v and (v % 16) or 0
	end

	local function lunarMonthDays(y, m)
		local v = lunarInfoOf(y)
		if not v then
			return 29
		end
		return bitOn(v, 0x10000 / (2 ^ m)) and 30 or 29
	end

	local function lunarLeapDays(y)
		if lunarLeapMonth(y) == 0 then
			return 0
		end
		return bitOn(lunarInfoOf(y), 0x10000) and 30 or 29
	end

	local function lunarYearDays(y)
		local total = 0
		for m = 1, 12 do
			total = total + lunarMonthDays(y, m)
		end
		return total + lunarLeapDays(y)
	end

	-- 公历 → 序号（1970-01-01 为 0），纯整数运算，不受 os.time 时区影响
	local function dayNumber(y, m, d)
		local yy = y
		if m <= 2 then
			yy = yy - 1
		end
		local era = math.floor(yy / 400)
		local yoe = yy - era * 400
		local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
		local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
		return era * 146097 + doe - 719468
	end

	local LUNAR_BASE_DAY = dayNumber(LUNAR_BASE_YEAR, 2, 17) -- 1950 年正月初一

	-- 返回：农历年、月、日、是否闰月
	local function solarToLunar(y, m, d)
		local offset = dayNumber(y, m, d) - LUNAR_BASE_DAY
		if offset < 0 then
			return nil
		end

		local ly = LUNAR_BASE_YEAR
		while true do
			local days = lunarYearDays(ly)
			if offset < days then
				break
			end
			offset = offset - days
			ly = ly + 1
		end

		local leap = lunarLeapMonth(ly)
		local month = 1
		local leapDone = false
		while month <= 12 do
			local isLeap = (leap == month) and leapDone
			local days = isLeap and lunarLeapDays(ly) or lunarMonthDays(ly, month)
			if offset < days then
				return ly, month, offset + 1, isLeap
			end
			offset = offset - days
			if isLeap then
				month = month + 1
				leapDone = false
			elseif leap == month then
				leapDone = true
			else
				month = month + 1
			end
		end

		return ly, 12, 30, false
	end

	-- 形如「乙巳年九月十二」，闰月会写成「闰六月初一」
	lunarText = function(y, m, d)
		local ly, lm, ld, isLeap = solarToLunar(y, m, d)
		if not ly then
			return ""
		end
		local idx = (ly - 4) % 60
		local gan = GAN[idx % 10 + 1]
		local zhi = ZHI[idx % 12 + 1]
		return string.format(
			"农历%s%s年%s%s月%s",
			gan,
			zhi,
			isLeap and "闰" or "",
			LUNAR_MONTH_CN[lm] or "",
			LUNAR_DAY_CN[ld] or ""
		)
	end

end

local dateLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.fromOffset(0, 62),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextSize = 12,
	TextColor3 = COLORS.White,
	TextTransparency = 0.22,
	Parent = lockGroup,
})

local clockLabel, clockShadow = textWithShadow(lockGroup, {
	Size = UDim2.new(1, 0, 0, 92),
	Position = UDim2.fromOffset(0, 84),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "00:00",
	TextSize = 68,
	TextColor3 = COLORS.White,
	ZIndex = 21,
	Parent = lockGroup,
}, 0.6, 2)

-- 通知卡（原来的滚动字幕收在这里）
local card = new("Frame", {
	Name = "Notice",
	Size = UDim2.new(1, -36, 0, 80),
	Position = UDim2.fromOffset(18, 214),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.84,
	BorderSizePixel = 0,
	ZIndex = 22,
	Parent = lockGroup,
})
corner(card, 18)
stroke(card, COLORS.White, 0.86, 1)

local cardIcon = new("Frame", {
	Size = UDim2.fromOffset(24, 24),
	Position = UDim2.fromOffset(12, 12),
	BackgroundColor3 = Color3.fromRGB(108, 132, 255),
	BorderSizePixel = 0,
	ZIndex = 23,
	Parent = card,
})
corner(cardIcon, 7)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(120, 158, 255), Color3.fromRGB(150, 108, 255)),
	Rotation = 135,
	Parent = cardIcon,
})
new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "H",
	TextSize = 13,
	TextColor3 = COLORS.White,
	Parent = cardIcon,
})

new("TextLabel", {
	Size = UDim2.new(1, -80, 0, 15),
	Position = UDim2.fromOffset(44, 11),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = CONFIG.Title,
	TextSize = 12,
	TextColor3 = COLORS.White,
	TextTransparency = 0.05,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = card,
})

new("TextLabel", {
	Size = UDim2.fromOffset(48, 14),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "现在",
	TextSize = 10,
	TextColor3 = COLORS.White,
	TextTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = card,
})

local marqueeClip = new("Frame", {
	Size = UDim2.new(1, -24, 0, 30),
	Position = UDim2.fromOffset(12, 38),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 23,
	Parent = card,
})

local MARQUEE_LINES = {
	"科技重塑秩序，公平属于计算。欢迎回来，这里是哈夫克之声，我是克拉拉。",
	"当人类第一次点燃火焰，黑夜开始退却。当第一台计算机启动，信息开始流通。而今天，人工智能正在开启新的文明篇章。",
	"我们正在见证一个前所未有的时代，知识不再被垄断，创造不再受限于资源，连接不再受制于距离。",
	"每一次算法的迭代都在提升社会运行的效率，每一次技术的突破都在拓展人类认知的边界。",
	"科技真正的价值不是替代人类，而是让更多人拥有改变命运的机会。",
	"哈夫克相信技术应当服务于所有人，让智慧自由流动，让价值公平共享。",
	"哈夫克期待与你在未来再次相遇。",
}

local MARQUEE_UNIT = table.concat(MARQUEE_LINES, "　·　") .. "　　"
local MARQUEE_TEXT = MARQUEE_UNIT .. MARQUEE_UNIT
local MARQUEE_FONT = Enum.Font.Gotham
local MARQUEE_SIZE = 11

local unitWidth = 0
do
	local ok, size = pcall(function()
		return TextService:GetTextSize(MARQUEE_UNIT, MARQUEE_SIZE, MARQUEE_FONT, Vector2.new(20000, 40))
	end)
	if ok and size then
		unitWidth = size.X
	end
end

local marqueeLabel = new("TextLabel", {
	Size = UDim2.fromOffset(unitWidth * 2 > 0 and unitWidth * 2 or 0, 30),
	AutomaticSize = Enum.AutomaticSize.X,
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Font = MARQUEE_FONT,
	Text = MARQUEE_TEXT,
	TextSize = MARQUEE_SIZE,
	TextColor3 = COLORS.White,
	TextTransparency = 0.28,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Parent = marqueeClip,
})

-- 字幕用「一次循环 Tween」驱动，交给引擎插值，不再每帧写属性
local marqueeTween = nil

local function marqueeStart()
	if unitWidth <= 0 then
		return
	end
	if marqueeTween then
		marqueeTween:Play()
		return
	end
	marqueeLabel.Position = UDim2.fromOffset(0, 0)
	marqueeTween = TweenService:Create(
		marqueeLabel,
		TweenInfo.new(unitWidth / CONFIG.MarqueeSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Position = UDim2.fromOffset(-unitWidth, 0) }
	)
	marqueeTween:Play()
end

local function marqueePause()
	if marqueeTween then
		marqueeTween:Pause()
	end
end

-- 万一 TextService 取宽失败，用渲染后的 TextBounds 兜底
task.defer(function()
	if unitWidth <= 0 then
		local bounds = marqueeLabel.TextBounds
		if bounds and bounds.X > 0 then
			unitWidth = bounds.X * 0.5
			marqueeLabel.Size = UDim2.fromOffset(unitWidth * 2, 30)
			marqueeLabel.AutomaticSize = Enum.AutomaticSize.None
			marqueeStart()
		end
	end
end)

-- 底部小白条位置（离底 24px），提示条再往上留 24px 空隙
local INDICATOR_Y = CONFIG.Height - 16 -- 小白条：离底 16，Dock 抬到它上面
local SWIPE_HINT_Y = INDICATOR_Y - 24 - 18
local swipeHint = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.fromOffset(0, SWIPE_HINT_Y),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "↑  从小白条上滑解锁",
	TextSize = 12,
	TextColor3 = COLORS.White,
	TextTransparency = 0.42,
	Parent = lockGroup,
})

-- 底部小白条
local function makeIndicator(parent, y, zindex)
	local bar = new("Frame", {
		Size = UDim2.fromOffset(108, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		ZIndex = zindex or 24,
		Parent = parent,
	})
	corner(bar, 2)
	return bar
end

makeIndicator(lockGroup, INDICATOR_Y, 24)

--=============================================================
-- 主屏层
--=============================================================
local homeGroup = new("CanvasGroup", {
	Name = "Home",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 15,
	Parent = screen,
})

new("TextLabel", {
	Size = UDim2.new(1, -36, 0, 16),
	Position = UDim2.fromOffset(18, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "快捷应用",
	TextSize = 10,
	TextColor3 = COLORS.White,
	TextTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = homeGroup,
})

local tileRow = new("Frame", {
	Size = UDim2.new(1, -36, 0, 104),
	Position = UDim2.fromOffset(18, 74),
	BackgroundTransparency = 1,
	Parent = homeGroup,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8), -- 4 列：4×60 + 3×8 = 264，正好塞满一行
	Parent = tileRow,
})

-- 单个 APP 图标
local function makeTile(parent, opts)
	local cell = new("Frame", {
		Size = UDim2.fromOffset(60, 104),
		BackgroundTransparency = 1,
		LayoutOrder = opts.order or 1,
		Parent = parent,
	})

	local icon = new("TextButton", {
		Name = opts.abbr,
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = opts.color,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = cell,
	})
	corner(icon, 14)
	new("UIGradient", {
		Color = ColorSequence.new(opts.color, opts.color2 or opts.color),
		Rotation = 135,
		Parent = icon,
	})
	stroke(icon, COLORS.White, 0.84, 1)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = opts.abbr,
		TextSize = 16,
		TextColor3 = COLORS.White,
		Parent = icon,
	})

	local label = new("TextLabel", {
		Size = UDim2.new(1, 8, 0, 14),
		Position = UDim2.new(0, -4, 0, 67),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = opts.name,
		TextSize = 11,
		TextColor3 = COLORS.White,
		TextTransparency = 0.12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = cell,
	})

	icon.MouseEnter:Connect(function()
		TweenService:Create(icon, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(64, 64),
		}):Play()
	end)
	icon.MouseLeave:Connect(function()
		TweenService:Create(icon, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(60, 60),
		}):Play()
	end)
	icon.MouseButton1Click:Connect(function()
		if opts.onClick then
			opts.onClick()
		end
	end)

	return cell
end

--=============================================================
-- 远程脚本
--=============================================================
local SCRIPT_URLS = {
	fly = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/fly.lua",
	tp  = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/cicktp.lua",
	car = "https://raw.githubusercontent.com/Sfk994/Df/refs/heads/main/flycar.lua",
}

--=============================================================
-- 日志
--=============================================================
local logLines = {}
local unread = 0
local logVisible = false
local booting = true

local logScroll, logList, dockLogDot, logRow
local refreshStatus
local logLabels = {}

-- 日志刷屏时把状态刷新合并成 0.12s 一次，避免每条日志都改一次 UI
local statusQueued = false
local function queueStatusRefresh()
	if statusQueued then
		return
	end
	statusQueued = true
	task.delay(0.12, function()
		statusQueued = false
		if refreshStatus then
			refreshStatus()
		end
	end)
end

local function refreshUnread()
	local showDock = unread > 0 and not logVisible
	if dockLogDot and dockLogDot.Visible ~= showDock then
		dockLogDot.Visible = showDock
	end
	local showRow = unread > 0
	if logRow and logRow.dot.Visible ~= showRow then
		logRow.dot.Visible = showRow
	end
end

local function stamp()
	return os.date("%H:%M:%S")
end

-- 只在日志页真正打开时才创建 TextLabel：脚本刷屏时不再每行都建控件
local function addLogLabel(item, order)
	local line = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = string.format("[%s] %s", item.time, item.text),
		TextSize = 11,
		TextColor3 = LEVEL_COLORS[item.level] or LEVEL_COLORS.info,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = order,
		Parent = logList,
	})
	table.insert(logLabels, line)
	return line
end

local function scrollLogToBottom()
	if not logScroll then
		return
	end
	task.defer(function()
		logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteSize.Y))
	end)
end

local function rebuildLog()
	if not logList then
		return
	end
	for _, label in ipairs(logLabels) do
		label:Destroy()
	end
	logLabels = {}
	for i, item in ipairs(logLines) do
		addLogLabel(item, i)
	end
	scrollLogToBottom()
end

function log(message, level)
	level = level or "info"
	message = tostring(message)

	local item = { text = message, level = level, time = stamp() }
	table.insert(logLines, item)
	while #logLines > CONFIG.MaxLogLines do
		table.remove(logLines, 1)
	end

	if refreshStatus then
		queueStatusRefresh()
	end

	if logList and logVisible then
		addLogLabel(item, #logLines)
		while #logLabels > #logLines do
			local oldest = table.remove(logLabels, 1)
			if oldest then
				oldest:Destroy()
			end
		end
		scrollLogToBottom()
	elseif not booting then
		unread = unread + 1
		refreshUnread()
	end
end

local function httpGet(url)
	-- 执行器一般提供 game:HttpGet；失败再退回 HttpService
	if game.HttpGet then
		local ok, result = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(result) == "string" then
			return result
		end
	end
	local HttpService = game:GetService("HttpService")
	return HttpService:GetAsync(url)
end

local function runRemote(name, url)
	log(string.format("正在加载「%s」…", name), "info")
	task.spawn(function()
		local ok, err = pcall(function()
			local source = httpGet(url)
			local fn = loadstring(source)
			if not fn then
				error("当前环境不支持 loadstring（需要执行器）")
			end
			fn()
		end)
		if ok then
			log(string.format("「%s」已执行", name), "success")
		else
			log(string.format("「%s」执行失败：%s", name, tostring(err)), "error")
		end
	end)
end

--=============================================================
-- 三个 APP 图标
--=============================================================
local APPS = {
	{
		order = 1, name = "飞行", abbr = "FLY",
		color = Color3.fromRGB(96, 148, 255), color2 = Color3.fromRGB(150, 108, 255),
		url = SCRIPT_URLS.fly,
	},
	{
		order = 2, name = "点击 TP", abbr = "TP",
		color = Color3.fromRGB(52, 192, 160), color2 = Color3.fromRGB(42, 146, 204),
		url = SCRIPT_URLS.tp,
	},
	{
		order = 3, name = "飞车", abbr = "CAR",
		color = Color3.fromRGB(255, 154, 92), color2 = Color3.fromRGB(238, 92, 112),
		url = SCRIPT_URLS.car,
	},
}

for _, app in ipairs(APPS) do
	makeTile(tileRow, {
		order = app.order,
		name = app.name,
		abbr = app.abbr,
		color = app.color,
		color2 = app.color2,
		onClick = function()
			runRemote(app.name, app.url)
		end,
	})
end

--=============================================================
-- 主屏留白处的水印（运行状态 / 日志已并入设置页）
--=============================================================
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 46),
	Position = UDim2.fromOffset(0, 356),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "HAVVK",
	TextSize = 42,
	TextColor3 = COLORS.White,
	TextTransparency = 0.86,
	Parent = homeGroup,
})

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.fromOffset(0, 404),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "PHONE   ·   v2.7",
	TextSize = 9,
	TextColor3 = COLORS.White,
	TextTransparency = 0.78,
	Parent = homeGroup,
})

--=============================================================
-- Dock（图标全部用线条绘制，不依赖字体字形）
--=============================================================

local dock = new("Frame", {
	Size = UDim2.new(1, -36, 0, 72),
	Position = UDim2.fromOffset(18, 538),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
	Parent = homeGroup,
})
corner(dock, 24)
stroke(dock, COLORS.White, 0.88, 1)

local dockRow = new("Frame", {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Parent = dock,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 20),
	Parent = dockRow,
})

-- 锁：锁梁（描边圆角环）+ 锁身
local function iconLock(parent, s)
	s = s or 1
	local shackle = new("Frame", {
		Size = UDim2.fromOffset(10 * s, 11 * s),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, -9.6 * s),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	corner(shackle, 5 * s)
	stroke(shackle, COLORS.White, 0.04, 1.7 * s)

	local body = new("Frame", {
		Size = UDim2.fromOffset(15 * s, 12 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 2.6 * s),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(body, 3.4 * s)

	local hole = new("Frame", {
		Size = UDim2.fromOffset(2.4 * s, 3.4 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 1.6 * s),
		BackgroundColor3 = Color3.fromRGB(48, 54, 66),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = body,
	})
	corner(hole, 1.2 * s)
end

-- 设置：三条滑轨 + 滑块
local function iconSliders(parent, s)
	s = s or 1
	local railsY = { -6.4, 0, 6.4 }
	local knobsX = { 4.2, -3.4, 0.8 }
	for i = 1, 3 do
		local rail = new("Frame", {
			Size = UDim2.fromOffset(16 * s, 1.8 * s),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, railsY[i] * s),
			BackgroundColor3 = COLORS.White,
			BackgroundTransparency = 0.22,
			BorderSizePixel = 0,
			Parent = parent,
		})
		corner(rail, 0.9 * s)

		local knob = new("Frame", {
			Size = UDim2.fromOffset(5 * s, 5 * s),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, knobsX[i] * s, 0.5, railsY[i] * s),
			BackgroundColor3 = COLORS.White,
			BorderSizePixel = 0,
			Parent = parent,
		})
		corner(knob, 2.5 * s)
	end
end

-- 日志：文档描边 + 三行文本
local function iconDocs(parent, s)
	s = s or 1
	local doc = new("Frame", {
		Size = UDim2.fromOffset(13 * s, 16 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	corner(doc, 2.8 * s)
	stroke(doc, COLORS.White, 0.05, 1.5 * s)

	local widths = { 6.5, 6.5, 4 }
	for i = 1, 3 do
		local line = new("Frame", {
			Size = UDim2.fromOffset(widths[i] * s, 1.3 * s),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (-4.2 + (i - 1) * 4.2) * s),
			BackgroundColor3 = COLORS.White,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Parent = doc,
		})
		corner(line, 0.65 * s)
	end
end

-- 换壁纸：两张叠起来的画布
local function iconPicture(parent, s)
	s = s or 1
	local back = new("Frame", {
		Size = UDim2.fromOffset(11 * s, 9 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 2.8 * s, 0.5, -3 * s),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	corner(back, 2.4 * s)
	stroke(back, COLORS.White, 0.5, 1.3 * s)

	local front = new("Frame", {
		Size = UDim2.fromOffset(12.6 * s, 10 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -1.6 * s, 0.5, 1.8 * s),
		BackgroundColor3 = parent.BackgroundColor3,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(front, 2.6 * s)
	stroke(front, COLORS.White, 0.05, 1.5 * s)

	local sun = new("Frame", {
		Size = UDim2.fromOffset(3.2 * s, 3.2 * s),
		Position = UDim2.fromOffset(2.6 * s, 2.4 * s),
		BackgroundColor3 = COLORS.White,
		BorderSizePixel = 0,
		Parent = front,
	})
	corner(sun, 1.6 * s)

	local hill = new("Frame", {
		Size = UDim2.fromOffset(7 * s, 1.5 * s),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2.4 * s, 1, -2.6 * s),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = front,
	})
	corner(hill, 0.75 * s)
end

-- 关于本机：i 字形徽标
local function iconInfo(parent, s)
	s = s or 1
	local ring = new("Frame", {
		Size = UDim2.fromOffset(14 * s, 14 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	corner(ring, 7 * s)
	stroke(ring, COLORS.White, 0.05, 1.5 * s)

	local dot = new("Frame", {
		Size = UDim2.fromOffset(2 * s, 2 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -3.4 * s),
		BackgroundColor3 = COLORS.White,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(dot, 1 * s)

	local bar = new("Frame", {
		Size = UDim2.fromOffset(1.9 * s, 5.2 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 1.4 * s),
		BackgroundColor3 = COLORS.White,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(bar, 0.95 * s)
end

-- 重载：圆环 + 顶部缺口 + 竖杠（电源符号）
local function iconPower(parent, s)
	s = s or 1
	local ring = new("Frame", {
		Size = UDim2.fromOffset(14 * s, 14 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	corner(ring, 7 * s)
	stroke(ring, COLORS.White, 0.05, 1.7 * s)

	-- 用底色块咬掉圆环顶部，做出开口
	new("Frame", {
		Size = UDim2.fromOffset(6 * s, 5 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -8 * s),
		BackgroundColor3 = parent.BackgroundColor3,
		BorderSizePixel = 0,
		Parent = parent,
	})

	local bar = new("Frame", {
		Size = UDim2.fromOffset(1.7 * s, 8.4 * s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -4.2 * s),
		BackgroundColor3 = COLORS.White,
		BorderSizePixel = 0,
		Parent = parent,
	})
	corner(bar, 0.85 * s)
end

local function makeDockButton(order, draw, color1, color2, onClick)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = color1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = dockRow,
	})
	corner(btn, 13)
	new("UIGradient", {
		Color = ColorSequence.new(color1, color2),
		Rotation = 135,
		Parent = btn,
	})
	stroke(btn, COLORS.White, 0.9, 1)

	draw(btn, 1)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { Size = UDim2.fromOffset(48, 48) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { Size = UDim2.fromOffset(46, 46) }):Play()
	end)
	btn.MouseButton1Click:Connect(function()
		if onClick then
			onClick()
		end
	end)
	return btn
end

--=============================================================
-- 设置页 / 日志页
--=============================================================
local pages = {}

local function closePage(page)
	if not page.Visible then
		return
	end
	page.Position = UDim2.fromOffset(0, 0)
	local tween = TweenService:Create(page, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(CONFIG.Width, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		page.Visible = false
		page.Position = UDim2.fromOffset(CONFIG.Width, 0)
		page.GroupTransparency = 0
	end)
end

local function openPage(page)
	page.Visible = true
	page.GroupTransparency = 0
	page.Position = UDim2.fromOffset(CONFIG.Width, 0)
	TweenService:Create(page, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()
	if page == pages.about and updateAboutLive then
		task.defer(updateAboutLive)
	end

	if page == pages.log then
		logVisible = true
		unread = 0
		refreshUnread()
		rebuildLog() -- 打开时才把历史日志铺成控件
	end
end

local function makePage(name, title)
	-- 用 CanvasGroup：整页可以一起淡出（上滑返回时才有「化开」的感觉）
	local page = new("CanvasGroup", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(CONFIG.Width, 0),
		BackgroundColor3 = COLORS.Page,
		BorderSizePixel = 0,
		GroupTransparency = 0,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	})
	corner(page, CONFIG.Corner)

	local back = new("TextButton", {
		Size = UDim2.fromOffset(70, 26),
		Position = UDim2.fromOffset(14, 40),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = "‹ 返回",
		TextSize = 13,
		TextColor3 = COLORS.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = page,
	})
	back.MouseButton1Click:Connect(function()
		if page == pages.log then
			logVisible = false
			refreshUnread()
		end
		closePage(page)
	end)

	new("TextLabel", {
		Size = UDim2.new(1, -140, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 43),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextSize = 14,
		TextColor3 = COLORS.Text,
		Parent = page,
	})

	return page
end

-- 设置页
local settingsPage = makePage("Settings", "设置")
pages.settings = settingsPage

-- 运行状态卡：帧率 / 延迟 / 日志条数（原来在主屏，现统一收进设置）
local statusCard = new("Frame", {
	Size = UDim2.new(1, -36, 0, 68),
	Position = UDim2.fromOffset(18, 70),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.92,
	BorderSizePixel = 0,
	Parent = settingsPage,
})
corner(statusCard, 14)
stroke(statusCard, COLORS.White, 0.9, 1)

local function statCell(index, caption, initial, color)
	local x = 16 + (index - 1) * 82
	local value = new("TextLabel", {
		Size = UDim2.fromOffset(70, 20),
		Position = UDim2.fromOffset(x, 15),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = initial,
		TextSize = 18,
		TextColor3 = color or COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = statusCard,
	})
	new("TextLabel", {
		Size = UDim2.fromOffset(76, 12),
		Position = UDim2.fromOffset(x, 37),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = caption,
		TextSize = 9,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = statusCard,
	})
	return value
end

local fpsValue = statCell(1, "FPS 帧率", "60", COLORS.Green)
local pingValue = statCell(2, "PING 延迟", "--", COLORS.Green)
local logCountValue = statCell(3, "日志条数", "0", COLORS.Text)

for i = 1, 2 do
	new("Frame", {
		Size = UDim2.new(0, 1, 0, 38),
		Position = UDim2.fromOffset(88 * i + 4, 15),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = statusCard,
	})
end

local function makeSettingRow(y, draw, color, title, desc, onClick)
	local row = new("TextButton", {
		Size = UDim2.new(1, -36, 0, 54),
		Position = UDim2.fromOffset(18, y),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = settingsPage,
	})
	corner(row, 14)
	stroke(row, COLORS.White, 0.9, 1)

	local badge = new("Frame", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(badge, 8)
	draw(badge, 0.6)

	new("TextLabel", {
		Size = UDim2.new(1, -104, 0, 15),
		Position = UDim2.fromOffset(52, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = title,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local descLabel = new("TextLabel", {
		Size = UDim2.new(1, -104, 0, 13),
		Position = UDim2.fromOffset(52, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = desc,
		TextSize = 9,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local dot = new("Frame", {
		Size = UDim2.fromOffset(7, 7),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -34, 0.5, 0),
		BackgroundColor3 = COLORS.Red,
		BorderSizePixel = 0,
		Visible = false,
		Parent = row,
	})
	corner(dot, 3.5)

	new("TextLabel", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "›",
		TextSize = 16,
		TextColor3 = COLORS.SubText,
		TextTransparency = 0.3,
		Parent = row,
	})

	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.86 }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.92 }):Play()
	end)
	row.MouseButton1Click:Connect(function()
		if onClick then
			onClick()
		end
	end)

	return { row = row, desc = descLabel, dot = dot }
end

wallpaperRow = makeSettingRow(152, iconPicture, Color3.fromRGB(176, 104, 208), "换壁纸", "当前壁纸：" .. WALLPAPERS[wallpaperIndex].name, function()
	setWallpaper(wallpaperIndex + 1)
end)

makeSettingRow(214, iconPower, Color3.fromRGB(96, 130, 220), "重载面板", "重新载入配置并清空未读", function()
	if type(API.OnReload) == "function" then
		local ok, err = pcall(API.OnReload)
		if not ok then
			log("重载出错：" .. tostring(err), "error")
		end
	end
	log("面板已重载", "success")
	unread = 0
	refreshUnread()
	refreshStatus()
end)

logRow = makeSettingRow(276, iconDocs, Color3.fromRGB(72, 160, 140), "日志", "查看脚本输出记录", function()
	openPage(pages.log)
end)

makeSettingRow(338, iconInfo, Color3.fromRGB(112, 118, 136), "关于本机", "账号 / 设备 / 运行明细", function()
	openPage(pages.about)
end)

-- 版本信息
new("TextLabel", {
	Size = UDim2.new(1, -36, 0, 16),
	Position = UDim2.fromOffset(18, 404),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "HAVVK Phone · v2.7",
	TextSize = 9,
	TextColor3 = COLORS.SubText,
	TextTransparency = 0.25,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = settingsPage,
})

-- 设置页状态刷新
function refreshStatus()
	if logCountValue then
		logCountValue.Text = tostring(#logLines)
	end
	if logRow then
		local last = logLines[#logLines]
		if last then
			logRow.desc.Text = string.format("%s  %s", last.time, last.text)
			logRow.desc.TextColor3 = LEVEL_COLORS[last.level] or COLORS.SubText
		else
			logRow.desc.Text = "查看脚本输出记录"
			logRow.desc.TextColor3 = COLORS.SubText
		end
		logRow.dot.Visible = unread > 0
	end
end

--=============================================================
-- 关于本机页（分组明细 + 滚动）
--=============================================================
local aboutPage = makePage("About", "关于本机")
pages.about = aboutPage

local aboutScroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 64),
	Size = UDim2.new(1, 0, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = Color3.fromRGB(72, 80, 96),
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = aboutPage,
})

local aboutList = new("Frame", {
	Size = UDim2.new(1, -36, 0, 0),
	Position = UDim2.fromOffset(18, 6),
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = aboutScroll,
})
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = aboutList,
})

local aboutLive = {}

local function safeCall(fn, fallback)
	local ok, value = pcall(fn)
	if ok and value ~= nil then
		return value
	end
	return fallback
end

local function aboutSection(order, title, rows)
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34 + #rows * 38),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = aboutList,
	})
	corner(card, 14)
	stroke(card, COLORS.White, 0.9, 1)

	new("TextLabel", {
		Size = UDim2.new(1, -28, 0, 14),
		Position = UDim2.fromOffset(14, 11),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextSize = 9,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	for i, row in ipairs(rows) do
		local y = 29 + (i - 1) * 38

		new("TextLabel", {
			Size = UDim2.new(0, 96, 0, 38),
			Position = UDim2.fromOffset(14, y),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = row[1],
			TextSize = 11,
			TextColor3 = COLORS.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})

		local valueLabel = new("TextLabel", {
			Size = UDim2.new(1, -124, 0, 38),
			Position = UDim2.fromOffset(110, y),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = row[2] or "—",
			TextSize = 11,
			TextColor3 = row[4] or COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
		})

		if row[3] then
			aboutLive[row[3]] = valueLabel
		end

		if i < #rows then
			new("Frame", {
				Size = UDim2.new(1, -28, 0, 1),
				Position = UDim2.fromOffset(14, y + 37),
				BackgroundColor3 = COLORS.White,
				BackgroundTransparency = 0.93,
				BorderSizePixel = 0,
				Parent = card,
			})
		end
	end

	return card
end

-- ---------- 品牌卡 ----------
local heroCard = new("Frame", {
	Size = UDim2.new(1, 0, 0, 86),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.92,
	BorderSizePixel = 0,
	LayoutOrder = 1,
	Parent = aboutList,
})
corner(heroCard, 16)
stroke(heroCard, COLORS.White, 0.9, 1)

local heroIcon = new("Frame", {
	Size = UDim2.fromOffset(46, 46),
	Position = UDim2.fromOffset(14, 20),
	BackgroundColor3 = Color3.fromRGB(96, 148, 255),
	BorderSizePixel = 0,
	Parent = heroCard,
})
corner(heroIcon, 13)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(108, 150, 255), Color3.fromRGB(158, 108, 255)),
	Rotation = 135,
	Parent = heroIcon,
})
new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "H",
	TextSize = 21,
	TextColor3 = COLORS.White,
	Parent = heroIcon,
})

new("TextLabel", {
	Size = UDim2.new(1, -84, 0, 18),
	Position = UDim2.fromOffset(72, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "HAVVK Phone",
	TextSize = 14,
	TextColor3 = COLORS.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = heroCard,
})

new("TextLabel", {
	Size = UDim2.new(1, -84, 0, 14),
	Position = UDim2.fromOffset(72, 42),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "调试面板 v2.7 · 构建 217",
	TextSize = 9,
	TextColor3 = COLORS.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = heroCard,
})

new("TextLabel", {
	Size = UDim2.new(1, -84, 0, 14),
	Position = UDim2.fromOffset(72, 58),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "iOS 锁屏风格 · Luau",
	TextSize = 9,
	TextColor3 = COLORS.SubText,
	TextTransparency = 0.25,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = heroCard,
})

-- ---------- 采集环境信息 ----------
local executorName = "Roblox Studio"
if type(identifyexecutor) == "function" then
	local ok, name = pcall(identifyexecutor)
	if ok and type(name) == "string" and name ~= "" then
		executorName = name
	end
end

local camera = safeCall(function()
	return workspace.CurrentCamera
end, nil)
local viewport = (camera and camera.ViewportSize) or Vector2.new(0, 0)

local platformName = safeCall(function()
	local p = UserInputService:GetPlatform()
	return (tostring(p):gsub("Enum.Platform.", ""))
end, "—")

local deviceType
if UserInputService.TouchEnabled and UserInputService.KeyboardEnabled then
	deviceType = "触屏 + 键鼠"
elseif UserInputService.TouchEnabled then
	deviceType = "移动端 · 触屏"
elseif UserInputService.GamepadEnabled then
	deviceType = "手柄"
else
	deviceType = "PC · 键鼠"
end

local qualityName = safeCall(function()
	return tostring(UserSettings().GameSettings.SavedQualityLevel)
end, "—")
qualityName = qualityName:gsub("Enum.QualityLevel.", "")

local membership = safeCall(function()
	return player.MembershipType.Name
end, "None")
local MEMBER_LABEL = {
	None = "普通玩家",
	Premium = "Premium 会员",
	BC = "Builders Club",
	TBC = "Turbo Builders Club",
	OBC = "Outrageous Builders Club",
}

local accountAge = safeCall(function()
	return player.AccountAge
end, 0)

local playerName = safeCall(function()
	return player.Name
end, "—")

local displayName = safeCall(function()
	return player.DisplayName
end, playerName)

local userId = safeCall(function()
	return player.UserId
end, "—")

local jobId = safeCall(function()
	return game.JobId
end, "")
if type(jobId) ~= "string" or jobId == "" then
	jobId = "本地 / Studio"
elseif #jobId > 12 then
	jobId = string.sub(jobId, 1, 12) .. "…"
end

local playerCount = safeCall(function()
	return #Players:GetPlayers()
end, 1)

local memoryMb = safeCall(function()
	local stats = game:GetService("Stats")
	return math.floor(stats:GetTotalMemoryUsageMb() + 0.5)
end, nil)

local function fmtClock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function serverUptime()
	local t = safeCall(function()
		return workspace.DistributedGameTime
	end, nil)
	return t and fmtClock(t) or "—"
end

-- ---------- 四组明细 ----------
aboutSection(2, "账号", {
	{ "昵称", tostring(playerName or "—") },
	{ "显示名称", tostring(displayName or "—") },
	{ "用户 ID", tostring(userId or "—") },
	{ "账号年龄", accountAge > 0 and (tostring(accountAge) .. " 天") or "—" },
	{ "会员", MEMBER_LABEL[membership] or membership },
})

aboutSection(3, "设备", {
	{ "系统平台", platformName },
	{ "设备类型", deviceType },
	{ "屏幕分辨率", string.format("%d × %d", viewport.X, viewport.Y) },
	{ "画质档位", qualityName },
	{ "界面缩放", string.format("%.2f ×", (gui.AbsoluteSize.Y > 0) and (root.AbsoluteSize.Y / CONFIG.Height) or 1) },
})

aboutSection(4, "运行", {
	{ "帧率 FPS", "—", "fps", COLORS.Green },
	{ "网络延迟", "—", "ping", COLORS.Green },
	{ "服务器运行", serverUptime(), "uptime" },
	{ "服务器 ID", jobId },
	{ "在线玩家", tostring(playerCount) .. " 人" },
	{ "内存占用", memoryMb and (tostring(memoryMb) .. " MB") or "—", "memory" },
})

local panelRows = {
	{ "面板版本", "v2.7（构建 217）" },
	{ "面板尺寸", string.format("%d × %d", CONFIG.Width, CONFIG.Height) },
	{ "当前壁纸", WALLPAPERS[wallpaperIndex].name, "wallpaper" },
	{ "日志条数", tostring(#logLines), "logs" },
	{ "执行器", executorName },
	{ "快捷键", "F2 显隐面板" },
}
aboutSection(5, "面板", panelRows)

aboutWallpaperValue = aboutLive.wallpaper

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "仅用于个人调试 · © HAVVK 科技",
	TextSize = 9,
	TextColor3 = COLORS.SubText,
	TextTransparency = 0.3,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 6,
	Parent = aboutList,
})

-- 关于页实时数值（只在页面可见时由 Heartbeat 驱动）
function updateAboutLive()
	if aboutLive.fps and currentFps then
		aboutLive.fps.Text = tostring(currentFps)
		aboutLive.fps.TextColor3 = fpsColor(currentFps)
	end
	if aboutLive.ping and currentPing then
		aboutLive.ping.Text = tostring(currentPing)
		aboutLive.ping.TextColor3 = pingColor(currentPing)
	end
	if aboutLive.uptime then
		aboutLive.uptime.Text = serverUptime()
	end
	if aboutLive.logs then
		aboutLive.logs.Text = tostring(#logLines)
	end
	if aboutLive.wallpaper then
		aboutLive.wallpaper.Text = WALLPAPERS[wallpaperIndex].name
	end
	if aboutLive.memory then
		local mb = safeCall(function()
			return math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb() + 0.5)
		end, nil)
		aboutLive.memory.Text = mb and (tostring(mb) .. " MB") or "—"
	end
end

-- 日志页
local logPage = makePage("Log", "日志")
pages.log = logPage

local clearBtn = new("TextButton", {
	Size = UDim2.fromOffset(52, 24),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 41),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamMedium,
	Text = "清空",
	TextSize = 11,
	TextColor3 = COLORS.Text,
	Parent = logPage,
})
corner(clearBtn, 7)
clearBtn.MouseButton1Click:Connect(function()
	logLines = {}
	for _, label in ipairs(logLabels) do
		label:Destroy()
	end
	logLabels = {}
	unread = 0
	refreshUnread()
	refreshStatus()
	log("日志已清空", "warn")
end)

logScroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(14, 72),
	Size = UDim2.new(1, -28, 1, -88),
	BackgroundColor3 = Color3.fromRGB(11, 12, 18),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = Color3.fromRGB(80, 88, 104),
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = logPage,
})
corner(logScroll, 12)

logList = new("Frame", {
	Size = UDim2.new(1, -16, 0, 0),
	Position = UDim2.fromOffset(8, 8),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = logScroll,
})
new("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = logList,
})

-- 用已有的历史日志填充一次
for _, item in ipairs(logLines) do
	-- 启动时为空，这里仅作占位
end

--=============================================================
-- 玩家列表页
--   · 头像 / 昵称 / 账号时间（AccountAge）/ 与你的距离 / 一键传送
--   · 距离每秒刷新一次，只有页面可见时才更新
--=============================================================
do
	local avatarCache = {}

	local playerPage = makePage("Players", "玩家列表")
	pages.players = playerPage

	local countLabel = new("TextLabel", {
		Size = UDim2.fromOffset(110, 16),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "在线 0 人",
		TextSize = 10,
		TextColor3 = COLORS.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = playerPage,
	})

	local refreshBtn = new("TextButton", {
		Size = UDim2.fromOffset(44, 22),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 64),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = "刷新",
		TextSize = 10,
		TextColor3 = COLORS.Text,
		Parent = playerPage,
	})
	corner(refreshBtn, 7)

	local playerScroll = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Color3.fromRGB(72, 80, 96),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = playerPage,
	})

	local playerList = new("Frame", {
		Size = UDim2.new(1, -28, 0, 0),
		Position = UDim2.fromOffset(14, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = playerScroll,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = playerList,
	})

	local function fmtAge(days)
		days = math.max(0, math.floor(days or 0))
		if days < 365 then
			return string.format("账号 %d 天", days)
		end
		return string.format("账号 %d 年 %d 天", math.floor(days / 365), days % 365)
	end

	local function fmtDist(m)
		m = math.max(0, m or 0)
		if m < 1 then
			return "距你 0 m"
		elseif m < 1000 then
			return string.format("距你 %d m", math.floor(m + 0.5))
		end
		return string.format("距你 %.1f km", m / 1000)
	end

	local function distanceTo(target)
		local myChar = player.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		local tChar = target.Character
		local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if not (myRoot and tRoot) then
			return nil
		end
		return (myRoot.Position - tRoot.Position).Magnitude
	end

	local function teleportTo(target)
		local myChar = player.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		local tChar = target.Character
		local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if not (myRoot and tRoot) then
			log("传送失败：" .. target.Name .. " 当前不在场景中", "warn")
			return
		end
		local ok = pcall(function()
			myChar:PivotTo(tRoot.CFrame * CFrame.new(0, 0, 3.4))
		end)
		if ok then
			log("已传送到 " .. target.Name, "success")
		else
			log("传送失败：" .. target.Name, "error")
		end
	end

	local rows = {}
	local rebuild -- 前向声明

	local function makeRow(target, index)
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundColor3 = COLORS.White,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = playerList,
		})
		corner(row, 13)
		stroke(row, COLORS.White, 0.92, 1)

		-- 头像
		local avatar = new("ImageLabel", {
			Name = "Avatar",
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.fromOffset(11, 11),
			BackgroundColor3 = Color3.fromRGB(38, 42, 56),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Image = "",
			ScaleType = Enum.ScaleType.Crop,
			Parent = row,
		})
		corner(avatar, 10)

		local cached = avatarCache[target.UserId]
		if cached then
			avatar.Image = cached
		else
			task.spawn(function()
				local ok, url = pcall(function()
					return Players:GetUserThumbnailAsync(
						target.UserId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size48x48
					)
				end)
				if ok and url and url ~= "" then
					avatarCache[target.UserId] = url
					if avatar.Parent then
						avatar.Image = url
					end
				end
			end)
		end

		-- 昵称（自己是「你」的高亮标记）
		new("TextLabel", {
			Size = UDim2.new(1, -110, 0, 16),
			Position = UDim2.fromOffset(56, 10),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = target.Name .. (target == player and "（你）" or ""),
			TextSize = 11,
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		local info = new("TextLabel", {
			Size = UDim2.new(1, -110, 0, 14),
			Position = UDim2.fromOffset(56, 27),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = "",
			TextSize = 9,
			TextColor3 = COLORS.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		local tp = new("TextButton", {
			Size = UDim2.fromOffset(42, 26),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -11, 0.5, 0),
			BackgroundColor3 = COLORS.Accent,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamBold,
			Text = "TP",
			TextSize = 10,
			TextColor3 = COLORS.White,
			Parent = row,
		})
		corner(tp, 8)
		tp.MouseButton1Click:Connect(function()
			teleportTo(target)
		end)

		return row, info
	end

	-- 每秒刷新一次距离文本（只改文本，不重建控件）
	local function refreshTimes()
		if not playerPage.Visible then
			return
		end
		for _, item in ipairs(rows) do
			local d = distanceTo(item.player)
			item.info.Text = string.format(
				"%s · %s",
				fmtAge(item.player.AccountAge),
				d and fmtDist(d) or "距离未知"
			)
		end
	end

	rebuild = function()
		for _, item in ipairs(rows) do
			item.row:Destroy()
		end
		rows = {}

		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			local da = distanceTo(a) or math.huge
			local db = distanceTo(b) or math.huge
			return da < db
		end)

		for i, target in ipairs(list) do
			local row, info = makeRow(target, i)
			local d = distanceTo(target)
			info.Text = string.format("%s · %s", fmtAge(target.AccountAge), d and fmtDist(d) or "距离未知")
			rows[#rows + 1] = { row = row, info = info, player = target }
		end

		countLabel.Text = string.format("在线 %d 人", #list)
		if #list == 0 then
			countLabel.Text = "在线 0 人"
		end
	end

	refreshBtn.MouseButton1Click:Connect(function()
		rebuild()
		refreshTimes()
		log("玩家列表已刷新（" .. #Players:GetPlayers() .. " 人）", "info")
	end)

	-- 进服 / 离服时，页面可见才重建
	Players.PlayerAdded:Connect(function(target)
		if playerPage.Visible then
			rebuild()
		end
	end)
	Players.PlayerRemoving:Connect(function(target)
		if playerPage.Visible then
			rebuild()
		end
	end)

	-- 打开时重建 + 起一个 1 秒的计时器（页面关掉就空转，几乎不占开销）
	task.spawn(function()
		while true do
			task.wait(1)
			refreshTimes()
		end
	end)

	-- 第 4 个应用：玩家列表
	makeTile(tileRow, {
		order = 4,
		name = "玩家列表",
		abbr = "PLR",
		color = Color3.fromRGB(120, 132, 255),
		color2 = Color3.fromRGB(90, 196, 255),
		onClick = function()
			openPage(playerPage)
			rebuild()
			refreshTimes()
		end,
	})

	-- 打开页面时也刷新一次（openPage 里统一走这里）
	local originalOpen = openPage
	openPage = function(page)
		originalOpen(page)
		if page == playerPage then
			rebuild()
			refreshTimes()
		end
	end
end

--=============================================================
-- Dock 按钮（依赖上面的页面对象）
--=============================================================
local reopenBtn

local function setVisible(state)
	local on = state and true or false
	root.Visible = on
	reopenBtn.Visible = not on
	if on then
		if not unlocked then
			marqueeStart()
		end
	else
		marqueePause()
	end
end

reopenBtn = new("TextButton", {
	Name = "Reopen",
	Size = UDim2.fromOffset(104, 30),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	BackgroundColor3 = COLORS.Screen,
	BorderSizePixel = 0,
	Visible = false,
	AutoButtonColor = false,
	Font = Enum.Font.GothamMedium,
	Text = "HAVVK (F2)",
	TextSize = 11,
	TextColor3 = COLORS.Text,
	Parent = gui,
})
corner(reopenBtn, 9)
stroke(reopenBtn, COLORS.White, 0.86, 1)
reopenBtn.MouseButton1Click:Connect(function()
	setVisible(true)
end)

local dockLogButton = nil

makeDockButton(1, iconLock, Color3.fromRGB(104, 114, 136), Color3.fromRGB(66, 74, 92), function()
	-- 由下方 lock 定义前先占位，运行到这里时已赋值
	if lock then
		lock()
	end
end)

makeDockButton(2, iconSliders, Color3.fromRGB(108, 122, 158), Color3.fromRGB(70, 82, 110), function()
	openPage(pages.settings)
end)

dockLogButton = makeDockButton(3, iconDocs, Color3.fromRGB(72, 168, 148), Color3.fromRGB(48, 118, 122), function()
	openPage(pages.log)
end)

dockLogDot = new("Frame", {
	Size = UDim2.fromOffset(8, 8),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -2, 0, 2),
	BackgroundColor3 = COLORS.Red,
	BorderSizePixel = 0,
	Visible = false,
	Parent = dockLogButton,
})
corner(dockLogDot, 4)

--=============================================================
-- 底部上滑返回桌面
--   · 解锁后底部常驻一条小白条（iOS 的 home indicator）
--   · 在小白条那一带往上拖：页面跟着手指走、逐渐透明，
--     松手超过阈值就一路飞出屏幕，没到阈值就弹回原位
--=============================================================
local homePill = makeIndicator(screen, INDICATOR_Y, 52)
homePill.BackgroundTransparency = 1 -- 锁屏时由锁屏层自己那条负责

do
	local function activePage()
		for _, page in pairs(pages) do
			if page.Visible then
				return page
			end
		end
		return nil
	end

	local homeDrag = nil

	-- 主屏落回来的那一下回弹
	local function bounceHome(dy)
		homeGroup.Position = UDim2.fromOffset(0, math.min(10, dy * 0.12))
		TweenService:Create(homeGroup, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		}):Play()
	end

	-- 没拉够：页面弹回原位
	local function settlePage(page, dy)
		TweenService:Create(page, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
			GroupTransparency = 0,
		}):Play()
		bounceHome(dy)
	end

	local function goHome(page)
		if not page or not page.Visible then
			return
		end
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		TweenService:Create(page, info, {
			Position = UDim2.fromOffset(0, -CONFIG.Height * 0.62),
			GroupTransparency = 1,
		}):Play()
		bounceHome(0)

		local ref = page
		task.delay(0.3, function()
			if ref.Visible then
				ref.Visible = false
				ref.Position = UDim2.fromOffset(CONFIG.Width, 0)
				ref.GroupTransparency = 0
			end
		end)
		if ref == pages.log then
			logVisible = false
			refreshUnread()
		end
	end

	-- 底部热区：只覆盖小白条那一条，不挡 Dock 图标和页面内容
	local homeSwipe = new("Frame", {
		Name = "HomeSwipe",
		Size = UDim2.new(1, -36, 0, 34),
		Position = UDim2.fromOffset(18, CONFIG.Height - 30),
		BackgroundTransparency = 1,
		Active = true,
		ZIndex = 53,
		Parent = screen,
	})

	homeSwipe.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local page = activePage()
		if not page then
			return
		end
		homeDrag = { page = page, startY = input.Position.Y, dy = 0 }
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not homeDrag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local raw = homeDrag.startY - input.Position.Y
		homeDrag.dy = math.clamp(raw, 0, CONFIG.Height * 0.7)
		local page = homeDrag.page
		if not page.Visible then
			homeDrag = nil
			return
		end
		-- 手指往上带，页面向上走并淡出；越往上阻力越大
		page.Position = UDim2.fromOffset(0, -homeDrag.dy * 0.78)
		page.GroupTransparency = math.min(0.9, homeDrag.dy / (CONFIG.Height * 0.55))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not homeDrag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local page = homeDrag.page
		local dy = homeDrag.dy
		homeDrag = nil
		if dy >= 52 then
			goHome(page)
		else
			-- 没拉够：弹回原位，不写日志（避免拖一下就刷一条）
			settlePage(page, dy)
		end
	end)
end

--=============================================================
-- 解锁 / 上锁
--=============================================================
unlocked = false
unlocking = false

local function setLockProgress(offset, alpha)
	lockGroup.Position = UDim2.fromOffset(0, offset)
	lockGroup.GroupTransparency = alpha
end

function unlock()
	if unlocked or unlocking then
		return
	end
	unlocking = true
	unlocked = true
	gesture.Visible = false
	if hintButton then
		hintButton.Visible = false
	end

	homeGroup.Visible = true
	homeGroup.GroupTransparency = 1
	homeGroup.Position = UDim2.fromOffset(0, 26)
	homePill.BackgroundTransparency = 0.34 -- 解锁后底部才出现小白条

	islandPulse("unlock")
	marqueePause()

	local info = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(lockGroup, info, {
		Position = UDim2.fromOffset(0, -CONFIG.Height),
		GroupTransparency = 1,
	}):Play()
	local homeTween = TweenService:Create(homeGroup, info, {
		Position = UDim2.fromOffset(0, 0),
		GroupTransparency = 0,
	})
	homeTween:Play()

	task.delay(0.46, function()
		lockGroup.Visible = false
		unlocking = false
	end)
end

function lock()
	if not unlocked or unlocking then
		return
	end
	unlocking = true
	unlocked = false

	-- 上锁前把所有页面收掉，否则页面会浮在锁屏上面
	for _, page in pairs(pages) do
		if page.Visible then
			page.Visible = false
			page.Position = UDim2.fromOffset(CONFIG.Width, 0)
			page.GroupTransparency = 0
		end
	end
	if logVisible then
		logVisible = false
		refreshUnread()
	end
	homePill.BackgroundTransparency = 1

	lockGroup.Visible = true
	setLockProgress(-CONFIG.Height, 1)
	gesture.Visible = true
	if hintButton then
		hintButton.Visible = true
	end

	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(lockGroup, info, {
		Position = UDim2.fromOffset(0, 0),
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(homeGroup, info, { GroupTransparency = 1 }):Play()

	islandPulse("lock")
	if root.Visible then
		marqueeStart()
	end

	task.delay(0.44, function()
		homeGroup.Visible = false
		unlocking = false
	end)
end

-- 上滑手势捕获层（盖住锁屏内容，不拦截状态栏）
-- 解锁手势热区：只盖住底部小白条那一条，从它开始往上拖才解锁
gesture = new("Frame", {
	Name = "Gesture",
	Size = UDim2.fromOffset(140, 46),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -4),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 25,
	Parent = screen,
})

local swipeStart = 0
local swipeDelta = 0
local swiping = false

gesture.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if unlocked then
		return
	end
	swiping = true
	swipeStart = input.Position.Y
	swipeDelta = 0
end)

UserInputService.InputChanged:Connect(function(input)
	if not swiping then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	swipeDelta = math.clamp(swipeStart - input.Position.Y, 0, CONFIG.Height)
	setLockProgress(-swipeDelta * 0.8, math.min(0.75, swipeDelta / 520))
end)

UserInputService.InputEnded:Connect(function(input)
	if not swiping then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	swiping = false

	if swipeDelta >= CONFIG.UnlockThreshold then
		unlock()
	else
		-- 回弹
		TweenService:Create(lockGroup, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
			GroupTransparency = 0,
		}):Play()
	end
	swipeDelta = 0
end)

-- 点「向上滑动解锁」也能解锁（透明热区放在手势层之上）
hintButton = new("TextButton", {
	Name = "HintButton",
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.fromOffset(0, SWIPE_HINT_Y - 11),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 26,
	Parent = screen,
})
hintButton.MouseButton1Click:Connect(function()
	if not unlocked then
		unlock()
	end
end)

--=============================================================
-- 拖动窗口（状态栏区域）
--=============================================================
local pos = Vector2.new(0, 0)
local moved = false

local function viewportSize()
	if camera and camera.ViewportSize then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function clampPos(p)
	local vp = viewportSize()
	local w = CONFIG.Width * uiScale.Scale
	local h = CONFIG.Height * uiScale.Scale
	return Vector2.new(
		math.clamp(p.X, 0, math.max(0, vp.X - w)),
		math.clamp(p.Y, 0, math.max(0, vp.Y - h))
	)
end

local dragBar = new("Frame", {
	Name = "DragBar",
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 26,
	Parent = screen,
})

local dragStart = nil

dragBar.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	dragStart = { input = Vector2.new(input.Position.X, input.Position.Y), origin = pos }
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragStart then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local now = Vector2.new(input.Position.X, input.Position.Y)
	local delta = now - dragStart.input
	pos = clampPos(dragStart.origin + delta)
	moved = true
	root.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragStart = nil
	end
end)

--=============================================================
-- 关闭 / 重新唤出
--=============================================================
local closeBtn = new("TextButton", {
	Name = "Close",
	Size = UDim2.fromOffset(22, 22),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -4, 0, -26),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextSize = 13,
	TextColor3 = COLORS.White,
	ZIndex = 40,
	Parent = root,
})
corner(closeBtn, 11)
closeBtn.MouseEnter:Connect(function()
	closeBtn.BackgroundTransparency = 0.6
end)
closeBtn.MouseLeave:Connect(function()
	closeBtn.BackgroundTransparency = 0.86
end)
closeBtn.MouseButton1Click:Connect(function()
	setVisible(false)
end)

--=============================================================
-- 自适应
--=============================================================
local function fit()
	local vp = viewportSize()
	local s = math.min((vp.Y - 40) / CONFIG.Height, (vp.X - 24) / CONFIG.Width, 1)
	s = math.max(s, 0.45)
	uiScale.Scale = s

	if not moved then
		pos = Vector2.new((vp.X - CONFIG.Width * s) / 2, (vp.Y - CONFIG.Height * s) / 2)
	else
		pos = clampPos(pos)
	end
	root.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
end

fit()

if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

--=============================================================
-- 时钟 / 日期
--=============================================================
local lastMinute = -1
local lastDateKey = ""
local dateTextCache = ""
local function updateClock()
	if not root.Visible then
		return
	end
	local now = os.date("*t")
	if now.min == lastMinute then
		return
	end
	lastMinute = now.min

	local timeText = string.format("%02d:%02d", now.hour, now.min)
	clockLabel.Text = timeText
	if clockShadow then
		clockShadow.Text = timeText
	end
	if statusTime then
		statusTime.Text = timeText
	end

	-- 日期 + 农历：同一天不重复算（农历查表 + 干支推算是纯计算，没必要每分钟跑）
	local dateKey = string.format("%d-%d-%d", now.year, now.month, now.day)
	if dateKey ~= lastDateKey then
		lastDateKey = dateKey
		dateTextCache = string.format(
			"%d月%d日 %s · %s",
			now.month,
			now.day,
			WEEKDAYS[now.wday] or "",
			lunarText(now.year, now.month, now.day)
		)
	end
	dateLabel.Text = dateTextCache
end

-- 启动时先写好时间，之后只在分钟变化时改文本
updateClock()

task.spawn(function()
	while true do
		task.wait(1)
		if root.Visible then
			updateClock()
			if pages.about.Visible then
				updateAboutLive()
			end
		end
	end
end)

-- 锁屏字幕启动
marqueeStart()

--=============================================================
-- 帧数 / 延迟
--=============================================================
local frameCount = 0
local elapsed = 0
local fpsText, pingText = "", ""

-- 只在面板可见时计数；设置页/关于页不显示时只算不写，避免无谓的属性复制
RunService.Heartbeat:Connect(function(dt)
	if not root.Visible then
		return
	end

	frameCount = frameCount + 1
	elapsed = elapsed + dt

	if elapsed < 0.5 then
		return
	end

	local fps = math.floor(frameCount / elapsed + 0.5)
	frameCount = 0
	elapsed = 0

	local ping = math.floor(player:GetNetworkPing() * 1000 + 0.5)
	currentFps = fps
	currentPing = ping

	local settingsOpen = pages.settings.Visible
	if settingsOpen then
		local t = tostring(fps)
		if t ~= fpsText then
			fpsText = t
			fpsValue.Text = t
			local c = fpsColor(fps)
			if fpsValue.TextColor3 ~= c then
				fpsValue.TextColor3 = c
			end
		end

		local p = tostring(ping)
		if p ~= pingText then
			pingText = p
			pingValue.Text = p
			local c = pingColor(ping)
			if pingValue.TextColor3 ~= c then
				pingValue.TextColor3 = c
			end
		end
	end

	if pages.about.Visible then
		updateAboutLive()
	end
end)

--=============================================================
-- 快捷键
--=============================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F2 then
		setVisible(not root.Visible)
	end
end)

--=============================================================
-- 启动日志
--=============================================================
log("HAVVK Phone 已启动", "success")
log("向上滑动解锁，点图标加载脚本", "info")
refreshStatus()

task.delay(0.5, function()
	booting = false
end)

--=============================================================
-- 对外接口
--=============================================================
function API:Log(message, level)
	log(message, level)
end

function API:OpenLog()
	unlock()
	openPage(pages.log)
end

function API:SetVisible(state)
	setVisible(state)
end

function API:Lock()
	lock()
end

function API:SetBattery(level)
	setBattery(level)
end

API.OnReload = nil

_G.HAVVKPhone = API
_G.DebugUI = API
