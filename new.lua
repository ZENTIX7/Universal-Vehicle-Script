-- ==========================================
-- UNIVERSAL VEHICLE SCRIPT PREMIUM v11
-- Changes vs v10:
--  * Soft Suspension no longer lowers the car. It now compensates
--    FreeLength as stiffness drops so resting ride height stays put,
--    while still making the spring softer/bouncier.
--  * Camber & Offset BETA note now uses a red-glowing attention pulse.
-- ==========================================

local function load()
    print("Universal Vehicle Script Loaded Successfully!")
    warn("made by moon @52bg")
end

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
load()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local configFolderName = "UVS_StanceConfigs"
pcall(function()
	if not isfolder(configFolderName) then makefolder(configFolderName) end
end)

-- ==========================================
-- UTILITIES
-- ==========================================
local function GetVehicleFromDescendant(Descendant)
	return
		Descendant:FindFirstAncestor(LocalPlayer.Name .. "'s Car") or
		(Descendant:FindFirstAncestor("Body") and Descendant:FindFirstAncestor("Body").Parent) or
		(Descendant:FindFirstAncestor("Misc") and Descendant:FindFirstAncestor("Misc").Parent) or
		Descendant:FindFirstAncestorWhichIsA("Model")
end

local function GetPositionFromWorld(seat, worldPos)
	if not seat then return "Unknown" end
	local relativePos = seat.CFrame:PointToObjectSpace(worldPos)
	local side = relativePos.X > 0 and "Right" or "Left"
	local frontBack = relativePos.Z > 0 and "Back" or "Front"
	return frontBack .. side
end

local function GetWheelPosition(seat, spring)
	if not seat then return "Unknown" end
	local targetPos
	if spring.Attachment0 then
		targetPos = spring.Attachment0.WorldPosition
	elseif spring.Attachment1 then
		targetPos = spring.Attachment1.WorldPosition
	else
		targetPos = spring.Parent.Position
	end
	return GetPositionFromWorld(seat, targetPos)
end

-- ==========================================
-- GLOBAL STATE
-- ==========================================
local velocityEnabled = true
local flightEnabled = false
local flightSpeed = 1

-- DRIFT / GRIP (logic now matches the Venyx script)
local driftModeEnabled = false
local targetFriction = 0.20
local driftPowerMult = 7      -- Artificial Horsepower (default 7)
local driftSteerAssist = 6    -- Artificial Steering / Handling assist (default 6)

local cachedVehicle = nil
local cachedParts = {}
local originalProperties = {}

local heightOverrideEnabled = false
local masterHeightOffset = 0
local stanceOffsets = { FrontLeft = 0, FrontRight = 0, BackLeft = 0, BackRight = 0 }

-- SOFT SUSPENSION (softens springs only, keeps ride height constant)
local softSuspensionEnabled = false
local softSuspensionAmount = 0
local originalSpringStiffness = {}
local originalSpringDamping = {}
local originalSpringFreeForSoft = {}   -- baseline free length for soft compensation

local camberEnabled = false
local masterCamber = 0
local camberOffsets = { FrontLeft = 0, FrontRight = 0, BackLeft = 0, BackRight = 0 }

local offsetEnabled = false
local masterWheelOffset = 0
local wheelOffsets = { FrontLeft = 0, FrontRight = 0, BackLeft = 0, BackRight = 0 }

local cachedSprings = {}
local originalSprings = {}
local originalSpringLimits = {}
local lastAppliedFreeLength = {}

local cachedWheels = {}

-- AUTO DRIVE FARM
local autoDriveEnabled = false
local autoDriveSpeed = 50
local autoDriveTpInterval = 1.5
local autoDriveStartCFrame = nil
local autoDriveLastTp = 0

-- NATURAL SPEED PICK-UP (anti auto-drive bypass)
local naturalSpeedEnabled = false
local naturalSpeedFactor = 1
local naturalSpeedTarget = 1
local naturalSpeedNextChange = 0

local velocityEnabledKeyCode = Enum.KeyCode.LeftShift
local qbEnabledKeyCode = Enum.KeyCode.S
local stopVehicleKeyCode = Enum.KeyCode.P
local driftHotkey = Enum.KeyCode.O
local minimizeHotkey = Enum.KeyCode.RightControl

-- ==========================================
-- KEYBIND PARSER
-- ==========================================
local function parseKeybind(v)
    if typeof(v) == "EnumItem" then return v
    elseif type(v) == "string" then
        if v == "None" or v == "Unknown" or v == "" then return Enum.KeyCode.Unknown end
        local ok, res = pcall(function() return Enum.KeyCode[v] end)
        if ok and res then return res end
    elseif type(v) == "table" then
        if v.Key then return parseKeybind(v.Key) end
    end
    return Enum.KeyCode.Unknown
end

local function clearKeybindWidget(widget)
    if not widget then return end
    pcall(function() widget:Set("None") end)
    pcall(function() widget:Set(Enum.KeyCode.Unknown) end)
end

-- ==========================================
-- WINDOW
-- ==========================================
local Window = WindUI:CreateWindow({
    Title = "Universal Vehicle Script",
    Icon = "car",
    Author = "by moon @52bg",
    Folder = "UVS_Hub_Moon",
    Size = UDim2.fromOffset(620, 480),
    MinSize = Vector2.new(560, 350),
    MaxSize = Vector2.new(900, 620),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 200,
    BackgroundImageTransparency = 0.42,
    HideSearchBar = true,
    ScrollBarEnabled = false
})

-- ==========================================
-- ANIMATED NOTE HELPER
-- ==========================================
-- Each entry: { labels = {...}, style = "default" | "redglow" }
local animatedNotes = {}

