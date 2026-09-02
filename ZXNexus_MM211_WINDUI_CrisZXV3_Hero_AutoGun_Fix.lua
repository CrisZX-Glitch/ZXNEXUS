-- Защита от повторной загрузки
if getgenv().ZXNexusLoaded then
    warn("⚠ ZXNexus is already running!")
    return
end
getgenv().ZXNexusLoaded = true

-- Сервисы
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TeleportService = game:GetService("TeleportService")
local Stats = game:GetService("Stats")

-- Player
local player = Players.LocalPlayer

-- Tester whitelist
local TESTERS = {
    ["cris_gamesrivals000"] = true,
    ["Denny123841"] = true,
    ["meisn468"] = true,
}

if not TESTERS[player.Name] then
    player:Kick("This script is only for testers.")
    return
end

-- Конфигурация
local CONFIG = {
	MAIN_COLOR = Color3.fromRGB(37, 99, 235), -- WindUI Midnight accent
	DEFAULT_WALK_SPEED = 16,
	DEFAULT_JUMP_POWER = 50,
	VALID_TARGET_ROLES = { "Sheriff", "Hero", "Innocent" },
	TOGGLE_SPACING = 52,
	BUTTON_HEIGHT = 48,
	SPACING = 8
}

-- Глобальные состояния
local FLOATING_STYLES = {
    ShootMurderer = {Size = 184, Height = 82, Shape = "Rounded"},
    FakeBombJump = {Size = 64, Height = 64, Shape = "Circle"},
    GrabGun = {Size = 64, Height = 64, Shape = "Circle"},
}

local function floatingCorner(shape, size)
    if shape == "Circle" then return UDim.new(1, 0) end
    if shape == "Pill" then return UDim.new(0, math.floor((size or 64) / 2)) end
    if shape == "Rounded" then return UDim.new(0, 12) end
    return UDim.new(0, 2)
end

local function applyFloatingShape(frame, shape, size)
    if not frame then return end
    local corner = frame:FindFirstChildOfClass("UICorner")
    if not corner then corner = Instance.new("UICorner"); corner.Parent = frame end
    corner.CornerRadius = floatingCorner(shape, size)
    frame.Rotation = shape == "Diamond" and 45 or 0
end
local AIMLOCK = {
    Enabled = false,
    Connection = nil,
}
local HITBOX_ESP = {
    Enabled = false,
    Size = 8,
    Objects = {},
}

local DROP_ESP = {
    Gun = false,
    Trap = false,
    Objects = {},
}

local SHOOT_CONFIG = {
    VerticalMultiplier = 0.50,
    HorizontalMultiplier = 0.75,
    Simulations = 3,
    Interval = 0.03,
    OffsetX = 0,
    OffsetY = 0,
    OffsetZ = 0,
    PredictLag = true,
    PrioritizePing = true,
    PredictJump = true,
    SharpShooter = true,
}
local YARHM_ANTI_FLING = {
    Enabled = false,
    Detection = nil,
    Neutralizer = nil,
    LastPos = Vector3.zero,
}
local STATES = {
	AutoFarm = {
		Enabled = false,
		Farming = false,
		BagFull = false,
		Resetting = false,
		StartPosition = nil
	},
	KillAll = {
		Enabled = false,
		AttackDelay = 0.5
	},
	Movement = {
		SpeedWalk = { Enabled = false, Value = CONFIG.DEFAULT_WALK_SPEED },
		JumpPower = { Enabled = false, Value = CONFIG.DEFAULT_JUMP_POWER }
	},
	ShootMurderer = {
		ButtonData = nil,
		Position = nil,
		Locked = false
	},
	FakeBombJump = {
		ButtonData = nil,
		Position = nil,
		Locked = false
	},
	GrabGun = {
		ButtonData = nil,
		Position = nil,
		Locked = false
	},
	GUIVisible = true,
	Performance = {
		Enabled = false,
		Overlay = nil,
		Position = nil
	},
	AntiFling = {
		Enabled = false,
		Connections = nil
	},
	MuteRadio = {
		Enabled = false
	}
}

-- Статистика фарма
local FARMING_STATS = {
	CoinsCollected = 0,
	StartTime = 0,
	IsRunning = false
}

-- RemoteEvents кэш
local REMOTE_EVENTS = {
	CoinCollected = nil,
	RoundStart = nil,
	RoundEnd = nil
}

-- Градиенты для обводки
local STROKE_GRADIENT = {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONFIG.MAIN_COLOR),
		ColorSequenceKeypoint.new(0.3, CONFIG.MAIN_COLOR),
		ColorSequenceKeypoint.new(0.7, CONFIG.MAIN_COLOR),
		ColorSequenceKeypoint.new(1, CONFIG.MAIN_COLOR)
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.8, 0.8),
		NumberSequenceKeypoint.new(1, 1)
	})
}

-- UI элементы
local UI_ELEMENTS = {
	ScreenGui = nil,
	OpenCloseGui = nil,
	MainFrame = nil,
	TabButtonsContainer = nil,
	ContentFrame = nil,
	Tabs = {},
	ToggleCallbacks = {},
	ToggleStates = {}
}

-- Очередь уведомлений
local ActiveNotifications = {} -- legacy, never displayed
local NOTIFICATION_HEIGHT = 85

-- Утилитарные функции
local UTILS = {}

function UTILS.playClickSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://138656262630730"
	sound.Volume = 0.7
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

function UTILS.showNotification(title, message, duration)
    -- Legacy ZXNexus notification UI intentionally disabled.
    -- WindUI is the only visible notification system.
end

function UTILS.createInstance(className, parent, properties)
	local obj = Instance.new(className, parent)
	for prop, value in pairs(properties) do
		obj[prop] = value
	end
	return obj
end

function UTILS.safeDestroy(obj)
	if obj and obj.Parent then
		obj:Destroy()
	end
end

function UTILS.secondsToMinutes(seconds)
	if seconds == -1 then return "" end
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%dm %ds", minutes, remainingSeconds)
end

function UTILS.getHRP()
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		return player.Character.HumanoidRootPart
	end
	return nil
end

function UTILS.addSpacer(parent, positionY, height)
	return UTILS.createInstance("Frame", parent, {
		Name = "Spacer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		Position = UDim2.new(0, 0, 0, positionY)
	})
end

function UTILS.updateCanvasSize(scrollingFrame, contentFrame)
	if not scrollingFrame or not contentFrame or not scrollingFrame:IsA("ScrollingFrame") then
		return
	end
	
	local totalHeight = 0
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			totalHeight = totalHeight + child.AbsoluteSize.Y
		end
	end
	
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 100)
	contentFrame.Size = UDim2.new(1, 0, 0, totalHeight + 80)
end

function UTILS.updateTabButtonsContainerSize(container)
	local totalHeight = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			totalHeight = totalHeight + child.AbsoluteSize.Y + 8
		end
	end
	
	container.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

function UTILS.joinAnotherServer()
    -- Server hop: find another public server for the same place.
    local HttpService = game:GetService("HttpService")
    local currentJobId = game.JobId
    local cursor = ""
    local candidates = {}

    for _ = 1, 3 do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"):format(
            game.PlaceId,
            cursor ~= "" and ("&cursor=" .. HttpService:UrlEncode(cursor)) or ""
        )
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then break end

        local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not okJson or not data then break end

        for _, server in ipairs(data.data or {}) do
            if server.id ~= currentJobId and (server.playing or 0) < (server.maxPlayers or 0) then
                table.insert(candidates, server.id)
            end
        end

        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
    end

    if #candidates > 0 then
        local target = candidates[math.random(1, #candidates)]
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target, player)
        end)
    else
        pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
    end
end

function UTILS.rejoinServer()
    -- Rejoin the exact current public server.
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)
end

function UTILS.createStaticStroke(frame)
	local stroke = UTILS.createInstance("UIStroke", frame, {
		Thickness = 2,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	})
	
	local gradient = UTILS.createInstance("UIGradient", stroke, {
		Color = STROKE_GRADIENT.Color,
		Transparency = STROKE_GRADIENT.Transparency,
		Rotation = 0
	})
	
	return stroke
end

function UTILS.createWithStaticStroke(className, parent, properties)
	local obj = UTILS.createInstance(className, parent, properties)
	if className == "Frame" or className == "TextButton" or className == "ScrollingFrame" then
		UTILS.createStaticStroke(obj)
	end
	return obj
end

-- ESP и Highlight система
local ESP_SYSTEM = {}

ESP_SYSTEM.ESP_STATES = {
	ESPName = false,
	MurdererName = true,
	SheriffName = true,
	HeroName = true,
	InnocentName = true
}

ESP_SYSTEM.ESP_HIGHLIGHT_STATES = {
	ESPHighlight = false,
	ESPHighlightMurderer = true,
	ESPHighlightSheriff = true,
	ESPHighlightHero = true,
	ESPHighlightInnocent = true
}

-- ESP Line состояния (обновленная логика)
ESP_SYSTEM.ESP_LINE_STATES = {
    ESPLine = false,           -- главный включатель линий
    MurdererLine = true,       -- линии для убийцы
    SheriffLine = true,        -- линии для шерифа
    HeroLine = true,           -- линии для героя
    InnocentLine = true,       -- линии для невинных
    LineThickness = 1.4,       -- толщина линии
    LineTransparency = 1       -- прозрачность линии (1 = видимо, 0 = не видимо)
}

ESP_SYSTEM.ROLE_COLORS = {
	Murderer = Color3.fromRGB(255, 0, 0),
	Sheriff = Color3.fromRGB(0, 0, 255),
	Hero = Color3.fromRGB(255, 255, 0),
	Innocent = Color3.fromRGB(0, 255, 0)
}

ESP_SYSTEM.billboards = {}
ESP_SYSTEM.currentRoles = {}
ESP_SYSTEM.Camera = workspace.CurrentCamera
ESP_SYSTEM.LineDrawings = {}

ESP_SYSTEM.MIN_DISTANCE = 5
ESP_SYSTEM.MAX_DISTANCE = 100
ESP_SYSTEM.MIN_SIZE = UDim2.new(0, 50, 0, 12)
ESP_SYSTEM.MAX_SIZE = UDim2.new(0, 200, 0, 50)
ESP_SYSTEM.MIN_TEXT_SIZE = 8
ESP_SYSTEM.MAX_TEXT_SIZE = 18

local cachedRolesData = {}
local lastRoleUpdate = 0
local UPDATE_INTERVAL = 0.5
local lineConnections = {} -- Для хранения соединений линий

function ESP_SYSTEM.IsPlayerOnScreen(targetPlayer)
    if not ESP_SYSTEM.Camera then return true end
    
    local character = targetPlayer.Character
    if not character then return false end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    local screenPoint, onScreen = ESP_SYSTEM.Camera:WorldToViewportPoint(humanoidRootPart.Position)
    
    if onScreen then
        local viewportSize = ESP_SYSTEM.Camera.ViewportSize
        if screenPoint.X >= -50 and screenPoint.X <= viewportSize.X + 50 and
           screenPoint.Y >= -50 and screenPoint.Y <= viewportSize.Y + 50 then
            return true
        end
    end
    
    return false
end

function ESP_SYSTEM.IsPlayerVisible(targetPlayer)
    if not ESP_SYSTEM.IsPlayerOnScreen(targetPlayer) then
        return false
    end
    return true
end

function ESP_SYSTEM.GetRolesData()
	local currentTime = tick()
	if currentTime - lastRoleUpdate < UPDATE_INTERVAL then
		return cachedRolesData
	end
	
	local success, rolesData = pcall(function()
		local getPlayerData = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
		if getPlayerData and getPlayerData:IsA("RemoteFunction") then
			return getPlayerData:InvokeServer()
		end
		return {}
	end)
	
	if success and rolesData then
		cachedRolesData = rolesData
		lastRoleUpdate = currentTime
	end
	
	return cachedRolesData
end

function ESP_SYSTEM.GetPlayerDataEntry(targetPlayer, rolesData)
    if not rolesData or not targetPlayer then return nil end

    -- MM2 can expose the table keyed by Name or UserId depending on the update.
    local playerData = rolesData[targetPlayer.Name]
    if playerData == nil then playerData = rolesData[tostring(targetPlayer.UserId)] end
    if playerData == nil then playerData = rolesData[targetPlayer.UserId] end
    return playerData
end

function ESP_SYSTEM.NormalizeRole(role)
    if typeof(role) ~= "string" then return nil end
    local r = string.lower(role):gsub("%s+", "")
    if r == "murderer" or r == "murder" then return "Murderer" end
    if r == "sheriff" then return "Sheriff" end
    if r == "hero" then return "Hero" end
    if r == "innocent" then return "Innocent" end
    return nil
end

function ESP_SYSTEM.IsAlive(targetPlayer, rolesData)
    local playerData = ESP_SYSTEM.GetPlayerDataEntry(targetPlayer, rolesData)
    if not playerData then
        local hum = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        return hum ~= nil and hum.Health > 0
    end
    return playerData.Killed ~= true and playerData.Dead ~= true
end

function ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
    if not rolesData then return nil, false end

    local playerData = ESP_SYSTEM.GetPlayerDataEntry(targetPlayer, rolesData)
    if not playerData then return nil, false end

    -- Accept the common role field variants used by MM2 updates.
    local role = ESP_SYSTEM.NormalizeRole(
        playerData.Role or playerData.role or playerData.RoleName or playerData.roleName or playerData.TeamRole
    )

    return role, ESP_SYSTEM.IsAlive(targetPlayer, rolesData)
end

function ESP_SYSTEM.GetPlayerColorByRole(role, isAlive)
	if not isAlive then
		return Color3.fromRGB(150, 150, 150)
	end
	
	if role == "Murderer" then
		return Color3.fromRGB(255, 0, 0)
	elseif role == "Sheriff" then
		return Color3.fromRGB(0, 0, 255)
	elseif role == "Hero" then
		return Color3.fromRGB(255, 255, 0)
	elseif role == "Innocent" then
		return Color3.fromRGB(0, 255, 0)
	else
		return Color3.fromRGB(255, 255, 255)
	end
end

-- Функция проверки, нужно ли показывать линию для данной роли
function ESP_SYSTEM.ShouldShowLineForRole(role)
	if not ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
		return false
	end
	
	if role == "Murderer" and ESP_SYSTEM.ESP_LINE_STATES.MurdererLine then
		return true
	elseif role == "Sheriff" and ESP_SYSTEM.ESP_LINE_STATES.SheriffLine then
		return true
	elseif role == "Hero" and ESP_SYSTEM.ESP_LINE_STATES.HeroLine then
		return true
	elseif role == "Innocent" and ESP_SYSTEM.ESP_LINE_STATES.InnocentLine then
		return true
	end
	return false
end

-- Надёжный tracer: обычные ScreenGui/Frame, без Drawing API.
local TRACER_GUI
local function ensureTracerGui()
    if TRACER_GUI and TRACER_GUI.Parent then return TRACER_GUI end
    TRACER_GUI = Instance.new("ScreenGui")
    TRACER_GUI.Name = "ZXNexusTracerGui"
    TRACER_GUI.ResetOnSpawn = false
    TRACER_GUI.IgnoreGuiInset = true
    TRACER_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Global
    TRACER_GUI.DisplayOrder = 999
    TRACER_GUI.Parent = CoreGui
    return TRACER_GUI
end

function ESP_SYSTEM.CreateLineDrawing()
    local frame = Instance.new("Frame")
    frame.Name = "Tracer"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.BackgroundTransparency = 0
    frame.Visible = false
    frame.ZIndex = 999
    frame.Parent = ensureTracerGui()
    return frame
end

function ESP_SYSTEM.GetLineForPlayer(playerName)
    local drawing = ESP_SYSTEM.LineDrawings[playerName]
    if not drawing or not drawing.Parent then
        drawing = ESP_SYSTEM.CreateLineDrawing()
        ESP_SYSTEM.LineDrawings[playerName] = drawing
    end
    return drawing
end

function ESP_SYSTEM.RemoveLineForPlayer(playerName)
    local drawing = ESP_SYSTEM.LineDrawings[playerName]
    if drawing then
        drawing:Destroy()
        ESP_SYSTEM.LineDrawings[playerName] = nil
    end
end

