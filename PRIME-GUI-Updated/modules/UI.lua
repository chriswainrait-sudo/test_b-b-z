local SHOW_LOGO_ON_PC = false

return {Exports={"userInputService","TweenService","Players","RunService","ReplicatedStorage","Workspace","StarterGui","GuiService","LocalPlayer","PlayerGui","GetGuiParent","GuiParent","IsMobileDevice","IS_MOBILE","SHOW_RESTORE_BUTTON","NexusUI","ScriptUnloaded","ScriptConnections","UnloadCallbacks","GuiConnections","TrackGuiConnection","TrackScriptConnection","RegisterUnloadCallback","PRIME_TIER","IS_PREMIUM_USER","Clamp","MAIN_WINDOW_TRANSPARENCY","GUI_BUTTON_TRANSPARENCY","GUI_PANEL_TRANSPARENCY","GUI_OVERLAY_TRANSPARENCY","GUI_DISABLED_TRANSPARENCY","ACCENT","COLOR_WINDOW","COLOR_TOPBAR","COLOR_GROUP","COLOR_CONTROL","COLOR_BORDER","COLOR_TEXT","COLOR_TEXT_DIM","COLOR_ON_ACCENT","ApplyButtonStyle","CreateClickButton","ConnectClick","windowSize","Window","Tabs","currentCloseKey","waitingForKey","SettingsSection","keybindRow","keybindRowCorner","keybindTitle","keybindHint","keybindBadge","keybindBadgeCorner","keybindBadgeStroke","keybindBadgeLabel","UpdateKeybindBadge","SetGUIKey","BeginKeyBinding"},Init=function()


userInputService = game:GetService("UserInputService")
TweenService = game:GetService("TweenService")
Players = game:GetService("Players")
RunService = game:GetService("RunService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
Workspace = game:GetService("Workspace")
StarterGui = game:GetService("StarterGui")
GuiService = game:GetService("GuiService")
LocalPlayer = Players.LocalPlayer
PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

function GetGuiParent()
    local function writable(parent)
        if typeof(parent) ~= "Instance" then return false end
        if parent == PlayerGui or parent:IsDescendantOf(PlayerGui) then return false end
        local probe = Instance.new("ScreenGui")
        local ok = pcall(function() probe.Parent = parent end)
        pcall(function() probe:Destroy() end)
        return ok
    end
    local ok, hui = pcall(function()
        return type(gethui) == "function" and gethui() or nil
    end)
    if ok and writable(hui) then
        return hui
    end
    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and writable(coreGui) then
        return coreGui
    end
    return nil
end

GuiParent = GetGuiParent()
if not GuiParent then return end

function IsMobileDevice()
    local success, platform = pcall(function()
        return userInputService:GetPlatform()
    end)

    if success then
        return platform == Enum.Platform.Android or platform == Enum.Platform.IOS
    end

    return userInputService.TouchEnabled and not userInputService.KeyboardEnabled
end

IS_MOBILE = IsMobileDevice()
SHOW_RESTORE_BUTTON = IS_MOBILE or SHOW_LOGO_ON_PC

NexusUI = {
    Options = {},
    State = {},
    Toggles = {}
}

ScriptUnloaded = false
ScriptConnections = {}
UnloadCallbacks = {}
GuiConnections = {}

function TrackGuiConnection(connection)
    if connection then
        table.insert(GuiConnections, connection)
    end
    return connection
end

function TrackScriptConnection(connection)
    if connection then
        table.insert(ScriptConnections, connection)
    end
    return connection
end

function RegisterUnloadCallback(callback)
    if callback then
        table.insert(UnloadCallbacks, callback)
    end
end

function NexusUI:UnloadFeatures()
    if ScriptUnloaded then
        return
    end
    ScriptUnloaded = true

    for _, toggle in pairs(self.Toggles) do
        if toggle.Value then
            pcall(function()
                toggle:SetValue(false)
            end)
        end
    end

    for index = #UnloadCallbacks, 1, -1 do
        pcall(UnloadCallbacks[index])
    end
    table.clear(UnloadCallbacks)

    for _, connection in ipairs(ScriptConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(ScriptConnections)
    table.clear(self.Toggles)
    table.clear(self.Options)
    table.clear(self.State)
end

PRIME_TIER = type(_G.PRIME_TIER) == "string" and _G.PRIME_TIER or "Freemium"
IS_PREMIUM_USER = string.lower(PRIME_TIER) == "premium"

function Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Fonts: wide techno face for titles, clean geometric face for everything else.
local FONT_BODY = "rbxasset://fonts/families/TitilliumWeb.json"
local FONT_TITLE = "rbxasset://fonts/families/Michroma.json"

-- Window background gradient (top-left light -> bottom-right deep black).
local function windowGradient()
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 38, 41)),
        ColorSequenceKeypoint.new(0.35, Color3.fromRGB(17, 17, 19)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(8, 8, 9)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 16)),
    })
    g.Rotation = 35
    return g
end

-- Silver border that fades from the top-left corner.
local function borderGradient()
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 150, 156)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(52, 52, 56)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(88, 88, 94)),
    })
    g.Rotation = 35
    return g
end