local function createAnimatedNote(tab, titleText, bodyText, style)
    style = style or "default"
    local para = tab:Paragraph({
        Title = titleText or "Note",
        Desc = bodyText or "",
    })

    task.spawn(function()
        task.wait(0.2)
        local labels = {}
        local function scan(inst)
            for _, c in ipairs(inst:GetDescendants()) do
                if c:IsA("TextLabel") then
                    table.insert(labels, c)
                end
                if c:IsA("Frame") or c:IsA("ImageLabel") then
                    pcall(function()
                        if c.BackgroundColor3 == Color3.fromRGB(255, 145, 25) then
                            c.BackgroundTransparency = 1
                        end
                    end)
                end
            end
        end
        pcall(function()
            if typeof(para) == "table" then
                for _, v in pairs(para) do
                    if typeof(v) == "Instance" then scan(v) end
                end
            elseif typeof(para) == "Instance" then
                scan(para)
            end
        end)
        if #labels > 0 then
            table.insert(animatedNotes, { labels = labels, style = style })
        end
    end)

    return para
end

task.spawn(function()
    -- default pulse: orange <-> red
    local orange   = Color3.fromRGB(255, 145, 25)
    local red      = Color3.fromRGB(255, 60, 60)
    -- red-glow pulse: deep red <-> bright glowing red
    local deepRed  = Color3.fromRGB(150, 10, 10)
    local glowRed  = Color3.fromRGB(255, 70, 70)
    while true do
        local now = tick()
        -- default: slower, smooth
        local tDefault = (math.sin(now * 2.2) + 1) / 2
        local colDefault = orange:Lerp(red, tDefault)
        -- redglow: faster, sharper pulse so it "glows" and grabs attention
        local pulse = (math.sin(now * 4.0) + 1) / 2
        pulse = pulse * pulse                 -- sharpen toward the bright end
        local colGlow = deepRed:Lerp(glowRed, pulse)

        for _, note in ipairs(animatedNotes) do
            local col = (note.style == "redglow") and colGlow or colDefault
            for _, lbl in ipairs(note.labels) do
                if lbl and lbl.Parent then
                    pcall(function()
                        lbl.TextColor3 = col
                        if note.style == "redglow" then
                            -- glow effect via stroke that brightens on the pulse
                            lbl.TextStrokeColor3 = glowRed
                            lbl.TextStrokeTransparency = 0.85 - (pulse * 0.65)
                        end
                    end)
                end
            end
        end
        task.wait(0.03)
    end
end)

-- ==========================================
-- GUI VISIBILITY
-- ==========================================
local guiVisible = true

local function findWindUiContainer()
    local targets = {CoreGui}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then table.insert(targets, pg) end
    for _, container in ipairs(targets) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("ScreenGui") and (child.Name == "WindUI" or child.Name:find("WindUI")) then
                return child
            end
        end
    end
    return nil
end

local function toggleMainGui()
    local handled = false
    pcall(function()
        if Window then
            if Window.Minimized ~= nil then
                if Window.Minimized then
                    if Window.Maximize then Window:Maximize(); handled = true
                    elseif Window.Open then Window:Open(); handled = true end
                else
                    if Window.Minimize then Window:Minimize(); handled = true end
                end
            else
                if guiVisible then
                    if Window.Minimize then Window:Minimize(); handled = true end
                else
                    if Window.Maximize then Window:Maximize(); handled = true
                    elseif Window.Open then Window:Open(); handled = true end
                end
            end
        end
    end)

    if not handled then
        local container = findWindUiContainer()
        if container then
            pcall(function() container.Enabled = not container.Enabled end)
        end
    end

    pcall(function()
        if Window and Window.Minimized ~= nil then
            guiVisible = not Window.Minimized
        else
            guiVisible = not guiVisible
        end
    end)
end

task.spawn(function()
    task.wait(1)
    pcall(function()
        if Window and Window.OnMinimize then end
    end)
end)

-- ==========================================
-- TABS
-- ==========================================
local VehicleTab  = Window:Tab({ Title = "Vehicle & Speed", Icon = "car", Locked = false })
local HandlingTab = Window:Tab({ Title = "Handling & Drift", Icon = "sliders", Locked = false })
local StanceTab   = Window:Tab({ Title = "Stance & Height", Icon = "wrench", Locked = false })
local WheelTab    = Window:Tab({ Title = "Camber & Offset", Icon = "circle-dot", Locked = false })
local AutoTab     = Window:Tab({ Title = "Auto Drive Farm", Icon = "repeat", Locked = false })
local KeybindsTab = Window:Tab({ Title = "GUI Settings", Icon = "keyboard", Locked = false })
local InfoTab     = Window:Tab({ Title = "Information", Icon = "info", Locked = false })

-- ==========================================
-- VEHICLE & SPEED TAB
-- ==========================================
VehicleTab:Section({ Title = "General Controls" })
VehicleTab:Toggle({ Title = "Keybinds Mastery Active", Value = true, Callback = function(v) velocityEnabled = v end })

VehicleTab:Section({ Title = "Drive Speed Controls & Bindings" })

local accelKeybind = VehicleTab:Keybind({
    Title = "Acceleration Drive Modifier Key", Value = "LeftShift",
    Callback = function(v) velocityEnabledKeyCode = parseKeybind(v) end
})
VehicleTab:Button({ Title = "❌ Unbind Acceleration Key", Callback = function()
    velocityEnabledKeyCode = Enum.KeyCode.Unknown
    clearKeybindWidget(accelKeybind)
    WindUI:Notify({Title = "Key Unbound", Content = "Acceleration modifier key removed."})
end })

local brakeKeybind = VehicleTab:Keybind({
    Title = "Deceleration Brake Modifier Key", Value = "S",
    Callback = function(v) qbEnabledKeyCode = parseKeybind(v) end
})
VehicleTab:Button({ Title = "❌ Unbind Deceleration Key", Callback = function()
    qbEnabledKeyCode = Enum.KeyCode.Unknown
    clearKeybindWidget(brakeKeybind)
    WindUI:Notify({Title = "Key Unbound", Content = "Deceleration modifier key removed."})
end })

