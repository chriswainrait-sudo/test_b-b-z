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
    local passInputInfo = function()
        if not alive then return end
        local network = controllers.Network
        local player = network and network.Player
        local settings = player and player.Customization and player.Customization.Settings
        local target = controllers.PassController and controllers.PassController.LookingAt
        local ability = controllers.AbilityController
        local signal = ability and ability.BallService and ability.BallService.Pass
        return settings, network and network.Gamemode, target, signal, controllers.PassController, ability and ability.BallService and ability.BallService.Throw, controllers.BallController
    end
    NexusUI.State.PassInputInfo = passInputInfo
    RegisterUnloadCallback(function() if NexusUI.State.PassInputInfo == passInputInfo then NexusUI.State.PassInputInfo = nil end end)
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
                PassController = {Pass = "function", Anim = "function"},
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
                                if name ~= "CameraController" and name ~= "PassController" then count += 1 end
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
                    if count == 5 and sharedTables.Zones and sharedTables.Styles and found.CameraController and found.PassController then break end
                    visited += 1
                    if visited % 2000 == 0 then task.wait() end
                end
                objects = nil
                if not alive then return end
                if count == 5 then
                    controllers = found
                    controllerState = "connected"
                    if sharedTables.Zones and sharedTables.Styles and found.CameraController and found.PassController then break end
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
    local liftService = {Alive = true}
    NexusUI.State.BallExtraLiftService = liftService
    local function activeLift()
        local lift = NexusUI.State.BallExtraLift
        if type(lift) ~= "table" then return end
        if lift.Service ~= liftService or lift.Character ~= character or not root or not humanoid or humanoid.Health <= 0
            or type(lift.Expires) ~= "number" or os.clock() > lift.Expires or typeof(lift.Velocity) ~= "Vector3" then
            if lift.Service == liftService and NexusUI.State.BallExtraLift == lift then NexusUI.State.BallExtraLift = nil end
            return
        end
        return lift
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
    local lastInfiniteJump = -math.huge
    local lastJumpRoot
    connect(Input.JumpRequest, function()
        if not config.InfiniteJump or config.Fly or not root or not humanoid
            or humanoid.Health <= 0 or humanoid.Sit or Input:GetFocusedTextBox() then return end
        local state = humanoid:GetState()
        if state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Climbing
            or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.Physics then return end
        local now = os.clock()
        if root == lastJumpRoot and now - lastInfiniteJump < 0.1 then return end
        lastJumpRoot, lastInfiniteJump = root, now
        local velocity = root.AssemblyLinearVelocity
        local height = config.Jump and config.JumpHeight or 7.2
        local launch = math.sqrt(2 * workspace.Gravity * height)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, launch), velocity.Z)
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
        return value and value:IsA("StringValue") and value.Value or "Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В Р вЂ№Р В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р Р‹Р Р†РІР‚С›РЎС›Р В Р’В Р вЂ™Р’В Р В Р’В Р В РІР‚в„–Р В Р’В Р В Р вЂ№Р В Р Р‹Р Р†РІР‚С›РЎС›"
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
        m.text.Text = name .. (config.Distance and string.format(" Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В РІР‚В Р В Р вЂ Р В РІР‚С™Р РЋРІР‚С”Р В Р Р‹Р РЋРІР‚С”Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р Р†РІР‚С›РЎС›Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В· %.0f studs", distance) or "")
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
        m.text.Text = table.concat(lines, " Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В РІР‚В Р В Р вЂ Р В РІР‚С™Р РЋРІР‚С”Р В Р Р‹Р РЋРІР‚С”Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р Р†РІР‚С›РЎС›Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В· ")
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
    csToggle("CS_InfiniteJump", "InfiniteJump", Tabs.EventsFarm, "Infinite Jump", "Jump again without waiting to land")
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
        local lift = activeLift()
        if config.Fly or lift then
            if not flyVelocity then
                flyAttachment = make("Attachment", {Name = "CourtsideFlight"}, root)
                flyVelocity = make("LinearVelocity", {Name = "CourtsideVelocity", Attachment0 = flyAttachment,
                    RelativeTo = Enum.ActuatorRelativeTo.World, ForceLimitsEnabled = false, VectorVelocity = Vector3.zero}, root)
            end
            override(humanoid, "AutoRotate", false)
            if lift then flyVelocity.VectorVelocity = lift.Velocity; return end
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
            if not config.Fly and not activeLift() then restore(humanoid, "AutoRotate") end
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
            status.Text = string.format("GUI: %s Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В Р вЂ№Р В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћвЂ“Р В Р’В Р вЂ™Р’В Р В Р’В Р В РІР‚в„–Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р Р‹Р Р†Р вЂљРЎСљ Knit: %s\nDribble: %s", "Nexus", controllerState, dribblePatchStatus)
            if config.InventoryHUD then
                local network = controllers.Network
                local data = network and network.Player
                local function count(key)
                    local value = type(data) == "table" and data[key]
                    return type(value) == "number" and tostring(math.max(0, math.floor(value))) or "Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В Р вЂ№Р В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р Р‹Р Р†РІР‚С›РЎС›Р В Р’В Р вЂ™Р’В Р В Р’В Р В РІР‚в„–Р В Р’В Р В Р вЂ№Р В Р Р‹Р Р†РІР‚С›РЎС›"
                end
                local ability = controllers.AbilityController
                local cds = ability and ability.CDS
                local cooldowns = {}
                for i = 1, 4 do
                    local value = type(cds) == "table" and cds[i]
                    cooldowns[i] = type(value) == "number" and string.format("%.1f", math.max(0, value - tick())) or "Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р Р†Р вЂљРІвЂћСћР В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р’В Р Р†Р вЂљР’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р РЋРІвЂћСћР В Р’В Р В Р вЂ№Р В Р вЂ Р Р†Р вЂљРЎвЂєР РЋРЎвЂєР В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В Р вЂ Р В РІР‚С™Р вЂ™Р’В Р В Р’В Р вЂ™Р’В Р В РІР‚в„ўР вЂ™Р’В Р В Р’В Р В РІР‚В Р В Р’В Р Р†Р вЂљРЎв„ўР В Р Р‹Р Р†РІР‚С›РЎС›Р В Р’В Р вЂ™Р’В Р В Р’В Р В РІР‚в„–Р В Р’В Р В Р вЂ№Р В Р Р‹Р Р†РІР‚С›РЎС›"
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
        liftService.Alive = false
        if NexusUI.State.BallExtraLiftService == liftService then NexusUI.State.BallExtraLiftService = nil end
        local lift = NexusUI.State.BallExtraLift
        if type(lift) == "table" and lift.Service == liftService then NexusUI.State.BallExtraLift = nil end
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