-- Whole GUI uses Michroma, max size 11, uppercase. Applied automatically to every
-- text object under a styled root, including text that changes later.
-- Objects with the "KeepFont" attribute (and pure symbols like ✓ › ◢) are left alone.
local TEXT_FONT = Font.new(FONT_TITLE, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TEXT_MAX_SIZE = 11

local function styleText(obj)
    local isBox = obj:IsA("TextBox")
    if not (isBox or obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
    if obj:GetAttribute("KeepFont") then return end

    local function apply()
        if obj:GetAttribute("KeepFont") then return end
        if isBox then
            local placeholder = string.upper(obj.PlaceholderText)
            if placeholder ~= obj.PlaceholderText then obj.PlaceholderText = placeholder end
        else
            if not string.find(obj.Text, "%a") then return end
            local upper = string.upper(obj.Text)
            if upper ~= obj.Text then obj.Text = upper end
        end
        if obj.FontFace.Family ~= FONT_TITLE or obj.FontFace.Weight ~= Enum.FontWeight.Regular then
            obj.FontFace = TEXT_FONT
        end
        if obj.TextSize > TEXT_MAX_SIZE then obj.TextSize = TEXT_MAX_SIZE end
    end

    apply()
    TrackGuiConnection(obj:GetPropertyChangedSignal(isBox and "PlaceholderText" or "Text"):Connect(apply))
    TrackGuiConnection(obj:GetPropertyChangedSignal("TextSize"):Connect(apply))
    TrackGuiConnection(obj:GetPropertyChangedSignal("FontFace"):Connect(apply))
end

local function attachTextStyler(root)
    for _, descendant in ipairs(root:GetDescendants()) do
        styleText(descendant)
    end
    TrackGuiConnection(root.DescendantAdded:Connect(styleText))
end

MAIN_WINDOW_TRANSPARENCY = 0
GUI_BUTTON_TRANSPARENCY = 0.25
GUI_PANEL_TRANSPARENCY = 0.35
GUI_OVERLAY_TRANSPARENCY = 0
GUI_DISABLED_TRANSPARENCY = 0.78

local themes = {
    Noir = {{255,255,255},{1,1,2},{5,5,6},{8,8,9},{13,13,14},{43,43,47},{248,248,248},{125,125,132},{0,0,0}}
}
local bindings = setmetatable({}, {__mode = "k"})
local colorRoles = {}
NexusUI.ThemeName = "Noir"
NexusUI.ThemeRefresh = {}
local function setPalette(name)
    local t = themes[name]
    local colors = {}
    for i,v in ipairs(t) do colors[i] = Color3.fromRGB(v[1],v[2],v[3]) end
    ACCENT,COLOR_WINDOW,COLOR_TOPBAR,COLOR_GROUP,COLOR_CONTROL,COLOR_BORDER,COLOR_TEXT,COLOR_TEXT_DIM,COLOR_ON_ACCENT = unpack(colors)
    NexusUI.Palette = colors
    table.clear(colorRoles)
    for i,v in ipairs(colors) do if not colorRoles[v] then colorRoles[v] = i end end
end
setPalette("Noir")
function NexusUI:ResolveColor(v)
    return self.Palette[colorRoles[v]] or v
end
function NexusUI:BindColor(o,k,f)
    local b = bindings[o]
    if not b then
        b = {}
        bindings[o] = b
        TrackGuiConnection(o.Destroying:Connect(function() bindings[o] = nil end))
    end
    b[k] = f
    o[k] = f()
end
function NexusUI:SetTheme(name)
    self.ThemeName = "Noir"
    setPalette("Noir")
    for o,b in pairs(bindings) do
        for k,f in pairs(b) do o[k] = f() end
    end
    for _,f in ipairs(self.ThemeRefresh) do f() end
    return true
end

local function makeLogo(parent, size)
    local function New(class, props)
        local object = Instance.new(class)
        for key, value in pairs(props) do object[key] = value end
        return object
    end
    local PrimeLabel = New("Frame", {
        Name = "PrimeLogo",
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = parent,
    })
		local function Polygon(points, top, bottom, layer)
			for row = 0, 95 do
				local y = (row + 0.5) / 96
				local hits = {}
				for i, point in ipairs(points) do
					local nextPoint = points[i % #points + 1]
					if (point[2] <= y and nextPoint[2] > y) or (nextPoint[2] <= y and point[2] > y) then
						hits[#hits + 1] = point[1] + (y - point[2]) * (nextPoint[1] - point[1]) / (nextPoint[2] - point[2])
					end
				end
				table.sort(hits)
				for i = 1, #hits - 1, 2 do
					New("Frame", {
						Name = "Facet",
						Position = UDim2.fromScale(hits[i], row / 96),
						Size = UDim2.fromScale(hits[i + 1] - hits[i], 1 / 96),
						BorderSizePixel = 0,
						BackgroundColor3 = top:Lerp(bottom, y),
						Parent = PrimeLabel,
						ZIndex = layer,
					})
				end
			end
		end
		local white = Color3.fromRGB(255, 255, 255)
		local silver = Color3.fromRGB(180, 180, 180)
		local dark = Color3.fromRGB(70, 70, 70)
		for i = 0, 79 do
			local angle = math.rad(i * 4.5 - 90)
			local nextAngle = angle + math.rad(4.8)
			local x, y = 0.5 + math.cos(angle) * 0.455, 0.5 + math.sin(angle) * 0.455
			local nx, ny = 0.5 + math.cos(nextAngle) * 0.455, 0.5 + math.sin(nextAngle) * 0.455
			New("Frame", {
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((x + nx) / 2, (y + ny) / 2),
				Size = UDim2.fromScale(math.sqrt((nx - x)^2 + (ny - y)^2) + 0.006, 0.025),
				Rotation = math.deg(angle) + 92.4,
				BackgroundColor3 = white:Lerp(silver, (y + 1) / 2),
				BorderSizePixel = 0,
				Parent = PrimeLabel,
			})
		end
		Polygon({{0.21,0.25},{0.34,0.23},{0.44,0.18},{0.51,0.12},{0.46,0.23},{0.445,0.34},{0.445,0.56},{0.36,0.66},{0.36,0.34},{0.34,0.29}}, white, silver, 2)
		Polygon({{0.21,0.25},{0.31,0.29},{0.34,0.34},{0.34,0.65},{0.30,0.73},{0.24,0.80},{0.29,0.68},{0.29,0.35},{0.27,0.29}}, silver, white, 3)
		Polygon({{0.36,0.28},{0.46,0.23},{0.445,0.34},{0.445,0.56},{0.38,0.63},{0.38,0.31}}, dark, white, 4)
		Polygon({{0.24,0.80},{0.45,0.59},{0.68,0.46},{0.54,0.63},{0.40,0.69}}, white, silver, 3)
		Polygon({{0.24,0.80},{0.40,0.71},{0.52,0.69},{0.70,0.69},{0.84,0.60},{0.72,0.78},{0.69,0.88},{0.64,0.81},{0.47,0.77},{0.35,0.77}}, white, silver, 4)
		Polygon({{0.24,0.80},{0.35,0.77},{0.47,0.77},{0.64,0.81},{0.69,0.88},{0.67,0.77},{0.51,0.73},{0.38,0.74}}, dark, white, 5)

    return PrimeLabel
end
RegisterUnloadCallback(function()
    table.clear(bindings)
    table.clear(NexusUI.ThemeRefresh)
end)

function ApplyButtonStyle(button)
    if not button then return end
    if button:IsA("TextButton") then
        button.AutoButtonColor = false
        button.SelectionImageObject = nil
    end
    if button:IsA("GuiObject") then
        button.Active = true
    end
end


function CreateClickButton(parent, text, size, position, bgColor, textColor, font, textSize, disableHover)
    local bgRole = colorRoles[bgColor] or 5
    local textRole = colorRoles[textColor] or 7
    local button = Instance.new("Frame")
    button.Size = size
    button.Position = position
    NexusUI:BindColor(button, "BackgroundColor3", function() return NexusUI.Palette[bgRole] end)
    button.BackgroundTransparency = GUI_BUTTON_TRANSPARENCY
    button.BorderSizePixel = 0
    button.Active = true
    button.ClipsDescendants = true
    button.ZIndex = 10
    button.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text or ""
    NexusUI:BindColor(label, "TextColor3", function() return NexusUI.Palette[textRole] end)
    label.FontFace = Font.new(FONT_BODY, font == Enum.Font.GothamBold and Enum.FontWeight.Bold or Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
    label.TextSize = (textSize or 14) + 1
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 11
    label.Parent = button

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button

    local defaultBackground = button.BackgroundColor3
    local hoverBackground = defaultBackground:Lerp(ACCENT, 0.12)
    local pressedBackground = defaultBackground:Lerp(ACCENT, 0.22)
    table.insert(NexusUI.ThemeRefresh, function()
        if not button.Parent then return end
        defaultBackground = NexusUI.Palette[bgRole]
        hoverBackground = defaultBackground:Lerp(ACCENT, 0.12)
        pressedBackground = defaultBackground:Lerp(ACCENT, 0.22)
    end)
    local hovered = false
    local pressed = false

    local function tweenBackground(color)
        if button and button.Parent then
            TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = color}):Play()
        end
    end

    if not disableHover then
        TrackGuiConnection(button.MouseEnter:Connect(function()
            hovered = true
            if not pressed then
                tweenBackground(hoverBackground)
            end
        end))

        TrackGuiConnection(button.MouseLeave:Connect(function()
            hovered = false
            if not pressed then
                tweenBackground(defaultBackground)
            end
        end))

        TrackGuiConnection(button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                pressed = true
                tweenBackground(pressedBackground)
            end
        end))

        TrackGuiConnection(button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                pressed = false
                tweenBackground(hovered and hoverBackground or defaultBackground)
            end
        end))
    end

    return button, label
end

function ConnectClick(button, callback)
    if not button then return end
    local pressed = false

    local function isClickInput(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
    end

    local beganConn = button.InputBegan:Connect(function(input)
        if isClickInput(input) then
            pressed = true
        end
    end)

    local endedConn = button.InputEnded:Connect(function(input)
        if isClickInput(input) and pressed then
            pressed = false
            if callback then
                pcall(callback)
            end
        end
    end)

    if beganConn then
        table.insert(GuiConnections, beganConn)
    end
    if endedConn then
        table.insert(GuiConnections, endedConn)
    end
end

function NexusUI:CreateWindow(options)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NexusBasketballZeroUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = GuiParent
    attachTextStyler(screenGui)

    local isVisibleByDefault = options == nil or options.visible ~= false
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    local requestedSize = options and options.Size or UDim2.fromOffset(620, 370)
    local preferredSize = Vector2.new(requestedSize.X.Offset, requestedSize.Y.Offset)
    local userResized = false
    mainFrame.Size = requestedSize
    mainFrame.Position = options and options.Position or UDim2.fromOffset(40, 40)
    mainFrame.Visible = isVisibleByDefault
    mainFrame.BackgroundColor3 = Color3.new(1, 1, 1)
    windowGradient().Parent = mainFrame
    mainFrame.BackgroundTransparency = MAIN_WINDOW_TRANSPARENCY
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = false
    mainFrame.Parent = screenGui
    local fit = Instance.new("UIScale")
    fit.Name = "NexusWindowScale"
    local targetScale = 1
    fit.Parent = mainFrame
    local cameraConnection
    local function fitWindow()
        local c = Workspace.CurrentCamera
        if not c then return end
        local v = c.ViewportSize
        if v.X < 600 and not userResized then
            mainFrame.Size = UDim2.fromOffset(math.min(410, v.X - 24), math.min(540, v.Y - 64))
        else
            mainFrame.Size = UDim2.fromOffset(preferredSize.X, preferredSize.Y)
        end
        targetScale = math.min(1, math.max(0.1, (v.X - 24) / mainFrame.Size.X.Offset), math.max(0.1, (v.Y - 64) / mainFrame.Size.Y.Offset))
        fit.Scale = targetScale
        local pos = mainFrame.Position
        mainFrame.Position = UDim2.fromOffset(math.clamp(pos.X.Offset, 8, math.max(8, v.X - mainFrame.Size.X.Offset * fit.Scale - 8)), math.clamp(pos.Y.Offset, 8, math.max(8, v.Y - mainFrame.Size.Y.Offset * fit.Scale - 48)))
    end
    local function bindCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        if Workspace.CurrentCamera then cameraConnection = TrackGuiConnection(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitWindow)) end
        fitWindow()
    end
    TrackGuiConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
    bindCamera()


    local mainCorner = Instance.new("UICorner")
    mainCorner.Name = "NexusMainCorner"
    mainCorner.CornerRadius = UDim.new(0, 18)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Name = "NexusMainStroke"
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Color = Color3.new(1, 1, 1)
    mainStroke.Transparency = 0.1
    mainStroke.Thickness = 1.2
    mainStroke.LineJoinMode = Enum.LineJoinMode.Round
    mainStroke.Parent = mainFrame
    borderGradient().Parent = mainStroke

    local innerClip = Instance.new("Frame")
    innerClip.Name = "InnerClip"
    innerClip.Size = UDim2.new(1, 0, 1, 0)
    innerClip.BackgroundTransparency = 1
    innerClip.BorderSizePixel = 0
    innerClip.ClipsDescendants = true
    innerClip.Parent = mainFrame

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(0, 18)
    innerCorner.Parent = innerClip

    -- Soft light sheen across the top-left, like a glass panel.
    local sheen = Instance.new("Frame")
    sheen.Name = "Sheen"
    sheen.Size = UDim2.fromScale(1, 1)
    sheen.BackgroundColor3 = Color3.new(1, 1, 1)
    sheen.BorderSizePixel = 0
    sheen.ZIndex = 0
    sheen.Parent = innerClip
    local sheenGradient = Instance.new("UIGradient")
    sheenGradient.Rotation = 35
    sheenGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.93),
        NumberSequenceKeypoint.new(0.3, 0.985),
        NumberSequenceKeypoint.new(0.85, 1),
        NumberSequenceKeypoint.new(1, 0.97),
    })
    sheenGradient.Parent = sheen

    local animationDuration = 0.18
    local function animateWindowIn()
        if not mainFrame or not mainFrame.Parent then return end
        if not mainFrame:FindFirstChild("NexusWindowScale") then
            local windowScale = Instance.new("UIScale")
            windowScale.Name = "NexusWindowScale"
            windowScale.Scale = 0.96 * targetScale
            windowScale.Parent = mainFrame
        end

        local windowScale = mainFrame:FindFirstChild("NexusWindowScale")
        if windowScale then
            windowScale.Scale = 0.96 * targetScale
            TweenService:Create(windowScale, TweenInfo.new(animationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
        end
        TweenService:Create(mainFrame, TweenInfo.new(animationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = MAIN_WINDOW_TRANSPARENCY}):Play()
    end

    local function animateWindowOut(callback)
        if not mainFrame or not mainFrame.Parent then
            if callback then callback() end
            return
        end
        if not mainFrame:FindFirstChild("NexusWindowScale") then
            local windowScale = Instance.new("UIScale")
            windowScale.Name = "NexusWindowScale"
            windowScale.Scale = targetScale
            windowScale.Parent = mainFrame
        end

        local windowScale = mainFrame:FindFirstChild("NexusWindowScale")
        if windowScale then
            TweenService:Create(windowScale, TweenInfo.new(animationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.96 * targetScale}):Play()
        end
        TweenService:Create(mainFrame, TweenInfo.new(animationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = MAIN_WINDOW_TRANSPARENCY}):Play()
        task.delay(animationDuration, function()
            if callback then callback() end
        end)
    end

    local topBarHeight = 46
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, topBarHeight)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BackgroundTransparency = 1
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 2
    topBar.Active = true
    topBar.Parent = innerClip

    local topBarCorner = Instance.new("UICorner")
    topBarCorner.CornerRadius = UDim.new(0, 14)
    topBarCorner.Parent = topBar

    -- Hairline divider that fades out toward both edges.
    local topBarDivider = Instance.new("Frame")
    topBarDivider.Size = UDim2.new(1, -28, 0, 1)
    topBarDivider.Position = UDim2.new(0, 14, 1, -1)
    topBarDivider.BackgroundColor3 = Color3.fromRGB(120, 120, 126)
    topBarDivider.BorderSizePixel = 0
    topBarDivider.ZIndex = 3
    topBarDivider.Parent = topBar
    local dividerGradient = Instance.new("UIGradient")
    dividerGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0.55),
        NumberSequenceKeypoint.new(0.8, 0.55),
        NumberSequenceKeypoint.new(1, 1),
    })
    dividerGradient.Parent = topBarDivider

    local logoContainer = Instance.new("Frame")
    logoContainer.Name = "LogoContainer"
    logoContainer.Size = UDim2.new(0, 0, 1, 0)
    logoContainer.AutomaticSize = Enum.AutomaticSize.X
    logoContainer.Position = UDim2.new(0, 14, 0, 0)
    logoContainer.BackgroundTransparency = 1
    logoContainer.ZIndex = 3
    logoContainer.Parent = topBar

    local logoLayout = Instance.new("UIListLayout")
    logoLayout.FillDirection = Enum.FillDirection.Horizontal
    logoLayout.Padding = UDim.new(0, 8)
    logoLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    logoLayout.Parent = logoContainer

    local cr = makeLogo(logoContainer,26)
    cr.Name = "PrimeLogo"
    cr.LayoutOrder = 1
    cr.ZIndex = 3

    local logoSubtitle = Instance.new("TextLabel")
    logoSubtitle.Name = "PrimeSubtitle"
    logoSubtitle.Size = UDim2.new(0, 0, 0, 18)
    logoSubtitle.AutomaticSize = Enum.AutomaticSize.X
    logoSubtitle.LayoutOrder = 2
    logoSubtitle.BackgroundTransparency = 1

    local isPremiumUser = IS_PREMIUM_USER

    logoSubtitle.Text = isPremiumUser and "PREMIUM" or "FREEMIUM"
    NexusUI:BindColor(logoSubtitle, "TextColor3", function() return COLOR_TEXT end)
    logoSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    logoSubtitle.TextYAlignment = Enum.TextYAlignment.Center

    logoSubtitle.FontFace = Font.new(FONT_TITLE, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    logoSubtitle.TextSize = 11
    logoSubtitle.ZIndex = 3
    logoSubtitle.Parent = logoContainer
    local sh = Instance.new("UIGradient")
    sh.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(142,142,150)),
        ColorSequenceKeypoint.new(0.35,Color3.fromRGB(210,210,218)),
        ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),
        ColorSequenceKeypoint.new(0.65,Color3.fromRGB(210,210,218)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(142,142,150))
    })
    sh.Offset = Vector2.new(-1,0)
    sh.Parent = logoSubtitle
    TweenService:Create(sh,TweenInfo.new(2.6,Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,-1),{Offset=Vector2.new(1,0)}):Play()

    local tabStrip = Instance.new("ScrollingFrame")
    tabStrip.Name = "TabStrip"
    tabStrip.Size = UDim2.new(1, -100, 1, 0)
    tabStrip.Position = UDim2.new(0, 90, 0, 0)
    tabStrip.BackgroundTransparency = 1
    tabStrip.ClipsDescendants = true
    tabStrip.ZIndex = 3
    tabStrip.Active = true
    tabStrip.Parent = topBar

    do
        tabStrip.BorderSizePixel = 0
        tabStrip.CanvasSize = UDim2.new(0, 0, 0, 0)
        tabStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
        tabStrip.ScrollingDirection = Enum.ScrollingDirection.X
        tabStrip.ScrollingEnabled = true
        tabStrip.ScrollBarThickness = 2
        NexusUI:BindColor(tabStrip, "ScrollBarImageColor3", function() return COLOR_BORDER end)
        tabStrip.ScrollBarImageTransparency = 0.2
        tabStrip.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable

        local function updateMobileTabStripBounds()
            if not tabStrip or not tabStrip.Parent then return end
            local measuredLogoWidth = math.floor(logoContainer.AbsoluteSize.X / math.max(fit.Scale, 0.1) + 0.5)
            local leftInset = math.max(138, measuredLogoWidth + 26)
            local rightInset = 8
            tabStrip.Position = UDim2.new(0, leftInset, 0, 0)
            tabStrip.Size = UDim2.new(1, -(leftInset + rightInset), 1, 0)
        end

        TrackGuiConnection(logoContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateMobileTabStripBounds))
        task.defer(updateMobileTabStripBounds)
    end

    local tabStripLayout = Instance.new("UIListLayout")
    tabStripLayout.FillDirection = Enum.FillDirection.Horizontal
    tabStripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    tabStripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabStripLayout.Padding = UDim.new(0, 2)
    tabStripLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabStripLayout.Parent = tabStrip

    local mobileTabHintHeight = IS_MOBILE and 14 or 0
    if IS_MOBILE then
        local tabSwipeHint = Instance.new("TextLabel")
        tabSwipeHint.Name = "TabSwipeHint"
        tabSwipeHint.Size = UDim2.new(1, -16, 0, mobileTabHintHeight)
        tabSwipeHint.Position = UDim2.new(0, 8, 0, topBarHeight)
        tabSwipeHint.BackgroundTransparency = 1
        tabSwipeHint.Text = "Swipe tabs left / right  ↔"
        NexusUI:BindColor(tabSwipeHint, "TextColor3", function() return COLOR_TEXT_DIM end)
        tabSwipeHint.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
        tabSwipeHint.TextSize = 9
        tabSwipeHint.TextXAlignment = Enum.TextXAlignment.Right
        tabSwipeHint.TextYAlignment = Enum.TextYAlignment.Center
        tabSwipeHint.ZIndex = 4
        tabSwipeHint.Parent = innerClip
    end

    local window = {}
    local restoreGui
    local connections = {}
    local function track(conn)
        if conn then
            table.insert(connections, conn)
        end
        return conn
    end

    local function createRestoreGui()
        if not SHOW_RESTORE_BUTTON then
            return nil
        end

        if restoreGui then
            return restoreGui
        end

        restoreGui = Instance.new("ScreenGui")
        restoreGui.Name = "NexusBasketballZeroUI_Restore"
        restoreGui.ResetOnSpawn = false
        restoreGui.IgnoreGuiInset = true
        restoreGui.Enabled = false
        restoreGui.Parent = GuiParent

        local restoreFrame = Instance.new("Frame")
        restoreFrame.Size = UDim2.fromOffset(48, 48)
        restoreFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        restoreFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        restoreFrame.BorderSizePixel = 0
        restoreFrame.BackgroundTransparency = 1
        restoreFrame.Parent = restoreGui
        restoreFrame.Active = true

        local restoreButton = makeLogo(restoreFrame,48)
        restoreButton.Name = "RestoreLogo"
        restoreButton.Active = true
        local restoreDragging = false
        local restoreDragMoved = false
        local restoreStartPos = nil
        local restoreStartInputPos = nil
        local restoreInputType = nil
        local restoreDragThreshold = 8

        local function beginRestoreInteraction(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                restoreDragging = true
                restoreDragMoved = false
                restoreStartPos = restoreFrame.Position
                restoreStartInputPos = input.Position
                restoreInputType = input.UserInputType
            end
        end

        local function updateRestoreInteraction(input)
            if not restoreDragging or not restoreStartPos or not restoreStartInputPos then
                return
            end

            local isMouseDrag = restoreInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
            local isTouchDrag = restoreInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch
            if not isMouseDrag and not isTouchDrag then
                return
            end

            local delta = input.Position - restoreStartInputPos
            if math.abs(delta.X) > restoreDragThreshold or math.abs(delta.Y) > restoreDragThreshold then
                restoreDragMoved = true
            end

            restoreFrame.Position = UDim2.new(
                restoreStartPos.X.Scale,
                restoreStartPos.X.Offset + delta.X,
                restoreStartPos.Y.Scale,
                restoreStartPos.Y.Offset + delta.Y
            )
        end

        local function endRestoreInteraction(input)
            if not restoreDragging then
                return
            end
            if input.UserInputType ~= restoreInputType then
                return
            end

            local shouldOpen = not restoreDragMoved
            restoreDragging = false
            restoreDragMoved = false
            restoreStartPos = nil
            restoreStartInputPos = nil
            restoreInputType = nil

            if shouldOpen then
                window:SetVisible(true)
            end
        end

        track(restoreFrame.InputBegan:Connect(beginRestoreInteraction))
        track(restoreButton.InputBegan:Connect(beginRestoreInteraction))
        track(userInputService.InputChanged:Connect(updateRestoreInteraction))
        track(userInputService.InputEnded:Connect(endRestoreInteraction))

        return restoreGui
    end

    local closeConfirmGui
    local setVisible
    local destroyWindow

    local function destroyCloseConfirm()
        if closeConfirmGui then
            closeConfirmGui:Destroy()
            closeConfirmGui = nil
        end
    end

    local function createCloseConfirm()
        if closeConfirmGui then
            return closeConfirmGui
        end

        destroyCloseConfirm()

        closeConfirmGui = Instance.new("Frame")
        closeConfirmGui.Name = "NexusBasketballZeroUI_CloseConfirm"
        closeConfirmGui.Size = UDim2.new(0, 360, 0, 190)
        closeConfirmGui.AnchorPoint = Vector2.new(0.5, 0.5)
        closeConfirmGui.Position = UDim2.new(0.5, 0, 0.5, 0)
        closeConfirmGui.BackgroundTransparency = 1
        closeConfirmGui.BorderSizePixel = 0
        closeConfirmGui.ZIndex = 50
        closeConfirmGui.Parent = mainFrame

        local dialog = Instance.new("Frame")
        dialog.Size = UDim2.new(1, 0, 1, 0)
        dialog.Position = UDim2.new(0, 0, 0, 0)
        dialog.BackgroundColor3 = Color3.new(1, 1, 1)
        windowGradient().Parent = dialog
        dialog.BorderSizePixel = 0
        dialog.BackgroundTransparency = 0
        dialog.ClipsDescendants = true
        dialog.ZIndex = 51
        dialog.Parent = closeConfirmGui

        local dialogCorner = Instance.new("UICorner")
        dialogCorner.CornerRadius = UDim.new(0, 16)
        dialogCorner.Parent = dialog

        local dialogStroke = Instance.new("UIStroke")
        dialogStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        dialogStroke.Color = Color3.new(1, 1, 1)
        dialogStroke.Transparency = 0.1
        dialogStroke.Thickness = 1.2
        dialogStroke.Parent = dialog
        borderGradient().Parent = dialogStroke

        local dialogTop = Instance.new("Frame")
        dialogTop.Size = UDim2.new(1, 0, 0, 40)
        dialogTop.Position = UDim2.new(0, 0, 0, 0)
        dialogTop.BorderSizePixel = 0
        dialogTop.BackgroundTransparency = 1
        dialogTop.ZIndex = 52
        dialogTop.Parent = dialog

        local dialogTitle = Instance.new("TextLabel")
        dialogTitle.Size = UDim2.new(1, -24, 0, 26)
        dialogTitle.Position = UDim2.new(0, 16, 0, 10)
        dialogTitle.BackgroundTransparency = 1
        dialogTitle.FontFace = Font.new(FONT_TITLE, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
        dialogTitle.TextSize = 14
        dialogTitle.Text = "CONFIRM CLOSE"
        NexusUI:BindColor(dialogTitle, "TextColor3", function() return COLOR_TEXT end)
        dialogTitle.TextXAlignment = Enum.TextXAlignment.Left
        dialogTitle.TextYAlignment = Enum.TextYAlignment.Center
        dialogTitle.ZIndex = 53
        dialogTitle.Parent = dialogTop

        local dialogText = Instance.new("TextLabel")
        dialogText.Size = UDim2.new(1, -24, 0, 48)
        dialogText.Position = UDim2.new(0, 16, 0, 52)
        dialogText.BackgroundTransparency = 1
        dialogText.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
        dialogText.TextSize = 14
        dialogText.Text = "Press 'Hide' to minimize the UI, or 'Close' to remove it completely."
        NexusUI:BindColor(dialogText, "TextColor3", function() return COLOR_TEXT end)
        dialogText.TextWrapped = true
        dialogText.TextXAlignment = Enum.TextXAlignment.Left
        dialogText.TextYAlignment = Enum.TextYAlignment.Top
        dialogText.ZIndex = 53
        dialogText.Parent = dialog

        local buttonContainer = Instance.new("Frame")
        buttonContainer.Size = UDim2.new(1, -24, 0, 36)
        buttonContainer.Position = UDim2.new(0, 12, 1, -48)
        buttonContainer.BackgroundTransparency = 1
        buttonContainer.ZIndex = 53
        buttonContainer.Parent = dialog

        local buttonLayout = Instance.new("UIListLayout")
        buttonLayout.FillDirection = Enum.FillDirection.Horizontal
        buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        buttonLayout.Padding = UDim.new(0, 10)
        buttonLayout.Parent = buttonContainer

        local hideButton, hideLabel = CreateClickButton(
            buttonContainer,
            "Hide",
            UDim2.new(0, 150, 1, 0),
            UDim2.new(0, 0, 0, 0),
            COLOR_CONTROL,
            COLOR_TEXT,
            Enum.Font.GothamSemibold,
            15,
            true
        )
        hideButton.BackgroundTransparency = 0.2
        local hideStroke = Instance.new("UIStroke")
        hideStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        hideStroke.Color = Color3.fromRGB(70, 70, 76)
        hideStroke.Transparency = 0.2
        hideStroke.Parent = hideButton
        if hideLabel then
            hideLabel.Text = "Hide"
            hideLabel.TextTransparency = 0
            hideLabel.ZIndex = 55
        end
        ApplyButtonStyle(hideButton)
        hideButton.ZIndex = 54

        local closeConfirmButton, closeConfirmLabel = CreateClickButton(
            buttonContainer,
            "Close",
            UDim2.new(0, 150, 1, 0),
            UDim2.new(0, 0, 0, 0),
            ACCENT,
            COLOR_WINDOW,
            Enum.Font.GothamSemibold,
            15,
            true
        )
        closeConfirmButton.BackgroundTransparency = 0
        local closeGradient = Instance.new("UIGradient")
        closeGradient.Rotation = 90
        closeGradient.Color = ColorSequence.new(Color3.fromRGB(250, 250, 252), Color3.fromRGB(190, 190, 196))
        closeGradient.Parent = closeConfirmButton
        if closeConfirmLabel then
            closeConfirmLabel.Text = "Close"
            NexusUI:BindColor(closeConfirmLabel, "TextColor3", function() return COLOR_ON_ACCENT end)
            closeConfirmLabel.TextTransparency = 0
            closeConfirmLabel.ZIndex = 55
        end
        ApplyButtonStyle(closeConfirmButton)
        closeConfirmButton.ZIndex = 54

        ConnectClick(hideButton, function()
            destroyCloseConfirm()
            setVisible(false)
        end)

        ConnectClick(closeConfirmButton, function()
            if destroyWindow then
                destroyWindow()
            end
        end)

        return closeConfirmGui
    end

    setVisible = function(visible)
        if visible then
            mainFrame.Visible = true
            animateWindowIn()
            if restoreGui then
                restoreGui.Enabled = false
            end
        else
            animateWindowOut(function()
                if mainFrame then
                    mainFrame.Visible = false
                end
            end)
            local mobileButtonGui = createRestoreGui()
            if mobileButtonGui then
                mobileButtonGui.Enabled = true
            end
        end
    end

    local isCollapsed = false

    local function setCollapsed(value)
        isCollapsed = value
        mainFrame.Visible = not value
    end

    local dragHandle = topBar


    local dragging = false
    local dragStartPos = nil
    local dragStartMousePos = nil

    local function isInputInside(guiObject, inputPosition)
        if not guiObject or not guiObject.Parent then return false end
        local pos = guiObject.AbsolutePosition
        local size = guiObject.AbsoluteSize
        local x = inputPosition.X
        local y = inputPosition.Y
        return x >= pos.X and x <= (pos.X + size.X) and y >= pos.Y and y <= (pos.Y + size.Y)
    end

    track(dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            -- On phones the top tabs must keep the touch gesture for horizontal scrolling.
            if IS_MOBILE and isInputInside(tabStrip, input.Position) then
                return
            end
            dragging = true
            dragStartPos = mainFrame.Position
            dragStartMousePos = input.Position
        end
    end))

    track(dragHandle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            if dragStartPos and dragStartMousePos then
                local delta = input.Position - dragStartMousePos
                mainFrame.Position = UDim2.new(
                    dragStartPos.X.Scale,
                    dragStartPos.X.Offset + delta.X,
                    dragStartPos.Y.Scale,
                    dragStartPos.Y.Offset + delta.Y
                )
            end
        end
    end))

    track(userInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -16, 1, -(topBarHeight + 42 + mobileTabHintHeight))
    content.Position = UDim2.new(0, 8, 0, topBarHeight + 6 + mobileTabHintHeight)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent = innerClip

    local cornerButtons = Instance.new("Frame")
    cornerButtons.Name = "CornerButtons"
    cornerButtons.Size = UDim2.new(0, 92, 0, 28)
    cornerButtons.Position = UDim2.new(1, -104, 1, -36)
    cornerButtons.BackgroundTransparency = 1
    cornerButtons.ZIndex = 5
    cornerButtons.Parent = innerClip

    local cornerButtonsLayout = Instance.new("UIListLayout")
    cornerButtonsLayout.FillDirection = Enum.FillDirection.Horizontal
    cornerButtonsLayout.Padding = UDim.new(0, 8)
    cornerButtonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cornerButtonsLayout.Parent = cornerButtons

    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "PerformanceStats"
    statsFrame.Size = UDim2.fromOffset(170, 26)
    statsFrame.Position = UDim2.new(0, 10, 1, -36)
    statsFrame.BackgroundTransparency = 1
    statsFrame.BorderSizePixel = 0
    statsFrame.ZIndex = 6
    statsFrame.Parent = innerClip

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, -12, 1, 0)
    statsLabel.Position = UDim2.fromOffset(6, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "FPS  --    PING  -- ms"
    NexusUI:BindColor(statsLabel, "TextColor3", function() return COLOR_TEXT_DIM end)
    statsLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
    statsLabel.TextSize = 12
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.ZIndex = 7
    statsLabel.Parent = statsFrame

    local frames, sampleTime = 0, 0
    track(RunService.RenderStepped:Connect(function(dt)
        frames += 1
        sampleTime += dt
        if sampleTime < 0.5 then return end
        local fps = math.floor(frames / sampleTime + 0.5)
        local ping = 0
        pcall(function()
            ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
        end)
        statsLabel.Text = string.format("FPS  %d    PING  %d ms", fps, ping)
        frames, sampleTime = 0, 0
    end))

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Name = "ResizeHandle"
    resizeHandle.Size = UDim2.fromOffset(24, 24)
    resizeHandle.Position = UDim2.new(1, -24, 1, -24)
    resizeHandle.BackgroundTransparency = 1
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Text = "◢"
    NexusUI:BindColor(resizeHandle, "TextColor3", function() return ACCENT end)
    resizeHandle.Font = Enum.Font.GothamBold
    resizeHandle.TextSize = 15
    resizeHandle.AutoButtonColor = false
    resizeHandle.ZIndex = 20
    resizeHandle.Parent = innerClip

    local resizing, resizeStart, resizeSize = false, nil, nil
    track(resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        resizing = true
        resizeStart = input.Position
        resizeSize = mainFrame.AbsoluteSize / math.max(fit.Scale, 0.1)
    end))
    track(userInputService.InputChanged:Connect(function(input)
        if not resizing or not resizeStart or not resizeSize then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local camera = Workspace.CurrentCamera
        if not camera then return end
        local delta = (input.Position - resizeStart) / math.max(fit.Scale, 0.1)
        local minWidth = IS_MOBILE and 320 or 430
        local minHeight = 320
        local maxWidth = math.max(minWidth, (camera.ViewportSize.X - mainFrame.AbsolutePosition.X - 8) / math.max(fit.Scale, 0.1))
        local maxHeight = math.max(minHeight, (camera.ViewportSize.Y - mainFrame.AbsolutePosition.Y - 48) / math.max(fit.Scale, 0.1))
        preferredSize = Vector2.new(
            math.clamp(math.floor(resizeSize.X + delta.X + 0.5), minWidth, maxWidth),
            math.clamp(math.floor(resizeSize.Y + delta.Y + 0.5), minHeight, maxHeight)
        )
        userResized = true
        mainFrame.Size = UDim2.fromOffset(preferredSize.X, preferredSize.Y)
    end))
    track(userInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if resizing then
            resizing = false
            fitWindow()
        end
    end))

    local function createCornerButton(text, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 42, 0, 28)
        NexusUI:BindColor(btn, "BackgroundColor3", function() return COLOR_CONTROL end)
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel = 0
        btn.Text = text
        NexusUI:BindColor(btn, "TextColor3", function() return COLOR_TEXT end)
        btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
        btn.TextSize = 16
        btn.AutoButtonColor = false
        btn.LayoutOrder = order
        btn.ZIndex = 5
        btn:SetAttribute("KeepFont", true)
        btn.Parent = cornerButtons

        TrackGuiConnection(btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {TextColor3 = COLOR_TEXT}):Play()
        end))
        TrackGuiConnection(btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {TextColor3 = COLOR_TEXT}):Play()
        end))
        return btn
    end

    local HIDE_GUI_SYMBOL = "―"
    local CLOSE_GUI_SYMBOL = "X"

    local hideCornerButton = createCornerButton(HIDE_GUI_SYMBOL, 1)
    ConnectClick(hideCornerButton, function()
        setVisible(false)
    end)

    local closeCornerButton = createCornerButton(CLOSE_GUI_SYMBOL, 2)
    ConnectClick(closeCornerButton, function()
        createCloseConfirm()
    end)

    local tabs = {}
    local currentTab = nil

    local function selectTab(index)
        local tabEntry = tabs[index]
        if not tabEntry then return end
        if currentTab == tabEntry then return end
        for i, tab in ipairs(tabs) do
            local selected = (i == index)
            if tab.underline then
                tab.underline.Visible = selected
            end
            if tab.label then
                NexusUI:BindColor(tab.label, "TextColor3", function() return selected and ACCENT or COLOR_TEXT_DIM end)
            end
            tab.page.Visible = selected
            tab.page.GroupTransparency = 0
            tab.page.Position = UDim2.fromOffset(0,0)
        end
        currentTab = tabEntry
    end

    local toggleKey = options and options.MinimizeKey or Enum.KeyCode.LeftAlt
    local toggleKeyName = "LeftAlt"

    local function updateToggleKeyDisplay()
        if toggleKey and toggleKey.Name then
            toggleKeyName = toggleKey.Name
        end
    end

    updateToggleKeyDisplay()

    function window:SetToggleKey(key)
        toggleKey = key or Enum.KeyCode.LeftAlt
        updateToggleKeyDisplay()
    end

    function window:GetToggleKey()
        return toggleKey
    end

    function window:AddTab(tabData)
        local tabButton = Instance.new("TextButton")
        tabButton.Size = UDim2.new(0, 0, 1, -8)
        tabButton.AutomaticSize = Enum.AutomaticSize.X
        tabButton.BackgroundTransparency = 1
        tabButton.Text = string.upper(tostring(tabData and tabData.Title or "Tab"))
        NexusUI:BindColor(tabButton, "TextColor3", function() return COLOR_TEXT_DIM end)
        tabButton.FontFace = Font.new(FONT_TITLE, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
        tabButton.TextSize = 11
        tabButton.AutoButtonColor = false
        tabButton.LayoutOrder = #tabs + 1
        tabButton.ZIndex = 4
        tabButton.Parent = tabStrip

        local tabButtonPadding = Instance.new("UIPadding")
        tabButtonPadding.PaddingLeft = UDim.new(0, 7)
        tabButtonPadding.PaddingRight = UDim.new(0, 7)
        tabButtonPadding.Parent = tabButton

        local tabLabel = tabButton

        local tabUnderline = Instance.new("Frame")
        tabUnderline.Size = UDim2.new(1, -8, 0, 2)
        tabUnderline.Position = UDim2.new(0, 4, 1, 3)
        NexusUI:BindColor(tabUnderline, "BackgroundColor3", function() return ACCENT end)
        tabUnderline.BorderSizePixel = 0
        tabUnderline.Visible = false
        tabUnderline.ZIndex = 4
        tabUnderline.Parent = tabButton
        local tabUnderlineCorner = Instance.new("UICorner")
        tabUnderlineCorner.CornerRadius = UDim.new(1, 0)
        tabUnderlineCorner.Parent = tabUnderline

        -- Small green superscript badge, e.g. "NEW" on recently updated tabs.
        if tabData and tabData.Badge then
            tabButtonPadding.PaddingRight = UDim.new(0, 30)
            local badge = Instance.new("TextLabel")
            badge.Name = "TabBadge"
            badge.Size = UDim2.fromOffset(26, 10)
            badge.Position = UDim2.new(1, 2, 0.5, -11)
            badge.BackgroundTransparency = 1
            badge.Text = tostring(tabData.Badge)
            badge.TextColor3 = Color3.fromRGB(70, 220, 120)
            badge.FontFace = TEXT_FONT
            badge.TextSize = 7
            badge.TextXAlignment = Enum.TextXAlignment.Left
            badge.ZIndex = 5
            badge.Parent = tabButton
        end

        TrackGuiConnection(tabButton.MouseEnter:Connect(function()
            if not tabUnderline.Visible then
                NexusUI:BindColor(tabButton, "TextColor3", function() return COLOR_TEXT end)
            end
        end))

        TrackGuiConnection(tabButton.MouseLeave:Connect(function()
            if not tabUnderline.Visible then
                NexusUI:BindColor(tabButton, "TextColor3", function() return COLOR_TEXT_DIM end)
            end
        end))

        local tabPage = Instance.new("CanvasGroup")
        tabPage.Size = UDim2.new(1, 0, 1, 0)
        tabPage.Position = UDim2.new(0, 0, 0, 0)
        tabPage.BackgroundTransparency = 1
        tabPage.GroupTransparency = 1
        tabPage.Visible = false
        tabPage.ClipsDescendants = true
        tabPage.Parent = content

        local function createColumn(position)
            local column = Instance.new("ScrollingFrame")
            column.Size = UDim2.new(0.5, -4, 1, 0)
            column.Position = position
            column.BackgroundTransparency = 1
            column.BorderSizePixel = 0
            column.ScrollBarThickness = 3
            NexusUI:BindColor(column, "ScrollBarImageColor3", function() return COLOR_BORDER end)
            column.AutomaticCanvasSize = Enum.AutomaticSize.Y
            column.CanvasSize = UDim2.new(0, 0, 0, 0)
            column.Parent = tabPage

            local columnLayout = Instance.new("UIListLayout")
            columnLayout.Padding = UDim.new(0, 8)
            columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
            columnLayout.Parent = column

            return column
        end

        local leftColumn = createColumn(UDim2.new(0, 0, 0, 0))
        local rightColumn = createColumn(UDim2.new(0.5, 4, 0, 0))
        local arranging = false
        local function arrangeColumns()
            if arranging then return end
            arranging = true
            local narrow = mainFrame.Size.X.Offset < 540
            leftColumn.Size = UDim2.new(narrow and 1 or 0.5, narrow and 0 or -4, 1, 0)
            rightColumn.Visible = not narrow
            for i,column in ipairs({leftColumn,rightColumn}) do
                for _,o in ipairs(column:GetChildren()) do
                    if o:IsA("GuiObject") then
                        local home = o:GetAttribute("ColumnHome") or i
                        o:SetAttribute("ColumnHome", home)
                        o.Parent = (narrow or home == 1) and leftColumn or rightColumn
                    end
                end
            end
            arranging = false
        end
        TrackGuiConnection(leftColumn.ChildAdded:Connect(arrangeColumns))
        TrackGuiConnection(rightColumn.ChildAdded:Connect(arrangeColumns))
        TrackGuiConnection(mainFrame:GetPropertyChangedSignal("Size"):Connect(arrangeColumns))
        arrangeColumns()


        local tabObject = {}
        local controls = {}
        local sectionCount = 0
        local currentSectionContent = nil
        tabObject.Page = tabPage
        tabObject.Button = tabButton

        function tabObject:AddSection(title, column)
            sectionCount = sectionCount + 1
            local side = column == "Right" and 2 or column == "Left" and 1 or (sectionCount % 2 == 1 and 1 or 2)
            local parentColumn = side == 1 and leftColumn or rightColumn

            local group = Instance.new("Frame")
            group.Size = UDim2.new(1, 0, 0, 0)
            group.AutomaticSize = Enum.AutomaticSize.Y
            group.BackgroundTransparency = 1
            group.BorderSizePixel = 0
            group.LayoutOrder = sectionCount
            group:SetAttribute("ColumnHome", side)
            group.Parent = parentColumn

            local groupLayout = Instance.new("UIListLayout")
            groupLayout.SortOrder = Enum.SortOrder.LayoutOrder
            groupLayout.Parent = group

            -- Plain section title with a fading hairline under it (no panel, not collapsible).
            local header = Instance.new("Frame")
            header.Size = UDim2.new(1, 0, 0, 30)
            header.BackgroundTransparency = 1
            header.LayoutOrder = 0
            header.ZIndex = 2
            header.Parent = group

            local headerLine = Instance.new("Frame")
            headerLine.Size = UDim2.new(1, -4, 0, 1)
            headerLine.Position = UDim2.new(0, 4, 1, -5)
            headerLine.BackgroundColor3 = Color3.fromRGB(120, 120, 126)
            headerLine.BorderSizePixel = 0
            headerLine.ZIndex = 2
            headerLine.Parent = header
            local headerLineGradient = Instance.new("UIGradient")
            headerLineGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.45),
                NumberSequenceKeypoint.new(1, 1),
            })
            headerLineGradient.Parent = headerLine

            local headerTitle = Instance.new("TextLabel")
            headerTitle.Size = UDim2.new(1, -8, 1, -6)
            headerTitle.Position = UDim2.new(0, 4, 0, 0)
            headerTitle.BackgroundTransparency = 1
            headerTitle.Text = string.upper(tostring(title))
            NexusUI:BindColor(headerTitle, "TextColor3", function() return COLOR_TEXT end)
            headerTitle.FontFace = Font.new(FONT_TITLE, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
            headerTitle.TextSize = 11
            headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
            headerTitle.TextXAlignment = Enum.TextXAlignment.Left
            headerTitle.ZIndex = 2
            headerTitle.Parent = header

            local sectionContent = Instance.new("Frame")
            sectionContent.Name = "Content"
            sectionContent.Size = UDim2.new(1, 0, 0, 0)
            sectionContent.AutomaticSize = Enum.AutomaticSize.Y
            sectionContent.BackgroundTransparency = 1
            sectionContent.LayoutOrder = 1
            sectionContent.Parent = group

            local contentLayout = Instance.new("UIListLayout")
            contentLayout.Padding = UDim.new(0, 5)
            contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
            contentLayout.Parent = sectionContent

            local contentPadding = Instance.new("UIPadding")
            contentPadding.PaddingLeft = UDim.new(0, 4)
            contentPadding.PaddingRight = UDim.new(0, 6)
            contentPadding.PaddingTop = UDim.new(0, 4)
            contentPadding.PaddingBottom = UDim.new(0, 10)
            contentPadding.Parent = sectionContent

            currentSectionContent = sectionContent
            local sectionObject = {Frame = group, Content = sectionContent}
            return sectionObject
        end

        function tabObject:SetActiveSection(sectionObject)
            if sectionObject and sectionObject.Content then
                currentSectionContent = sectionObject.Content
                return true
            end
            return false
        end

        local function getControlParent()
            return currentSectionContent or leftColumn
        end

        function tabObject:AddToggle(id, data)
            local rowHeight = IS_MOBILE and 30 or 26
            local showDescription = data and data.ShowDescription == true
            local toggleFrame = Instance.new("Frame")
            toggleFrame.Size = UDim2.new(1, 0, 0, rowHeight)
            if showDescription then toggleFrame.AutomaticSize = Enum.AutomaticSize.Y end
            toggleFrame.BackgroundTransparency = 1
            toggleFrame.Active = true
            toggleFrame.LayoutOrder = #controls + 1
            toggleFrame.BorderSizePixel = 0
            toggleFrame.Parent = getControlParent()

            -- ON / OFF pill switch on the right side of the row.
            local SWITCH_W = IS_MOBILE and 50 or 44
            local SWITCH_H = IS_MOBILE and 22 or 20
            local KNOB = SWITCH_H - 6
            local SWITCH_ON = Color3.fromRGB(34, 150, 64)
            local SWITCH_OFF = Color3.fromRGB(10, 10, 11)
            local SWITCH_LOCKED = Color3.fromRGB(28, 28, 30)

            local switch = Instance.new("Frame")
            switch.Name = "Switch"
            switch.AnchorPoint = Vector2.new(1, 0.5)
            switch.Size = UDim2.fromOffset(SWITCH_W, SWITCH_H)
            switch.Position = showDescription and UDim2.new(1, -2, 0, rowHeight / 2) or UDim2.new(1, -2, 0.5, 0)
            switch.BackgroundColor3 = SWITCH_OFF
            switch.BorderSizePixel = 0
            switch.Parent = toggleFrame

            local switchCorner = Instance.new("UICorner")
            switchCorner.CornerRadius = UDim.new(1, 0)
            switchCorner.Parent = switch

            local switchStroke = Instance.new("UIStroke")
            switchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            switchStroke.Color = Color3.fromRGB(70, 70, 76)
            switchStroke.Transparency = 0.25
            switchStroke.Thickness = 1
            switchStroke.Parent = switch

            local switchText = Instance.new("TextLabel")
            switchText.Name = "State"
            switchText.BackgroundTransparency = 1
            switchText.Size = UDim2.new(1, -(KNOB + 6), 1, 0)
            switchText.Position = UDim2.fromOffset(KNOB + 4, 0)
            switchText.Text = "OFF"
            switchText.TextColor3 = Color3.fromRGB(235, 235, 240)
            switchText.FontFace = TEXT_FONT
            switchText.TextSize = 7
            switchText.TextXAlignment = Enum.TextXAlignment.Center
            switchText.ZIndex = 2
            switchText.Parent = switch

            local knob = Instance.new("Frame")
            knob.Name = "Knob"
            knob.AnchorPoint = Vector2.new(0, 0.5)
            knob.Size = UDim2.fromOffset(KNOB, KNOB)
            knob.Position = UDim2.new(0, 3, 0.5, 0)
            knob.BackgroundColor3 = Color3.new(1, 1, 1)
            knob.BorderSizePixel = 0
            knob.ZIndex = 3
            knob.Parent = switch

            local knobCorner = Instance.new("UICorner")
            knobCorner.CornerRadius = UDim.new(1, 0)
            knobCorner.Parent = knob

            local label = Instance.new("TextLabel")
            label.Size = showDescription and UDim2.new(1, -(SWITCH_W + 10), 0, rowHeight)
                or UDim2.new(1, -(SWITCH_W + 10), 1, 0)
            label.Position = UDim2.new(0, 0, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = data and data.Title or id
            NexusUI:BindColor(label, "TextColor3", function() return COLOR_TEXT end)
            label.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            label.TextSize = 15
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.Parent = toggleFrame

            local descriptionLabel
            if showDescription then
                descriptionLabel = Instance.new("TextLabel")
                descriptionLabel.Name = "Description"
                descriptionLabel.Size = UDim2.new(1, -4, 0, 0)
                descriptionLabel.Position = UDim2.fromOffset(0, rowHeight + 2)
                descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
                descriptionLabel.BackgroundTransparency = 1
                descriptionLabel.Text = tostring(data.Description or "")
                descriptionLabel.TextWrapped = true
                descriptionLabel.TextScaled = false
                descriptionLabel.TextSize = 12
                descriptionLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
                descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
                descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
                NexusUI:BindColor(descriptionLabel, "TextColor3", function() return COLOR_TEXT_DIM end)
                descriptionLabel.Parent = toggleFrame
            end

            local lockedBanner = Instance.new("TextLabel")
            lockedBanner.Name = "LockedBanner"
            lockedBanner.Size = UDim2.new(1, 0, 1, 0)
            lockedBanner.BackgroundTransparency = 1
            lockedBanner.Text = data and data.LockedText or ""
            NexusUI:BindColor(lockedBanner, "TextColor3", function() return COLOR_TEXT_DIM end)
            lockedBanner.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            lockedBanner.TextSize = 12
            lockedBanner.TextXAlignment = Enum.TextXAlignment.Center
            lockedBanner.TextYAlignment = Enum.TextYAlignment.Center
            lockedBanner.TextTruncate = Enum.TextTruncate.AtEnd
            lockedBanner.Visible = false
            lockedBanner.ZIndex = 3
            lockedBanner.Parent = toggleFrame

            local enabled = data and data.Default == true or false
            local locked = false
            local toggleOption = {
                Value = enabled,
                IsToggle = true,
                Locked = false,
                Frame = toggleFrame,
                Label = label,
                Title = data and data.Title or id
            }

            local switchTweens = {}
            local function setSwitch(object, props, animated)
                if switchTweens[object] then switchTweens[object]:Cancel() end
                if animated then
                    switchTweens[object] = TweenService:Create(object, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
                    switchTweens[object]:Play()
                else
                    for key, value in pairs(props) do object[key] = value end
                end
            end

            local function refresh(animated)
                local on = enabled and not locked
                setSwitch(switch, {BackgroundColor3 = locked and SWITCH_LOCKED or (on and SWITCH_ON or SWITCH_OFF)}, animated)
                setSwitch(knob, {
                    Position = on and UDim2.new(1, -(KNOB + 3), 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                    BackgroundTransparency = locked and 0.55 or 0,
                }, animated)
                switchStroke.Transparency = on and 1 or 0.25
                switchText.Text = on and "ON" or "OFF"
                switchText.Position = on and UDim2.fromOffset(2, 0) or UDim2.fromOffset(KNOB + 4, 0)
                switchText.TextTransparency = locked and 0.6 or 0
                NexusUI:BindColor(label, "TextColor3", function() return locked and COLOR_TEXT_DIM or COLOR_TEXT end)

                lockedBanner.Visible = locked and lockedBanner.Text ~= ""
                label.Visible = not lockedBanner.Visible
                switch.Visible = not lockedBanner.Visible
            end
            refresh(false)

            function toggleOption:SetValue(value)
                local newValue = value == true
                if locked and newValue then
                    return false
                end
                if enabled == newValue then
                    return true
                end

                enabled = newValue
                self.Value = enabled
                refresh(true)

                if data and data.Callback then
                    local ok = pcall(data.Callback, enabled)
                    if not ok then
                        enabled = not newValue
                        self.Value = enabled
                        pcall(data.Callback, enabled)
                        refresh(false)
                        return false
                    end
                end
                return true
            end

            function toggleOption:SetTitle(text)
                local newTitle = tostring(text or "")
                -- Drop any bracketed suffix such as a "[LOCK 03:59:59]" countdown.
                newTitle = newTitle:gsub("%s*%[.-%]%s*$", "")
                if newTitle == "" then
                    newTitle = tostring(id)
                end
                self.Title = newTitle
                label.Text = newTitle
            end

            function toggleOption:SetDescription(text)
                local description = tostring(text or "")
                if descriptionLabel then descriptionLabel.Text = description end
                if description ~= "" then
                    label.Text = self.Title or (data and data.Title or id)
                end
            end

            -- Locking is disabled: toggles always stay usable. Kept as no-ops so
            -- external callers (e.g. the loader) do not error.
            function toggleOption:SetLocked(value) end

            function toggleOption:SetLockedText(text) end

            function toggleOption:IsLocked()
                return locked
            end

            NexusUI.Options[id] = toggleOption
            NexusUI.Toggles[id] = toggleOption

            -- A full-row TextButton is a native click/touch target: works with mouse on PC
            -- and tap on phones (Activated fires for both).
            local rowHitbox = Instance.new("TextButton")
            rowHitbox.Name = "TouchHitbox"
            rowHitbox.Size = UDim2.fromScale(1, 1)
            rowHitbox.Position = UDim2.fromScale(0, 0)
            rowHitbox.BackgroundTransparency = 1
            rowHitbox.BorderSizePixel = 0
            rowHitbox.Text = ""
            rowHitbox.AutoButtonColor = false
            rowHitbox.Active = true
            rowHitbox.Selectable = IS_MOBILE
            rowHitbox.ZIndex = 5
            rowHitbox.Parent = toggleFrame
            TrackGuiConnection(rowHitbox.Activated:Connect(function()
                toggleOption:SetValue(not enabled)
            end))

            table.insert(controls, toggleFrame)
            return toggleFrame
        end

        function tabObject:AddSlider(id, data)
            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 0, 34)
            frame.BackgroundTransparency = 1
            frame.LayoutOrder = #controls + 1
            frame.BorderSizePixel = 0
            frame.Parent = getControlParent()

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -50, 0, 14)
            label.Position = UDim2.new(0, 0, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = data and data.Title or id
            NexusUI:BindColor(label, "TextColor3", function() return COLOR_TEXT end)
            label.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            label.TextSize = 15
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = frame

            local valueLabel = Instance.new("TextLabel")
            valueLabel.Size = UDim2.new(0, 50, 0, 14)
            valueLabel.Position = UDim2.new(1, -50, 0, 0)
            valueLabel.BackgroundTransparency = 1
            valueLabel.Text = tostring(data and data.Default or 0)
            NexusUI:BindColor(valueLabel, "TextColor3", function() return COLOR_TEXT_DIM end)
            valueLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            valueLabel.TextSize = 12
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right
            valueLabel.Parent = frame

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1, 0, 0, 4)
            track.Position = UDim2.new(0, 0, 0, 22)
            NexusUI:BindColor(track, "BackgroundColor3", function() return COLOR_CONTROL end)
            track.BorderSizePixel = 0
            track.ZIndex = 5
            track.Active = true
            track.ClipsDescendants = false
            track.Parent = frame

            local trackCorner = Instance.new("UICorner")
            trackCorner.CornerRadius = UDim.new(1, 0)
            trackCorner.Parent = track

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(0, 0, 1, 0)
            NexusUI:BindColor(fill, "BackgroundColor3", function() return ACCENT end)
            fill.BorderSizePixel = 0
            fill.ZIndex = 6
            fill.ClipsDescendants = true
            fill.Parent = track

            local fillCorner = Instance.new("UICorner")
            fillCorner.CornerRadius = UDim.new(1, 0)
            fillCorner.Parent = fill

            local knob = Instance.new("Frame")
            knob.Name = "SliderKnob"
            knob.Size = UDim2.fromOffset(8, 8)
            knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.Position = UDim2.new(0, 0, 0.5, 0)
            NexusUI:BindColor(knob, "BackgroundColor3", function() return ACCENT end)
            knob.BorderSizePixel = 0
            knob.ZIndex = 8
            knob.Active = true
            knob.Parent = track

            local knobCorner = Instance.new("UICorner")
            knobCorner.CornerRadius = UDim.new(1, 0)
            knobCorner.Parent = knob

            local value = data and data.Default or 0
            local step = data and data.Step or 1
            local minValue = data and data.Min or value
            local maxValue = data and data.Max or value
            local rounding = data and data.Rounding or 0

            local function roundValue(v)
                if rounding and rounding > 0 then
                    return tonumber(string.format("%." .. tostring(rounding) .. "f", v))
                end
                return math.floor(v + 0.5)
            end

            -- Persistent slider object so configs can read and restore its value.
            local sliderOption = {Value = value, IsSlider = true}

            local refresh

            function sliderOption:SetValue(newValue)
                newValue = tonumber(newValue)
                if not newValue then return false end
                value = newValue
                refresh()
                return true
            end

            function refresh()
                local clampedValue = Clamp(value, minValue, maxValue)
                value = clampedValue
                local range = maxValue - minValue
                local ratio = range == 0 and 0 or ((value - minValue) / range)
                ratio = Clamp(ratio, 0, 1)
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                knob.Position = UDim2.new(ratio, 0, 0.5, 0)
                valueLabel.Text = tostring(roundValue(value))
                sliderOption.Value = value
                NexusUI.Options[id] = sliderOption
                NexusUI.Options[id .. "Value"] = value
                if data and data.Callback then
                    pcall(data.Callback, value)
                end
            end

            local dragging = false

            local function setValueFromPosition(xPosition)
                local trackStart = track.AbsolutePosition.X
                local trackSize = track.AbsoluteSize.X
                local ratio = Clamp((xPosition - trackStart) / math.max(trackSize, 1), 0, 1)
                local range = maxValue - minValue
                value = minValue + (range * ratio)
                if step and step > 0 then
                    value = roundValue(math.floor((value / step) + 0.5) * step)
                end
                refresh()
            end

            local function beginSliderDrag(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    setValueFromPosition(input.Position.X)
                end
            end

            table.insert(connections, track.InputBegan:Connect(beginSliderDrag))
            table.insert(connections, knob.InputBegan:Connect(beginSliderDrag))

            table.insert(connections, userInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    setValueFromPosition(input.Position.X)
                end
            end))

            table.insert(connections, userInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end))

            refresh()
            table.insert(controls, frame)
            return frame
        end

        function tabObject:AddDropdown(id, data)
            local horizontalInset = math.max(0, tonumber(data and data.HorizontalInset) or 8)
            local selectorHeight = math.max(20, tonumber(data and data.SelectorHeight) or 36)
            local listMaxHeight = math.max(90, tonumber(data and data.ListMaxHeight) or 210)
            local optionHeight = math.max(24, tonumber(data and data.OptionHeight) or 36)
            local selectorY = 26
            local closedHeight = selectorY + selectorHeight + 10
            local listY = closedHeight + 4

            local dropdownFrame = Instance.new("Frame")
            dropdownFrame.Size = UDim2.new(1, 0, 0, closedHeight)
            NexusUI:BindColor(dropdownFrame, "BackgroundColor3", function() return COLOR_GROUP end)
            dropdownFrame.BackgroundTransparency = GUI_PANEL_TRANSPARENCY
            dropdownFrame.BorderSizePixel = 0
            dropdownFrame.ClipsDescendants = true
            dropdownFrame.LayoutOrder = #controls + 1
            dropdownFrame.Parent = getControlParent()

            local dropdownCorner = Instance.new("UICorner")
            dropdownCorner.CornerRadius = UDim.new(0, 10)
            dropdownCorner.Parent = dropdownFrame

            local dropdownStroke = Instance.new("UIStroke")
            dropdownStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            NexusUI:BindColor(dropdownStroke, "Color", function() return COLOR_BORDER end)
            dropdownStroke.Transparency = 0.42
            dropdownStroke.Thickness = 1
            dropdownStroke.Parent = dropdownFrame

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -16, 0, 14)
            title.Position = UDim2.fromOffset(12, 7)
            title.BackgroundTransparency = 1
            title.Text = data and data.Title or id
            NexusUI:BindColor(title, "TextColor3", function() return COLOR_TEXT_DIM end)
            title.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            title.TextSize = 12
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Parent = dropdownFrame

            local selector, selectorLabel = CreateClickButton(
                dropdownFrame,
                "Select...",
                UDim2.new(1, -(horizontalInset * 2), 0, selectorHeight),
                UDim2.fromOffset(horizontalInset, selectorY),
                COLOR_CONTROL,
                COLOR_TEXT,
                Enum.Font.GothamSemibold,
                12
            )
            local selectorStroke = Instance.new("UIStroke")
            selectorStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            selectorStroke.Transparency = 0.5
            NexusUI:BindColor(selectorStroke, "Color", function() return COLOR_BORDER end)
            selectorStroke.Parent = selector
            selectorLabel.TextXAlignment = Enum.TextXAlignment.Left
            selectorLabel.TextTruncate = Enum.TextTruncate.AtEnd

            local selectorAccent = Instance.new("Frame")
            selectorAccent.Size = UDim2.fromOffset(3, 18)
            selectorAccent.Position = UDim2.new(0, 7, 0.5, -9)
            selectorAccent.BorderSizePixel = 0
            NexusUI:BindColor(selectorAccent, "BackgroundColor3", function() return ACCENT end)
            selectorAccent.Parent = selector

            local selectorAccentCorner = Instance.new("UICorner")
            selectorAccentCorner.CornerRadius = UDim.new(1, 0)
            selectorAccentCorner.Parent = selectorAccent

            local selectorPadding = Instance.new("UIPadding")
            selectorPadding.PaddingLeft = UDim.new(0, 18)
            selectorPadding.PaddingRight = UDim.new(0, 38)
            selectorPadding.Parent = selectorLabel

            local arrow = Instance.new("TextLabel")
            arrow.BackgroundTransparency = 1
            arrow.Size = UDim2.fromOffset(28, selectorHeight)
            arrow.Position = UDim2.new(1, -32, 0, 0)
            arrow.Text = "›"
            arrow.Font = Enum.Font.GothamBold
            arrow.TextSize = 21
            arrow.Rotation = 90
            NexusUI:BindColor(arrow, "TextColor3", function() return ACCENT end)
            arrow.Parent = selector
            local optionViews, openTween, arrowTween = {}, nil, nil
            local function refreshSelection(value)
                for v, item in pairs(optionViews) do
                    item[1]:SetAttribute("Selected", v == value)
                    item[3].Visible = v == value
                    item[4].Visible = v == value
                    item[5](false)
                end
            end

            local optionsList = Instance.new("ScrollingFrame")
            optionsList.Size = UDim2.new(1, -(horizontalInset * 2), 0, 0)
            optionsList.Position = UDim2.fromOffset(horizontalInset, listY)
            NexusUI:BindColor(optionsList, "BackgroundColor3", function() return COLOR_TOPBAR end)
            optionsList.BackgroundTransparency = 0.08
            optionsList.BorderSizePixel = 0
            optionsList.ScrollBarThickness = 3
            NexusUI:BindColor(optionsList, "ScrollBarImageColor3", function() return COLOR_BORDER end)
            optionsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
            optionsList.CanvasSize = UDim2.new()
            optionsList.Visible = false
            optionsList.Parent = dropdownFrame

            local optionsCorner = Instance.new("UICorner")
            optionsCorner.CornerRadius = UDim.new(0, 8)
            optionsCorner.Parent = optionsList

            local optionsStroke = Instance.new("UIStroke")
            optionsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            NexusUI:BindColor(optionsStroke, "Color", function() return COLOR_BORDER end)
            optionsStroke.Transparency = 0.52
            optionsStroke.Parent = optionsList

            local optionsPadding = Instance.new("UIPadding")
            optionsPadding.PaddingTop = UDim.new(0, 2)
            optionsPadding.PaddingBottom = UDim.new(0, 2)
            optionsPadding.PaddingLeft = UDim.new(0, 2)
            optionsPadding.PaddingRight = UDim.new(0, 2)
            optionsPadding.Parent = optionsList

            local optionsLayout = Instance.new("UIListLayout")
            optionsLayout.Padding = UDim.new(0, 4)
            optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
            optionsLayout.Parent = optionsList

            local dropdown = {
                Value = nil,
                Values = {},
                Opened = false,
                IsDropdown = true,
            }

            local function connectActivated(guiObject, callback)
                local hitbox = Instance.new("TextButton")
                hitbox.Name = "InputHitbox"
                hitbox.Size = UDim2.fromScale(1, 1)
                hitbox.BackgroundTransparency = 1
                hitbox.BorderSizePixel = 0
                hitbox.Text = ""
                hitbox.AutoButtonColor = false
                hitbox.Active = true
                hitbox.Selectable = true
                hitbox.ZIndex = guiObject.ZIndex + 2
                hitbox.Parent = guiObject
                TrackGuiConnection(hitbox.Activated:Connect(callback))
                return hitbox
            end

            local function updateOpenState(open)
                dropdown.Opened = open == true
                local count = #dropdown.Values
                local listHeight = math.min((count * (optionHeight + 4)), listMaxHeight)
                optionsList.Visible = dropdown.Opened and count > 0
                optionsList.Size = UDim2.new(1, -(horizontalInset * 2), 0, optionsList.Visible and listHeight or 0)
                if openTween then openTween:Cancel() end
                if arrowTween then arrowTween:Cancel() end
                openTween = TweenService:Create(dropdownFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, optionsList.Visible and (listY + listHeight + 8) or closedHeight)})
                arrowTween = TweenService:Create(arrow, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Rotation = dropdown.Opened and -90 or 90})
                NexusUI:BindColor(dropdownStroke, "Color", function() return dropdown.Opened and ACCENT or COLOR_BORDER end)
                NexusUI:BindColor(selectorStroke, "Color", function() return dropdown.Opened and ACCENT or COLOR_BORDER end)
                openTween:Play()
                arrowTween:Play()
                if count == 0 then
                    selectorLabel.Text = "No options available"
                else
                    selectorLabel.Text = (dropdown.Value and tostring(dropdown.Value) or "Select...")
                end
            end

            local function setValue(value, invokeCallback)
                if value == nil then return false end
                local found = false
                for _, availableValue in ipairs(dropdown.Values) do
                    if availableValue == value then
                        found = true
                        break
                    end
                end
                if not found then return false end

                dropdown.Value = value
                refreshSelection(value)
                updateOpenState(false)
                if invokeCallback ~= false and data and data.Callback then
                    pcall(data.Callback, value)
                end
                return true
            end

            local function rebuildOptions()
                table.clear(optionViews)
                for _, child in ipairs(optionsList:GetChildren()) do
                    if child:IsA("GuiObject") then
                        child:Destroy()
                    end
                end

                for index, value in ipairs(dropdown.Values) do
                    local option, optionLabel = CreateClickButton(
                        optionsList,
                        tostring(value),
                        UDim2.new(1, -2, 0, optionHeight),
                        UDim2.new(),
                        COLOR_CONTROL,
                        COLOR_TEXT,
                        Enum.Font.GothamSemibold,
                        12,
                        true
                    )
                    option.LayoutOrder = index
                    local selected = Instance.new("TextLabel")
                    selected.BackgroundTransparency = 1
                    selected.Size = UDim2.fromOffset(24, optionHeight)
                    selected.Position = UDim2.new(1, -28, 0, 0)
                    selected.Text = "✓"
                    selected.Font = Enum.Font.GothamBold
                    selected.TextSize = 13
                    selected.ZIndex = optionLabel.ZIndex
                    selected.Visible = false
                    NexusUI:BindColor(selected, "TextColor3", function() return ACCENT end)
                    selected.Parent = option
                    local optionAccent = Instance.new("Frame")
                    optionAccent.Size = UDim2.fromOffset(3, math.max(14, optionHeight - 16))
                    optionAccent.Position = UDim2.new(0, 5, 0.5, -math.max(14, optionHeight - 16) / 2)
                    optionAccent.BorderSizePixel = 0
                    optionAccent.Visible = false
                    optionAccent.ZIndex = optionLabel.ZIndex
                    NexusUI:BindColor(optionAccent, "BackgroundColor3", function() return ACCENT end)
                    optionAccent.Parent = option
                    local optionAccentCorner = Instance.new("UICorner")
                    optionAccentCorner.CornerRadius = UDim.new(1, 0)
                    optionAccentCorner.Parent = optionAccent
                    local hovered, hoverTween = false, nil
                    local function color()
                        return COLOR_CONTROL:Lerp(ACCENT, option:GetAttribute("Selected") and 0.2 or hovered and 0.1 or 0)
                    end
                    NexusUI:BindColor(option, "BackgroundColor3", color)
                    local function paint(animated)
                        if hoverTween then hoverTween:Cancel() end
                        if animated then
                            hoverTween = TweenService:Create(option, TweenInfo.new(0.12), {BackgroundColor3 = color()})
                            hoverTween:Play()
                        else option.BackgroundColor3 = color() end
                    end
                    TrackGuiConnection(option.MouseEnter:Connect(function() hovered = true; paint(true) end))
                    TrackGuiConnection(option.MouseLeave:Connect(function() hovered = false; paint(true) end))
                    optionViews[value] = {option, optionLabel, selected, optionAccent, paint}
                    optionLabel.TextTruncate = Enum.TextTruncate.AtEnd
                    optionLabel.TextXAlignment = Enum.TextXAlignment.Left
                    local optionPadding = Instance.new("UIPadding")
                    optionPadding.PaddingLeft = UDim.new(0, 16)
                    optionPadding.PaddingRight = UDim.new(0, 36)
                    optionPadding.Parent = optionLabel
                    connectActivated(option, function()
                        setValue(value, true)
                    end)
                end
                refreshSelection(dropdown.Value)
                updateOpenState(dropdown.Opened)
            end

            function dropdown:SetValues(values)
                local same = #self.Values == #(values or {})
                if same then
                    for i, v in ipairs(values or {}) do if self.Values[i] ~= v then same = false; break end end
                end
                if same then return end
                self.Values = {}
                for _, value in ipairs(values or {}) do
                    table.insert(self.Values, value)
                end
                if self.Value then
                    local stillExists = false
                    for _, value in ipairs(self.Values) do
                        if value == self.Value then
                            stillExists = true
                            break
                        end
                    end
                    if not stillExists then
                        self.Value = nil
                    end
                end
                rebuildOptions()
            end

            function dropdown:SetValue(value)
                return setValue(value, true)
            end

            function dropdown:GetValue()
                return self.Value
            end

            connectActivated(selector, function()
                updateOpenState(not dropdown.Opened)
            end)

            dropdown:SetValues(data and data.Values or {})
            if data and data.Default ~= nil then
                setValue(data.Default, false)
            end

            NexusUI.Options[id] = dropdown
            table.insert(controls, dropdownFrame)
            return dropdown
        end

        function tabObject:AddButton(data)
            local hasDesc = data and data.Description and data.Description ~= ""

            local buttonFrame = Instance.new("Frame")
            buttonFrame.Size = hasDesc and UDim2.new(1, 0, 0, 52) or UDim2.new(1, 0, 0, 38)
            NexusUI:BindColor(buttonFrame, "BackgroundColor3", function() return COLOR_CONTROL end)
            buttonFrame.BackgroundTransparency = GUI_BUTTON_TRANSPARENCY
            buttonFrame.LayoutOrder = #controls + 1
            buttonFrame.BorderSizePixel = 0
            buttonFrame.Active = true
            buttonFrame.Parent = getControlParent()

            local bCorner = Instance.new("UICorner")
            bCorner.CornerRadius = UDim.new(0, 10)
            bCorner.Parent = buttonFrame

            local bStroke = Instance.new("UIStroke")
            bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            NexusUI:BindColor(bStroke, "Color", function() return COLOR_BORDER end)
            bStroke.Transparency = 0.4
            bStroke.Thickness = 1
            bStroke.Parent = buttonFrame

            local titleLabel = Instance.new("TextLabel")
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = data and data.Title or "Button"
            NexusUI:BindColor(titleLabel, "TextColor3", function() return COLOR_TEXT end)
            titleLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
            titleLabel.TextSize = 15
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.TextYAlignment = Enum.TextYAlignment.Center
            if hasDesc then
                titleLabel.Size = UDim2.new(1, -36, 0, 15)
                titleLabel.Position = UDim2.new(0, 10, 0, 7)
            else
                titleLabel.Size = UDim2.new(1, -36, 1, 0)
                titleLabel.Position = UDim2.new(0, 10, 0, 0)
            end
            titleLabel.Parent = buttonFrame

            if hasDesc then
                local descLabel = Instance.new("TextLabel")
                descLabel.Size = UDim2.new(1, -36, 0, 12)
                descLabel.Position = UDim2.new(0, 10, 0, 25)
                descLabel.BackgroundTransparency = 1
                descLabel.Text = data.Description
                NexusUI:BindColor(descLabel, "TextColor3", function() return COLOR_TEXT_DIM end)
                descLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
                descLabel.TextSize = 12
                descLabel.TextXAlignment = Enum.TextXAlignment.Left
                descLabel.TextWrapped = true
                descLabel.Parent = buttonFrame
            end

            local arrowLabel = Instance.new("TextLabel")
            arrowLabel.Size = UDim2.fromOffset(14, 14)
            arrowLabel.AnchorPoint = Vector2.new(1, 0.5)
            arrowLabel.Position = UDim2.new(1, -8, 0.5, 0)
            arrowLabel.BackgroundTransparency = 1
            arrowLabel.Text = ">"
            NexusUI:BindColor(arrowLabel, "TextColor3", function() return COLOR_TEXT_DIM end)
            arrowLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
            arrowLabel.TextSize = 14
            arrowLabel.ZIndex = buttonFrame.ZIndex + 1
            arrowLabel.Parent = buttonFrame

            local defaultBg = COLOR_CONTROL
            local hoverBg = COLOR_CONTROL:Lerp(ACCENT, 0.12)
            table.insert(NexusUI.ThemeRefresh, function() defaultBg = COLOR_CONTROL; hoverBg = COLOR_CONTROL:Lerp(ACCENT, 0.12) end)

            TrackGuiConnection(buttonFrame.MouseEnter:Connect(function()
                TweenService:Create(buttonFrame, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {BackgroundColor3 = hoverBg}):Play()
                TweenService:Create(bStroke, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {Transparency = 0.3}):Play()
            end))

            TrackGuiConnection(buttonFrame.MouseLeave:Connect(function()
                TweenService:Create(buttonFrame, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {BackgroundColor3 = defaultBg}):Play()
                TweenService:Create(bStroke, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {Transparency = 0.55}):Play()
            end))

            ConnectClick(buttonFrame, function()
                TweenService:Create(buttonFrame, TweenInfo.new(0.07, Enum.EasingStyle.Quad), {BackgroundColor3 = COLOR_CONTROL}):Play()
                task.delay(0.12, function()
                    if buttonFrame and buttonFrame.Parent then
                        TweenService:Create(buttonFrame, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {BackgroundColor3 = defaultBg}):Play()
                    end
                end)
                if data and data.Callback then
                    pcall(data.Callback)
                end
            end)

            table.insert(controls, buttonFrame)
            return buttonFrame
        end

        local tabIndex = #tabs + 1
        if IS_MOBILE then
            TrackGuiConnection(tabButton.Activated:Connect(function()
                selectTab(tabIndex)
            end))
        else
            ConnectClick(tabButton, function()
                selectTab(tabIndex)
            end)
        end

        table.insert(tabs, {button = tabButton, page = tabPage, label = tabLabel, underline = tabUnderline})
        if tabIndex == 1 then
            selectTab(1)
        end
        return tabObject
    end

    function window:SelectTab(index)
        selectTab(index)
    end

    function window:SetCollapsed(value)
        setCollapsed(value)
    end

    function window:ToggleCollapsed()
        setCollapsed(not isCollapsed)
    end

    function window:SetVisible(visible)
        setVisible(visible)
    end

    function window:IsVisible()
        return mainFrame.Visible
    end

    function window:SetSize(width, height)
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        local minWidth = IS_MOBILE and 320 or 430
        preferredSize = Vector2.new(
            math.clamp(math.floor(tonumber(width) or preferredSize.X), minWidth, math.max(minWidth, camera.ViewportSize.X - 16)),
            math.clamp(math.floor(tonumber(height) or preferredSize.Y), 320, math.max(320, camera.ViewportSize.Y - 64))
        )
        userResized = true
        mainFrame.Size = UDim2.fromOffset(preferredSize.X, preferredSize.Y)
        fitWindow()
        return true
    end

    function window:GetSize()
        return preferredSize.X, preferredSize.Y
    end

    track(userInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == toggleKey then
            window:SetVisible(not mainFrame.Visible)
        end
    end))

    local function updateRestoreVisibility()
        if not SHOW_RESTORE_BUTTON then
            if restoreGui then
                restoreGui:Destroy()
                restoreGui = nil
            end
            return
        end

        if not mainFrame.Visible or not screenGui.Enabled then
            local mobileButtonGui = createRestoreGui()
            if mobileButtonGui then
                mobileButtonGui.Enabled = true
            end
        elseif restoreGui then
            restoreGui.Enabled = false
        end
    end

    track(mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        updateRestoreVisibility()
    end))

    track(screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        updateRestoreVisibility()
    end))

    if not isVisibleByDefault then
        setVisible(false)
    else
        animateWindowIn()
        updateRestoreVisibility()
    end

    local windowDestroyed = false
    destroyWindow = function()
        if windowDestroyed then
            return
        end
        windowDestroyed = true

        NexusUI:UnloadFeatures()
        destroyCloseConfirm()

        for _, conn in ipairs(connections) do
            if conn and conn.Connected then
                conn:Disconnect()
            end
        end
        connections = {}
        for _, conn in ipairs(GuiConnections) do
            if conn and conn.Connected then
                conn:Disconnect()
            end
        end
        GuiConnections = {}
        if restoreGui then
            restoreGui:Destroy()
            restoreGui = nil
        end
        if screenGui and screenGui.Parent then
            screenGui:Destroy()
        end
    end

    function window:Destroy()
        destroyWindow()
    end

    return window