local stopKeybind = VehicleTab:Keybind({
    Title = "Instant Stop", Value = "P",
    Callback = function(v) stopVehicleKeyCode = parseKeybind(v) end
})
VehicleTab:Button({ Title = "❌ Unbind Instant Stop Key", Callback = function()
    stopVehicleKeyCode = Enum.KeyCode.Unknown
    clearKeybindWidget(stopKeybind)
    WindUI:Notify({Title = "Key Unbound", Content = "Instant stop key removed."})
end })

VehicleTab:Section({ Title = "Flight Framework" })
VehicleTab:Toggle({ Title = "Toggle Flight System", Value = false, Callback = function(v) flightEnabled = v end })
VehicleTab:Slider({ Title = "Flight Precision Speed", Step = 1, Value = { Min = 0, Max = 800, Default = 100 },
    Callback = function(value) flightSpeed = value / 100 end })

VehicleTab:Section({ Title = "Velocity Configuration" })
local velocityMult = 0.025
VehicleTab:Slider({ Title = "Acceleration Multiplier (Thousandths)", Step = 1, Value = { Min = 0, Max = 50, Default = 25 },
    Callback = function(value) velocityMult = value / 1000 end })
local velocityMult2 = 0.150
VehicleTab:Slider({ Title = "Brake Dampening Force (Thousandths)", Step = 1, Value = { Min = 0, Max = 300, Default = 150 },
    Callback = function(value) velocityMult2 = value / 1000 end })

-- ==========================================
-- HANDLING & DRIFT TAB  (logic matches Venyx script)
-- ==========================================
HandlingTab:Section({ Title = "Presets Execution" })
HandlingTab:Button({ Title = "Apply Calibrated Drift Preset", Callback = function()
    driftModeEnabled = true
    targetFriction = 0.20
    driftPowerMult = 7
    driftSteerAssist = 6
    WindUI:Notify({ Title = "Preset Applied", Content = "Applied Power 7 / Assist 6 drifting setup." })
end })
HandlingTab:Button({ Title = "Restore Stock Mechanics", Callback = function()
    -- Reset grip AND power back to factory.
    driftModeEnabled = false
    driftPowerMult = 0
    driftSteerAssist = 0
    targetFriction = 0.20
    WindUI:Notify({ Title = "Mechanics Reset", Content = "Grip and power restored to factory settings." })
end })

HandlingTab:Section({ Title = "Manual Drift & Grip Controls" })
local driftKeybind = HandlingTab:Keybind({ Title = "Grip Toggle Key", Value = "O",
    Callback = function(v) driftHotkey = parseKeybind(v) end })
HandlingTab:Button({ Title = "❌ Unbind Grip Toggle Key", Callback = function()
    driftHotkey = Enum.KeyCode.Unknown
    clearKeybindWidget(driftKeybind)
    WindUI:Notify({Title = "Key Unbound", Content = "Grip toggle key removed."})
end })

HandlingTab:Toggle({ Title = "Manual Drift Mode Toggle", Value = false, Callback = function(v) driftModeEnabled = v end })

HandlingTab:Slider({ Title = "Surface Friction (Tire Grip)", Step = 1, Value = { Min = 0, Max = 1000, Default = 200 },
    Callback = function(value) targetFriction = value / 1000 end })

HandlingTab:Section({ Title = "Drift Power & Handling (throttle driven, W/S/A/D)" })
HandlingTab:Slider({ Title = "Drift: Power Boost", Step = 1, Value = { Min = 0, Max = 100, Default = 7 },
    Callback = function(value) driftPowerMult = value end })
HandlingTab:Slider({ Title = "Drift: Handling / Steering Assist", Step = 1, Value = { Min = 0, Max = 100, Default = 6 },
    Callback = function(value) driftSteerAssist = value end })

-- ==========================================
-- STANCE & HEIGHT TAB
-- ==========================================
StanceTab:Section({ Title = "Stance Setup" })
StanceTab:Toggle({ Title = "Enable Custom Stance Mod", Value = false, Callback = function(v) heightOverrideEnabled = v end })
StanceTab:Slider({ Title = "Master Height Offset (All Axles)", Step = 1, Value = { Min = -300, Max = 600, Default = 0 },
    Callback = function(value) masterHeightOffset = value / 10 end })

StanceTab:Section({ Title = "Per-Wheel Height" })
StanceTab:Slider({Title = "Front Left Height",  Step = 1, Value = {Min = -200, Max = 400, Default = 0}, Callback = function(v) stanceOffsets.FrontLeft  = v / 10 end})
StanceTab:Slider({Title = "Front Right Height", Step = 1, Value = {Min = -200, Max = 400, Default = 0}, Callback = function(v) stanceOffsets.FrontRight = v / 10 end})
StanceTab:Slider({Title = "Rear Left Height",   Step = 1, Value = {Min = -200, Max = 400, Default = 0}, Callback = function(v) stanceOffsets.BackLeft   = v / 10 end})
StanceTab:Slider({Title = "Rear Right Height",  Step = 1, Value = {Min = -200, Max = 400, Default = 0}, Callback = function(v) stanceOffsets.BackRight  = v / 10 end})

-- SOFT SUSPENSION (softens springs WITHOUT lowering ride height)
StanceTab:Section({ Title = "Soft Suspension" })
StanceTab:Toggle({ Title = "Enable Soft Suspension", Value = false, Callback = function(v) softSuspensionEnabled = v end })
StanceTab:Slider({ Title = "Suspension Softness", Step = 1, Value = { Min = 0, Max = 100, Default = 0 },
    Callback = function(value) softSuspensionAmount = value end })
createAnimatedNote(StanceTab, "📝 Note",
    "The more you increase the slider, the SOFTER and bouncier the suspension gets. Ride height STAYS THE SAME — the spring length is auto-compensated so the car does NOT sag while it softens. Set it to 0 for stock feel.")