--[=[
do
    local state = {Alive = true, Enabled = false, Team = "Auto", LastClick = -10, Phase = "Ready", Since = 0, Epoch = 0}
    local elapsed, links = 0, {}
    local input, pressed
    local candidate, candidateAt, candidatePosition, leftAt
    local function active() return state.Alive and not ScriptUnloaded end
    local function visible(object)
        local current = object
        while current and current ~= PlayerGui do
            if current:IsA("GuiObject") and not current.Visible or current:IsA("ScreenGui") and not current.Enabled then return false end
            current = current.Parent
        end
        return current == PlayerGui
    end
    local function release(cancel)
        local current = pressed
        pressed = nil
        if current and input then return pcall(input.SendMouseButtonEvent, input, cancel and 0 or current.X, cancel and 0 or current.Y, 0, false, game, 0) end
    end
    local function fail(message)
        state.Enabled = false
        release(true)
        local epoch = state.Epoch
        task.defer(function()
            if not active() or state.Epoch ~= epoch then return end
            local option = NexusUI.Options.NewAutoPlay
            if option then option:SetValue(false) end
            NexusUI:Notify({Title = "Auto Play", Content = tostring(message), Duration = 5})
        end)
    end
    local function hitButton(button, x, y)
        local ok, objects = pcall(PlayerGui.GetGuiObjectsAtPosition, PlayerGui, x, y)
        if not ok or not objects then return false end
        for _, object in ipairs(objects) do
            if object == button or object:IsDescendantOf(button) then return true end
            if object:IsA("GuiButton") or object.Active then return false end
        end
        return false
    end
    local function buttonPoint(button)
        if not button or not button:IsA("GuiButton") or not visible(button) or button.Interactable == false then return end
        local size, position = button.AbsoluteSize, button.AbsolutePosition
        local camera = Workspace.CurrentCamera
        if size.X < 2 or size.Y < 2 or not camera then return end
        local inset = game:GetService("GuiService"):GetGuiInset()
        local center = position + size / 2
        for _, offset in ipairs({Vector2.zero, inset}) do
            local x, y = math.floor(center.X + offset.X), math.floor(center.Y + offset.Y)
            if x > 0 and y > 0 and x < camera.ViewportSize.X and y < camera.ViewportSize.Y and hitButton(button, x, y) then return x, y, center end
        end
    end
    local function click(button, phase, slot)
        if pressed or not input or userInputService:GetFocusedTextBox() then return false end
        local x, y, center = buttonPoint(button)
        if not x then return false end
        if candidate ~= button or (candidatePosition - center).Magnitude > 2 then
            candidate, candidateAt, candidatePosition = button, os.clock(), center
            return false
        end
        if os.clock() - candidateAt < 0.4 or slot and slot.Value ~= nil then return false end
        candidate = nil
        state.LastClick, state.Since, state.Phase = os.clock(), os.clock(), phase
        local current = {X = x, Y = y, Epoch = state.Epoch}
        pressed = current
        local ok, failure = pcall(input.SendMouseButtonEvent, input, x, y, 0, true, game, 0)
        if not ok then fail(failure); return false end
        task.delay(0.08, function()
            if pressed ~= current then return end
            local cancel = not active() or not state.Enabled or state.Epoch ~= current.Epoch
                or not button.Parent or not visible(button) or slot and slot.Value ~= nil
                or (button.AbsolutePosition + button.AbsoluteSize / 2 - center).Magnitude > 4
            if not cancel then cancel = not hitButton(button, x, y) end
            local released, failure = release(cancel)
            if released == false then fail(failure) end
        end)
        return true
    end
    local function update()
        if not active() or not state.Enabled or pressed then return end
        local now = os.clock()
        local slots = ReplicatedStorage:FindFirstChild("Teams")
        local pick = PlayerGui:FindFirstChild("PickTeam")
        if not slots or not pick then return end
        for _, folder in ipairs(slots:GetChildren()) do
            for _, slot in ipairs(folder:GetChildren()) do
                if slot:IsA("ObjectValue") and slot.Value == LocalPlayer then
                    state.Phase, leftAt, candidate = "Joined", nil, nil
                    return
                end
            end
        end
        if state.Phase == "Joined" then
            if not LocalPlayer.Team or LocalPlayer.Team.Name ~= "Visitor" then leftAt = nil; return end
            leftAt = leftAt or now
            if now - leftAt < 2 then return end
            state.Phase, state.Since, leftAt = "Ready", now, nil
        end
        if state.Phase == "JoinPending" then
            if now - state.Since > 15 then fail("The game did not confirm joining. No repeat request was sent.") end
            return
        end
        if state.Phase == "MenuPending" then
            if pick.Enabled then state.Phase, state.Since = "TeamReady", now
            elseif now - state.Since > 12 then fail("The team menu did not open. No repeat click was sent.") end
            return
        end
        if userInputService:GetFocusedTextBox() then candidate = nil; return end
        if not pick.Enabled then
            if state.Phase == "TeamReady" then fail("The team menu closed. Auto Play stopped."); return end
            local hud = PlayerGui:FindFirstChild("HUD")
            local play = hud and hud:FindFirstChild("Play", true)
            local button = play and (play:IsA("GuiButton") and play or play:FindFirstChildWhichIsA("GuiButton", true))
            click(button, "MenuPending")
            return
        end
        if state.Phase ~= "TeamReady" then state.Phase, state.Since = "TeamReady", now end
        if now - state.Since < 0.75 then return end
        local choices = state.Team == "Auto" and {"Home", "Away"} or {state.Team}
        if LocalPlayer.Team and (LocalPlayer.Team.Name == "Home" or LocalPlayer.Team.Name == "Away") then choices = {LocalPlayer.Team.Name}
        elseif state.Team == "Auto" then
            local teams = game:GetService("Teams")
            local home, away = teams:FindFirstChild("Home"), teams:FindFirstChild("Away")
            if home and away and #home:GetPlayers() > #away:GetPlayers() then choices = {"Away", "Home"} end
        end
        for _, name in ipairs(choices) do
            local folder, panel = slots:FindFirstChild(name), pick:FindFirstChild(name)
            if folder and panel and visible(panel) then
                for _, button in ipairs(panel:GetDescendants()) do
                    if button:IsA("GuiButton") and visible(button) then
                        local slot = folder:FindFirstChild(button.Name)
                        if slot and slot:IsA("ObjectValue") and slot.Value == nil and buttonPoint(button) then click(button, "JoinPending", slot); return end
                    end
                end
            end
        end
    end
    Tabs.EventsFarm:AddSection("Auto Play")
    Tabs.EventsFarm:AddDropdown("NewJoinTeam", {Title = "Team", Values = {"Auto", "Home", "Away"}, Default = "Auto", Callback = function(value) state.Team = value end})
    Tabs.EventsFarm:AddToggle("NewAutoPlay", {Title = "Auto Play", Description = "Clicks Play and an available team position", Default = false, Callback = function(value)
        release(true)
        state.Epoch = state.Epoch + 1
        state.Enabled, state.LastClick, state.Phase, state.Since = value, -10, "Ready", os.clock()
        candidate, leftAt = nil, nil
        if not value then return end
        if not input then
            local ok, result = pcall(game.GetService, game, "VirtualInputManager")
            if not ok then fail(result); return end
            input = result
        end
    end})
    links[#links + 1] = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if elapsed >= 0.2 then elapsed = 0; update() end
    end)
    RegisterUnloadCallback(function()
        state.Alive, state.Enabled = false, false
        state.Epoch = state.Epoch + 1
        release(true)
        for _, connection in ipairs(links) do connection:Disconnect() end
    end)
end
]=]

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