end

function NexusUI:CreateMinimizer()
    return nil
end

function NexusUI:Notify(options)
    local notifyGui = Instance.new("ScreenGui")
    notifyGui.Name = "NexusNotify"
    notifyGui.ResetOnSpawn = false
    notifyGui.Parent = GuiParent
    attachTextStyler(notifyGui)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(300, 54)
    frame.Position = UDim2.new(1, -310, 0, 20)
    NexusUI:BindColor(frame, "BackgroundColor3", function() return COLOR_WINDOW end)
    frame.BackgroundTransparency = 0.02
    frame.BorderSizePixel = 0
    frame.Parent = notifyGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 6)
    frameCorner.Parent = frame

    local frameStroke = Instance.new("UIStroke")
    frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    NexusUI:BindColor(frameStroke, "Color", function() return COLOR_BORDER end)
    frameStroke.Transparency = 0.4
    frameStroke.Thickness = 1
    frameStroke.Parent = frame

    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 3, 1, -10)
    accentBar.Position = UDim2.new(0, 5, 0, 5)
    NexusUI:BindColor(accentBar, "BackgroundColor3", function() return ACCENT end)
    accentBar.BorderSizePixel = 0
    accentBar.Parent = frame

    local accentBarCorner = Instance.new("UICorner")
    accentBarCorner.CornerRadius = UDim.new(1, 0)
    accentBarCorner.Parent = accentBar

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -22, 1, 0)
    label.Position = UDim2.new(0, 16, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = (options and options.Title or "Notify") .. "\n" .. (options and options.Content or "")
    NexusUI:BindColor(label, "TextColor3", function() return COLOR_TEXT end)
    label.FontFace = Font.new(FONT_BODY, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = frame

    task.delay((options and options.Duration or 3) + 0.2, function()
        if notifyGui then
            notifyGui:Destroy()
        end
    end)
end

windowSize = IS_MOBILE and UDim2.fromOffset(620, 390) or UDim2.fromOffset(640, 350)

Window = NexusUI:CreateWindow({
    Title = "",
    Size = windowSize,
    Theme = "Noir",
    visible = true,
    MinimizeKey = Enum.KeyCode.LeftAlt
})

StarterGui:SetCore("SendNotification", {
    Title = "PRIME Loaded",
    Text = "PRIME Loaded Successfully!",
    Duration = 4,
    Button1 = "OK"
})

Tabs = {
    Main = Window:AddTab({ Title = "Main"}),
    Movement = Window:AddTab({ Title = "Movement"}),
    ESP = Window:AddTab({ Title = "ESP"}),
    Zone = Window:AddTab({ Title = "Zone"}),
    Misc = Window:AddTab({ Title = "Misc"}),
    Visuals = Window:AddTab({ Title = "Visuals"}),
    Other = Window:AddTab({ Title = "Other"})
}

Tabs.Settings = Window:AddTab({ Title = "Settings"})
NexusUI:SetTheme("Noir")

currentCloseKey = Enum.KeyCode.LeftAlt
waitingForKey = false

if not IS_MOBILE then
SettingsSection = Tabs.Settings:AddSection("Keybinds")

keybindRow = Instance.new("Frame")
keybindRow.Size = UDim2.new(1, 0, 0, 48)
NexusUI:BindColor(keybindRow, "BackgroundColor3", function() return COLOR_CONTROL end)
keybindRow.BackgroundTransparency = GUI_BUTTON_TRANSPARENCY
keybindRow.BorderSizePixel = 0
keybindRow.LayoutOrder = 2
keybindRow.Parent = SettingsSection.Content

keybindRowCorner = Instance.new("UICorner")
keybindRowCorner.CornerRadius = UDim.new(0, 10)
keybindRowCorner.Parent = keybindRow

keybindTitle = Instance.new("TextLabel")
keybindTitle.Size = UDim2.new(1, -130, 0, 16)
keybindTitle.Position = UDim2.new(0, 8, 0, 8)
keybindTitle.BackgroundTransparency = 1
keybindTitle.Text = "Toggle GUI"
NexusUI:BindColor(keybindTitle, "TextColor3", function() return COLOR_TEXT end)
keybindTitle.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
keybindTitle.TextSize = 15
keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
keybindTitle.Parent = keybindRow

keybindHint = Instance.new("TextLabel")
keybindHint.Size = UDim2.new(1, -130, 0, 13)
keybindHint.Position = UDim2.new(0, 8, 0, 27)
keybindHint.BackgroundTransparency = 1
keybindHint.Text = "Click box to rebind"
NexusUI:BindColor(keybindHint, "TextColor3", function() return COLOR_TEXT_DIM end)
keybindHint.FontFace = Font.new(FONT_BODY, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
keybindHint.TextSize = 11
keybindHint.TextXAlignment = Enum.TextXAlignment.Left
keybindHint.Parent = keybindRow

keybindBadge = Instance.new("Frame")
keybindBadge.Size = UDim2.fromOffset(78, 28)
keybindBadge.Position = UDim2.new(1, -86, 0.5, -14)
NexusUI:BindColor(keybindBadge, "BackgroundColor3", function() return COLOR_CONTROL end)
keybindBadge.BackgroundTransparency = GUI_BUTTON_TRANSPARENCY
keybindBadge.BorderSizePixel = 0
keybindBadge.Active = true
keybindBadge.ZIndex = 5
keybindBadge.Parent = keybindRow

keybindBadgeCorner = Instance.new("UICorner")
keybindBadgeCorner.CornerRadius = UDim.new(0, 7)
keybindBadgeCorner.Parent = keybindBadge

keybindBadgeStroke = Instance.new("UIStroke")
keybindBadgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
NexusUI:BindColor(keybindBadgeStroke, "Color", function() return COLOR_BORDER end)
keybindBadgeStroke.Transparency = 0.4
keybindBadgeStroke.Thickness = 1
keybindBadgeStroke.Parent = keybindBadge

keybindBadgeLabel = Instance.new("TextLabel")
keybindBadgeLabel.Size = UDim2.new(1, -6, 1, 0)
keybindBadgeLabel.Position = UDim2.new(0, 3, 0, 0)
keybindBadgeLabel.BackgroundTransparency = 1
keybindBadgeLabel.Text = "LeftAlt"
NexusUI:BindColor(keybindBadgeLabel, "TextColor3", function() return COLOR_TEXT end)
keybindBadgeLabel.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
keybindBadgeLabel.TextSize = 13
keybindBadgeLabel.TextTruncate = Enum.TextTruncate.AtEnd
keybindBadgeLabel.ZIndex = 6
keybindBadgeLabel.Parent = keybindBadge

function UpdateKeybindBadge()
    keybindBadgeLabel.Text = currentCloseKey and currentCloseKey.Name or "None"
    NexusUI:BindColor(keybindBadgeLabel, "TextColor3", function() return COLOR_TEXT end)
    TweenService:Create(keybindBadge, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        BackgroundColor3 = COLOR_CONTROL
    }):Play()
    TweenService:Create(keybindBadgeStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        Color = COLOR_BORDER,
        Transparency = 0.4
    }):Play()
end

function SetGUIKey(key)
    if not key then return end
    currentCloseKey = key
    Window:SetToggleKey(key)
    waitingForKey = false
    UpdateKeybindBadge()
end

function BeginKeyBinding()
    waitingForKey = true
    keybindBadgeLabel.Text = "..."
    NexusUI:BindColor(keybindBadgeLabel, "TextColor3", function() return COLOR_TEXT end)
    TweenService:Create(keybindBadge, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        BackgroundColor3 = COLOR_BORDER
    }):Play()
    TweenService:Create(keybindBadgeStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        Color = ACCENT,
        Transparency = 0.1
    }):Play()