StanceTab:Section({ Title = "Data Storage Management" })
local saveName = "MyStance"
StanceTab:Input({ Title = "Profile Storage Tag", Placeholder = "Enter config label to save...",
    Callback = function(Text) saveName = Text end })

StanceTab:Button({ Title = "Commit Profile to Storage", Callback = function()
    if saveName == "" then return end
    local data = {
        Master = masterHeightOffset,
        FL = stanceOffsets.FrontLeft, FR = stanceOffsets.FrontRight,
        BL = stanceOffsets.BackLeft, BR = stanceOffsets.BackRight,
        CMaster = masterCamber,
        CFL = camberOffsets.FrontLeft, CFR = camberOffsets.FrontRight,
        CBL = camberOffsets.BackLeft, CBR = camberOffsets.BackRight,
        OMaster = masterWheelOffset,
        OFL = wheelOffsets.FrontLeft, OFR = wheelOffsets.FrontRight,
        OBL = wheelOffsets.BackLeft, OBR = wheelOffsets.BackRight,
        SoftEnabled = softSuspensionEnabled, SoftAmount = softSuspensionAmount
    }
    pcall(function()
        writefile(configFolderName .. "/" .. saveName .. ".json", HttpService:JSONEncode(data))
        WindUI:Notify({Title = "System IO", Content = "Profile saved: " .. saveName})
    end)
end })

StanceTab:Input({ Title = "Restore Active Profile State", Placeholder = "Enter exact label and press ENTER...",
    Callback = function(Text)
        if Text ~= "" then
            pcall(function()
                local readData = readfile(configFolderName .. "/" .. Text .. ".json")
                if readData then
                    local data = HttpService:JSONDecode(readData)
                    masterHeightOffset = data.Master or 0
                    stanceOffsets.FrontLeft  = data.FL or 0
                    stanceOffsets.FrontRight = data.FR or 0
                    stanceOffsets.BackLeft   = data.BL or 0
                    stanceOffsets.BackRight  = data.BR or 0
                    masterCamber = data.CMaster or 0
                    camberOffsets.FrontLeft  = data.CFL or 0
                    camberOffsets.FrontRight = data.CFR or 0
                    camberOffsets.BackLeft   = data.CBL or 0
                    camberOffsets.BackRight  = data.CBR or 0
                    masterWheelOffset = data.OMaster or 0
                    wheelOffsets.FrontLeft  = data.OFL or 0
                    wheelOffsets.FrontRight = data.OFR or 0
                    wheelOffsets.BackLeft   = data.OBL or 0
                    wheelOffsets.BackRight  = data.OBR or 0
                    softSuspensionEnabled = data.SoftEnabled or false
                    softSuspensionAmount = data.SoftAmount or 0
                    WindUI:Notify({Title = "System IO", Content = "Restored from: " .. Text})
                end
            end)
        end
    end })

-- ==========================================
-- CAMBER & OFFSET TAB
-- ==========================================
WheelTab:Section({ Title = "⚠️ BETA FEATURES" })
createAnimatedNote(WheelTab, "🧪 BETA — Camber & Offset",
    "These features are in BETA. They may NOT work in all games and can be buggy or cause the wheels to jitter. Use with caution.",
    "redglow")

WheelTab:Section({ Title = "Camber Control (tilts wheel parts directly)" })
WheelTab:Toggle({ Title = "Enable Camber Mod [BETA]", Value = false, Callback = function(v) camberEnabled = v end })
WheelTab:Slider({ Title = "Master Camber (degrees)", Step = 1, Value = { Min = -45, Max = 45, Default = 0 },
    Callback = function(v) masterCamber = v end })

WheelTab:Section({ Title = "Per-Wheel Camber (degrees)" })
WheelTab:Slider({Title = "Front Left Camber",  Step = 1, Value = {Min = -45, Max = 45, Default = 0}, Callback = function(v) camberOffsets.FrontLeft  = v end})
WheelTab:Slider({Title = "Front Right Camber", Step = 1, Value = {Min = -45, Max = 45, Default = 0}, Callback = function(v) camberOffsets.FrontRight = v end})
WheelTab:Slider({Title = "Rear Left Camber",   Step = 1, Value = {Min = -45, Max = 45, Default = 0}, Callback = function(v) camberOffsets.BackLeft   = v end})
WheelTab:Slider({Title = "Rear Right Camber",  Step = 1, Value = {Min = -45, Max = 45, Default = 0}, Callback = function(v) camberOffsets.BackRight  = v end})

WheelTab:Section({ Title = "Wheel Track Offset (+ pushes each wheel OUT to its own side)" })
WheelTab:Toggle({ Title = "Enable Wheel Offset Mod [BETA]", Value = false, Callback = function(v) offsetEnabled = v end })
WheelTab:Slider({ Title = "Master Offset (+out / -in)", Step = 1, Value = { Min = -100, Max = 100, Default = 0 },
    Callback = function(v) masterWheelOffset = v / 10 end })

WheelTab:Section({ Title = "Per-Wheel Offset (+out / -in)" })
WheelTab:Slider({Title = "Front Left Offset",  Step = 1, Value = {Min = -80, Max = 80, Default = 0}, Callback = function(v) wheelOffsets.FrontLeft  = v / 10 end})
WheelTab:Slider({Title = "Front Right Offset", Step = 1, Value = {Min = -80, Max = 80, Default = 0}, Callback = function(v) wheelOffsets.FrontRight = v / 10 end})
WheelTab:Slider({Title = "Rear Left Offset",   Step = 1, Value = {Min = -80, Max = 80, Default = 0}, Callback = function(v) wheelOffsets.BackLeft   = v / 10 end})
WheelTab:Slider({Title = "Rear Right Offset",  Step = 1, Value = {Min = -80, Max = 80, Default = 0}, Callback = function(v) wheelOffsets.BackRight  = v / 10 end})