do
    local variants = {["Normal Shot"] = "ShootF", ["Fadeaway"] = "ShootB"}
    local fakeId = "116636356590637"
    local mode = "Default"
    local generation = 0
    local played, stopped, characterAdded, characterRemoving
    local tracks = {}
    local overlay

    local function stopOverlay()
        if stopped then stopped:Disconnect(); stopped = nil end
        if overlay then overlay:Stop(0.06); overlay = nil end
    end

    local function clearAnimator()
        generation += 1
        if played then played:Disconnect(); played = nil end
        stopOverlay()
        for _, track in pairs(tracks) do track:Destroy() end
        table.clear(tracks)
    end

    local function bindAnimator(character)
        clearAnimator()
        if not character or mode == "Default" or ScriptUnloaded then return end
        local token = generation
        task.spawn(function()
            local humanoid = character:WaitForChild("Humanoid", 8)
            local animator = humanoid and humanoid:WaitForChild("Animator", 8)
            if not animator or token ~= generation or LocalPlayer.Character ~= character then return end
            local assets = ReplicatedStorage:FindFirstChild("Assets")
            local animations = assets and assets:FindFirstChild("Animations")
            local shots = animations and animations:FindFirstChild("Shots")
            if not shots then return end

            for _, name in pairs(variants) do
                local animation = shots:FindFirstChild(name)
                if animation and animation:IsA("Animation") then
                    local ok, track = pcall(animator.LoadAnimation, animator, animation)
                    if token ~= generation then
                        if ok then track:Destroy() end
                        return
                    end
                    if ok then
                        track.Priority = Enum.AnimationPriority.Action3
                        track.Looped = false
                        tracks[name] = track
                    end
                end
            end

            played = animator.AnimationPlayed:Connect(function(track)
                if track == overlay or token ~= generation then return end
                local animation = track.Animation
                local id = animation and animation.AnimationId:match("%d+")
                if id ~= fakeId then
                    local priority = track.Priority
                    if priority ~= Enum.AnimationPriority.Core and priority.Value >= Enum.AnimationPriority.Action2.Value then
                        stopOverlay()
                    end
                    return
                end

                task.defer(function()
                    if token ~= generation or not track.IsPlaying then return end
                    local replacement = tracks[variants[mode]]
                    if not replacement then return end
                    stopOverlay()
                    overlay = replacement
                    replacement:Play(0.04)
                    if replacement.Length > 0 then
                        replacement.TimePosition = math.min(track.TimePosition, math.max(0, replacement.Length - 0.05))
                    end
                    stopped = track.Stopped:Connect(stopOverlay)
                end)
            end)
        end)
    end

    Tabs.EventsFarm:AddDropdown("PumpFakeAnimation", {
        Title = "Pump Fake Animation",
        Values = {"Default", "Normal Shot", "Fadeaway"},
        Default = "Default",
        Callback = function(value)
            mode = value or "Default"
            bindAnimator(LocalPlayer.Character)
        end,
    })
    characterAdded = LocalPlayer.CharacterAdded:Connect(bindAnimator)
    characterRemoving = LocalPlayer.CharacterRemoving:Connect(clearAnimator)
    RegisterUnloadCallback(function()
        mode = "Default"
        characterAdded:Disconnect()
        characterRemoving:Disconnect()
        clearAnimator()
    end)
end

do
    local delayMs = 60
    local generation = 0
    local connection

    local function stop()
        generation += 1
        if connection then connection:Disconnect(); connection = nil end
    end

    local function start()
        stop()
        local token = generation
        task.spawn(function()
            local ok, ball, ability, network, moves, jackpot = pcall(function()
                local knit = require(ReplicatedStorage.Packages.Knit)
                local abilities = ReplicatedStorage.Controllers.AbilityController.Abilities
                return knit.GetController("BallController"), knit.GetController("AbilityController"),
                    knit.GetController("Network"), require(abilities), abilities.Jackpot.JackpotSteal
            end)
            if not ok or token ~= generation or ScriptUnloaded then return end

            local function getCandidate()
                local team = LocalPlayer.Team
                if not team or (team.Name ~= "Home" and team.Name ~= "Away") then return end
                local values = ReplicatedStorage:FindFirstChild("GameValues")
                local state = values and values:FindFirstChild("State")
                local tipOff = values and values:FindFirstChild("TipOff")
                if not state or state.Value ~= "Playing" or (tipOff and tipOff.Value) then return end

                local style = LocalPlayer:FindFirstChild("Style")
                local equipped = style and moves[style.Value]
                if not equipped then return end
                local slot
                for index = 1, 3 do
                    local effective = index == 1 and network.CharValues.InAwakening and equipped[4] and 4 or index
                    local move = equipped[effective]
                    local cooldown = ability.CDS and ability.CDS[effective]
                    if move and move.Ability == jackpot and not move.Holdable
                        and type(cooldown) == "number" and cooldown <= tick() then
                        slot = index
                        break
                    end
                end
                if not slot then return end

                local opponent = ball:GetPlayerPossessingBall()
                if not opponent or opponent.Team == team or not opponent.Team
                    or opponent.Team.Name == "Visitor" then return end
                local character, enemy = LocalPlayer.Character, opponent.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
                if not root or not enemyRoot then return end
                local hoops = workspace:FindFirstChild("Hoops")
                local home = hoops and hoops:FindFirstChild("Home")
                local away = hoops and hoops:FindFirstChild("Away")
                local homeHoop = home and home:FindFirstChild("Hoop")
                local awayHoop = away and away:FindFirstChild("Hoop")
                if not homeHoop or not awayHoop then return end
                local axis = awayHoop.Position - homeHoop.Position
                axis = Vector3.new(axis.X, 0, axis.Z)
                if axis.Magnitude < 1 then return end
                local side = (enemyRoot.Position - (homeHoop.Position + awayHoop.Position) / 2):Dot(axis)
                if (team.Name == "Home" and side >= 0) or (team.Name == "Away" and side <= 0) then return end
                local position = ball:GetServerBallPosition()
                if typeof(position) ~= "Vector3" or (position - root.Position).Magnitude > 38 then return end
                return opponent, slot
            end

            local carrier, queuedSlot, enteredAt, busy
            local lastCheck, lastAttempt = -math.huge, -math.huge
            connection = RunService.Heartbeat:Connect(function()
                local now = os.clock()
                if busy or now - lastCheck < 0.016 then return end
                lastCheck = now
                local valid, opponent, slot = pcall(getCandidate)
                if token ~= generation or ScriptUnloaded then return end
                if not valid or not opponent then carrier, queuedSlot, enteredAt = nil, nil, nil; return end
                if carrier ~= opponent or queuedSlot ~= slot then
                    carrier, queuedSlot, enteredAt = opponent, slot, now
                end
                if now - enteredAt < delayMs / 1000 or now - lastAttempt < 0.75 then return end

                local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local hud = playerGui and playerGui:FindFirstChild("InGame")
                local bg = hud and hud:FindFirstChild("BG")
                local bottom = bg and bg:FindFirstChild("Bottom")
                local button = bottom and bottom:FindFirstChild("Ability" .. slot)
                if not button or not button:IsA("GuiButton") then return end

                lastAttempt, busy = now, true
                local signal = button.MouseButton1Click
                local fired = false
                if type(getconnections) == "function" then
                    local found, connections = pcall(getconnections, signal)
                    if found and type(connections) == "table" then
                        for _, handler in ipairs(connections) do
                            if token ~= generation then break end
                            local called = pcall(function()
                                if handler.Enabled == false or type(handler.Function) ~= "function" then error("inactive") end
                                handler.Function()
                            end)
                            fired = fired or called
                        end
                    end
                end
                if not fired and token == generation and type(firesignal) == "function" then pcall(firesignal, signal) end
                busy = false
            end)
        end)
    end

    Tabs.EventsFarm:AddToggle("NewJackpotSteal", {
        Title = "Jackpot Steal",
        Default = false,
        Callback = function(value)
            if value and not ScriptUnloaded then start() else stop() end
        end,
    })
    Tabs.EventsFarm:AddSlider("NewJackpotStealDelay", {
        Title = "Jackpot Steal Delay (ms)",
        Default = 60, Min = 0, Max = 500, Rounding = 0,
        Callback = function(value) delayMs = value end,
    })
    RegisterUnloadCallback(stop)
