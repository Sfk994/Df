--[[
    ============================================================
    Hush 合规观测台 (v5) · 单文件
    ============================================================
    界面沿用 DebugUI 的视觉体系：
      · 深色窗口 + 缓慢旋转的彩虹细描边
      · macOS 三色圆点（悬停浮现 × / + / −）
      · 卡片化按钮、10px 圆角、hover 提亮
      · 保留缩放：绿点循环 100% / 125% / 150%，右下角拖拽改尺寸，
        Ctrl + 滚轮 5% 微调（0.6× – 1.8×）
      · 已删除「目录」与远程脚本列表

    【为什么改成观测台】
    从 Place_100.txt（HushClient.Main）与 Lib.MoveWatch 的源码可以确认，
    这个游戏对位移相关行为有一套客户端上报 + 服务端计数的双重检测：

      Lib.MoveWatch              客户端采集，每 5s 采样一次，
                                 classify() 会把异常归类为：
                                   wall / wall_long       —— 穿墙（前方 2.2 格射线命中 Collide 部件）
                                   zbody / zbody_long     —— 卡进僵尸身体
                                   anchored               —— 被锚定还产生位移
                                   nan                    —— 速度向量 NaN
                                   touch_ghost            —— 触屏残留按下态
                                   ctrl_over              —— 无输入却高速移动
                                   state / owner          —— 平台站立 / 网络归属异常
                                 然后通过 ReplicatedStorage.HushNet["mv.stuck"]
                                 把报告发给服务器（限流：60s 内最多 4 条，fault 最多 4 条）

      Character:GetAttribute("SpeedViolations")   —— 服务端速度违规计数
      Character:GetAttribute("WallViolations")    —— 服务端穿墙违规计数
      Character:GetAttribute("Rescues")           —— 服务端“救援/纠正”次数

    也就是说：飞天 = ctrl_over + SpeedViolations；穿墙 = wall + WallViolations；
    隔空取物 = owner 异常 + 交互距离校验；取物 = 服务端距离校验。
    这些都不是“客户端能不能改”的问题，而是“服务端已经记账”。

    所以本面板默认 **只读**：
      · 只读取上述属性/模块状态，不写速度、不改 WalkSpeed、不动 CFrame
      · 唯一会“写入”的地方是游戏自己的命令总线：
        LocalPlayer:SetAttribute("HushClientCmd", "...")
        —— 这是 HushClient.Main 第 177~198 行本来就留的调试入口，
           它会执行已注册命令并把结果写回 HushClientCmdResult。
           面板只调用只读类命令（movewatch.state / zrender.* / weapon.state）
    目的：让你在尝试任何动作前后，立刻知道“服务器有没有记账”“记了多少”。

    ------------------------ v4 新增 ------------------------
    补完 Camera / HUD / RaidClient / RaidSettings / InventoryUI 五个控制器后，
    确认检测其实是 **两条独立通道**，不是一条：

      ① MoveWatch → HushNet["mv.stuck"]，只在 Place=="Raid" 且
         RaidStatus=="Alive"/"Downed" 时累加 stuck（其余时刻直接清零）。
      ② AcClient   → HushNet["ac.hb"]，每 5s 一包，内容是
         { v, fd, cd, k, x, m }：fd=焦点↔根水平距离，cd=相机↔根距离，
         k=touch/pad/kb，x=0/1 违规位，m=相机模式。
         x=1 的三种情形：fp 相机离头 >4、tp >14、iso 视线偏焦点 >4°
         或 CameraType≠Scriptable。同样要求 Place=="Raid"。
      ③ 还有一条 10Hz 的 HushNet["rv.cam"]，只在
         LocalPlayer:GetAttribute("Watched")==true（有人盯着你看）时开启，
         上传 yaw/dist/fov 与焦点相对根的三轴偏移。

    所以 v4 在「判定条」下面加了一条「心跳」：实时复刻 ② 的载荷，
    并把 ③ 的 Watched 状态直接标红。命令表（46 条只读/本地命令）
    也从这五个控制器的 command() 注册里筛出来，点一下就执行。

    ------------------------ v5 新增 ------------------------
    WeaponClient（10095 行）与 MapUI（8049 行）补进来之后，多了两处
    可直接观测的“武器侧指纹”：

      · weapon.state 末尾多出的三个字段
          wantYaw      客户端自己算出的瞄准朝向（aim override 的目标角）
          serverAimYaw Character:GetAttribute("AimYaw")，服务器认可的朝向
          shotSeq      WeaponClient.sendAndPredict 每次开火 +1 的本地序号
        于是形成两条判据：
          偏角 = |wantYaw − serverAimYaw|  > 4° → 自瞄/吸附痕迹
          RPM  = ΔshotSeq / Δt × 60        > 1200 → 连发加速痕迹
        面板把这两条做成第三条「武器」条 + 「射速校验」按钮（后台采样 3s）。

      · MapUI 的 16 条命令里，只有 mapHintSeen 这类设置会走
        menu.get / menu.op；标记、航点、关卡、任务行全在客户端内存，
        所以「地图任务」按钮是零上行读取。

    所有读取都做了 pcall / 类型判断，字段不存在时显示「—」，
    不会因为版本差异报错。
    ============================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = workspace

local LocalPlayer = Players.LocalPlayer

--=============================================================
-- 0) 配置
--=============================================================
local CONFIG = {
	Width = 404,
	Height = 792,
	MinWidth = 352,
	MinHeight = 470,
	HeaderHeight = 46,
	BottomBarHeight = 14,
	Pad = 12,
	MinimizedWidth = 196,
	MinimizedHeight = 30,
	MaxLogLines = 200,
	StatHeight = 92,
	VerdictHeight = 22,
	AcHeight = 20,
	WeaponHeight = 20,
	PrimaryHeight = 32,
	CmdHeight = 28,
	ButtonHeight = 30,
	ButtonGap = 5,
	ButtonsPerRow = 2,
}

local THEME = {
	Background = Color3.fromRGB(20, 22, 28),
	Header = Color3.fromRGB(26, 29, 36),
	Card = Color3.fromRGB(33, 37, 47),
	CardHover = Color3.fromRGB(40, 45, 56),
	CardDown = Color3.fromRGB(52, 60, 78),
	Stroke = Color3.fromRGB(42, 47, 58),
	Text = Color3.fromRGB(232, 236, 244),
	SubText = Color3.fromRGB(138, 147, 164),
	Accent = Color3.fromRGB(88, 132, 255),
	Green = Color3.fromRGB(78, 201, 132),
	Yellow = Color3.fromRGB(254, 188, 46),
	Red = Color3.fromRGB(255, 95, 87),
	Purple = Color3.fromRGB(160, 130, 255),
}

local ZOOM_STEPS = { 1.0, 1.25, 1.5 }

-- 风险模型阈值（全部来自 MoveWatch / 服务端的判定口径）
local RISK = {
	SpeedSoft = 1.15,   -- 水平速度 > WalkSpeed × 1.15 开始记分
	SpeedHard = 1.60,
	SpeedMad = 2.50,
	AirTime = 1.20,     -- 有水平输入却连续悬空超过这个秒数 → 疑似飞天
	WallRange = 2.2,    -- MoveWatch.rays 的探测距离（源码原值）
	AimDev = 4.0,       -- wantYaw 与服务器 AimYaw 的偏差（度），超过就可疑
	RpmMax = 1200,      -- 实测射速上限，超过视为连发加速
}

--=============================================================
-- 1) 基础工具
--=============================================================
local function new(class, props)
	local inst = Instance.new(class)
	if props then
		local parent = props.Parent
		for k, v in pairs(props) do
			if k ~= "Parent" then
				pcall(function()
					inst[k] = v
				end)
			end
		end
		if parent then
			inst.Parent = parent
		end
	end
	return inst
end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or THEME.Stroke
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function pad(inst, x, y)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.Parent = inst
	return p
end

-- 安全调用：模拟环境 / 老版本缺方法时不炸
local function safe(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

-- 兼容不同环境的 GUI 容器
local function guiParent()
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then
			return h
		end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local VIEW = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	or Vector2.new(1280, 720)

--=============================================================
-- 2) 窗口骨架
--=============================================================
local gui = new("ScreenGui", {
	Name = "HushGuardPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = guiParent(),
})

local window = new("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height),
	Position = UDim2.fromOffset(
		math.floor((VIEW.X - CONFIG.Width) / 2),
		math.floor((VIEW.Y - CONFIG.Height) / 2)
	),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
	Parent = gui,
})
corner(window, 12)

local uiScale = new("UIScale", { Scale = 1, Parent = window })

-- 彩虹描边（DebugUI 同款，每帧缓慢旋转）
local borderStroke = stroke(window, Color3.fromRGB(255, 255, 255), 1.4, 0.12)
local rainbow = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 99, 99)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 196, 87)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 220, 140)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(96, 178, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(160, 130, 255)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 99, 99)),
	}),
	Rotation = 0,
	Parent = borderStroke,
})

---------------------------------------------------------------
-- 标题栏
---------------------------------------------------------------
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, CONFIG.HeaderHeight),
	BackgroundColor3 = THEME.Header,
	BorderSizePixel = 0,
	Active = true,
	Parent = window,
})

local logo = new("Frame", {
	Name = "Logo",
	Size = UDim2.fromOffset(32, 32),
	Position = UDim2.fromOffset(12, 7),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Parent = header,
})
corner(logo, 9)
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
	Text = "H",
	TextSize = 15,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = logo,
})

local titleLabel = new("TextLabel", {
	Name = "Title",
	Size = UDim2.new(1, -150, 0, 16),
	Position = UDim2.fromOffset(54, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Hush 合规观测台",
	TextSize = 13,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local subtitleLabel = new("TextLabel", {
	Name = "Subtitle",
	Size = UDim2.new(1, -150, 0, 14),
	Position = UDim2.fromOffset(54, 25),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "只读 · 初始化中…",
	TextSize = 10,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = header,
})

new("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 1, -1),
	BackgroundColor3 = Color3.fromRGB(36, 40, 50),
	BorderSizePixel = 0,
	Parent = header,
})

---------------------------------------------------------------
-- 三色圆点
---------------------------------------------------------------
local dotGlyphs = {}

local function makeDot(color, offsetX, glyph)
	local btn = new("TextButton", {
		Name = "Dot",
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -offsetX, 0, 8),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = Color3.fromRGB(20, 22, 28),
		ZIndex = 5,
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

local closeDot = makeDot(THEME.Red, 10, "×")
local zoomDot = makeDot(THEME.Green, 28, "+")
local minDot = makeDot(THEME.Yellow, 46, "−")

---------------------------------------------------------------
-- 主体
---------------------------------------------------------------
local body = new("Frame", {
	Name = "Body",
	Size = UDim2.new(1, 0, 1, -CONFIG.HeaderHeight - CONFIG.BottomBarHeight),
	Position = UDim2.fromOffset(0, CONFIG.HeaderHeight),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = window,
})

local inner = new("Frame", {
	Name = "Inner",
	Size = UDim2.new(1, -CONFIG.Pad * 2, 1, -CONFIG.Pad * 2),
	Position = UDim2.fromOffset(CONFIG.Pad, CONFIG.Pad),
	BackgroundTransparency = 1,
	Parent = body,
})

--=============================================================
-- 3) 状态矩阵：4 列 × 2 行
--=============================================================
local statBar = new("Frame", {
	Name = "Stats",
	Size = UDim2.new(1, 0, 0, CONFIG.StatHeight),
	BackgroundColor3 = THEME.Card,
	BorderSizePixel = 0,
	Parent = inner,
})
corner(statBar, 10)
stroke(statBar, THEME.Stroke, 1, 0.15)

local statValues = {}
local statCells = {}

local function makeStat(index, label, defaultText, color)
	local row = math.floor((index - 1) / 4)      -- 0 / 1
	local col = (index - 1) % 4                  -- 0..3
	local cellW = 1 / 4
	local cellH = 0.5

	local cell = new("Frame", {
		Size = UDim2.new(cellW, 0, cellH, 0),
		Position = UDim2.fromScale(col * cellW, row * cellH),
		BackgroundTransparency = 1,
		Parent = statBar,
	})

	if col > 0 then
		new("Frame", {
			Size = UDim2.new(0, 1, 1, -14),
			Position = UDim2.new(0, 0, 0, 7),
			BackgroundColor3 = Color3.fromRGB(44, 49, 60),
			BorderSizePixel = 0,
			Parent = cell,
		})
	end
	if row > 0 then
		new("Frame", {
			Size = UDim2.new(1, -12, 0, 1),
			Position = UDim2.new(0, 6, 0, 0),
			BackgroundColor3 = Color3.fromRGB(44, 49, 60),
			BorderSizePixel = 0,
			Parent = cell,
		})
	end

	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 11),
		Position = UDim2.fromOffset(0, 7),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = label,
		TextSize = 9,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = cell,
	})

	local value = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 15),
		Position = UDim2.fromOffset(0, 19),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = defaultText,
		TextSize = 13,
		TextColor3 = color or THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = cell,
	})

	statValues[label] = value
	statCells[label] = cell
	return value
end

makeStat(1, "速违", "0", THEME.Text)
makeStat(2, "墙违", "0", THEME.Text)
makeStat(3, "风险", "—", THEME.Green)
makeStat(4, "速比", "—", THEME.Text)
makeStat(5, "FPS", "—")
makeStat(6, "延迟", "—")
makeStat(7, "僵尸", "—", THEME.Green)
makeStat(8, "余量", "—", THEME.Text)

---------------------------------------------------------------
-- 判定条：本帧如果被 MoveWatch 采样，它会给什么结论
---------------------------------------------------------------
local verdictBar = new("Frame", {
	Name = "Verdict",
	Size = UDim2.new(1, 0, 0, CONFIG.VerdictHeight),
	Position = UDim2.fromOffset(0, CONFIG.StatHeight + 8),
	BackgroundColor3 = Color3.fromRGB(26, 29, 37),
	BorderSizePixel = 0,
	Parent = inner,
})
corner(verdictBar, 8)
stroke(verdictBar, THEME.Stroke, 1, 0.25)

