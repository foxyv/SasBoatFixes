-- SasBoatFixes: handling fixes for Ships At Sea, plus the recorder used to find them.
-- F4 toggles the list fix, which is on by default: crew and passengers no longer press down on the
--    deck they stand on. This is a change to how the game behaves. See "List fix" below.
-- F9 starts and stops a physics recording of the boat being driven, written to boatlog.txt in this
--    mod's folder. The recorder only reads.
-- The wake fix is always on: a boat's wake keeps going when nobody is at the helm. See "Wake fix".
-- The crane view fix is always on: the game's invert mouse setting applies in a crane's camera. See
--    "Crane look fix".

local TICK_MS = 250
local TICKS_PER_SECOND = 4

local ScriptDir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
local BoatLogPath = ScriptDir .. "\\..\\boatlog.txt"

---------------------------------------------------------------------------------------------------
-- Helpers

local function IsObject(obj)
    return obj ~= nil and type(obj) == "userdata" and pcall(function() return obj:IsValid() end) and obj:IsValid()
end

-- Reads a value for the log; a read that fails becomes a short error note instead of stopping the row.
local function Get(fn)
    local ok, value = pcall(fn)
    if not ok then return "<err " .. tostring(value):gsub("\n.*", ""):sub(-60) .. ">" end
    if type(value) == "number" then return string.format("%.4f", value) end
    return tostring(value)
end

local function V3(v)
    local ok, text = pcall(function() return string.format("%.2f %.2f %.2f", v.X, v.Y, v.Z) end)
    return ok and text or "?"
end

-- Iterates a TArray wrapper or a plain Lua table the same way.
local function Each(array, fn)
    if type(array) == "table" then
        for _, element in ipairs(array) do
            local ok, inner = pcall(function() return element:get() end)
            fn(ok and inner ~= nil and inner or element)
        end
    elseif array ~= nil then
        array:ForEach(function(_, element) fn(element:get()) end)
    end
end

-- The owned boat nearest the player, which is the one being driven.
local function DrivenBoat()
    local here = nil
    pcall(function() here = FindFirstOf("PlayerController").Pawn:K2_GetActorLocation() end)
    local best, bestDistance = nil, nil
    for _, component in ipairs(FindAllOf("CompanyOwnedBoatsComponent") or {}) do
        pcall(function()
            Each(component.ActiveBoats, function(boat)
                if not IsObject(boat) then return end
                local distance = 0
                if here then
                    local at = boat:K2_GetActorLocation()
                    distance = (at.X - here.X) ^ 2 + (at.Y - here.Y) ^ 2
                end
                if not bestDistance or distance < bestDistance then best, bestDistance = boat, distance end
            end)
        end)
    end
    return best
end

-- A world-space point expressed along the boat's own forward / right / up axes, in cm.
local function InBoatAxes(boat, point)
    local origin = boat:K2_GetActorLocation()
    local dx, dy, dz = point.X - origin.X, point.Y - origin.Y, point.Z - origin.Z
    local function along(axis) return dx * axis.X + dy * axis.Y + dz * axis.Z end
    return string.format("fwd %.1f right %.1f up %.1f",
        along(boat:GetActorForwardVector()), along(boat:GetActorRightVector()), along(boat:GetActorUpVector()))
end

-- Body queries take a bone name; a boat hull is a single body, so that is always "None".
local function WholeBody()
    return FName("None")
end

local function CentreOfMass(boat)
    return InBoatAxes(boat, boat.Mesh:GetCenterOfMass(WholeBody()))
end

---------------------------------------------------------------------------------------------------
-- People aboard. A character standing on a physics body pushes down on it where they stand, with a
-- force of their mass times gravity times StandingDownwardForceScale. That push is not part of the
-- boat's mass or centre of mass, so it has to be looked at separately.

local ABOARD_RANGE_CM = 3000