function ESP_SYSTEM.ClearAllLines()
    for playerName, drawing in pairs(ESP_SYSTEM.LineDrawings) do
        if drawing then pcall(function() drawing:Destroy() end) end
    end
    ESP_SYSTEM.LineDrawings = {}
end

function ESP_SYSTEM.UpdateCamera()
    ESP_SYSTEM.Camera = workspace.CurrentCamera
end

function ESP_SYSTEM.StopAllLines()
    for _, conn in ipairs(lineConnections) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
    lineConnections = {}
    ESP_SYSTEM.ClearAllLines()
end

function ESP_SYSTEM.InitializePlayerLines(targetPlayer)
    if not targetPlayer or targetPlayer == player then return nil end
    local line = ESP_SYSTEM.GetLineForPlayer(targetPlayer.Name)
    local cachedRole, cachedIsAlive = nil, false
    local lastRoleFetch = 0

    local connection
    connection = RunService.RenderStepped:Connect(function()
        if not ESP_SYSTEM.ESP_LINE_STATES.ESPLine or not targetPlayer.Parent then
            line.Visible = false
            if not targetPlayer.Parent then
                pcall(function() connection:Disconnect() end)
                ESP_SYSTEM.RemoveLineForPlayer(targetPlayer.Name)
            end
            return
        end

        ESP_SYSTEM.UpdateCamera()
        local char = targetPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or not ESP_SYSTEM.Camera then
            line.Visible = false
            return
        end

        if tick() - lastRoleFetch >= 0.25 then
            local rolesData = ESP_SYSTEM.GetRolesData()
            cachedRole, cachedIsAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
            lastRoleFetch = tick()
        end

        if not cachedIsAlive or not ESP_SYSTEM.ShouldShowLineForRole(cachedRole) then
            line.Visible = false
            return
        end

        local screenPos, onScreen = ESP_SYSTEM.Camera:WorldToViewportPoint(hrp.Position)
        local vp = ESP_SYSTEM.Camera.ViewportSize
        local from = Vector2.new(vp.X / 2, vp.Y / 2)
        local to = Vector2.new(screenPos.X, screenPos.Y)
        -- Tracer is visible only while the target is inside the camera viewport.
        if not onScreen or screenPos.Z < 0
            or screenPos.X < 0 or screenPos.X > vp.X
            or screenPos.Y < 0 or screenPos.Y > vp.Y then
            line.Visible = false
            return
        end
        to = Vector2.new(math.clamp(to.X, 4, vp.X - 4), math.clamp(to.Y, 4, vp.Y - 4))
        local delta = to - from
        local length = delta.Magnitude
        if length < 2 then
            line.Visible = false
            return
        end

        line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
        line.Size = UDim2.fromOffset(length, math.max(1, ESP_SYSTEM.ESP_LINE_STATES.LineThickness))
        line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        line.BackgroundColor3 = ESP_SYSTEM.GetPlayerColorByRole(cachedRole, cachedIsAlive)
        line.BackgroundTransparency = 1 - ESP_SYSTEM.ESP_LINE_STATES.LineTransparency
        line.Visible = true
    end)

    return connection
end

-- Старт всех линий
function ESP_SYSTEM.StartAllLines()
    ESP_SYSTEM.StopAllLines()
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local conn = ESP_SYSTEM.InitializePlayerLines(targetPlayer)
            table.insert(lineConnections, conn)
        end
    end
end