local verdictTag = new("TextLabel", {
	Name = "Tag",
	Size = UDim2.fromOffset(34, CONFIG.VerdictHeight),
	Position = UDim2.fromOffset(9, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "判定",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = verdictBar,
})

local verdictText = new("TextLabel", {
	Name = "Text",
	Size = UDim2.new(1, -52, 1, 0),
	Position = UDim2.fromOffset(44, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	Text = "等待角色…",
	TextSize = 9.5,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = verdictBar,
})

---------------------------------------------------------------
-- 心跳条：本帧如果被 AcClient 采样，它会外发什么（ac.hb / rv.cam）
---------------------------------------------------------------
local acBarY = CONFIG.StatHeight + 8 + CONFIG.VerdictHeight + 4

local acBar = new("Frame", {
	Name = "ACHeat",
	Size = UDim2.new(1, 0, 0, CONFIG.AcHeight),
	Position = UDim2.fromOffset(0, acBarY),
	BackgroundColor3 = Color3.fromRGB(26, 29, 37),
	BorderSizePixel = 0,
	Parent = inner,
})
corner(acBar, 8)
stroke(acBar, THEME.Stroke, 1, 0.25)

local acTag = new("TextLabel", {
	Name = "Tag",
	Size = UDim2.fromOffset(34, CONFIG.AcHeight),
	Position = UDim2.fromOffset(9, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "心跳",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = acBar,
})

local acText = new("TextLabel", {
	Name = "Text",
	Size = UDim2.new(1, -104, 1, 0),
	Position = UDim2.fromOffset(44, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	Text = "等待角色…",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = acBar,
})

local acGate = new("TextLabel", {
	Name = "Gate",
	Size = UDim2.fromOffset(54, CONFIG.AcHeight),
	Position = UDim2.new(1, -58, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "—",
	TextSize = 8.5,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = acBar,
})

---------------------------------------------------------------
-- 武器条：弹出 / 装填 / 瞄准偏差 / 实测射速（weapon.state 复刻）
---------------------------------------------------------------
local wpnBarY = acBarY + CONFIG.AcHeight + 4

local wpnBar = new("Frame", {
	Name = "WeaponBar",
	Size = UDim2.new(1, 0, 0, CONFIG.WeaponHeight),
	Position = UDim2.fromOffset(0, wpnBarY),
	BackgroundColor3 = Color3.fromRGB(26, 29, 37),
	BorderSizePixel = 0,
	Parent = inner,
})
corner(wpnBar, 8)
stroke(wpnBar, THEME.Stroke, 1, 0.25)

local wpnTag = new("TextLabel", {
	Name = "Tag",
	Size = UDim2.fromOffset(34, CONFIG.WeaponHeight),
	Position = UDim2.fromOffset(9, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "武器",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = wpnBar,
})

local wpnText = new("TextLabel", {
	Name = "Text",
	Size = UDim2.new(1, -104, 1, 0),
	Position = UDim2.fromOffset(44, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	Text = "等待武器…",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = wpnBar,
})

local wpnGate = new("TextLabel", {
	Name = "Gate",
	Size = UDim2.fromOffset(54, CONFIG.WeaponHeight),
	Position = UDim2.new(1, -58, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "—",
	TextSize = 8.5,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = wpnBar,
})

---------------------------------------------------------------
-- 一键巡检
---------------------------------------------------------------
local primaryBtn = new("TextButton", {
	Name = "Primary",
	Size = UDim2.new(1, 0, 0, CONFIG.PrimaryHeight),
	Position = UDim2.fromOffset(0, wpnBarY + CONFIG.WeaponHeight + 6),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "全量巡检（读数 + 探针 + 命令）",
	TextSize = 11,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = inner,
})
corner(primaryBtn, 9)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 140, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(132, 106, 255)),
	}),
	Rotation = 20,
	Parent = primaryBtn,
})

---------------------------------------------------------------
-- 命令行（走游戏自己的 HushClientCmd 属性总线）
---------------------------------------------------------------
local cmdY = wpnBarY + CONFIG.WeaponHeight + 6 + CONFIG.PrimaryHeight + 6

local cmdBox = new("Frame", {
	Name = "CmdRow",
	Size = UDim2.new(1, 0, 0, CONFIG.CmdHeight),
	Position = UDim2.fromOffset(0, cmdY),
	BackgroundColor3 = Color3.fromRGB(26, 29, 37),
	BorderSizePixel = 0,
	Parent = inner,
})
corner(cmdBox, 8)
stroke(cmdBox, THEME.Stroke, 1, 0.25)

new("TextLabel", {
	Size = UDim2.fromOffset(24, CONFIG.CmdHeight),
	Position = UDim2.fromOffset(8, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = ">",
	TextSize = 12,
	TextColor3 = THEME.Green,
	Parent = cmdBox,
})

local cmdInput = new("TextBox", {
	Name = "CmdInput",
	Size = UDim2.new(1, -96, 1, 0),
	Position = UDim2.fromOffset(26, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	PlaceholderText = "movewatch.state / zrender.eyes / weapon.state",
	PlaceholderColor3 = Color3.fromRGB(96, 104, 120),
	Text = "",
	TextSize = 10,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Parent = cmdBox,
})

local cmdRunBtn = new("TextButton", {
	Name = "CmdRun",
	Size = UDim2.fromOffset(58, CONFIG.CmdHeight - 8),
	Position = UDim2.new(1, -66, 0, 4),
	BackgroundColor3 = Color3.fromRGB(46, 52, 66),
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "执行",
	TextSize = 10,
	TextColor3 = THEME.Text,
	Parent = cmdBox,
})
corner(cmdRunBtn, 6)

---------------------------------------------------------------
-- 功能按钮区（替代原目录）
---------------------------------------------------------------
local funcLabelY = cmdY + CONFIG.CmdHeight + 9

local funcLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.fromOffset(2, funcLabelY),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "检测 / 观测",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = inner,
})

local ROWS = 9
local gridY = funcLabelY + 13

local btnArea = new("Frame", {
	Name = "Actions",
	Size = UDim2.new(1, 0, 0, ROWS * CONFIG.ButtonHeight + (ROWS - 1) * CONFIG.ButtonGap),
	Position = UDim2.fromOffset(0, gridY),
	BackgroundTransparency = 1,
	Parent = inner,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, CONFIG.ButtonGap),
	Parent = btnArea,
})

---------------------------------------------------------------
-- 日志区
---------------------------------------------------------------
local logLabelY = gridY + ROWS * CONFIG.ButtonHeight + (ROWS - 1) * CONFIG.ButtonGap + 8

local logLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.fromOffset(2, logLabelY),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "输出",
	TextSize = 9,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = inner,
})

local logPanel = new("Frame", {
	Name = "LogPanel",
	Size = UDim2.new(1, 0, 0, 80),
	Position = UDim2.fromOffset(0, logLabelY + 15),
	BackgroundColor3 = Color3.fromRGB(26, 29, 37),
	BorderSizePixel = 0,
	Parent = inner,
})
corner(logPanel, 10)
stroke(logPanel, THEME.Stroke, 1, 0.3)

local logScroll = new("ScrollingFrame", {
	Name = "Log",
	Size = UDim2.new(1, -14, 1, -12),
	Position = UDim2.fromOffset(8, 6),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
	ScrollBarImageTransparency = 0.4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = logPanel,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
	Parent = logScroll,
})

---------------------------------------------------------------
-- 底部拖动条
---------------------------------------------------------------
local bottomBar = new("Frame", {
	Name = "BottomBar",
	Size = UDim2.new(1, 0, 0, CONFIG.BottomBarHeight),
	Position = UDim2.new(0, 0, 1, -CONFIG.BottomBarHeight),
	BackgroundColor3 = Color3.fromRGB(25, 28, 35),
	BorderSizePixel = 0,
	Active = true,
	Parent = window,
})
local barKnob = new("Frame", {
	Name = "BarKnob",
	Size = UDim2.fromOffset(34, 3),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
	Parent = bottomBar,
})
corner(barKnob, 2)

---------------------------------------------------------------
-- 最小化胶囊
---------------------------------------------------------------
local minimizedDot = new("Frame", {
	Name = "MinDot",
	Size = UDim2.fromOffset(7, 7),
	Position = UDim2.fromOffset(14, 11),
	BackgroundColor3 = THEME.Green,
	BorderSizePixel = 0,
	Visible = false,
	Parent = window,
})
corner(minimizedDot, 4)

local minimizedLabel = new("TextLabel", {
	Name = "MinLabel",
	Size = UDim2.new(1, -92, 1, 0),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Hush 合规观测台",
	TextSize = 11,
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Visible = false,
	Parent = window,
})

local minimizedBadge = new("TextLabel", {
	Name = "MinBadge",
	Size = UDim2.fromOffset(52, 16),
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	BackgroundColor3 = THEME.Card,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "—",
	TextSize = 9,
	TextColor3 = THEME.Green,
	Visible = false,
	Parent = window,
})
corner(minimizedBadge, 5)

--=============================================================
-- 4) 日志
--=============================================================
local LEVEL_COLOR = {
	info = "9aa5b8",
	ok = "4ec984",
	warn = "febc2e",
	err = "ff5f57",
	risk = "ff9f43",
}

local logLines = {}
local plainLog = {}

local function esc(s)
	s = tostring(s)
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

local function pushLog(msg, level)
	level = level or "info"
	local color = LEVEL_COLOR[level] or LEVEL_COLOR.info
	local time = os.date("%H:%M:%S")
	local text = string.format(
		'<font color="#5d6577">%s</font> <font color="#%s">%s</font>',
		time, color, esc(msg)
	)

	local lbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		RichText = true,
		Text = text,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = logScroll,
	})
	lbl.LayoutOrder = #logLines + 1

	table.insert(logLines, lbl)
	table.insert(plainLog, string.format("[%s] %s", time, tostring(msg)))

	while #logLines > CONFIG.MaxLogLines do
		local old = table.remove(logLines, 1)
		if old then
			old:Destroy()
		end
		table.remove(plainLog, 1)
	end
	for i, line in ipairs(logLines) do
		line.LayoutOrder = i
	end

	task.defer(function()
		pcall(function()
			logScroll.CanvasPosition = Vector2.new(0, 999999)
		end)
	end)
end

--=============================================================
-- 5) 基础数据读取
--=============================================================
local function firstPartOf(model)
	if not model then
		return nil
	end
	local function isBasePart(inst)
		if not inst then
			return false
		end
		local ok, v = pcall(function()
			return inst:IsA("BasePart")
		end)
		return ok and v == true
	end

	local primary = safe(function()
		return model.PrimaryPart
	end)
	if isBasePart(primary) then
		return primary
	end
	local ok, list = pcall(function()
		return model:GetChildren()
	end)
	if not ok then
		return nil
	end
	for _, c in ipairs(list) do
		if isBasePart(c) then
			return c
		end
	end
	return nil
end

local function modelPosition(model)
	local p = firstPartOf(model)
	if not p then
		return nil
	end
	return p.Position
end

local function rootPosition()
	local char = LocalPlayer.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.Position
	end
	return nil
end

local function refPosition()
	local rp = rootPosition()
	if rp then
		return rp
	end
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	return Vector3.new(0, 0, 0)
end

local ZOMBIE_KINDS = {
	walker = true, walker_2 = true, walker_3 = true, walker_4 = true,
	walker_5 = true, walker_6 = true, runner = true, crawler = true,
	brute = true, listener = true, hazmat = true, ringer = true, riot = true,
}

local function isPlayerModel(model)
	if not Players.GetPlayerFromCharacter then
		return false
	end
	local ok, p = pcall(function()
		return Players:GetPlayerFromCharacter(model)
	end)
	return ok and p ~= nil
end

local function kindOf(model)
	local attr = safe(function()
		return model:GetAttribute("Kind") or model:GetAttribute("Type") or model:GetAttribute("ZKind")
	end)
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	local n = string.lower(model.Name)
	local base = string.match(n, "^([%a_]+)")
	if base and ZOMBIE_KINDS[base] then
		return base
	end
	return n
end

local zombieCache = { at = 0, list = {} }

local function collectZombies(force)
	local now = os.clock()
	if not force and now - zombieCache.at < 0.25 then
		return zombieCache.list
	end

	local list = {}
	local hushLocal = workspace:FindFirstChild("HushLocal")
	local folder = hushLocal and hushLocal:FindFirstChild("Zombies")

	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end

	-- 兜底：直接扫工作区里的僵尸模型（HushLocal 还没建好时）
	if #list == 0 then
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and not isPlayerModel(m) then
				local n = string.lower(m.Name)
				local base = string.match(n, "^([%a_]+)")
				if base and ZOMBIE_KINDS[base] and firstPartOf(m) then
					table.insert(list, m)
				end
			end
		end
	end

	zombieCache.at = now
	zombieCache.list = list
	return list
end

local function attrOf(inst, name)
	if not inst then
		return nil
	end
	local ok, v = pcall(function()
		return inst:GetAttribute(name)
	end)
	if not ok then
		return nil
	end
	local t = type(v)
	if t == "string" or t == "number" or t == "boolean" then
		return v
	end
	return nil
end

local function numAttr(inst, name, default)
	local v = attrOf(inst, name)
	if type(v) == "number" then
		return v
	end
	return default
end

-- 速度：不同版本字段名不同，逐个兜底并把结果规整成 {X,Y,Z}
local function velocityOf(part)
	if not part then
		return { X = 0, Y = 0, Z = 0 }
	end
	local candidates = { "AssemblyLinearVelocity", "Velocity" }
	for _, key in ipairs(candidates) do
		local v = safe(function()
			return part[key]
		end)
		if type(v) == "table" and type(v.X) == "number" then
			return v
		end
	end
	return { X = 0, Y = 0, Z = 0 }
end

local function classNameOf(inst)
	if not inst then
		return "?"
	end
	local v = safe(function()
		return inst.ClassName
	end)
	if type(v) == "string" then
		return v
	end
	return "?"
end

local function fmt(v, default)
	if v == nil then
		return default or "—"
	end
	if type(v) == "boolean" then
		return v and "是" or "否"
	end
	if type(v) == "number" then
		if v ~= v then
			return "NaN"
		end
		if math.abs(v - math.floor(v + 0.5)) < 0.001 then
			return string.format("%d", math.floor(v + 0.5))
		end
		return string.format("%.1f", v)
	end
	return tostring(v)
end

local function sign(n)
	if n > 0 then
		return "+" .. fmt(n)
	end
	return fmt(n)
end

local function nearestZombie()
	local ref = refPosition()
	local best, bestD = nil, math.huge
	for _, m in ipairs(collectZombies(true)) do
		local p = modelPosition(m)
		if p then
			local d = (p - ref).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best, bestD, ref
end

--=============================================================
-- 6) 僵尸透视（纯客户端渲染，不产生任何服务端交互）
--=============================================================
local espOn = false
local espPlayers = false
local espGuis = {}
local playerGuis = {}

local function destroyEsp()
	for model, bb in pairs(espGuis) do
		pcall(function()
			bb:Destroy()
		end)
		espGuis[model] = nil
	end
	for pl, bb in pairs(playerGuis) do
		pcall(function()
			bb:Destroy()
		end)
		playerGuis[pl] = nil
	end
end

local function espColor(d)
	if d <= 25 then
		return THEME.Red
	elseif d <= 60 then
		return THEME.Yellow
	end
	return THEME.Green
end