end

TrackScriptConnection(userInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if waitingForKey then
        if input.KeyCode == Enum.KeyCode.Escape then
            waitingForKey = false
            UpdateKeybindBadge()
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
            SetGUIKey(input.KeyCode)
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            SetGUIKey(Enum.KeyCode.MouseButton1)
        else
            waitingForKey = false
            UpdateKeybindBadge()
        end
    end
end))

ConnectClick(keybindBadge, function()
    if waitingForKey then
        waitingForKey = false
        UpdateKeybindBadge()
    else
        BeginKeyBinding()
    end
end)

TrackGuiConnection(keybindBadge.MouseEnter:Connect(function()
    if not waitingForKey then
        TweenService:Create(keybindBadge, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
            BackgroundColor3 = COLOR_CONTROL
        }):Play()
    end
end))

TrackGuiConnection(keybindBadge.MouseLeave:Connect(function()
    if not waitingForKey then
        TweenService:Create(keybindBadge, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
            BackgroundColor3 = COLOR_CONTROL
        }):Play()
    end
end))
end -- desktop-only Settings UI

-- Configs: save / load / overwrite / rename / delete every toggle, slider and dropdown.
do
    local HttpService = game:GetService("HttpService")
    local CONFIG_ROOT = "PRIME"
    local CONFIG_FOLDER = CONFIG_ROOT .. "/Configs"
    local CONFIG_LIST_ID = "PRIME_ConfigList"
    local CONFIG_EXCLUDED = {
        [CONFIG_LIST_ID] = true,
        EmoteAnimation = true, -- plays an emote on select, not a setting
    }

    local function configNotify(content)
        NexusUI:Notify({Title = "Configs", Content = content, Duration = 3})
    end

    local function fileApiAvailable()
        return type(writefile) == "function" and type(readfile) == "function"
            and type(isfile) == "function" and type(listfiles) == "function"
            and type(makefolder) == "function" and type(isfolder) == "function"
    end

    local function ensureConfigFolder()
        if not fileApiAvailable() then return false end
        local ok = pcall(function()
            if not isfolder(CONFIG_ROOT) then makefolder(CONFIG_ROOT) end
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        end)
        return ok
    end

    local function sanitizeConfigName(name)
        name = tostring(name or ""):gsub("[^%w%s%-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #name > 32 then name = name:sub(1, 32) end
        return name
    end

    local function configPath(name)
        return CONFIG_FOLDER .. "/" .. name .. ".json"
    end

    local function configExists(name)
        local ok, result = pcall(isfile, configPath(name))
        return ok and result == true
    end

    local function listConfigs()
        local names = {}
        if not ensureConfigFolder() then return names end
        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if not ok or type(files) ~= "table" then return names end
        for _, path in ipairs(files) do
            local name = tostring(path):match("([^/\\]+)%.json$")
            if name then table.insert(names, name) end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end

    local function collectConfig()
        local data = {Version = 1, Toggles = {}, Sliders = {}, Dropdowns = {}}
        for id, option in pairs(NexusUI.Options) do
            if type(option) == "table" and not CONFIG_EXCLUDED[id] then
                if option.IsToggle then
                    data.Toggles[id] = option.Value == true
                elseif option.IsSlider then
                    data.Sliders[id] = tonumber(option.Value)
                elseif option.IsDropdown and option.Value ~= nil then
                    data.Dropdowns[id] = tostring(option.Value)
                end
            end
        end
        if currentCloseKey then
            data.Keybind = currentCloseKey.Name
        end
        return data
    end

    local function writeConfig(name)
        if not ensureConfigFolder() then
            configNotify("Your executor does not support file saving")
            return false
        end
        local ok, err = pcall(function()
            writefile(configPath(name), HttpService:JSONEncode(collectConfig()))
        end)
        if not ok then
            configNotify("Failed to save: " .. tostring(err))
        end
        return ok
    end

    local function applyConfig(data)
        local applied = 0

        for id, value in pairs(type(data.Sliders) == "table" and data.Sliders or {}) do
            local option = NexusUI.Options[id]
            if type(option) == "table" and option.IsSlider and option.Value ~= value then
                if pcall(function() option:SetValue(value) end) then applied += 1 end
            end
        end

        for id, value in pairs(type(data.Dropdowns) == "table" and data.Dropdowns or {}) do
            local option = NexusUI.Options[id]
            if type(option) == "table" and option.IsDropdown and not CONFIG_EXCLUDED[id]
                and tostring(option.Value) ~= value then
                for _, available in ipairs(option.Values) do
                    if tostring(available) == value then
                        if pcall(function() option:SetValue(available) end) then applied += 1 end
                        break
                    end
                end
            end
        end

        -- Toggles last so features start with the restored slider/dropdown values.
        for id, value in pairs(type(data.Toggles) == "table" and data.Toggles or {}) do
            local option = NexusUI.Toggles[id]
            if type(option) == "table" and option.Value ~= (value == true) then
                if pcall(function() option:SetValue(value == true) end) then applied += 1 end
            end
        end

        if type(data.Keybind) == "string" and not IS_MOBILE and type(SetGUIKey) == "function" then
            local ok, key = pcall(function() return Enum.KeyCode[data.Keybind] end)
            if ok and key then pcall(SetGUIKey, key) end
        end

        return applied
    end

    local function readConfig(name)
        if not fileApiAvailable() then
            configNotify("Your executor does not support file loading")
            return nil
        end
        if not configExists(name) then
            configNotify("Config \"" .. name .. "\" not found")
            return nil
        end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(configPath(name)))
        end)
        if not ok or type(data) ~= "table" then
            configNotify("Config \"" .. name .. "\" is corrupted")
            return nil
        end
        return data
    end

    local ConfigSection = Tabs.Settings:AddSection("Configs")

    -- Config name input
    local nameRow = Instance.new("Frame")
    nameRow.Size = UDim2.new(1, 0, 0, 38)
    NexusUI:BindColor(nameRow, "BackgroundColor3", function() return COLOR_CONTROL end)
    nameRow.BackgroundTransparency = GUI_BUTTON_TRANSPARENCY
    nameRow.BorderSizePixel = 0
    nameRow.LayoutOrder = 0
    nameRow.Parent = ConfigSection.Content

    local nameRowCorner = Instance.new("UICorner")
    nameRowCorner.CornerRadius = UDim.new(0, 10)
    nameRowCorner.Parent = nameRow

    local nameRowStroke = Instance.new("UIStroke")
    nameRowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    NexusUI:BindColor(nameRowStroke, "Color", function() return COLOR_BORDER end)
    nameRowStroke.Transparency = 0.4
    nameRowStroke.Thickness = 1
    nameRowStroke.Parent = nameRow

    local nameBox = Instance.new("TextBox")
    nameBox.Size = UDim2.new(1, -20, 1, 0)
    nameBox.Position = UDim2.new(0, 10, 0, 0)
    nameBox.BackgroundTransparency = 1
    nameBox.ClearTextOnFocus = false
    nameBox.Text = ""
    nameBox.PlaceholderText = "Config name..."
    NexusUI:BindColor(nameBox, "TextColor3", function() return COLOR_TEXT end)
    NexusUI:BindColor(nameBox, "PlaceholderColor3", function() return COLOR_TEXT_DIM end)
    nameBox.FontFace = Font.new(FONT_BODY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
    nameBox.TextSize = 15
    nameBox.TextXAlignment = Enum.TextXAlignment.Left
    nameBox.TextTruncate = Enum.TextTruncate.AtEnd
    nameBox.ZIndex = 5
    nameBox.Parent = nameRow

    TrackGuiConnection(nameBox.Focused:Connect(function()
        nameRowStroke.Transparency = 0.1
        NexusUI:BindColor(nameRowStroke, "Color", function() return ACCENT end)
    end))
    TrackGuiConnection(nameBox.FocusLost:Connect(function()
        nameRowStroke.Transparency = 0.4
        NexusUI:BindColor(nameRowStroke, "Color", function() return COLOR_BORDER end)
    end))

    local configDropdown = Tabs.Settings:AddDropdown(CONFIG_LIST_ID, {
        Title = "Config List",
        Values = listConfigs(),
    })

    local function refreshConfigList(selectName)
        configDropdown:SetValues(listConfigs())
        if selectName then
            configDropdown:SetValue(selectName)
        end
    end

    local function getSelectedConfig()
        local selected = configDropdown:GetValue()
        if not selected then
            configNotify("Select a config first")
        end
        return selected
    end

    Tabs.Settings:AddButton({
        Title = "Create Config",
        Description = "Save current settings as a new config",
        Callback = function()
            local name = sanitizeConfigName(nameBox.Text)
            if name == "" then
                configNotify("Enter a config name")
                return
            end
            if configExists(name) then
                configNotify("\"" .. name .. "\" already exists. Use Overwrite")
                return
            end
            if writeConfig(name) then
                nameBox.Text = ""
                refreshConfigList(name)
                configNotify("Created \"" .. name .. "\"")
            end
        end,
    })

    Tabs.Settings:AddButton({
        Title = "Load Config",
        Description = "Apply the selected config",
        Callback = function()
            local name = getSelectedConfig()
            if not name then return end
            local data = readConfig(name)
            if not data then return end
            applyConfig(data)
            configNotify("Loaded \"" .. name .. "\"")
        end,
    })

    Tabs.Settings:AddButton({
        Title = "Overwrite Config",
        Description = "Save current settings into the selected config",
        Callback = function()
            local name = getSelectedConfig()
            if not name then return end
            if writeConfig(name) then
                configNotify("Overwrote \"" .. name .. "\"")
            end
        end,
    })

    Tabs.Settings:AddButton({
        Title = "Rename Config",
        Description = "Rename the selected config to the name above",
        Callback = function()
            local oldName = getSelectedConfig()
            if not oldName then return end
            local newName = sanitizeConfigName(nameBox.Text)
            if newName == "" then
                configNotify("Enter a new name above")
                return
            end
            if newName == oldName then return end
            if configExists(newName) then
                configNotify("\"" .. newName .. "\" already exists")
                return
            end
            local ok, err = pcall(function()
                writefile(configPath(newName), readfile(configPath(oldName)))
                delfile(configPath(oldName))
            end)
            if not ok then
                configNotify("Failed to rename: " .. tostring(err))
                return
            end
            nameBox.Text = ""
            refreshConfigList(newName)
            configNotify("Renamed to \"" .. newName .. "\"")
        end,
    })

    local pendingDelete, pendingDeleteTime = nil, 0
    Tabs.Settings:AddButton({
        Title = "Delete Config",
        Description = "Click twice to delete the selected config",
        Callback = function()
            local name = getSelectedConfig()
            if not name then return end
            if pendingDelete ~= name or os.clock() - pendingDeleteTime > 3 then
                pendingDelete, pendingDeleteTime = name, os.clock()
                configNotify("Click Delete again to remove \"" .. name .. "\"")
                return
            end
            pendingDelete = nil
            if type(delfile) ~= "function" then
                configNotify("Your executor does not support deleting files")
                return
            end
            local ok, err = pcall(delfile, configPath(name))
            if not ok then
                configNotify("Failed to delete: " .. tostring(err))
                return
            end
            refreshConfigList()
            configNotify("Deleted \"" .. name .. "\"")
        end,
    })

    Tabs.Settings:AddButton({
        Title = "Refresh List",
        Callback = function()
            refreshConfigList()
        end,
    })
end

end}