function ESP_SYSTEM.updatePlayerBillboard(targetPlayer, role, isAlive)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local distance = (ESP_SYSTEM.Camera.CFrame.Position - humanoidRootPart.Position).Magnitude
	local billboard = humanoidRootPart:FindFirstChild("PlayerBillboard")
	
	local color
	if role == "Murderer" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Murderer
	elseif role == "Sheriff" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Sheriff
	elseif role == "Hero" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Hero
	elseif role == "Innocent" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Innocent
	else
		color = Color3.fromRGB(255, 255, 255)
	end
	
	if billboard then
		local textLabel = billboard:FindFirstChild("PlayerName")
		if textLabel then
			textLabel.TextColor3 = color
			textLabel.Text = targetPlayer.Name
		end
	else
		billboard = Instance.new("BillboardGui")
		billboard.Name = "PlayerBillboard"
		billboard.Adornee = humanoidRootPart
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.new(0, 100, 0, 30)
		billboard.StudsOffset = Vector3.new(0, 2.5, 0)
		billboard.ResetOnSpawn = false
		
		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "PlayerName"
		textLabel.Size = UDim2.new(1, 0, 1, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = targetPlayer.Name
		textLabel.TextColor3 = color
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextSize = 14
		textLabel.TextStrokeTransparency = 0.5
		textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		textLabel.Parent = billboard
		
		billboard.Parent = humanoidRootPart
		ESP_SYSTEM.billboards[targetPlayer] = billboard
	end
end

function ESP_SYSTEM.removePlayerBillboard(targetPlayer)
	if targetPlayer == player then return end
	
	if ESP_SYSTEM.billboards[targetPlayer] then
		ESP_SYSTEM.billboards[targetPlayer]:Destroy()
		ESP_SYSTEM.billboards[targetPlayer] = nil
	end
	
	local character = targetPlayer.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local billboard = humanoidRootPart:FindFirstChild("PlayerBillboard")
			if billboard then
				billboard:Destroy()
			end
		end
	end
end

function ESP_SYSTEM.clearAllESP()
	for targetPlayer, billboard in pairs(ESP_SYSTEM.billboards) do
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	 end
	ESP_SYSTEM.billboards = {}
end

function ESP_SYSTEM.updatePlayerHighlight(targetPlayer, role, isAlive)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	local highlight = character:FindFirstChild("PlayerHighlight")
	
	if not highlight or not highlight:IsA("Highlight") then
		if highlight then
			highlight:Destroy()
		end
		
		highlight = Instance.new("Highlight")
		highlight.Name = "PlayerHighlight"
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0.4
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.Parent = character
	end
	
	local color
	if role == "Murderer" and isAlive then
		color = Color3.fromRGB(255, 0, 0)
	elseif role == "Sheriff" and isAlive then
		color = Color3.fromRGB(0, 0, 255)
	elseif role == "Hero" and isAlive then
		color = Color3.fromRGB(255, 255, 0)
	elseif role == "Innocent" and isAlive then
		color = Color3.fromRGB(0, 255, 0)
	else
		color = Color3.fromRGB(255, 255, 255)
	end
	
	highlight.FillColor = color
end

function ESP_SYSTEM.removePlayerHighlight(targetPlayer)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if character then
		local highlight = character:FindFirstChild("PlayerHighlight")
		if highlight and highlight:IsA("Highlight") then
			highlight:Destroy()
		end
	end
end

function ESP_SYSTEM.clearAllHighlights()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
		end
	end
end

function ESP_SYSTEM.updateESP()
	if not ESP_SYSTEM.ESP_STATES.ESPName then
		ESP_SYSTEM.clearAllESP()
		return
	end
	
	local rolesData = ESP_SYSTEM.GetRolesData()
	
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == player then continue end
		
		local character = targetPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		
		if not character or not humanoidRootPart then
			ESP_SYSTEM.removePlayerBillboard(targetPlayer)
			continue
		end
		
		local role, isAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
		
		local shouldShow = false
		if role == "Murderer" and ESP_SYSTEM.ESP_STATES.MurdererName then
			shouldShow = true
		elseif role == "Sheriff" and ESP_SYSTEM.ESP_STATES.SheriffName then
			shouldShow = true
		elseif role == "Hero" and ESP_SYSTEM.ESP_STATES.HeroName then
			shouldShow = true
		elseif role == "Innocent" and ESP_SYSTEM.ESP_STATES.InnocentName then
			shouldShow = true
		elseif not role then
			shouldShow = true
		end
		
		if shouldShow then
			ESP_SYSTEM.updatePlayerBillboard(targetPlayer, role, isAlive)
		else
			ESP_SYSTEM.removePlayerBillboard(targetPlayer)
		end
	end
end

function ESP_SYSTEM.updateHighlights()
	if not ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
		ESP_SYSTEM.clearAllHighlights()
		return
	end
	
	local rolesData = ESP_SYSTEM.GetRolesData()
	
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == player then continue end
		
		local character = targetPlayer.Character
		if not character then 
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
			continue
		end
		
		local role, isAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
		
		local shouldShow = false
		if role == "Murderer" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightMurderer then
			shouldShow = true
		elseif role == "Sheriff" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightSheriff then
			shouldShow = true
		elseif role == "Hero" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightHero then
			shouldShow = true
		elseif role == "Innocent" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightInnocent then
			shouldShow = true
		end
		
		if shouldShow then
			ESP_SYSTEM.updatePlayerHighlight(targetPlayer, role, isAlive)
		else
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
		end
	end
end

function ESP_SYSTEM.initializePlayer(targetPlayer)
	if targetPlayer == player then return end
	
	local function onCharacterAdded(character)
		task.wait(0.5)
		ESP_SYSTEM.updateESP()
	end
	
	local function onCharacterRemoving()
		ESP_SYSTEM.removePlayerBillboard(targetPlayer)
		ESP_SYSTEM.removePlayerHighlight(targetPlayer)
	end
	
	targetPlayer.CharacterAdded:Connect(onCharacterAdded)
	targetPlayer.CharacterRemoving:Connect(onCharacterRemoving)
	
	if targetPlayer.Character then
		task.spawn(onCharacterAdded, targetPlayer.Character)
	end
end

-- Anti-Fling система
local ANTI_FLING = {}

function ANTI_FLING.enable()
    if STATES.AntiFling.Enabled then
        return
    end
    
    STATES.AntiFling.Enabled = true
    
    local localPlayer = player
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    
    local function disableAllPlayersParts()
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if targetPlayer ~= localPlayer and targetPlayer.Character then
                for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") and not part.Anchored then
                        part.CanCollide = false
                    end
                end
            end
        end
    end
    
    disableAllPlayersParts()
    
    local antiFlingTask = nil
    antiFlingTask = task.spawn(function()
        while STATES.AntiFling.Enabled do
            task.wait(0.3)
            
            if not character or character.Parent == nil then
                character = localPlayer.Character
                if character then
                    humanoid = character:FindFirstChild("Humanoid")
                    if humanoid then
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                    end
                end
            end
            
            disableAllPlayersParts()
        end
    end)
    
    local function onPlayerAdded(targetPlayer)
        if targetPlayer ~= localPlayer then
            targetPlayer.CharacterAdded:Connect(function(char)
                task.wait(0.2)
                if STATES.AntiFling.Enabled then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") and not part.Anchored then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end
    end
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        onPlayerAdded(targetPlayer)
    end
    
    local playerAddedConnection
    playerAddedConnection = Players.PlayerAdded:Connect(onPlayerAdded)
    
    local characterAddedConnection
    characterAddedConnection = localPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = character:FindFirstChild("Humanoid")
        if humanoid and STATES.AntiFling.Enabled then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        end
        task.wait(0.2)
        if STATES.AntiFling.Enabled then
            disableAllPlayersParts()
        end
    end)
    
    STATES.AntiFling.Connections = {
        task = antiFlingTask,
        playerAdded = playerAddedConnection,
        characterAdded = characterAddedConnection
    }
end

function ANTI_FLING.disable()
    if not STATES.AntiFling.Enabled then
        return
    end
    
    STATES.AntiFling.Enabled = false
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.task then
        task.cancel(STATES.AntiFling.Connections.task)
    end
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.playerAdded then
        STATES.AntiFling.Connections.playerAdded:Disconnect()
    end
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.characterAdded then
        STATES.AntiFling.Connections.characterAdded:Disconnect()
    end
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character then
            for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
    
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        end
    end
    
    STATES.AntiFling.Connections = nil
end

-- Функция для Mute Radio
local function toggleMuteRadio(value)
    STATES.MuteRadio.Enabled = value
    
    local function muteRadioSounds()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Sound") and obj.Name == "RadioSound" then
                if value then
                    obj.Volume = 0
                else
                    obj.Volume = 1
                end
            end
        end
    end
    
    muteRadioSounds()
    
    local connection
    connection = workspace.DescendantAdded:Connect(function(descendant)
        if STATES.MuteRadio.Enabled and descendant:IsA("Sound") and descendant.Name == "RadioSound" then
            descendant.Volume = 0
        end
    end)
    
    if value then
        if not STATES.MuteRadio.Connection then
            STATES.MuteRadio.Connection = connection
        end
    else
        if STATES.MuteRadio.Connection then
            STATES.MuteRadio.Connection:Disconnect()
            STATES.MuteRadio.Connection = nil
        end
    end
end

-- Фарминг системы
local FARMING = {}

function FARMING.getNearestCoin()
	local root = UTILS.getHRP()
	if not root then return nil, math.huge end
	
	local nearestCoin = nil
	local nearestDistance = math.huge
	
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:FindFirstChild("CoinContainer") then
			for _, coin in ipairs(obj.CoinContainer:GetChildren()) do
				if coin:IsA("BasePart") and coin:GetAttribute("CoinID") == "Coin" and coin:FindFirstChild("TouchInterest") then
					local distance = (root.Position - coin.Position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestCoin = coin
					end
				end
			end
		end
	end
	
	return nearestCoin, nearestDistance
end

local farmingLoopActive = true

function FARMING.startFarmingLoop()
	task.spawn(function()
		while farmingLoopActive do
			local waitTime = 0.1
			
			if STATES.AutoFarm.Enabled and STATES.AutoFarm.Farming and not STATES.AutoFarm.BagFull then
				local coin, dist = FARMING.getNearestCoin()
				local hrp = UTILS.getHRP()
				
				if coin and hrp then
					if dist > 150 then
						hrp.CFrame = coin.CFrame
					else
						local tween = TweenService:Create(hrp, TweenInfo.new(dist / 25, Enum.EasingStyle.Linear), {CFrame = coin.CFrame})
						tween:Play()
						
						local startTime = tick()
						repeat
							task.wait()
							if tick() - startTime > 5 then break end
						until not coin:FindFirstChild("TouchInterest") or not STATES.AutoFarm.Farming or not STATES.AutoFarm.Enabled
						
						if tween then tween:Cancel() end
					end
				end
			elseif STATES.AutoFarm.Enabled then
				waitTime = 0.5
			else
				waitTime = 1
			end
			
			task.wait(waitTime)
		end
	end)
end

function FARMING.autoReset()
	if STATES.AutoFarm.Enabled and STATES.AutoFarm.BagFull and not STATES.AutoFarm.Resetting then
		STATES.AutoFarm.Resetting = true
		
		local hrp = UTILS.getHRP()
		if hrp and STATES.AutoFarm.StartPosition then
			local tween = TweenService:Create(hrp, TweenInfo.new(2, Enum.EasingStyle.Linear), {CFrame = STATES.AutoFarm.StartPosition})
			tween:Play()
			tween.Completed:Wait()
		end
		
		task.wait(0.5)
		
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid.Health = 0
		end
		
		player.CharacterAdded:Wait()
		task.wait(1.5)
		
		STATES.AutoFarm.Resetting = false
		STATES.AutoFarm.BagFull = false
	end
end

-- Kill All системы
local KILL_ALL = {}

function KILL_ALL.getPlayerRoleFromServer(targetPlayer)
	local getPlayerDataRemote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
	if getPlayerDataRemote and getPlayerDataRemote:IsA("RemoteFunction") then
		local playerData = getPlayerDataRemote:InvokeServer()
		return playerData and playerData[targetPlayer.Name] and playerData[targetPlayer.Name].Role
	end
	return nil
end

function KILL_ALL.hasKnife()
	local char = player.Character
	if not char then return false end
	
	if char:FindFirstChild("Knife") then return true end
	
	local knife = player.Backpack:FindFirstChild("Knife")
	if knife then
		knife.Parent = char
		return true
	end
	
	return false
end

function KILL_ALL.equipKnife()
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    if not character then return false end
    
    local knife = (backpack and backpack:FindFirstChild("Knife")) or character:FindFirstChild("Knife")
    
    if knife then
        if knife.Parent ~= character then
            knife.Parent = character
        end
        return true
    end
    return false
end

function KILL_ALL.getNearestTarget()
	local validTargets = {}
	local myRoot = UTILS.getHRP()
	if not myRoot then return nil end
	
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and targetPlayer.Character then
			local role = KILL_ALL.getPlayerRoleFromServer(targetPlayer)
			local humanoid = targetPlayer.Character:FindFirstChild("Humanoid")
			local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
			
			if role and humanoid and humanoid.Health > 0 and root and table.find(CONFIG.VALID_TARGET_ROLES, role) then
				local distance = (myRoot.Position - root.Position).Magnitude
				table.insert(validTargets, {
					Player = targetPlayer,
					Distance = distance
				})
			end
		end
	end
	
	table.sort(validTargets, function(a, b) return a.Distance < b.Distance end)
	
	return validTargets[1] and validTargets[1].Player or nil
end

function KILL_ALL.getAllValidTargets()
    local validTargets = {}
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character then
            local role = KILL_ALL.getPlayerRoleFromServer(targetPlayer)
            local humanoid = targetPlayer.Character:FindFirstChild("Humanoid")
            
            if role and humanoid and humanoid.Health > 0 and table.find(CONFIG.VALID_TARGET_ROLES, role) then
                table.insert(validTargets, targetPlayer)
            end
        end
    end
    
    return validTargets
end

function KILL_ALL.killTargetThroughEvent(target)
    if not target or not target.Character then return false end
    
    local humanoid = target.Character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    
    if not KILL_ALL.equipKnife() then return false end
    
    task.wait(0.1)
    
    local myRoot = UTILS.getHRP()
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    
    if not myRoot or not targetRoot then return false end
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local killEvent = remotes and remotes:FindFirstChild("Gameplay") and remotes.Gameplay:FindFirstChild("KillEvent")
    
    if not killEvent then
        local knife = player.Character:FindFirstChild("Knife")
        if knife and knife:FindFirstChild("Stab") then
            knife.Stab:FireServer("Down")
            task.wait(0.1)
            knife.Stab:FireServer("Down")
            return true
        end
        return false
    end
    
    targetRoot.CFrame = myRoot.CFrame * CFrame.new(0, 0, -3)
    
    pcall(function()
        killEvent:FireServer(target.Name, Color3.new(1, 0, 0))
    end)
    
    return true
end

local killAllLoopActive = true

function KILL_ALL.killAllPlayers()
    if not STATES.KillAll.Enabled then
        return
    end
    
    if not KILL_ALL.equipKnife() then
        return
    end
    
    task.wait(0.1)
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local killEvent = remotes and remotes:FindFirstChild("Gameplay") and remotes.Gameplay:FindFirstChild("KillEvent")
    
    if not killEvent then
        return
    end
    
    local allTargets = KILL_ALL.getAllValidTargets()
    local myRoot = UTILS.getHRP()
    
    if not myRoot then return end
    
    for _, target in ipairs(allTargets) do
        if not STATES.KillAll.Enabled then
            break
        end
        
        if target.Character and target.Character:FindFirstChild("Humanoid") and 
           target.Character.Humanoid.Health > 0 and 
           target.Character:FindFirstChild("HumanoidRootPart") then
            
            local targetRoot = target.Character.HumanoidRootPart
            targetRoot.CFrame = myRoot.CFrame * CFrame.new(0, 0, -3)
            
            pcall(function()
                killEvent:FireServer(target.Name, Color3.new(1, 0, 0))
            end)
            
            task.wait(STATES.KillAll.AttackDelay or 0.2)
        end
    end
end

function KILL_ALL.startKillAllLoop()
	task.spawn(function()
		while killAllLoopActive do
			local waitTime = 0.1
			
			if STATES.KillAll.Enabled and STATES.AutoFarm.BagFull then
				if KILL_ALL.hasKnife() then
				    KILL_ALL.killAllPlayers()
				    waitTime = 3
				else
					waitTime = 1
				end
			else
				waitTime = 0.5
			end
			
			task.wait(waitTime)
		end
	end)
end

-- Движение системы
local MOVEMENT = {}

function MOVEMENT.updateWalkSpeed()
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.WalkSpeed = STATES.Movement.SpeedWalk.Enabled and 
			STATES.Movement.SpeedWalk.Value or CONFIG.DEFAULT_WALK_SPEED
	end
end

function MOVEMENT.updateJumpPower()
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.JumpPower = STATES.Movement.JumpPower.Enabled and 
			STATES.Movement.JumpPower.Value or CONFIG.DEFAULT_JUMP_POWER
	end
end

-- RemoteEvents системы
local REMOTE_SYSTEM = {}

function REMOTE_SYSTEM.findRemoteEvents()
	for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			if obj.Name == "CoinCollected" then
				REMOTE_EVENTS.CoinCollected = obj
			elseif obj.Name == "RoundStart" then
				REMOTE_EVENTS.RoundStart = obj
			elseif obj.Name == "RoundEnd" then
				REMOTE_EVENTS.RoundEnd = obj
			end
		end
		
		if REMOTE_EVENTS.CoinCollected and REMOTE_EVENTS.RoundStart and REMOTE_EVENTS.RoundEnd then
			break
		end
	end
end

function REMOTE_SYSTEM.connectRemoteEvents()
	if REMOTE_EVENTS.CoinCollected then
		REMOTE_EVENTS.CoinCollected.OnClientEvent:Connect(function(_, current, max)
			if STATES.AutoFarm.Enabled then
				FARMING_STATS.CoinsCollected = FARMING_STATS.CoinsCollected + 1
			end
			
			if current == max and not STATES.AutoFarm.Resetting then
				STATES.AutoFarm.BagFull = true
				if STATES.AutoFarm.Enabled then
					task.spawn(FARMING.autoReset)
				end
			end
		end)
	end
	
	if REMOTE_EVENTS.RoundStart then
		REMOTE_EVENTS.RoundStart.OnClientEvent:Connect(function()
			STATES.AutoFarm.Farming = true
			STATES.AutoFarm.BagFull = false
			
			local hrp = UTILS.getHRP()
			if hrp then
				STATES.AutoFarm.StartPosition = hrp.CFrame
			end
		end)
	end
	
	if REMOTE_EVENTS.RoundEnd then
		REMOTE_EVENTS.RoundEnd.OnClientEvent:Connect(function()
			STATES.AutoFarm.Farming = false
			STATES.KillAll.Enabled = false
		end)
	end
end

-- Функция для создания Performance Stats Overlay
local function createPerformanceOverlay()
    if STATES.Performance.Overlay then
        return
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "StatsOverlay"
    screenGui.Parent = CoreGui
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screenGui.DisplayOrder = 95
    screenGui.ResetOnSpawn = false
    
    local frame = UTILS.createWithStaticStroke("Frame", screenGui, {
        Name = "StatsFrame",
        Size = UDim2.new(0, 100, 0, 40),
        Position = STATES.Performance.Position or UDim2.new(0.5, -50, 0.5, -20),
        BackgroundColor3 = Color3.fromRGB(18, 30, 50),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", frame, {CornerRadius = UDim.new(0, 4)})
    
    local bgGradient = UTILS.createInstance("UIGradient", frame, {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
        }),
        Rotation = 90
    })
    
    local statsContainer = UTILS.createInstance("Frame", frame, {
        Name = "StatsContainer",
        Size = UDim2.new(1, -4, 1, -4),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1,
        ZIndex = 6
    })
    
    local pingLabel = UTILS.createInstance("TextLabel", statsContainer, {
        Name = "PingLabel",
        Size = UDim2.new(1, 0, 0.5, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
        TextSize = 10,
        RichText = true,
        Text = "<font color='rgb(50, 150, 255)'>●</font> Ping: ...",
        ZIndex = 7
    })
    
    local fpsLabel = UTILS.createInstance("TextLabel", statsContainer, {
        Name = "FPSLabel",
        Size = UDim2.new(1, 0, 0.5, 0),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
        TextSize = 10,
        RichText = true,
        Text = "<font color='rgb(50, 150, 255)'>●</font> FPS: ...",
        ZIndex = 7
    })
    
    local isDragging = false
    local dragStartPos
    local frameStartPos
    local dragTouchId
    local DRAG_THRESHOLD = 5
    
    local dragButton = UTILS.createInstance("TextButton", frame, {
        Name = "DragButton",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10
    })
    
    dragButton.AutoButtonColor = false
    dragButton.Selected = false
    
    local function onDragStart(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then

                -- Locked: pode clicar, mas não pode iniciar arraste.
                if STATES.GrabGun.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                -- Locked: pode clicar, mas não pode iniciar arraste.
                if STATES.FakeBombJump.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end
            
            isDragging = false
            dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
            dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
            frameStartPos = frame.Position
            
            frame.BackgroundColor3 = Color3.fromRGB(30, 48, 75)
            
            return Enum.ContextActionResult.Sink
        end
    end
    
    local function onDrag(input)
        if not dragStartPos then return end
        
        if input.UserInputType == Enum.UserInputType.Touch then
            if not dragTouchId or dragTouchId ~= input then
                return
            end
        end
        
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - dragStartPos
        
        if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
            isDragging = true
        end
        
        if isDragging then
            local newPosition = UDim2.new(
                frameStartPos.X.Scale,
                frameStartPos.X.Offset + delta.X,
                frameStartPos.Y.Scale,
                frameStartPos.Y.Offset + delta.Y
            )
            
            frame.Position = newPosition
        end
    end
    
    local function onDragEnd(input)
        frame.BackgroundColor3 = Color3.fromRGB(18, 30, 50)
        
        if isDragging then
            local finalPosition = frame.Position
            if not STATES.Performance then
                STATES.Performance = {}
            end
            STATES.Performance.Position = finalPosition
        end
        
        isDragging = false
        dragStartPos = nil
        dragTouchId = nil
        frameStartPos = nil
    end
    
    dragButton.InputBegan:Connect(onDragStart)
    dragButton.InputChanged:Connect(onDrag)
    dragButton.InputEnded:Connect(onDragEnd)
    
    local lastTime = tick()
    local frameCount = 0
    local updateConnection
    
    updateConnection = RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        if tick() - lastTime >= 1 then
            local success, ping = pcall(function()
                return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            
            if success then
                local pingColor
                if ping < 50 then
                    pingColor = "rgb(100, 255, 100)"
                elseif ping < 100 then
                    pingColor = "rgb(255, 255, 100)"
                elseif ping < 200 then
                    pingColor = "rgb(255, 150, 100)"
                else
                    pingColor = "rgb(255, 100, 100)"
                end
                
                pingLabel.Text = string.format(
                    "<font color='rgb(50, 150, 255)'>●</font> Ping: <font color='%s'>%d</font>",
                    pingColor, ping
                )
            else
                pingLabel.Text = "<font color='rgb(50, 150, 255)'>●</font> Ping: ..."
            end
            
            local fpsColor
            if frameCount >= 60 then
                fpsColor = "rgb(100, 255, 100)"
            elseif frameCount >= 30 then
                fpsColor = "rgb(255, 255, 100)"
            else
                fpsColor = "rgb(255, 100, 100)"
            end
            
            fpsLabel.Text = string.format(
                "<font color='rgb(50, 150, 255)'>●</font> FPS: <font color='%s'>%d</font>",
                fpsColor, frameCount
            )
            
            frameCount = 0
            lastTime = tick()
        end
    end)
    
    STATES.Performance.Overlay = {
        gui = screenGui,
        frame = frame,
        connections = {
            update = updateConnection
        },
        destroy = function()
            if updateConnection then updateConnection:Disconnect() end
            if screenGui then screenGui:Destroy() end
            STATES.Performance.Overlay = nil
        end
    }
end

-- WindUI bridge registries (legacy callbacks are preserved)
local LEGACY_TOGGLES = {}
local LEGACY_BUTTONS = {}

-- Фабрика для создания стилизованных кнопок
local function createStyledButton(parent, config)
    config = config or {}
    
    local buttonContainer = UTILS.createWithStaticStroke("Frame", parent, {
        Name = config.name or "StyledButton",
        BackgroundColor3 = config.backgroundColor or Color3.fromRGB(22, 35, 55),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = config.size or UDim2.new(1, -20, 0, 50),
        Position = config.position or UDim2.new(0, 10, 0, 0),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", buttonContainer, {CornerRadius = UDim.new(0, 8)})
    
    local iconContainer = UTILS.createInstance("Frame", buttonContainer, {
        Name = "IconContainer",
        BackgroundColor3 = Color3.fromRGB(38, 65, 100),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(0, 12, 0.5, -18),
        ZIndex = 6
    })
    UTILS.createInstance("UICorner", iconContainer, {CornerRadius = UDim.new(1, 0)})
    
    local icon = UTILS.createInstance("ImageLabel", iconContainer, {
        Name = "Icon",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(0.5, -12, 0.5, -12),
        Image = config.icon or "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 7
    })
    
    local titleLabel = UTILS.createInstance("TextLabel", buttonContainer, {
        Name = "Title",
        Text = config.title or "Button",
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextSize = 15,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 55, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 7
    })
    
    local button = UTILS.createInstance("TextButton", buttonContainer, {
        Name = "Button",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 8
    })
    
    button.MouseEnter:Connect(function()
        TweenService:Create(buttonContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(35, 55, 85),
            BackgroundTransparency = 0.1
        }):Play()
        
        TweenService:Create(titleLabel, TweenInfo.new(0.15), {
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
        
        TweenService:Create(iconContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(80, 65, 100)
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(buttonContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = config.backgroundColor or Color3.fromRGB(22, 35, 55),
            BackgroundTransparency = 0.2
        }):Play()
        
        TweenService:Create(titleLabel, TweenInfo.new(0.15), {
            TextColor3 = Color3.fromRGB(232, 245, 255)
        }):Play()
        
        TweenService:Create(iconContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(38, 65, 100)
        }):Play()
    end)
    
    button.MouseButton1Click:Connect(function()
        UTILS.playClickSound()
        
        TweenService:Create(buttonContainer, TweenInfo.new(0.05), {
            Size = UDim2.new(1, -20, 0, 48)
        }):Play()
        
        task.wait(0.05)
        
        TweenService:Create(buttonContainer, TweenInfo.new(0.05), {
            Size = config.size or UDim2.new(1, -20, 0, 50)
        }):Play()
        
        local originalColor = buttonContainer.BackgroundColor3
        buttonContainer.BackgroundColor3 = config.accentColor or CONFIG.MAIN_COLOR
        task.wait(0.1)
        buttonContainer.BackgroundColor3 = originalColor
        
        if config.onClick then
            config.onClick()
        end
    end)
    
    if config.title and config.onClick then
        LEGACY_BUTTONS[config.title] = config.onClick
    end

    return {
        container = buttonContainer,
        button = button,
        title = titleLabel,
        icon = icon
    }
end

-- Функция создания тогглов (без анимации размера)
local function createToggle(parent, text, positionY, stateTable, stateKey, callback)
    local toggleFrame = UTILS.createWithStaticStroke("Frame", parent, {
        Name = text .. "Toggle",
        Size = UDim2.new(1, -20, 0, 45),
        Position = UDim2.new(0, 10, 0, positionY),
        BackgroundColor3 = Color3.fromRGB(22, 35, 55),
        BackgroundTransparency = 0.5,
        ZIndex = 5
    })
    UTILS.createInstance("UICorner", toggleFrame, {CornerRadius = UDim.new(0, 8)})
    
    local title = UTILS.createInstance("TextLabel", toggleFrame, {
        Text = text,
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(230, 230, 230),
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    local switchBg = UTILS.createInstance("Frame", toggleFrame, {
        Size = UDim2.new(0, 40, 0, 20),
        Position = UDim2.new(1, -55, 0.5, -10),
        BackgroundColor3 = stateTable[stateKey] and CONFIG.MAIN_COLOR or Color3.fromRGB(60, 50, 70),
        ZIndex = 6
    })
    UTILS.createInstance("UICorner", switchBg, {CornerRadius = UDim.new(1, 0)})
    
    local ball = UTILS.createInstance("Frame", switchBg, {
        Size = UDim2.new(0, 16, 0, 16),
        Position = stateTable[stateKey] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        ZIndex = 7
    })
    UTILS.createInstance("UICorner", ball, {CornerRadius = UDim.new(1, 0)})
    
    local button = UTILS.createInstance("TextButton", toggleFrame, {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 8
    })
    
    button.MouseButton1Click:Connect(function()
        stateTable[stateKey] = not stateTable[stateKey]
        local newState = stateTable[stateKey]
        
        TweenService:Create(switchBg, TweenInfo.new(0.3), {
            BackgroundColor3 = newState and CONFIG.MAIN_COLOR or Color3.fromRGB(60, 50, 70)
        }):Play()
        
        TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            Position = newState and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        
        if callback then
            task.spawn(callback, newState)
        end        
        UTILS.playClickSound()
    end)
    
    button.MouseEnter:Connect(function()
        TweenService:Create(toggleFrame, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(45, 35, 55),
            BackgroundTransparency = 0.3
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(toggleFrame, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(22, 35, 55),
            BackgroundTransparency = 0.5
        }):Play()
    end)
    
    LEGACY_TOGGLES[text] = {
        stateTable = stateTable,
        stateKey = stateKey,
        callback = callback,
    }

    return toggleFrame, button
end

-- UI системы
local UI_SYSTEM = {}

function UI_SYSTEM.createPlayerInfoContainer(parent)
	local playerInfoContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "PlayerInfoContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 360, 0, 100),
		Position = UDim2.new(0, 8, 0, 8),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", playerInfoContainer, {CornerRadius = UDim.new(0, 8)})
	
	local avatarInfoFrame = UTILS.createInstance("Frame", playerInfoContainer, {
		Name = "AvatarInfoFrame",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.new(0, 8, 0, 8),
		ZIndex = 6
	})
	
	local playerAvatar = UTILS.createInstance("ImageLabel", avatarInfoFrame, {
		Name = "PlayerAvatar",
		BackgroundColor3 = Color3.fromRGB(38, 62, 95),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 0, 0, 0),
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", playerAvatar, {CornerRadius = UDim.new(0, 8)})
	
	local infoFrame = UTILS.createInstance("Frame", avatarInfoFrame, {
		Name = "InfoFrame",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -72, 1, 0),
		Position = UDim2.new(0, 72, 0, 0),
		ZIndex = 6
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "DisplayName",
		Text = player.DisplayName,
		TextColor3 = Color3.fromRGB(250, 240, 255),
		TextSize = 18,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "Username",
		Text = "@" .. player.Name,
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 24),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "GameName",
		Text = "Murder Mystery 2",
		TextColor3 = Color3.fromRGB(175, 215, 245),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 48),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "PlayerId",
		Text = "Player ID: " .. tostring(player.UserId),
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(0.48, -4, 0, 18),
		Position = UDim2.new(0, 0, 0, 72),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "ServerId",
		Text = "Server ID: " .. tostring(game.PlaceId),
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(0.48, -4, 0, 18),
		Position = UDim2.new(0.52, 0, 0, 72),
		ZIndex = 7
	})
	
	return playerInfoContainer
end

function UI_SYSTEM.createSpeedJumpContainer(parent)
	local speedJumpContainer = UTILS.createWithStaticStroke("Frame", parent, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(18, 30, 50),
		BackgroundTransparency = 0.5,
		Size = UDim2.new(0, 360, 0, 180),
		Position = UDim2.new(0, 8, 0, 116),
		Name = "SpeedJumpContainer",
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", speedJumpContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", speedJumpContainer, {
		Name = "SpeedJumpTitle",
		Text = "Speed And Jump",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local speedWalkToggle = createToggle(speedJumpContainer, "Speed Walk", 32, STATES.Movement.SpeedWalk, "Enabled", function(isEnabled)
		STATES.Movement.SpeedWalk.Enabled = isEnabled
		MOVEMENT.updateWalkSpeed()
	end)
	
	local speedWalkSliderContainer = UTILS.createInstance("Frame", speedJumpContainer, {
		Name = "SpeedWalkSliderContainer",
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 76),
		ZIndex = 6
	})
	
	UTILS.createInstance("UICorner", speedWalkSliderContainer, {CornerRadius = UDim.new(0, 8)})
	
	local speedWalkSlider = UTILS.createInstance("Frame", speedWalkSliderContainer, {
		Name = "SpeedWalkSlider",
		BackgroundColor3 = Color3.fromRGB(80, 60, 100),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", speedWalkSlider, {CornerRadius = UDim.new(0, 8)})
	
	local speedWalkValue = UTILS.createInstance("TextLabel", speedWalkSliderContainer, {
		Name = "SpeedWalkValue",
		Text = "16",
		TextColor3 = Color3.fromRGB(232, 245, 255),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8
	})
	
	local jumpPowerToggle = createToggle(speedJumpContainer, "Jump Power", 104, STATES.Movement.JumpPower, "Enabled", function(isEnabled)
		STATES.Movement.JumpPower.Enabled = isEnabled
		MOVEMENT.updateJumpPower()
	end)
	
	local jumpPowerSliderContainer = UTILS.createInstance("Frame", speedJumpContainer, {
		Name = "JumpPowerSliderContainer",
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 148),
		ZIndex = 6
	})
	
	UTILS.createInstance("UICorner", jumpPowerSliderContainer, {CornerRadius = UDim.new(0, 8)})
	
	local jumpPowerSlider = UTILS.createInstance("Frame", jumpPowerSliderContainer, {
		Name = "JumpPowerSlider",
		BackgroundColor3 = Color3.fromRGB(80, 60, 100),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", jumpPowerSlider, {CornerRadius = UDim.new(0, 8)})
	
	local jumpPowerValue = UTILS.createInstance("TextLabel", jumpPowerSliderContainer, {
		Name = "JumpPowerValue",
		Text = "50",
		TextColor3 = Color3.fromRGB(232, 245, 255),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8
	})
	
	local speedWalkSliderObj = UI_SYSTEM.createSlider(
		speedWalkSlider,
		speedWalkValue,
		16, 116, 16,
		function(value)
			STATES.Movement.SpeedWalk.Value = value
			if STATES.Movement.SpeedWalk.Enabled then
				MOVEMENT.updateWalkSpeed()
			end
		end
	)
	
	local jumpPowerSliderObj = UI_SYSTEM.createSlider(
		jumpPowerSlider,
		jumpPowerValue,
		50, 150, 50,
		function(value)
			STATES.Movement.JumpPower.Value = value
			if STATES.Movement.JumpPower.Enabled then
				MOVEMENT.updateJumpPower()
			end
		end
	)
	
	return speedJumpContainer
end

function UI_SYSTEM.createSlider(sliderFrame, valueLabel, minValue, maxValue, defaultValue, callback)
	local isDragging = false
	local currentValue = defaultValue or minValue
	local startPercentage = (defaultValue - minValue) / (maxValue - minValue)
	
	local thumb = UTILS.createInstance("Frame", sliderFrame.Parent, {
		Name = "SliderThumb",
		Size = UDim2.new(0, 20, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(startPercentage, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 15
	})
	
	UTILS.createInstance("UICorner", thumb, {CornerRadius = UDim.new(1, 0)})
	UTILS.createInstance("UIStroke", thumb, {
		Thickness = 2,
		Color = Color3.fromRGB(50, 150, 255)
	})
	
	sliderFrame.Size = UDim2.new(startPercentage, 0, 1, 0)
	
	local function updateSlider(positionX)
		local containerWidth = sliderFrame.Parent.AbsoluteSize.X
		local newX = math.clamp(positionX, 0, containerWidth)
		local percentage = newX / containerWidth
		local value = math.floor(minValue + (maxValue - minValue) * percentage)
		
		TweenService:Create(sliderFrame, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(percentage, 0, 1, 0)
		}):Play()
		
		TweenService:Create(thumb, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(percentage, 0, 0.5, 0)
		}):Play()
		
		valueLabel.Text = tostring(value)
		currentValue = value
		
		thumb.BackgroundColor3 = isDragging and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(255, 255, 255)
		sliderFrame.BackgroundColor3 = isDragging and Color3.fromRGB(120, 80, 150) or Color3.fromRGB(80, 60, 100)
		
		if callback then callback(value) end
	end
	
	local containerButton = UTILS.createInstance("TextButton", sliderFrame.Parent, {
		Name = "SliderButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10
	})
	
	local thumbButton = UTILS.createInstance("TextButton", thumb, {
		Name = "ThumbButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20
	})
	
	local function handleContainerInputBegan(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local relativeX = input.Position.X - containerPosition.X
			updateSlider(relativeX)
		end
	end
	
	local thumbStartPos, thumbStartMousePos
	
	local function handleThumbInputBegan(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			thumbStartPos = thumb.Position
			thumbStartMousePos = input.Position
			thumb.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
		end
	end
	
	local function handleInputEnded(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
			thumbStartPos = nil
			thumbStartMousePos = nil
			
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			}):Play()
			
			TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(80, 60, 100)
			}):Play()
		end
	end
	
	local function handleThumbInputChanged(input)
		if isDragging and thumbStartPos and thumbStartMousePos and 
		   (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local containerWidth = sliderFrame.Parent.AbsoluteSize.X
			local deltaX = input.Position.X - thumbStartMousePos.X
			local newX = math.clamp((thumbStartPos.X.Scale * containerWidth) + deltaX, 0, containerWidth)
			updateSlider(newX)
		end
	end
	
	local function handleContainerInputChanged(input)
		if isDragging and not thumbStartPos and 
		   (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local relativeX = input.Position.X - containerPosition.X
			updateSlider(relativeX)
		end
	end
	
	containerButton.InputBegan:Connect(handleContainerInputBegan)
	containerButton.InputEnded:Connect(handleInputEnded)
	containerButton.InputChanged:Connect(handleContainerInputChanged)
	
	thumbButton.InputBegan:Connect(handleThumbInputBegan)
	thumbButton.InputEnded:Connect(handleInputEnded)
	thumbButton.InputChanged:Connect(handleThumbInputChanged)
	
	local function setValue(newValue)
		newValue = math.clamp(newValue, minValue, maxValue)
		local percentage = (newValue - minValue) / (maxValue - minValue)
		
		TweenService:Create(sliderFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(percentage, 0, 1, 0)
		}):Play()
		
		TweenService:Create(thumb, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(percentage, 0, 0.5, 0)
		}):Play()
		
		valueLabel.Text = tostring(newValue)
		currentValue = newValue
		
		if callback then callback(newValue) end
	end
	
	thumbButton.MouseEnter:Connect(function()
		if not isDragging then
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 24, 0, 24),
				BackgroundColor3 = Color3.fromRGB(230, 230, 255)
			}):Play()
		end
	end)
	
	thumbButton.MouseLeave:Connect(function()
		if not isDragging then
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			}):Play()
		end
	end)
	
	containerButton.MouseEnter:Connect(function()
		TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(90, 70, 110)
		}):Play()
	end)
	
	containerButton.MouseLeave:Connect(function()
		if not isDragging then
			TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(80, 60, 100)
			}):Play()
		end
	end)
	
	setValue(defaultValue)
	
	return {
		setValue = setValue,
		getValue = function() return currentValue end,
		thumb = thumb
	}