-- ==========================================
-- AUTO DRIVE FARM TAB
-- ==========================================
AutoTab:Section({ Title = "Universal Auto Drive Farm" })
createAnimatedNote(AutoTab, "📝 Note",
    "Use an EMPTY or FLAT road for best results. When you enable the farm it saves your current position, then keeps driving forward and teleports you back to the saved spot every interval — without losing speed or momentum.")

AutoTab:Toggle({ Title = "Enable Auto Drive Farm", Value = false, Callback = function(v)
    autoDriveEnabled = v
    if v then
        local Character = LocalPlayer.Character
        if Character then
            local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
            if Humanoid and Humanoid.SeatPart and Humanoid.SeatPart:IsA("VehicleSeat") then
                autoDriveStartCFrame = Humanoid.SeatPart.CFrame
                autoDriveLastTp = tick()
                naturalSpeedFactor = 1
                naturalSpeedTarget = 1
                naturalSpeedNextChange = tick() + math.random(3, 6)
                WindUI:Notify({ Title = "Auto Drive", Content = "Start position saved. Driving forward now." })
            else
                autoDriveEnabled = false
                WindUI:Notify({ Title = "Auto Drive", Content = "You must be seated in a vehicle to start!" })
            end
        else
            autoDriveEnabled = false
        end
    else
        autoDriveStartCFrame = nil
        WindUI:Notify({ Title = "Auto Drive", Content = "Auto Drive Farm stopped." })
    end
end })

AutoTab:Button({ Title = "📍 Re-Save Current Position", Callback = function()
    local Character = LocalPlayer.Character
    if Character then
        local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
        if Humanoid and Humanoid.SeatPart and Humanoid.SeatPart:IsA("VehicleSeat") then
            autoDriveStartCFrame = Humanoid.SeatPart.CFrame
            autoDriveLastTp = tick()
            WindUI:Notify({ Title = "Auto Drive", Content = "Start position updated to current spot." })
        else
            WindUI:Notify({ Title = "Auto Drive", Content = "Sit in a vehicle first." })
        end
    end
end })

AutoTab:Slider({ Title = "Drive Speed (studs/sec)", Step = 1, Value = { Min = 1, Max = 500, Default = 50 },
    Callback = function(v) autoDriveSpeed = v end })

AutoTab:Slider({ Title = "Teleport Interval (seconds x10)", Step = 1, Value = { Min = 1, Max = 100, Default = 15 },
    Callback = function(v) autoDriveTpInterval = v / 10 end })

AutoTab:Section({ Title = "Anti-Detection" })
AutoTab:Toggle({ Title = "Natural Speed Pick-Up", Value = false, Callback = function(v)
    naturalSpeedEnabled = v
    if v then
        naturalSpeedFactor = 1
        naturalSpeedTarget = 1
        naturalSpeedNextChange = tick() + math.random(3, 6)
    else
        naturalSpeedFactor = 1
        naturalSpeedTarget = 1
    end
end })
createAnimatedNote(AutoTab, "⚠️ Natural Speed Pick-Up",
    "This makes the car SOMETIMES randomly kinda brake and lower its speed, then pick the speed back up again randomly — mimicking a real human driver. This helps BYPASS some games' anti auto-drive detection. Expect occasional slowdowns; that is intentional.")

-- ==========================================
-- GUI SETTINGS TAB
-- ==========================================
KeybindsTab:Section({ Title = "Interface Tuning" })
local minimizeKeybind = KeybindsTab:Keybind({ Title = "Minimize / Restore GUI Key", Value = "RightControl",
    Callback = function(v) minimizeHotkey = parseKeybind(v) end })
KeybindsTab:Button({ Title = "❌ Unbind Minimize Key", Callback = function()
    minimizeHotkey = Enum.KeyCode.Unknown
    clearKeybindWidget(minimizeKeybind)
    WindUI:Notify({Title = "Key Unbound", Content = "Minimize GUI key removed."})
end })
KeybindsTab:Button({ Title = "🔽 Minimize GUI Now", Callback = function()
    pcall(function() if Window and Window.Minimize then Window:Minimize() end end)
    guiVisible = false
end })

-- ==========================================
-- INFORMATION TAB
-- ==========================================
InfoTab:Section({ Title = "Product Identity Attribution" })
InfoTab:Button({ Title = "Script Created by: moon @52bg", Callback = function() end })
InfoTab:Section({ Title = "Community Network Access" })
InfoTab:Button({ Title = "Copy Discord Link", Callback = function()
    setclipboard("https://discord.gg/aedqyFNS3F")
    WindUI:Notify({ Title = "System IO", Content = "Discord link copied to clipboard." })
end })

-- ==========================================
-- SPRING LIMIT HELPERS (used for height)
-- ==========================================
local function unlockSpring(spring)
    if originalSpringLimits[spring] == nil then
        originalSpringLimits[spring] = { limits = spring.LimitsEnabled, max = spring.MaxLength, min = spring.MinLength }
    end
    pcall(function() spring.LimitsEnabled = true end)
    pcall(function() spring.MaxLength = 1000 end)
    pcall(function() spring.MinLength = 0 end)
end

local function restoreSpring(spring)
    local lim = originalSpringLimits[spring]
    if lim then
        pcall(function() spring.LimitsEnabled = lim.limits end)
        pcall(function() spring.MaxLength = lim.max end)
        pcall(function() spring.MinLength = lim.min end)
    end
    local len = originalSprings[spring]
    if len then pcall(function() spring.FreeLength = len end) end
    if originalSpringStiffness[spring] ~= nil then
        pcall(function() spring.Stiffness = originalSpringStiffness[spring] end)
    end
    if originalSpringDamping[spring] ~= nil then
        pcall(function() spring.Damping = originalSpringDamping[spring] end)
    end
    lastAppliedFreeLength[spring] = nil
end

-- ==========================================
-- WHEEL PART CACHE (camber / offset)
-- ==========================================
local function isWheelPart(part)
	local n = part.Name:lower()
	return n:find("wheel") or n:find("tire") or n:find("tyre") or n:find("rim")