local function updateEsp()
	if not espOn then
		return
	end

	local ref = refPosition()
	local seen = {}

	for _, model in ipairs(collectZombies()) do
		local part = firstPartOf(model)
		if part then
			local pos = part.Position
			local d = (pos - ref).Magnitude
			seen[model] = true

			local bb = espGuis[model]
			if not bb or not bb.Parent then
				local adornee = model:FindFirstChild("HumanoidRootPart") or part
				bb = new("BillboardGui", {
					Name = "HushZombieEsp",
					Adornee = adornee,
					Size = UDim2.fromOffset(96, 22),
					StudsOffset = Vector3.new(0, 2.6, 0),
					AlwaysOnTop = true,
					LightInfluence = 0,
					MaxDistance = 800,
					Parent = adornee,
				})

				new("TextLabel", {
					Size = UDim2.new(1, 0, 0, 13),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = "",
					TextSize = 11,
					TextColor3 = THEME.Green,
					TextStrokeTransparency = 0.2,
					TextStrokeColor3 = Color3.new(0, 0, 0),
					Parent = bb,
				})

				new("TextLabel", {
					Size = UDim2.new(1, 0, 0, 10),
					Position = UDim2.fromOffset(0, 12),
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = "",
					TextSize = 9,
					TextColor3 = Color3.fromRGB(220, 226, 236),
					TextStrokeTransparency = 0.35,
					TextStrokeColor3 = Color3.new(0, 0, 0),
					Parent = bb,
				})

				espGuis[model] = bb
			end

			local kids = bb:GetChildren()
			local nameLbl, distLbl
			for _, c in ipairs(kids) do
				if c:IsA("TextLabel") then
					local posProp = safe(function()
						return c.Position
					end)
					local yOff = 0
					if type(posProp) == "table" and type(posProp.Y) == "table" then
						yOff = tonumber(posProp.Y.Offset) or 0
					end
					if yOff > 6 then
						distLbl = c
					else
						nameLbl = c
					end
				end
			end
			if nameLbl then
				nameLbl.Text = tostring(kindOf(model))
				nameLbl.TextColor3 = espColor(d)
			end
			if distLbl then
				local dy = math.floor(ref.Y - pos.Y)
				distLbl.Text = string.format("%dm  %s%d", math.floor(d), dy >= 0 and "↓" or "↑", math.abs(dy))
			end
		end
	end

	for model, bb in pairs(espGuis) do
		if not seen[model] then
			pcall(function()
				bb:Destroy()
			end)
			espGuis[model] = nil
		end
	end

	-- 玩家标记：同队=绿，其他=红
	local seenPl = {}
	if espPlayers then
		local mySquad = attrOf(LocalPlayer, "SquadId")
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= LocalPlayer then
				local ch = pl.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp then
					seenPl[pl] = true
					local d = (hrp.Position - ref).Magnitude
					local mate = mySquad ~= nil and attrOf(pl, "SquadId") == mySquad
					local color = mate and THEME.Green or THEME.Red

					local bb = playerGuis[pl]
					if not bb or not bb.Parent then
						bb = new("BillboardGui", {
							Name = "HushPlayerEsp",
							Adornee = hrp,
							Size = UDim2.fromOffset(110, 20),
							StudsOffset = Vector3.new(0, 2.9, 0),
							AlwaysOnTop = true,
							LightInfluence = 0,
							MaxDistance = 900,
							Parent = hrp,
						})
						new("TextLabel", {
							Name = "Name",
							Size = UDim2.new(1, 0, 0, 12),
							BackgroundTransparency = 1,
							Font = Enum.Font.GothamBold,
							Text = "",
							TextSize = 10,
							TextColor3 = color,
							TextStrokeTransparency = 0.25,
							TextStrokeColor3 = Color3.new(0, 0, 0),
							Parent = bb,
						})
						new("TextLabel", {
							Name = "Info",
							Size = UDim2.new(1, 0, 0, 9),
							Position = UDim2.fromOffset(0, 11),
							BackgroundTransparency = 1,
							Font = Enum.Font.Gotham,
							Text = "",
							TextSize = 8,
							TextColor3 = Color3.fromRGB(224, 230, 240),
							TextStrokeTransparency = 0.4,
							TextStrokeColor3 = Color3.new(0, 0, 0),
							Parent = bb,
						})
						playerGuis[pl] = bb
					end

					local nl = bb:FindFirstChild("Name")
					local il = bb:FindFirstChild("Info")
					if nl then
						nl.TextColor3 = color
						nl.Text = (mate and "◆ " or "▲ ") .. pl.Name
					end
					if il then
						local downed = attrOf(pl, "Downed") == true
						il.Text = string.format(
							"%d格%s%s", math.floor(d),
							mate and " 队友" or "",
							downed and " 倒地" or ""
						)
					end
				end
			end
		end
	end

	for pl, bb in pairs(playerGuis) do
		if not seenPl[pl] then
			pcall(function()
				bb:Destroy()
			end)
			playerGuis[pl] = nil
		end
	end
end

--=============================================================
-- 7) 风控数据层
--    1) 服务端违规计数   2) MoveWatch 内部状态
--    3) 命令总线         4) 射线/重叠探针   5) 风险评分
--=============================================================

---------------------------------------------------------------
-- 7.1 服务端违规计数
---------------------------------------------------------------
local violBoot = nil       -- 首次读数（基线）
local violSeen = { speed = nil, wall = nil, rescue = nil }
local violLast = { speed = 0, wall = 0, rescue = 0, src = "—" }

local function readViolations()
	local out = { speed = nil, wall = nil, rescue = nil, src = "—", found = false }

	local function tryFrom(inst, tag)
		if not inst then
			return false
		end
		local s = attrOf(inst, "SpeedViolations")
		local w = attrOf(inst, "WallViolations")
		local r = attrOf(inst, "Rescues")
		if s == nil and w == nil and r == nil then
			return false
		end
		out.speed = tonumber(s) or 0
		out.wall = tonumber(w) or 0
		out.rescue = tonumber(r) or 0
		out.src = tag
		out.found = true
		return true
	end

	if tryFrom(LocalPlayer.Character, "角色") then
		return out
	end
	if tryFrom(LocalPlayer, "玩家") then
		return out
	end
	return out
end

-- 每 0.5s 调一次；发现增长立即告警
local function violTick()
	local v = readViolations()
	if not v.found then
		return v
	end

	if violBoot == nil then
		violBoot = { speed = v.speed, wall = v.wall, rescue = v.rescue }
		violSeen.speed, violSeen.wall, violSeen.rescue = v.speed, v.wall, v.rescue
	end

	if violSeen.speed ~= nil and v.speed > violSeen.speed then
		pushLog(string.format("⚠ 速度违规 +%d（累计 %d）—— 服务端已记账", v.speed - violSeen.speed, v.speed), "err")
	end
	if violSeen.wall ~= nil and v.wall > violSeen.wall then
		pushLog(string.format("⚠ 穿墙违规 +%d（累计 %d）—— 服务端已记账", v.wall - violSeen.wall, v.wall), "err")
	end
	if violSeen.rescue ~= nil and v.rescue > violSeen.rescue then
		pushLog(string.format("服务端纠正 +%d（累计 %d）", v.rescue - violSeen.rescue, v.rescue), "warn")
	end

	violSeen.speed, violSeen.wall, violSeen.rescue = v.speed, v.wall, v.rescue
	violLast = v
	return v
end

local function violDelta()
	if not violBoot then
		return 0, 0, 0
	end
	local v = readViolations()
	if not v.found then
		return 0, 0, 0
	end
	return v.speed - violBoot.speed, v.wall - violBoot.wall, v.rescue - violBoot.rescue
end

---------------------------------------------------------------
-- 7.2 MoveWatch 内部状态
---------------------------------------------------------------
local mwCache = { checked = false, module = nil, path = "未找到", live = false, why = "", at = 0 }

local function hushClientRoot()
	local ps = safe(function()
		return LocalPlayer:WaitForChild("PlayerScripts", 2)
	end)
	if not ps then
		return nil
	end
	return ps:FindFirstChild("HushClient")
end

local function probeMoveWatch(force)
	-- 首次失败后每 8s 重试一次，避免客户端比面板晚加载导致永久读不到
	if mwCache.checked and not force then
		if mwCache.module or (os.clock() - mwCache.at) < 8 then
			return mwCache
		end
	end
	mwCache.checked = true
	mwCache.at = os.clock()
	mwCache.module = nil
	mwCache.live = false

	local root = hushClientRoot()
	if not root then
		mwCache.path = "HushClient 不存在"
		mwCache.why = "客户端脚本未注入或已被改名"
		return mwCache
	end

	local lib = root:FindFirstChild("Lib")
	local mod = lib and lib:FindFirstChild("MoveWatch")
	if not mod then
		mwCache.path = "HushClient.Lib.MoveWatch 不存在"
		mwCache.why = "该版本没有 MoveWatch 模块"
		return mwCache
	end

	mwCache.path = "HushClient.Lib.MoveWatch"
	local ok, res = pcall(require, mod)
	if not ok or type(res) ~= "table" then
		mwCache.why = "require 失败: " .. tostring(res)
		return mwCache
	end

	mwCache.module = res
	local st = res._state
	if type(st) == "table" then
		local reports = tonumber(st.reports) or 0
		local lastLine = tostring(st.last or "")
		local attrLine = tostring(attrOf(LocalPlayer, "MoveWatch") or "")
		if reports > 0 then
			mwCache.live = true
			mwCache.why = string.format("实时实例（已采样 %d 次）", reports)
		elseif attrLine ~= "" and lastLine ~= "" and attrLine:find(lastLine:sub(1, 18), 1, true) then
			mwCache.live = true
			mwCache.why = "实时实例（与 MoveWatch 属性一致）"
		else
			mwCache.why = "镜像副本（require 拿到的是新实例，计数仅供参考）"
		end
	else
		mwCache.why = "模块无 _state 字段"
	end
	return mwCache
end

---------------------------------------------------------------
-- 7.3 命令总线（HushClient.Main 自带的调试入口）
---------------------------------------------------------------
local CMD_TIMEOUT = 1.8

local function runCommand(line)
	if type(line) ~= "string" then
		return false, "命令为空"
	end
	line = line:gsub("^%s+", ""):gsub("%s+$", "")
	if line == "" then
		return false, "命令为空"
	end

	local canWrite = safe(function()
		LocalPlayer:SetAttribute("HushClientCmdResult", "")
		return true
	end)
	if not canWrite then
		return false, "无法写入属性（客户端未加载 / 环境受限）"
	end

	local ok = safe(function()
		LocalPlayer:SetAttribute("HushClientCmd", line)
		return true
	end)
	if not ok then
		return false, "写入 HushClientCmd 失败"
	end

	local t0 = os.clock()
	while os.clock() - t0 < CMD_TIMEOUT do
		local res = attrOf(LocalPlayer, "HushClientCmdResult")
		if type(res) == "string" and res ~= "" then
			return true, res
		end
		task.wait(0.05)
	end
	return false, "无响应（命令未注册 / 客户端未 boot）"
end

---------------------------------------------------------------
-- 7.3b 命令表
--      全部来自 HushClient 各 controller 的 command(...) 注册，
--      从已解包的 47 个 Controllers + 461 个 Lib 模块里筛出「只读」项。
--      tag: "r" 只读 / "w" 客户端写入（只动 UI 或相机，不发远程）
---------------------------------------------------------------
local COMMAND_GROUPS = {
	{
		name = "判定 / 风控",
		items = {
			{ "movewatch.state", "计数器", "r" },
			{ "movewatch.look", "立刻采样一次", "r" },
			{ "zblock.stats", "穿墙判定统计", "r" },
			{ "tc.state", "触摸控制器状态", "r" },
			{ "input.state", "输入状态", "r" },
		},
	},
	{
		name = "相机",
		items = {
			{ "camera.info", "模式/朝向/距离/FOV", "r" },
			{ "fptp.state", "第一/第三人称", "r" },
			{ "camera.zoom 3", "切到第 3 档", "w" },
			{ "camera.rotate 1", "转 90°", "w" },
		},
	},
	{
		name = "战局",
		items = {
			{ "raidclient.status", "撤离点/事件计数", "r" },
			{ "endcine.status", "结算镜头", "r" },
			{ "hud.state", "HUD 挂载状态", "r" },
			{ "events.state", "事件面板", "r" },
			{ "events.summary", "事件摘要", "r" },
			{ "wave.state", "波次状态", "r" },
			{ "raidsettings.state", "对局设置", "r" },
			{ "comms.state", "语音/无线电", "r" },
			{ "vault.state", "金库", "r" },
			{ "map.state", "地图", "r" },
		},
	},
	{
		name = "渲染 / 视觉",
		items = {
			{ "zrender.stats", "僵尸渲染池", "r" },
			{ "zrender.eyes", "视线统计", "r" },
			{ "zrender.fpcheck", "首次渲染检查", "r" },
			{ "playeroutline.state", "玩家描边", "r" },
			{ "squadmarkers.state", "队友标记", "r" },
			{ "vision.info", "视锥/遮挡配置", "r" },
			{ "nvg.state", "夜视", "r" },
			{ "skins.state", "皮肤", "r" },
		},
	},
	{
		name = "物品 / 武器",
		items = {
			{ "weapon.state", "状态机（含瞄准/射序）", "r" },
			{ "weapon.switchstate", "切枪状态", "r" },
			{ "weapon.fprange", "第一人称射程检查", "r" },
			{ "weapon.aimpick", "瞄准拾取", "r" },
			{ "invui.dump", "背包快照", "r" },
			{ "hud.tally", "统计条", "r" },
			{ "crates.state", "箱子", "r" },
			{ "sell.totals", "出售汇总", "r" },
		},
	},
	{
		name = "地图 / 任务",
		items = {
			{ "map.state", "开关/场景/标记数", "r" },
			{ "map.level", "关卡与构建统计", "r" },
			{ "map.tasks", "任务列表", "r" },
			{ "map.wp", "航点统计", "r" },
			{ "map.cursor", "光标状态", "r" },
			{ "map.key", "图例标签", "r" },
			{ "map.zoom in", "地图放大", "w" },
			{ "map.zoom out", "地图缩小", "w" },
			{ "map.zoom reset", "回到默认缩放", "w" },
			{ "map.open", "打开地图", "w" },
			{ "map.close", "关闭地图", "w" },
		},
	},
	{
		name = "环境 / 调试",
		items = {
			{ "coregui.state", "CoreGui 屏蔽", "r" },
			{ "ui.viewport", "视口/安全区", "r" },
			{ "pad.state", "手柄", "r" },
			{ "keys.state", "按键绑定", "r" },
			{ "perfhud.state", "性能 HUD", "r" },
			{ "atmo.stats", "大气/光照", "r" },
			{ "audio.stats", "音频", "r" },
			{ "huntclient.status", "猎杀模式", "r" },
		},
	},
	{
		name = "动作（仅客户端）",
		items = {
			{ "raidclient.reveal", "6 秒内高亮撤离点", "w" },
			{ "hud.extracts", "HUD 提示撤离点", "w" },
			{ "camera.mode iso", "回到俯视", "w" },
			{ "raidsettings.open", "打开对局设置", "w" },
			{ "raidsettings.close", "关闭对局设置", "w" },
		},
	},
}

-- 扁平化，给 cmdHelp / 失败提示用
local KNOWN_CMD = {}
for _, g in ipairs(COMMAND_GROUPS) do
	for _, it in ipairs(g.items) do
		table.insert(KNOWN_CMD, { it[1], it[2] })
	end
end

---------------------------------------------------------------
-- 7.4 探针
---------------------------------------------------------------
local function rayParamsFor(char)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = { char }
	local hl = workspace:FindFirstChild("HushLocal")
	if hl then
		table.insert(list, hl)
	end
	rp.FilterDescendantsInstances = list
	return rp
end

-- 完全复刻 MoveWatch.rays：从腰部和根部各打一条 2.2 格的水平射线
local function wallProbe(dirX, dirZ)
	local char = LocalPlayer.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end

	local dir = Vector3.new(dirX, 0, dirZ)
	if dir.Magnitude < 0.05 then
		return nil
	end

	local rp = rayParamsFor(char)
	local hip = tonumber(safe(function()
		return hum.HipHeight
	end)) or 2
	local start = hrp.Position - Vector3.new(0, math.max(0, hip + hrp.Size.Y / 2 - 0.7), 0)

	for _, origin in ipairs({ hrp.Position, start }) do
		local hit = safe(function()
			return workspace:Raycast(origin, dir.Unit * RISK.WallRange, rp)
		end)
		if hit and hit.Instance and hit.Instance.CanCollide then
			return hit.Instance.Name, (hit.Position - origin).Magnitude
		end
	end
	return nil
end

local function overlapProbe(maxParts)
	local char = LocalPlayer.Character
	if not char then
		return 0, {}
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 0, {}
	end

	local ok, list = pcall(function()
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { char }
		local hl = workspace:FindFirstChild("HushLocal")
		if hl then
			table.insert(filter, hl)
		end
		op.FilterDescendantsInstances = filter
		op.RespectCanCollide = true
		op.MaxParts = maxParts or 6
		return workspace:GetPartsInPart(hrp, op)
	end)

	if not ok or type(list) ~= "table" then
		return 0, {}
	end
	local names = {}
	for i, p in ipairs(list) do
		if i > 3 then
			break
		end
		table.insert(names, string.sub(tostring(p.Name), 1, 16))
	end
	return #list, names
end