end

function UI_SYSTEM.createTabButton(parent, text, positionY, tabName, contentFrame)
	local tabFrame = UTILS.createWithStaticStroke("Frame", parent, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(32, 52, 82),
		Size = UDim2.new(0, 116, 0, 48),
		Position = UDim2.new(0, 4, 0, positionY),
		Name = "Tab_" .. tabName,
		BackgroundTransparency = 0.7,
		ZIndex = 12
	})
	
	UTILS.createInstance("UICorner", tabFrame, {CornerRadius = UDim.new(0, 5)})
	
	local tabButton = UTILS.createInstance("TextButton", tabFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Name = "TabButton_" .. tabName,
		ZIndex = 15
	})
	
	local textLabel = UTILS.createInstance("TextLabel", tabFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(225, 240, 255),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		TextWrapped = true,
		ZIndex = 13
	})
	
	local tabContentScrolling = UTILS.createInstance("ScrollingFrame", contentFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Name = "content_" .. tabName,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(70, 110, 150),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 5
	})
	
	local tabContent = UTILS.createInstance("Frame", tabContentScrolling, {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Name = "contentContainer_" .. tabName,
		ZIndex = 5
	})
	
	return tabButton, tabFrame, tabContent, textLabel, tabContentScrolling
end

function UI_SYSTEM.createShootMurdererButton()
	local ScreenGui_1 = UTILS.createInstance("ScreenGui", CoreGui, {
		Name = "ShootMurdererGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		DisplayOrder = 50
	})
	
	local shootButton_2 = UTILS.createWithStaticStroke("Frame", ScreenGui_1, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		Size = UDim2.fromOffset(FLOATING_STYLES.ShootMurderer.Size, FLOATING_STYLES.ShootMurderer.Height),
		Position = STATES.ShootMurderer.Position or UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Name = "shootButton",
		BackgroundTransparency = 0.3,
		ZIndex = 1
	})
	
	UTILS.createInstance("UICorner", shootButton_2, {CornerRadius = floatingCorner(FLOATING_STYLES.ShootMurderer.Shape, FLOATING_STYLES.ShootMurderer.Size)})
	
	local backgroundGradient = UTILS.createInstance("UIGradient", shootButton_2, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
		}),
		Rotation = 90
	})
	
	local TextLabel_5 = UTILS.createInstance("TextLabel", shootButton_2, {
		BorderSizePixel = 0,
		TextSize = 19,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "Shoot Murderer",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextScaled = false,
		TextWrapped = true,
		ZIndex = 2
	})
	
	local isDragging = false
	local dragStartPos
	local buttonStartPos
	local dragTouchId
	local wasClick = false
	local DRAG_THRESHOLD = 5
	
	local instakillshoot = false
	
	local function findMurderer()
		for _, i in ipairs(Players:GetPlayers()) do
			if i.Backpack:FindFirstChild("Knife") then
				return i
			end
		end
	
		for _, i in ipairs(Players:GetPlayers()) do
			if not i.Character then continue end
			if i.Character:FindFirstChild("Knife") then
				return i
			end
		end
	
		return nil
	end
	
	local function findSheriff()
		for _, i in ipairs(Players:GetPlayers()) do
			if i.Backpack:FindFirstChild("Gun") then
				return i
			end
		end
	
		for _, i in ipairs(Players:GetPlayers()) do
			if not i.Character then continue end
			if i.Character:FindFirstChild("Gun") then
				return i
			end
		end
	
		return nil
	end
	
	local function getPredictedPosition(targetPlayer, _offset)
		if not targetPlayer or not targetPlayer.Character then return Vector3.zero end
		local hrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return hrp and hrp.Position or Vector3.zero end
		local position = hrp.Position
		local velocity = hrp.AssemblyLinearVelocity
		local pingSeconds = player:GetNetworkPing()
		local step = math.max(SHOOT_CONFIG.Interval, 0.01)
		local simulations = math.clamp(math.floor(SHOOT_CONFIG.Simulations), 1, 30)
		local timeAhead = SHOOT_CONFIG.PrioritizePing and pingSeconds or 0
		for _ = 1, simulations do
			if SHOOT_CONFIG.PredictLag then
				local horizontal = Vector3.new(velocity.X * SHOOT_CONFIG.HorizontalMultiplier, 0, velocity.Z * SHOOT_CONFIG.HorizontalMultiplier)
				local vertical = SHOOT_CONFIG.PredictJump and velocity.Y * SHOOT_CONFIG.VerticalMultiplier or 0
				position += (horizontal + Vector3.new(0, vertical, 0)) * (step + timeAhead)
			end
			timeAhead += step
		end
		position += Vector3.new(SHOOT_CONFIG.OffsetX, SHOOT_CONFIG.OffsetY, SHOOT_CONFIG.OffsetZ)
		if SHOOT_CONFIG.PredictJump and hum:GetState() == Enum.HumanoidStateType.Jumping then
			position += Vector3.new(0, math.max(0, velocity.Y) * 0.03, 0)
		end
		return position
	end

	local function shootMurdererFunction()
		if findSheriff() ~= player then 
			return 
		end
	
		local murderer = findMurderer()
		if not murderer then
			return
		end
	
		if not player.Character then
			return
		end
	
		if not player.Character:FindFirstChild("Gun") then
			local hum = player.Character:FindFirstChild("Humanoid")
			if hum and player.Backpack:FindFirstChild("Gun") then
				hum:EquipTool(player.Backpack:FindFirstChild("Gun"))
			else
				return
			end
		end
	
		local murdererHRP = murderer.Character:FindFirstChild("HumanoidRootPart")
		if not murdererHRP then
			return
		end
	
		local predictedPosition = getPredictedPosition(murderer, 0)
		if SHOOT_CONFIG.SharpShooter then
			local origin = player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
			if origin then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = {player.Character}
				local hit = workspace:Raycast(origin, predictedPosition - origin, params)
				if hit and not hit.Instance:IsDescendantOf(murderer.Character) then return end
			end
		end
	
		local args
		if instakillshoot then
			args = {
				CFrame.new(murdererHRP.Position + Vector3.new(0, 1, 0)),
				CFrame.new(murdererHRP.Position)
			}
		else
			if not player.Character:FindFirstChild("RightHand") then
				return
			end
			args = {
				CFrame.new(player.Character.RightHand.Position),
				CFrame.new(predictedPosition)
			}
		end
		
		local gun = player.Character:WaitForChild("Gun")
		local shootEvent = gun:WaitForChild("Shoot")
		shootEvent:FireServer(unpack(args))
		
		local originalColor = shootButton_2.BackgroundColor3
		local flashTween = TweenService:Create(shootButton_2, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(255, 100, 100)
		})
		flashTween:Play()
		
		task.wait(0.1)
		
		local returnTween = TweenService:Create(shootButton_2, TweenInfo.new(0.1), {
			BackgroundColor3 = originalColor
		})
		returnTween:Play()
	end
	
	local function onDragStart(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		   input.UserInputType == Enum.UserInputType.Touch then

			-- Locked buttons still click, but cannot be moved.
			if STATES.ShootMurderer.Locked then
                isDragging = false
                wasClick = true
                dragTouchId = nil
                dragStartPos = nil
                buttonStartPos = nil
                return Enum.ContextActionResult.Sink
            end
			
			isDragging = false
			wasClick = true
			dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
			dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
			buttonStartPos = shootButton_2.Position
			
			shootButton_2.BackgroundColor3 = Color3.fromRGB(32, 55, 90)
			shootButton_2.BackgroundTransparency = 0.2
			
			return Enum.ContextActionResult.Sink
		end
	end
	
	local function onDrag(input)
		if STATES.ShootMurderer.Locked then return end
		if not dragStartPos then return end
		
		if input.UserInputType == Enum.UserInputType.Touch then
			if not dragTouchId or dragTouchId ~= input then
				return
			end
		end
		
		local currentPos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = currentPos - dragStartPos
		
		if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
			isDragging = true
			wasClick = false
		end
		
		if isDragging then
			local newPosition = UDim2.new(
				buttonStartPos.X.Scale,
				buttonStartPos.X.Offset + delta.X,
				buttonStartPos.Y.Scale,
				buttonStartPos.Y.Offset + delta.Y
			)
			
			shootButton_2.Position = newPosition
		end
	end
	
	local function onDragEnd(input)
		if wasClick and not isDragging then
			UTILS.playClickSound()
			shootMurdererFunction()
		end
		
		shootButton_2.BackgroundColor3 = Color3.fromRGB(25, 40, 65)
		shootButton_2.BackgroundTransparency = 0.3
		TextLabel_5.TextColor3 = Color3.fromRGB(225, 240, 255)
		
		if isDragging then
			local finalPosition = shootButton_2.Position
			STATES.ShootMurderer.Position = finalPosition
		end
		
		isDragging = false
		wasClick = false
		dragStartPos = nil
		dragTouchId = nil
		buttonStartPos = nil
	end
	
	local dragButton = UTILS.createInstance("TextButton", shootButton_2, {
		Name = "DragButton",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10
	})
	
	dragButton.InputBegan:Connect(onDragStart)
	dragButton.InputChanged:Connect(onDrag)
	dragButton.InputEnded:Connect(onDragEnd)
	
	dragButton.MouseEnter:Connect(function()
		if not isDragging then
			shootButton_2.BackgroundTransparency = 0.2
			shootButton_2.BackgroundColor3 = Color3.fromRGB(30, 48, 75)
			TextLabel_5.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end)
	
	dragButton.MouseLeave:Connect(function()
		if not isDragging then
			shootButton_2.BackgroundTransparency = 0.3
			shootButton_2.BackgroundColor3 = Color3.fromRGB(25, 40, 65)
			TextLabel_5.TextColor3 = Color3.fromRGB(225, 240, 255)
		end
	end)
	
	return {
		gui = ScreenGui_1,
		frame = shootButton_2,
        shoot = shootMurdererFunction,
		destroy = function()
			if ScreenGui_1 then ScreenGui_1:Destroy() end
		end
	}
end

function UI_SYSTEM.createEspContainer(parent)
	local espContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 20),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espContainer, {
		Name = "EspTitle",
		Text = "ESP",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espNameToggle = createToggle(espContainer, "ESP Name", currentY, ESP_SYSTEM.ESP_STATES, "ESPName", function(isEnabled)
		if not isEnabled then
			ESP_SYSTEM.clearAllESP()
		else
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local murdererToggle = createToggle(espContainer, "Murderer Name", currentY, ESP_SYSTEM.ESP_STATES, "MurdererName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local sheriffToggle = createToggle(espContainer, "Sheriff Name", currentY, ESP_SYSTEM.ESP_STATES, "SheriffName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local heroToggle = createToggle(espContainer, "Hero Name", currentY, ESP_SYSTEM.ESP_STATES, "HeroName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local innocentToggle = createToggle(espContainer, "Innocent Name", currentY, ESP_SYSTEM.ESP_STATES, "InnocentName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	
	return espContainer
end

function UI_SYSTEM.createEspHighlightContainer(parent)
	local espHighlightContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspHighlightContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 330),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espHighlightContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espHighlightContainer, {
		Name = "EspHighlightTitle",
		Text = "ESP Highlight",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espHighlightToggle = createToggle(espHighlightContainer, "ESP Highlight", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlight", function(isEnabled)
		if not isEnabled then
			ESP_SYSTEM.clearAllHighlights()
		else
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightMurderer = createToggle(espHighlightContainer, "ESP Highlight Murderer", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightMurderer", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightSheriff = createToggle(espHighlightContainer, "ESP Highlight Sheriff", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightSheriff", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightHero = createToggle(espHighlightContainer, "ESP Highlight Hero", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightHero", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightInnocent = createToggle(espHighlightContainer, "ESP Highlight Innocent", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightInnocent", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	
	return espHighlightContainer
end

function UI_SYSTEM.createEspLineContainer(parent)
	local espLineContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspLineContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 640),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espLineContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espLineContainer, {
		Name = "EspLineTitle",
		Text = "Tracers",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espLineToggle = createToggle(espLineContainer, "ESP Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "ESPLine", function(isEnabled)
		if isEnabled then
			ESP_SYSTEM.StartAllLines()
		else
			ESP_SYSTEM.StopAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineMurderer = createToggle(espLineContainer, "Murderer Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "MurdererLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineSheriff = createToggle(espLineContainer, "Sheriff Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "SheriffLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineHero = createToggle(espLineContainer, "Hero Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "HeroLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineInnocent = createToggle(espLineContainer, "Innocent Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "InnocentLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	
	return espLineContainer
end

function UI_SYSTEM.createMainTabContent(content)
	UI_SYSTEM.createPlayerInfoContainer(content)
	UI_SYSTEM.createSpeedJumpContainer(content)
    
    local performanceY = 116 + 180 + 20
    local performanceToggle = createToggle(content, "Performance (Ping & Fps)", performanceY, STATES.Performance, "Enabled", function(isEnabled)
		if isEnabled then
			createPerformanceOverlay()
		else
			if STATES.Performance.Overlay then
				STATES.Performance.Overlay.destroy()
			end
		end
	end)
end

function UI_SYSTEM.createVisualTabContent(content)
	local espContainer = UI_SYSTEM.createEspContainer(content)
	local espHighlightContainer = UI_SYSTEM.createEspHighlightContainer(content)
	local espLineContainer = UI_SYSTEM.createEspLineContainer(content)
	return espContainer, espHighlightContainer, espLineContainer
end

function UI_SYSTEM.createCombatTabContent(content)
	local shootToggle = createToggle(content, "Shoot The Murderer", 32, STATES, "ShootMurdererTemp", function(isEnabled)
		if isEnabled then
			if not STATES.ShootMurderer.ButtonData then
				STATES.ShootMurderer.ButtonData = UI_SYSTEM.createShootMurdererButton()
			end
		else
			if STATES.ShootMurderer.ButtonData then
				STATES.ShootMurderer.ButtonData.destroy()
				STATES.ShootMurderer.ButtonData = nil
			end
		end
	end)

	local shootLockToggle = createToggle(content, "Lock Shoot Button", 84, STATES, "ShootMurdererLocked", function(isLocked)
		STATES.ShootMurdererLocked = isLocked
        STATES.ShootMurderer.Locked = isLocked
	end)
end

STATES.ShootMurdererTemp = false
STATES.ShootMurderer = STATES.ShootMurderer or {}
STATES.ShootMurderer.Locked = false
STATES.ShootMurdererLocked = false

function UI_SYSTEM.createTeleportTabContent(content)
    local currentY = 20
    
    local bombContainer = UTILS.createWithStaticStroke("Frame", content, {
        Name = "FakeBombJumpContainer",
        BackgroundColor3 = CONFIG.MAIN_COLOR,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 152),
        Position = UDim2.new(0, 10, 0, currentY),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", bombContainer, {CornerRadius = UDim.new(0, 8)})
    
    UTILS.createInstance("TextLabel", bombContainer, {
        Name = "BombContainerTitle",
        Text = "Fake Bomb Jump",
        TextColor3 = Color3.fromRGB(225, 240, 255),
        TextSize = 16,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6
    })
    
    local bombButtonData = nil
    
    local function createBombButton()
        if bombButtonData then return end
        
        local bombGui = UTILS.createInstance("ScreenGui", CoreGui, {
            Name = "FakeBombJumpGui",
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            ResetOnSpawn = false,
            DisplayOrder = 50
        })
        
        local bombFrame = UTILS.createWithStaticStroke("Frame", bombGui, {
            Name = "BombJumpFrame",
            BackgroundColor3 = CONFIG.MAIN_COLOR,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(FLOATING_STYLES.FakeBombJump.Size, FLOATING_STYLES.FakeBombJump.Size),
            Position = STATES.FakeBombJump.Position or UDim2.new(0.5, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            ZIndex = 1
        })
        
        UTILS.createInstance("UICorner", bombFrame, {CornerRadius = UDim.new(0, 5)})
        
        local backgroundGradient = UTILS.createInstance("UIGradient", bombFrame, {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
            }),
            Rotation = 90
        })
        
        local textLabel = UTILS.createInstance("TextLabel", bombFrame, {
            Name = "BombText",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "💣",
            TextColor3 = Color3.fromRGB(225, 240, 255),
            TextSize = 30,
            FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
            TextWrapped = true,
            ZIndex = 2
        })
        
        local button = UTILS.createInstance("TextButton", bombFrame, {
            Name = "BombButton",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3
        })
        
        local bombAvailable = true
        local bombCooldown = 22
        local cooldownActive = false
        local isDragging = false
        local dragStartPos
        local buttonStartPos
        local dragTouchId
        local wasClick = false
        local DRAG_THRESHOLD = 5
        
        local COLORS = {
            READY = Color3.fromRGB(225, 240, 255),
            READY_HOVER = Color3.fromRGB(255, 255, 255),
            COOLDOWN = Color3.fromRGB(255, 150, 150)
        }
        
        local function updateUI(status, message)
            if status == "ready" then
                textLabel.Text = "💣"
                cooldownActive = false
                textLabel.TextColor3 = COLORS.READY
            elseif status == "cooldown" then
                textLabel.Text = tostring(message) .. "s"
                cooldownActive = true
                textLabel.TextColor3 = COLORS.COOLDOWN
            end
        end
        
        local function useBomb()
            if bombAvailable and not cooldownActive then
                bombAvailable = false
                cooldownActive = true
                
                local player = Players.LocalPlayer
                local character = player.Character
                
                if not character then
                    bombAvailable = true
                    cooldownActive = false
                    updateUI("ready")
                    return
                end
                
                local backpack = player.Backpack
                
                local bomb = backpack:FindFirstChild("FakeBomb") or character:FindFirstChild("FakeBomb")
                if not bomb then
                    local remote = ReplicatedStorage:FindFirstChild("Remotes")
                    if remote then
                        local extras = remote:FindFirstChild("Extras")
                        if extras then
                            local replicateToy = extras:FindFirstChild("ReplicateToy")
                            if replicateToy then
                                pcall(function()
                                    replicateToy:InvokeServer("FakeBomb")
                                end)
                            end
                        end
                    end
                    
                    bomb = backpack:WaitForChild("FakeBomb", 5)
                    if not bomb then
                        bombAvailable = true
                        cooldownActive = false
                        updateUI("ready")
                        return
                    end
                end
                
                bomb.Parent = character
                
                if bomb:IsDescendantOf(character) and character:FindFirstChild("Humanoid") then
                    local humanoid = character.Humanoid
                    local hrp = character:FindFirstChild("HumanoidRootPart")
                    
                    if hrp then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        humanoid.JumpPower = 53
                        
                        if bomb:FindFirstChild("Remote") then
                            bomb.Remote:FireServer(hrp.CFrame * CFrame.new(0, -3, 0), 50)
                        end
                        
                        task.wait(0.3)
                        
                        if bomb and bomb.Parent == character then
                            bomb.Parent = backpack
                        end
                        
                        if humanoid then
                            humanoid.JumpPower = 51
                        end
                    end
                end
                
                local startTime = time()
                local characterCheck = character
                
                while time() - startTime < bombCooldown do
                    if Players.LocalPlayer.Character ~= characterCheck then
                        bombAvailable = true
                        cooldownActive = false
                        updateUI("ready")
                        return
                    end
                    
                    local remaining = math.ceil(bombCooldown - (time() - startTime))
                    updateUI("cooldown", remaining)
                    task.wait(1)
                end
                
                bombAvailable = true
                cooldownActive = false
                updateUI("ready")
            end
        end
        
        local function onDragStart(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                
                -- Locked: pode clicar, mas não pode mover.
                if STATES.FakeBombJump.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                isDragging = false
                wasClick = true
                dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                buttonStartPos = bombFrame.Position
                
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.18)
                bombFrame.BackgroundTransparency = 0.2
                
                return Enum.ContextActionResult.Sink
            end
        end
        
        local function onDrag(input)
            if STATES.FakeBombJump.Locked then return end
            if not dragStartPos then return end
            
            if input.UserInputType == Enum.UserInputType.Touch then
                if not dragTouchId or dragTouchId ~= input then
                    return
                end
            end
            
            local currentPos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentPos - dragStartPos
            
            if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
                isDragging = true
                wasClick = false
            end
            
            if isDragging then
                local newPosition = UDim2.new(
                    buttonStartPos.X.Scale,
                    buttonStartPos.X.Offset + delta.X,
                    buttonStartPos.Y.Scale,
                    buttonStartPos.Y.Offset + delta.Y
                )
                
                bombFrame.Position = newPosition
            end
        end
        
        local function onDragEnd(input)
            if wasClick and not isDragging then
                UTILS.playClickSound()
                if not cooldownActive then
                    useBomb()
                end
            end
            
            bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
            bombFrame.BackgroundTransparency = 0.3
            local targetColor = cooldownActive and COLORS.COOLDOWN or COLORS.READY
            textLabel.TextColor3 = targetColor
            
            if isDragging then
                local finalPosition = bombFrame.Position
                STATES.FakeBombJump.Position = finalPosition
            end
            
            isDragging = false
            wasClick = false
            dragStartPos = nil
            dragTouchId = nil
            buttonStartPos = nil
        end
        
        button.InputBegan:Connect(onDragStart)
        button.InputChanged:Connect(onDrag)
        button.InputEnded:Connect(onDragEnd)
        
        button.MouseEnter:Connect(function()
            if not isDragging then
                bombFrame.BackgroundTransparency = 0.2
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.12)
                
                if not cooldownActive then
                    textLabel.TextColor3 = COLORS.READY_HOVER
                end
            end
        end)
        
        button.MouseLeave:Connect(function()
            if not isDragging then
                bombFrame.BackgroundTransparency = 0.3
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
                
                local targetColor = cooldownActive and COLORS.COOLDOWN or COLORS.READY
                textLabel.TextColor3 = targetColor
            end
        end)
        
        updateUI("ready")
        
        bombButtonData = {
            gui = bombGui,
            frame = bombFrame,
            destroy = function()
                if bombGui then bombGui:Destroy() end
                bombButtonData = nil
                STATES.FakeBombJump.ButtonData = nil
            end
        }
        STATES.FakeBombJump.ButtonData = bombButtonData
    end
    
    local function destroyBombButton()
        if bombButtonData then
            bombButtonData.destroy()
        end
    end
    
    STATES.FakeBombJumpTemp = false
STATES.FakeBombJump = STATES.FakeBombJump or {}
STATES.FakeBombJump.Locked = false
STATES.FakeBombJumpLocked = false
    local bombToggle = createToggle(bombContainer, "Fake Bomb Jump Button", 40, STATES, "FakeBombJumpTemp", function(isEnabled)
        if isEnabled then
            createBombButton()
        else
            destroyBombButton()
        end
    end)

    local bombLockToggle = createToggle(bombContainer, "Lock Fake Bomb Button", 92, STATES, "FakeBombJumpLocked", function(isLocked)
        STATES.FakeBombJumpLocked = isLocked
        STATES.FakeBombJump.Locked = isLocked
    end)
    
    currentY = currentY + 152 + 20
    
    local grabberContainer = UTILS.createWithStaticStroke("Frame", content, {
        Name = "GrabberContainer",
        BackgroundColor3 = CONFIG.MAIN_COLOR,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 257),
        Position = UDim2.new(0, 10, 0, currentY),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", grabberContainer, {CornerRadius = UDim.new(0, 8)})
    
    UTILS.createInstance("TextLabel", grabberContainer, {
        Name = "GrabberTitle",
        Text = "Grabber",
        TextColor3 = Color3.fromRGB(225, 240, 255),
        TextSize = 16,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6
    })
    
    local function GrabGunRemote()
        local hrp = UTILS.getHRP()
        if not hrp then return false end
        
        for _, obj in pairs(workspace:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChild("GunDrop") then
                local gun = obj.GunDrop
                firetouchinterest(hrp, gun, 0)
                task.wait(0.1)
                firetouchinterest(hrp, gun, 1)
                return true
            end
        end
        return false
    end
    
    local grabGunButton = createStyledButton(grabberContainer, {
        name = "GrabGunStyledButton",
        title = "Grab Gun",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, 40),
        onClick = function()
            GrabGunRemote()
        end
    })
    
    local toggleY = 100
    
    local grabGunButtonData = nil
    
    local function createGunDropButton()
        if grabGunButtonData then return end
        
        local gunGui = UTILS.createInstance("ScreenGui", CoreGui, {
            Name = "GunDropButtonGui",
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            ResetOnSpawn = false,
            DisplayOrder = 50
        })
        
        local gunFrame = UTILS.createWithStaticStroke("Frame", gunGui, {
            Name = "GunDropFrame",
            BackgroundColor3 = CONFIG.MAIN_COLOR,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(FLOATING_STYLES.GrabGun.Size, FLOATING_STYLES.GrabGun.Size),
            Position = STATES.GrabGun.Position or UDim2.new(0, 130, 0, 46),
            AnchorPoint = Vector2.new(0, 0),
            ZIndex = 1
        })
        
        UTILS.createInstance("UICorner", gunFrame, {CornerRadius = floatingCorner(FLOATING_STYLES.GrabGun.Shape, FLOATING_STYLES.GrabGun.Size)})
        
        local backgroundGradient = UTILS.createInstance("UIGradient", gunFrame, {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
            }),
            Rotation = 90
        })
        
        local textLabel = UTILS.createInstance("TextLabel", gunFrame, {
            Name = "GunText",
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Text = "Get Gun",
            TextColor3 = Color3.fromRGB(225, 240, 255),
            TextSize = 10,
            FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
            TextScaled = false,
            TextWrapped = true,
            ZIndex = 2
        })
        
        local button = UTILS.createInstance("TextButton", gunFrame, {
            Name = "GunButton",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3
        })
        
        local isDragging = false
        local dragStartPos
        local buttonStartPos
        local dragTouchId
        local wasClick = false
        local DRAG_THRESHOLD = 5
        
        local function onDragStart(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                
                -- Locked: pode clicar, mas não pode mover.
                if STATES.GrabGun.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                isDragging = false
                wasClick = true
                dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                buttonStartPos = gunFrame.Position
                
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.18)
                
                return Enum.ContextActionResult.Sink
            end
        end
        
        local function onDrag(input)
            if STATES.GrabGun.Locked then return end
            if not dragStartPos then return end
            
            if input.UserInputType == Enum.UserInputType.Touch then
                if not dragTouchId or dragTouchId ~= input then
                    return
                end
            end
            
            local currentPos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentPos - dragStartPos
            
            if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
                isDragging = true
                wasClick = false
            end
            
            if isDragging then
                local newPosition = UDim2.new(
                    buttonStartPos.X.Scale,
                    buttonStartPos.X.Offset + delta.X,
                    buttonStartPos.Y.Scale,
                    buttonStartPos.Y.Offset + delta.Y
                )
                
                gunFrame.Position = newPosition
            end
        end
        
        local function onDragEnd(input)
            if wasClick and not isDragging then
                UTILS.playClickSound()
                GrabGunRemote()
            end
            
            gunFrame.BackgroundTransparency = 0.3
            gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
            textLabel.TextColor3 = Color3.fromRGB(225, 240, 255)
            
            if isDragging then
                local finalPosition = gunFrame.Position
                STATES.GrabGun.Position = finalPosition
            end
            
            isDragging = false
            wasClick = false
            dragStartPos = nil
            dragTouchId = nil
            buttonStartPos = nil
        end
        
        button.InputBegan:Connect(onDragStart)
        button.InputChanged:Connect(onDrag)
        button.InputEnded:Connect(onDragEnd)
        
        button.MouseEnter:Connect(function()
            if not isDragging then
                gunFrame.BackgroundTransparency = 0.2
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.12)
                textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end)
        
        button.MouseLeave:Connect(function()
            if not isDragging then
                gunFrame.BackgroundTransparency = 0.3
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
                textLabel.TextColor3 = Color3.fromRGB(225, 240, 255)
            end
        end)
        
        grabGunButtonData = {
            gui = gunGui,
            frame = gunFrame,
            destroy = function()
                if gunGui then gunGui:Destroy() end
                grabGunButtonData = nil
                STATES.GrabGun.ButtonData = nil
            end
        }
        STATES.GrabGun.ButtonData = grabGunButtonData
    end
    
    local function destroyGunDropButton()
        if grabGunButtonData then
            grabGunButtonData.destroy()
        end
    end
    
    STATES.GrabGunTemp = false
STATES.GrabGun = STATES.GrabGun or {}
STATES.GrabGun.Locked = false
STATES.GrabGunLocked = false
    local grabGunToggle = createToggle(grabberContainer, "GrabGun Button", toggleY, STATES, "GrabGunTemp", function(isEnabled)
        if isEnabled then
            createGunDropButton()
        else
            destroyGunDropButton()
        end
    end)

    local grabGunLockToggle = createToggle(grabberContainer, "Lock Grab Gun Button", toggleY + 52, STATES, "GrabGunLocked", function(isLocked)
        STATES.GrabGunLocked = isLocked
        STATES.GrabGun.Locked = isLocked
    end)
    
    toggleY = toggleY + 104
    
    local autoGrabGunActive = false
    local autoGrabGunConnection = nil
    
    STATES.AutoGrabGunTemp = false
    local autoGrabGunToggle = createToggle(grabberContainer, "AutoGrabGun", toggleY, STATES, "AutoGrabGunTemp", function(isEnabled)
        autoGrabGunActive = isEnabled
        
        if isEnabled then
            if autoGrabGunConnection then
                autoGrabGunConnection:Disconnect()
            end
            
            autoGrabGunConnection = RunService.Heartbeat:Connect(function()
                if autoGrabGunActive then
                    GrabGunRemote()
                    task.wait(0.2)
                end
            end)
        else
            if autoGrabGunConnection then
                autoGrabGunConnection:Disconnect()
                autoGrabGunConnection = nil
            end
        end
    end)
    
    return bombContainer, grabberContainer
end

function UI_SYSTEM.createAutoFarmTabContent(content)
	local currentY = 20
	
	local farmContainer = UTILS.createWithStaticStroke("Frame", content, {
		Name = "FarmContainer",
		BackgroundColor3 = CONFIG.MAIN_COLOR,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 160),
		Position = UDim2.new(0, 10, 0, currentY),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", farmContainer, {CornerRadius = UDim.new(0, 8)})
	
	local farmY = 10
	local autoFarmToggle = createToggle(farmContainer, "Auto Farm", farmY, STATES.AutoFarm, "Enabled", function(isEnabled)
		STATES.AutoFarm.Enabled = isEnabled
		if isEnabled then
			STATES.AutoFarm.Farming = true
		else
			STATES.AutoFarm.Farming = false
		end
	end)
	
	farmY = farmY + 52
	local autoResetToggle = createToggle(farmContainer, "Auto Reset (Full Bag)", farmY, STATES.AutoFarm, "Enabled", function(isEnabled)
		STATES.AutoFarm.Enabled = isEnabled
		if isEnabled then
			STATES.AutoFarm.Farming = true
		else
			STATES.AutoFarm.Farming = false
		end
	end)
	
	farmY = farmY + 52
	local autoKillToggle = createToggle(farmContainer, "Auto Kill All (Murderer)", farmY, STATES.KillAll, "Enabled", function(isEnabled)
		STATES.KillAll.Enabled = isEnabled
		if not isEnabled then 
			STATES.AutoFarm.BagFull = false 
		end
	end)
	
	currentY = currentY + 160 + 20
	
	local statsFrame = UTILS.createWithStaticStroke("Frame", content, {
		Name = "StatsContainer",
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.new(0, 10, 0, currentY),
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 5
	})
	UTILS.createInstance("UICorner", statsFrame, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", statsFrame, {
		Name = "StatsTitle",
		Text = "Farming Statistics",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6
	})
	
	local coinLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "CoinLabel",
		Text = "Coin: 0",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 25),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})

	local hourLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "HourLabel",
		Text = "Coins/hour: 0",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 45),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 255, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})

	local timeLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "TimeLabel",
		Text = "0h 0m 0s",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 65),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})
	
	RunService.Heartbeat:Connect(function()
		if STATES.AutoFarm.Enabled then
			if not FARMING_STATS.IsRunning then
				FARMING_STATS.StartTime = tick()
				FARMING_STATS.IsRunning = true
				FARMING_STATS.CoinsCollected = 0
			end
			
			local elapsed = tick() - FARMING_STATS.StartTime
			local hours = math.floor(elapsed / 3600)
			local minutes = math.floor((elapsed % 3600) / 60)
			local seconds = math.floor(elapsed % 60)
			
			timeLabel.Text = string.format("%dh %dm %ds", hours, minutes, seconds)
			coinLabel.Text = "Coin: " .. FARMING_STATS.CoinsCollected
			
			if elapsed > 0 then
				local cph = math.floor((FARMING_STATS.CoinsCollected / elapsed) * 3600)
				hourLabel.Text = "Coins/hour: " .. cph
			end
		else
			FARMING_STATS.IsRunning = false
		end
	end)
	
	return farmContainer, statsFrame