end

local function buildWheelCache(Vehicle, SeatPart)
	cachedWheels = {}
	local seen = {}

	for _, spring in pairs(cachedSprings) do
		local att = spring.Attachment1 or spring.Attachment0
		local part = att and att.Parent
		if part and part:IsA("BasePart") and not seen[part] then
			seen[part] = true
			table.insert(cachedWheels, {
				part = part,
				position = GetPositionFromWorld(SeatPart, part.Position),
			})
		end
	end

	if #cachedWheels == 0 then
		for _, obj in pairs(Vehicle:GetDescendants()) do
			if obj:IsA("BasePart") and isWheelPart(obj) and not seen[obj] then
				seen[obj] = true
				table.insert(cachedWheels, {
					part = obj,
					position = GetPositionFromWorld(SeatPart, obj.Position),
				})
			end
		end
	end
end

local function applyWheelTransform(seat, w)
	local part = w.part
	if not part or not part.Parent then return end

	local pos = w.position
	local side = (pos == "FrontRight" or pos == "BackRight") and 1 or -1

	local seatCF = seat.CFrame
	local localCF = seatCF:ToObjectSpace(part.CFrame)

	local camberDeg = camberEnabled and (masterCamber + (camberOffsets[pos] or 0)) or 0
	local offStud = offsetEnabled and (masterWheelOffset + (wheelOffsets[pos] or 0)) or 0

	local delta = CFrame.new()
	if offStud ~= 0 then
		delta = delta * CFrame.new(offStud * side, 0, 0)
	end
	if camberDeg ~= 0 then
		delta = delta * CFrame.Angles(0, 0, math.rad(camberDeg) * side)
	end

	local newWorld = seatCF * delta * localCF

	pcall(function()
		part.CFrame = newWorld
		part.AssemblyLinearVelocity = part.AssemblyLinearVelocity
	end)
end

-- ==========================================
-- SOFT SUSPENSION APPLY
-- Softens spring stiffness/damping, and compensates FreeLength so the
-- resting ride height stays the same (no sagging / lowering).
-- Returns the extra free-length compensation so the height routine can
-- coexist with it (we apply soft-comp on top of the height target).
-- ==========================================
local function getSoftFactors()
    -- factor = how much stiffness/damping remain (lower = softer)
    local stiffFactor = math.clamp(1 - (softSuspensionAmount / 100) * 0.95, 0.05, 1)
    local dampFactor  = math.clamp(1 - (softSuspensionAmount / 100) * 0.85, 0.05, 1)
    return stiffFactor, dampFactor
end

local function applySoftSuspension(spring, baseFreeLength)
    -- Cache originals once.
    if originalSpringStiffness[spring] == nil then
        pcall(function() originalSpringStiffness[spring] = spring.Stiffness end)
    end
    if originalSpringDamping[spring] == nil then
        pcall(function() originalSpringDamping[spring] = spring.Damping end)
    end
    if originalSpringFreeForSoft[spring] == nil then
        originalSpringFreeForSoft[spring] = originalSprings[spring] or spring.FreeLength
    end

    local baseStiff = originalSpringStiffness[spring] or 0
    local baseDamp  = originalSpringDamping[spring] or 0
    local stiffFactor, dampFactor = getSoftFactors()

    pcall(function()
        if baseStiff > 0 then spring.Stiffness = baseStiff * stiffFactor end
        if baseDamp  > 0 then spring.Damping   = baseDamp  * dampFactor end
    end)

    -- Ride-height compensation.
    -- A softer spring sags more under the same car weight. The static
    -- compression of a spring at rest is proportional to 1/Stiffness, so
    -- the extra sag (vs the original) is the rest compression times
    -- (1/stiffFactor - 1). We approximate the original rest compression as
    -- a small fraction of the free length and add it back to FreeLength so
    -- the car settles at the same height.
    if baseStiff > 0 and stiffFactor < 1 then
        local restRef = baseFreeLength or originalSpringFreeForSoft[spring] or spring.FreeLength
        -- Assumed original static compression ~12% of free length.
        local assumedRestComp = restRef * 0.12
        local extraSag = assumedRestComp * ((1 / stiffFactor) - 1)
        return extraSag
    end

    return 0
end

-- ==========================================
-- NATURAL SPEED PICK-UP UPDATER
-- ==========================================
local function updateNaturalSpeed()
    if not naturalSpeedEnabled then
        naturalSpeedFactor = 1
        naturalSpeedTarget = 1
        return
    end

    local now = tick()
    if now >= naturalSpeedNextChange then
        local roll = math.random()
        if roll < 0.45 then
            naturalSpeedTarget = math.random(25, 70) / 100
            naturalSpeedNextChange = now + (math.random(8, 18) / 10)
        else
            naturalSpeedTarget = math.random(90, 100) / 100
            naturalSpeedNextChange = now + math.random(3, 7)
        end
    end

    naturalSpeedFactor = naturalSpeedFactor + (naturalSpeedTarget - naturalSpeedFactor) * 0.08
end