local function PeopleAboard(boat)
    local people = {}
    local origin = boat:K2_GetActorLocation()
    local right, forward, up = boat:GetActorRightVector(), boat:GetActorForwardVector(), boat:GetActorUpVector()
    for _, character in ipairs(FindAllOf("Character") or {}) do
        pcall(function()
            if not character:IsValid() or character:GetFullName():find("Default__", 1, true) then return end
            local at = character:K2_GetActorLocation()
            local dx, dy, dz = at.X - origin.X, at.Y - origin.Y, at.Z - origin.Z
            if dx * dx + dy * dy + dz * dz > ABOARD_RANGE_CM * ABOARD_RANGE_CM then return end
            local movement = character.CharacterMovement
            people[#people + 1] = {
                class = character:GetClass():GetFName():ToString(),
                right = dx * right.X + dy * right.Y + dz * right.Z,
                forward = dx * forward.X + dy * forward.Y + dz * forward.Z,
                up = dx * up.X + dy * up.Y + dz * up.Z,
                mass = movement.Mass,
                push = movement.StandingDownwardForceScale,
                interacts = movement.bEnablePhysicsInteraction,
            }
        end)
    end
    return people
end

-- kg-metres of sideways turning effect from people pressing on the deck; positive leans to starboard.
local function PeopleMoment(people)
    local moment, count = 0.0, 0
    for _, person in ipairs(people) do
        if person.interacts and person.push and person.push > 0 then
            moment = moment + person.mass * person.push * person.right / 100.0
            count = count + 1
        end
    end
    return moment, count
end

---------------------------------------------------------------------------------------------------
-- List fix. Boats could heel over in a turn and stay heeled for as long as they kept their speed.
-- Recordings of the class 3 service vessel showed its mass and centre of mass never moving while it
-- held 17 degrees of list at 26 knots; the list went within five seconds of switching off the
-- downward push of the six crew and passengers aboard. The game already has that push switched off
-- for the player's own character, so this gives every other character the same treatment.
--
-- The hull's weak righting force at speed is the underlying problem and is not touched here.

local ListFixOn = true
local ListFixToggle = false
local SavedPush = {}  -- character full name -> its original StandingDownwardForceScale

local function ApplyListFix()
    if ListFixToggle then
        ListFixToggle = false
        ListFixOn = not ListFixOn
        print("[SasBoatFixes] list fix " .. (ListFixOn and "on: crew and passengers do not press on the deck" or "off: game default") .. "\n")
        if not ListFixOn then
            for _, character in ipairs(FindAllOf("SasNpcCharacter") or {}) do
                pcall(function()
                    local saved = SavedPush[character:GetFullName()]
                    if saved then character.CharacterMovement.StandingDownwardForceScale = saved end
                end)
            end
            SavedPush = {}
        end
    end
    if not ListFixOn then return end
    for _, character in ipairs(FindAllOf("SasNpcCharacter") or {}) do
        pcall(function()
            local movement = character.CharacterMovement
            local push = movement.StandingDownwardForceScale
            if push > 0 then
                SavedPush[character:GetFullName()] = push
                movement.StandingDownwardForceScale = 0.0
            end
        end)
    end
end

---------------------------------------------------------------------------------------------------
-- Boat physics recorder. It writes what the boat is made of (mass, centre of mass, buoyancy settings,
-- what is attached, who is aboard) and then a row four times a second with its attitude.

local BoatLog = nil  -- open file while recording
local BoatLogToggle = false
local BoatLogTicks = 0

local BUOYANCY_FIELDS = {
    "WaterDensity", "bEnableHydrostaticsForce", "BuoyancyCoefficient", "LateralBuoyantForcePercentage",
    "bEnableLinearDampingImpulse", "LinearDampingCoefficientLong", "LinearDampingCoefficientLat", "LinearDampingCoefficientVert",
    "bEnableAngularDampingImpulse", "AngularDampingCoefficientRoll", "AngularDampingCoefficientPitch", "AngularDampingCoefficientYaw",
    "bEnableViscousDrag", "bEnablePressureSuctionDrag", "PressureDragPower", "LinearPressureDragCoefficient",
    "QuadraticPressureDragCoefficient", "SuctionDragPower", "LinearSuctionDragCoefficient", "QuadraticSuctionDragCoefficient",
    "DragReferenceVelocity", "DragMultiplierLong", "DragMultiplierLat", "DragMultiplierVert", "bEnableSlammingForce",
    "VerticalWaterDisplacementForceCoefficient", "LateralWaterDisplacementForceCoefficient",
}