end

function UI_SYSTEM.createActMgrTabContent(content)
    local currentY = 20
    
    local joinButton = createStyledButton(content, {
        name = "JoinAnotherServer",
        title = "Join Another Server",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, currentY),
        onClick = function()
            UTILS.joinAnotherServer()
        end
    })
    
    currentY = currentY + 60
    
    local rejoinButton = createStyledButton(content, {
        name = "RejoinServer",
        title = "Rejoin",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, currentY),
        onClick = function()
            UTILS.rejoinServer()
        end
    })
    
    currentY = currentY + 60
    
    local antiAFKInterval = 5
    
    local antiAFKEnabled = false
    local antiAFKTask = nil
    
    local function getVirtualUser()
        local VirtualUser = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")
        return VirtualUser
    end
    
    local function simulateActivity()
        local VirtualUser = getVirtualUser()
        local camera = workspace.CurrentCamera
        
        if VirtualUser and camera then
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0, 0), camera.CFrame)
                task.wait(0.1)
                VirtualUser:Button2Up(Vector2.new(0, 0), camera.CFrame)
            end)
        end
    end
    
    local function toggleAntiAFK(value)
        antiAFKEnabled = value
        
        if value then
            if antiAFKTask then
                task.cancel(antiAFKTask)
                antiAFKTask = nil
            end
            
            antiAFKTask = task.spawn(function()
                while antiAFKEnabled do
                    task.wait(antiAFKInterval * 60)
                    simulateActivity()
                end
            end)
        else
            if antiAFKTask then
                task.cancel(antiAFKTask)
                antiAFKTask = nil
            end
        end
    end
    
    STATES.AntiAFKTemp = false
    local antiAFKToggle = createToggle(content, "Anti-AFK (every " .. antiAFKInterval .. " min)", currentY, STATES, "AntiAFKTemp", function(isEnabled)
        toggleAntiAFK(isEnabled)
    end)
    
    currentY = currentY + 60
    
    local antiFlingToggle = createToggle(content, "Anti-Fling", currentY, STATES.AntiFling, "Enabled", function(isEnabled)
        if isEnabled then
            ANTI_FLING.enable()
        else
            ANTI_FLING.disable()
        end
    end)
    
    currentY = currentY + 60
    
    local muteRadioToggle = createToggle(content, "Mute Radio", currentY, STATES.MuteRadio, "Enabled", function(isEnabled)
        toggleMuteRadio(isEnabled)
    end)
    
    return joinButton.container, rejoinButton.container, antiAFKToggle, antiFlingToggle, muteRadioToggle