-- ==========================================
-- MAIN LOOP
-- ==========================================
local defaultCharacterParent
RunService.Stepped:Connect(function()
	local Character = LocalPlayer.Character
	if not Character or typeof(Character) ~= "Instance" then return end
	local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
	if not Humanoid then return end
	local SeatPart = Humanoid.SeatPart

	-- FLIGHT
	if flightEnabled then
		if SeatPart and SeatPart:IsA("VehicleSeat") then
			local Vehicle = GetVehicleFromDescendant(SeatPart)
			if Vehicle and Vehicle:IsA("Model") then
				Character.Parent = Vehicle
				if not Vehicle.PrimaryPart then
					if SeatPart.Parent == Vehicle then Vehicle.PrimaryPart = SeatPart
					else Vehicle.PrimaryPart = Vehicle:FindFirstChildWhichIsA("BasePart") end
				end
				local cf = Vehicle:GetPrimaryPartCFrame()
				Vehicle:SetPrimaryPartCFrame(CFrame.new(cf.Position, cf.Position + workspace.CurrentCamera.CFrame.LookVector) * (UserInputService:GetFocusedTextBox() and CFrame.new(0,0,0) or CFrame.new(
					(UserInputService:IsKeyDown(Enum.KeyCode.D) and flightSpeed) or (UserInputService:IsKeyDown(Enum.KeyCode.A) and -flightSpeed) or 0,
					(UserInputService:IsKeyDown(Enum.KeyCode.E) and flightSpeed/2) or (UserInputService:IsKeyDown(Enum.KeyCode.Q) and -flightSpeed/2) or 0,
					(UserInputService:IsKeyDown(Enum.KeyCode.S) and flightSpeed) or (UserInputService:IsKeyDown(Enum.KeyCode.W) and -flightSpeed) or 0)))
				SeatPart.AssemblyLinearVelocity = Vector3.zero
				SeatPart.AssemblyAngularVelocity = Vector3.zero
			end
		end
	else
		Character.Parent = defaultCharacterParent or Character.Parent
		defaultCharacterParent = Character.Parent
	end

	if SeatPart and SeatPart:IsA("VehicleSeat") then
		local Vehicle = GetVehicleFromDescendant(SeatPart)
		if Vehicle then
			-- Rebuild cache on vehicle change
			if Vehicle ~= cachedVehicle then
				if cachedVehicle then
					for part, props in pairs(originalProperties) do
						if part.Parent then part.CustomPhysicalProperties = props end
					end
					for spring in pairs(originalSprings) do
						if spring.Parent then restoreSpring(spring) end
					end
				end
				cachedVehicle = Vehicle
				cachedParts = {}
				originalProperties = {}
				cachedSprings = {}
				originalSprings = {}
				originalSpringLimits = {}
				lastAppliedFreeLength = {}
				originalSpringStiffness = {}
				originalSpringDamping = {}
				originalSpringFreeForSoft = {}

				for _, obj in pairs(Vehicle:GetDescendants()) do
					if obj:IsA("BasePart") then
						table.insert(cachedParts, obj)
						originalProperties[obj] = obj.CustomPhysicalProperties or PhysicalProperties.new(obj.Material)
					elseif obj:IsA("SpringConstraint") then
						table.insert(cachedSprings, obj)
						originalSprings[obj] = obj.FreeLength
					end
				end
				buildWheelCache(Vehicle, SeatPart)
			end

			-- VELOCITY MODIFIERS (speed keys)
			if velocityEnabled and not UserInputService:GetFocusedTextBox() then
				if velocityEnabledKeyCode ~= Enum.KeyCode.Unknown and UserInputService:IsKeyDown(velocityEnabledKeyCode) then
					SeatPart.AssemblyLinearVelocity *= Vector3.new(1 + velocityMult, 1, 1 + velocityMult)
				elseif qbEnabledKeyCode ~= Enum.KeyCode.Unknown and UserInputService:IsKeyDown(qbEnabledKeyCode) then
					SeatPart.AssemblyLinearVelocity *= Vector3.new(1 - velocityMult2, 1, 1 - velocityMult2)
				end
			end

			-- ============================
			-- DRIFT / GRIP / POWER LOGIC
			-- (copied EXACTLY from the Venyx script)
			-- ============================
			if driftModeEnabled then
				-- Apply Friction & Power/Handling Overrides
				for _, part in pairs(cachedParts) do
					local orig = originalProperties[part]
					if orig then
						part.CustomPhysicalProperties = PhysicalProperties.new(
							orig.Density,
							targetFriction,
							0, -- Zero bounce for smooth slides
							100,
							100
						)
					end
				end

				-- Inject Artificial Drift Power & Steering
				local speed = SeatPart.AssemblyLinearVelocity.Magnitude

				-- Power (W/S)
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then
					SeatPart.AssemblyLinearVelocity += SeatPart.CFrame.LookVector * (driftPowerMult / 10)
				elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
					SeatPart.AssemblyLinearVelocity -= SeatPart.CFrame.LookVector * (driftPowerMult / 10)
				end

				-- Handling Assist (A/D) - Only applies if car is actually moving
				if speed > 5 then
					local turn = 0
					if UserInputService:IsKeyDown(Enum.KeyCode.A) then turn += 1 end
					if UserInputService:IsKeyDown(Enum.KeyCode.D) then turn -= 1 end

					if turn ~= 0 then
						SeatPart.AssemblyAngularVelocity += Vector3.new(0, turn * (driftSteerAssist / 100), 0)
					end
				end
			else
				for part, props in pairs(originalProperties) do
					if part.CustomPhysicalProperties ~= props then
						part.CustomPhysicalProperties = props
					end
				end
			end

			-- SOFT SUSPENSION (stiffness/damping only; FreeLength comp is
			-- applied inside the STANCE / HEIGHT block so the two cooperate)
			local softActive = softSuspensionEnabled and softSuspensionAmount > 0
			if not softActive then
				-- restore stiffness/damping if previously softened
				for spring in pairs(originalSprings) do
					if originalSpringStiffness[spring] ~= nil then
						pcall(function() spring.Stiffness = originalSpringStiffness[spring] end)
					end
					if originalSpringDamping[spring] ~= nil then
						pcall(function() spring.Damping = originalSpringDamping[spring] end)
					end
				end
			end

			-- AUTO DRIVE FARM
			if autoDriveEnabled and autoDriveStartCFrame then
				updateNaturalSpeed()
				local appliedSpeed = autoDriveSpeed * naturalSpeedFactor

				local forwardDir = SeatPart.CFrame.LookVector
				local desiredVel = forwardDir * appliedSpeed
				SeatPart.AssemblyLinearVelocity = Vector3.new(desiredVel.X, SeatPart.AssemblyLinearVelocity.Y, desiredVel.Z)

				if tick() - autoDriveLastTp >= autoDriveTpInterval then
					autoDriveLastTp = tick()
					local savedVel = SeatPart.AssemblyLinearVelocity
					local savedAng = SeatPart.AssemblyAngularVelocity
					local moved = false
					pcall(function()
						local Veh = GetVehicleFromDescendant(SeatPart)
						if Veh and Veh:IsA("Model") then
							if not Veh.PrimaryPart then
								if SeatPart.Parent == Veh then Veh.PrimaryPart = SeatPart
								else Veh.PrimaryPart = Veh:FindFirstChildWhichIsA("BasePart") end
							end
							if Veh.PrimaryPart then
								local seatToPrimary = SeatPart.CFrame:ToObjectSpace(Veh.PrimaryPart.CFrame)
								Veh:SetPrimaryPartCFrame(autoDriveStartCFrame * seatToPrimary)
								moved = true
							end
						end
					end)
					if not moved then
						pcall(function() SeatPart.CFrame = autoDriveStartCFrame end)
					end
					pcall(function()
						SeatPart.AssemblyLinearVelocity = savedVel
						SeatPart.AssemblyAngularVelocity = savedAng
					end)
				end
			end

			-- STANCE / HEIGHT via spring FreeLength (+ soft compensation)
			if heightOverrideEnabled or softActive then
				for _, spring in pairs(cachedSprings) do
					if originalSprings[spring] then
						unlockSpring(spring)

						-- Base target from height settings (or stock if height off)
						local baseTarget
						if heightOverrideEnabled then
							local wheelPosition = GetWheelPosition(SeatPart, spring)
							local specificOffset = stanceOffsets[wheelPosition] or 0
							baseTarget = originalSprings[spring] + masterHeightOffset + specificOffset
						else
							baseTarget = originalSprings[spring]
						end

						-- Soft suspension: soften springs and get height comp.
						local softComp = 0
						if softActive then
							softComp = applySoftSuspension(spring, originalSprings[spring])
						end

						local target = math.clamp(baseTarget + softComp, 0.05, 1000)
						local last = lastAppliedFreeLength[spring]
						if last == nil then last = spring.FreeLength end
						local smoothed = last + (target - last) * 0.35
						if math.abs(smoothed - last) > 0.001 then
							pcall(function() spring.FreeLength = smoothed end)
							lastAppliedFreeLength[spring] = smoothed
						elseif last ~= target then
							pcall(function() spring.FreeLength = target end)
							lastAppliedFreeLength[spring] = target
						end
					end
				end
			else
				-- Neither height nor soft active: restore spring limits/length.
				for spring in pairs(originalSprings) do
					if originalSpringLimits[spring] then
						local lim = originalSpringLimits[spring]
						pcall(function() spring.LimitsEnabled = lim.limits end)
						pcall(function() spring.MaxLength = lim.max end)
						pcall(function() spring.MinLength = lim.min end)
						if originalSprings[spring] then
							pcall(function() spring.FreeLength = originalSprings[spring] end)
						end
						lastAppliedFreeLength[spring] = nil
						originalSpringLimits[spring] = nil
					end
				end
			end

			-- CAMBER + OFFSET applied to the actual wheel PARTS, in seat space.
			if camberEnabled or offsetEnabled then
				for _, w in pairs(cachedWheels) do
					applyWheelTransform(SeatPart, w)
				end
			end
		end
	else
		-- Out of vehicle: restore everything
		if cachedVehicle then
			for part, props in pairs(originalProperties) do
				if part.Parent then part.CustomPhysicalProperties = props end
			end
			for spring in pairs(originalSprings) do
				if spring.Parent then restoreSpring(spring) end
			end
			cachedVehicle = nil
			cachedParts = {}
			originalProperties = {}
			cachedSprings = {}
			originalSprings = {}
			originalSpringLimits = {}
			lastAppliedFreeLength = {}
			cachedWheels = {}
			originalSpringStiffness = {}
			originalSpringDamping = {}
			originalSpringFreeForSoft = {}
		end
		if autoDriveEnabled then
			autoDriveEnabled = false
			autoDriveStartCFrame = nil
		end
	end
end)