local function WriteBoatHeader(file, boat)
    local function line(label, fn) file:write(label, ": ", Get(fn), "\n") end
    local body = boat.Mesh
    local movement = boat.BoatMovementComponent
    file:write("# SasBoatFixes boat recording ", os.date("%Y-%m-%d %H:%M:%S"), "\n")
    line("boat", function() return boat:GetFullName() end)
    line("info", function() return boat:GetBoatInfo():GetFullName() end)
    line("mass kg", function() return body:GetMass() end)
    line("centre of mass", function() return CentreOfMass(boat) end)
    line("inertia tensor", function() return V3(body:GetInertiaTensor(WholeBody())) end)
    line("linear damping", function() return body:GetLinearDamping() end)
    line("angular damping", function() return body:GetAngularDamping() end)
    line("body COM nudge", function() return V3(body.BodyInstance.COMNudge) end)
    line("body mass override", function() return tostring(body.BodyInstance.bOverrideMass) .. " " .. tostring(body.BodyInstance.MassInKgOverride) end)
    line("buoyancy values asset", function() return movement.BuoyancyValues:GetFullName() end)
    for _, field in ipairs(BUOYANCY_FIELDS) do
        line("  " .. field, function() return movement.BuoyancyValues.BuoyancyValues[field] end)
    end
    line("health", function() return boat.DamageComponent.CurrentHealth end)
    pcall(function()
        boat.BoatInventoryComponent.Inventories:ForEach(function(key, value)
            line("  inventory " .. key:get().TagName:ToString() .. " weight", function() return value:get().InventoryWeight end)
        end)
    end)
    pcall(function()
        local attached = {}
        boat:GetAttachedActors(attached, true, true)
        Each(attached.OutActors or attached, function(actor)
            file:write("  attached: ", Get(function() return actor:GetFullName():match("([^%.:]+)$") end),
                " | class ", Get(function() return actor:GetClass():GetFName():ToString() end),
                " | at ", Get(function() return InBoatAxes(boat, actor:K2_GetActorLocation()) end), "\n")
        end)
    end)
    pcall(function()
        for _, person in ipairs(PeopleAboard(boat)) do
            file:write(string.format("  aboard: %s | right %.0f fwd %.0f up %.0f cm | mass %s push %s interacts %s\n",
                person.class, person.right, person.forward, person.up,
                tostring(person.mass), tostring(person.push), tostring(person.interacts)))
        end
    end)
    file:write("# t_s roll_deg pitch_deg yaw_deg speed_kn mass_kg | centre of mass | people pushing, their moment kg.m (+ = starboard), offsets right cm | list fix\n")
end