end

-- =========================
-- YARHM / EXTRA VISUAL + COMBAT SYSTEMS
-- =========================

local function destroyDropESP(obj)
    local data = DROP_ESP.Objects[obj]
    if data then
        if data.billboard then pcall(function() data.billboard:Destroy() end) end
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
    end
    DROP_ESP.Objects[obj] = nil
end

local function getDropAdornee(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function addDropESP(obj, label, color)
    if not obj or DROP_ESP.Objects[obj] or not obj:IsDescendantOf(workspace) then return end
    local adornee = getDropAdornee(obj)
    if not adornee then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ZXNexusDropHighlight"
    highlight.Adornee = obj:IsA("Model") and obj or adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.OutlineColor = Color3.new(1, 1, 1)
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0.05
    highlight.Parent = CoreGui

    local gui = Instance.new("BillboardGui")
    gui.Name = "ZXNexusDropESP"
    gui.Adornee = adornee
    gui.Size = UDim2.fromOffset(150, 34)
    gui.StudsOffset = Vector3.new(0, 2.5, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 0
    gui.Parent = CoreGui

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = label
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0.15
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 14
    textLabel.Parent = gui

    DROP_ESP.Objects[obj] = {billboard = gui, highlight = highlight}
end

local function refreshDropESP()
    for obj in pairs(DROP_ESP.Objects) do
        if not obj.Parent then destroyDropESP(obj) end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if DROP_ESP.Gun and obj.Name == "GunDrop" then
            addDropESP(obj, "Dropped Gun", Color3.fromRGB(255, 235, 60))
        elseif DROP_ESP.Trap and obj.Name == "Trap" then
            addDropESP(obj, "Trap", Color3.fromRGB(255, 70, 70))
        end
    end
end

workspace.DescendantAdded:Connect(function(obj)
    if DROP_ESP.Gun and obj.Name == "GunDrop" then addDropESP(obj, "Dropped Gun", Color3.fromRGB(255, 235, 60)) end
    if DROP_ESP.Trap and obj.Name == "Trap" then addDropESP(obj, "Trap", Color3.fromRGB(255, 70, 70)) end
end)

local function setDropESP(kind, enabled)
    DROP_ESP[kind] = enabled
    refreshDropESP()
end

local KNIFE_THROW = {Auto = false, Connection = nil, FloatingButton = nil, FloatingEnabled = false, Locked = false}
local AUTO_SHOOT = {Enabled = false, Connection = nil}
local AUTO_GET_GUN = {Enabled = false, Connection = nil}
local function getNearestPlayer()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, distance = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local d = (plr.Character.HumanoidRootPart.Position - root.Position).Magnitude
            if d < distance then nearest, distance = plr, d end
        end
    end
    return nearest
end

local function knifeThrow()
    local target = getNearestPlayer()
    if not target or not target.Character then return end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return end
    if not char:FindFirstChild("Knife") then
        local knife = player.Backpack:FindFirstChild("Knife")
        if not knife then return end
        hum:EquipTool(knife)
        task.wait()
    end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    local hand = char:FindFirstChild("RightHand")
    local knife = char:FindFirstChild("Knife")
    if not hrp or not hand or not knife then return end
    local predicted = hrp.Position + Vector3.new(SHOOT_CONFIG.OffsetX, SHOOT_CONFIG.OffsetY, SHOOT_CONFIG.OffsetZ)
    local args = {CFrame.new(hand.Position), CFrame.new(predicted)}
    local event = knife:FindFirstChild("Events") and knife.Events:FindFirstChild("KnifeThrown")
    if event then pcall(function() event:FireServer(unpack(args)) end) end
end

local function setKnifeAuto(enabled)
    KNIFE_THROW.Auto = enabled
    if KNIFE_THROW.Connection then KNIFE_THROW.Connection:Disconnect(); KNIFE_THROW.Connection = nil end
    if enabled then
        KNIFE_THROW.Connection = task.spawn(function()
            while KNIFE_THROW.Auto do
                knifeThrow()
                task.wait(1.5)
            end
        end)
    end
end

local function createKnifeFloatingButton()
    if KNIFE_THROW.FloatingButton then return KNIFE_THROW.FloatingButton end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ZXNexusKnifeThrowFloating"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 80
    gui.Parent = CoreGui

    local frame = Instance.new("Frame")
    frame.Name = "KnifeThrowButton"
    frame.Size = UDim2.fromOffset(64, 64)
    frame.Position = UDim2.new(0, 210, 0, 46)
    frame.BackgroundColor3 = CONFIG.MAIN_COLOR
    frame.BorderSizePixel = 0
    frame.Parent = gui
    applyFloatingShape(frame, "Circle", 64)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "Knife"
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = frame

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.fromScale(1, 1)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.Parent = frame

    local dragging, dragStart, startPos, moved = false, nil, nil, false
    hit.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if KNIFE_THROW.Locked then
            moved = false
            return
        end
        dragging, moved = false, false
        dragStart, startPos = Vector2.new(input.Position.X, input.Position.Y), frame.Position
    end)
    hit.InputChanged:Connect(function(input)
        if not dragStart or KNIFE_THROW.Locked then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if delta.Magnitude > 5 then dragging, moved = true, true end
        if dragging then
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    hit.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not moved then knifeThrow() end
        dragStart = nil
        dragging = false
    end)

    KNIFE_THROW.FloatingButton = {gui = gui, frame = frame}
    return KNIFE_THROW.FloatingButton
end

local function destroyKnifeFloatingButton()
    if KNIFE_THROW.FloatingButton and KNIFE_THROW.FloatingButton.gui then
        KNIFE_THROW.FloatingButton.gui:Destroy()
    end
    KNIFE_THROW.FloatingButton = nil
end

local function setKnifeFloating(enabled)
    KNIFE_THROW.FloatingEnabled = enabled
    if enabled then createKnifeFloatingButton() else destroyKnifeFloatingButton() end
end

local function setAutoShoot(enabled)
    AUTO_SHOOT.Enabled = enabled
    if AUTO_SHOOT.Connection then AUTO_SHOOT.Connection:Disconnect(); AUTO_SHOOT.Connection = nil end
    if enabled then
        AUTO_SHOOT.Connection = RunService.Heartbeat:Connect(function()
            if not AUTO_SHOOT.Enabled then return end
            local data = STATES.ShootMurderer.ButtonData
            if data and data.shoot then
                data.shoot()
            end
        end)
    end
end

local function setAutoGetGun(enabled)
    AUTO_GET_GUN.Enabled = enabled
    if AUTO_GET_GUN.Connection then
        task.cancel(AUTO_GET_GUN.Connection)
        AUTO_GET_GUN.Connection = nil
    end

    if enabled then
        -- Deliberately NOT Heartbeat + GetDescendants: that combination was causing huge FPS drops.
        AUTO_GET_GUN.Connection = task.spawn(function()
            local cachedGun = nil

            while AUTO_GET_GUN.Enabled do
                if not cachedGun or not cachedGun.Parent then
                    -- Low-frequency lookup; at most ~4 searches/sec instead of every frame.
                    cachedGun = workspace:FindFirstChild("GunDrop", true)
                end

                local root = UTILS.getHRP()
                if root and cachedGun and cachedGun:IsA("BasePart") then
                    firetouchinterest(root, cachedGun, 0)
                    task.wait(0.03)
                    firetouchinterest(root, cachedGun, 1)
                    task.wait(0.20)
                else
                    task.wait(0.35)
                end
            end
        end)
    end
end


-- =========================
-- YARHM / EXTRA COMBAT SYSTEMS
-- =========================

local ROLE_HELPERS = {}

function ROLE_HELPERS.findByRoleItem(itemName)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Backpack:FindFirstChild(itemName) or (plr.Character and plr.Character:FindFirstChild(itemName)) then
            return plr
        end
    end
end

function ROLE_HELPERS.getMurderer()
    return ROLE_HELPERS.findByRoleItem("Knife")
end

function ROLE_HELPERS.getSheriffOrHero()
    return ROLE_HELPERS.findByRoleItem("Gun")
end

-- YARHM anti-fling logic adapted to ZXNexus/WindUI.
function YARHM_ANTI_FLING.enable()
    if YARHM_ANTI_FLING.Enabled then return end
    YARHM_ANTI_FLING.Enabled = true
    YARHM_ANTI_FLING.LastPos = Vector3.zero

    YARHM_ANTI_FLING.Detection = RunService.Heartbeat:Connect(function()
        if not YARHM_ANTI_FLING.Enabled then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and plr.Character and plr.Character:IsDescendantOf(workspace) and plr.Character.PrimaryPart then
                local root = plr.Character.PrimaryPart
                if root.AssemblyAngularVelocity.Magnitude > 50 or root.AssemblyLinearVelocity.Magnitude > 100 then
                    for _, part in ipairs(plr.Character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                            part.AssemblyAngularVelocity = Vector3.zero
                            part.AssemblyLinearVelocity = Vector3.zero
                            pcall(function()
                                part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0)
                            end)
                        end
                    end
                end
            end
        end
    end)

    YARHM_ANTI_FLING.Neutralizer = RunService.Heartbeat:Connect(function()
        local char = player.Character
        local root = char and char.PrimaryPart
        if not root then return end

        if root.AssemblyLinearVelocity.Magnitude > 250 or root.AssemblyAngularVelocity.Magnitude > 250 then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if YARHM_ANTI_FLING.LastPos ~= Vector3.zero then
                root.CFrame = CFrame.new(YARHM_ANTI_FLING.LastPos)
            end
        else
            YARHM_ANTI_FLING.LastPos = root.Position
        end
    end)
end

function YARHM_ANTI_FLING.disable()
    YARHM_ANTI_FLING.Enabled = false
    if YARHM_ANTI_FLING.Detection then YARHM_ANTI_FLING.Detection:Disconnect() end
    if YARHM_ANTI_FLING.Neutralizer then YARHM_ANTI_FLING.Neutralizer:Disconnect() end
    YARHM_ANTI_FLING.Detection = nil
    YARHM_ANTI_FLING.Neutralizer = nil
end

local function yarhmSkidFling(targetPlayer)
    if not targetPlayer or targetPlayer == player or not targetPlayer.Character then return false end
    if YARHM_ANTI_FLING.Enabled then return false end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local targetCharacter = targetPlayer.Character
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    local targetRoot = targetHumanoid and targetHumanoid.RootPart
    local targetHead = targetCharacter and targetCharacter:FindFirstChild("Head")

    if not character or not humanoid or not root or not targetCharacter or not targetHumanoid then return false end
    local basePart = targetHead or targetRoot
    if not basePart then return false end

    local oldPos = root.CFrame
    local oldFallen = workspace.FallenPartsDestroyHeight
    workspace.FallenPartsDestroyHeight = 0/0

    local bv = Instance.new("BodyVelocity")
    bv.Name = "ZXNexusEpixVel"
    bv.Velocity = Vector3.new(9e8, 9e8, 9e8)
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = root

    local ok = pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        local start = tick()
        local angle = 0
        repeat
            if not root.Parent or not basePart.Parent or targetPlayer.Parent ~= Players or humanoid.Health <= 0 then break end
            angle += 100
            local mv = targetHumanoid.MoveDirection * math.max(basePart.AssemblyLinearVelocity.Magnitude, 1) / 1.25
            root.CFrame = CFrame.new(basePart.Position) * CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
            character:SetPrimaryPartCFrame(root.CFrame)
            root.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
            root.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
            task.wait()
            root.CFrame = CFrame.new(basePart.Position) * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
            character:SetPrimaryPartCFrame(root.CFrame)
            task.wait()
            if basePart.AssemblyLinearVelocity.Magnitude > 500 then break end
        until tick() > start + 2
    end)

    bv:Destroy()
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
    root.CFrame = oldPos * CFrame.new(0, .5, 0)
    character:SetPrimaryPartCFrame(root.CFrame)
    workspace.FallenPartsDestroyHeight = oldFallen
    return ok