---------------------------------------------------------------
-- 7.5 运动快照 + 风险评分
---------------------------------------------------------------
local airTime = 0

local function motion()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end

	local vel = velocityOf(hrp)
	local hs = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	local vs = tonumber(vel.Y) or 0
	local ws = tonumber(safe(function()
		return hum.WalkSpeed
	end)) or 0
	local md = safe(function()
		return hum.MoveDirection
	end)
	local mdLen = (type(md) == "table" and type(md.Magnitude) == "number") and md.Magnitude or 0
	local floorMat = tostring(safe(function()
		return hum.FloorMaterial.Name
	end) or "?")
	local stateName = tostring(safe(function()
		return hum:GetState().Name
	end) or "?")

	local owner = "未知"
	if hrp.Anchored then
		owner = "anchored"
	elseif hrp.GetNetworkOwner then
		local ok, o = pcall(function()
			return hrp:GetNetworkOwner()
		end)
		if ok then
			owner = (o == nil) and "server" or (o == LocalPlayer and "me" or "other")
		end
	end

	return {
		char = char, hrp = hrp, hum = hum,
		speed = hs, vy = vs, ws = ws,
		vx = vel.X, vz = vel.Z,
		ratio = (ws > 0) and (hs / ws) or 0,
		md = mdLen,
		onGround = (floorMat ~= "Air"),
		floor = floorMat,
		state = stateName,
		anchored = hrp.Anchored,
		owner = owner,
		nan = (vel.X ~= vel.X) or (vel.Z ~= vel.Z),
		portal = (safe(function()
			return hum.PlatformStand
		end) == true),
		seated = (safe(function()
			return hum.Sit
		end)) == true,
		dead = (attrOf(char, "Dead") == true)
			or (tonumber(safe(function()
				return hum.Health
			end)) or 1) <= 0,
	}
end

---------------------------------------------------------------
-- 7.45 判定复刻
--      常量与分支逐条对照 Lib.MoveWatch（868 行）原文：
--      STICK_MIN 0.5 / SPEED_MAX 0.5 / STUCK_AFTER 1.5 / LONG_STUCK 8
--      ANCHOR_AFTER 4 / LOOK_GAP 5 / SEND_GAP 60 / SEND_MAX 4
---------------------------------------------------------------
local MW = {
	STICK_MIN = 0.5,
	SPEED_MAX = 0.5,
	STUCK_AFTER = 1.5,
	LONG_STUCK = 8,
	ANCHOR_AFTER = 4,
	LOOK_GAP = 5,
	SEND_GAP = 60,
	SEND_MAX = 4,
	REMOTE = "mv.stuck",
}

local replica = {
	stuck = 0,
	wallAt = 0,
	wallName = nil,
	wallDist = 0,
	hard = {},
	soft = {},
	report = {},
	verdict = "—",
	at = 0,
}

-- 原文 advance(p9,p10,p11,p12)：只有“推着摇杆却几乎不动”才累加，其余按 -2dt 衰减
local function mwAdvance(stuck, dt, stick, speed)
	if MW.STICK_MIN < stick and speed < MW.SPEED_MAX then
		return stuck + dt
	end
	return math.max(0, stuck - dt * 2)
end

-- 原文 classify 的裁剪版：省略 panel/held/zbody 这些外部信号
local function mwClassify(m, stuck, wallName)
	local hard, soft = {}, {}
	if not m then
		return hard, soft
	end

	if m.dead then
		table.insert(hard, "dead")
	end

	if wallName then
		if stuck >= MW.LONG_STUCK then
			table.insert(soft, "wall_long")
		else
			table.insert(hard, "wall")
		end
	end

	if m.anchored then
		if stuck >= MW.ANCHOR_AFTER then
			table.insert(soft, "anchored")
		else
			table.insert(hard, "anchor_short")
		end
	end

	if m.nan then
		table.insert(soft, "nan")
	end

	-- 无输入（MoveDirection 为 0）却有明显速度 → ctrl_over
	if m.md <= 0.01 and m.speed >= MW.SPEED_MAX then
		table.insert(soft, "ctrl_over")
	end

	if m.owner == "server" or m.owner == "other" then
		table.insert(soft, "owner")
	end

	if m.portal or m.seated then
		table.insert(soft, "state")
		if m.ws < 1 then
			table.insert(soft, "ws_low")
		end
	end

	return hard, soft
end

-- 原文 HEALS：只有这几类软判定会被“自愈”解释掉，其余无人认领 → 外发
local MW_HEALS = {
	panel_inv = "panels",
	panel_map = "panels",
	panel_set = "panels",
	anchored = "anchor",
	nan = "nan",
	touch_ghost = "touch",
}

local function updateReplica(m, dt)
	if not m then
		replica.stuck = 0
		replica.hard, replica.soft, replica.report = {}, {}, {}
		replica.verdict = "无角色"
		return
	end

	replica.stuck = mwAdvance(replica.stuck, dt, m.md, m.speed)

	local now = os.clock()
	if now - replica.wallAt >= 0.25 then
		replica.wallAt = now
		local dirX, dirZ
		if m.speed >= MW.SPEED_MAX then
			-- 移动中：沿实际速度方向打射线（MoveWatch 用的是移动方向）
			dirX, dirZ = m.vx or 0, m.vz or 0
		end
		if not dirX or (dirX * dirX + dirZ * dirZ) < 0.0025 then
			local cam = workspace.CurrentCamera
			local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
			dirX, dirZ = look.X, look.Z
		end
		replica.wallName, replica.wallDist = wallProbe(dirX, dirZ)
	end

	replica.hard, replica.soft = mwClassify(m, replica.stuck, replica.wallName)
	replica.report = {}
	for _, tag in ipairs(replica.soft) do
		if MW_HEALS[tag] == nil then
			table.insert(replica.report, tag)
		end
	end
	replica.at = now
end

local function verdictLine()
	local function join(list)
		return #list > 0 and table.concat(list, "+") or ""
	end

	local rep = join(replica.report)
	local soft = join(replica.soft)
	local hard = join(replica.hard)

	local tag
	if rep ~= "" then
		tag = "会外发 " .. rep
	elseif soft ~= "" then
		tag = "自愈 " .. soft
	elseif hard ~= "" then
		tag = "已知 " .. hard
	else
		tag = "干净"
	end

	return string.format(
		"stuck %.1f/%.1fs  墙 %s  %s",
		replica.stuck, MW.STUCK_AFTER,
		replica.wallName or "无",
		tag
	)
end

-- full = true 时附带射线/重叠探针（较慢，只在点按钮时用）
local function computeRisk(full)
	local m = motion()
	if not m then
		return { score = 0, level = "无角色", reasons = {} }
	end

	local score = 0
	local reasons = {}

	local function add(points, text)
		score = score + points
		table.insert(reasons, string.format("%s %+d", text, points))
	end

	-- 1) 速度比
	if m.ratio >= RISK.SpeedMad then
		add(45, string.format("速度 %.0f%% WalkSpeed", m.ratio * 100))
	elseif m.ratio >= RISK.SpeedHard then
		add(28, string.format("速度 %.0f%% WalkSpeed", m.ratio * 100))
	elseif m.ratio >= RISK.SpeedSoft then
		add(12, string.format("速度 %.0f%% WalkSpeed", m.ratio * 100))
	end

	-- 2) 悬空 + 有输入 = 疑似飞天
	if (not m.onGround) and m.md > 0.1 then
		if airTime >= RISK.AirTime then
			add(24, string.format("有输入却悬空 %.1fs", airTime))
		elseif airTime > 0.35 then
			add(6, string.format("悬空 %.1fs", airTime))
		end
	end

	-- 3) 数值/归属异常
	if m.nan then
		add(40, "速度向量 NaN")
	end
	if m.anchored and m.speed > 0.4 then
		add(22, "锚定中仍有位移")
	end
	if m.owner == "other" or m.owner == "server" then
		add(18, "网络归属异常(" .. m.owner .. ")")
	end

	-- 4) 服务端记账增量
	local ds, dw = violDelta()
	if ds > 0 then
		add(math.min(30, 10 + ds * 6), string.format("速违 +%d", ds))
	end
	if dw > 0 then
		add(math.min(30, 10 + dw * 6), string.format("墙违 +%d", dw))
	end

	-- 5) 探针（可选）
	local wallNames = {}
	if full then
		local dirs = {
			{ 0, 1, "前" }, { 0, -1, "后" },
			{ 1, 0, "右" }, { -1, 0, "左" },
		}
		local hitCount = 0
		for _, d in ipairs(dirs) do
			local n, dist = wallProbe(d[1], d[2])
			if n then
				hitCount = hitCount + 1
				table.insert(wallNames, string.format("%s %s(%.1f)", d[3], n, dist))
			end
		end
		if hitCount > 0 and m.speed > 2 then
			add(14 + hitCount * 3, string.format("%d 面贴墙且仍在移动", hitCount))
		end

		local cnt, names = overlapProbe(6)
		if cnt > 0 then
			add(10, string.format("身体与 %d 个部件重叠(%s)", cnt, table.concat(names, ",")))
		end
	end

	score = math.clamp(score, 0, 100)

	local level
	if score >= 60 then
		level = "高危"
	elseif score >= 30 then
		level = "警戒"
	elseif score > 0 then
		level = "留意"
	else
		level = "干净"
	end

	return { score = score, level = level, reasons = reasons, m = m, walls = wallNames }
end

local function riskColor(score)
	if score >= 60 then
		return THEME.Red
	elseif score >= 30 then
		return THEME.Yellow
	end
	return THEME.Green
end

--=============================================================
-- 7.6 AcClient 复刻（Lib/AcClient · ac.hb · rv.cam）
--
--   原模块的采样门控（源码 start() 内）：
--     if config.flag("AntiCheat") == "off"
--        or LocalPlayer:GetAttribute("Place") ~= "Raid" then return end
--   —— 也就是说：只有在 Raid 里才会发心跳，主菜单 / Hideout 完全不采样。
--
--   采样：Heartbeat 与 RenderStepped 各拍一帧，build() 出
--     { v = 1, fd = focus↔root 水平距离, cd = camPos↔root 距离,
--       k = touch/pad/kb, x = 违规标记 0/1, m = 相机模式 }
--   fd / cd 都按 0.1 取整；两帧 merge 时取 max，x 取「或」。
--
--   x 变成 1 的三个条件（等号右边是源码原值）：
--     m == "fp" 且 |camPos - head| > 4
--     m == "tp" 且 |camPos - head| > 14
--     m == "iso" 且 angle(focus-camPos, camLook) > 4°
--                或 CameraType ~= "Scriptable"
--
--   另有一条 10Hz 的 rv.cam 流，只在 LocalPlayer:GetAttribute("Watched")
--   == true（有人正在看你）时开启，内容是 yaw/dist/fov/ox/oh/oo/aim/ammo。
--=============================================================
local AC = {
	PERIOD = 5,
	CD_FP = 4,
	CD_TP = 14,
	LOOK_DEG = 4,
	REMOTE = "ac.hb",
	WATCH_REMOTE = "rv.cam",
	WATCH_HZ = 10,
	PRIVATE = { "Ammo", "AmmoReserve", "AmmoTier", "Throwable", "ThrowableList", "Throwables" },
}

local function dist2d(ax, az, bx, bz)
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

local function dist3d(ax, ay, az, bx, by, bz)
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function acDevice()
	if safe(function()
		return UserInputService.TouchEnabled
	end) then
		return "touch"
	end
	if safe(function()
		return UserInputService.GamepadEnabled
	end) then
		return "pad"
	end
	return "kb"
end

-- 复刻 gather() + build()：返回这一帧会外发的载荷与判定依据
local function acSnapshot()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not (hrp and cam) then
		return nil
	end

	local root = hrp.Position
	local focus = safe(function()
		return cam.Focus.Position
	end) or root
	local camPos = safe(function()
		return cam.CFrame.Position
	end) or root
	local look = safe(function()
		return cam.CFrame.LookVector
	end) or { X = 0, Y = 0, Z = -1 }
	local camType = tostring(safe(function()
		return cam.CameraType.Name
	end) or "?")

	local headPart = char:FindFirstChild("Head")
	local head = (headPart and safe(function()
		return headPart.Position
	end)) or { X = root.X, Y = root.Y + 1.5, Z = root.Z }

	local mode = attrOf(LocalPlayer, "CamMode")
	if type(mode) ~= "string" then
		mode = "—"
	end
	if attrOf(LocalPlayer, "CamOverride") == true then
		mode = "scripted"
	end

	local fd = dist2d(focus.X, focus.Z, root.X, root.Z)
	local cd = dist3d(camPos.X, camPos.Y, camPos.Z, root.X, root.Y, root.Z)

	local flag, why = 0, nil
	if mode == "fp" or mode == "tp" then
		local limit = (mode == "fp") and AC.CD_FP or AC.CD_TP
		local d = dist3d(camPos.X, camPos.Y, camPos.Z, head.X, head.Y, head.Z)
		if d > limit then
			flag, why = 1, string.format("%s 相机离头 %.1f > %d", mode, d, limit)
		end
	elseif mode == "iso" then
		local vx, vy, vz = focus.X - camPos.X, focus.Y - camPos.Y, focus.Z - camPos.Z
		local vm = math.sqrt(vx * vx + vy * vy + vz * vz)
		local lm = math.sqrt(look.X * look.X + look.Y * look.Y + look.Z * look.Z)
		if vm > 1 and lm > 0.1 then
			local dot = (vx * look.X + vy * look.Y + vz * look.Z) / (vm * lm)
			dot = math.max(-1, math.min(1, dot))
			local deg = math.deg(math.acos(dot))
			if deg > AC.LOOK_DEG then
				flag, why = 1, string.format("视线偏离焦点 %.1f° > 4°", deg)
			end
		end
		if camType ~= "Scriptable" then
			flag = 1
			why = (why and (why .. "；") or "") .. "CameraType=" .. camType .. "（应为 Scriptable）"
		end
	end

	local place = attrOf(LocalPlayer, "Place")
	local status = attrOf(LocalPlayer, "RaidStatus")

	return {
		fd = fd,
		cd = cd,
		mode = mode,
		camType = camType,
		dev = acDevice(),
		flag = flag,
		why = why,
		place = place,
		status = status,
		watched = (attrOf(LocalPlayer, "Watched") == true),
		gated = (place ~= "Raid"),
	}
end

local function acGateText(s)
	if not s then
		return "—", THEME.SubText
	end
	if s.gated then
		return "门控关", THEME.SubText
	end
	if s.watched then
		return "被观察", THEME.Red
	end
	return "5s", THEME.Green
end

-- 一行摘要：fd/cd/k/x/m + 门控
local function acLine()
	local s = acSnapshot()
	if not s then
		return "等待角色…", THEME.SubText, "—", THEME.SubText
	end
	local txt = string.format(
		"fd %.1f  cd %.1f  %s  %s  x=%d",
		s.fd, s.cd, s.dev, s.mode, s.flag
	)
	if s.gated then
		txt = txt .. "  （不在 Raid，不上报）"
	end
	local color = THEME.Green
	if s.flag == 1 then
		color = THEME.Red
	elseif s.gated then
		color = THEME.SubText
	end
	return txt, color, acGateText(s)
end

--=============================================================
-- 7.7 撤离点（RaidClient：Extracts 文件夹 + 逐部件属性）
--     部件属性：ExtractId / State(inbound|boarding|running|departed)
--               StateEndsAt / Kind(Heli|Vehicle) / Seats / Condition / Open
--=============================================================
local EXTRACT_STATE = {
	inbound = "在途",
	boarding = "登机中",
	running = "引擎已开",
	departed = "已起飞",
}

