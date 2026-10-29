return {Exports={"Options","NoCooldownEnabled","NoCooldownConnection","NoStunEnabled","NoStunConnection","NoRagdollEnabled","NoRagdollConnection","AutoBlockEnabled","AutoBlockConnection","AutoPassEnabled","AutoPassConnection","AutoBlockDunkEnabled","AutoBlockDunkConnection","SpeedBoostEnabled","SpeedBoostConnection","SpeedBoostValue","JumpBoostEnabled","JumpBoostConnection","JumpBoostValue","ShotPowerEnabled","ShotPowerConnection","ShotPowerMultiplier","ApplyShotPowerModifier","InfinitePumpFakesEnabled","InfinitePumpFakesThread","BallController","OriginalGetMaxPumpFakes","FOVEnabled","FOVConnection","FOVValue","AntiSlipEnabled","AntiSlipConnection","OriginalCameraMaxZoomDistance","OriginalFieldOfView","MainSection","GetCurrentBall","NoCooldownControllerInstance","FindNoCooldownController","executorName","noCooldownUnsupportedExecutor","noCooldownInputBlocker","setNoCooldownInputBlocked","lockNoAbilityCooldown","CosmeticAssets","ActiveCosmeticContainer","ActiveCosmeticTrove","SelectedCosmeticName","CosmeticWeld","SetCosmeticVfxEnabled","NewCosmeticTrove","setupRankedBadge","setupMascot","attachPartsByName","attachHandleToHead","CosmeticHandlers","CollectCosmeticNames","DestroyActiveCosmetic","AttachFallbackCosmetic","EquipCosmetic","cosmeticDropdown","cosmeticRefreshQueued","QueueCosmeticRefresh"},Init=function()
if not GuiParent or not Tabs then return end
Options = NexusUI.Options

NoCooldownEnabled = false
NoCooldownConnection = nil
NoStunEnabled = false
NoStunConnection = nil
NoRagdollEnabled = false
NoRagdollConnection = nil
AutoBlockEnabled = false
AutoBlockConnection = nil
AutoPassEnabled = false
AutoPassConnection = nil
AutoBlockDunkEnabled = false
AutoBlockDunkConnection = nil
SpeedBoostEnabled = false
SpeedBoostConnection = nil
SpeedBoostValue = 15
JumpBoostEnabled = false
JumpBoostConnection = nil
JumpBoostValue = 80
ShotPowerEnabled = false
ShotPowerConnection = nil
ShotPowerMultiplier = 1.5
-- BEGIN SHARED SHOT POWER
function ApplyShotPowerModifier(velocity, multiplier, targetSpeed)
    if type(targetSpeed) == "number" and targetSpeed == targetSpeed and targetSpeed > 0 and targetSpeed < math.huge then
        local magnitude = velocity.Magnitude
        if magnitude > 0.0001 then return velocity * (targetSpeed / magnitude) end
        return velocity * 0
    end
    local factor = multiplier or ShotPowerMultiplier or 1.5
    if type(factor) ~= "number" or factor ~= factor or math.abs(factor) == math.huge then factor = 1.5 end
    factor = math.max(0.5, math.min(3, factor))
    return velocity * factor
end
-- END SHARED SHOT POWER
InfinitePumpFakesEnabled = false
InfinitePumpFakesThread = nil
BallController = nil
OriginalGetMaxPumpFakes = nil
FOVEnabled = false
FOVConnection = nil
FOVValue = 90
AntiSlipEnabled = false
AntiSlipConnection = nil
OriginalCameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance
OriginalFieldOfView = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70

local function activateGuiButton(button, signalOnly)
    if not button or not button:IsA("GuiButton") then return false end
    if signalOnly then
        return type(firesignal) == "function" and pcall(firesignal, button.MouseButton1Click) or false
    end
    local activated = false
    if type(getconnections) == "function" then
        local success, connections = pcall(getconnections, button.MouseButton1Click)
        for _, connection in ipairs(success and type(connections) == "table" and connections or {}) do
            if type(connection.Function) == "function" then
                local ok = pcall(connection.Function)
                activated = activated or ok
            end
        end
    end
    if activated then return true end
    return type(firesignal) == "function" and pcall(firesignal, button.MouseButton1Click) or false
end

local function findGuiButton(name, preferred)
    if preferred and preferred:IsA("GuiButton") then return preferred end
    for _, descendant in ipairs(PlayerGui:GetDescendants()) do
        if descendant:IsA("GuiButton") and descendant.Name:lower() == name:lower() then
            return descendant
        end
    end
end

RegisterUnloadCallback(function()
    waitingForKey = false
    LocalPlayer.CameraMaxZoomDistance = OriginalCameraMaxZoomDistance

    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = OriginalFieldOfView
    end

    for _, child in ipairs(GuiParent:GetChildren()) do
        if child.Name == "NexusNotify" then
            child:Destroy()
        end
    end
end)

MainSection = Tabs.Main:AddSection("Main", "Left")

-- Steal Support: remote dribble counters are NOT replicated in this Place.
-- All displayed cooldowns are estimates from ordinary character animations.
do
    local enabled = false
    local connections, records, roundConnections = {}, {}, {}
    local lastOwner
    local animationInfo, specialAnimations = {}, {}
    -- Passive copies of notifications already delivered to the normal client.
    -- Never require game code or request a fresh BallState snapshot.
    local ballEvents = {}
    local ballSnapshot = {}
    -- Verified in this Place's Shared.Tables.Zones. Other PRIME features may
    -- modify the loaded Zones table locally; those edits do not affect opponents.
    local zoneDribbles = {StreetDribbler = 4, Perfectionist = 4, EmperorVision = 4,
        GoldVision = 4, Senses = 4, Darkness = 4, ["777"] = 5,
        Ordinary = 4, Shock = 4, Oldschool = 5, Samurai = 2}
    local heartbeat
    local lastUpdate = 0
    local GREEN = Color3.fromRGB(90, 235, 135)
    local RED = Color3.fromRGB(255, 105, 105)
    local AMBER = Color3.fromRGB(255, 205, 95)
    local DIM = Color3.fromRGB(205, 210, 220)

    -- BEGIN STEAL SUPPORT STATE (pure functions; tested outside Studio)
    local function newDribbleState(now)
        return {used = 0, known = false, readyAt = now + 4,
            db = now, protectedUntil = 0, specialUntil = 0, ambiguousUntil = 0}
    end

    local function advanceDribbleState(state, now)
        if now >= state.readyAt and now >= state.specialUntil then state.known = true end
        if now > state.db + 3.5 then state.used = 0 end
    end

    local function observeDribble(state, now, maxLow, maxHigh, comboCount)
        advanceDribbleState(state, now)
        state.used = math.max(state.used + 1, comboCount or 1)
        state.protectedUntil = math.max(state.protectedUntil, now + 0.72)
        state.readyAt = now + 4
        if state.used >= maxHigh then
            state.used = 0
            state.db = now + 4
            state.known = true
            state.ambiguousUntil = 0
        else
            state.db = now + 0.5
            state.ambiguousUntil = maxLow ~= maxHigh and state.used >= maxLow and now + 4 or 0
        end
    end

    local function dribbleStatus(state, now, owner, opponent, protected, low, high, protectionKnown)
        advanceDribbleState(state, now)
        local limit = low == high and tostring(high) or (tostring(low) .. "-" .. tostring(high))
        if state.specialUntil > now then return "SPECIAL / CD UNKNOWN", "amber" end
        if owner and (protected or state.protectedUntil > now) then return "PROTECTED / DRIBBLING", "red" end
        if state.ambiguousUntil > now then return "DRIBBLE CD ? (ZONE)", "amber" end
        if not state.known then return "DRIBBLE ? / " .. limit, "amber" end
        local remaining = state.db - now
        if remaining > 0 then
            if owner and opponent and protectionKnown == false then
                return string.format("DRIBBLE CD ~%.1fs / PROTECTION ?", remaining), "amber"
            end
            local prefix = owner and opponent and "STEAL WINDOW" or "DRIBBLE CD"
            return string.format("%s ~%.1fs", prefix, remaining), owner and opponent and "green" or "amber"
        end
        return string.format("DRIBBLE READY ~%d / %s", math.max(0, high - state.used), limit), "dim"
    end
    -- END STEAL SUPPORT STATE

    local function connect(list, signal, callback)
        local connection = signal:Connect(callback)
        table.insert(list, connection)
        return connection
    end

    local function disconnectAll(list)
        for _, connection in ipairs(list) do connection:Disconnect() end
        table.clear(list)
    end

    local function animationId(value)
        return tostring(value or ""):match("%d+")
    end

    local function rebuildAnimationMap()
        table.clear(animationInfo)
        table.clear(specialAnimations)
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        local animations = assets and assets:FindFirstChild("Animations")
        if animations then
            for _, folder in ipairs(animations:GetChildren()) do
                if folder.Name == "Dribbles" or folder.Name:find("Combo", 1, true) then
                    for _, animation in ipairs(folder:GetChildren()) do
                        if animation:IsA("Animation") then
                            local id = animationId(animation.AnimationId)
                            if id then
                                animationInfo[id] = folder.Name == "Dribbles" and 1 or math.max(1, #animation.Name - 1)
                            end
                        end
                    end
                end
            end
        end
        local styles = assets and assets:FindFirstChild("StyleAnimations")
        if styles then
            for _, animation in ipairs(styles:GetDescendants()) do
                if animation:IsA("Animation") and not animation.Name:find("Ball", 1, true) then
                    local id = animationId(animation.AnimationId)
                    if id then specialAnimations[id] = true end
                end
            end
        end
    end

    local function readBallState(method)
        if method == "getCharacterPossessingBall" then
            return ballSnapshot.player and ballSnapshot.player.Character
        elseif method == "ballPlayerZoneIsActive" then return ballSnapshot.inZone
        elseif method == "ballIFrameIsActive" then
            return type(ballSnapshot.iframe) == "number" and tick() < ballSnapshot.iframe
        elseif method == "ballTeamIFrameIsActive" then
            return type(ballSnapshot.teamIframe) == "number" and tick() < ballSnapshot.teamIframe
        end
    end

    local function bindBallEvents()
        disconnectAll(ballEvents)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local folder = remotes and remotes:FindFirstChild("BallState")
        if not folder then return end
        local handlers = {
            SetCurrentBallPlayer = function(player)
                ballSnapshot.player = player
                ballSnapshot.inZone = nil
            end,
            SetBallPlayerInZone = function(active) ballSnapshot.inZone = active end,
            SetBallIFrame = function(timestamp)
                if type(timestamp) == "number" then ballSnapshot.iframe = timestamp end
            end,
            SetBallTeamIFrame = function(timestamp)
                if type(timestamp) == "number" then ballSnapshot.teamIframe = timestamp end
            end,
        }
        for name, handler in pairs(handlers) do
            local remote = folder:FindFirstChild(name)
            if remote and remote:IsA("RemoteEvent") then
                connect(ballEvents, remote.OnClientEvent, handler)
            end
        end
    end

    local function valueOf(player, character, name)
        for _, object in ipairs({character, player}) do
            local value = object:GetAttribute(name)
            if value ~= nil then return value end
            local child = object:FindFirstChild(name)
            if child and child:IsA("ValueBase") then return child.Value end
        end
    end

    local function maxDribbles(player, character, owner)
        local zone = player:FindFirstChild("Zone")
        local zoneName = zone and zone:IsA("StringValue") and zone.Value
        if not zoneName then return 2, 5 end
        local max = zoneName and zoneDribbles and zoneDribbles[zoneName] or 3
        local active = valueOf(player, character, "InZone")
        if active == nil and owner then active = readBallState("ballPlayerZoneIsActive") end
        if active == false then return 3, 3 end
        if zoneName == "777" then
            local rng = valueOf(player, character, "ZoneRNG")
            if rng ~= nil then max = rng == 3 and max or 3
            else return 3, math.max(3, max) end
        end
        if active == true then return max, max end
        return math.min(3, max), math.max(3, max)
    end

    local function clearCharacter(record)
        disconnectAll(record.characterConnections)
        if record.gui then record.gui:Destroy() end
        record.gui, record.label, record.character, record.animator = nil, nil, nil, nil
        record.seen = setmetatable({}, {__mode = "k"})
        record.state = newDribbleState(os.clock())
    end

    local function makeMarker(record, adornee)
        local gui = Instance.new("BillboardGui")
        gui.Name = "PRIME_StealSupport"
        gui.Adornee = adornee
        gui.Size = UDim2.fromOffset(320, 24)
        gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 600
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Font = Enum.Font.GothamBold
        label:SetAttribute("KeepFont", true)
        label.TextSize = 13
        label.TextScaled = false
        label.TextWrapped = false
        label.TextColor3 = AMBER
        label.TextStrokeTransparency = 0.6
        label.Text = "DRIBBLE ?"
        label.Parent = gui
        gui.Parent = GuiParent
        record.gui, record.label = gui, label
    end

    local function observeTrack(record, track, existing)
        if not enabled or not record.character then return end
        local position = track.TimePosition
        local previous = record.seen[track]
        -- A stopped track can be reused for the next dribble; Play fires again.
        if existing and previous ~= nil then return end
        record.seen[track] = position
        local id = track.Animation and animationId(track.Animation.AnimationId)
        local combo = id and animationInfo[id]
        local now = os.clock()
        if combo then
            -- Do not count looped movement/ball animations or stale tracks.
            if track.Looped or (existing and position / math.max(0.01, math.abs(track.Speed)) > 0.72) then return end
            local character = record.character
            local owner = readBallState("getCharacterPossessingBall") == character
            local low, high = maxDribbles(record.player, character, owner)
            local eventTime = existing and now - position / math.max(0.01, math.abs(track.Speed)) or now
            observeDribble(record.state, eventTime, low, high, combo)
        elseif id and specialAnimations[id] then
            -- Ability animations can enable automatic dribbles/other protections.
            record.state.known = false
            record.state.used = 0
            record.state.specialUntil = now + 7
            record.state.readyAt = now + 7
            record.state.db = now
            record.state.ambiguousUntil = 0
        end
    end

    local function bindAnimator(record, animator)
        if record.animator == animator then return end
        if record.animationConnection then record.animationConnection:Disconnect() end
        record.state = newDribbleState(os.clock())
        record.animator = animator
        record.animationConnection = connect(record.characterConnections, animator.AnimationPlayed, function(track)
            observeTrack(record, track, false)
        end)
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do observeTrack(record, track, true) end
    end

    local function bindCharacter(record, character)
        clearCharacter(record)
        record.character = character
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator then bindAnimator(record, animator) end
        connect(record.characterConnections, character.DescendantAdded, function(child)
            if child:IsA("Animator") and child.Parent:IsA("Humanoid") then bindAnimator(record, child) end
        end)
    end

    local function removePlayer(player)
        local record = records[player]
        if not record then return end
        clearCharacter(record)
        disconnectAll(record.connections)
        records[player] = nil
    end

    local function addPlayer(player)
        if player == LocalPlayer or records[player] then return end
        local record = {player = player, connections = {}, characterConnections = {}}
        records[player] = record
        clearCharacter(record)
        connect(record.connections, player.CharacterAdded, function(character) bindCharacter(record, character) end)
        connect(record.connections, player.CharacterRemoving, function() clearCharacter(record) end)
        if player.Character then bindCharacter(record, player.Character) end
    end

    local function resetRound()
        local now = os.clock()
        lastOwner = nil
        table.clear(ballSnapshot)
        rebuildAnimationMap()
        for _, record in pairs(records) do
            record.state = newDribbleState(now)
            record.seen = setmetatable({}, {__mode = "k"})
            if record.label then record.label.Text = "NEW ROUND | DRIBBLE ?" end
        end
    end

    local function bindRoundSignals(values)
        disconnectAll(roundConnections)
        resetRound()
        if not values then return end
        local state = values:FindFirstChild("State")
        if state then connect(roundConnections, state:GetPropertyChangedSignal("Value"), resetRound) end
        for _, name in ipairs({"TipOff", "PositionReset"}) do
            local value = values:FindFirstChild(name)
            if value then
                connect(roundConnections, value:GetPropertyChangedSignal("Value"), function()
                    if value.Value == true then resetRound() end
                end)
            end
        end
        local timer = values:FindFirstChild("Timer")
        if timer then
            local previous = timer.Value
            connect(roundConnections, timer:GetPropertyChangedSignal("Value"), function()
                local current = timer.Value
                -- Covers a restarted match even if State stays Playing.
                if current > previous + 5 then resetRound() end
                previous = current
            end)
        end
    end

    local function stop()
        enabled = false
        if heartbeat then heartbeat:Disconnect() heartbeat = nil end
        disconnectAll(ballEvents)
        disconnectAll(connections)
        disconnectAll(roundConnections)
        for player in pairs(records) do removePlayer(player) end
        table.clear(ballSnapshot)
        lastOwner = nil
    end

    local function start()
        stop()
        enabled = true
        rebuildAnimationMap()
        for _, player in ipairs(Players:GetPlayers()) do addPlayer(player) end
        connect(connections, Players.PlayerAdded, addPlayer)
        connect(connections, Players.PlayerRemoving, removePlayer)
        bindRoundSignals(ReplicatedStorage:FindFirstChild("GameValues"))
        bindBallEvents()
        connect(connections, ReplicatedStorage.ChildAdded, function(child)
            if child.Name == "GameValues" then bindRoundSignals(child) end
            if child.Name == "Remotes" then bindBallEvents() end
        end)
        heartbeat = RunService.Heartbeat:Connect(function()
            if ScriptUnloaded then stop() return end
            local now = os.clock()
            if now - lastUpdate < 0.05 then return end
            lastUpdate = now
            local owner = readBallState("getCharacterPossessingBall")
            if owner ~= lastOwner then
                -- Passing/losing the ball can coincide with a stun counter reset.
                -- Discard old chain counts instead of carrying them into a new possession.
                if lastOwner then
                    for _, record in pairs(records) do
                        if record.character == lastOwner or record.character == owner then
                            record.state = newDribbleState(now)
                        end
                    end
                end
                lastOwner = owner
            end
            local protected = readBallState("ballIFrameIsActive") == true
            local ownerPlayer = owner and Players:GetPlayerFromCharacter(owner)
            if ownerPlayer and ownerPlayer.Team == LocalPlayer.Team then
                protected = protected or readBallState("ballTeamIFrameIsActive") == true
            end
            local gameValues = ReplicatedStorage:FindFirstChild("GameValues")
            local gameState = gameValues and gameValues:FindFirstChild("State")
            local playing = gameState and gameState.Value == "Playing"
            for player, record in pairs(records) do
                local character = record.character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local adornee = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
                local visible = character and character.Parent and humanoid and humanoid.Health > 0 and adornee
                if visible then
                    if not record.gui or not record.gui.Parent then makeMarker(record, adornee) end
                    record.gui.Adornee = adornee
                    record.gui.Enabled = true
                    local isOwner = owner == character
                    local opponent = playing and LocalPlayer.Team and player.Team and player.Team ~= LocalPlayer.Team
                        and LocalPlayer.Team.Name ~= "Visitor" and player.Team.Name ~= "Visitor"
                    local low, high = maxDribbles(player, character, isOwner)
                    local protectionKnown = type(ballSnapshot.iframe) == "number"
                    local text, color = dribbleStatus(record.state, now, isOwner, opponent, protected, low, high, protectionKnown)
                    if not next(animationInfo) or not record.animator then
                        text, color = "DRIBBLE DATA UNAVAILABLE", "amber"
                    elseif not playing then
                        text, color = "WAITING FOR ROUND", "dim"
                    end
                    record.label.Text = (isOwner and "BALL | " or "") .. text
                    record.label.TextColor3 = ({green = GREEN, red = RED, amber = AMBER, dim = DIM})[color]
                elseif record.gui then record.gui.Enabled = false end
            end
        end)
    end

    Tabs.Main:AddToggle("StealSupport", {
        Title = "Steal Support",
        Description = "Passive animation-based Dribble estimates (~); protection stays unknown until observed",
        Default = false,
        Callback = function(value) if value and not ScriptUnloaded then start() else stop() end end,
    })
    RegisterUnloadCallback(stop)
end



local perfectShotLock
function GetCurrentBall(withPhysicsLock)
    local reference = ReplicatedStorage:FindFirstChild("Basketball")
    if not reference or not reference:IsA("ObjectValue") then
        return nil
    end

    local ball = reference.Value
    if ball and ball:IsA("BasePart") and ball:IsDescendantOf(Workspace) then
        if withPhysicsLock then return ball, perfectShotLock and perfectShotLock.ball == ball and os.clock() < perfectShotLock.expires or false end
        return ball
    end
    return nil
end

local ballStateClient
local function localPlayerHasBall()
    if not ballStateClient then
        local ok, result = pcall(function()
            local controller = ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("BallController")
            return require(controller:WaitForChild("BallStateClient"))
        end)
        if ok then ballStateClient = result end
    end
    if ballStateClient and type(ballStateClient.localPlayerPossessesBall) == "function" then
        local ok, result = pcall(ballStateClient.localPlayerPossessesBall, ballStateClient)
        return ok and result == true
    end
    return false
end

NoCooldownControllerInstance = nil

function FindNoCooldownController()
    if NoCooldownControllerInstance then return NoCooldownControllerInstance end
    if type(getgc) ~= "function" then return nil end
    pcall(function()
        for _, obj in pairs(getgc(true)) do
            if type(obj) == "table" then
                if rawget(obj, "CDS") and rawget(obj, "Name") == "AbilityController" then
                    NoCooldownControllerInstance = obj
                    return
                end
            end
        end
    end)
    return NoCooldownControllerInstance
end

Tabs.Main:AddToggle("NoAbilityCooldown", {
    Title = "No Ability Cooldown",
    Description = "Remove cooldowns from abilities",
    Default = false,
    Callback = function(Value)
        NoCooldownEnabled = Value
        if Value then
            if NoCooldownConnection then
                NoCooldownConnection:Disconnect()
                NoCooldownConnection = nil
            end
            NoCooldownConnection = TrackScriptConnection(RunService.Heartbeat:Connect(function()
                if not NoCooldownEnabled then return end
                local instance = FindNoCooldownController()
                if instance and instance.CDS then
                    for i = 1, 4 do
                        if instance.CDS[i] then
                            instance.CDS[i] = 0
                        end
                    end
                end
            end))
        else
            if NoCooldownConnection then
                NoCooldownConnection:Disconnect()
                NoCooldownConnection = nil
            end
        end
    end
})

executorName = ""
pcall(function()
    if type(identifyexecutor) == "function" then
        executorName = string.lower(tostring(identifyexecutor()))
    end
end)

noCooldownUnsupportedExecutor = executorName:find("xeno") or executorName:find("solara")
noCooldownInputBlocker = nil

-- No Ability Cooldown is never locked (any tier, any executor). These stay as
-- no-op stubs so external callers (e.g. the loader) do not error.
function setNoCooldownInputBlocked(blocked) end
function lockNoAbilityCooldown(reason, useBanner) end

if noCooldownUnsupportedExecutor then
    NexusUI:Notify({
        Title = "PRIME",
        Content = "No Ability Cooldown may not work on your executor",
        Duration = 5
    })
end

Tabs.Main:AddToggle("NoStun", {
    Title = "No Stun",
    Description = "Prevents stun effects",
    Default = false,
    Callback = function(Value)
        NoStunEnabled = Value
        if Value then
            local function RemoveStunEffects()
                if not NoStunEnabled then return end
                if LocalPlayer.Character then
                    for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                        if v.Name:lower():find("stun") or v.Name:lower():find("impact") or v.Name:lower():find("dizzy") then
                            pcall(function() v:Destroy() end)
                        end
                    end
                    if LocalPlayer.Character:GetAttribute("Stunned") then
                        LocalPlayer.Character:SetAttribute("Stunned", false)
                    end
                    if LocalPlayer.Character:GetAttribute("StunTime") then
                        LocalPlayer.Character:SetAttribute("StunTime", 0)
                    end
                end
            end
            NoStunConnection = TrackScriptConnection(RunService.Heartbeat:Connect(RemoveStunEffects))
        else
            if NoStunConnection then
                NoStunConnection:Disconnect()
                NoStunConnection = nil
            end
        end
    end
})

Tabs.Main:AddToggle("NoRagdoll", {
    Title = "No Ragdoll",
    Description = "Prevents ragdoll effects",
    Default = false,
    Callback = function(Value)
        NoRagdollEnabled = Value
        if Value then
            local function RemoveRagdoll()
                if not NoRagdollEnabled then return end
                if not LocalPlayer.Character then return end
                local isRagdoll = LocalPlayer.Character:FindFirstChild("IsRagdoll")
                if isRagdoll and isRagdoll:IsA("BoolValue") then
                    if isRagdoll.Value == true then
                        isRagdoll.Value = false
                    end
                end
                local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and hrp.Anchored then
                    hrp.Anchored = false
                end
                if hrp and hrp.AssemblyLinearVelocity.Magnitude > 100 then
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
                local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
                if humanoid then
                    if humanoid.PlatformStand then
                        humanoid.PlatformStand = false
                    end
                    if humanoid.Sit then
                        humanoid.Sit = false
                    end
                end
            end
            NoRagdollConnection = TrackScriptConnection(RunService.Heartbeat:Connect(RemoveRagdoll))
        else
            if NoRagdollConnection then
                NoRagdollConnection:Disconnect()
                NoRagdollConnection = nil
            end
        end
    end
})


Tabs.Main:AddToggle("AutoBlock", {
    Title = "Auto Block",
    Description = "auto ball block",
    Default = false,
    Callback = function(Value)
        AutoBlockEnabled = Value
        if Value then
            local AUTO_BLOCK_RANGE = 15.5
            local COOLDOWN = 0.1
            local lastBlockTime = 0
            local isBlocking = false
            local blockedAnimationIds = {

                "rbxassetid://111975541117141",
                "rbxassetid://76228113424835",
                "rbxassetid://77325057015467",
                "rbxassetid://81077726192701",
                "rbxassetid://97212719145496",
                "rbxassetid://93637049934243",
                "rbxassetid://86845329217363",
                "rbxassetid://85237775854620",
                "rbxassetid://76799100204102",
                "rbxassetid://140044737112890",
                "rbxassetid://75206041339842",
                "rbxassetid://93426416285702",
                "rbxassetid://92462901193976",
                "rbxassetid://97638974924509",
                "rbxassetid://103324749935306",
                "rbxassetid://80419239450998",
                "rbxassetid://83196870153629",
                "rbxassetid://82883842626848",
                "rbxassetid://135837817164001",
                "rbxassetid://134971996964091",
                "rbxassetid://139790361616736",
                "rbxassetid://98718932626065",
                "rbxassetid://90905743250824",
                "rbxassetid://112630239907251",    
                "rbxassetid://125858081984425",
                "rbxassetid://89731716334782",
                "rbxassetid://93824649798557",
                "rbxassetid://115245242244708",
                "rbxassetid://87091601850111",
                "rbxassetid://86466269548335",
                "rbxassetid://85842414472420",
                "rbxassetid://122154195183566",
                "rbxassetid://101759701167020",
                "rbxassetid://91149657331993",
                "rbxassetid://131932666588221",
                "rbxassetid://100842460034279",
                "rbxassetid://94452665372956",
                "rbxassetid://83037726599973",
                "rbxassetid://131498997481190",
                "rbxassetid://115763852918123",
                "rbxassetid://139765328348537"

            }

            
            local function Jump()
                local char = LocalPlayer.Character
                if not char then return false end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if not humanoid then return false end
                if not isBlocking and humanoid.FloorMaterial ~= Enum.Material.Air and tick() - lastBlockTime > COOLDOWN then
                    isBlocking = true
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    lastBlockTime = tick()
                    task.delay(0.2, function() isBlocking = false end)
                    return true
                end
            end

            local function HasBlockingAnimation(player)
                local char = player and player.Character
                if not char then return false end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if not humanoid then return false end
                local animator = humanoid:FindFirstChildOfClass("Animator")
                if not animator then return false end

                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    if track and track.Animation then
                        local animationId = track.Animation.AnimationId
                        for _, blockedId in ipairs(blockedAnimationIds) do
                            if animationId == blockedId then
                                return true
                            end
                        end
                    end
                end

                return false
            end
            
            AutoBlockConnection = TrackScriptConnection(RunService.Heartbeat:Connect(function()
                if not AutoBlockEnabled then return end
                local ball = GetCurrentBall()
                if not ball then return end
                local char = LocalPlayer.Character
                if not char then return end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then return end

                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Team ~= LocalPlayer.Team and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        local dist = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
                        if dist <= AUTO_BLOCK_RANGE and HasBlockingAnimation(p) then
                            Jump()
                            return
                        end
                    end
                end
            end))
        else
            if AutoBlockConnection then
                AutoBlockConnection:Disconnect()
                AutoBlockConnection = nil
            end
        end
    end
})

Tabs.Main:AddToggle("AutoPass", {
    Title = "Auto Pass",
    Description = "Passes to an open teammate when a defender is close",
    Default = false,
    Callback = function(Value)
        AutoPassEnabled = Value
        if AutoPassConnection then
            AutoPassConnection:Disconnect()
            AutoPassConnection = nil
        end
        if not Value then return end

        local lastCheck = 0
        local lastPass = 0
        AutoPassConnection = TrackScriptConnection(RunService.Heartbeat:Connect(function()
            local now = os.clock()
            if not AutoPassEnabled or now - lastCheck < 0.08 or now - lastPass < 1.05 then return end
            lastCheck = now
            if not localPlayerHasBall() or not LocalPlayer.Team or LocalPlayer.Team.Name == "Visitor" then return end

            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local camera = Workspace.CurrentCamera
            if not root or not camera then return end

            local threatened = false
            for _, player in ipairs(Players:GetPlayers()) do
                local enemyRoot = player ~= LocalPlayer and player.Team ~= LocalPlayer.Team and player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                if enemyRoot and (root.Position - enemyRoot.Position).Magnitude <= 18 then
                    threatened = true
                    break
                end
            end
            if not threatened then return end

            local target
            local bestScreenDistance = math.huge
            local screenCenter = camera.ViewportSize / 2
            for _, player in ipairs(Players:GetPlayers()) do
                local teammateRoot = player ~= LocalPlayer and player.Team == LocalPlayer.Team and player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                if teammateRoot and (root.Position - teammateRoot.Position).Magnitude <= 180 then
                    local point, visible = camera:WorldToViewportPoint(teammateRoot.Position)
                    local screenDistance = (Vector2.new(point.X, point.Y) - screenCenter).Magnitude
                    if visible and screenDistance < bestScreenDistance then
                        target = player.Character
                        bestScreenDistance = screenDistance
                    end
                end
            end
            if not target then return end

            local targetRoot = target:FindFirstChild("HumanoidRootPart")
            for _, player in ipairs(Players:GetPlayers()) do
                local enemyRoot = player ~= LocalPlayer and player.Team ~= LocalPlayer.Team and player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                if enemyRoot and (targetRoot.Position - enemyRoot.Position).Magnitude <= 14 then return end
            end

            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character, target, GetCurrentBall()}
            if Workspace:Raycast(root.Position, targetRoot.Position - root.Position, params) then return end

            local mobile = PlayerGui:FindFirstChild("Mobile")
            local ball = mobile and mobile:FindFirstChild("Ball")
            local button = findGuiButton("Pass", ball and ball:FindFirstChild("Pass"))
            if activateGuiButton(button) then lastPass = now end
        end))
    end,
})

Tabs.Main:AddToggle("AutoBlockDunk", {
    Title = "Auto Block Dunk",
    Description = "Jumps when a nearby opponent starts a dunk",
    Default = false,
    Callback = function(Value)
        AutoBlockDunkEnabled = Value
        if AutoBlockDunkConnection then
            AutoBlockDunkConnection:Disconnect()
            AutoBlockDunkConnection = nil
        end
        if not Value then return end

        local dunkAnimations = {
            ["rbxassetid://80419239450998"] = true, ["rbxassetid://83196870153629"] = true,
            ["rbxassetid://82883842626848"] = true, ["rbxassetid://135837817164001"] = true,
            ["rbxassetid://115763852918123"] = true, ["rbxassetid://139765328348537"] = true,
            ["rbxassetid://83037726599973"] = true, ["rbxassetid://131498997481190"] = true,
            ["rbxassetid://87091601850111"] = true, ["rbxassetid://86466269548335"] = true,
            ["rbxassetid://101759701167020"] = true, ["rbxassetid://91149657331993"] = true,
            ["rbxassetid://90905743250824"] = true, ["rbxassetid://112630239907251"] = true,
            ["rbxassetid://100842460034279"] = true, ["rbxassetid://94452665372956"] = true,
            ["rbxassetid://131932666588221"] = true, ["rbxassetid://134971996964091"] = true,
            ["rbxassetid://125858081984425"] = true, ["rbxassetid://89731716334782"] = true,
            ["rbxassetid://93824649798557"] = true, ["rbxassetid://115245242244708"] = true,
        }
        local lastBlock = 0

        AutoBlockDunkConnection = TrackScriptConnection(RunService.Heartbeat:Connect(function()
            if not AutoBlockDunkEnabled or os.clock() - lastBlock < 0.35 then return end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not root or not humanoid or humanoid.FloorMaterial == Enum.Material.Air then return end

            for _, player in ipairs(Players:GetPlayers()) do
                local enemy = player ~= LocalPlayer and player.Team ~= LocalPlayer.Team and player.Character
                local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
                local enemyHumanoid = enemy and enemy:FindFirstChildOfClass("Humanoid")
                local animator = enemyHumanoid and enemyHumanoid:FindFirstChildOfClass("Animator")
                if enemyRoot and animator and (root.Position - enemyRoot.Position).Magnitude <= 22 then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        if track.Animation and dunkAnimations[track.Animation.AnimationId] then
                            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                            lastBlock = os.clock()
                            return
                        end
                    end
                end
            end
        end))
    end,
})

RegisterUnloadCallback(function()
    AutoPassEnabled = false
    AutoBlockDunkEnabled = false
    if AutoPassConnection then AutoPassConnection:Disconnect() AutoPassConnection = nil end
    if AutoBlockDunkConnection then AutoBlockDunkConnection:Disconnect() AutoBlockDunkConnection = nil end
end)

-- Rage function: controls share a lifecycle and existing client controllers.
do
-- Auto Dunk activates the game's button and observes incoming notifications.
local setAutoDunk, stopAutoDunk
do
    local enabled, input, actionBusy = false, nil, false
    local heartbeat
    local epoch, warned = 0, false
    local listeners, remoteListeners, roundListeners = {}, {}, {}
    local data = {}
    local lastAttempt, lastPoll = -math.huge, 0
    local rangeBuffs = {Darkness = 0.3, HAHA = 0.3, Monster = 0.3, Flight = 0.6}

    local function connect(list, signal, callback)
        local c = signal:Connect(callback); list[#list + 1] = c; return c
    end
    local function disconnect(list)
        for _, c in ipairs(list) do c:Disconnect() end
        table.clear(list)
    end
    local function release()
        epoch = epoch + 1
        actionBusy = false
    end
    local function reset()
        release()
        table.clear(data)
        lastAttempt, lastPoll = -math.huge, 0
    end
    local function read(character, name)
        if data[name] ~= nil then return data[name] end
        local value = character:GetAttribute(name)
        if value ~= nil then return value end
        local child = character:FindFirstChild(name)
        return child and child:IsA("ValueBase") and child.Value or nil
    end
    local function bindRemotes()
        disconnect(remoteListeners)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then return end
        for _, name in ipairs({"Network", "UnreliableNetwork"}) do
            local remote = remotes:FindFirstChild(name)
            if remote and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
                connect(remoteListeners, remote.OnClientEvent, function(name, value)
                    -- Keep a private copy; never change the game's Network table.
                    if type(name) == "string" then data[name] = value end
                end)
            end
        end
        local ballState = remotes:FindFirstChild("BallState")
        local owner = ballState and ballState:FindFirstChild("SetCurrentBallPlayer")
        if owner and owner:IsA("RemoteEvent") then
            connect(remoteListeners, owner.OnClientEvent, function(player)
                data.HasBall = player == LocalPlayer
                if not data.HasBall then release() end
            end)
        end
    end
    local function bindRound()
        disconnect(roundListeners)
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        if not values then return end
        for _, name in ipairs({"State", "TipOff", "PositionReset"}) do
            local value = values:FindFirstChild(name)
            if value then connect(roundListeners, value:GetPropertyChangedSignal("Value"), function()
                if name == "State" or value.Value then reset() end
            end) end
        end
        local timer = values:FindFirstChild("Timer")
        if timer then
            local previous = timer.Value
            connect(roundListeners, timer:GetPropertyChangedSignal("Value"), function()
                if timer.Value > previous + 5 then reset() end
                previous = timer.Value
            end)
        end
    end
    local function canAttempt()
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local team = LocalPlayer.Team
        if not root or not humanoid or humanoid.Health <= 0 or not team
            or team.Name == "Visitor" or LocalPlayer.Neutral or read(character, "HasBall") ~= true then return false end
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        local state = values and values:FindFirstChild("State")
        if not state or state.Value ~= "Playing" then return false end
        for _, name in ipairs({"Scoring", "TipOff", "PositionReset"}) do
            local value = values:FindFirstChild(name)
            if value and value.Value then return false end
        end
        local barrier = Workspace:FindFirstChild("BARRIER")
        local ragdoll = character:FindFirstChild("IsRagdoll")
        local camera = Workspace.CurrentCamera
        if (barrier and barrier.CanCollide) or (ragdoll and ragdoll.Value)
            or (camera and camera.CameraType == Enum.CameraType.Scriptable)
            or input:GetFocusedTextBox()
            or humanoid.FloorMaterial == Enum.Material.Air then return false end
        for _, name in ipairs({"Stunned", "Shooting", "AimAssist", "Dunking", "Ability", "PumpFake", "InPostForm"}) do
            if read(character, name) == true then return false end
        end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track.IsPlaying and track.Priority.Value >= Enum.AnimationPriority.Action.Value then return false end
            end
        end
        local hoops = Workspace:FindFirstChild("Hoops")
        local side = hoops and hoops:FindFirstChild(team.Name)
        local hoop = side and side:FindFirstChild("Hoop")
        if not hoop or not hoop:IsA("BasePart") then return false end
        local delta = hoop.Position - root.Position
        local distance = Vector2.new(delta.X, delta.Z).Magnitude
        local speed = Vector2.new(root.AssemblyLinearVelocity.X, root.AssemblyLinearVelocity.Z).Magnitude
        local multiplier = 1
        local awakened = read(character, "InAwakening") == true
        local style = LocalPlayer:FindFirstChild("Style")
        if awakened and style and style.Value == "Symbiote" then multiplier = multiplier + 0.3 end
        if read(character, "InZone") == true then
            local zone = LocalPlayer:FindFirstChild("Zone")
            multiplier = multiplier + (zone and rangeBuffs[zone.Value] or 0)
        end
        local dunkTick = read(character, "DunkTick")
        if type(dunkTick) == "number" and dunkTick >= Workspace:GetServerTimeNow() then return true end
        -- The game's button handler makes the final eligibility check.
        local running = read(character, "Running") == true or input:IsKeyDown(Enum.KeyCode.LeftShift) or speed >= 17
        return distance < (running and 36 or 25) * multiplier and (distance <= 17 or speed >= 5)
    end
    local function press()
        local generation = epoch
        actionBusy = true
        task.defer(function()
            if not enabled or ScriptUnloaded or generation ~= epoch or not canAttempt() then
                if generation == epoch then actionBusy = false end
                return
            end
            local touchGui = PlayerGui:FindFirstChild("TouchGui")
            local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
            local button = frame and frame:FindFirstChild("JumpButton")
            -- In this Place, Resets connects Dunk to JumpButton only on touch
            -- devices. A plain desktop jump button does not provide that action.
            local usable = input.TouchEnabled and button and button:IsA("GuiButton")
            local ok = usable and activateGuiButton(button, true)
            if generation == epoch then actionBusy = false end
            if not ok and not warned and enabled and generation == epoch then
                warned = true
                NexusUI:Notify({Title = "Auto Dunk", Content = usable
                    and "Button signal activation is unavailable in this executor"
                    or "The game's Dunk button is available in touch mode", Duration = 5})
            end
        end)
        return true
    end
    stopAutoDunk = function()
        enabled = false
        release()
        if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
        disconnect(listeners); disconnect(remoteListeners); disconnect(roundListeners)
        table.clear(data)
    end
    setAutoDunk = function(value)
        stopAutoDunk()
        if not value or ScriptUnloaded then return end
        local ok, result = pcall(function() return game:GetService("UserInputService") end)
        if not ok then return end
        input = result
        warned = false
        enabled = true; reset(); bindRemotes(); bindRound()
        connect(listeners, ReplicatedStorage.ChildAdded, function(child)
            if child.Name == "Remotes" then reset(); bindRemotes() end
            if child.Name == "GameValues" then reset(); bindRound() end
        end)
        connect(listeners, LocalPlayer.CharacterAdded, reset)
        connect(listeners, LocalPlayer.CharacterRemoving, reset)
        connect(listeners, LocalPlayer:GetPropertyChangedSignal("Team"), reset)
        heartbeat = RunService.Heartbeat:Connect(function()
            if ScriptUnloaded then stopAutoDunk(); return end
            local now = os.clock()
            if not enabled or actionBusy or now - lastPoll < 0.05 or now - lastAttempt < 0.8 then return end
            lastPoll = now
            if canAttempt() then lastAttempt = now; press() end
        end)
    end
end

    local config = {StealDanger = false, InfiniteDribble = false, AutoDribble = false,
        SilentAimShot = false, AutoDunk = false, PerfectShot = false}
    local controllers, connections, roundConnections = {}, {}, {}
    local alive = false
    local heartbeat, discoveryTask, dangerGui, dangerLabel
    local infinitePatch, throwPatch

    local lastScan, lastThreatCheck, lastDribble = 0, 0, -math.huge
    local actionBusy, actionEpoch = false, 0
    local stealIds = {}
    local notified = {}
    local unpackArgs = table.unpack or unpack

    local function connect(list, signal, callback)
        local connection = signal:Connect(callback)
        table.insert(list, connection)
        return connection
    end
    local function disconnectAll(list)
        for _, connection in ipairs(list) do connection:Disconnect() end
        table.clear(list)
    end
    local function anyEnabled()
        for key, value in pairs(config) do if key ~= "AutoDunk" and value then return true end end
        return false
    end
    local function mutable(object)
        return type(object) == "table" and not (table.isfrozen and table.isfrozen(object))
    end
    local function notifyOnce(key, message)
        if notified[key] or not alive then return end
        notified[key] = true
        NexusUI:Notify({Title = "Rage function", Content = message, Duration = 5})
    end
    local function states()
        local movement = controllers.MovementController
        return movement and movement.States or {}
    end
    local function values()
        local network = controllers.Network
        return network and network.CharValues or {}
    end
    local function hasBall()
        local controller = controllers.BallController
        if controller and type(controller.GetPlayerPossessingBall) == "function" then
            local ok, owner = pcall(controller.GetPlayerPossessingBall, controller)
            if ok then return owner == LocalPlayer end
        end
        return values().HasBall == true
    end
    local function localParts()
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        return character, root, humanoid
    end
    local function playing()
        local team = LocalPlayer.Team
        if not team or team.Name == "Visitor" or LocalPlayer.Neutral then return false end
        local gameValues = ReplicatedStorage:FindFirstChild("GameValues")
        local state = gameValues and gameValues:FindFirstChild("State")
        local scoring = gameValues and gameValues:FindFirstChild("Scoring")
        local tipOff = gameValues and gameValues:FindFirstChild("TipOff")
        local positionReset = gameValues and gameValues:FindFirstChild("PositionReset")
        local barrier = Workspace:FindFirstChild("BARRIER")
        return state and state.Value == "Playing" and not (scoring and scoring.Value)
            and not (tipOff and tipOff.Value) and not (positionReset and positionReset.Value)
            and not (barrier and barrier.CanCollide)
    end
    local function targetHoop()
        local team = LocalPlayer.Team
        local hoops = Workspace:FindFirstChild("Hoops")
        local side = team and team.Name ~= "Visitor" and hoops and hoops:FindFirstChild(team.Name)
        local hoop = side and side:FindFirstChild("Hoop")
        return hoop and hoop:IsA("BasePart") and hoop or nil
    end
    local function opponent(player)
        return player ~= LocalPlayer and LocalPlayer.Team and player.Team
            and LocalPlayer.Team ~= player.Team and LocalPlayer.Team.Name ~= "Visitor"
            and player.Team.Name ~= "Visitor" and not LocalPlayer.Neutral and not player.Neutral
    end
    local function buildStealIds()
        table.clear(stealIds)
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        local animations = assets and assets:FindFirstChild("Animations")
        local blocks = animations and animations:FindFirstChild("Blocks")
        if blocks then
            for _, animation in ipairs(blocks:GetChildren()) do
                if animation:IsA("Animation") and (animation.Name == "StealL" or animation.Name == "StealR") then
                    local id = animation.AnimationId:match("%d+")
                    if id then stealIds[id] = true end
                end
            end
        end
        -- Verified ordinary Steal animations in the current Place.
        stealIds["106268822474526"], stealIds["132607768946898"] = true, true
    end
    local function isStealing(humanoid)
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator then return false end
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local animation = track.Animation
            local id = animation and animation.AnimationId:match("%d+")
            if id and stealIds[id] and track.IsPlaying and not track.Looped
                and track.Speed > 0 and track.TimePosition / track.Speed <= 0.55 then
                return true
            end
        end
        return false
    end
    local function lineClear(character, enemy, origin, destination)
        local delta = destination - origin
        if delta.Magnitude < 0.01 then return true end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignored = {character, enemy}
        local ball = GetCurrentBall()
        if ball then table.insert(ignored, ball) end
        params.FilterDescendantsInstances = ignored
        return Workspace:Raycast(origin, delta, params) == nil
    end
    local function findThreats(character, root)
        local danger
        local bestDanger = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if opponent(player) then
                local enemy = player.Character
                local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
                local humanoid = enemy and enemy:FindFirstChildOfClass("Humanoid")
                if enemyRoot and humanoid and humanoid.Health > 0 then
                    local offset = enemyRoot.Position - root.Position
                    local distance = offset.Magnitude
                    if distance <= 25 and lineClear(character, enemy, root.Position, enemyRoot.Position) then
                        local stealing = isStealing(humanoid)
                        local toward = distance > 0.01 and -offset.Unit or root.CFrame.LookVector
                        local facing = enemyRoot.CFrame.LookVector:Dot(toward) >= 0.1
                        local incoming = stealing and facing
                        local score = distance - (incoming and 30 or 0)
                        if score < bestDanger then
                            bestDanger = score
                            danger = {player = player, distance = distance, incoming = incoming}
                        end
                    end
                end
            end
        end
        return danger
    end
    local function makeDangerGui()
        if dangerGui and dangerGui.Parent then return end
        dangerGui = Instance.new("ScreenGui")
        dangerGui.Name = "PRIME_StealDanger"
        dangerGui.ResetOnSpawn = false
        dangerGui.IgnoreGuiInset = true
        dangerGui.DisplayOrder = 120
        dangerLabel = Instance.new("TextLabel")
        dangerLabel.Name = "Danger"
        dangerLabel.AnchorPoint = Vector2.new(0.5, 0)
        dangerLabel.Position = UDim2.new(0.5, 0, 0, 72)
        dangerLabel.Size = UDim2.fromOffset(310, 46)
        dangerLabel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
        dangerLabel.BackgroundTransparency = 0.18
        dangerLabel.BorderSizePixel = 0
        dangerLabel.Font = Enum.Font.GothamBold
        dangerLabel:SetAttribute("KeepFont", true)
        dangerLabel.TextSize = 14
        dangerLabel.Visible = false
        dangerLabel.Parent = dangerGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = dangerLabel
        dangerGui.Parent = GuiParent
    end
    local function removeDangerGui()
        if dangerGui then dangerGui:Destroy() end
        dangerGui, dangerLabel = nil, nil
    end
    local function updateDanger(threat)
        if not config.StealDanger then removeDangerGui() return end
        makeDangerGui()
        dangerLabel.Visible = threat ~= nil
        if threat then
            dangerLabel.Text = string.format("%s\n%s | %.1f studs",
                threat.incoming and "STEAL INCOMING" or "STEAL DANGER",
                threat.player.DisplayName, threat.distance)
            dangerLabel.TextColor3 = threat.incoming and Color3.fromRGB(255, 85, 85) or Color3.fromRGB(255, 205, 90)
        end
    end
    local function removeInfinite()
        local patch = infinitePatch
        infinitePatch = nil
        if not patch then return end
        if rawget(patch.object, "Dribble") == patch.wrapper then rawset(patch.object, "Dribble", patch.rawOriginal) end
        for key, applied in pairs(patch.applied) do
            if rawget(patch.object, key) == applied then rawset(patch.object, key, patch.original[key]) end
        end
    end
    local function resetDribbleCounters(patch)
        for key, value in pairs({Dribbles = 0, LastDribble = 0, DribbleDB = tick() - 0.1}) do
            if patch.original[key] == nil then patch.original[key] = rawget(patch.object, key) end
            rawset(patch.object, key, value)
            patch.applied[key] = value
        end
    end
    local function updateInfinite()
        local object = controllers.BallController
        if not config.InfiniteDribble or not mutable(object) then removeInfinite() return end
        if not infinitePatch or infinitePatch.object ~= object then
            removeInfinite()
            if type(object.Dribble) ~= "function" then return end
            local original = object.Dribble
            local patch = {object = object, rawOriginal = rawget(object, "Dribble"), original = {}, applied = {}}
            patch.wrapper = function(self, ...)
                if alive and config.InfiniteDribble and self == object and infinitePatch == patch then
                    resetDribbleCounters(patch)
                end
                local result = table.pack(original(self, ...))
                -- The game increments the counter and sets a new debounce during
                -- Dribble. Clear both immediately after it returns as well, so
                -- unlimited consecutive uses do not depend on the next Heartbeat.
                -- Never reapply an old patch after disabling/rebinding while a
                -- game method yields. GetMaxDribbles and its checks stay intact.
                if alive and config.InfiniteDribble and self == object and infinitePatch == patch then
                    resetDribbleCounters(patch)
                end
                return unpackArgs(result, 1, result.n)
            end
            rawset(object, "Dribble", patch.wrapper)
            infinitePatch = patch
        end
        if hasBall() then resetDribbleCounters(infinitePatch) end
    end
    local psReq, psSignal, psNext = nil, nil, 0
    local psHooks = {}
    local function clearPerfect()
        psReq, perfectShotLock = nil, nil
    end
    local function removePerfectHook()
        clearPerfect()
        for _, h in ipairs(psHooks) do
            if h.node then
                if rawget(h.node, "_fn") == h.wrapper then rawset(h.node, "_fn", h.fn) end
            else
                if h.connection then pcall(function() h.connection:Disconnect() end) end
                pcall(h.enable, h.source)
            end
        end
        table.clear(psHooks)
        psSignal, psNext = nil, 0
    end
    local function psVelocity(ball, target)
        local delta, g = target - ball.Position, Workspace.Gravity
        if g <= 0 then return end
        local dist = Vector2.new(delta.X, delta.Z).Magnitude
        local t = dist / math.clamp(65 + dist * 0.5, 65, 220)
        local apex = math.max(ball.Position.Y, target.Y) + math.clamp(dist * 0.04, 3, 16)
        t = math.max(t, (math.sqrt(2 * g * (apex - ball.Position.Y))
            + math.sqrt(2 * g * (apex - target.Y))) / g)
        if t <= 0 then return end
        local v = delta / t + Vector3.new(0, g * t * 0.5, 0)
        return ApplyShotPowerModifier(v, nil, v.Magnitude), t
    end
    local function psWrap(fn)
        return function(destination, ...)
            local r = psReq
            local valid = alive and config.PerfectShot and r and typeof(destination) == "Vector3"
                and os.clock() <= r.expires and playing() and LocalPlayer.Character == r.char
                and GetCurrentBall() == r.ball and targetHoop() == r.hoop
                and r.ball.Parent and r.hoop.Parent
            if valid then
                local c = controllers.BallController
                if c and type(c.GetPlayerPossessingBall) == "function" then
                    local ok, holder = pcall(c.GetPlayerPossessingBall, c)
                    if not ok or holder and holder ~= LocalPlayer then valid = false end
                end
            end
            if not valid then return fn(destination, ...) end
            psReq = nil
            local target = r.hoop.Position
            local result = table.pack(fn(target, ...))
            if alive and config.PerfectShot and GetCurrentBall() == r.ball
                and LocalPlayer.Character == r.char and not r.ball.Anchored then
                local ok, velocity, seconds = pcall(psVelocity, r.ball, target)
                if ok and velocity then
                    r.ball.AssemblyLinearVelocity = velocity
                    perfectShotLock = {ball = r.ball, expires = os.clock() + seconds + 0.2}
                end
            end
            return unpackArgs(result, 1, result.n)
        end
    end
    local function psNative(fn, module)
        if type(fn) ~= "function" then return false end
        if type(getfenv) == "function" then
            local ok, env = pcall(getfenv, fn)
            if ok and type(env) == "table" and env.script == module then return true end
        end
        if debug and type(debug.info) == "function" then
            local ok, source = pcall(debug.info, fn, "s")
            return ok and type(source) == "string" and source:find(module:GetFullName(), 1, true) ~= nil
        end
        return false
    end
    local function psRead(obj, key)
        local ok, value = pcall(function() return obj[key] end)
        if ok then return value end
    end
    local function updatePerfectHook()
        if not config.PerfectShot then
            if psSignal or #psHooks > 0 then removePerfectHook() end
            return
        end
        if psReq and os.clock() > psReq.expires then psReq = nil end
        local ability = controllers.AbilityController
        local signal = ability and ability.BallService and ability.BallService.Throw
        if not signal then return end
        if psSignal == signal and #psHooks > 0 then return end
        if psSignal and psSignal ~= signal then removePerfectHook() end
        if os.clock() < psNext then return end
        psNext = os.clock() + 1
        local folder = ReplicatedStorage:FindFirstChild("Controllers")
        local module = folder and folder:FindFirstChild("BallController")
        if not module then return end
        if rawget(signal, "_directConnect") == false then
            local inner = rawget(signal, "_signal")
            local node = type(inner) == "table" and rawget(inner, "_handlerListHead")
            while node do
                local fn = rawget(node, "_fn")
                if rawget(node, "Connected") and psNative(fn, module) then
                    local wrapper = psWrap(fn)
                    rawset(node, "_fn", wrapper)
                    psHooks[#psHooks + 1] = {node = node, fn = fn, wrapper = wrapper}
                end
                node = rawget(node, "_next")
            end
        elseif type(getconnections) == "function" then
            local remote = rawget(signal, "_re")
            local ok, list = pcall(function() return getconnections(remote.OnClientEvent) end)
            if ok and type(list) == "table" then
                for _, c in ipairs(list) do
                    local fn = psRead(c, "Function")
                    local disable, enable = psRead(c, "Disable"), psRead(c, "Enable")
                    if psRead(c, "Enabled") ~= false and type(disable) == "function"
                        and type(enable) == "function" and psNative(fn, module) then
                        local wrapper = psWrap(fn)
                        local success, connection = pcall(function() return remote.OnClientEvent:Connect(wrapper) end)
                        if success and connection then
                            local disabled = pcall(disable, c)
                            if disabled then
                                psHooks[#psHooks + 1] = {source = c, enable = enable, connection = connection}
                            else
                                pcall(function() connection:Disconnect() end)
                            end
                        end
                    end
                end
            end
        end
        if #psHooks > 0 then psSignal = signal end
    end
    local function removeSilentAim()
        local patch = throwPatch
        throwPatch = nil
        if patch and rawget(patch.object, "Fire") == patch.wrapper then
            rawset(patch.object, "Fire", patch.rawOriginal)
        end
    end
    local function updateSilentAim()
        local ability = controllers.AbilityController
        local signal = ability and ability.BallService and ability.BallService.Throw
        if not (config.SilentAimShot or config.PerfectShot) or not mutable(signal) then removeSilentAim() return end
        if throwPatch and throwPatch.object == signal and rawget(signal, "Fire") == throwPatch.wrapper then return end
        removeSilentAim()
        local original = signal.Fire
        if type(original) ~= "function" then return end
        local patch = {object = signal, rawOriginal = rawget(signal, "Fire")}
        patch.wrapper = function(self, ...)
            local args, s = table.pack(...), states()
            if alive and self == signal and (config.SilentAimShot or config.PerfectShot)
                and typeof(args[1]) == "Vector2" and args[2] ~= true and not s.Dunking
                and not s.Ability and not s.PumpFake and (s.Shooting or s.AimAssist) then
                local char, root = localParts()
                local hoop, ball = targetHoop(), GetCurrentBall()
                if root and hoop then
                    local d = hoop.Position - root.Position
                    local dir = Vector2.new(d.X, d.Z)
                    if dir.Magnitude > 0.01 then args[1] = dir.Unit end
                end
                if config.PerfectShot and #psHooks > 0 and playing() and hasBall() and ball and hoop then
                    clearPerfect()
                    psReq = {ball = ball, hoop = hoop, char = char, expires = os.clock() + 2.5}
                end
            end
            return original(self, unpackArgs(args, 1, args.n))
        end
        rawset(signal, "Fire", patch.wrapper)
        throwPatch = patch
    end

    local function discoverControllers()
        if discoveryTask or not alive then return end
        discoveryTask = task.defer(function()
            local found = {}
            -- Same pattern the game itself uses: require its already-loaded controller
            -- modules. No Knit registry call, and only once the round has started.
            local folder = ReplicatedStorage:FindFirstChild("Controllers")
            if folder and LocalPlayer.Character and ReplicatedStorage:FindFirstChild("GameValues") then
                for _, name in ipairs({"BallController", "MovementController", "Network", "AbilityController"}) do
                    local module = folder:FindFirstChild(name)
                    if module and module:IsA("ModuleScript") then
                        local ok, object = pcall(require, module)
                        if ok and type(object) == "table" then found[name] = object end
                    end
                end
            end
            if (not found.BallController or not found.MovementController or not found.Network or not found.AbilityController)
                and type(getgc) == "function" then
                local ok, objects = pcall(getgc, true)
                if ok and type(objects) == "table" then
                    local visited = 0
                    for _, object in pairs(objects) do
                        if not alive then return end
                        if type(object) == "table" then
                            local name = rawget(object, "Name")
                            if name == "BallController" and not found[name] and type(object.Dribble) == "function"
                                and type(object.Dunk) == "function" and type(object.DribbleDB) == "number" then found[name] = object
                            elseif name == "MovementController" and not found[name] and type(object.States) == "table" then found[name] = object
                            elseif name == "Network" and not found[name] and type(object.CharValues) == "table" then found[name] = object
                            elseif name == "AbilityController" and not found[name] and type(object.BallService) == "table" then found[name] = object end
                        end
                        visited = visited + 1
                        if found.BallController and found.MovementController and found.Network and found.AbilityController then break end
                        if visited % 1000 == 0 then task.wait() end
                    end
                end
            end
            if alive then
                for name, object in pairs(found) do controllers[name] = object end
                updateInfinite()
                updateSilentAim()
                updatePerfectHook()
                if not controllers.BallController then notifyOnce("controllers", "Waiting for the game's client controllers") end
            end
            discoveryTask = nil
        end)
    end
    local function actionAllowed(root, humanoid)
        local state = states()
        local character = LocalPlayer.Character
        local ragdoll = character and character:FindFirstChild("IsRagdoll")
        return root and humanoid and humanoid.Health > 0 and not (ragdoll and ragdoll.Value)
            and not state.Shooting and not state.AimAssist and not state.Dunking and not state.Ability
            and not state.Stunned and not state.PumpFake and not actionBusy
    end
    local adCons, adPlayers, adThreats = {}, {}, {}
    local adBound, adButton = false, nil
    local function tryDribble()
        if not alive or not config.AutoDribble or actionBusy or not playing() or not hasBall() then return end
        local _, root, hum = localParts()
        if not actionAllowed(root, hum) or hum:GetState() == Enum.HumanoidStateType.Freefall then return end
        local now = os.clock()
        for char, t in pairs(adThreats) do
            local p = Players:GetPlayerFromCharacter(char)
            local er = char:FindFirstChild("HumanoidRootPart")
            if now >= t.untilAt or not char.Parent or not er or not p or not opponent(p) then
                adThreats[char] = nil
            elseif not t.done and now >= t.nextAt and (root.Position - er.Position).Magnitude <= 20 then
                local ball = controllers.BallController
                if ball and type(ball.DribbleDB) == "number" and ball.DribbleDB > tick() then return end
                if not adButton or not adButton.Parent then
                    local mobile = PlayerGui:FindFirstChild("Mobile")
                    local folder = mobile and mobile:FindFirstChild("Ball")
                    adButton = findGuiButton("Dribble", folder and folder:FindFirstChild("Dribble"))
                end
                if not adButton then return end
                t.nextAt = now + 0.04
                local db, stamp = ball and ball.DribbleDB, values().DribblingTick
                local epoch = actionEpoch
                actionBusy = true
                local ok = activateGuiButton(adButton)
                if epoch == actionEpoch then actionBusy = false end
                if epoch ~= actionEpoch or not alive then return end
                if ok and (not ball or values().DribblingTick ~= stamp
                    or not config.InfiniteDribble and ball.DribbleDB ~= db) then
                    lastDribble = now
                    for _, other in pairs(adThreats) do other.done = true end
                end
                return
            end
        end
    end
    local function onStealAnimation(char, age)
        if not alive or not config.AutoDribble then return end
        local p = Players:GetPlayerFromCharacter(char)
        if not p or not opponent(p) then return end
        local now = os.clock()
        adThreats[char] = {untilAt = now + math.max(0, 0.45 - age), nextAt = 0, done = false}
        tryDribble()
    end
    local function clearAdPlayer(p)
        local r = adPlayers[p]
        if not r then return end
        disconnectAll(r.pc)
        disconnectAll(r.cc)
        if r.ac then r.ac:Disconnect() end
        if r.char then adThreats[r.char] = nil end
        adPlayers[p] = nil
    end
    local function bindAdPlayer(p)
        if p == LocalPlayer or adPlayers[p] then return end
        local r = {pc = {}, cc = {}}
        adPlayers[p] = r
        local function bindChar(char)
            disconnectAll(r.cc)
            if r.ac then r.ac:Disconnect() r.ac = nil end
            if r.char then adThreats[r.char] = nil end
            r.char, r.anim = char, nil
            if not char then return end
            local function played(track, existing)
                local a = track.Animation
                local id = a and a.AnimationId:match("%d+")
                if not id or not stealIds[id] or track.Looped then return end
                local age = existing and track.TimePosition / math.max(math.abs(track.Speed), 0.1) or 0
                if age < 0.45 then onStealAnimation(char, age) end
            end
            local function bindAnim()
                local hum = char:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                if not anim or r.anim == anim then return end
                if r.ac then r.ac:Disconnect() end
                r.anim = anim
                r.ac = anim.AnimationPlayed:Connect(function(track) played(track, false) end)
                for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                    if track.IsPlaying then played(track, true) end
                end
            end
            connect(r.cc, char.DescendantAdded, function(v)
                if v:IsA("Animator") or v:IsA("Humanoid") then bindAnim() end
            end)
            bindAnim()
        end
        connect(r.pc, p.CharacterAdded, bindChar)
        connect(r.pc, p.CharacterRemoving, function() bindChar(nil) end)
        bindChar(p.Character)
    end
    local function removeStealHook()
        disconnectAll(adCons)
        for p in pairs(adPlayers) do clearAdPlayer(p) end
        table.clear(adThreats)
        adBound, adButton = false, nil
    end
    local function updateStealHook()
        if not config.AutoDribble then
            if adBound then removeStealHook() end
            return
        end
        if not adBound then
            adBound = true
            connect(adCons, Players.PlayerAdded, bindAdPlayer)
            connect(adCons, Players.PlayerRemoving, clearAdPlayer)
            for _, p in ipairs(Players:GetPlayers()) do bindAdPlayer(p) end
        end
        tryDribble()
    end

    local function resetRound()
        -- Round transitions can replace controllers, signals or their Fire method.
        -- Keep the toggles enabled, but rebuild their runtime bindings.
        if discoveryTask then pcall(task.cancel, discoveryTask) discoveryTask = nil end
        removeSilentAim()
        removePerfectHook()
        removeStealHook()
        table.clear(controllers)
        actionEpoch = actionEpoch + 1
        actionBusy = false
        lastDribble, lastThreatCheck = -math.huge, 0
        if dangerLabel then dangerLabel.Visible = false end
        if infinitePatch then
            infinitePatch.original = {Dribbles = 0, LastDribble = 0, DribbleDB = tick()}
            table.clear(infinitePatch.applied)
        end
        buildStealIds()
        if alive then discoverControllers() end
    end
    local function bindRoundSignals(gameValues)
        disconnectAll(roundConnections)
        if not gameValues then return end
        local state = gameValues:FindFirstChild("State")
        if state then connect(roundConnections, state:GetPropertyChangedSignal("Value"), resetRound) end
        for _, name in ipairs({"TipOff", "PositionReset"}) do
            local value = gameValues:FindFirstChild(name)
            if value then connect(roundConnections, value:GetPropertyChangedSignal("Value"), function()
                if value.Value then resetRound() end
            end) end
        end
        local timer = gameValues:FindFirstChild("Timer")
        if timer then
            local previous = timer.Value
            connect(roundConnections, timer:GetPropertyChangedSignal("Value"), function()
                if timer.Value > previous + 5 then resetRound() end
                previous = timer.Value
            end)
        end
    end
    local function stop()
        alive = false
        actionEpoch = actionEpoch + 1
        actionBusy = false
        if heartbeat then heartbeat:Disconnect() heartbeat = nil end
        if discoveryTask then pcall(task.cancel, discoveryTask) discoveryTask = nil end
        disconnectAll(connections)
        disconnectAll(roundConnections)
        removeInfinite()
        removeSilentAim()
        removePerfectHook()
        removeStealHook()
        removeDangerGui()
        table.clear(controllers)
        table.clear(notified)
    end
    local function start()
        if alive then return end
        alive = true
        resetRound()
        bindRoundSignals(ReplicatedStorage:FindFirstChild("GameValues"))
        connect(connections, ReplicatedStorage.ChildAdded, function(child)
            if child.Name == "GameValues" then resetRound(); bindRoundSignals(child) end
        end)
        connect(connections, LocalPlayer.CharacterAdded, resetRound)
        connect(connections, LocalPlayer.CharacterRemoving, resetRound)
        connect(connections, LocalPlayer:GetPropertyChangedSignal("Team"), resetRound)
        lastScan = os.clock()
        discoverControllers()
        heartbeat = RunService.Heartbeat:Connect(function(dt)
            if ScriptUnloaded then stop() return end
            local now = os.clock()
            if now - lastScan >= 2 then
                lastScan = now
                if not controllers.BallController or not controllers.MovementController or not controllers.Network
                    or ((config.SilentAimShot or config.PerfectShot or config.AutoDribble) and not controllers.AbilityController) then discoverControllers() end
            end
            updateSilentAim()
            updateInfinite()
            updatePerfectHook()
            updateStealHook()

            if now - lastThreatCheck < 0.04 then return end
            lastThreatCheck = now
            local character, root, humanoid = localParts()
            if not playing() or not hasBall() or not root or not humanoid or humanoid.Health <= 0 then
                updateDanger(nil)
                return
            end
            updateDanger(config.StealDanger and findThreats(character, root) or nil)
        end)
    end
    local function setFeature(key, value)
        config[key] = value == true and not ScriptUnloaded
        if key == "AutoDunk" then setAutoDunk(config.AutoDunk) end
        if not config.PerfectShot then clearPerfect() end
        if anyEnabled() then
            start()
            updateInfinite()
            updateSilentAim()
            updatePerfectHook()
            updateStealHook()
            if not config.StealDanger then removeDangerGui() end
        else stop() end
    end

    Tabs.Main:AddSection("Rage function", "Right")
    local controls = {
        {"StealDanger", "Steal Danger", "Warns about nearby enemies and incoming Steal animations"},
        {"InfiniteDribble", "Infinite Dribble", "Unlimited local Dribble uses with no series limit or cooldown"},
        {"AutoDribble", "Auto Dribble", "Presses the game Dribble button when a nearby opposing player plays a Steal animation"},
        {"SilentAimShot", "Silent Aim", "Aims ordinary shot releases at your scoring hoop without moving the camera"},
        {"PerfectShot", "Perfect Shot", "Hold the ball for about 5 seconds before shooting for this feature to work."},
        {"AutoDunk", "Auto Dunk", "Activates the game Dunk button in range; no keyboard input or module calls"},
    }
    for _, control in ipairs(controls) do
        local key, title, description = control[1], control[2], control[3]
        Tabs.Main:AddToggle(key, {Title = title, Description = description, ShowDescription = key == "PerfectShot", Default = false,
            Callback = function(value) setFeature(key, value) end})
    end
-- No Steal Fall: scoped to the local character's ordinary Steal animation.
do
    local enabled, heartbeat, character, humanoid, animator
    local untilTime, armedAt, lastPoll = 0, 0, 0
    local connections, animationConnections, roundConnections = {}, {}, {}
    local savedStates, scripts, motors, constraints = {}, {}, {}, {}
    local stealIds = {["106268822474526"] = true, ["132607768946898"] = true}
    local function connect(list, signal, fn)
        local c = signal:Connect(fn); list[#list + 1] = c; return c
    end
    local function disconnect(list)
        for _, c in ipairs(list) do c:Disconnect() end
        table.clear(list)
    end
    local function ragdolled()
        local flag = character and character:FindFirstChild("IsRagdoll")
        return flag and flag:IsA("BoolValue") and flag.Value == true
    end
    local function restore()
        untilTime = 0
        if humanoid and humanoid.Parent then
            for state, old in pairs(savedStates) do
                local applied = state == Enum.HumanoidStateType.GettingUp
                if humanoid:GetStateEnabled(state) == applied then humanoid:SetStateEnabled(state, old) end
            end
        end
        for object, old in pairs(scripts) do
            if object.Parent and object.Enabled == false then object.Enabled = old end
        end
        -- If the game still has ragdoll active, return joint control to it.
        -- After a completed recovery, leave the ordinary body joints enabled.
        if ragdolled() then
            for object, old in pairs(motors) do
                if object.Parent and object.Enabled == true then object.Enabled = old end
            end
            for object, old in pairs(constraints) do
                if object.Parent and object.Enabled == false then object.Enabled = old end
            end
        end
        table.clear(savedStates); table.clear(scripts); table.clear(motors); table.clear(constraints)
    end
    local function protect()
        if not enabled or not humanoid or humanoid.Health <= 0 or os.clock() >= untilTime then return end
        for _, state in ipairs({Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown,
            Enum.HumanoidStateType.GettingUp}) do
            if savedStates[state] == nil then savedStates[state] = humanoid:GetStateEnabled(state) end
            humanoid:SetStateEnabled(state, state == Enum.HumanoidStateType.GettingUp)
        end
        local ragdoll = character:FindFirstChild("RagdollR6")
        local client = ragdoll and ragdoll:FindFirstChild("RagdollClient")
        if client and client:IsA("LocalScript") then
            if scripts[client] == nil then scripts[client] = client.Enabled end
            client.Enabled = false
        end
        if not ragdolled() then return end
        -- Keep an already observed Steal knockdown suppressed until recovery,
        -- with a bounded lifetime so unrelated future falls are unaffected.
        untilTime = math.max(untilTime, math.min(os.clock() + 0.25, armedAt + 8))
        local bodyJoints = {}
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("Motor6D") and object.Part0 and object.Part1 then
                bodyJoints[#bodyJoints + 1] = {object.Part0, object.Part1}
                if not object.Enabled then
                    if motors[object] == nil then motors[object] = false end
                    object.Enabled = true
                end
            end
        end
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("BallSocketConstraint") or object:IsA("HingeConstraint") then
                local a, b = object.Attachment0, object.Attachment1
                if a and b then
                    for _, pair in ipairs(bodyJoints) do
                        if (a.Parent == pair[1] and b.Parent == pair[2]) or (a.Parent == pair[2] and b.Parent == pair[1]) then
                            if object.Enabled then
                                if constraints[object] == nil then constraints[object] = true end
                                object.Enabled = false
                            end
                            break
                        end
                    end
                end
            end
        end
        humanoid.PlatformStand = false
        local state = humanoid:GetState()
        if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.Physics then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        if root and not root.Anchored then
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            local forward = root.CFrame.LookVector
            local horizontal = Vector3.new(forward.X, 0, forward.Z)
            if horizontal.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit) end
        end
    end
    local function observe(track, existing)
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        if not enabled or not stealIds[id] then return end
        if existing and (not track.IsPlaying or track.TimePosition / math.max(0.01, math.abs(track.Speed)) > 0.72) then return end
        if not humanoid or humanoid.Health <= 0 then return end
        armedAt = os.clock()
        untilTime = armedAt + 2.5
        protect()
    end
    local function bindCharacter()
        restore(); disconnect(animationConnections)
        character = LocalPlayer.Character
        humanoid = character and character:FindFirstChildOfClass("Humanoid")
        animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator then
            connect(animationConnections, animator.AnimationPlayed, function(track) observe(track, false) end)
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do observe(track, true) end
        end
    end
    local function bindRound()
        disconnect(roundConnections)
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        if not values then return end
        for _, name in ipairs({"State", "TipOff", "PositionReset"}) do
            local value = values:FindFirstChild(name)
            if value then connect(roundConnections, value:GetPropertyChangedSignal("Value"), function()
                if name == "State" or value.Value then restore() end
            end) end
        end
        local timer = values:FindFirstChild("Timer")
        if timer then
            local previous = timer.Value
            connect(roundConnections, timer:GetPropertyChangedSignal("Value"), function()
                if timer.Value > previous + 5 then restore() end
                previous = timer.Value
            end)
        end
    end
    local function stop()
        enabled = false
        if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
        restore(); disconnect(connections); disconnect(animationConnections); disconnect(roundConnections)
        character, humanoid, animator = nil, nil, nil
    end
    local function start()
        stop()
        if ScriptUnloaded then return end
        enabled = true
        bindCharacter(); bindRound()
        connect(connections, LocalPlayer.CharacterAdded, bindCharacter)
        connect(connections, LocalPlayer.CharacterRemoving, function()
            restore(); disconnect(animationConnections); character, humanoid, animator = nil, nil, nil
        end)
        connect(connections, LocalPlayer:GetPropertyChangedSignal("Team"), restore)
        connect(connections, ReplicatedStorage.ChildAdded, function(child)
            if child.Name == "GameValues" then restore(); bindRound() end
        end)
        heartbeat = RunService.Heartbeat:Connect(function()
            if ScriptUnloaded then stop(); return end
            local now = os.clock()
            if now - lastPoll < 0.03 then return end
            lastPoll = now
            local current = LocalPlayer.Character
            local hum = current and current:FindFirstChildOfClass("Humanoid")
            local anim = hum and hum:FindFirstChildOfClass("Animator")
            if current ~= character or hum ~= humanoid or anim ~= animator then bindCharacter() end
            if untilTime > 0 then
                if now >= untilTime or not humanoid or humanoid.Health <= 0 then restore() else protect() end
            end
        end)
    end
    Tabs.Main:AddToggle("NoStealFall", {Title = "No Steal Fall",
        Description = "Locally suppresses ragdoll knockdown briefly after your Steal animation",
        Default = false, Callback = function(value) if value then start() else stop() end end})
    RegisterUnloadCallback(stop)
end

    Tabs.Main:SetActiveSection(MainSection)
    RegisterUnloadCallback(function()
        for key in pairs(config) do config[key] = false end
        stopAutoDunk()
        stop()
    end)
end

-- BEGIN PRIME SMART SUPPORT v1
do
    -- BEGIN SUPPORT MATH (no Roblox dependencies)
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local function facingAllowed(dot, threshold)
        return finite(dot) and finite(threshold) and dot >= threshold
    end
    -- END SUPPORT MATH

    local config = {AutoSteal = false, StealRange = 12}
    local controllers, connections = {}, {}
    local heartbeat, discoveryTask
    local generation, lastTick, lastDiscovery, nextSteal = 0, 0, -math.huge, 0
    local running, actionBusy, warned = false, false, false
    local function anyEnabled()
        return config.AutoSteal
    end
    local function connect(signal, fn)
        connections[#connections + 1] = signal:Connect(fn)
    end
    local function parts(player)
        local character = player and player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then return character, root, humanoid end
    end
    local function activePlayer(player)
        return player and player.Team and not player.Neutral and player.Team.Name ~= "Visitor"
    end
    local function call(object, method)
        if type(object) ~= "table" or type(object[method]) ~= "function" then return nil, false end
        local ok, value = pcall(object[method], object)
        return value, ok
    end
    local function playing()
        if ScriptUnloaded or not activePlayer(LocalPlayer) then return false end
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        local state = values and values:FindFirstChild("State")
        if not state or state.Value ~= "Playing" then return false end
        for _, name in ipairs({"Scoring", "TipOff", "PositionReset"}) do
            local value = values:FindFirstChild(name)
            if value and value.Value then return false end
        end
        local barrier = Workspace:FindFirstChild("BARRIER")
        if barrier and barrier:IsA("BasePart") and barrier.CanCollide then return false end
        return true
    end
    local function allowed(character, humanoid)
        if not character or not humanoid or humanoid.Health <= 0 or humanoid.Sit
            or userInputService:GetFocusedTextBox() then return false end
        local camera = Workspace.CurrentCamera
        if not camera or camera.CameraType == Enum.CameraType.Scriptable then return false end
        local ragdoll = character:FindFirstChild("IsRagdoll")
        if ragdoll and ragdoll:IsA("BoolValue") and ragdoll.Value then return false end
        local movement = controllers.MovementController
        local states = movement and movement.States
        if type(states) ~= "table" then return false end
        for _, name in ipairs({"Stunned", "Shooting", "AimAssist", "Dunking", "Ability", "PumpFake", "Stealing"}) do
            if states[name] then return false end
        end
        local blocked, ok = call(controllers.BallController, "NoAction")
        return ok and blocked == false
    end
    local function discover()
        if discoveryTask or not running then return end
        local epoch = generation
        discoveryTask = task.defer(function()
            local found = {}
            local packages = ReplicatedStorage:FindFirstChild("Packages")
            local knitModule = packages and packages:FindFirstChild("Knit")
            if knitModule and knitModule:IsA("ModuleScript") then
                local ok, knit = pcall(require, knitModule)
                if ok and type(knit) == "table" and type(knit.GetController) == "function" then
                    for _, name in ipairs({"BallController", "DefenseController", "MovementController"}) do
                        local success, object = pcall(knit.GetController, name)
                        if success and type(object) == "table" then found[name] = object end
                    end
                end
            end
            if (not found.BallController or not found.DefenseController or not found.MovementController)
                and type(getgc) == "function" then
                local ok, objects = pcall(getgc, true)
                if ok and type(objects) == "table" then
                    local signatures = {BallController = "GetPlayerPossessingBall",
                        DefenseController = "Steal", MovementController = "States"}
                    local visited = 0
                    for _, object in pairs(objects) do
                        if not running or generation ~= epoch then return end
                        if type(object) == "table" then
                            local name = rawget(object, "Name")
                            local key = signatures[name]
                            if key and not found[name] and type(rawget(object, key)) == (key == "States" and "table" or "function") then
                                found[name] = object
                            end
                        end
                        visited = visited + 1
                        if visited % 2000 == 0 then task.wait() end
                    end
                end
            end
            if running and generation == epoch then
                controllers = found
                discoveryTask = nil
            end
        end)
    end
    local function lineClear(from, to, exclusions)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclusions
        params.IgnoreWater = true
        return Workspace:Raycast(from, to - from, params) == nil
    end
    local function stealEligible(character, root, humanoid)
        if not playing() or not allowed(character, humanoid) or humanoid.FloorMaterial == Enum.Material.Air then return false end
        local ballController = controllers.BallController
        local owner, ownerKnown = call(ballController, "GetPlayerPossessingBall")
        if not ownerKnown or not activePlayer(owner) or owner == LocalPlayer or owner.Team == LocalPlayer.Team then return false end
        -- These are the game's real local copies, not guesses based on animations.
        local protected, known = call(ballController, "BallIFrameIsActive")
        if not known or protected ~= false then return false end
        local teamProtected, teamKnown = call(ballController, "BallTeamIFrameIsActive")
        if not teamKnown or teamProtected ~= false then return false end
        local enemy, enemyRoot = parts(owner)
        if not enemyRoot then return false end
        local delta = enemyRoot.Position - root.Position
        if delta.Magnitude > config.StealRange or delta.Magnitude < 0.01 then return false end
        local flat = Vector3.new(delta.X, 0, delta.Z)
        if flat.Magnitude < 0.01 or not facingAllowed(root.CFrame.LookVector:Dot(flat.Unit), 0.35) then return false end
        local ball = GetCurrentBall()
        local exclusions = {character, enemy}
        if ball then exclusions[#exclusions + 1] = ball end
        return lineClear(root.Position, enemyRoot.Position, exclusions)
    end
    local function autoSteal(now, character, root, humanoid)
        if not config.AutoSteal or actionBusy or now < nextSteal or not stealEligible(character, root, humanoid) then return end
        local defense = controllers.DefenseController
        if not defense or type(defense.Steal) ~= "function" then return end
        actionBusy, nextSteal = true, now + 0.35
        local epoch = generation
        task.defer(function()
            if running and generation == epoch and config.AutoSteal and LocalPlayer.Character == character
                and stealEligible(character, root, humanoid) then
                local ok = pcall(defense.Steal, defense)
                local movement = controllers.MovementController
                if ok and movement and movement.States.Stealing then
                    -- Controller's own cooldown remains authoritative; throttle retries too.
                    nextSteal = os.clock() + 0.8
                end
            end
            if generation == epoch then actionBusy = false end
        end)
    end
    local function reset()
        generation = generation + 1
        if discoveryTask then pcall(task.cancel, discoveryTask); discoveryTask = nil end
        controllers, actionBusy, nextSteal, lastDiscovery = {}, false, 0, -math.huge
    end
    local function stop()
        running = false
        reset()
        if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        connections = {}
    end
    local function start()
        if running or ScriptUnloaded then return end
        running, warned, lastTick = true, false, 0
        reset()
        connect(LocalPlayer.CharacterAdded, reset)
        connect(LocalPlayer.CharacterRemoving, reset)
        connect(LocalPlayer:GetPropertyChangedSignal("Team"), reset)
        local values = ReplicatedStorage:FindFirstChild("GameValues")
        if values then
            for _, name in ipairs({"State", "TipOff", "PositionReset"}) do
                local value = values:FindFirstChild(name)
                if value then connect(value:GetPropertyChangedSignal("Value"), reset) end
            end
        end
        heartbeat = RunService.Heartbeat:Connect(function()
            if ScriptUnloaded or not anyEnabled() then stop(); return end
            local now = os.clock()
            if now - lastTick < 0.08 then return end
            lastTick = now
            if not playing() then return end
            if now - lastDiscovery >= 3 then lastDiscovery = now; discover() end
            local character, root, humanoid = parts(LocalPlayer)
            if not root then return end
            local ok, err = pcall(function()
                autoSteal(now, character, root, humanoid)
            end)
            if not ok and not warned then
                warned = true
                NexusUI:Notify({Title = "Smart Support", Content = "Feature error: " .. tostring(err), Duration = 5})
            end
        end)
    end
    Tabs.Main:AddSection("Smart Support", "Right")
    for _, control in ipairs({
        {"AutoSteal", "Smart Auto Steal", "Uses the ordinary Steal action only in range, facing the carrier and outside ball protection"},
    }) do
        local key = control[1]
        Tabs.Main:AddToggle("PRIME_SS_" .. key, {Title = control[2], Description = control[3], Default = false,
            Callback = function(value)
                config[key] = value == true and not ScriptUnloaded
                if anyEnabled() then start() else stop() end
            end})
    end
    for _, control in ipairs({{"StealRange", "Auto Steal Range", 3, 15}}) do
        local key = control[1]
        Tabs.Main:AddSlider("PRIME_SS_" .. key, {Title = control[2], Default = config[key], Min = control[3], Max = control[4], Step = 1, Rounding = 0,
            Callback = function(value) if finite(value) then config[key] = math.max(control[3], math.min(control[4], value)) end end})
    end
    Tabs.Main:SetActiveSection(MainSection)
    RegisterUnloadCallback(function()
        for _, key in ipairs({"AutoSteal"}) do config[key] = false end
        stop()
    end)
end
-- END PRIME SMART SUPPORT v1


-- Cosmetic selector (Additional)
CosmeticAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Cosmetics")
ActiveCosmeticContainer = nil
ActiveCosmeticTrove = nil
SelectedCosmeticName = "None"

function CosmeticWeld(part0, part1)
    if not part0 or not part1 then
        return nil
    end
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = part0
    weld.Part1 = part1
    weld.Parent = part1
    return weld
end

function SetCosmeticVfxEnabled(root, enabled)
    if not root then return end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("ParticleEmitter")
            or descendant:IsA("Trail")
            or descendant:IsA("Beam")
            or descendant:IsA("Fire")
            or descendant:IsA("Smoke")
            or descendant:IsA("Sparkles")
            or descendant:IsA("PointLight")
            or descendant:IsA("SpotLight")
            or descendant:IsA("SurfaceLight") then
            descendant.Enabled = enabled
        end
    end
end

function NewCosmeticTrove()
    local trove = {Items = {}}

    function trove:Add(item)
        if item ~= nil then
            table.insert(self.Items, item)
        end
        return item
    end

    function trove:Clean()
        for index = #self.Items, 1, -1 do
            local item = self.Items[index]
            local itemType = typeof(item)

            if itemType == "function" then
                pcall(item)
            elseif itemType == "RBXScriptConnection" then
                pcall(function()
                    if item.Connected then
                        item:Disconnect()
                    end
                end)
            elseif itemType == "Instance" then
                pcall(function()
                    item:Destroy()
                end)
            elseif itemType == "thread" then
                pcall(task.cancel, item)
            elseif type(item) == "table" then
                if type(item.Destroy) == "function" then
                    pcall(function() item:Destroy() end)
                elseif type(item.Clean) == "function" then
                    pcall(function() item:Clean() end)
                elseif type(item.Disconnect) == "function" then
                    pcall(function() item:Disconnect() end)
                end
            end

            self.Items[index] = nil
        end
    end

    return trove
end

function setupRankedBadge(_, cosmeticModel, _)
	local badgeVisuals = ReplicatedStorage.Assets.Misc.RankedBadgeVisuals:Clone()
	badgeVisuals.Parent = cosmeticModel
	badgeVisuals.Enabled = true
end

function setupMascot(character, mascotModel, trove)
	for _, accessory in character:GetChildren() do
		if accessory:IsA("Accessory") then
			local originalTransparency = accessory.Handle.Transparency
			accessory.Handle.Transparency = 1

			trove:Add(function()
				accessory.Handle.Transparency = originalTransparency
			end)
		end
	end

	for _, bodyModel in mascotModel:GetChildren() do
		for _, part in bodyModel:GetChildren() do
			if part ~= bodyModel.Main then
				local internalWeld = trove:Add(Instance.new("WeldConstraint"))
				internalWeld.Parent = part
				internalWeld.Part0 = bodyModel.Main
				internalWeld.Part1 = part
			end
		end

		bodyModel.Main.CFrame = character:FindFirstChild(bodyModel.Name).CFrame

		local bodyWeld = trove:Add(Instance.new("WeldConstraint"))
		bodyWeld.Parent = bodyModel.Main
		bodyWeld.Part0 = character:FindFirstChild(bodyModel.Name)
		bodyWeld.Part1 = bodyModel.Main
	end

	local player = Players:GetPlayerFromCharacter(character)

	if player ~= nil then
		for _, descendant in mascotModel:GetDescendants() do
			if descendant:IsA("SurfaceAppearance") and descendant.Parent.Name == "Jersey" then
				descendant.Color = player.Team:GetAttribute("Color")
			end
		end

		trove:Add(player:GetPropertyChangedSignal("Team"):Connect(function()
			for _, descendant in mascotModel:GetDescendants() do
				if descendant:IsA("SurfaceAppearance") and descendant.Parent.Name == "Jersey" then
					descendant.Color = player.Team:GetAttribute("Color")
				end
			end
		end))
	end
end

function attachPartsByName(character, cosmeticModel, _)
	for _, cosmeticPart in cosmeticModel:GetChildren() do
		local characterPart = character:FindFirstChild(cosmeticPart.Name)

		if characterPart then
			cosmeticPart.CFrame = characterPart.CFrame
			cosmeticPart.WeldConstraint.Part1 = characterPart
		end
	end
end

function attachHandleToHead(character, cosmetic, trove)
	cosmetic.Handle:PivotTo(character.Head.CFrame)
	trove:Add(CosmeticWeld(character.Head, cosmetic.Handle))
end

CosmeticHandlers = {
	["Tentacles"] = function(character, cosmeticModel, trove)
		local torso = character:FindFirstChild("Torso")

		for index = 1, 4 do
			local tentacle = cosmeticModel:FindFirstChild(("tentacle%s"):format(index))
			tentacle.Cylinder.CFrame =
				torso.CFrame
				* CFrame.new(0, -3, 0)
				* CFrame.Angles(0, math.pi, 0)

			trove:Add(CosmeticWeld(torso, tentacle.Cylinder))
			trove:Add(
				tentacle.AnimationController.Animator:LoadAnimation(
					cosmeticModel.Anims:FindFirstChild(tostring(index))
				)
			):Play(0)
		end
	end,

	["Clouds"] = function(character, cosmeticModel, trove)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			local characterPart = character:FindFirstChild(cosmeticPart.Name)
			cosmeticPart.CFrame = characterPart.CFrame
			trove:Add(CosmeticWeld(characterPart, cosmeticPart))
		end
	end,

	["Psychic Jacket"] = function(character, cosmeticModel, trove)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			local characterPart = character:FindFirstChild(cosmeticPart.Name)
			cosmeticPart.CFrame = characterPart.CFrame
			trove:Add(CosmeticWeld(characterPart, cosmeticPart))
		end
	end,

	["Cyber Jacket"] = function(character, cosmeticModel, trove)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			local characterPart = character:FindFirstChild(cosmeticPart.Name)
			cosmeticPart.CFrame = characterPart.CFrame
			trove:Add(CosmeticWeld(characterPart, cosmeticPart))
		end
	end,

	["Brother Duo"] = function(character, companionCharacter, trove)
		local player = Players:GetPlayerFromCharacter(character)
		local fallbackUserId = nil
		local friendUserId

		if player == nil then
			friendUserId = fallbackUserId
		else
			local success
			success, friendUserId = pcall(function()
				local friends = Players:GetFriendsAsync(player.UserId):GetCurrentPage()
				return friends[Random.new():NextInteger(1, #friends)].Id
			end)

			if success ~= true then
				friendUserId = fallbackUserId
			end
		end

		local description = trove:Add(Players:GetHumanoidDescriptionFromUserId(friendUserId))
		companionCharacter.Humanoid:ApplyDescriptionReset(description)
		companionCharacter:ScaleTo(0.66)

		companionCharacter.HumanoidRootPart.CFrame =
			character.HumanoidRootPart.CFrame * CFrame.new(0.2, 0.47, 0.35)

		trove:Add(CosmeticWeld(character.HumanoidRootPart, companionCharacter.HumanoidRootPart))

		companionCharacter.Humanoid.Animator
			:LoadAnimation(ReplicatedStorage.Assets.EmoteAnimations.TodoReceiver)
			:Play(0)
	end,

	["S1 Bronze Badge"] = setupRankedBadge,
	["S1 Silver Badge"] = setupRankedBadge,
	["S1 Gold Badge"] = setupRankedBadge,
	["S1 Iron Badge"] = setupRankedBadge,
	["S1 Diamond Badge"] = setupRankedBadge,
	["S1 Platinum Badge"] = setupRankedBadge,
	["S1 Champion Badge"] = setupRankedBadge,

	["S2 Bronze Badge"] = setupRankedBadge,
	["S2 Silver Badge"] = setupRankedBadge,
	["S2 Gold Badge"] = setupRankedBadge,
	["S2 Iron Badge"] = setupRankedBadge,
	["S2 Diamond Badge"] = setupRankedBadge,
	["S2 Platinum Badge"] = setupRankedBadge,
	["S2 Champion Badge"] = setupRankedBadge,

	["Sun Man"] = setupMascot,
	["Dog Mascot"] = setupMascot,
	["Chrollo Mascot"] = setupMascot,
	["Hawk Mascot"] = setupMascot,
	["Duck Mascot"] = setupMascot,
	["BlueBee Mascot"] = setupMascot,
	["Bull Mascot"] = setupMascot,
	["Teddy Mascot"] = setupMascot,
	["Jofu Mascot"] = setupMascot,
	["Tatlis Mascot"] = setupMascot,

	["Straw Hat"] = function(character, cosmetic, trove)
		cosmetic.Handle:PivotTo(character.Head.CFrame)
		trove:Add(CosmeticWeld(character.Head, cosmetic.Handle))
	end,

	["Pineapple Head"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.5, 0)
					* CFrame.Angles(math.pi / 2, 0, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Current Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, 0, 0)
					* CFrame.Angles(0, math.pi, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Phoenix Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.5, 0)
					* CFrame.Angles(math.pi / 2, 0, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Golden Backpack"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.new(0, 0.114, 0.03)
					* CFrame.Angles(0, math.pi, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Demon Dog"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Meteor Aura"] = function(character, cosmeticModel, _)
		cosmeticModel.Root.Value = character.HumanoidRootPart
	end,

	["Skateboard"] = function(character, cosmetic, _)
		cosmetic.Handle.CFrame =
			character.Torso.CFrame
				* CFrame.new(0, 0, 0.5)
				* cosmetic.Handle.BodyBackAttachment.CFrame:Inverse()

		CosmeticWeld(cosmetic.Handle, character.Torso)
	end,

	["Cat!"] = function(character, cosmeticModel, trove)
		local animationTrack =
			cosmeticModel.AnimationController.Animator:LoadAnimation(cosmeticModel.Animation)

		animationTrack:Play()

		cosmeticModel.Cat.CFrame =
			character.Torso.CFrame
				* CFrame.new(0, 0.2, 0.55)
				* CFrame.fromEulerAngles(0, math.pi, 0)

		CosmeticWeld(cosmeticModel.Cat, character.Torso)

		trove:Add(function()
			animationTrack:Destroy()
		end)
	end,

	["Unlimited"] = function(character, cosmeticModel, trove)
		local animationTrack =
			cosmeticModel.AnimationController.Animator:LoadAnimation(cosmeticModel.Animation)

		animationTrack:Play()

		cosmeticModel.Icosphere.CFrame =
			character.Torso.CFrame * CFrame.new(0, 0, 1)

		CosmeticWeld(cosmeticModel.Icosphere, character.Torso)
		SetCosmeticVfxEnabled(cosmeticModel, true)

		trove:Add(function()
			animationTrack:Destroy()
		end)
	end,

	["Winner"] = function(character, cosmeticPart, trove)
		cosmeticPart.Parent = ActiveCosmeticContainer or workspace

		cosmeticPart.CFrame =
			character["Right Arm"].CFrame
				* CFrame.new(0.35, 0, 0)
				* CFrame.fromEulerAnglesXYZ(0, -math.pi / 2, 0)

		CosmeticWeld(cosmeticPart, character["Right Arm"])

		trove:Add(task.spawn(function()
			local hueDegrees = 0

			while task.wait(1) do
				hueDegrees = (hueDegrees + 20) % 360

				local color = Color3.fromHSV(hueDegrees / 360, 0.7, 0.7)
				local red = color.R * 20
				local green = color.G * 20
				local blue = color.B * 20

				TweenService:Create(
					cosmeticPart.Mesh,
					TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						VertexColor = Vector3.new(red, green, blue),
					}
				):Play()
			end
		end))
	end,

	["Oni's Wrath"] = function(character, cosmeticModel, _)
		cosmeticModel.WeldLeftArm.Weld.Part0 = character["Left Arm"]
		cosmeticModel.WeldRightArm.Weld.Part0 = character["Right Arm"]
		cosmeticModel.WeldTorso.Weld.Part0 = character.Torso
	end,

	["Vampire Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.5, 0)
					* CFrame.Angles(math.pi / 2, 0, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Emperor Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.7, 0.65)
					* CFrame.Angles(math.pi / 2, 0, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Cherry Blossom Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.5, 0)
					* CFrame.Angles(math.pi / 2, 0, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Gold Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.6, 1.15)
					* CFrame.fromEulerAnglesYXZ(math.pi / 2, math.pi, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Model"] = function(character, cosmeticPart, _)
		cosmeticPart.CFrame = character.HumanoidRootPart.CFrame
		CosmeticWeld(cosmeticPart, character.HumanoidRootPart)
	end,

	["Perfect Wings"] = function(character, cosmeticModel, trove)
		local animationTrack =
			cosmeticModel.AnimationController.Animator:LoadAnimation(cosmeticModel.Animation)

		animationTrack:Play()

		cosmeticModel:PivotTo(
			character.Torso.BodyBackAttachment.WorldCFrame
				* CFrame.Angles(0, math.pi, 0)
		)

		CosmeticWeld(cosmeticModel["Plane.001"], character.Torso)

		trove:Add(function()
			animationTrack:Destroy()
		end)
	end,

	["Rulebook Backpack"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.new(-0.375, -0.05, 0)
					* CFrame.Angles(0, -math.pi / 2, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Referee Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.6, 0.5)
					* CFrame.Angles(0, -math.pi / 2, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Referee Hat"] = attachHandleToHead,

	["Old Radio"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, math.pi / 2, 0)
					* CFrame.new(-0.55, 1, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Duck Hat"] = attachHandleToHead,

	["Heart Balloon"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, -math.pi / 2, 0)
					* CFrame.new(0.75, 0.25, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Joker Cape"] = function(character, cosmetic, trove)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.CFrame
					* CFrame.new(0, -0.477, 0.897)
					* CFrame.Angles(0, math.pi / 2, -math.pi / 12)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		else
			for _, torso in { character.Torso } do
				torso:SetAttribute("ColliderKey", "Cape")
				torso:SetAttribute("ColliderShape", "Box")
				torso:AddTag("SmartCollider")

				trove:Add(function()
					torso:SetAttribute("ColliderKey", nil)
					torso:SetAttribute("ColliderShape", nil)
					torso:RemoveTag("SmartCollider")
				end)
			end
		end
	end,

	["Wazzup! Mask"] = attachHandleToHead,
	["Ghost Mask"] = attachHandleToHead,
	["Cyber Glasses"] = attachHandleToHead,
	["Cyber Helmet"] = attachHandleToHead,

	["Cyber Wings"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, -math.pi / 2, 0)
					* CFrame.new(1.05, 0.3, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Dino Backpack"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, -math.pi / 2, 0)
					* CFrame.new(0.34, 0.25, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Popstar Keytar"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, math.pi / 2, math.pi / 4)
					* CFrame.new(-0.125, -1, 0.25)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Popstar Guitar"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, math.pi / 2, math.pi / 4)
					* CFrame.new(-0.3, -1.4, 0.1)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Popstar Backpack"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(character.Torso.CFrame)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Hanging Shoes"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.new(0, 0.1, 0.175)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["King's Crown"] = attachHandleToHead,

	["Air's Trophy"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyFrontAttachment.WorldCFrame
					* CFrame.Angles(0, 0, math.pi / 6)
					* CFrame.new(0, 0.5, 0.5)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Samurai Hat"] = attachHandleToHead,

	["Dual Katanas"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(character.Torso.CFrame)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Dragon Wrap"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyFrontAttachment.WorldCFrame
					* CFrame.Angles(0, math.pi, 0)
					* CFrame.new(-0.3, -0.45, 0.85)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Viki"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, math.pi / 2, 0)
					* CFrame.new(-0.058, -0.067, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Ace Backpack"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, -math.pi / 2, 0)
					* CFrame.new(-0.28, 0.062, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Crystal Arms"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Arm Wraps"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Witch Hat"] = attachHandleToHead,

	["Arm Band"] = function(character, cosmeticPart, _)
		cosmeticPart.Weld.Part0 = character:FindFirstChild("Left Arm")
	end,

	["Demon Wings"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.Angles(0, -math.pi / 2, 0)
					* CFrame.new(1.09, 1.4, 0)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Ancient Vines"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Watcher Eye"] = attachHandleToHead,
	["Giant Tongue"] = attachHandleToHead,
	["0 IQ"] = attachHandleToHead,
	["Obsessed Octopus"] = attachHandleToHead,

	["Magma Arms"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Glitchy"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Mech"] = function(character, cosmeticModel, trove)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			local characterPart = character:FindFirstChild(cosmeticPart.Name)

			if characterPart then
				cosmeticPart.Weld.Part0 = characterPart
				characterPart.Transparency = 1

				trove:Add(function()
					characterPart.Transparency = 0
				end)
			end
		end
	end,

	["Love Chain"] = function(character, cosmetic, _)
		if true then
			local handle = cosmetic.Handle
			handle.Parent = ActiveCosmeticContainer or character
			cosmetic:Destroy()

			handle:PivotTo(
				character.Torso.BodyBackAttachment.WorldCFrame
					* CFrame.new(0, 0.565, -0.588)
			)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = character.Torso
			weld.Part1 = handle
			weld.Parent = handle
		end
	end,

	["Cursed Energy"] = function(character, cosmeticModel, _)
		for _, cosmeticPart in cosmeticModel:GetChildren() do
			cosmeticPart.Weld.Part0 = character:FindFirstChild(cosmeticPart.Name)
		end
	end,

	["Black Shock Aura"] = attachPartsByName,
	["Chrollo Aura"] = attachPartsByName,

	["Black Eye Aura"] = attachHandleToHead,
	["Gold Eye Aura"] = attachHandleToHead,
	["Skarp Eye Aura"] = attachHandleToHead,
}


function CollectCosmeticNames()
    local names = {"None"}
    for _, cosmetic in ipairs(CosmeticAssets:GetChildren()) do
        table.insert(names, cosmetic.Name)
    end
    table.sort(names, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a:lower() < b:lower()
    end)
    return names
end

function DestroyActiveCosmetic()
    if ActiveCosmeticTrove then
        ActiveCosmeticTrove:Clean()
        ActiveCosmeticTrove = nil
    end

    if ActiveCosmeticContainer then
        pcall(function()
            ActiveCosmeticContainer:Destroy()
        end)
        ActiveCosmeticContainer = nil
    end
end

function AttachFallbackCosmetic(character, cosmetic, trove)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")
    local root = character:FindFirstChild("HumanoidRootPart")

    if cosmetic:IsA("Accessory") and humanoid then
        local ok = pcall(function()
            humanoid:AddAccessory(cosmetic)
        end)
        if ok then
            trove:Add(cosmetic)
            return true
        end
    end

    local attached = false
    local descendants = cosmetic:GetDescendants()
    for _, part in ipairs(descendants) do
        if part:IsA("BasePart") then
            local characterPart = character:FindFirstChild(part.Name)
            if characterPart and characterPart:IsA("BasePart") then
                part.CFrame = characterPart.CFrame
                trove:Add(CosmeticWeld(characterPart, part))
                attached = true
            else
                local weld = part:FindFirstChildWhichIsA("Weld") or part:FindFirstChildWhichIsA("WeldConstraint")
                if weld and weld.Part0 == nil then
                    local target = character:FindFirstChild(part.Name)
                    if target and target:IsA("BasePart") then
                        weld.Part0 = target
                        attached = true
                    end
                end
            end
        end
    end

    if attached then
        return true
    end

    local handle = cosmetic:FindFirstChild("Handle", true)
    if handle and handle:IsA("BasePart") and head then
        handle:PivotTo(head.CFrame)
        trove:Add(CosmeticWeld(head, handle))
        return true
    end

    local mainPart = nil
    if cosmetic:IsA("BasePart") then
        mainPart = cosmetic
    elseif cosmetic:IsA("Model") then
        mainPart = cosmetic.PrimaryPart or cosmetic:FindFirstChildWhichIsA("BasePart", true)
    else
        mainPart = cosmetic:FindFirstChildWhichIsA("BasePart", true)
    end

    if mainPart and root then
        if cosmetic:IsA("Model") then
            cosmetic:PivotTo(root.CFrame)
        else
            mainPart.CFrame = root.CFrame
        end
        trove:Add(CosmeticWeld(root, mainPart))
        return true
    end

    return false
end

function EquipCosmetic(cosmeticName, silent)
    DestroyActiveCosmetic()
    SelectedCosmeticName = cosmeticName or "None"

    if SelectedCosmeticName == "None" then
        return true
    end

    local source = CosmeticAssets:FindFirstChild(SelectedCosmeticName)
    if not source then
        if not silent then
            NexusUI:Notify({
                Title = "Cosmetics",
                Content = "Cosmetic not found: " .. tostring(SelectedCosmeticName),
                Duration = 2,
            })
        end
        return false
    end

    local character = LocalPlayer.Character
    if not character or not character.Parent then
        if not silent then
            NexusUI:Notify({
                Title = "Cosmetics",
                Content = "Character is not ready.",
                Duration = 2,
            })
        end
        return false
    end

    local container = Instance.new("Folder")
    container.Name = "Nexus_SelectedCosmetic"
    container.Parent = character

    local trove = NewCosmeticTrove()
    ActiveCosmeticContainer = container
    ActiveCosmeticTrove = trove

    local cosmetic = source:Clone()
    cosmetic.Name = "NexusCosmetic_" .. source.Name
    cosmetic.Parent = container
    trove:Add(cosmetic)

    local handler = CosmeticHandlers[source.Name]
    local success, result
    if handler then
        success, result = pcall(handler, character, cosmetic, trove)
    else
        success, result = pcall(AttachFallbackCosmetic, character, cosmetic, trove)
        if success and result ~= true then
            success = false
            result = "No compatible attachment point was found"
        end
    end

    if not success then
        DestroyActiveCosmetic()
        if not silent then
            NexusUI:Notify({
                Title = "Cosmetics",
                Content = "Failed to attach " .. source.Name .. ": " .. tostring(result),
                Duration = 3,
            })
        end
        return false
    end

    return true
end

cosmeticDropdown = nil

cosmeticRefreshQueued = false
function QueueCosmeticRefresh()
    if cosmeticRefreshQueued then return end
    cosmeticRefreshQueued = true
    task.defer(function()
        cosmeticRefreshQueued = false
        if ScriptUnloaded or not cosmeticDropdown then return end

        cosmeticDropdown:SetValues(CollectCosmeticNames())
        if SelectedCosmeticName ~= "None" and not CosmeticAssets:FindFirstChild(SelectedCosmeticName) then
            SelectedCosmeticName = "None"
            DestroyActiveCosmetic()
            cosmeticDropdown:SetValue("None")
        end
    end)
end

TrackScriptConnection(CosmeticAssets.ChildAdded:Connect(QueueCosmeticRefresh))
TrackScriptConnection(CosmeticAssets.ChildRemoved:Connect(QueueCosmeticRefresh))
TrackScriptConnection(LocalPlayer.CharacterAdded:Connect(function(character)
    DestroyActiveCosmetic()
    if SelectedCosmeticName == "None" then return end

    task.defer(function()
        character:WaitForChild("HumanoidRootPart", 10)
        if not ScriptUnloaded and LocalPlayer.Character == character and SelectedCosmeticName ~= "None" then
            EquipCosmetic(SelectedCosmeticName, true)
        end
    end)
end))

RegisterUnloadCallback(function()
    SelectedCosmeticName = "None"
    DestroyActiveCosmetic()
end)


end}