end

do
    local jumpScale, travelScale = 1, 1
    local generation = 0
    local played, simulation
    local applied = {}
    local jump, dribble
    local jumpMoves = {
        Sniper = {"Ability1"},
        Dealer = {"HighStakes"},
        LazyWorker = {"Ability2Left", "Ability2Right"},
        Silver = {"EarthshakerJump", "PushFade"},
    }
    local travelMoves = {
        Silver = {"DribblePush"},
        ScaryMonster = {"BulletPressure", "TimeSkipCrossover"},
    }

    local function restore()
        for mover, change in pairs(applied) do
            if mover.Parent and mover[change.Property] == change.Applied then
                mover[change.Property] = change.Base
            end
        end
        table.clear(applied)
    end

    local function stop()
        generation += 1
        if played then played:Disconnect(); played = nil end
        if simulation then simulation:Disconnect(); simulation = nil end
        jump, dribble = nil, nil
        restore()
    end

    local function bind(character)
        stop()
        if not character or ScriptUnloaded or (jumpScale == 1 and travelScale == 1) then return end
        local token = generation
        task.spawn(function()
            local humanoid = character:WaitForChild("Humanoid", 8)
            local animator = humanoid and humanoid:WaitForChild("Animator", 8)
            local root = character:FindFirstChild("HumanoidRootPart")
            if not animator or not root or token ~= generation or LocalPlayer.Character ~= character then return end
            local assets = ReplicatedStorage:FindFirstChild("Assets")
            local styles = assets and assets:FindFirstChild("StyleAnimations")
            local animations = assets and assets:FindFirstChild("Animations")
            if not styles or not animations then return end
            local jumpIds, travelIds = {}, {}

            local function addAnimation(target, animation)
                if animation and animation:IsA("Animation") then
                    local id = animation.AnimationId:match("%d+")
                    if id then target[id] = true end
                end
            end

            local function registerMoves(target, entries)
                for style, names in pairs(entries) do
                    local folder = styles:FindFirstChild(style)
                    if folder then
                        for _, name in ipairs(names) do addAnimation(target, folder:FindFirstChild(name)) end
                    end
                end
            end

            registerMoves(jumpIds, jumpMoves)
            registerMoves(travelIds, travelMoves)
            for _, folder in ipairs(animations:GetChildren()) do
                if folder.Name == "Dribbles" or folder.Name:match("Combo$") then
                    for _, animation in ipairs(folder:GetChildren()) do addAnimation(travelIds, animation) end
                end
            end

            played = animator.AnimationPlayed:Connect(function(track)
                if token ~= generation or ScriptUnloaded then return end
                local values = ReplicatedStorage:FindFirstChild("GameValues")
                local state = values and values:FindFirstChild("State")
                if not state or state.Value ~= "Playing" or humanoid.Health <= 0 then return end
                local animation = track.Animation
                local id = animation and animation.AnimationId:match("%d+")
                if not id then return end
                local now = os.clock()
                if jumpScale > 1 and jumpIds[id] then jump = {Track = track, At = now} end
                if travelScale > 1 and travelIds[id] then
                    restore()
                    dribble = {Track = track, At = now}
                end
            end)

            simulation = RunService.PreSimulation:Connect(function()
                if token ~= generation then return end
                if ScriptUnloaded or humanoid.Health <= 0 then stop(); return end
                local now = os.clock()
                if jump then
                    local elapsed = now - jump.At
                    if not jump.Track.IsPlaying or elapsed > 0.3 then
                        jump = nil
                    elseif elapsed >= 0.02 then
                        local velocity = root.AssemblyLinearVelocity
                        if velocity.Y > 4 or elapsed >= 0.10 then
                            local base = math.max(velocity.Y, 0)
                            local boost = base > 4 and base * (math.sqrt(jumpScale) - 1)
                                or 40 * (math.sqrt(jumpScale) - 1)
                            root:ApplyImpulse(Vector3.new(0, root.AssemblyMass * boost, 0))
                            jump = nil
                        end
                    end
                end

                if not dribble then return end
                if not dribble.Track.IsPlaying or now - dribble.At > 1.2 then
                    dribble = nil
                    restore()
                    return
                end
                for _, mover in ipairs(root:GetChildren()) do
                    local property
                    if mover:IsA("LinearVelocity") and mover.RelativeTo == Enum.ActuatorRelativeTo.World
                        and mover.VelocityConstraintMode == Enum.VelocityConstraintMode.Vector then
                        property = "VectorVelocity"
                    elseif mover:IsA("BodyVelocity") then
                        property = "Velocity"
                    end
                    if property then
                        local value = mover[property]
                        local prior = applied[mover]
                        local base = prior and value == prior.Applied and prior.Base or value
                        if math.abs(base.X) + math.abs(base.Z) > 1 then
                            local scaled = Vector3.new(base.X * travelScale, base.Y, base.Z * travelScale)
                            mover[property] = scaled
                            applied[mover] = {Property = property, Base = base, Applied = mover[property]}
                        end
                    end
                end
            end)
        end)
    end

    Tabs.EventsFarm:AddSection("Style Tuning")
    Tabs.EventsFarm:AddSlider("NewStyleJumpHeight", {
        Title = "Ability Jump Height (%)", Default = 100, Min = 100, Max = 250, Rounding = 0,
        Callback = function(value)
            jumpScale = value / 100
            bind(LocalPlayer.Character)
        end,
    })
    Tabs.EventsFarm:AddSlider("NewDribbleTravel", {
        Title = "Dribble Travel (%)", Default = 100, Min = 100, Max = 160, Rounding = 0,
        Callback = function(value)
            travelScale = value / 100
            bind(LocalPlayer.Character)
        end,
    })
    local added = LocalPlayer.CharacterAdded:Connect(bind)
    local removing = LocalPlayer.CharacterRemoving:Connect(stop)
    RegisterUnloadCallback(function()
        added:Disconnect()
        removing:Disconnect()
        stop()
    end)
end