local function findExtractFolders()
	local out = {}
	local seen = {}

	local function walk(inst, depth)
		if depth > 3 or #out >= 6 then
			return
		end
		local kids = safe(function()
			return inst:GetChildren()
		end)
		if type(kids) ~= "table" then
			return
		end
		for _, c in ipairs(kids) do
			local nm = safe(function()
				return c.Name
			end)
			if nm == "Extracts" and not seen[c] then
				seen[c] = true
				table.insert(out, c)
			elseif nm ~= "Extracts" then
				local cls = classNameOf(c)
				if cls == "Folder" or cls == "Model" then
					walk(c, depth + 1)
				end
			end
		end
	end

	walk(Workspace, 0)

	local pg = safe(function()
		return LocalPlayer:FindFirstChild("PlayerGui")
	end)
	local personal = pg and safe(function()
		return pg:FindFirstChild("HushPersonalExtracts")
	end)
	if personal then
		table.insert(out, personal)
	end
	return out
end

-- 返回 { list = {...}, folders = n }
local function scanExtracts()
	local ref = refPosition()
	local list, nFolders = {}, 0
	for _, folder in ipairs(findExtractFolders()) do
		nFolders = nFolders + 1
		local kids = safe(function()
			return folder:GetChildren()
		end)
		if type(kids) == "table" then
			for _, part in ipairs(kids) do
				local pos = safe(function()
					return part.Position
				end)
				if type(pos) == "table" and type(pos.X) == "number" then
					table.insert(list, {
						id = tostring(attrOf(part, "ExtractId") or part.Name),
						state = tostring(attrOf(part, "State") or "—"),
						kind = tostring(attrOf(part, "Kind") or "—"),
						seats = attrOf(part, "Seats"),
						open = attrOf(part, "Open"),
						cond = tostring(attrOf(part, "Condition") or ""),
						ends = numAttr(part, "StateEndsAt", 0),
						dist = dist3d(pos.X, pos.Y, pos.Z, ref.X, ref.Y, ref.Z),
					})
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return { list = list, folders = nFolders }
end

---------------------------------------------------------------
-- 7.8 相机（Camera 控制器把实时状态写成本地属性）
--     CamMode / CamZoom / CamDist / CamYaw / CamStep / CamOverride / CamTarget
---------------------------------------------------------------
local CAM_ATTRS = { "CamMode", "CamZoom", "CamDist", "CamYaw", "CamStep", "CamOverride", "CamTarget" }

local function cameraState()
	local cam = workspace.CurrentCamera
	local out = { attrs = {}, fov = nil, camType = nil, viewport = nil }
	for _, name in ipairs(CAM_ATTRS) do
		out.attrs[name] = attrOf(LocalPlayer, name)
	end
	out.fov = safe(function()
		return cam.FieldOfView
	end)
	out.camType = safe(function()
		return cam.CameraType.Name
	end)
	out.viewport = safe(function()
		return tostring(cam.ViewportSize.X) .. "×" .. tostring(cam.ViewportSize.Y)
	end)
	return out
end

--=============================================================
-- 8) 功能实现
--=============================================================
local actions = {}

---------------------------------------------------------------
-- 8.0 武器状态：weapon.state 的解析与实时条
--     字段来自 WeaponClient 的 command 返回值：
--     active weapon ammo/mag reserve mode reloading jammed throwable
--     fx debugAim wantYaw serverAimYaw shotSeq
---------------------------------------------------------------
local wpnCache = {
	at = 0,
	kv = nil,
	rpm = nil,
	dev = nil,
	base = nil,     -- { seq, at } 射速基线
	sampling = false,
}

local function parseKV(str)
	local t = {}
	for k, v in tostring(str):gmatch("([%w_]+)=([^%s]+)") do
		t[k] = v
	end
	return t
end

local function angDiffDeg(a, b)
	local d = (a - b) % (math.pi * 2)
	if d > math.pi then
		d = d - math.pi * 2
	end
	return math.abs(math.deg(d))
end

-- 只读本地属性，不碰命令总线（这条每 0.5s 跑一次）
local function weaponLine()
	local char = LocalPlayer.Character
	if not char then
		wpnText.Text = "无角色"
		wpnText.TextColor3 = THEME.SubText
		wpnGate.Text = "—"
		wpnGate.TextColor3 = THEME.SubText
		return
	end

	local ammo = attrOf(char, "Ammo")
	local mag = attrOf(char, "MagSize") or attrOf(char, "Mag")
	local reserve = attrOf(char, "AmmoReserve")
	local mode = attrOf(char, "FireMode")
	local reloading = attrOf(char, "Reloading")
	local jammed = attrOf(char, "Jammed")
	local aimYaw = attrOf(char, "AimYaw")
	local uid = attrOf(char, "WeaponUid")

	if uid == nil and ammo == nil then
		wpnText.Text = "未装备"
		wpnText.TextColor3 = THEME.SubText
		wpnGate.Text = "空手"
		wpnGate.TextColor3 = THEME.SubText
		return
	end

	local parts = {}
	if ammo ~= nil then
		table.insert(parts, string.format("%s/%s", tostring(ammo), mag ~= nil and tostring(mag) or "?"))
	else
		table.insert(parts, "弹 —")
	end
	if reserve ~= nil then
		table.insert(parts, "备 " .. tostring(reserve))
	end
	if mode ~= nil then
		table.insert(parts, tostring(mode))
	end

	local color = THEME.Text
	if wpnCache.dev ~= nil then
		table.insert(parts, string.format("偏 %.1f°", wpnCache.dev))
		if wpnCache.dev > RISK.AimDev then
			color = THEME.Yellow
		end
	end
	if wpnCache.rpm ~= nil then
		table.insert(parts, string.format("%.0frpm", wpnCache.rpm))
		if wpnCache.rpm > RISK.RpmMax then
			color = THEME.Red
		end
	end
	if aimYaw ~= nil and wpnCache.dev == nil then
		table.insert(parts, string.format("yaw %.2f", tonumber(aimYaw) or 0))
	end

	wpnText.Text = table.concat(parts, " · ")
	wpnText.TextColor3 = color

	if jammed == true then
		wpnGate.Text = "卡壳"
		wpnGate.TextColor3 = THEME.Red
	elseif reloading == true then
		wpnGate.Text = "装填"
		wpnGate.TextColor3 = THEME.Yellow
	elseif wpnCache.dev ~= nil and wpnCache.dev > RISK.AimDev then
		wpnGate.Text = "偏瞄"
		wpnGate.TextColor3 = THEME.Yellow
	elseif wpnCache.rpm ~= nil and wpnCache.rpm > RISK.RpmMax then
		wpnGate.Text = "超速"
		wpnGate.TextColor3 = THEME.Red
	elseif uid ~= nil then
		wpnGate.Text = "就绪"
		wpnGate.TextColor3 = THEME.Green
	else
		wpnGate.Text = "—"
		wpnGate.TextColor3 = THEME.SubText
	end
end

-- 把一次 weapon.state 的结果塞进缓存
local function absorbWeapon(kv, at)
	wpnCache.kv = kv
	wpnCache.at = at

	local want = tonumber(kv.wantYaw)
	local server = tonumber(kv.serverAimYaw)
	if want and server then
		wpnCache.dev = angDiffDeg(want, server)
	else
		wpnCache.dev = nil
	end

	local seq = tonumber(kv.shotSeq)
	if seq then
		local b = wpnCache.base
		if b and b.seq and seq >= b.seq and (at - b.at) >= 1.0 then
			wpnCache.rpm = (seq - b.seq) / (at - b.at) * 60
		end
		wpnCache.base = { seq = seq, at = at }
	end
end

---------------------------------------------------------------
-- 8.1 违规读数
---------------------------------------------------------------
function actions.violations()
	local v = readViolations()
	if not v.found then
		pushLog("未找到 SpeedViolations / WallViolations 属性：可能不在对局内，或该版本改用其它字段", "warn")
		pushLog("→ 用「命令总线」执行 movewatch.state 可看客户端侧计数", "info")
		return
	end

	local ds, dw, dr = violDelta()
	pushLog(string.format(
		"违规读数（来源:%s）  速度 %d (Δ%+d)  穿墙 %d (Δ%+d)  纠正 %d (Δ%+d)",
		v.src, v.speed, ds, v.wall, dw, v.rescue, dr
	), (v.speed > 0 or v.wall > 0) and "err" or "ok")

	if v.speed == 0 and v.wall == 0 then
		pushLog("服务端尚未记账：当前行为没触发位移类检测", "ok")
	else
		pushLog("已有记账：说明历史上有动作被判违规，继续叠加可能触发踢出/封禁", "risk")
	end

	local mw = attrOf(LocalPlayer, "MoveWatch")
	if type(mw) == "string" and mw ~= "" then
		pushLog("最近一次上报: " .. mw, "info")
		local stuck = string.match(mw, "stuck=([%d%.]+)")
		local suspects = string.match(mw, "suspects=([%w_+]+)")
		if suspects and suspects ~= "none" then
			pushLog("判定归类: " .. suspects, "warn")
		end
		if stuck then
			pushLog("卡住计时: " .. stuck .. "s（MoveWatch 在 1.5s 开始采样，8s 升级为 wall_long）", "info")
		end
	end

	local zb = attrOf(LocalPlayer, "ZBlockStats")
	if type(zb) == "string" and zb ~= "" and zb ~= "none" then
		pushLog("ZBlockStats（僵尸阻挡）: " .. zb, "info")
	end

	local snare = attrOf(LocalPlayer.Character, "SnareMul")
	if type(snare) == "number" then
		pushLog(string.format("SnareMul = %.2f（<0.3 会被 MoveWatch 判为受控减速）", snare), "info")
	end
end

---------------------------------------------------------------
-- 8.2 速度审计
---------------------------------------------------------------
function actions.speed()
	local m = motion()
	if not m then
		pushLog("没有角色，无法审计", "warn")
		return
	end

	local cap = m.ws * 1.05
	pushLog(string.format(
		"实测 WalkSpeed = %.1f 格/秒 → 建议位移峰值 ≤ %.1f 格/秒",
		m.ws, cap
	), "info")

	pushLog("采样 1.2s …", "info")
	local peak, sum, n, over = 0, 0, 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < 1.2 do
		local s = motion()
		if s then
			n = n + 1
			sum = sum + s.speed
			if s.speed > peak then
				peak = s.speed
			end
			if s.speed > cap then
				over = over + 1
			end
		end
		task.wait(0.05)
	end

	if n == 0 then
		pushLog("采样失败（角色中途消失）", "warn")
		return
	end

	local avg = sum / n
	local overPct = over / n * 100
	pushLog(string.format(
		"均值 %.1f  峰值 %.1f  超限帧 %.0f%%  峰值倍率 %.2f×",
		avg, peak, overPct, (m.ws > 0) and (peak / m.ws) or 0
	), overPct > 20 and "err" or (overPct > 5 and "warn" or "ok"))

	if peak / math.max(m.ws, 1) > RISK.SpeedHard then
		pushLog("峰值已越过 1.6× 阈值：服务端速度校验很容易抓到", "err")
	elseif peak / math.max(m.ws, 1) > RISK.SpeedSoft then
		pushLog("峰值在 1.15×–1.6× 之间：短时可容忍，长时间维持会被计数", "warn")
	else
		pushLog("速度在合法区间内，不会产生 SpeedViolations", "ok")
	end

	if m.vy > 6 then
		pushLog(string.format("垂直速度 %+.1f：正在上升，落地前别叠加水平加速", m.vy), "warn")
	end
end

---------------------------------------------------------------
-- 8.3 墙体探针
---------------------------------------------------------------
function actions.wall()
	local m = motion()
	if not m then
		pushLog("没有角色", "warn")
		return
	end

	local dirs = {
		{ 0, 1, "前" }, { 0, -1, "后" },
		{ 1, 0, "右" }, { -1, 0, "左" },
	}
	local hitAny = false
	for _, d in ipairs(dirs) do
		local name, dist = wallProbe(d[1], d[2])
		if name then
			hitAny = true
			pushLog(string.format("%s侧 %.1f 格处: %s（Collide=真）", d[3], dist, name), "warn")
		end
	end

	if not hitAny then
		pushLog(string.format("四面 %.1f 格内无碰撞体：MoveWatch 不会判 wall", RISK.WallRange), "ok")
		return
	end

	if m.speed > 2 then
		pushLog("贴墙且仍在移动：这个组合会直接进入 MoveWatch.classify 的 wall 分支", "err")
		pushLog("超过 8s 会升级成 wall_long，并可能上报 mv.stuck", "risk")
	else
		pushLog("虽然贴墙，但速度接近 0，暂时不会被判 wall", "info")
	end
end

---------------------------------------------------------------
-- 8.4 卡模检测
---------------------------------------------------------------
function actions.overlap()
	local cnt, names = overlapProbe(8)
	if cnt == 0 then
		pushLog("身体没有与任何 Collide 部件重叠", "ok")
		return
	end
	pushLog(string.format("身体与 %d 个部件重叠: %s", cnt, table.concat(names, ", ")), "warn")
	pushLog("重叠会被 MoveWatch 记进 overlap 字段，配合 stuck 一起上报", "info")
end

---------------------------------------------------------------
-- 8.5 反作弊状态
---------------------------------------------------------------
function actions.movewatch()
	local mw = probeMoveWatch(true)
	if not mw.module then
		pushLog("MoveWatch 读取失败: " .. mw.path .. " — " .. mw.why, "warn")
		return
	end

	pushLog("模块: " .. mw.path .. " · " .. mw.why, mw.live and "ok" or "warn")
	pushLog(string.format(
		"常量  STUCK_MIN=%.2f  SPEED_MAX=%.2f  STUCK_AFTER=%.1fs  LONG_STUCK=%.0fs  ANCHOR_AFTER=%.0fs",
		tonumber(mw.module.STICK_MIN) or 0,
		tonumber(mw.module.SPEED_MAX) or 0,
		tonumber(mw.module.STUCK_AFTER) or 0,
		tonumber(mw.module.LONG_STUCK) or 0,
		tonumber(mw.module.ANCHOR_AFTER) or 0
	), "info")
	pushLog(string.format(
		"上报  间隔 %.0fs  上限 %d 条  故障上限 %d 条  远程 %s",
		tonumber(mw.module.SEND_GAP) or 0,
		tonumber(mw.module.SEND_MAX) or 0,
		tonumber(mw.module.FAULT_MAX) or 0,
		tostring(mw.module.REMOTE or "?")
	), "info")

	local st = mw.module._state
	if type(st) ~= "table" then
		pushLog("没有 _state，无法读取计数器", "warn")
		return
	end

	pushLog(string.format(
		"计数  采样 %d  已解释 %d  上报 %d  上报包 %d  修复 %d  自愈 %d  错误 %d  故障 %d",
		tonumber(st.looks) or 0,
		tonumber(st.explained) or 0,
		tonumber(st.reports) or 0,
		tonumber(st.sends) or 0,
		tonumber(st.fixReports) or 0,
		tonumber(st.heals) or 0,
		tonumber(st.errors) or 0,
		tonumber(st.faults) or 0
	), "info")

	if st.lastKnown and st.lastKnown ~= "" then
		pushLog("最近已知归类: " .. tostring(st.lastKnown), "warn")
	end
	if st.off then
		pushLog("MoveWatch 自身已因错误停用", "err")
	end
	if (tonumber(st.sends) or 0) >= (tonumber(mw.module.SEND_MAX) or 4) then
		pushLog("上报配额已用尽：本局已向服务器送满 mv.stuck 包", "err")
	end
end