end

local function aimlockUpdate()
    if not AIMLOCK.Enabled then return end
    if ROLE_HELPERS.getSheriffOrHero() ~= player then return end
    local target = ROLE_HELPERS.getMurderer()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if target and hrp and hum and hum.Health > 0 then
        local cam = workspace.CurrentCamera
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, hrp.Position)
    end
end

local function setAimlock(enabled)
    AIMLOCK.Enabled = enabled
    if AIMLOCK.Connection then AIMLOCK.Connection:Disconnect() AIMLOCK.Connection = nil end
    if enabled then
        AIMLOCK.Connection = RunService.RenderStepped:Connect(aimlockUpdate)
    end
end

local function clearHitboxESP()
    for _, obj in pairs(HITBOX_ESP.Objects) do
        pcall(function() obj:Destroy() end)
    end
    HITBOX_ESP.Objects = {}
end

local function updateHitboxESP()
    clearHitboxESP()
    if not HITBOX_ESP.Enabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local adorn = Instance.new("BoxHandleAdornment")
                adorn.Name = "ZXNexusHitboxESP"
                adorn.Adornee = root
                adorn.AlwaysOnTop = true
                adorn.ZIndex = 5
                adorn.Size = Vector3.new(HITBOX_ESP.Size, HITBOX_ESP.Size, HITBOX_ESP.Size)
                adorn.Transparency = 0.75
                adorn.Color3 = CONFIG.MAIN_COLOR
                adorn.Parent = workspace.Terrain
                HITBOX_ESP.Objects[plr] = adorn
            end
        end
    end
end

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if HITBOX_ESP.Enabled then updateHitboxESP() end
        if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then ESP_SYSTEM.StartAllLines() end
    end)
end)

-- Webhook: username + executor + local date/time.
local WEBHOOK_URL = "https://discord.com/api/webhooks/1541130654945771621/LQBw768SmR2k1JzpW8nSw0nPTyUVfYu2y-77cTLBfXd-gHbmJFyWn1SQCcIyej-SKTie"
local function sendLoadWebhook()
    local request = (syn and syn.request) or (http and http.request) or request or http_request
    if not request then return end
    local HttpService = game:GetService("HttpService")
    local executor = identifyexecutor or getexecutorname
    local executorName = executor and executor() or "Unknown"
    local payload = {
        username = "ZXNexus",
        embeds = {{
            title = "ZXNexus loaded",
            color = 3447003,
            fields = {
                {name = "User", value = tostring(player.Name), inline = true},
                {name = "Executor", value = tostring(executorName), inline = true},
                {name = "Game", value = tostring(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name), inline = true},
                {name = "Date / Time", value = os.date("%Y-%m-%d %H:%M:%S"), inline = false},
            },
            thumbnail = {
                url = ("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png"):format(player.UserId)
            },
            footer = {text = "Made by CrisZX"}
        }}
    }
    pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- Основная инициализация