-- ==========================================
-- ACTION LISTENER
-- ==========================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == stopVehicleKeyCode and stopVehicleKeyCode ~= Enum.KeyCode.Unknown then
        local Character = LocalPlayer.Character
        if Character then
            local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
            if Humanoid then
                local SeatPart = Humanoid.SeatPart
                if SeatPart and SeatPart:IsA("VehicleSeat") then
                    SeatPart.AssemblyLinearVelocity = Vector3.zero
                    SeatPart.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
    elseif input.KeyCode == driftHotkey and driftHotkey ~= Enum.KeyCode.Unknown then
        driftModeEnabled = not driftModeEnabled
        WindUI:Notify({ Title = "Status Update",
            Content = driftModeEnabled and "Grip System Activated" or "Grip System Suspended" })
    elseif input.KeyCode == minimizeHotkey and minimizeHotkey ~= Enum.KeyCode.Unknown then
        toggleMainGui()
    end
end)

repeat task.wait(0) until game:IsLoaded() and game.PlaceId > 0

if game.PlaceId == 3351674303 then
	local drivingEmpirePage = Window:Tab({ Title = "Wayfort Extras", Icon = "map", Locked = false })
	drivingEmpirePage:Section({ Title = "Vehicle Dealership Warp" })
	local dealershipList = {}
	for _, value in pairs(workspace:WaitForChild("Game"):WaitForChild("Dealerships"):WaitForChild("Dealerships"):GetChildren()) do
		table.insert(dealershipList, value.Name)
	end
	drivingEmpirePage:Dropdown({
		Title = "Select Target Dealership Location",
		Values = dealershipList,
		Value = dealershipList[1],
		Callback = function(v)
			game:GetService("ReplicatedStorage").Remotes.Location:FireServer("Enter", v)
		end
	})
end