---------------------------------------------------------------
-- 8.6 网络余量
---------------------------------------------------------------
function actions.net()
	local rs = safe(function()
		return game:GetService("ReplicatedStorage")
	end)
	local hushNet = rs and rs:FindFirstChild("HushNet")
	if not hushNet then
		pushLog("ReplicatedStorage.HushNet 不存在：客户端可能未初始化", "warn")
		return
	end

	local names = {}
	for _, c in ipairs(hushNet:GetChildren()) do
		table.insert(names, string.format("%s(%s)", tostring(c.Name), classNameOf(c)))
	end
	table.sort(names)
	pushLog(string.format("HushNet 共 %d 个远程: %s", #names, table.concat(names, "  ")), "info")

	local mv = hushNet:FindFirstChild("mv.stuck")
	if mv then
		pushLog("mv.stuck 存在（" .. classNameOf(mv) .. "）：MoveWatch 用它上报卡住/穿墙样本", "warn")
	else
		pushLog("mv.stuck 不存在：本版本 MoveWatch 不会上报（但仍可能有服务端校验）", "ok")
	end

	local mw = probeMoveWatch()
	if mw.module then
		local st = mw.module._state or {}
		local sendMax = tonumber(mw.module.SEND_MAX) or 4
		local used = tonumber(st.sends) or 0
		pushLog(string.format(
			"上报配额 %d/%d  冷却 %.0fs  故障 %d/%d",
			used, sendMax,
			tonumber(mw.module.SEND_GAP) or 60,
			tonumber(st.faults) or 0,
			tonumber(mw.module.FAULT_MAX) or 4
		), used >= sendMax and "err" or "info")
	else
		pushLog("配额未知（MoveWatch 不可读），保守假设已上报 0 条", "info")
	end

	pushLog("提示：面板不会主动 FireServer，任何上报都来自游戏自己的 MoveWatch", "ok")
end

---------------------------------------------------------------
-- 8.7 命令总线
---------------------------------------------------------------
function actions.command(line)
	pushLog("→ " .. line, "info")
	local ok, res = runCommand(line)
	if ok then
		pushLog(string.format("← %s", tostring(res)), "ok")
	else
		pushLog(string.format("← 失败: %s", tostring(res)), "err")
		pushLog("可用命令: " .. (function()
			local t = {}
			for _, c in ipairs(KNOWN_CMD) do
				table.insert(t, c[1])
			end
			return table.concat(t, " / ")
		end)(), "info")
	end
end

function actions.cmdHelp()
	pushLog("命令总线 = HushClient.Main 自带的 HushClientCmd 属性入口（只读类命令）", "info")
	for _, c in ipairs(KNOWN_CMD) do
		pushLog(string.format("  %-18s %s", c[1], c[2]), "info")
	end
	pushLog("写法: 命令名 + 空格 + 参数，例如 movewatch.state / zrender.follow log", "info")
end

---------------------------------------------------------------
-- 8.8 武器状态
---------------------------------------------------------------
local function sampleWeapon()
	local ok, res = runCommand("weapon.state")
	if not ok then
		return nil, res
	end
	local kv = parseKV(res)
	absorbWeapon(kv, os.clock())
	return kv, res
end

function actions.weapon()
	local char = LocalPlayer.Character
	local kv, res = sampleWeapon()
	if kv then
		pushLog("武器: " .. tostring(res), "ok")
		pushLog(string.format(
			"弹 %s · 备 %s · 模式 %s · 装填 %s · 卡壳 %s · 投掷 %s",
			tostring(kv.ammo), tostring(kv.reserve),
			tostring(kv.mode), tostring(kv.reloading), tostring(kv.jammed),
			tostring(kv.throwable)
		), "info")

		local want = tonumber(kv.wantYaw)
		local server = tonumber(kv.serverAimYaw)
		if want and server then
			local dev = angDiffDeg(want, server)
			pushLog(string.format(
				"瞄准: wantYaw %.2f / serverAimYaw %.2f → 偏 %.2f°（阈值 %.0f°）",
				want, server, dev, RISK.AimDev
			), dev > RISK.AimDev and "warn" or "ok")
			if dev > RISK.AimDev then
				pushLog("客户端瞄准方向与服务器认可的 AimYaw 不一致：自瞄/吸附的典型痕迹", "warn")
			end
		else
			pushLog(string.format("瞄准: wantYaw=%s serverAimYaw=%s（无有效瞄准面）",
				tostring(kv.wantYaw), tostring(kv.serverAimYaw)), "info")
		end

		pushLog(string.format(
			"发射序号 shotSeq=%s（本地自增，连点两次「射速校验」可算 RPM）",
			tostring(kv.shotSeq)
		), "info")
	else
		pushLog("weapon.state 无响应（可能未装备武器）: " .. tostring(res), "warn")
		local tool = char and char:FindFirstChildOfClass("Tool")
		if tool then
			pushLog("仍持有工具: " .. tool.Name, "info")
			local attrs = safe(function()
				return tool:GetAttributes()
			end)
			if type(attrs) == "table" then
				local n = 0
				for name, value in pairs(attrs) do
					if n >= 6 then
						break
					end
					pushLog(string.format("  %s = %s", tostring(name), fmt(value)), "info")
					n = n + 1
				end
			end
		end
	end

	local uid = attrOf(char, "WeaponUid")
	if uid ~= nil then
		pushLog("WeaponUid = " .. tostring(uid), "info")
	end
end

---------------------------------------------------------------
-- 8.8b 射速校验：同一把枪两次采样，用 shotSeq 增量算实际 RPM
--      shotSeq 来自 WeaponClient.sendAndPredict，每次开火 +1
---------------------------------------------------------------
function actions.weaponRate()
	if wpnCache.sampling then
		pushLog("射速采样正在进行，等这一轮出结果", "warn")
		return
	end

	local kv = sampleWeapon()
	if not kv then
		pushLog("射速校验失败：weapon.state 无响应", "err")
		return
	end

	local s1 = tonumber(kv.shotSeq)
	if not s1 then
		pushLog("射速校验失败：返回里没有 shotSeq 字段", "err")
		return
	end

	wpnCache.rpm = nil
	wpnCache.sampling = true
	pushLog(string.format("射速采样 · 基线 seq=%d，保持开火 3 秒…", s1), "info")

	task.spawn(function()
		task.wait(3)
		local kv2 = sampleWeapon()
		wpnCache.sampling = false
		if not kv2 then
			pushLog("射速采样失败：第二次 weapon.state 无响应", "err")
			return
		end
		local s2 = tonumber(kv2.shotSeq)
		if not s2 then
			pushLog("射速采样失败：第二次没有 shotSeq", "err")
			return
		end
		local d = s2 - s1
		if d < 0 then
			pushLog("射速采样失效：seq 回退（可能换枪/重生，或客户端重新加载）", "warn")
			return
		end
		local rpm = d / 3 * 60
		wpnCache.rpm = rpm
		pushLog(string.format(
			"射速: Δseq=%d / 3.0s → %.0f RPM（模式 %s · 武器 %s）",
			d, rpm, tostring(kv2.mode), tostring(kv2.weapon)
		), rpm > RISK.RpmMax and "warn" or "ok")
		if rpm > RISK.RpmMax then
			pushLog(string.format(
				"超过 %.0f RPM：连发加速/自动扳机的特征；服务端按武器间隔校验时会对不上",
				RISK.RpmMax
			), "warn")
		end
		if d == 0 then
			pushLog("这 3 秒没有发射（seq 未变），换个开火窗口再试", "info")
		end
	end)
end

---------------------------------------------------------------
-- 8.8c 地图 / 任务（MapUI，纯客户端渲染，只有设置项会走 menu.op）
---------------------------------------------------------------
function actions.mapInfo()
	local ok1, state = runCommand("map.state")
	if ok1 then
		local kv = parseKV(state)
		pushLog(string.format(
			"地图: 打开=%s 场景=%s 层=%s 标记=%s 模式=%s",
			tostring(kv.open), tostring(kv.place), tostring(kv.level),
			tostring(kv.marks), tostring(kv.mode)
		), "ok")
		pushLog(string.format(
			"      图幅 %s · 按钮 touch=%s exits=%s",
			tostring(kv.sheet), tostring(kv.touchBtn), tostring(kv.exitsBtn)
		), "info")
	else
		pushLog("map.state 无响应: " .. tostring(state), "warn")
	end

	local ok2, lvl = runCommand("map.level")
	if ok2 then
		local kv = parseKV(lvl)
		pushLog(string.format(
			"关卡: 模式=%s 图=%s 层=%s 实际层=%s · 图页 %s 张（%s）· 房间 %s 帧 %s 门 %s 链接 %s · 构建 %sms",
			tostring(kv.mode), tostring(kv.map), tostring(kv.level), tostring(kv.own),
			tostring(kv.sheets), tostring(kv.sheet), tostring(kv.rooms), tostring(kv.frames),
			tostring(kv.doors), tostring(kv.links), tostring(kv.buildMs)
		), "info")
	end

	local ok3, tasks = runCommand("map.tasks")
	if ok3 then
		local head, body = tostring(tasks):match("^(.-)::%s*(.*)$")
		pushLog("任务: " .. tostring(head), "ok")
		if body and body ~= "" then
			local n = 0
			for item in body:gmatch("%S+") do
				if n >= 8 then
					pushLog("      …（还有更多，用 map.tasks 看全量）", "info")
					break
				end
				pushLog("      " .. item, "info")
				n = n + 1
			end
		end
	else
		pushLog("map.tasks 无响应: " .. tostring(tasks), "warn")
	end

	local ok4, wp = runCommand("map.wp")
	if ok4 then
		local kv = parseKV(wp)
		pushLog(string.format(
			"航点: 状态 %s · 已设 %s · 已清 %s · 签名 %s",
			tostring(kv.wp), tostring(kv.set), tostring(kv.cleared), tostring(kv.sig)
		), "info")
	end

	pushLog("MapUI 的标记/路径全在客户端内存，只有 mapHintSeen 这类设置会走 menu.op", "info")
end

---------------------------------------------------------------
-- 8.9 渲染统计
---------------------------------------------------------------
function actions.render()
	local ok, res = runCommand("zrender.stats")
	if ok then
		pushLog("渲染: " .. tostring(res), "ok")
	else
		pushLog("zrender.stats 无响应: " .. tostring(res), "warn")
	end

	local ok2, res2 = runCommand("zrender.eyes")
	if ok2 then
		pushLog("视界: " .. tostring(res2), "ok")
	end

	local zc = #collectZombies(true)
	pushLog(string.format(
		"HushLocal.Zombies = %d 只  渲染开关 esp=%s  纯客户端，不产生服务端交互",
		zc, espOn and "开" or "关"
	), "info")
end

---------------------------------------------------------------
-- 8.9b 判定复刻（把面板自己的结论摊开）
---------------------------------------------------------------
function actions.verdict()
	local m = motion()
	if not m then
		pushLog("没有角色，无法判定", "warn")
		return
	end

	updateReplica(m, 0)

	pushLog("判定复刻 · 对照 Lib.MoveWatch.classify", "info")
	pushLog(string.format(
		"输入 %.2f   水平速度 %.2f   速比 %.2f×   WS %.1f",
		m.md, m.speed, m.ratio, m.ws
	), "info")
	pushLog(string.format(
		"状态 %s   地面 %s   锚定 %s   归属 %s   平台 %s   坐下 %s   死亡 %s",
		m.state, m.floor, m.anchored and "是" or "否", m.owner,
		m.portal and "是" or "否", m.seated and "是" or "否", m.dead and "是" or "否"
	), "info")
	pushLog(string.format(
		"stuck %.2fs（阈值 %.1fs · 长时 %.1fs）   前方墙体 %s",
		replica.stuck, MW.STUCK_AFTER, MW.LONG_STUCK,
		replica.wallName and string.format("%s %.1f格", replica.wallName, replica.wallDist) or "无"
	), "info")

	if #replica.hard > 0 then
		pushLog("已知项: " .. table.concat(replica.hard, "+") .. "  → MoveWatch 当作可解释，不上报", "ok")
	else
		pushLog("已知项: 无", "info")
	end
	if #replica.soft > 0 then
		pushLog("软判定: " .. table.concat(replica.soft, "+") .. "  → 交给 HEALS 尝试解释", "warn")
	end
	if replica.report and #replica.report > 0 then
		pushLog(
			"会外发: " .. table.concat(replica.report, "+")
			.. "  → 无 heal 认领，满足 60s 冷却与 4 条配额就会 FireServer",
			"err"
		)
	else
		pushLog("外发风险: 无（当前没有无人认领的软判定）", "ok")
	end

	if m.md <= 0.01 and m.speed >= MW.SPEED_MAX then
		pushLog("提示: 当前无输入却有速度，正是 ctrl_over 的触发条件", "warn")
	end
	if replica.stuck >= MW.STUCK_AFTER then
		pushLog(string.format(
			"提示: stuck 已过 %.1fs，MoveWatch 每 %.0fs 采样一次（LOOK_GAP）",
			MW.STUCK_AFTER, MW.LOOK_GAP
		), "warn")
	end

	-- 第二条通道：AcClient 的 ac.hb 载荷
	local s = acSnapshot()
	if s then
		pushLog("— 第二条通道 · ac.hb（每 5s 一包）—", "info")
		pushLog(string.format(
			"载荷 v=1  fd=%.1f  cd=%.1f  k=%s  m=%s  x=%d",
			s.fd, s.cd, s.dev, s.mode, s.flag
		), s.flag == 1 and "err" or "ok")
		if s.flag == 1 then
			pushLog("  x=1 原因: " .. tostring(s.why), "err")
		end
		if s.gated then
			pushLog(string.format("  Place=%s ≠ Raid → 心跳不发，但换图后会立刻开始", tostring(s.place)), "warn")
		end
		if s.watched then
			pushLog("  Watched=true：rv.cam 以 10Hz 上传相机与偏移，说明有人在看", "err")
		end
	end
end

---------------------------------------------------------------
-- 8.9c 战局信息
---------------------------------------------------------------
function actions.raid()
	local p = LocalPlayer
	local place = attrOf(p, "Place") or "?"
	local status = attrOf(p, "RaidStatus") or "?"
	local mapId = attrOf(p, "MapId") or attrOf(p, "Map") or "?"
	local diff = attrOf(p, "Difficulty") or "?"
	local raidId = attrOf(p, "RaidId")

	pushLog(string.format("对局  %s · %s · 地图 %s · 难度 %s", place, status, mapId, diff), "info")
	if type(raidId) == "string" and raidId ~= "" then
		pushLog("  实例 " .. raidId, "info")
	end

	local startedAt = numAttr(p, "StartedAt", nil)
	if startedAt and startedAt > 1000000000 then
		local elapsed = os.time() - startedAt
		if elapsed >= 0 and elapsed < 86400 then
			pushLog(string.format(
				"  已进行 %02d:%02d", math.floor(elapsed / 60), elapsed % 60
			), "info")
		end
	end

	-- 队伍
	local mySquad = attrOf(p, "SquadId")
	local mates, others = {}, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= p then
			local sid = attrOf(pl, "SquadId")
			if mySquad ~= nil and sid == mySquad then
				table.insert(mates, pl)
			else
				others = others + 1
			end
		end
	end
	pushLog(string.format("  队友 %d 人   其他玩家 %d 人", #mates, others), "info")
	for _, pl in ipairs(mates) do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - refPosition()).Magnitude
			pushLog(string.format(
				"    %s  %.0f格  %s", pl.Name, d,
				attrOf(pl, "Downed") == true and "倒地" or "正常"
			), "info")
		end
	end

	-- 场景
	local raid = workspace:FindFirstChild("Raid")
	if raid then
		local zones = {}
		for _, c in ipairs(raid:GetChildren()) do
			table.insert(zones, c.Name)
			if #zones >= 6 then
				break
			end
		end
		pushLog("  Raid 子节点: " .. table.concat(zones, ", "), "info")
	end

	local zc = #collectZombies(true)
	local _, zd = nearestZombie()
	pushLog(string.format(
		"  僵尸 %d 只%s", zc,
		zd and zd < math.huge and string.format("，最近 %.0f 格", zd) or ""
	), "info")

	local known = numAttr(p, "ZombiesKnown", nil)
	if known then
		pushLog(string.format("  渲染器口径 ZombiesKnown=%d", known), "info")
	end
end

---------------------------------------------------------------
-- 8.9d 撤离点（RaidClient）
---------------------------------------------------------------
local function serverNow()
	local t = safe(function()
		return workspace:GetServerTimeNow()
	end)
	if type(t) == "number" then
		return t
	end
	return os.time()
end

function actions.extracts()
	local res = scanExtracts()

	if res.folders == 0 then
		pushLog("没找到 Extracts 容器：不在 Raid，或本轮撤离点还没刷出来", "warn")
		local ok0, r0 = runCommand("raidclient.status")
		pushLog("raidclient.status ← " .. tostring(r0), ok0 and "info" or "warn")
		return
	end

	pushLog(string.format("Extracts 容器 %d 个 · 部件 %d 个", res.folders, #res.list), "ok")
	if #res.list == 0 then
		pushLog("容器是空的：RaidClient 还没 hook 到部件，或撤离点已被清空", "warn")
		return
	end

	local now = serverNow()
	for i, e in ipairs(res.list) do
		if i > 8 then
			pushLog(string.format("  …还有 %d 个", #res.list - 8), "info")
			break
		end
		local st = EXTRACT_STATE[e.state] or e.state
		local bits = { string.format("%-10s %5.0f格  %s", e.id, e.dist, st) }
		if e.kind ~= "—" and e.kind ~= "" then
			table.insert(bits, e.kind)
		end
		if type(e.seats) == "number" then
			table.insert(bits, string.format("%d 座", e.seats))
		end
		if e.ends and e.ends > 0 then
			local left = e.ends - now
			if left > -60 and left < 3600 then
				table.insert(bits, string.format("%s%02d:%02d", left >= 0 and "剩 " or "超 ", math.floor(math.abs(left) / 60), math.floor(math.abs(left)) % 60))
			end
		end
		if e.cond and e.cond ~= "" then
			table.insert(bits, e.cond)
		end
		if e.open ~= nil then
			table.insert(bits, e.open and "开放" or "关闭")
		end
		pushLog("  " .. table.concat(bits, "  "), "info")
	end

	local ok, r = runCommand("raidclient.status")
	if ok then
		pushLog("raidclient.status ← " .. tostring(r), "info")
	end
	pushLog("提示：撤离点的 State/Seats 只由服务器推进，面板只读不改", "info")
end

---------------------------------------------------------------
-- 8.9e 相机（Camera 控制器属性 + camera.info）
---------------------------------------------------------------
function actions.camera()
	local cs = cameraState()
	local s = acSnapshot()

	pushLog("相机 · Camera 控制器把状态写成 LocalPlayer 属性", "info")
	pushLog(string.format(
		"  mode=%s  zoom=%s  dist=%s  yaw=%s  step=%s  override=%s",
		fmt(cs.attrs.CamMode), fmt(cs.attrs.CamZoom), fmt(cs.attrs.CamDist),
		fmt(cs.attrs.CamYaw), fmt(cs.attrs.CamStep), fmt(cs.attrs.CamOverride)
	), "info")
	pushLog(string.format(
		"  实时 FOV %.1f   CameraType %s   视口 %s",
		tonumber(cs.fov) or 0, tostring(cs.camType), tostring(cs.viewport)
	), "info")

	if s then
		pushLog(string.format(
			"  AcClient 口径: fd %.1f（焦点↔根水平）  cd %.1f（相机↔根）  x=%d",
			s.fd, s.cd, s.flag
		), s.flag == 1 and "err" or "ok")
		if s.why then
			pushLog("  触发原因: " .. s.why, "err")
		end
		if s.mode == "iso" and s.camType ~= "Scriptable" then
			pushLog("  iso 模式下 CameraType 必须是 Scriptable，否则 x 直接置 1", "warn")
		end
		if s.gated then
			pushLog(string.format("  门控: Place=%s，MoveWatch 与 ac.hb 都不会采样", tostring(s.place)), "info")
		end
		if s.watched then
			pushLog("  ★ Watched=true：服务端正在观察你，rv.cam 以 10Hz 上传 yaw/dist/fov/偏移", "err")
		end
	end

	local ok, r = runCommand("camera.info")
	if ok then
		pushLog("camera.info ← " .. tostring(r), "info")
	else
		pushLog("camera.info 无响应: " .. tostring(r), "warn")
	end
	local ok2, r2 = runCommand("fptp.state")
	if ok2 then
		pushLog("fptp.state ← " .. tostring(r2), "info")
	end
	pushLog("可切换档位: camera.zoom 1-N（纯客户端，等价于双指缩放）", "info")
end

---------------------------------------------------------------
-- 8.10 僵尸
---------------------------------------------------------------
function actions.scan()
	local list = collectZombies(true)
	local counts, order = {}, {}
	for _, m in ipairs(list) do
		local k = kindOf(m)
		if counts[k] == nil then
			counts[k] = 0
			table.insert(order, k)
		end
		counts[k] = counts[k] + 1
	end

	if #list == 0 then
		pushLog("未发现僵尸：HushLocal.Zombies 为空，可能不在对局内或尚未渲染", "warn")
		return
	end

	table.sort(order, function(a, b)
		return counts[a] > counts[b]
	end)

	local parts = {}
	for _, k in ipairs(order) do
		table.insert(parts, string.format("%s×%d", k, counts[k]))
	end
	pushLog(string.format("扫描到 %d 只僵尸：%s", #list, table.concat(parts, "  ")), "ok")
end

function actions.nearest()
	local m, d, ref = nearestZombie()
	if not m then
		pushLog("附近没有僵尸", "warn")
		return
	end

	local p = modelPosition(m)
	local dx, dz = p.X - ref.X, p.Z - ref.Z
	local dir
	if math.abs(dx) > math.abs(dz) then
		dir = dx > 0 and "东" or "西"
	else
		dir = dz > 0 and "南" or "北"
	end

	pushLog(string.format(
		"最近：%s  距离 %.1f 格  方位 %s  高度差 %+.1f",
		tostring(kindOf(m)), d, dir, p.Y - ref.Y
	), "ok")
end

---------------------------------------------------------------
-- 8.11 全量巡检
---------------------------------------------------------------
function actions.inspect()
	pushLog("——— 全量巡检开始 ———", "ok")

	local m = motion()
	if m then
		pushLog(string.format(
			"运动  速度 %.1f / WS %.1f → %.2f×   垂直 %+.1f   状态 %s   地面 %s",
			m.speed, m.ws, m.ratio, m.vy, m.state, m.floor
		), "info")
		pushLog(string.format(
			"归属  %s   锚定 %s   悬空 %s   平台站立 %s",
			m.owner, m.anchored and "是" or "否",
			m.onGround and "否" or "是",
			tostring(m.portal)
		), "info")
	end

	actions.violations()
	actions.movewatch()
	actions.net()

	local r = computeRisk(true)
	local tag = riskColor(r.score)
	pushLog(string.format(
		"风险评分 %d / 100（%s）", r.score, r.level
	), r.score >= 30 and "err" or "ok")
	if #r.reasons > 0 then
		pushLog("构成: " .. table.concat(r.reasons, " · "), "warn")
	else
		pushLog("没有命中任何检测特征", "ok")
	end

	actions.command("movewatch.state")
	pushLog("——— 巡检结束 ———", "ok")
end

---------------------------------------------------------------
-- 8.12 复制 / 清空
---------------------------------------------------------------
function actions.copy()
	local text = table.concat(plainLog, "\n")
	if #text == 0 then
		pushLog("日志为空，没有可复制内容", "warn")
		return
	end

	local fn = setclipboard or toclipboard or set_clipboard
	if not fn then
		pushLog("当前环境不支持写剪贴板", "err")
		return
	end
	if pcall(fn, text) then
		pushLog(string.format("已复制 %d 行到剪贴板", #plainLog), "ok")
	else
		pushLog("复制失败", "err")
	end
end

function actions.clear()
	for _, line in ipairs(logLines) do
		line:Destroy()
	end
	logLines = {}
	plainLog = {}
	pushLog("日志已清空", "info")
end

--=============================================================
-- 9) 生成按钮
--=============================================================
local buttonSpecs = {
	{ text = "违规读数", fn = actions.violations },
	{ text = "速度审计", fn = actions.speed },
	{ text = "墙体探针", fn = actions.wall },
	{ text = "卡模检测", fn = actions.overlap },
	{ text = "反作弊状态", fn = actions.movewatch },
	{ text = "网络余量", fn = actions.net },
	{ text = "命令表", fn = nil, toggle = "palette" },
	{ text = "武器状态", fn = actions.weapon },
	{ text = "射速校验", fn = actions.weaponRate },
	{ text = "渲染统计", fn = actions.render },
	{ text = "判定复刻", fn = actions.verdict },
	{ text = "战局信息", fn = actions.raid },
	{ text = "撤离点", fn = actions.extracts },
	{ text = "地图任务", fn = actions.mapInfo },
	{ text = "相机", fn = actions.camera },
	{ text = "僵尸透视", fn = nil, toggle = "esp" },
	{ text = "复制报告", fn = actions.copy },
	{ text = "清空日志", fn = actions.clear },
}

local espButton
local openPalette -- 由 9.5 节的浮层赋值（先声明，避免前向引用变成全局）

local function makeRow(index)
	local row = new("Frame", {
		Name = "Row" .. index,
		Size = UDim2.new(1, 0, 0, CONFIG.ButtonHeight),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = btnArea,
	})
	return row
end

local function makeActionButton(parent, spec, side)
	local btn = new("TextButton", {
		Name = "Btn_" .. spec.text,
		Size = UDim2.new(0.5, -3, 1, 0),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = THEME.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "",
		Parent = parent,
	})
	if side == "right" then
		btn.Position = UDim2.new(0.5, 3, 0, 0)
	end
	corner(btn, 9)
	local st = stroke(btn, THEME.Stroke, 1, 0.1)

	new("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = spec.text,
		TextSize = 11,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = btn,
	})

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = THEME.CardHover }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.14), { BackgroundColor3 = THEME.Card }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.06), { BackgroundColor3 = THEME.CardDown }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Card }):Play()
	end)

	btn.MouseButton1Click:Connect(function()
		if spec.toggle == "esp" then
			return
		end
		if spec.toggle == "palette" then
			if openPalette then
				openPalette()
			end
			return
		end
		if not spec.fn then
			return
		end
		local ok, err = pcall(spec.fn)
		if not ok then
			pushLog("执行失败: " .. tostring(err), "err")
		end
	end)

	return btn, st
end

for i, spec in ipairs(buttonSpecs) do
	local rowIndex = math.ceil(i / CONFIG.ButtonsPerRow)
	local row = btnArea:FindFirstChild("Row" .. rowIndex) or makeRow(rowIndex)
	local side = (i % CONFIG.ButtonsPerRow == 1) and "left" or "right"
	local btn, st = makeActionButton(row, spec, side)
	if spec.toggle == "esp" then
		espButton = btn
		espButton.MouseButton1Click:Connect(function()
			-- 三态：关 → 僵尸 → 僵尸+玩家 → 关
			if not espOn then
				espOn, espPlayers = true, false
			elseif not espPlayers then
				espPlayers = true
			else
				espOn, espPlayers = false, false
			end

			if espOn then
				updateEsp()
				pushLog(espPlayers and "透视已开启（僵尸 + 玩家，纯客户端）" or "僵尸透视已开启（纯客户端渲染）", "ok")
			else
				destroyEsp()
				pushLog("透视已关闭", "info")
			end

			local lbl = espButton:FindFirstChild("Label")
			if lbl then
				if espPlayers then
					lbl.Text = "透视：僵尸+人"
				elseif espOn then
					lbl.Text = "透视：僵尸"
				else
					lbl.Text = "僵尸透视"
				end
				lbl.TextColor3 = espOn and THEME.Green or THEME.Text
			end
			st.Color = espOn and THEME.Green or THEME.Stroke
		end)
	end
end

primaryBtn.MouseButton1Click:Connect(function()
	local ok, err = pcall(actions.inspect)
	if not ok then
		pushLog("巡检失败: " .. tostring(err), "err")
	end
end)

cmdRunBtn.MouseButton1Click:Connect(function()
	local ok, err = pcall(actions.command, cmdInput.Text)
	if not ok then
		pushLog("命令执行异常: " .. tostring(err), "err")
	end
	cmdInput.Text = ""
end)

cmdInput.FocusLost:Connect(function(enter)
	if enter then
		local ok, err = pcall(actions.command, cmdInput.Text)
		if not ok then
			pushLog("命令执行异常: " .. tostring(err), "err")
		end
		cmdInput.Text = ""
	end
end)

--=============================================================
-- 9.5) 命令表（浮层）
--      点一下就送进 HushClientCmd，结果显示在浮层底部，同时写日志。
--      只列只读命令 + 少数「只动客户端」的动作。
--=============================================================
local paletteOpen = false
local paletteModal, paletteStatus

local function paletteZebra(index)
	if index % 2 == 0 then
		return 0.55
	end
	return 0.35
end

local function buildPalette()
	local modal = new("Frame", {
		Name = "CmdPalette",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 22, 28),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		ClipsDescendants = true,
		Parent = inner,
	})
	corner(modal, 10)
	stroke(modal, THEME.Accent, 1, 0.45)

	local head = new("Frame", {
		Name = "Head",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = THEME.Header,
		BorderSizePixel = 0,
		ZIndex = 31,
		Parent = modal,
	})
	corner(head, 10)
	new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "命令表 · 点即执行",
		TextSize = 10.5,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 32,
		Parent = head,
	})

	local closeBtn = new("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(26, 20),
		Position = UDim2.new(1, -32, 0, 5),
		BackgroundColor3 = Color3.fromRGB(46, 52, 66),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "×",
		TextSize = 13,
		TextColor3 = THEME.Text,
		ZIndex = 32,
		Parent = head,
	})
	corner(closeBtn, 6)

	local list = new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -12, 1, -74),
		Position = UDim2.fromOffset(6, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(70, 78, 92),
		ScrollBarImageTransparency = 0.35,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ZIndex = 31,
		Parent = modal,
	})

	local curY = 2
	local rowIndex = 0

	local function addGroupLabel(text)
		local lbl = new("TextLabel", {
			Name = "G",
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(2, curY),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 8.5,
			TextColor3 = THEME.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 31,
			Parent = list,
		})
		curY = curY + 16
		return lbl
	end

	local function addRow(cmd, desc, tag)
		rowIndex = rowIndex + 1
		local row = new("TextButton", {
			Name = "C_" .. cmd,
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.fromOffset(2, curY),
			BackgroundColor3 = THEME.Card,
			BackgroundTransparency = paletteZebra(rowIndex),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 31,
			Parent = list,
		})
		corner(row, 6)

		new("TextLabel", {
			Name = "Cmd",
			Size = UDim2.new(0.55, -6, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = cmd,
			TextSize = 9.5,
			TextColor3 = (tag == "w") and THEME.Yellow or THEME.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 32,
			Parent = row,
		})
		new("TextLabel", {
			Name = "Desc",
			Size = UDim2.new(0.45, -10, 1, 0),
			Position = UDim2.new(0.55, 4, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = (tag == "w" and "写 · " or "") .. desc,
			TextSize = 8.5,
			TextColor3 = (tag == "w") and THEME.Yellow or THEME.SubText,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 32,
			Parent = row,
		})

		row.MouseButton1Click:Connect(function()
			if not paletteStatus then
				return
			end
			paletteStatus.Text = "→ " .. cmd
			paletteStatus.TextColor3 = THEME.SubText
			task.spawn(function()
				local ok, res = runCommand(cmd)
				local text = tostring(res)
				if #text > 120 then
					text = string.sub(text, 1, 120) .. "…"
				end
				paletteStatus.Text = (ok and "← " or "× ") .. text
				paletteStatus.TextColor3 = ok and THEME.Green or THEME.Red
				pushLog(string.format("%s → %s", cmd, tostring(res)), ok and "ok" or "err")
			end)
		end)

		curY = curY + 22 + 3
	end

	for _, g in ipairs(COMMAND_GROUPS) do
		addGroupLabel(g.name)
		for _, it in ipairs(g.items) do
			addRow(it[1], it[2], it[3])
		end
		curY = curY + 4
	end

	list.CanvasSize = UDim2.new(0, 0, 0, curY + 4)

	paletteStatus = new("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 1, -32),
		BackgroundColor3 = Color3.fromRGB(26, 29, 37),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Text = "选一条命令 · 黄字是只动客户端的写入",
		TextSize = 8.5,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
		Parent = modal,
	})
	corner(paletteStatus, 6)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = paletteStatus,
	})

	closeBtn.MouseButton1Click:Connect(function()
		modal.Visible = false
		paletteOpen = false
	end)

	return modal