function UI_SYSTEM.init()
    -- Keep the original UI builders alive as a hidden callback bridge.
    -- The visible interface is 100% WindUI; floating buttons remain native ScreenGuis.
    local legacyGui = UTILS.createInstance("ScreenGui", CoreGui, {
        Name = "ZXNexusLegacyUIBridge",
        ResetOnSpawn = false,
        DisplayOrder = -100,
        Enabled = false,
    })

    local function makeLegacyContent(name)
        local frame = UTILS.createInstance("Frame", legacyGui, {
            Name = name,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(1, 1),
        })
        return frame
    end

    -- Build the original controls invisibly so every original callback/function
    -- remains intact. Nothing from this bridge is shown to the player.
    UI_SYSTEM.createMainTabContent(makeLegacyContent("Main"))
    UI_SYSTEM.createVisualTabContent(makeLegacyContent("Visual"))
    UI_SYSTEM.createCombatTabContent(makeLegacyContent("Combat"))
    UI_SYSTEM.createTeleportTabContent(makeLegacyContent("Teleport"))
    UI_SYSTEM.createAutoFarmTabContent(makeLegacyContent("AutoFarm"))
    UI_SYSTEM.createActMgrTabContent(makeLegacyContent("ActMgr"))

    local ok, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not WindUI then
        error("ZXNexus: failed to load WindUI")
    end

    local Window = WindUI:CreateWindow({
        Title = "Murder Mystery 2 | ZXNexus",
        Author = "ZXNexus",
        Icon = "gamepad-2",
        Folder = "ZXNexus_MM2",
        Theme = "Midnight",
        Size = UDim2.fromOffset(672, 624),
        MinSize = Vector2.new(600, 520),
        MaxSize = Vector2.new(900, 760),
        Resizable = true,
        HideSearchBar = false,
        OpenButton = {
            Title = "Open ZXNexus",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.55,
        },
        Topbar = {
            Height = 44,
            ButtonsType = "Default",
        },
    })

    local function bindToggle(tab, title)
        local entry = LEGACY_TOGGLES[title]
        if not entry then
            warn("ZXNexus WindUI: missing legacy toggle: " .. title)
            return nil
        end

        return tab:Toggle({
            Title = title,
            Value = entry.stateTable[entry.stateKey] == true,
            Callback = function(value)
                entry.stateTable[entry.stateKey] = value
                if entry.callback then
                    task.spawn(entry.callback, value)
                end
            end,
        })
    end

    local function bindButton(tab, title, icon)
        local callback = LEGACY_BUTTONS[title]
        if not callback then
            warn("ZXNexus WindUI: missing legacy button: " .. title)
            return nil
        end

        return tab:Button({
            Title = title,
            Icon = icon or "play",
            Callback = function()
                task.spawn(callback)
            end,
        })
    end

    local tabs = {}
    tabs.Main = Window:Tab({Title = "Changelogs", Icon = "scroll-text"})
    tabs.Movement = Window:Tab({Title = "Movement", Icon = "move"})
    tabs.Visual = Window:Tab({Title = "Visual", Icon = "eye"})
    tabs.Sheriff = Window:Tab({Title = "Sheriff", Icon = "crosshair"})
    tabs.Murderer = Window:Tab({Title = "Murderer", Icon = "skull"})
    tabs.Innocent = Window:Tab({Title = "Innocent", Icon = "shield"})
    tabs.Optimization = Window:Tab({Title = "Optimization", Icon = "gauge"})
    tabs.Teleport = Window:Tab({Title = "Teleport", Icon = "map-pin"})
    tabs.AutoFarm = Window:Tab({Title = "Auto Farm", Icon = "coins"})
    tabs.Emote = Window:Tab({Title = "Emote", Icon = "smile"})
    tabs.Misc = Window:Tab({Title = "Misc", Icon = "sliders-horizontal"})

    -- Changelogs / tester warning
    tabs.Main:Paragraph({
        Title = "ZXNexus — Tester Build",
        Desc = "This version of the script is for TESTERS ONLY. Any leaked version of this script will result in a BAN.",
    })
    tabs.Main:Paragraph({
        Title = "Changelog",
        Desc = "WindUI migration • role-based tabs • configurable FloatingButtons • improved ESP/tracers • YARHM integrations • server rejoin/server hop.",
    })
    tabs.Main:Paragraph({
        Title = "Credits",
        Desc = "Made by CrisZX",
    })

    -- Movement
    tabs.Movement:Section({Title = "Movement"})
    bindToggle(tabs.Movement, "Speed Walk")
    tabs.Movement:Slider({
        Title = "Walk Speed",
        Step = 1,
        Value = {Min = 16, Max = 116, Default = STATES.Movement.SpeedWalk.Value},
        Callback = function(v)
            STATES.Movement.SpeedWalk.Value = v
            if STATES.Movement.SpeedWalk.Enabled then MOVEMENT.updateWalkSpeed() end
        end,
    })
    bindToggle(tabs.Movement, "Jump Power")
    tabs.Movement:Slider({
        Title = "Jump Power",
        Step = 1,
        Value = {Min = 50, Max = 150, Default = STATES.Movement.JumpPower.Value},
        Callback = function(v)
            STATES.Movement.JumpPower.Value = v
            if STATES.Movement.JumpPower.Enabled then MOVEMENT.updateJumpPower() end
        end,
    })

    -- Visual
    tabs.Visual:Section({Title = "Player ESP"})
    for _, title in ipairs({"ESP Name", "Murderer Name", "Sheriff Name", "Hero Name", "Innocent Name"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Section({Title = "Highlights"})
    for _, title in ipairs({"ESP Highlight", "ESP Highlight Murderer", "ESP Highlight Sheriff", "ESP Highlight Hero", "ESP Highlight Innocent"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Section({Title = "ESP Lines"})
    for _, title in ipairs({"ESP Tracer", "Murderer Tracer", "Sheriff Tracer", "Hero Tracer", "Innocent Tracer"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Paragraph({Title = "Line behavior", Desc = "ESP Lines disappear when the target leaves your camera viewport and reappear when the target returns."})
    tabs.Visual:Section({Title = "YARHM ESP"})
    tabs.Visual:Toggle({Title = "ESP Gun", Value = false, Callback = function(v) setDropESP("Gun", v) end})
    tabs.Visual:Toggle({Title = "ESP Trap", Value = false, Callback = function(v) setDropESP("Trap", v) end})
    tabs.Visual:Section({Title = "Hitbox ESP"})
    tabs.Visual:Toggle({Title = "Hitbox ESP", Value = HITBOX_ESP.Enabled, Callback = function(v) HITBOX_ESP.Enabled = v; updateHitboxESP() end})
    tabs.Visual:Slider({Title = "Hitbox Size", Step = 1, Value = {Min = 2, Max = 16, Default = HITBOX_ESP.Size}, Callback = function(v) HITBOX_ESP.Size = v; if HITBOX_ESP.Enabled then updateHitboxESP() end end})

    -- Sheriff
    tabs.Sheriff:Section({Title = "Sheriff / Hero"})
    tabs.Sheriff:Paragraph({
        Title = "Aimlock warning",
        Desc = "Aimlock only works when YOUR role is Sheriff or Hero.",
    })
    tabs.Sheriff:Toggle({
        Title = "AutoShoot",
        Value = AUTO_SHOOT.Enabled,
        Callback = function(v)
            if v and not STATES.ShootMurderer.ButtonData then
                STATES.ShootMurderer.ButtonData = UI_SYSTEM.createShootMurdererButton()
            end
            setAutoShoot(v)
        end,
    })
    bindToggle(tabs.Sheriff, "Shoot The Murderer")
    bindToggle(tabs.Sheriff, "Lock Shoot Button")
    tabs.Sheriff:Toggle({Title = "Aimlock on Murderer", Desc = "Sheriff / Hero only.", Value = false, Callback = setAimlock})
    tabs.Sheriff:Button({Title = "Fling Sheriff", Icon = "wind", Callback = function()
        local target = ROLE_HELPERS.getSheriffOrHero()
        if target and target ~= player then yarhmSkidFling(target) end
    end})
    tabs.Sheriff:Button({Title = "Fling Murderer", Icon = "wind", Callback = function()
        local target = ROLE_HELPERS.getMurderer()
        if target and target ~= player then yarhmSkidFling(target) end
    end})

    tabs.Sheriff:Section({Title = "Shoot on Murderer — Prediction"})
    tabs.Sheriff:Paragraph({Title = "Default profile", Desc = "Vertical 0.50 • Horizontal 0.75 • 3 simulations • 0.03s interval • lag/ping/jump/sharp enabled."})
    tabs.Sheriff:Slider({Title = "Vertical Multiplier", Step = 0.05, Value = {Min = 0, Max = 2, Default = SHOOT_CONFIG.VerticalMultiplier}, Callback = function(v) SHOOT_CONFIG.VerticalMultiplier = v end})
    tabs.Sheriff:Slider({Title = "Horizontal Multiplier", Step = 0.05, Value = {Min = 0, Max = 2, Default = SHOOT_CONFIG.HorizontalMultiplier}, Callback = function(v) SHOOT_CONFIG.HorizontalMultiplier = v end})
    tabs.Sheriff:Slider({Title = "Simulations", Step = 1, Value = {Min = 1, Max = 20, Default = SHOOT_CONFIG.Simulations}, Callback = function(v) SHOOT_CONFIG.Simulations = v end})
    tabs.Sheriff:Slider({Title = "Interval", Step = 0.01, Value = {Min = 0.01, Max = 0.20, Default = SHOOT_CONFIG.Interval}, Callback = function(v) SHOOT_CONFIG.Interval = v end})
    tabs.Sheriff:Slider({Title = "Offset X", Step = 0.5, Value = {Min = -10, Max = 10, Default = SHOOT_CONFIG.OffsetX}, Callback = function(v) SHOOT_CONFIG.OffsetX = v end})
    tabs.Sheriff:Slider({Title = "Offset Y", Step = 0.5, Value = {Min = -10, Max = 10, Default = SHOOT_CONFIG.OffsetY}, Callback = function(v) SHOOT_CONFIG.OffsetY = v end})
    tabs.Sheriff:Slider({Title = "Offset Z", Step = 0.5, Value = {Min = -10, Max = 10, Default = SHOOT_CONFIG.OffsetZ}, Callback = function(v) SHOOT_CONFIG.OffsetZ = v end})
    tabs.Sheriff:Toggle({Title = "Predict Lag", Value = SHOOT_CONFIG.PredictLag, Callback = function(v) SHOOT_CONFIG.PredictLag = v end})
    tabs.Sheriff:Toggle({Title = "Prioritize Ping", Value = SHOOT_CONFIG.PrioritizePing, Callback = function(v) SHOOT_CONFIG.PrioritizePing = v end})
    tabs.Sheriff:Toggle({Title = "Predict Jump", Value = SHOOT_CONFIG.PredictJump, Callback = function(v) SHOOT_CONFIG.PredictJump = v end})
    tabs.Sheriff:Toggle({Title = "Sharp Shooter", Value = SHOOT_CONFIG.SharpShooter, Callback = function(v) SHOOT_CONFIG.SharpShooter = v end})

    -- Murderer
    tabs.Murderer:Section({Title = "Murderer"})
    bindToggle(tabs.Murderer, "Auto Kill All (Murderer)")
    tabs.Murderer:Button({Title = "Kill All", Icon = "skull", Callback = function() KILL_ALL.killAllPlayers() end})
    tabs.Murderer:Button({Title = "Throw Knife", Icon = "swords", Callback = knifeThrow})
    tabs.Murderer:Toggle({Title = "Auto Throw Knife", Value = KNIFE_THROW.Auto, Callback = setKnifeAuto})
    tabs.Murderer:Toggle({Title = "Throw Knife FloatingButton", Value = KNIFE_THROW.FloatingEnabled, Callback = setKnifeFloating})
    tabs.Murderer:Toggle({Title = "Lock Throw Knife FloatingButton", Value = KNIFE_THROW.Locked, Callback = function(v) KNIFE_THROW.Locked = v end})

    -- Innocent
    tabs.Innocent:Section({Title = "Innocent / Get Gun"})
    tabs.Innocent:Paragraph({Title = "Get Gun", Desc = "Use these controls when you are Innocent and want to obtain the dropped gun."})
    bindButton(tabs.Innocent, "Grab Gun", "crosshair")
    tabs.Innocent:Toggle({Title = "Auto Get Gun", Value = AUTO_GET_GUN.Enabled, Callback = setAutoGetGun})
    bindToggle(tabs.Innocent, "GrabGun Button")
    bindToggle(tabs.Innocent, "Lock Grab Gun Button")

    -- Optimization
    tabs.Optimization:Paragraph({
        Title = "Coming Soon",
        Desc = "Additional optimization and performance features are coming soon.",
    })
    tabs.Optimization:Section({Title = "Available"})
    tabs.Optimization:Toggle({
        Title = "Anti-Fling",
        Desc = "YARHM anti-fling implementation.",
        Value = false,
        Callback = function(v) if v then YARHM_ANTI_FLING.enable() else YARHM_ANTI_FLING.disable() end end,
    })
    bindToggle(tabs.Optimization, "Anti-AFK (every 5 min)")
    bindToggle(tabs.Optimization, "Mute Radio")
    bindToggle(tabs.Optimization, "Performance (Ping & Fps)")

    -- Teleport
    tabs.Teleport:Section({Title = "Servers"})
    tabs.Teleport:Button({Title = "Rejoin Current Server", Icon = "refresh-cw", Callback = UTILS.rejoinServer})
    tabs.Teleport:Button({Title = "Server Hop", Icon = "shuffle", Callback = UTILS.joinAnotherServer})
    tabs.Teleport:Paragraph({Title = "Rejoin", Desc = "Returns to the exact current server instance."})
    tabs.Teleport:Paragraph({Title = "Server Hop", Desc = "Finds another public server for the same game."})

    -- Auto Farm
    tabs.AutoFarm:Section({Title = "Farm"})
    bindToggle(tabs.AutoFarm, "Auto Farm")
    bindToggle(tabs.AutoFarm, "Auto Reset (Full Bag)")

    -- Emote
    tabs.Emote:Paragraph({
        Title = "Emote",
        Desc = "Emote functionality will be added later. Coming soon.",
    })

    -- Misc / FloatingButtons
    tabs.Misc:Section({Title = "Bomb Jump"})
    bindToggle(tabs.Misc, "Fake Bomb Jump Button")
    bindToggle(tabs.Misc, "Lock Fake Bomb Button")

    local function addFloatingStyleControls(tab, title, state, d)
        tab:Section({Title = title})
        tab:Slider({Title = "Width", Step = 2, Value = {Min = 40, Max = 300, Default = state.Size}, Callback = function(v)
            state.Size = v
            if d() then d().frame.Size = UDim2.fromOffset(v, state.Height) end
        end})
        tab:Slider({Title = "Height", Step = 2, Value = {Min = 40, Max = 160, Default = state.Height}, Callback = function(v)
            state.Height = v
            if d() then d().frame.Size = UDim2.fromOffset(state.Size, v) end
        end})
        tab:Dropdown({Title = "Shape", Values = {"Square","Rounded","Pill","Circle","Diamond","Octagon","Hexagon"}, Value = state.Shape, Callback = function(v)
            state.Shape = v
            if d() then applyFloatingShape(d().frame, v, math.max(state.Size, state.Height)) end
        end})
    end

    addFloatingStyleControls(tabs.Misc, "Shoot Murderer FloatingButton", FLOATING_STYLES.ShootMurderer, function() return STATES.ShootMurderer.ButtonData end)
    addFloatingStyleControls(tabs.Misc, "Fake Bomb Jump FloatingButton", FLOATING_STYLES.FakeBombJump, function() return STATES.FakeBombJump.ButtonData end)
    addFloatingStyleControls(tabs.Misc, "Get Gun FloatingButton", FLOATING_STYLES.GrabGun, function() return STATES.GrabGun.ButtonData end)
    tabs.Misc:Section({Title = "Knife Throw FloatingButton"})
    tabs.Misc:Slider({Title = "Knife Width", Step = 2, Value = {Min = 40, Max = 120, Default = 64}, Callback = function(v)
        if KNIFE_THROW.FloatingButton then KNIFE_THROW.FloatingButton.frame.Size = UDim2.fromOffset(v, KNIFE_THROW.FloatingButton.frame.Size.Y.Offset) end
    end})
    tabs.Misc:Slider({Title = "Knife Height", Step = 2, Value = {Min = 40, Max = 120, Default = 64}, Callback = function(v)
        if KNIFE_THROW.FloatingButton then KNIFE_THROW.FloatingButton.frame.Size = UDim2.fromOffset(KNIFE_THROW.FloatingButton.frame.Size.X.Offset, v) end
    end})
    tabs.Misc:Dropdown({Title = "Knife Shape", Values = {"Square","Rounded","Pill","Circle","Diamond","Octagon","Hexagon"}, Value = "Circle", Callback = function(v)
        if KNIFE_THROW.FloatingButton then applyFloatingShape(KNIFE_THROW.FloatingButton.frame, v, math.max(KNIFE_THROW.FloatingButton.frame.Size.X.Offset, KNIFE_THROW.FloatingButton.frame.Size.Y.Offset)) end
    end})
    Window:Tag({Title = "MM2", Icon = "gamepad-2", Border = true})

    -- The legacy bridge stays disabled; WindUI is the visible interface.
    UI_ELEMENTS.MainFrame = nil

    return Window, legacyGui
end

local function init()
    local screenGui, openCloseGui = UI_SYSTEM.init()

    REMOTE_SYSTEM.findRemoteEvents()
    REMOTE_SYSTEM.connectRemoteEvents()

    FARMING.startFarmingLoop()
    KILL_ALL.startKillAllLoop()

    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        task.wait(0.1)
        MOVEMENT.updateWalkSpeed()
        MOVEMENT.updateJumpPower()
    end)

    if player.Character and player.Character:FindFirstChild("Humanoid") then
        MOVEMENT.updateWalkSpeed()
        MOVEMENT.updateJumpPower()
    end

    local espConnection
    local highlightConnection

    espConnection = RunService.Heartbeat:Connect(function()
        if ESP_SYSTEM.ESP_STATES.ESPName then
            ESP_SYSTEM.updateESP()
        else
            ESP_SYSTEM.clearAllESP()
        end
    end)

    highlightConnection = RunService.Heartbeat:Connect(function()
        if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
            ESP_SYSTEM.updateHighlights()
        else
            ESP_SYSTEM.clearAllHighlights()
        end
    end)

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            ESP_SYSTEM.initializePlayer(targetPlayer)
        end
    end

    Players.PlayerAdded:Connect(function(targetPlayer)
        if targetPlayer ~= player then
            ESP_SYSTEM.initializePlayer(targetPlayer)
        end
    end)

    Players.PlayerRemoving:Connect(function(targetPlayer)
        if targetPlayer ~= player then
            ESP_SYSTEM.removePlayerBillboard(targetPlayer)
            ESP_SYSTEM.removePlayerHighlight(targetPlayer)
            ESP_SYSTEM.RemoveLineForPlayer(targetPlayer.Name)
        end
    end)

    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        ESP_SYSTEM.Camera = workspace.CurrentCamera
    end)
    
    Players.PlayerAdded:Connect(function(newPlayer)
        if newPlayer ~= player and ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
            local conn = ESP_SYSTEM.InitializePlayerLines(newPlayer)
            table.insert(lineConnections, conn)
        end
    end)

    task.spawn(sendLoadWebhook)
    task.spawn(function()
        while task.wait(1) do
            if HITBOX_ESP.Enabled then updateHitboxESP() end
            if DROP_ESP.Gun or DROP_ESP.Trap then refreshDropESP() end
        end
    end)

    return screenGui, openCloseGui
end

return init()