do
    local durations = {}
    local moves = {
        {"DealerDash", "Dealer False Deal Extension", 350},
        {"LazyDash", "Lazy Worker Ability 2 Extension", 350},
        {"SilverDash", "Silver Dribble Push Extension", 350},
        {"SilverAir", "Silver Jump Hang Time", 300},
        {"SniperAir", "Sniper Perfect Arc Hang Time", 300},
        {"SniperDash", "Sniper Quick Release Extension", 250},
    }
    local ids = {}
    local function register(key, folder, name)
        local asset = folder and folder:FindFirstChild(name)
        local id = asset and asset:IsA("Animation") and asset.AnimationId:match("%d+")
        if id then ids[id] = key end
    end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local styles = assets and assets:FindFirstChild("StyleAnimations")
    local animations = assets and assets:FindFirstChild("Animations")
    if styles and animations then
        register("DealerDash", styles:FindFirstChild("Dealer"), "FalseDeal")
        register("LazyDash", styles:FindFirstChild("LazyWorker"), "Ability2")
        register("SilverDash", styles:FindFirstChild("Silver"), "DribblePush")
        register("SilverAir", styles:FindFirstChild("Silver"), "EarthshakerJump")
        register("SilverAir", styles:FindFirstChild("Silver"), "PushFade")
        register("SilverBlock", animations:FindFirstChild("Blocks"), "JumpBlock2")
        register("SniperAir", styles:FindFirstChild("Sniper"), "Ability1")
    end

    local animationConnection, stepConnection
    local motion, hang
    local function stop()
        if animationConnection then animationConnection:Disconnect(); animationConnection = nil end
        if stepConnection then stepConnection:Disconnect(); stepConnection = nil end
        motion, hang = nil, nil
    end

    local generation = 0
    local function refresh(character)
        generation += 1
        stop()
        if not character or ScriptUnloaded or not next(durations) then return end
        local token = generation
        task.spawn(function()
            local humanoid = character:WaitForChild("Humanoid", 8)
            local animator = humanoid and humanoid:WaitForChild("Animator", 8)
            local root = character:FindFirstChild("HumanoidRootPart")
            if not animator or not root or token ~= generation or LocalPlayer.Character ~= character then return end

            local function style()
                local value = LocalPlayer:FindFirstChild("Style")
                return value and value.Value
            end
            local function playing()
                local values = ReplicatedStorage:FindFirstChild("GameValues")
                local state = values and values:FindFirstChild("State")
                return state and state.Value == "Playing" and humanoid.Health > 0
                    and not humanoid.Sit and not root.Anchored and character.Parent
                    and not character:GetAttribute("Stunned")
            end
            animationConnection = animator.AnimationPlayed:Connect(function(track)
                if token ~= generation or not playing() then return end
                local animation = track.Animation
                local key = animation and ids[animation.AnimationId:match("%d+")]
                if key == "SilverBlock" then
                    key = style() == "Silver" and track.Priority == Enum.AnimationPriority.Action3 and "SilverAir" or nil
                end
                if not key or not durations[key] then return end
                if key == "SilverAir" or key == "SniperAir" then
                    hang = {Key = key, Track = track, Until = os.clock() + 1.4}
                elseif not motion or motion.Key ~= key then
                    motion = {Key = key, Until = os.clock() + 1.5}
                end
            end)

            stepConnection = RunService.PreSimulation:Connect(function()
                if token ~= generation or ScriptUnloaded or not playing() then motion, hang = nil, nil; return end
                local now = os.clock()
                local velocity = root.AssemblyLinearVelocity
                local mover = root:FindFirstChildWhichIsA("LinearVelocity")
                local styleName = style()
                if not motion and mover then
                    local vector = mover.VectorVelocity
                    local force = mover.MaxAxesForce
                    if durations.SniperDash and styleName == "Sniper"
                        and mover.ForceLimitMode == Enum.ForceLimitMode.PerAxis
                        and force.X >= 2e9 and force.Y >= 2e9 and force.Z >= 2e9
                        and math.abs(vector.Magnitude - 50) < 1 then
                        motion = {Key = "SniperDash", Until = now + 1.8}
                    elseif durations.DealerDash and styleName == "Dealer" and mover.MaxForce == math.huge
                        and vector:Dot(root.CFrame.LookVector) < -12 and math.abs(vector.Y) < 0.1
                        and math.abs(vector:Dot(root.CFrame.RightVector)) < 0.1 then
                        motion = {Key = "DealerDash", Until = now + 0.8}
                    end
                end

                if motion then
                    local duration = durations[motion.Key]
                    if not duration or now > motion.Until then
                        motion = nil
                    elseif not motion.Mover then
                        if mover then motion.Mover = mover end
                    elseif motion.Mover.Parent == root then
                        local vector = motion.Mover.VectorVelocity
                        local horizontal = Vector3.new(vector.X, 0, vector.Z)
                        if horizontal.Magnitude >= 8 then motion.Last = horizontal end
                    elseif mover or not motion.Last then
                        motion = nil
                    else
                        motion.Start = motion.Start or now
                        local fraction = (now - motion.Start) / duration
                        if fraction >= 1 then
                            motion = nil
                        else
                            local extra = motion.Last.Unit * math.min(motion.Last.Magnitude, 25) * (1 - fraction)
                            root.AssemblyLinearVelocity = Vector3.new(extra.X, velocity.Y, extra.Z)
                        end
                    end
                end

                if hang then
                    local duration = durations[hang.Key]
                    if not duration or now > hang.Until
                        or (hang.Key == "SniperAir" and hang.Track.Speed >= 2.37 and not hang.Rising) then
                        hang = nil
                    elseif velocity.Y > 5 and humanoid.FloorMaterial == Enum.Material.Air then
                        hang.Rising = true
                    elseif hang.Rising and humanoid.FloorMaterial == Enum.Material.Air and velocity.Y <= 0 then
                        hang.Start = hang.Start or now
                        if now - hang.Start >= duration then
                            hang = nil
                        elseif velocity.Y < -3 then
                            local current = root.AssemblyLinearVelocity
                            root.AssemblyLinearVelocity = Vector3.new(current.X, -3, current.Z)
                        end
                    end
                end
            end)
        end)
    end

    Tabs.EventsFarm:AddSection("Test Functions")
    for _, entry in ipairs(moves) do
        local key, title, maximum = entry[1], entry[2], entry[3]
        Tabs.EventsFarm:AddSlider("Test" .. key, {
            Title = title .. " (ms)", Default = 0, Min = 0, Max = maximum, Rounding = 0,
            Callback = function(value)
                durations[key] = value > 0 and value / 1000 or nil
                refresh(LocalPlayer.Character)
            end,
        })
    end
    local added = LocalPlayer.CharacterAdded:Connect(refresh)
    local removing = LocalPlayer.CharacterRemoving:Connect(function()
        generation += 1
        stop()
    end)
    RegisterUnloadCallback(function()
        generation += 1
        added:Disconnect()
        removing:Disconnect()
        stop()
    end)
end