end

paletteModal = buildPalette()

local function togglePalette(show)
	paletteOpen = show
	paletteModal.Visible = show
	if show and paletteStatus then
		paletteStatus.Text = "选一条命令 · 黄字是只动客户端的写入"
		paletteStatus.TextColor3 = THEME.SubText
	end
end

openPalette = function()
	togglePalette(not paletteOpen)
end

--=============================================================
-- 10) 窗口移动 / 缩放
--=============================================================
local winW, winH = CONFIG.Width, CONFIG.Height
local minimized = false
local userScale = 1
local pos = Vector2.new(
	math.floor((VIEW.X - CONFIG.Width) / 2),
	math.floor((VIEW.Y - CONFIG.Height) / 2)
)
local dragState, resizeState = nil, nil

local function viewport()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return VIEW
end

local function fitScale()
	local vp = viewport()
	local w, h = winW, winH
	if minimized then
		w, h = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	end
	local fit = math.min(1, (vp.Y - 24) / h, (vp.X - 24) / w)
	return math.clamp(fit * userScale, 0.5, 1.8)
end

local function clampPos(p)
	local vp = viewport()
	local s = uiScale.Scale
	local w = (minimized and CONFIG.MinimizedWidth or winW) * s
	local h = (minimized and CONFIG.MinimizedHeight or winH) * s
	return Vector2.new(
		math.clamp(p.X, 0, math.max(0, vp.X - w)),
		math.clamp(p.Y, 0, math.max(0, vp.Y - h))
	)
