return {Exports={},Init=function()
if not GuiParent or not Tabs then return end

do
    local playerGui = PlayerGui
    local player = LocalPlayer
    local Run = RunService
    local Input = userInputService
    local Replicated = ReplicatedStorage
    local Lighting = game:GetService("Lighting")
    local Http = game:GetService("HttpService")

    local config = {
        Speed = false, WalkSpeed = 32, Jump = false, JumpHeight = 12,
        InfiniteJump = false, Fly = false, FlySpeed = 45, Noclip = false,
        ESP = false, Boxes = true, Names = true, Health = true, Distance = true,
        PlayerFilter = "All", MaxDistance = 600, BallESP = false, HoopESP = false,
        Trajectory = false, Horizon = 1.5,
        Theme = "Noir",
        AlwaysRun = false, 
        NoStealCD = false, DribbleBoost = false, DribbleMultiplier = 1.35,
        BlockRange = false, BlockMultiplier = 1.3, NoCameraShake = false,
        StyleESP = false, ZoneESP = false, BallOwnerESP = false, InventoryHUD = false,
        ExtendedDunk = false, DunkMultiplier = 1.3, QuickRelease = false,
        ExtraPumpFakes = false, PumpCount = 3, ExtendedChain = false, ChainCount = 5,
        PassBoost = false, PassMultiplier = 1.35,
        AntiSlow = false,
        NoDynamicFOV = false, LowGraphics = false,
    }

    local connections, markers, snapshots = {}, {}, {}
    local alive, vertical = true, 0
    local flightTouches = {}
    local humanoid, root, character, flyAttachment, flyVelocity
    local renderName = "Courtside_" .. Http:GenerateGUID(false)
    local controllers, controllerState, controllerTask = {}, "disconnected", nil
    local sharedTables = {}
    local modifiedZone, modifiedZoneTables
    local tableChanges, savedAttributes = {}, {}
    local stolen = {}
    local stealNote, info, status = stolen, stolen, stolen
    local NIL = {}
    local extras

    local methodPatches = {}
    local function removeMethodPatch(key)
        local patch = methodPatches[key]
        if patch then
            if not table.isfrozen(patch.object) and rawget(patch.object, patch.method) == patch.wrapper then
                rawset(patch.object, patch.method, patch.originalRaw)
            end
            methodPatches[key] = nil
        end
    end
    local function installMethodPatch(key, object, method, factory)
        if type(object) ~= "table" or table.isfrozen(object) then removeMethodPatch(key); return false end
        local previous = methodPatches[key]
        if previous then
            if previous.object == object then
                return rawget(object, method) == previous.wrapper
            end
            removeMethodPatch(key)
        end
        local original = object[method]
        if type(original) ~= "function" then return false end
        local wrapper = factory(original)
        methodPatches[key] = {object = object, method = method, originalRaw = rawget(object, method), wrapper = wrapper}
        rawset(object, method, wrapper)
        return true
    end

    local function tableOverride(object, key, value)
        if type(object) ~= "table" or table.isfrozen(object) then return end
        tableChanges[object] = tableChanges[object] or {}
        if tableChanges[object][key] == nil then
            local original = rawget(object, key)
            tableChanges[object][key] = original == nil and NIL or original
        end
        object[key] = value
    end
    local function restoreTable(object, key)
        local changes = tableChanges[object]
        if changes and changes[key] ~= nil then
            local original = changes[key]
            if not table.isfrozen(object) then
                if original == NIL then object[key] = nil else object[key] = original end
            end
            changes[key] = nil
            if next(changes) == nil then tableChanges[object] = nil end
        end
    end
    local function restoreGameChanges()
        if extras then extras.reset() end
        removeMethodPatch("Dribble")
        removeMethodPatch("CameraShake")
        for object, changes in pairs(tableChanges) do
            for key, original in pairs(changes) do
                if not table.isfrozen(object) then
                    if original == NIL then object[key] = nil else object[key] = original end
                end
            end
        end
        table.clear(tableChanges)
        for name, original in pairs(savedAttributes) do
            if original == NIL then player:SetAttribute(name, nil) else player:SetAttribute(name, original) end
        end
        table.clear(savedAttributes)
        modifiedZone, modifiedZoneTables = nil, nil
    end
    local function connectControllers()
        if controllerTask or controllerState == "connected" then return end
        controllerState = "searching..."
        controllerTask = task.defer(function()
            if type(getgc) ~= "function" then
                controllerState = "getgc unavailable"
                controllerTask = nil
                return
            end
            local signatures = {
                BallController = {Dribble = "function", DribbleDB = "number"},
                DefenseController = {Steal = "function"},
                MovementController = {States = "table", WalkSpeed = "function"},
                AbilityController = {CDS = "table", BallService = "table"},
                Network = {CharValues = "table"},
                CameraController = {SetShiftlock = "function"},
            }
            local attempt = 0
            while alive do
                attempt += 1
                local ok, objects = pcall(getgc, true)
                if not ok or type(objects) ~= "table" then
                    controllerState = "getgc error"
                    controllerTask = nil
                    return
                end
                local count, visited = 0, 0
                local found = {}
                for _, object in pairs(objects) do
                    if not alive then return end
                    if type(object) == "table" and not table.isfrozen(object) then
                        local name = rawget(object, "Name")
                        local signature = type(name) == "string" and signatures[name]
                        if signature and not found[name] then
                            local matches = true
                            for key, expectedType in pairs(signature) do
                                if type(rawget(object, key)) ~= expectedType then matches = false; break end
                            end
                            if matches then
                                found[name] = object
                                if name ~= "CameraController" then count += 1 end
                            end
                        end
                        if type(rawget(object, "StealCooldowns")) == "table"
                            and type(rawget(object, "BlockDistBuffZones")) == "table"
                            and type(rawget(object, "ZoneDribblingSpeed")) == "table" then
                            sharedTables.Zones = object
                        end
                        local styles = rawget(object, "Styles")
                        if type(styles) == "table" and type(rawget(styles, "Sniper")) == "table"
                            and type(rawget(styles, "Lock")) == "table" then sharedTables.Styles = styles end
                    end
                    if count == 5 and sharedTables.Zones and sharedTables.Styles and found.CameraController then break end
                    visited += 1
                    if visited % 2000 == 0 then task.wait() end
                end
                objects = nil
                if not alive then return end
                if count == 5 then
                    controllers = found
                    controllerState = "connected"
                    if sharedTables.Zones and sharedTables.Styles and found.CameraController then break end
                else
                    controllerState = string.format("waiting for controllers %d/5", count)
                end
                task.wait(attempt < 5 and 2 or 10)
            end
            controllerTask = nil
        end)
    end
    local function connect(signal, callback)
        local c = signal:Connect(callback)
        table.insert(connections, c)
        return c
    end
    local function make(class, props, parent)
        local object = Instance.new(class)
        for k, v in pairs(props or {}) do object[k] = v end
        object.Parent = parent
        return object
    end
    local function override(object, property, value)
        if not object then return end
        snapshots[object] = snapshots[object] or {}
        if snapshots[object][property] == nil then snapshots[object][property] = object[property] end
        object[property] = value
    end
    local function restore(object, property)
        local saved = snapshots[object]
        if saved and saved[property] ~= nil then
            pcall(function() object[property] = saved[property] end)
            saved[property] = nil
            if next(saved) == nil then snapshots[object] = nil end
        end
    end
    local function restoreAll()
        for object, saved in pairs(snapshots) do
            for property, value in pairs(saved) do pcall(function() object[property] = value end) end
        end
        table.clear(snapshots)
    end
    local function stopFly()
        table.clear(flightTouches)
        vertical = 0
        if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
        if flyAttachment then flyAttachment:Destroy(); flyAttachment = nil end
        if humanoid then restore(humanoid, "AutoRotate") end
    end
    local function bindCharacter()
        local nextCharacter = player.Character
        local nextHumanoid = nextCharacter and nextCharacter:FindFirstChildOfClass("Humanoid")
        local nextRoot = nextCharacter and nextCharacter:FindFirstChild("HumanoidRootPart")
        if nextCharacter ~= character or nextHumanoid ~= humanoid or nextRoot ~= root then
            stopFly()
            for object, saved in pairs(snapshots) do
                if character and object:IsDescendantOf(character) then
                    for property, value in pairs(saved) do pcall(function() object[property] = value end) end
                    snapshots[object] = nil
                end
            end
            character, humanoid, root = nextCharacter, nextHumanoid, nextRoot
        end
    end

    local gui = make("ScreenGui", {Name = "Courtside_HUD", ResetOnSpawn = false,
        IgnoreGuiInset = true, DisplayOrder = 90, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, GuiParent)
    local palette = {Background = Color3.fromRGB(1,1,2), Surface = Color3.fromRGB(13,13,14),
        Text = Color3.fromRGB(248,248,248), Muted = Color3.fromRGB(125,125,132)}
    local accent = Color3.fromRGB(255,255,255)
    local function round(object, radius) make("UICorner", {CornerRadius = UDim.new(0, 0)}, object) end
    local function button(parent, text, size, position)
        return make("TextButton", {Text = text, Size = size, Position = position or UDim2.new(),
            BackgroundColor3 = palette.Surface, TextColor3 = palette.Text, BorderSizePixel = 0,
            Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true}, parent)
    end

    local overlay = make("Frame", {Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, gui)
    local inventory = make("TextLabel", {Name = "InventoryHUD", AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 52), Size = UDim2.fromOffset(290, 140),
        BackgroundColor3 = palette.Background, BackgroundTransparency = 0.15, BorderSizePixel = 0,
        TextColor3 = palette.Text, TextSize = 12, Font = Enum.Font.Gotham,
        TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, ZIndex = 3}, gui)
    round(inventory)
    make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, inventory)
    overlay.ZIndex = 0
    local function marker(key)
        if markers[key] then return markers[key] end
        local box = make("Frame", {BackgroundTransparency = 1, Visible = false}, overlay)
        local stroke = make("UIStroke", {Color = accent, Thickness = 1}, box)
        local text = make("TextLabel", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.fromOffset(200, 44), TextColor3 = Color3.fromRGB(248,248,248),
            TextWrapped = true, TextStrokeTransparency = 0.15, TextStrokeColor3 = Color3.fromRGB(0,0,0), TextYAlignment = Enum.TextYAlignment.Bottom, Font = Enum.Font.GothamMedium, TextSize = 10}, box)
        markers[key] = {box = box, stroke = stroke, text = text}
        return markers[key]
    end
    connect(Players.PlayerRemoving, function(other)
        if markers[other] then markers[other].box:Destroy(); markers[other] = nil end
    end)
    local dots = {}
    for i = 1, 30 do
        dots[i] = make("Frame", {Size = UDim2.fromOffset(4, 4), AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = accent, BorderSizePixel = 0, Visible = false}, overlay)
        round(dots[i], 2)
    end
    local up = button(gui, "UP", UDim2.fromOffset(58, 52), UDim2.new(1, -82, 0.5, -58))
    local down = button(gui, "DOWN", UDim2.fromOffset(58, 52), UDim2.new(1, -82, 0.5, 6))
    local function updateFlightTouches()
        local u, d = false, false
        for _, v in pairs(flightTouches) do
            if v == 1 then u = true else d = true end
        end
        vertical = (u and 1 or 0) - (d and 1 or 0)
    end
    for b, direction in pairs({[up] = 1, [down] = -1}) do
        b.Visible = false
        b.ZIndex = 20
        round(b, 12)
        connect(b.InputBegan, function(input)
            if config.Fly and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
                flightTouches[input] = direction
                updateFlightTouches()
            end
        end)
    end
    connect(Input.InputEnded, function(input)
        if flightTouches[input] then
            flightTouches[input] = nil
            updateFlightTouches()
        end
    end)
    connect(Input.WindowFocusReleased, function()
        table.clear(flightTouches)
        vertical = 0
        if flyVelocity then flyVelocity.VectorVelocity = Vector3.zero end
    end)
    connect(Input.JumpRequest, function()
        if config.InfiniteJump and not config.Fly and humanoid and humanoid.Health > 0 and not Input:GetFocusedTextBox() then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    local function ballPart()
        local ref = Replicated:FindFirstChild("Basketball")
        local part = ref and ref:IsA("ObjectValue") and ref.Value or workspace:FindFirstChild("Basketball")
        if part and part:IsA("BasePart") and part:IsDescendantOf(workspace) then return part end
        return nil
    end
    local function hoopPart(name)
        local folder = workspace:FindFirstChild("Hoops")
        local hoop = folder and folder:FindFirstChild(name)
        local part = hoop and hoop:FindFirstChild("Hoop")
        return part and part:IsA("BasePart") and part or nil
    end
    local function sameTeam(other)
        return player.Team ~= nil and not player.Neutral and not other.Neutral and player.Team == other.Team
    end
    local function passesFilter(other)
        return config.PlayerFilter == "All" or (config.PlayerFilter == "Team" and sameTeam(other))
            or (config.PlayerFilter == "Opponents" and not sameTeam(other))
    end
    local function playerValue(other, name)
        local value = other:FindFirstChild(name)
        return value and value:IsA("StringValue") and value.Value or "РІР‚вЂќ"
    end
    local function ballOwner()
        local controller = controllers.BallController
        if not controller or type(controller.GetPlayerPossessingBall) ~= "function" then return nil end
        local ok, owner = pcall(controller.GetPlayerPossessingBall, controller)
        if ok and typeof(owner) == "Instance" and owner:IsA("Player") and owner.Parent == Players then return owner end
        return nil
    end
    local function updateZoneModifiers()
        local zones = sharedTables.Zones
        local zoneObject = player:FindFirstChild("Zone")
        local zone = zoneObject and zoneObject:IsA("StringValue") and zoneObject.Value or nil
        if modifiedZone and (modifiedZone ~= zone or modifiedZoneTables ~= zones) then
            for _, name in ipairs({"StealCooldowns", "ZoneDribblingSpeed", "BlockDistBuffZones", "DunkDistBuffZones", "ZoneIncreasedShootingSpeed", "ZonePumpFakes", "ZoneDribbles", "ZoneIncreasedPassingSpeed"}) do
                local values = modifiedZoneTables and modifiedZoneTables[name]
                if type(values) == "table" then restoreTable(values, modifiedZone) end
            end
            modifiedZone, modifiedZoneTables = nil, nil
        end
        if not zones or not zone or zone == "" then
            stealNote.Text = config.NoStealCD and "No CD Steal: Zones table not found yet" or "No CD Steal disabled"
            return
        end
        modifiedZone, modifiedZoneTables = zone, zones
        local entries = {
            {"StealCooldowns", config.NoStealCD, 0},
            {"ZoneDribblingSpeed", config.DribbleBoost, config.DribbleMultiplier - 1},
            {"BlockDistBuffZones", config.BlockRange, config.BlockMultiplier - 1},
            {"DunkDistBuffZones", config.ExtendedDunk, config.DunkMultiplier - 1},
            {"ZoneIncreasedShootingSpeed", config.QuickRelease, true},
            {"ZonePumpFakes", config.ExtraPumpFakes, config.PumpCount},
            {"ZoneDribbles", config.ExtendedChain, config.ChainCount},
            {"ZoneIncreasedPassingSpeed", config.PassBoost, config.PassMultiplier},
        }
        for _, entry in ipairs(entries) do
            local values = zones[entry[1]]
            if type(values) == "table" then
                if entry[2] then tableOverride(values, zone, entry[3]) else restoreTable(values, zone) end
            end
        end
        if config.NoStealCD then
            local values = zones.StealCooldowns
            stealNote.Text = type(values) == "table" and values[zone] == 0
                and "Steal CD = 0; an active timer must finish first"
                or "No CD Steal: table cannot be modified"
        else stealNote.Text = "No CD Steal disabled" end
    end
    local dribblePatchStatus = "OFF"
    local function updateControllers(dt)
        updateZoneModifiers()
        local cameraController = controllers.CameraController
        local shaker = cameraController and rawget(cameraController, "CamShake")
        if config.NoCameraShake then
            installMethodPatch("CameraShake", shaker, "Update", function(original)
                return function(self, ...)
                    local result = original(self, ...)
                    if alive and config.NoCameraShake then return CFrame.new() end
                    return result
                end
            end)
        else removeMethodPatch("CameraShake") end
        local movement, ballController, ability = controllers.MovementController, controllers.BallController, controllers.AbilityController
        if movement then
            if config.AlwaysRun then tableOverride(movement, "AlwaysRun", true) else restoreTable(movement, "AlwaysRun") end
        end
        if ability and type(ability.CDS) == "table" then
            for i = 1, 4 do
                restoreTable(ability.CDS, i)
            end
        end
    end
    extras = (function()
        local state = {nextAwaken = 0,
            threats = {}, watched = {}, animKinds = {}, visualSaved = {},
            flightUntil = 0, flightId = 0, blockedId = -1}
        local api = {}
        local function opponent(other)
            return other and other ~= player and other.Team and other.Team.Name ~= "Visitor"
                and not other.Neutral and not sameTeam(other)
        end
        local assets = Replicated:FindFirstChild("Assets")
        local animations = assets and assets:FindFirstChild("Animations")
        if animations then
            for _, a in ipairs(animations:GetDescendants()) do
                if a:IsA("Animation") then
                    local path = a:GetFullName()
                    local kind = a.Name:match("^Steal") and "steal"
                        or ((path:find(".Shots.", 1, true) or path:find(".Dunks.", 1, true)
                            or path:find(".Passes.", 1, true)) and not a.Name:find("PumpFake")
                            and not a.Name:find("Idle") and not a.Name:find("CallPass") and "release")
                    if kind then state.animKinds[a.AnimationId:match("%d+") or a.AnimationId] = kind end
                end
            end
        end
        local function watch(other)
            local c = other.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local animator = h and h:FindFirstChildOfClass("Animator")
            local previous = state.watched[other]
            if previous and previous.animator == animator then return end
            if previous then previous.connection:Disconnect(); state.watched[other] = nil end
            if other == player or not animator then return end
            local connection = animator.AnimationPlayed:Connect(function(track)
                if not alive or not opponent(other) or not track.Animation then return end
                local kind = state.animKinds[track.Animation.AnimationId:match("%d+") or ""]
                if kind == "steal" then
                    state.threats[other] = os.clock() + 0.55
                elseif kind == "release" and ballOwner() == other then
                    state.releaseOwner = other; state.releaseUntil = os.clock() + 1.2
                end
            end)
            state.watched[other] = {animator = animator, connection = connection}
        end
        local function graphicsProperty(o, k, v)
            local saved = state.visualSaved[o]
            if saved and saved[k] ~= nil then return end
            local ok, old = pcall(function()
                local old = o[k]
                o[k] = v
                return old
            end)
            if not ok then return end
            if not saved then saved = {}; state.visualSaved[o] = saved end
            saved[k] = old
        end
        local function graphicsObject(o)
            if o:IsA("BasePart") then graphicsProperty(o, "CastShadow", false) end
            if o:IsA("Decal") or o:IsA("Texture") then graphicsProperty(o, "Transparency", 1)
            elseif o:IsA("MeshPart") then graphicsProperty(o, "TextureID", "")
            elseif o:IsA("SpecialMesh") then graphicsProperty(o, "TextureId", "") end
        end
        local function restoreGraphics()
            for o, saved in pairs(state.visualSaved) do
                for k, v in pairs(saved) do pcall(function() o[k] = v end) end
            end
            table.clear(state.visualSaved)
        end
        connect(workspace.DescendantAdded, function(o) if config.LowGraphics then graphicsObject(o) end end)
        connect(Lighting.DescendantAdded, function(o) if config.LowGraphics then graphicsObject(o) end end)
        function api.reset()
            restoreGraphics(); state.low = false
            if controllers.MovementController then restoreTable(controllers.MovementController.ExtraBoosts, "CourtsideAntiSlow") end
            state.flightUntil = 0
            state.fixedFOV = nil
            for _, item in pairs(state.watched) do item.connection:Disconnect() end
            table.clear(state.watched)
            table.clear(state.threats)
            state.releaseOwner, state.owner, state.lastOwner = nil, nil, nil
            state.releaseUntil = 0
        end
        function api.update(dt)
            local now = os.clock()
            local ballController, movement = controllers.BallController, controllers.MovementController
            local network = controllers.Network
            local values = network and network.CharValues
            if state.low ~= config.LowGraphics then
                state.low = config.LowGraphics
                if state.low then
                    for _, o in ipairs(workspace:GetDescendants()) do graphicsObject(o) end
                    for _, o in ipairs(Lighting:GetDescendants()) do graphicsObject(o) end
                else restoreGraphics() end
            end
            if movement and type(movement.ExtraBoosts) == "table" then
                local amount = 0
                if config.AntiSlow and type(values) == "table" then
                    local serverNow = workspace:GetServerTimeNow()
                    if values.Defense then amount += 0.25 end
                    if values.BeingSpotted then amount += 3 end
                    for _, name in ipairs({"VampiricSpeedDrain", "TechnicalSlow"}) do
                        local v = player:GetAttribute(name)
                        if type(v) == "number" and v > serverNow then amount += 4 end
                    end
                    local fear = player:GetAttribute("FearSlow")
                    if type(fear) == "number" then amount += 4 * math.max(0, fear) end
                    local soul = player:GetAttribute("SoulStringsSlow")
                    if type(soul) == "number" and soul > serverNow then
                        local slow = soul - 10 + 3.3833333333333333 > serverNow and 8 or 4
                        amount += slow * ((movement.States or {}).Running and 2 or 1)
                    end
                    tableOverride(movement.ExtraBoosts, "CourtsideAntiSlow", amount)
                else restoreTable(movement.ExtraBoosts, "CourtsideAntiSlow") end
            end
        end
        function api.camera(dt, camera)
            if config.NoDynamicFOV and not config.CustomFOV then
                if not state.fixedFOV then state.fixedFOV = camera.FieldOfView end
                override(camera, "FieldOfView", state.fixedFOV)
            else state.fixedFOV = nil end
        end
        return api
    end)()

    local function markPoint(key, part, name, camera)
        if not part then return end
        local distance = (camera.CFrame.Position - part.Position).Magnitude
        if distance > config.MaxDistance then return end
        local p, visible = camera:WorldToViewportPoint(part.Position)
        if not visible then return end
        local m = marker(key)
        m.box.Visible = true; m.box.Size = UDim2.fromOffset(8, 8)
        m.box.Position = UDim2.fromOffset(p.X - 4, p.Y - 4)
        m.stroke.Enabled = true; m.stroke.Color = accent
        m.text.Text = name .. (config.Distance and string.format(" Р’В· %.0f studs", distance) or "")
    end
    local function markPlayer(other, camera)
        local model = other.Character
        local h = model and model:FindFirstChildOfClass("Humanoid")
        local r = model and model:FindFirstChild("HumanoidRootPart")
        if not r or not h or h.Health <= 0 or not passesFilter(other) then return end
        local distance = (camera.CFrame.Position - r.Position).Magnitude
        if distance > config.MaxDistance then return end
        local cf, size = model:GetBoundingBox()
        local minimum, maximum = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
        for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
            local p = camera:WorldToViewportPoint(cf * (size * Vector3.new(x, y, z) * 0.5))
            if p.Z <= 0 then return end
            minimum = Vector2.new(math.min(minimum.X, p.X), math.min(minimum.Y, p.Y))
            maximum = Vector2.new(math.max(maximum.X, p.X), math.max(maximum.Y, p.Y))
        end end end
        if maximum.X < 0 or maximum.Y < 0 or minimum.X > camera.ViewportSize.X or minimum.Y > camera.ViewportSize.Y then return end
        local m = marker(other)
        m.box.Visible = true; m.box.Position = UDim2.fromOffset(minimum.X, minimum.Y)
        m.box.Size = UDim2.fromOffset(maximum.X - minimum.X, maximum.Y - minimum.Y)
        m.stroke.Enabled = config.Boxes; m.stroke.Color = sameTeam(other) and Color3.fromRGB(94, 220, 184) or accent
        local lines = {}
        if config.Names then table.insert(lines, other.DisplayName) end
        if config.Health then table.insert(lines, string.format("HP %.0f / %.0f", h.Health, h.MaxHealth)) end
        if config.Distance then table.insert(lines, string.format("%.0f studs", distance)) end
        if config.StyleESP then table.insert(lines, "Style: " .. playerValue(other, "Style")) end
        if config.ZoneESP then table.insert(lines, "Zone: " .. playerValue(other, "Zone")) end
        m.text.Text = table.concat(lines, " Р’В· ")
    end

    local function csToggle(id, key, tab, title, description)
        local frame = tab:AddToggle(id, {
            Title = title,
            Description = description,
            Default = config[key] == true,
            Callback = function(Value) config[key] = Value end,
        })
        return frame
    end

    local function csSlider(id, key, tab, title, description, minimum, maximum, step, rounding)
        tab:AddSlider(id, {
            Title = title,
            Description = description,
            Default = config[key],
            Min = minimum,
            Max = maximum,
            Step = step,
            Rounding = rounding,
            Callback = function(Value) config[key] = Value end,
        })
    end

    Tabs.Movement:AddSection("Courtside Movement")
    csToggle("CS_Speed", "Speed", Tabs.Movement, "Speed", "Increases walk speed")
    csSlider("CS_WalkSpeed", "WalkSpeed", Tabs.Movement, "Walk Speed", "Walk speed value", 4, 100, 1, 1)
    csToggle("CS_Jump", "Jump", Tabs.Movement, "Jump", "Increases jump power")
    csSlider("CS_JumpHeight", "JumpHeight", Tabs.Movement, "Jump Height", "Jump height in studs", 2, 40, 1, 1)
    csToggle("CS_InfiniteJump", "InfiniteJump", Tabs.Movement, "Infinite Jump", "Jump while in the air")
    csToggle("CS_Fly", "Fly", Tabs.Movement, "Fly", "Mobile: joystick + UP / DOWN. PC: WASD + Space / Ctrl")
    csSlider("CS_FlySpeed", "FlySpeed", Tabs.Movement, "Fly Speed", "Fly speed value", 5, 120, 1, 1)
    csToggle("CS_Noclip", "Noclip", Tabs.Movement, "Noclip", "Walk through obstacles")

    Tabs.ESP:AddSection("Players")
    csToggle("CS_ESP", "ESP", Tabs.ESP, "ESP", "Enable player ESP")
    csToggle("CS_Boxes", "Boxes", Tabs.ESP, "Boxes", "Draw player boxes")
    csToggle("CS_Names", "Names", Tabs.ESP, "Names", "Show player names")
    csToggle("CS_Health", "Health", Tabs.ESP, "Health", "Show player health")
    csToggle("CS_StyleESP", "StyleESP", Tabs.ESP, "Player Style", "Show each player style")
    csToggle("CS_ZoneESP", "ZoneESP", Tabs.ESP, "Player Zone", "Show each player zone")
    csToggle("CS_Distance", "Distance", Tabs.ESP, "Distance", "Show distance values")
    local playerFilterDd = Tabs.ESP:AddDropdown("CS_PlayerFilter", {
        Title = "Players Filter",
        Default = "All",
        Values = {"All", "Opponents", "Team"},
        Callback = function(Value) config.PlayerFilter = Value end,
    })
    csSlider("CS_MaxDistance", "MaxDistance", Tabs.ESP, "Max Distance", "ESP range in studs", 50, 1500, 10, 1)
    Tabs.ESP:AddSection("Ball & Hoops")
    csToggle("CS_BallESP", "BallESP", Tabs.ESP, "Ball Marker", "Mark the ball")
    csToggle("CS_BallOwnerESP", "BallOwnerESP", Tabs.ESP, "Ball Owner Marker", "Mark the ball owner")
    csToggle("CS_HoopESP", "HoopESP", Tabs.ESP, "Hoops Markers", "Mark the hoops")
    csToggle("CS_Trajectory", "Trajectory", Tabs.ESP, "Ball Trajectory", "Show predicted ball path")
    csSlider("CS_Horizon", "Horizon", Tabs.ESP, "Trajectory Horizon", "Prediction horizon in seconds", 0.25, 3, 0.05, 2)

    Tabs.Zone:AddSection("Game Controllers")
    csToggle("CS_NoStealCD", "NoStealCD", Tabs.Zone, "No CD Steal (Visual Only)", "Changes the local steal cooldown")
    csToggle("CS_DribbleBoost", "DribbleBoost", Tabs.Zone, "Zone Dribble Boost", "Faster dribbling inside the zone")
    csSlider("CS_DribbleMultiplier", "DribbleMultiplier", Tabs.Zone, "Dribble Multiplier", "Dribble speed multiplier", 1, 2.5, 0.05, 2)
    csToggle("CS_BlockRange", "BlockRange", Tabs.Zone, "Zone Block Range", "Larger block range inside the zone")
    csSlider("CS_BlockMultiplier", "BlockMultiplier", Tabs.Zone, "Block Multiplier", "Block range multiplier", 1, 2, 0.05, 2)
    csToggle("CS_AlwaysRun", "AlwaysRun", Tabs.Zone, "Always Run", "Keep sprinting all the time")
    Tabs.Zone:AddSection("Zone Abilities")
    csToggle("CS_ExtendedDunk", "ExtendedDunk", Tabs.Zone, "Extended Dunk", "Longer dunk distance inside the zone")
    csSlider("CS_DunkMultiplier", "DunkMultiplier", Tabs.Zone, "Dunk Distance x", "Dunk distance multiplier", 1, 2, 0.05, 2)
    csToggle("CS_QuickRelease", "QuickRelease", Tabs.Zone, "Quick Release", "Faster shooting inside the zone")
    csToggle("CS_ExtraPumpFakes", "ExtraPumpFakes", Tabs.Zone, "Extra Pump Fakes", "More pump fakes inside the zone")
    csSlider("CS_PumpCount", "PumpCount", Tabs.Zone, "Pump Fakes Count", "Number of pump fakes", 1, 6, 1, 1)
    csToggle("CS_ExtendedChain", "ExtendedChain", Tabs.Zone, "Extended Dribble Chain", "Longer dribble chains inside the zone")
    csSlider("CS_ChainCount", "ChainCount", Tabs.Zone, "Dribbles In Series", "Dribbles per series", 3, 10, 1, 1)
    csToggle("CS_PassBoost", "PassBoost", Tabs.Zone, "Pass Boost", "Faster passes inside the zone")
    csSlider("CS_PassMultiplier", "PassMultiplier", Tabs.Zone, "Pass Speed x", "Pass speed multiplier", 1, 2, 0.05, 2)

    Tabs.Misc:AddSection("Movement Protection")
    csToggle("CS_AntiSlow", "AntiSlow", Tabs.Misc, "Anti Slow", "Compensate local slow effects")
    Tabs.Misc:AddSection("HUD")
    csToggle("CS_InventoryHUD", "InventoryHUD", Tabs.Misc, "Inventory HUD", "Show style, spins, pity and cooldowns")

    Tabs.Visuals:AddSection("Effects")
    csToggle("CS_NoCameraShake", "NoCameraShake", Tabs.Visuals, "No Camera Shake", "Disable camera shake")
    csToggle("CS_NoDynamicFOV", "NoDynamicFOV", Tabs.Visuals, "No Dynamic FOV", "Disable dynamic field of view")
    csToggle("CS_LowGraphics", "LowGraphics", Tabs.Visuals, "Low Graphics", "Reduce textures and shadows while preserving color effects")

    connect(Run.PreSimulation, function()
        if not alive then return end
        bindCharacter()
        if not humanoid or not root or humanoid.Health <= 0 then stopFly(); return end
        if config.Speed then override(humanoid, "WalkSpeed", config.WalkSpeed) else restore(humanoid, "WalkSpeed") end
        if config.Jump then
            if humanoid.UseJumpPower then
                restore(humanoid, "JumpHeight")
                override(humanoid, "JumpPower", math.sqrt(2 * workspace.Gravity * config.JumpHeight))
            else restore(humanoid, "JumpPower"); override(humanoid, "JumpHeight", config.JumpHeight) end
        else restore(humanoid, "JumpPower"); restore(humanoid, "JumpHeight") end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if config.Noclip then override(part, "CanCollide", false) else restore(part, "CanCollide") end
            end
        end
        if config.Fly then
            if not flyVelocity then
                flyAttachment = make("Attachment", {Name = "CourtsideFlight"}, root)
                flyVelocity = make("LinearVelocity", {Name = "CourtsideVelocity", Attachment0 = flyAttachment,
                    RelativeTo = Enum.ActuatorRelativeTo.World, ForceLimitsEnabled = false, VectorVelocity = Vector3.zero}, root)
            end
            override(humanoid, "AutoRotate", false)
            local movement = humanoid.MoveDirection * Vector3.new(1, 0, 1)
            local camera = workspace.CurrentCamera
            local y = vertical
            if Input:GetFocusedTextBox() then movement = Vector3.zero; y = 0
            elseif Input:GetLastInputType() ~= Enum.UserInputType.Touch and Input.KeyboardEnabled and camera then
                local x = (Input:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (Input:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
                local z = (Input:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (Input:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
                movement = camera.CFrame.RightVector * x + camera.CFrame.LookVector * z
            end
            if not Input:GetFocusedTextBox() then
                y += (Input:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) - (Input:IsKeyDown(Enum.KeyCode.LeftControl) and 1 or 0)
            end
            movement += Vector3.new(0, y, 0)
            if movement.Magnitude > 1 then movement = movement.Unit end
            flyVelocity.VectorVelocity = movement * config.FlySpeed
        else stopFly() end
    end)

    local lastCamera, theme, statusClock = nil, nil, 0
    Run:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 10, function(dt)
        if not alive then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        updateControllers(dt)
        extras.update(dt)
        if root and humanoid and humanoid.Health > 0 then
            if not config.Fly then restore(humanoid, "AutoRotate") end
            if config.Speed then override(humanoid, "WalkSpeed", config.WalkSpeed) end
            if config.Jump then
                if humanoid.UseJumpPower then override(humanoid, "JumpPower", math.sqrt(2 * workspace.Gravity * config.JumpHeight))
                else override(humanoid, "JumpHeight", config.JumpHeight) end
            end
        end
        if camera ~= lastCamera then
            if lastCamera then restore(lastCamera, "FieldOfView") end
            lastCamera = camera
        end
        local viewport = camera.ViewportSize
        if theme ~= NexusUI.ThemeName then
            theme = NexusUI.ThemeName
            accent = ACCENT
            inventory.BackgroundColor3 = COLOR_WINDOW
            inventory.TextColor3 = COLOR_TEXT
            up.BackgroundColor3 = COLOR_CONTROL
            up.TextColor3 = COLOR_TEXT
            down.BackgroundColor3 = COLOR_CONTROL
            down.TextColor3 = COLOR_TEXT
        end
        up.Visible = config.Fly and Input.TouchEnabled and humanoid ~= nil and root ~= nil and humanoid.Health > 0
        down.Visible = up.Visible
        local ball = ballPart()
        extras.camera(dt, camera)
        for _, m in pairs(markers) do m.box.Visible = false end
        if config.ESP then for _, other in ipairs(Players:GetPlayers()) do if other ~= player then markPlayer(other, camera) end end end
        if config.BallESP then markPoint("Ball", ball, "BALL", camera) end
        if config.BallOwnerESP then
            local owner = ballOwner()
            local part = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
            markPoint("BallOwner", part, owner and ("BALL OWNER: " .. owner.DisplayName) or "", camera)
        end
        if config.HoopESP then
            markPoint("Home", hoopPart("Home"), "HOME HOOP", camera)
            markPoint("Away", hoopPart("Away"), "AWAY HOOP", camera)
        end
        for i, dot in ipairs(dots) do
            dot.Visible = false
            if config.Trajectory and ball and ball.AssemblyLinearVelocity.Magnitude > 0.5 then
                local t = i / #dots * config.Horizon
                local position = ball.Position + ball.AssemblyLinearVelocity * t + Vector3.new(0, -workspace.Gravity * t * t / 2, 0)
                local p, visible = camera:WorldToViewportPoint(position)
                dot.Visible = visible; dot.Position = UDim2.fromOffset(p.X, p.Y); dot.BackgroundColor3 = accent
            end
        end
        statusClock += dt
        inventory.Visible = config.InventoryHUD
        if statusClock >= 0.5 then
            statusClock = 0
            status.Text = string.format("GUI: %s РІР‚Сћ Knit: %s\nDribble: %s", "Nexus", controllerState, dribblePatchStatus)
            if config.InventoryHUD then
                local network = controllers.Network
                local data = network and network.Player
                local function count(key)
                    local value = type(data) == "table" and data[key]
                    return type(value) == "number" and tostring(math.max(0, math.floor(value))) or "РІР‚вЂќ"
                end
                local ability = controllers.AbilityController
                local cds = ability and ability.CDS
                local cooldowns = {}
                for i = 1, 4 do
                    local value = type(cds) == "table" and cds[i]
                    cooldowns[i] = type(value) == "number" and string.format("%.1f", math.max(0, value - tick())) or "РІР‚вЂќ"
                end
                inventory.Text = string.format("Style: %s\nZone: %s\nSpins: %s  |  Lucky: %s\nPity: %s/50  |  Lucky pity: %s/75\nAbility CD: %s",
                    playerValue(player, "Style"), playerValue(player, "Zone"), count("Spins"), count("LuckySpins"),
                    count("StyleSpinsDone"), count("LuckyStyleSpinsDone"), table.concat(cooldowns, " / "))
            end
        end
    end)

    local function cleanup()
        if not alive then return end
        alive = false
        Run:UnbindFromRenderStep(renderName)
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        if controllerTask then pcall(task.cancel, controllerTask); controllerTask = nil end
        stopFly()
        restoreAll()
        restoreGameChanges()
        pcall(function() gui:Destroy() end)
    end
    RegisterUnloadCallback(cleanup)
    gui.Destroying:Connect(cleanup)
    connectControllers()
end


do
    local state = {Alive = true, AutoPlay = false, AutoPass = false, Team = "Auto", Mode = "Random Teammate", Speed = 240, LastPass = -10, LastJoin = -10, Epoch = 0}
    local controllers, links, names = {}, {}, {}
    local knit, teamService, ballService, patch, flight, pending, targetDropdown
    local discovering, passing, joining, elapsed, nextDiscovery = false, false, false, 0, 0
    local random = Random.new()
    local function notify(message) NexusUI:Notify({Title = "New", Content = tostring(message), Duration = 5}) end
    local function disconnect(connection) if connection then connection:Disconnect() end end
    local function active() return state.Alive and not ScriptUnloaded end
    local function playing() return LocalPlayer.Team and (LocalPlayer.Team.Name == "Home" or LocalPlayer.Team.Name == "Away") end
    local function owner()
        local c = controllers.BallController
        if c and type(c.GetPlayerPossessingBall) == "function" then local ok, result = pcall(c.GetPlayerPossessingBall, c); if ok then return result end end
    end
    local function ownsPhysics()
        local c = controllers.BallController
        if not c or type(c.LocalPlayerIsBallNetworkOwner) ~= "function" then return false end
        local ok, result = pcall(c.LocalPlayerIsBallNetworkOwner, c)
        return ok and result == true
    end
    local function clearFlight()
        local previous = flight
        flight = nil
        if not previous then return end
        disconnect(previous.Connection)
        if previous.Ball.Parent and owner() == nil and ownsPhysics() then
            for actuator, record in pairs(previous.Actuators) do
                if actuator.Parent == previous.Ball and actuator.VectorVelocity == record.Applied then actuator.VectorVelocity = record.Native end
            end
            if previous.Applied and previous.Ball.AssemblyLinearVelocity == previous.Applied then previous.Ball.AssemblyLinearVelocity = previous.Native end
        end
    end
    local function resetPass() state.Epoch = state.Epoch + 1; pending = nil; clearFlight() end
    local function validTarget(player)
        if not player or player == LocalPlayer or player.Parent ~= Players or not playing() or player.Team ~= LocalPlayer.Team then return end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local mine = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and humanoid and humanoid.Health > 0 and mine and (root.Position - mine.Position).Magnitude <= 180 then return root end
    end
    local function startFlight(request)
        clearFlight()
        local ball = request.Ball
        local current = {Ball = ball, Request = request, Actuators = {}, Started = os.clock()}
        flight = current
        local function add(object)
            if object:IsA("LinearVelocity") and not request.Existing[object] and object.Attachment0 == ball:FindFirstChild("Root") then current.Actuators[object] = {Native = object.VectorVelocity} end
        end
        for _, object in ipairs(ball:GetChildren()) do add(object) end
        current.Connection = ball.ChildAdded:Connect(add)
    end
    local function updateFlight()
        local current = flight
        if not current then return end
        local request, ball = current.Request, current.Ball
        local root, holder = validTarget(request.Player), owner()
        if not active() or not state.AutoPass or request.Epoch ~= state.Epoch or LocalPlayer.Character ~= request.Character
            or not root or root ~= request.Root or GetCurrentBall() ~= ball or not ball.Parent or ball.Anchored
            or os.clock() - current.Started > 3 or not ownsPhysics() or (root.Position - ball.Position).Magnitude <= 3 then clearFlight(); return end
        if holder then
            if holder == LocalPlayer and os.clock() - current.Started < 0.3 then return end
            clearFlight(); return
        end
        local velocity = ball.AssemblyLinearVelocity
        for actuator, record in pairs(current.Actuators) do
            if actuator.Parent ~= ball then current.Actuators[actuator] = nil
            else
                local native = actuator.VectorVelocity
                if native ~= record.Applied then record.Native = native end
                if record.Native.Magnitude > 0.01 then velocity = record.Native.Unit * state.Speed; record.Applied = velocity; actuator.VectorVelocity = velocity end
            end
        end
        if velocity.Magnitude > 0.01 then
            if ball.AssemblyLinearVelocity ~= current.Applied then current.Native = ball.AssemblyLinearVelocity end
            current.Applied = velocity.Unit * state.Speed
            ball.AssemblyLinearVelocity = current.Applied
        end
    end
    local function removePatch()
        if patch and rawget(patch.Object, "Pass") == patch.Wrapper then rawset(patch.Object, "Pass", patch.Original) end
        patch = nil
    end
    local function installPatch()
        local object = controllers.PassController
        if patch and patch.Object == object then return true end
        removePatch()
        if type(object) ~= "table" or table.isfrozen(object) or type(object.Pass) ~= "function" then return false end
        local original, raw = object.Pass, rawget(object, "Pass")
        local wrapper = function(self, target, ...)
            local request = pending
            local eligible = active() and state.AutoPass and request and os.clock() <= request.Expires
                and request.Epoch == state.Epoch and request.Character == LocalPlayer.Character and request.Root == target
                and request.Ball == GetCurrentBall() and validTarget(request.Player) == target
            if eligible then
                local ball = controllers.BallController
                local ok, last = pcall(ball.GetLastPlayerToPossessBall, ball)
                eligible = ok and last == LocalPlayer
            end
            if eligible then
                request.Existing = {}
                for _, object in ipairs(request.Ball:GetChildren()) do if object:IsA("LinearVelocity") then request.Existing[object] = true end end
            end
            local result = table.pack(original(self, target, ...))
            if eligible and active() and state.AutoPass and request.Epoch == state.Epoch and os.clock() <= request.Expires
                and request.Character == LocalPlayer.Character and request.Ball == GetCurrentBall() and validTarget(request.Player) == target and ownsPhysics() then pending = nil; startFlight(request) end
            return table.unpack(result, 1, result.n)
        end
        rawset(object, "Pass", wrapper)
        patch = {Object = object, Original = raw, Wrapper = wrapper}
        return true
    end
    local function discover()
        if discovering or os.clock() < nextDiscovery or not active() then return end
        discovering, nextDiscovery = true, os.clock() + 3
        task.spawn(function()
            local ok, failure = pcall(function()
                if not knit then
                    local packages = ReplicatedStorage:FindFirstChild("Packages")
                    local module = packages and packages:FindFirstChild("Knit")
                    if module then local loaded, result = pcall(require, module); if loaded then knit = result end end
                end
                if knit then
                    for _, name in ipairs({"BallController", "PassController", "Network"}) do local found, result = pcall(knit.GetController, name); if found then controllers[name] = result end end
                    local found, result = pcall(knit.GetService, "BallService"); if found then ballService = result end
                    found, result = pcall(knit.GetService, "TeamService"); if found then teamService = result end
                end
                if type(getgc) == "function" and (not controllers.Network or not controllers.Network.CharValues or not controllers.PassController) then
                    for index, object in pairs(getgc(true)) do
                        if not active() then break end
                        if type(object) == "table" then
                            local name = rawget(object, "Name")
                            if name == "Network" and type(rawget(object, "CharValues")) == "table" or name == "BallController" and type(rawget(object, "DribbleDB")) == "number"
                                or name == "PassController" and type(rawget(object, "Pass")) == "function" then controllers[name] = object end
                            if not ballService and type(rawget(object, "BallService")) == "table" then ballService = rawget(object, "BallService") end
                        end
                        if type(index) == "number" and index % 400 == 0 then task.wait() end
                    end
                end
            end)
            discovering = false
            if active() and not ok and not state.DiscoveryError then state.DiscoveryError = true; notify(failure) end
        end)
    end
    local function joinMatch()
        if joining or not teamService or os.clock() - state.LastJoin < 2 then return end
        local slots = ReplicatedStorage:FindFirstChild("Teams")
        if not slots then return end
        for _, folder in ipairs(slots:GetChildren()) do for _, slot in ipairs(folder:GetChildren()) do if slot:IsA("ObjectValue") and slot.Value == LocalPlayer then return end end end
        local network = controllers.Network
        local mode = network and network.Gamemode or "Normal"
        local match = type(mode) == "string" and mode:sub(1, 6) == "Match-"
        local choices = state.Team == "Auto" and {"Home", "Away"} or {state.Team}
        if match and playing() then choices = {LocalPlayer.Team.Name} end
        if state.Team == "Auto" and not match then
            local teams = game:GetService("Teams")
            local home, away = teams:FindFirstChild("Home"), teams:FindFirstChild("Away")
            if home and away and #home:GetPlayers() > #away:GetPlayers() then choices = {"Away", "Home"} end
        end
        local pick, side, position = PlayerGui:FindFirstChild("PickTeam")
        for _, name in ipairs(choices) do
            local folder = slots:FindFirstChild(name)
            local panel = pick and pick:FindFirstChild(name)
            local positions = panel and (panel:FindFirstChild(mode) or panel:FindFirstChild("Normal"))
            if folder and (not panel or panel.Visible) then
                for _, slot in ipairs(folder:GetChildren()) do
                    local button = positions and positions:FindFirstChild(slot.Name)
                    if slot:IsA("ObjectValue") and slot.Value == nil and (not positions or button and button.Visible) then side, position = name, slot.Name; break end
                end
            end
            if side then break end
        end
        if not side then return end
        joining, state.LastJoin = true, os.clock()
        task.spawn(function()
            local ok, result = pcall(function() if active() and state.AutoPlay then return teamService:Select(side, position) end end)
            joining = false
            if active() and state.AutoPlay and ok and result and pick and pick.Parent then pick.Enabled = false end
            if active() and not ok and not state.JoinError then state.JoinError = true; notify(result) end
        end)
    end
    local function passBall()
        local now = os.clock()
        if passing or flight or pending and now <= pending.Expires or now - state.LastPass < 1.1 then return end
        pending = nil
        local ball, network = controllers.BallController, controllers.Network
        if not playing() or not ball or not network or not network.CharValues or network.CharValues.HasBall ~= true
            or owner() ~= LocalPlayer or not ballService or not ballService.Pass or not installPatch() then return end
        local can, ready = pcall(ball.CanPass, ball)
        if not can or not ready then return end
        local available = {}
        for _, player in ipairs(Players:GetPlayers()) do if validTarget(player) and (state.Mode ~= "Specific User" or player.UserId == state.TargetId) then available[#available + 1] = player end end
        if #available == 0 then return end
        local player = available[random:NextInteger(1, #available)]
        local root, currentBall = validTarget(player), GetCurrentBall()
        if not root or not currentBall then return end
        local request = {Player = player, Root = root, Ball = currentBall, Character = LocalPlayer.Character, Epoch = state.Epoch, Expires = now + 2.5}
        pending, passing, state.LastPass = request, true, now
        task.spawn(function()
            local ok, failure = pcall(function()
                if not active() or not state.AutoPass or request.Epoch ~= state.Epoch or not validTarget(player) or owner() ~= LocalPlayer then return end
                controllers.PassController:Anim(player.Character)
                ballService.Pass:Fire(player.Character)
            end)
            passing = false
            if not ok then
                if pending == request then pending = nil end
                if active() and not state.PassError then state.PassError = true; notify(failure) end
            end
        end)
    end
    local function refreshPlayers()
        local values, map, selected = {"Select a player"}, {}, "Select a player"
        local players = Players:GetPlayers()
        table.sort(players, function(a, b) return a.Name:lower() < b.Name:lower() end)
        for _, player in ipairs(players) do
            if player ~= LocalPlayer then
                local label = player.DisplayName .. " (@" .. player.Name .. ")"
                values[#values + 1], map[label] = label, player.UserId
                if player.UserId == state.TargetId then selected = label end
            end
        end
        names = map
        targetDropdown:SetValues(values)
        targetDropdown:SetValue(selected)
    end
    Tabs.EventsFarm:AddSection("Auto Play")
    Tabs.EventsFarm:AddDropdown("NewJoinTeam", {Title = "Team", Values = {"Auto", "Home", "Away"}, Default = "Auto", Callback = function(value) state.Team = value end})
    Tabs.EventsFarm:AddToggle("NewAutoPlay", {Title = "Auto Play", Description = "Automatically joins an available position on the selected team", Default = false, Callback = function(value)
        state.AutoPlay = value
        if value then state.LastJoin = -10; discover() end
    end})
    Tabs.EventsFarm:AddSection("Auto Pass")
    Tabs.EventsFarm:AddDropdown("NewPassMode", {Title = "Pass To", Values = {"Random Teammate", "Specific User"}, Default = "Random Teammate", Callback = function(value) state.Mode = value; resetPass() end})
    targetDropdown = Tabs.EventsFarm:AddDropdown("NewPassTarget", {Title = "Specific User", Values = {"Select a player"}, Default = "Select a player", Callback = function(value)
        local id = names[value]
        if id ~= state.TargetId then state.TargetId = id; resetPass() end
    end})
    Tabs.EventsFarm:AddSlider("NewPassSpeed", {Title = "Pass Ball Speed", Description = "Ball speed in studs per second", Min = 80, Max = 500, Step = 5, Rounding = 0, Default = 240, Callback = function(value) state.Speed = value end})
    Tabs.EventsFarm:AddToggle("NewAutoPass", {Title = "Auto Pass", Description = "Automatically passes to the selected user or a random available teammate", Default = false, Callback = function(value)
        state.AutoPass = value; resetPass()
        if value then
            local previous = NexusUI.Options.AutoPass
            if previous and previous.Value then previous:SetValue(false) end
            discover()
        else removePatch() end
    end})
    refreshPlayers()
    links[#links + 1] = Players.PlayerAdded:Connect(function() task.defer(function() if active() then refreshPlayers() end end) end)
    links[#links + 1] = Players.PlayerRemoving:Connect(function(player)
        if state.TargetId == player.UserId then state.TargetId = nil; resetPass() end
        task.defer(function() if active() then refreshPlayers() end end)
    end)
    links[#links + 1] = LocalPlayer.CharacterRemoving:Connect(resetPass)
    links[#links + 1] = LocalPlayer:GetPropertyChangedSignal("Team"):Connect(resetPass)
    links[#links + 1] = RunService.PreSimulation:Connect(updateFlight)
    links[#links + 1] = RunService.Heartbeat:Connect(function(dt)
        if not active() then return end
        elapsed = elapsed + dt
        if elapsed < 0.15 then return end
        elapsed = 0
        if not state.AutoPlay and not state.AutoPass then return end
        if not teamService or not ballService or not controllers.Network or not controllers.Network.CharValues or not controllers.PassController or not controllers.BallController then discover() end
        if state.AutoPlay then joinMatch() end
        if state.AutoPass then
            local previous = NexusUI.Options.AutoPass
            if previous and previous.Value then previous:SetValue(false) end
            passBall()
        end
    end)
    RegisterUnloadCallback(function()
        state.Alive, state.AutoPlay, state.AutoPass = false, false, false
        resetPass(); removePatch()
        for _, connection in ipairs(links) do disconnect(connection) end
        table.clear(links)
    end)
end

do
    local farm = {Enabled = false, Epoch = 0, Lifetime = 45, Recent = setmetatable({}, {__mode = "k"})}
    local function active(epoch)
        return farm.Enabled and not ScriptUnloaded and farm.Epoch == epoch
    end
    local function returnBack()
        local trip = farm.Trip
        farm.Trip = nil
        if not trip or LocalPlayer.Character ~= trip.Character or not trip.Root.Parent or not trip.Humanoid.Parent or trip.Humanoid.Health <= 0 then return end
        pcall(function()
            trip.Root.CFrame = trip.Home
            trip.Root.AssemblyLinearVelocity, trip.Root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        end)
    end
    local function stop()
        farm.Enabled = false
        farm.Epoch = farm.Epoch + 1
        local thread = farm.Thread
        farm.Thread = nil
        if type(thread) == "thread" and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then pcall(task.cancel, thread) end
        if farm.Idle then farm.Idle:Disconnect(); farm.Idle = nil end
        returnBack()
        table.clear(farm.Recent)
    end
    local function position(model, folder)
        if folder.Parent ~= Workspace or not model:IsA("Model") or model.Parent ~= folder or model:GetAttribute("RemovedAt") then return end
        local part = model.PrimaryPart
        if not part or not part:IsA("BasePart") or not part:IsDescendantOf(model) then return end
        local born = model:GetAttribute("Born")
        if type(born) == "number" and born == born then
            local ok, now = pcall(Workspace.GetServerTimeNow, Workspace)
            if ok and now - born >= farm.Lifetime then return end
        end
        return part.Position
    end
    local function nearest(folder, root)
        local best, point, distance
        local now = os.clock()
        for _, model in ipairs(folder:GetChildren()) do
            local target = position(model, folder)
            if target and (farm.Recent[model] or 0) <= now then
                local gap = (target - root.Position).Magnitude
                if not distance or gap < distance then best, point, distance = model, target, gap end
            end
        end
        return best, point
    end
    local function start(enabled)
        stop()
        if not enabled or ScriptUnloaded then return end
        farm.Enabled = true
        local epoch = farm.Epoch
        farm.Idle = LocalPlayer.Idled:Connect(function()
            if not active(epoch) then return end
            local ok = pcall(function()
                local user = game:GetService("VirtualUser")
                user:CaptureController()
                local camera = Workspace.CurrentCamera
                user:ClickButton2(Vector2.zero, camera and camera.CFrame or CFrame.identity)
            end)
            if not ok and not farm.IdleNotified then
                farm.IdleNotified = true
                NexusUI:Notify({Title = "Candy Farm", Content = "Anti-AFK is unavailable in this executor.", Duration = 5})
            end
        end)
        farm.Thread = task.defer(function()
            local ok, failure = pcall(function()
                while active(epoch) do
                    local character = LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local folder = Workspace:FindFirstChild("HalloweenCandy")
                    if humanoid and humanoid.Health > 0 and root and not root.Anchored and not humanoid.Sit and folder then
                        local model, target = nearest(folder, root)
                        if model then
                            local balance = tonumber(LocalPlayer:GetAttribute("HalloweenCandy")) or 0
                            farm.Trip = {Character = character, Humanoid = humanoid, Root = root, Home = root.CFrame}
                            humanoid:Move(Vector3.zero, false)
                            root.CFrame = CFrame.new(target) * root.CFrame.Rotation
                            root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
                            local deadline = os.clock() + 1.2
                            repeat
                                task.wait(0.05)
                                if not active(epoch) then return end
                                if LocalPlayer.Character ~= character or not root.Parent or humanoid.Health <= 0 then break end
                                if not position(model, folder) or (tonumber(LocalPlayer:GetAttribute("HalloweenCandy")) or 0) > balance then break end
                            until os.clock() >= deadline
                            returnBack()
                            farm.Recent[model] = os.clock() + 3
                        end
                    end
                    task.wait(0.2)
                end
            end)
            if active(epoch) and not ok then
                stop()
                local option = NexusUI.Options.AutoFarmCandy
                if option then option:SetValue(false) end
                NexusUI:Notify({Title = "Candy Farm", Content = tostring(failure), Duration = 5})
            end
        end)
    end
    Tabs.EventsFarm:AddSection("Halloween")
    Tabs.EventsFarm:AddToggle("AutoFarmCandy", {
        Title = "Auto Farm Candy", Default = false, ShowDescription = true,
        Description = "You can use this feature without being in a round, quickly collect candy, and return to your original position (this way, you will not be noticed and the risk of a ban is minimal). Anti-AFK is also built in, so you can go about your business while farming candy!",
        Callback = start
    })
    RegisterUnloadCallback(stop)
end

end}