local function RecordBoat()
    if BoatLogToggle then
        BoatLogToggle = false
        if BoatLog then
            BoatLog:close()
            BoatLog = nil
            print("[SasBoatFixes] boat recording stopped\n")
        else
            local boat = DrivenBoat()
            if not IsObject(boat) then
                print("[SasBoatFixes] boat recording: no owned boat found\n")
                return
            end
            BoatLog = io.open(BoatLogPath, "w")
            BoatLogTicks = 0
            pcall(WriteBoatHeader, BoatLog, boat)
            print("[SasBoatFixes] boat recording started: " .. BoatLogPath .. "\n")
        end
    end
    if not BoatLog then return end
    local boat = DrivenBoat()
    if not IsObject(boat) then return end
    BoatLogTicks = BoatLogTicks + 1
    -- Each value is read on its own, so one that cannot be read still leaves a usable row.
    BoatLog:write(string.format("%.2f", BoatLogTicks / TICKS_PER_SECOND), " ",
        Get(function() return boat:K2_GetActorRotation().Roll end), " ",
        Get(function() return boat:K2_GetActorRotation().Pitch end), " ",
        Get(function() return boat:K2_GetActorRotation().Yaw end), " ",
        Get(function() return boat.BoatMovementComponent:GetSpeedKnots() end), " ",
        Get(function() return boat.Mesh:GetMass() end), " | ",
        Get(function() return CentreOfMass(boat) end), " | ",
        Get(function()
            local people = PeopleAboard(boat)
            local moment, count = PeopleMoment(people)
            local offsets = {}
            for _, person in ipairs(people) do offsets[#offsets + 1] = string.format("%.0f", person.right) end
            return string.format("%d %.1f [%s]", count, moment, table.concat(offsets, " "))
        end), " | ", ListFixOn and "list-fix-on" or "list-fix-off", "\n")
    BoatLog:flush()
end

---------------------------------------------------------------------------------------------------
-- Wake fix. The water is NVIDIA WaveWorks, and a boat's wake is its "local waves" simulation, which
-- covers a square of water around a centre (LocalWavesSimulationSettings.SimulationDomainCenter on
-- the WaveWorksComponent). The game keeps that square on the boat only while someone is at the helm.
-- Leave the helm under way and the square stays behind: the boat sails out of it in a few seconds and
-- its wake vanishes. While your boat has nobody at the helm, this slides the square along with the
-- boat. The slide is a short step each frame. Dropping the square onto the boat in one move, or
-- shoving it by a metre several times a second, smears the foam across the whole square, which draws
-- as a block of white water around the ship. At the helm the game's own handling is left alone.
-- Only the square the boat's own wake uses is moved. Replacing the centre with a new value writes
-- just those two numbers; writing the whole setting would clear the foam and the size of the square.

local WAKE_MS = 16
local WAKE_LOOKUP_TICKS = 60   -- the boat and the water are looked up about once a second
local WAKE_NEAR_CM = 20000     -- only while you are within 200 m of the boat
local WAKE_MAX_STEP_CM = 80    -- a fast boat moves less than this in one step; more than this smears foam
local WakeBoat, WakeWater, WakeLookAgain = nil, nil, 0
local WakeHolding = false

local function WakeNumber(fn)
    local ok, value = pcall(fn)
    if ok and type(value) == "number" then return value end
    return nil
end

local function SameObject(a, b)
    if a == b then return true end
    local ok, same = pcall(function() return a:GetAddress() == b:GetAddress() end)
    return ok and same
end

-- The water component the boat disturbs for its wake, or nil when this boat has none.
local function BoatWakeWater(boat)
    local found = nil
    pcall(function()
        for _, dist in ipairs(FindAllOf("BoatWaterLocalDisturbanceComponent") or {}) do
            if not dist:GetFullName():find("Default__", 1, true) and SameObject(dist:GetOwner(), boat)
                and IsObject(dist.WaveWorksComponent) then
                found = dist.WaveWorksComponent
                break
            end
        end
    end)
    return found
end

-- The local-waves square already nearest the boat: the one the game was keeping on it.
local function NearestWakeWater(at)
    local best, bestDistance = nil, nil
    for _, comp in ipairs(FindAllOf("WaveWorksComponent") or {}) do
        pcall(function()
            if comp:GetFullName():find("Default__", 1, true) then return end
            if comp.bUseLocalWaves == false then return end
            local center = comp.LocalWavesSimulationSettings.SimulationDomainCenter
            local dx, dy = center.X - at.X, center.Y - at.Y
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then best, bestDistance = comp, distance end
        end)
    end
    return best
end

-- A wiped foam setup (every rate at zero) or a broken square size is put back from the class default.
-- That is the state left behind by writing the centre as a whole new setting.
local function RepairWakeSettings(comp)
    local size = WakeNumber(function() return comp.LocalWavesSimulationSettings.SimulationDomainWorldspaceSize end)
    local amount = WakeNumber(function() return comp.LocalWavesSimulationSettings.FoamSettings.FoamGenerationAmount end)
    local dissipate = WakeNumber(function() return comp.LocalWavesSimulationSettings.FoamSettings.FoamDissipationSpeed end)
    local falloff = WakeNumber(function() return comp.LocalWavesSimulationSettings.FoamSettings.FoamFalloffSpeed end)
    local sizeBroken = not size or size < 100 or size > 10000000
    local foamBroken = amount == 0 and dissipate == 0 and falloff == 0
    if not sizeBroken and not foamBroken then return end
    local cdo = nil
    pcall(function() cdo = comp:GetClass():GetDefaultObject() end)
    if not IsObject(cdo) then
        pcall(function()
            local name = comp:GetClass():GetFName():ToString()
            cdo = StaticFindObject("/Script/Sas.Default__" .. name)
            if not IsObject(cdo) then cdo = StaticFindObject("/Script/WaveWorks.Default__" .. name) end
        end)
    end
    if not IsObject(cdo) then
        print("[SasBoatFixes] wake fix: the water square's settings look wiped, and the original could not be read back\n")
        return
    end
    pcall(function()
        local live, def = comp.LocalWavesSimulationSettings, cdo.LocalWavesSimulationSettings
        if sizeBroken then live.SimulationDomainWorldspaceSize = def.SimulationDomainWorldspaceSize end
        if foamBroken then
            local lf, df = live.FoamSettings, def.FoamSettings
            lf.FoamWhitecapsThreshold = df.FoamWhitecapsThreshold
            lf.FoamGenerationThreshold = df.FoamGenerationThreshold
            lf.FoamGenerationAmount = df.FoamGenerationAmount
            lf.FoamDissipationSpeed = df.FoamDissipationSpeed
            lf.FoamFalloffSpeed = df.FoamFalloffSpeed
            live.AmplitudeMultiplier = def.AmplitudeMultiplier
            live.LateralMultiplier = def.LateralMultiplier
        end
    end)
    local restored = WakeNumber(function() return comp.LocalWavesSimulationSettings.SimulationDomainWorldspaceSize end)
    print("[SasBoatFixes] wake fix restored the water square's settings (now " .. tostring(restored) .. " cm across)\n")
end

-- Moves the square's centre towards the boat by at most one short step.
local function SlideWakeCenter(comp, x, y)
    local cx = WakeNumber(function() return comp.LocalWavesSimulationSettings.SimulationDomainCenter.X end)
    local cy = WakeNumber(function() return comp.LocalWavesSimulationSettings.SimulationDomainCenter.Y end)
    local tx, ty = x, y
    if cx and cy then
        local dx, dy = x - cx, y - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > WAKE_MAX_STEP_CM then
            local scale = WAKE_MAX_STEP_CM / dist
            tx, ty = cx + dx * scale, cy + dy * scale
        end
    end
    pcall(function()
        local center = comp.LocalWavesSimulationSettings.SimulationDomainCenter
        center.X = tx
        center.Y = ty
    end)
end

local function WakeFix()
    WakeLookAgain = WakeLookAgain - 1
    if WakeLookAgain <= 0 then
        WakeLookAgain = WAKE_LOOKUP_TICKS
        WakeBoat = DrivenBoat()
        WakeWater = nil
        if IsObject(WakeBoat) then
            local at = WakeBoat:K2_GetActorLocation()
            WakeWater = BoatWakeWater(WakeBoat) or NearestWakeWater(at)
            if IsObject(WakeWater) then RepairWakeSettings(WakeWater) end
        end
    end
    local boat, comp = WakeBoat, WakeWater
    if not IsObject(boat) or not IsObject(comp) then return end
    local driven = false
    pcall(function() driven = IsObject(boat.DriverComponent.Driver) end)
    local at = boat:K2_GetActorLocation()
    local near = false
    pcall(function()
        local here = FindFirstOf("PlayerController").Pawn:K2_GetActorLocation()
        near = (at.X - here.X) ^ 2 + (at.Y - here.Y) ^ 2 < WAKE_NEAR_CM ^ 2
    end)
    local hold = not driven and near
    if hold ~= WakeHolding then
        WakeHolding = hold
        print("[SasBoatFixes] wake fix " .. (hold and "keeping the wake on the boat: nobody at the helm" or "standing by: the boat is driven, or you are away from it") .. "\n")
    end
    if not hold then return end
    SlideWakeCenter(comp, at.X, at.Y)
end

---------------------------------------------------------------------------------------------------
-- Crane look fix. The game applies the invert mouse and invert stick settings through input modifiers
-- (LAB132InputModifierMouseInversion, LAB132InputModifierControllerInversion) set on the look
-- binding of each input context: the character's, the boat's, the water cannon's. The crane's
-- (IMC_CraneContext) look binding, the same IA_CharacterLook action, has none, so in a crane's camera
-- the setting does nothing. This adds the character context's own inversion modifiers to the crane's
-- look bindings. The same modifier object is shared; it holds no state and follows the setting.
-- Nothing is changed in the saved settings, and the sensitivity settings are left as they were.

local CRANE_CONTEXT = "/Game/ShipsAtSea/Input/Crane/IMC_CraneContext.IMC_CraneContext"
local LOOK_CONTEXT = "/Game/ShipsAtSea/Input/Character/IMC_Character.IMC_Character"
local CraneLookTries, CraneLookDone = 0, false

local function ContextObject(path)
    local obj = StaticFindObject(path)
    if not IsObject(obj) then pcall(function() obj = LoadAsset(path) end) end
    return IsObject(obj) and obj or nil
end

local function ModifierName(mod)
    local ok, name = pcall(function() return mod:GetFullName() end)
    return ok and tostring(name) or ""
end

-- The modifier of a binding whose name has the text in it (MouseInversion, ControllerInversion), or nil.
local function InversionFor(mapping, text)
    for i = 1, #mapping.Modifiers do
        local mod = mapping.Modifiers[i]
        if ModifierName(mod):find(text, 1, true) then return mod end
    end
    return nil
end

local function KeyOf(mapping)
    local ok, key = pcall(function() return mapping.Key.KeyName:ToString() end)
    return ok and tostring(key) or ""
end

local function CraneLookFix()
    if CraneLookDone then return end
    CraneLookTries = CraneLookTries + 1
    local crane, look = ContextObject(CRANE_CONTEXT), ContextObject(LOOK_CONTEXT)
    if not crane or not look then
        if CraneLookTries == 20 then print("[SasBoatFixes] crane look fix: input contexts not found\n") end
        return
    end
    CraneLookDone = true
    local lookMaps, craneMaps = look.DefaultKeyMappings.Mappings, crane.DefaultKeyMappings.Mappings
    local added = 0
    for _, spec in ipairs({ { key = "Mouse2D", kind = "MouseInversion" },
                            { key = "Gamepad_Right2D", kind = "ControllerInversion" } }) do
        local source = nil
        for i = 1, #lookMaps do
            local m = lookMaps[i]
            if KeyOf(m) == spec.key and ModifierName(m.Action):find("IA_CharacterLook", 1, true) then
                source = InversionFor(m, spec.kind)
                break
            end
        end
        if not source then
            print("[SasBoatFixes] crane look fix: no " .. spec.key .. " inversion modifier found to copy\n")
        else
            for i = 1, #craneMaps do
                local m = craneMaps[i]
                if KeyOf(m) == spec.key and ModifierName(m.Action):find("IA_CharacterLook", 1, true) then
                    if InversionFor(m, spec.kind) then
                        print("[SasBoatFixes] crane look fix: " .. spec.key .. " already inverts\n")
                    else
                        local before = #m.Modifiers
                        pcall(function() m.Modifiers[before + 1] = source end)
                        if #m.Modifiers > before then
                            added = added + 1
                            print("[SasBoatFixes] crane look fix: " .. spec.key .. " in the crane now follows the invert setting\n")
                        else
                            print("[SasBoatFixes] crane look fix: could not add the modifier to " .. spec.key .. "\n")
                        end
                    end
                end
            end
        end
    end
    return added
end

---------------------------------------------------------------------------------------------------
-- Key presses only set flags. All the work happens in one timer on the game thread, which is the
-- only place game objects may be touched, so this mod's Lua never runs on two threads at once.

RegisterKeyBind(Key.F4, function()
    ListFixToggle = true
end)

RegisterKeyBind(Key.F9, function()
    BoatLogToggle = true
end)

local Ticks = 0

local function Tick()
    Ticks = Ticks + 1
    pcall(RecordBoat)
    if ListFixToggle or Ticks % (2 * TICKS_PER_SECOND) == 0 then  -- new crew and passengers appear over time
        pcall(ApplyListFix)
    end
    return false
end

if LoopInGameThreadWithDelay then
    LoopInGameThreadWithDelay(TICK_MS, Tick)
    LoopInGameThreadWithDelay(WAKE_MS, function()
        pcall(WakeFix)
        return false
    end)
    LoopInGameThreadWithDelay(2000, function()
        if not CraneLookDone and CraneLookTries < 30 then
            local ok, err = pcall(CraneLookFix)
            if not ok then print("[SasBoatFixes] crane look fix failed: " .. tostring(err):gsub("\n.*", "") .. "\n") end
        end
        return false
    end)
else
    -- Older UE4SS builds: a single background timer that hands each tick to the game thread.
    LoopAsync(TICK_MS, function()
        ExecuteInGameThread(Tick)
        return false
    end)
end

print("[SasBoatFixes] loaded: list fix on (F4 toggles), wake fix on, crane look fix on, F9 = record boat physics\n")