do
    local alive, context, loading = true, nil, false
    local config = {SmartSteal = false, StealRange = 14, StealTiming = "Balanced", Genius = false,
        SoulCatch = false, CopyTarget = "Default", CopySlot = "Random", SpecialTarget = "Default",
        SwitchTarget = "Default"}
    local connections, hooks, targets, options = {}, {}, {}, {}
    local notices, circles = {}, setmetatable({}, {__mode = "k"})
    local steal = {Seen = setmetatable({}, {__mode = "k"}), Next = 0, Protected = 0, Exhausted = 0, Count = 0}
    local lastScan, lastTargets, lastSteal = -math.huge, -math.huge, -math.huge
    local updateHooks, updateRun
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local dribbleIds, specialIds = {}, {}

    local function connect(signal, fn)
        local c = signal:Connect(fn)
        connections[#connections + 1] = c
        return c
    end
    local function notify(key, message)
        if notices[key] then return end
        notices[key] = true
        NexusUI:Notify({Title = "PRIME", Content = message, Duration = 5})
    end
    local function click(button, event)
        if not button or not button:IsA("GuiButton") then return false end
        local signal = button[event or "MouseButton1Click"]
        if type(getconnections) == "function" then
            local ok, handlers = pcall(getconnections, signal)
            local fired = false
            for _, handler in ipairs(ok and type(handlers) == "table" and handlers or {}) do
                if not alive or ScriptUnloaded then break end
                local readable, enabled = pcall(function() return handler.Enabled end)
                if not readable or enabled ~= false then
                    local got, fn = pcall(function() return handler.Function end)
                    local success = got and type(fn) == "function" and pcall(fn)
                    if not success then success = pcall(function() handler:Fire() end) end
                    fired = fired or success
                end
            end
            if fired then return true end
        end
        return type(firesignal) == "function" and pcall(firesignal, signal) or false
    end
    local function visible(object)
        if not object or not object:IsDescendantOf(PlayerGui) then return false end
        local p = object
        while p and p ~= PlayerGui do
            if p:IsA("GuiObject") and not p.Visible then return false end
            if p:IsA("ScreenGui") and not p.Enabled then return false end
            p = p.Parent
        end
        return true
    end
    local function living(player)
        local character = player and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if player and player.Parent == Players and character and character.Parent and root and humanoid and humanoid.Health > 0 then
            return character, root, humanoid
        end
    end
    local function sameSide(player, side)
        local team, other = LocalPlayer.Team, player and player.Team
        return player ~= LocalPlayer and team and other and team.Name ~= "Visitor" and other.Name ~= "Visitor"
            and (side == "Any" or side == "Ally" and team == other or side == "Enemy" and team ~= other)
    end
    local function targetFor(selection, side, maximum)
        local _, root = living(LocalPlayer)
        if not root or selection == "Default" then return end
        local chosen, distance
        for _, player in ipairs(Players:GetPlayers()) do
            if sameSide(player, side) and (selection == "Nearest" or targets[selection] == player.UserId) then
                local character, otherRoot = living(player)
                local d = otherRoot and (otherRoot.Position - root.Position).Magnitude
                if d and (not maximum or d <= maximum) and (not distance or d < distance) then
                    chosen, distance = character, d
                end
            end
        end
        return chosen
    end
    local function proxyController(controller, field, selection, side, maximum, ownerKey)
        local target = targetFor(selection, side, maximum)
        if not target then return end
        ownerKey = ownerKey or "Pass"
        local pass = controller[ownerKey]
        if type(pass) ~= "table" then return end
        local selected = setmetatable({}, {
            __index = function(_, key)
                if key == field then
                    if target.Parent and Players:GetPlayerFromCharacter(target) then return target end
                    return nil
                end
                return pass[key]
            end,
            __newindex = function(_, key, value) pass[key] = value end,
        })
        return setmetatable({}, {
            __index = function(_, key) if key == ownerKey then return selected end; return controller[key] end,
            __newindex = function(_, key, value) controller[key] = value end,
        })
    end
    local function loadContext()
        if context or loading or not alive then return end
        loading = true
        task.spawn(function()
            local ok, result = pcall(function()
                local knit = require(ReplicatedStorage.Packages.Knit)
                local modules = ReplicatedStorage.Controllers.AbilityController.Abilities
                return {Ball = knit.GetController("BallController"), Ability = knit.GetController("AbilityController"),
                    Network = knit.GetController("Network"), Movement = knit.GetController("MovementController"),
                    Modules = modules, Moves = require(modules), Zones = require(ReplicatedStorage.Shared.Tables.Zones),
                    Knit = knit}
            end)
            loading = false
            if not alive or ScriptUnloaded then return end
            if not ok then
                notify("controllers", "Game controllers are not ready. Re-enable the function after loading.")
                return
            end
            context = result
            if updateHooks then updateHooks() end
        end)
    end
    local function wantsHooks()
        return config.CopyTarget ~= "Default" or config.CopySlot ~= "Random"
            or config.SpecialTarget ~= "Default" or config.SwitchTarget ~= "Default"
    end
    local function installHook(module, handler)
        if not module or not module:IsA("ModuleScript") then return false end
        local ok, fn = pcall(require, module)
        if not ok or type(fn) ~= "function" then return false end
        local env = type(getgenv) == "function" and getgenv() or _G
        local registry = env.PRIMEStyleHooksV1
        if type(registry) ~= "table" then registry = {}; env.PRIMEStyleHooksV1 = registry end
        local node = registry[fn]
        if not node then
            if type(hookfunction) ~= "function" then
                notify("hooks", "Target selectors and Copy Slot require hookfunction in this executor.")
                return false
            end
            node = {}
            local installed, original = pcall(hookfunction, fn, function(...)
                if node.Handler then return node.Handler(node.Original, ...) end
                return node.Original(...)
            end)
            if not installed or type(original) ~= "function" then return false end
            node.Original = original
            registry[fn] = node
        end
        node.Owner, node.Handler = config, handler
        hooks[node] = true
        return true
    end
    local function clearHooks()
        for node in pairs(hooks) do
            if node.Owner == config then node.Handler, node.Owner = nil, nil end
        end
        table.clear(hooks)
    end
    local function moduleAt(path)
        local module = context and context.Modules
        for part in path:gmatch("[^.]+") do module = module and module:FindFirstChild(part) end
        return module
    end
    local function applyCopySlot(controller, index)
        local setting = controller.CopiedSetting
        local moves = setting and context.Moves[setting.Style]
        local chosen = moves and moves[index]
        local copy = context.Moves.Copycat and context.Moves.Copycat[1]
        if not chosen or not chosen.Ability or not copy then return false end
        setting.Index, setting.Ability = index, chosen.Ability
        copy.Ability = chosen.Multi and chosen.Ability or moduleAt("Copycat.Copy")
        for _, key in ipairs({"Name", "BallName", "RequiresBall", "Steal", "Jump"}) do copy[key] = chosen[key] end
        return true
    end
    updateHooks = function()
        clearHooks()
        if not context or not wantsHooks() or not alive then return end
        if config.CopyTarget ~= "Default" or config.CopySlot ~= "Random" then
            installHook(moduleAt("Copycat.Copy"), function(original, controller, ...)
                if not alive or ScriptUnloaded then return original(controller, ...) end
                local style = LocalPlayer:FindFirstChild("Style")
                if not style or style.Value ~= "Copycat" then return original(controller, ...) end
                local acquiring = controller.CopiedSetting == nil
                local input = controller
                if acquiring and config.CopyTarget ~= "Default" then
                    input = proxyController(controller, "LookingDirect", config.CopyTarget, "Enemy")
                    if not input then controller:ResetCD(1); return end
                end
                local results = table.pack(original(input, ...))
                if alive and not ScriptUnloaded and acquiring and controller.CopiedSetting and config.CopySlot ~= "Random" then
                    applyCopySlot(controller, tonumber(config.CopySlot))
                end
                return table.unpack(results, 1, results.n)
            end)
        end
        if config.SpecialTarget ~= "Default" then
            for _, path in ipairs({"Emperor.UltimatePass", "Gold.NeedlePass", "Dealer.BlinkDeal", "Genius.LockdownTarget"}) do
                installHook(moduleAt(path), function(original, controller, ...)
                    if not alive or ScriptUnloaded or config.SpecialTarget == "Default" then return original(controller, ...) end
                    if path == "Emperor.UltimatePass" and (controller.EmperorsReach or controller.UltimatePass) then return original(controller, ...) end
                    local input = proxyController(controller, "LookingAt", config.SpecialTarget, "Ally", nil,
                        path == "Dealer.BlinkDeal" and "Network" or "Pass")
                    if not input then
                        notify("pass-target", "Selected pass target is unavailable")
                        return original(controller, ...)
                    end
                    return original(input, ...)
                end)
            end
        end
        if config.SwitchTarget ~= "Default" then
            installHook(moduleAt("Switcher.Switch"), function(original, controller, ...)
                if not alive or ScriptUnloaded or config.SwitchTarget == "Default" then return original(controller, ...) end
                local limit = controller.Network.CharValues.HasBall and 95 or 130
                local input = proxyController(controller, "LookingAt", config.SwitchTarget, "Ally", limit)
                if not input then controller:ResetCD(2); return end
                return original(input, ...)
            end)
        end
    end

    local function refreshTargets()
        local lists = {Enemy = {"Default", "Nearest"}, Ally = {"Default", "Nearest"}}
        local ids = {}
        for _, player in ipairs(Players:GetPlayers()) do
            local side = sameSide(player, "Enemy") and "Enemy" or sameSide(player, "Ally") and "Ally"
            if side then
                local label = string.format("%s (@%s)", player.DisplayName, player.Name)
                lists[side][#lists[side] + 1], ids[label] = label, player.UserId
            end
        end
        for _, list in pairs(lists) do
            table.sort(list, function(a, b)
                if a == "Default" or b == "Default" then return a == "Default" and b ~= "Default" end
                if a == "Nearest" or b == "Nearest" then return a == "Nearest" and b ~= "Nearest" end
                return a:lower() < b:lower()
            end)
        end
        for _, pair in ipairs({{"CopyTarget", "Enemy"}, {"SpecialTarget", "Ally"}, {"SwitchTarget", "Ally"}}) do
            local key, side = pair[1], pair[2]
            local selection = config[key]
            local list = table.clone(lists[side])
            if selection ~= "Default" and selection ~= "Nearest" and not ids[selection] then
                list[#list + 1] = selection
                ids[selection] = targets[selection]
            end
            if options[key] then options[key]:SetValues(list) end
        end
        targets = ids
    end
    local function resetSteal()
        if steal.Connection then steal.Connection:Disconnect() end
        steal = {Seen = setmetatable({}, {__mode = "k"}), Next = 0, Protected = 0, Exhausted = 0, Count = 0}
    end
    local function observeDribble(track, existing)
        if steal.Seen[track] ~= nil then return end
        local id = track.Animation and track.Animation.AnimationId:match("%d+")
        local combo = id and dribbleIds[id]
        local special = id and specialIds[id]
        if not combo and not special then return end
        steal.Seen[track] = true
        local elapsed = track.TimePosition / math.max(0.01, math.abs(track.Speed))
        if track.Looped or existing and elapsed > 0.72 then return end
        local at = os.clock() - (existing and elapsed or 0)
        if special then
            steal.Protected = math.max(steal.Protected, at + math.max(0.8, track.Length / math.max(0.01, math.abs(track.Speed))))
            return
        end
        if at - (steal.LastDribble or -math.huge) > 4 then steal.Count = 0 end
        steal.LastDribble = at
        steal.Count = math.max(steal.Count + 1, combo)
        steal.Protected = math.max(steal.Protected, at + 0.72)
        local maximum = 3
        local zone = steal.Owner and steal.Owner:FindFirstChild("Zone")
        if context.Ball:BallPlayerZoneIsActive() and zone then maximum = context.Zones.ZoneDribbles[zone.Value] or 3 end
        if steal.Count >= maximum then steal.Count = 0; steal.Exhausted = at + 4 end
    end
    local function bindOwner(owner, character, humanoid)
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if steal.Owner == owner and steal.Character == character and steal.Animator == animator then return end
        local nextAttempt = steal.Next
        resetSteal()
        steal.Next = nextAttempt
        steal.Owner, steal.Character, steal.Animator, steal.Entered = owner, character, animator, os.clock()
        if animator then
            steal.Connection = animator.AnimationPlayed:Connect(function(track)
                steal.Seen[track] = nil
                observeDribble(track, false)
            end)
        end
    end
    local function canPlay()
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        local state = values and values:FindFirstChild("State")
        local tip = values and values:FindFirstChild("TipOff")
        local scoring = values and values:FindFirstChild("Scoring")
        return state and state.Value == "Playing" and not (tip and tip.Value) and not (scoring and scoring.Value)
    end
    local function updateSteal(now)
        if not config.SmartSteal or not context or now - lastSteal < 0.04 then return end
        lastSteal = now
        if not canPlay() or userInputService:GetFocusedTextBox() then resetSteal(); return end
        local ball, movement = context.Ball, context.Movement.States
        local own, root, humanoid = living(LocalPlayer)
        local owner = ball:GetPlayerPossessingBall()
        if not own or not owner or not sameSide(owner, "Enemy") then resetSteal(); return end
        local character, enemyRoot, enemyHumanoid = living(owner)
        if not character then return end
        bindOwner(owner, character, enemyHumanoid)
        if steal.Animator then
            for _, track in ipairs(steal.Animator:GetPlayingAnimationTracks()) do
                if track.IsPlaying then observeDribble(track, true) end
            end
        end
        if now < steal.Next or now - steal.Entered < 0.18 or now < steal.Protected
            or config.StealTiming == "Safe windows" and now >= steal.Exhausted then return end
        if movement.Stunned or movement.Stealing or movement.Ability or movement.NoWalk
            or context.Network.CharValues.HasBall or humanoid.Sit or humanoid.FloorMaterial == Enum.Material.Air
            or (own:FindFirstChild("IsRagdoll") and own.IsRagdoll.Value) or ball:NoAction()
            or ball:BallIFrameIsActive() or ball:BallTeamIFrameIsActive() then return end
        local position = ball:GetServerBallPosition()
        local delta = position + enemyRoot.AssemblyLinearVelocity * 0.08 - root.Position
        local horizontal = Vector3.new(delta.X, 0, delta.Z)
        if delta.Magnitude > config.StealRange or math.abs(delta.Y) > 7 or horizontal.Magnitude < 0.1
            or root.CFrame.LookVector:Dot(horizontal.Unit) < 0.35 then return end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {own, character}
        params.RespectCanCollide = true
        if Workspace:Raycast(root.Position, position - root.Position, params) then return end
        local mobile = PlayerGui:FindFirstChild("Mobile")
        local panel = mobile and mobile:FindFirstChild("NoBall")
        local button = panel and panel:FindFirstChild("Steal")
        if not button then return end
        local zone = LocalPlayer:FindFirstChild("Zone")
        steal.Next = now + math.max(0.4, zone and context.Zones.StealCooldowns[zone.Value] or 2.35)
        task.spawn(function()
            if config.SmartSteal and alive and not ScriptUnloaded then click(button) end
        end)
    end

    local function discoverCircles()
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name == "Circle" and not circles[gui] then
                local button = gui:FindFirstChild("Button")
                local group = button and button:FindFirstChild("CanvasGroup")
                local white = group and group:FindFirstChild("White")
                local center = group and group:FindFirstChild("Center")
                local frame = gui:FindFirstChild("Frame")
                local radius = frame and frame:FindFirstChild("Radius")
                local scale = radius and radius:FindFirstChildOfClass("UIScale")
                local soulButton = frame and frame:FindFirstChild("Button")
                local holder = frame and frame:FindFirstChild("Holder")
                if button and white and center and button:IsA("GuiButton") then
                    circles[gui] = {Kind = "Genius", Button = button, White = white, Center = center}
                elseif scale and soulButton and soulButton:IsA("GuiButton") and holder and holder:FindFirstChild("KeybindText") then
                    circles[gui] = {Kind = "SoulCatch", Button = soulButton, Scale = scale}
                end
            end
        end
    end
    local function updateCircles(dt)
        if not config.Genius and not config.SoulCatch then return end
        for gui, record in pairs(circles) do
            if not gui.Parent then circles[gui] = nil
            elseif not record.Fired and config[record.Kind] and visible(record.Button) then
                local ready, original
                if record.Kind == "Genius" then
                    local gap = (record.White.Rotation - record.Center.Rotation) % 360
                    ready = math.min(gap, 360 - gap) <= 2.8 or record.Gap and record.Gap < 30 and gap > 330
                    record.Gap = gap
                    if ready then original = record.Center.Rotation; record.Center.Rotation = record.White.Rotation end
                else
                    local scale = record.Scale.Scale
                    ready = math.abs(scale - 1) <= 0.04 or record.Previous and record.Previous > 1 and scale < 1
                    record.Previous = scale
                    if ready then original = scale; record.Scale.Scale = 1 end
                end
                if ready then
                    record.Fired = true
                    task.spawn(function()
                        if not alive or ScriptUnloaded or not config[record.Kind] or not gui.Parent then return end
                        local success = click(record.Button, "Activated")
                        if not success then
                            if record.Kind == "Genius" and record.Center.Parent then record.Center.Rotation = original
                            elseif record.Scale and record.Scale.Parent then record.Scale.Scale = original end
                            notify("skill-input", "Skillcheck button callbacks are unavailable in this executor")
                        end
                    end)
                end
            end
        end
    end

    local heartbeat, render
    updateRun = function()
        local active = config.SmartSteal or config.Genius or config.SoulCatch or wantsHooks()
        if config.SmartSteal or wantsHooks() then loadContext() end
        if active and not heartbeat then
            heartbeat = RunService.Heartbeat:Connect(function()
                if not alive or ScriptUnloaded then return end
                local now = os.clock()
                if now - lastTargets >= 1 then lastTargets = now; refreshTargets() end
                if (config.Genius or config.SoulCatch) and now - lastScan >= 0.1 then lastScan = now; discoverCircles() end
                local ok, err = pcall(function() updateSteal(now) end)
                if not ok then
                    notify("update", "A game state changed; automated actions were paused")
                    config.SmartSteal = false
                    if options.SmartSteal then options.SmartSteal:SetValue(false) end
                end
            end)
        elseif not active and heartbeat then
            heartbeat:Disconnect(); heartbeat = nil
        end
        if (config.Genius or config.SoulCatch) and not render then
            render = RunService.RenderStepped:Connect(function(dt)
                if alive and not ScriptUnloaded then pcall(updateCircles, dt) end
            end)
            discoverCircles()
        elseif not config.Genius and not config.SoulCatch and render then render:Disconnect(); render = nil end
        if not config.SmartSteal then resetSteal() end
        updateHooks()
    end
    local function toggle(tab, id, key, title, description)
        options[key] = tab:AddToggle(id, {Title = title, Description = description, Default = false, Callback = function(value)
            config[key] = value == true
            updateRun()
        end})
    end
    local function dropdown(tab, id, key, title, values)
        options[key] = tab:AddDropdown(id, {Title = title, Values = values, Default = config[key], Callback = function(value)
            config[key] = value
            updateRun()
        end})
    end
    for _, folder in ipairs(assets and assets:GetChildren() or {}) do
        if folder.Name == "Animations" then
            for _, group in ipairs(folder:GetChildren()) do
                if group.Name == "Dribbles" or group.Name:find("Combo", 1, true) then
                    for _, animation in ipairs(group:GetChildren()) do
                        if animation:IsA("Animation") then
                            local id = animation.AnimationId:match("%d+")
                            if id then dribbleIds[id] = group.Name == "Dribbles" and 1 or math.max(1, #animation.Name - 1) end
                        end
                    end
                end
            end
        elseif folder.Name == "StyleAnimations" then
            for _, animation in ipairs(folder:GetDescendants()) do
                if animation:IsA("Animation") and not animation.Name:lower():find("ball", 1, true) then
                    local id = animation.AnimationId:match("%d+")
                    if id then specialIds[id] = true end
                end
            end
        end
    end
    Tabs.Main:AddSection("Smart Steal", "Right")
    toggle(Tabs.Main, "SmartAutoSteal", "SmartSteal", "[Smart] Auto Steal", "Uses the game Steal button when the carrier is in range and ball protection has ended")
    options.StealRange = Tabs.Main:AddSlider("SmartStealRange", {Title = "Steal Range", Default = 14, Min = 5, Max = 17, Rounding = 1,
        Callback = function(value) config.StealRange = math.clamp(value, 5, 17) end})
    dropdown(Tabs.Main, "SmartStealTiming", "StealTiming", "Steal Timing", {"Balanced", "Safe windows"})
    local styleTab = Tabs.Styles or Tabs.EventsFarm
    styleTab:AddSection("Skillchecks")
    toggle(styleTab, "GeniusAutoPerfectLockdown", "Genius", "Genius Auto Perfect Lockdown", "Completes each Lockdown circle once at the alignment point")
    toggle(styleTab, "TatlisV2AutoSoulCatch", "SoulCatch", "Tatlis V2 Auto Soul Catch Skillcheck", "Completes the Soul Catch ring through its native button callback")
    styleTab:AddSection("Copycat")
    dropdown(styleTab, "CopycatCopyTarget", "CopyTarget", "Copycat Copy Target Selector", {"Default", "Nearest"})
    dropdown(styleTab, "CopycatCopySlot", "CopySlot", "[Experimental] Copycat Copy Slot", {"Random", "1", "2"})
    styleTab:AddSection("Pass / Switch")
    dropdown(styleTab, "SpecialPassTarget", "SpecialTarget", "Special Pass Target", {"Default", "Nearest"})
    dropdown(styleTab, "SwitcherSwitchTarget", "SwitchTarget", "Switcher Switch Target", {"Default", "Nearest"})
    refreshTargets()
    connect(Players.PlayerAdded, refreshTargets)
    connect(Players.PlayerRemoving, function() task.defer(function() if alive then refreshTargets() end end) end)
    connect(LocalPlayer:GetPropertyChangedSignal("Team"), function()
        resetSteal()
        refreshTargets()
    end)
    connect(LocalPlayer.CharacterRemoving, function()
        resetSteal()
        table.clear(circles)
    end)
    RegisterUnloadCallback(function()
        alive = false
        clearHooks()
        resetSteal()
        if heartbeat then heartbeat:Disconnect() end
        if render then render:Disconnect() end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(circles)
    end)
end

end}