end

-- 日志区高度随窗口伸缩
local function layoutLog()
	local innerH = winH - CONFIG.HeaderHeight - CONFIG.BottomBarHeight - CONFIG.Pad * 2
	logPanel.Size = UDim2.new(1, 0, 0, math.max(26, innerH - (logLabelY + 15)))
end

local function apply()
	local w, h = winW, winH
	if minimized then
		w, h = CONFIG.MinimizedWidth, CONFIG.MinimizedHeight
	end
	uiScale.Scale = fitScale()
	window.Size = UDim2.fromOffset(w, h)
	pos = clampPos(pos)
	window.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
	layoutLog()
end

---------------------------------------------------------------
-- 拖动
---------------------------------------------------------------
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
		dragState = { start = inputXY(input), origin = pos }
	end)
end

bindDrag(header)
bindDrag(bottomBar)

---------------------------------------------------------------
-- 右下角拖拽改尺寸
---------------------------------------------------------------
local grip = new("TextButton", {
	Name = "Grip",
	Size = UDim2.fromOffset(22, 22),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 6,
	Parent = window,
})

local gripVisual = new("Frame", {
	Name = "GripVisual",
	Size = UDim2.fromOffset(24, 24),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, 0, 1, 0),
	Rotation = 45,
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 5,
	Parent = window,
})

grip.MouseEnter:Connect(function()
	TweenService:Create(gripVisual, TweenInfo.new(0.12), { BackgroundTransparency = 0.5 }):Play()
end)
grip.MouseLeave:Connect(function()
	TweenService:Create(gripVisual, TweenInfo.new(0.12), { BackgroundTransparency = 0.78 }):Play()
end)
grip.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if minimized then
		return
	end
	resizeState = { start = inputXY(input), w = winW, h = winH }
	dragState = nil
end)

UserInputService.InputChanged:Connect(function(input)
	if dragState then
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = inputXY(input) - dragState.start
		pos = clampPos(dragState.origin + delta)
		window.Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y))
		return
	end

	if resizeState then
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local vp = viewport()
		local s = math.max(uiScale.Scale, 0.01)
		local delta = (inputXY(input) - resizeState.start) / s
		local maxW = math.max(CONFIG.MinWidth, (vp.X - 16) / s)
		local maxH = math.max(CONFIG.MinHeight, (vp.Y - 16) / s)

		winW = math.clamp(resizeState.w + delta.X, CONFIG.MinWidth, maxW)
		winH = math.clamp(resizeState.h + delta.Y, CONFIG.MinHeight, maxH)
		winW = math.floor(winW)
		winH = math.floor(winH)
		apply()
		return
	end

	-- Ctrl + 滚轮微调缩放
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if not ctrl then
			return
		end
		userScale = math.clamp(userScale + (input.Position.Z > 0 and 0.05 or -0.05), 0.6, 1.8)
		apply()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragState = nil
		resizeState = nil
	end
end)

--=============================================================
-- 11) 最小化
--=============================================================
local compactParts = { header, body }

local function setMinimized(state)
	minimized = state
	window.ClipsDescendants = true

	for _, inst in ipairs(compactParts) do
		inst.Visible = not state
	end
	minimizedDot.Visible = state
	minimizedLabel.Visible = state
	minimizedBadge.Visible = state
	grip.Visible = not state
	gripVisual.Visible = not state

	apply()
end

minDot.MouseButton1Click:Connect(function()
	setMinimized(not minimized)
end)

minimizedLabel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		setMinimized(false)
	end
end)
minimizedDot.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		setMinimized(false)
	end
end)

---------------------------------------------------------------
-- 绿点循环缩放（保留缩放功能）
---------------------------------------------------------------
zoomDot.MouseButton1Click:Connect(function()
	local idx = 1
	for i, v in ipairs(ZOOM_STEPS) do
		if math.abs(userScale - v) < 0.001 then
			idx = i
			break
		end
	end
	userScale = ZOOM_STEPS[(idx % #ZOOM_STEPS) + 1]
	apply()
	pushLog(string.format("缩放 %d%%", math.floor(userScale * 100 + 0.5)), "info")
end)

---------------------------------------------------------------
-- 红点关闭
---------------------------------------------------------------
local closed = false
closeDot.MouseButton1Click:Connect(function()
	closed = true
	espOn = false
	destroyEsp()
	pcall(function()
		gui:Destroy()
	end)
end)

--=============================================================
-- 12) 主循环
--=============================================================
local frameCount, frameTime, fps = 0, 0, 60
local statTimer, espTimer = 0, 0
local airAccum = 0
local riskScore, riskLevel = 0, "—"
local lastRiskAt = 0

RunService.RenderStepped:Connect(function(dt)
	if closed or not gui.Parent then
		return
	end

	rainbow.Rotation = (rainbow.Rotation + dt * 42) % 360

	frameCount = frameCount + 1
	frameTime = frameTime + dt
	if frameTime >= 0.5 then
		fps = math.floor(frameCount / frameTime + 0.5)
		frameCount, frameTime = 0, 0
	end

	-- 悬空计时（用于飞天判定）——每 0.1s 采样一次，避免每帧 GetNetworkOwner
	airAccum = airAccum + dt
	if airAccum >= 0.1 then
		local step = airAccum
		airAccum = 0
		local mm = motion()
		if mm then
			if (not mm.onGround) and mm.md > 0.1 then
				airTime = airTime + step
			else
				airTime = 0
			end
			updateReplica(mm, step)
		else
			updateReplica(nil, step)
		end
	end

	statTimer = statTimer + dt
	if statTimer >= 0.5 then
		statTimer = 0

		-- 违规
		local v = violTick()
		local sTxt = "—"
		if v.found then
			sTxt = tostring(v.speed)
			statValues["速违"].Text = sTxt
			statValues["速违"].TextColor3 = v.speed > 0 and THEME.Red or THEME.Text
			statValues["墙违"].Text = tostring(v.wall)
			statValues["墙违"].TextColor3 = v.wall > 0 and THEME.Red or THEME.Text
		else
			statValues["速违"].Text = "—"
			statValues["墙违"].Text = "—"
			statValues["速违"].TextColor3 = THEME.SubText
			statValues["墙违"].TextColor3 = THEME.SubText
		end

		-- 风险（轻量，不带射线）
		local r = computeRisk(false)
		riskScore, riskLevel = r.score, r.level
		statValues["风险"].Text = tostring(r.score)
		statValues["风险"].TextColor3 = riskColor(r.score)

		-- 速比
		if r.m then
			statValues["速比"].Text = string.format("%.2f×", r.m.ratio)
			statValues["速比"].TextColor3 = (r.m.ratio > RISK.SpeedSoft) and THEME.Yellow or THEME.Text
		else
			statValues["速比"].Text = "—"
			statValues["速比"].TextColor3 = THEME.SubText
		end

		-- FPS
		statValues["FPS"].Text = tostring(fps)

		-- 延迟
		local ping = safe(function()
			return math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
		end)
		statValues["延迟"].Text = ping and (tostring(ping) .. "ms") or "—"
		if ping and ping > 180 then
			statValues["延迟"].TextColor3 = THEME.Red
		elseif ping and ping > 100 then
			statValues["延迟"].TextColor3 = THEME.Yellow
		else
			statValues["延迟"].TextColor3 = THEME.Text
		end

		-- 僵尸
		local zc = #collectZombies()
		statValues["僵尸"].Text = tostring(zc)
		statValues["僵尸"].TextColor3 = zc > 0 and THEME.Green or THEME.SubText

		-- 上报余量
		local mw = probeMoveWatch()
		if mw.module then
			local st = mw.module._state or {}
			local mx = tonumber(mw.module.SEND_MAX) or 4
			local used = tonumber(st.sends) or 0
			statValues["余量"].Text = string.format("%d/%d", math.max(0, mx - used), mx)
			statValues["余量"].TextColor3 = (used >= mx) and THEME.Red
				or (used > 0 and THEME.Yellow or THEME.Green)
			local badge = string.format("风险 %d", riskScore)
			minimizedBadge.Text = badge
			minimizedBadge.TextColor3 = riskColor(riskScore)
		else
			statValues["余量"].Text = "—"
			statValues["余量"].TextColor3 = THEME.SubText
			minimizedBadge.Text = string.format("风险 %d", riskScore)
			minimizedBadge.TextColor3 = riskColor(riskScore)
		end

		-- 判定条：复刻 MoveWatch 的实时结论
		local vline = verdictLine()
		verdictText.Text = vline
		if replica.report and #replica.report > 0 then
			verdictText.TextColor3 = THEME.Red
			verdictTag.TextColor3 = THEME.Red
		elseif #replica.soft > 0 then
			verdictText.TextColor3 = THEME.Yellow
			verdictTag.TextColor3 = THEME.Yellow
		else
			verdictText.TextColor3 = THEME.Green
			verdictTag.TextColor3 = THEME.Green
		end
		replica.verdict = vline

		-- 心跳条：AcClient 视角
		local acTxt, acColor, acGateTxt, acGateColor = acLine()
		acText.Text = acTxt
		acText.TextColor3 = acColor
		acGate.Text = acGateTxt
		acGate.TextColor3 = acGateColor

		-- 武器条：弹量 / 模式 / 瞄准偏差 / 实测射速
		local okW, errW = pcall(weaponLine)
		if not okW then
			wpnText.Text = "读取异常: " .. tostring(errW)
			wpnText.TextColor3 = THEME.Red
		end

		local watched = attrOf(LocalPlayer, "Watched") == true
		subtitleLabel.Text = string.format(
			"只读 · 风险 %d(%s) · 速违 %s 墙违 %s%s · %d%%",
			riskScore, riskLevel, sTxt,
			v.found and tostring(v.wall) or "—",
			watched and " · 被观察" or "",
			math.floor(userScale * 100 + 0.5)
		)

		-- 高危提醒（每 6s 最多一次）
		if riskScore >= 60 and os.clock() - lastRiskAt > 6 then
			lastRiskAt = os.clock()
			pushLog(string.format("风险 %d（%s）: %s", riskScore, riskLevel, table.concat(r.reasons, " · ")), "err")
		end
	end

	espTimer = espTimer + dt
	if espTimer >= 0.2 then
		espTimer = 0
		pcall(updateEsp)
	end
end)

--=============================================================
-- 13) 启动
--=============================================================
apply()

local function onViewportChanged()
	apply()
end

if workspace.CurrentCamera then
	pcall(function()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	end)
end

pushLog("Hush 合规观测台 v5 已加载（只读）", "ok")
pushLog("通道①: mv.stuck（MoveWatch，1.5s stuck 后每 5s 采样）", "info")
pushLog("通道②: ac.hb（AcClient，每 5s 一包 fd/cd/x/m）  通道③: rv.cam（Watched 时 10Hz）", "info")
pushLog("武器侧: wantYaw vs AimYaw 偏角 > 4° / shotSeq 实测 RPM > 1200 记异常", "info")
pushLog(string.format("命令表 %d 条，点「命令表」直接执行", #KNOWN_CMD), "info")

local boot = readViolations()
if boot.found then
	violBoot = { speed = boot.speed, wall = boot.wall, rescue = boot.rescue }
	violSeen.speed, violSeen.wall, violSeen.rescue = boot.speed, boot.wall, boot.rescue
	pushLog(string.format(
		"基线：速度违规 %d  穿墙违规 %d  纠正 %d", boot.speed, boot.wall, boot.rescue
	), (boot.speed + boot.wall) > 0 and "warn" or "ok")
else
	pushLog("未读到违规计数属性（可能不在对局内）", "warn")
end

local mwBoot = probeMoveWatch(true)
if mwBoot.module then
	pushLog("MoveWatch 已连接：" .. tostring(mwBoot.why), mwBoot.live and "ok" or "warn")
	local st = mwBoot.module._state or {}
	pushLog(string.format(
		"  采样 %d  上报 %d  自愈 %d", tonumber(st.looks) or 0,
		tonumber(st.reports) or 0, tonumber(st.heals) or 0
	), "info")
else
	pushLog("MoveWatch 不可读：" .. tostring(mwBoot.why), "warn")
end

if attrOf(LocalPlayer, "ClientBooted") == true then
	pushLog("HushClient 已 boot，命令总线可用", "ok")
else
	pushLog("HushClient 未 boot：命令总线可能无响应", "warn")
end

local cerr = attrOf(LocalPlayer, "ClientError")
if type(cerr) == "string" and cerr ~= "" then
	pushLog("客户端报错: " .. cerr, "err")
end

local z0 = #collectZombies(true)
if z0 > 0 then
	pushLog(string.format("场景内僵尸 %d 只，点「僵尸透视」或「全量巡检」", z0), "info")
end
