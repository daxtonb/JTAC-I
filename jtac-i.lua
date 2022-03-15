JTACI = {
    comms = {
        frequency = 251,
        modulation = 'AM'
    },
    isImmortal = true,
    aircraftSpawnDelay = 15
}

local debug = false
local objectiveZone
local aircraftGroups = {}
local unitWeaponsInFlight = {}

local unitVoices = {}

local microsoftVoices = {
    [1] = { name = "Microsoft David Desktop", gender = "male"},
}

local currentVoiceIndex = 1
local fuelEmptyBuffer = 0.1 -- Fuel capacity at which aircraft will RTB

local aircraftMenu = missionCommands.addSubMenu('Aircraft')

local phoneticAlphabet = {
    a = "alpha",
    b = "bravo",
    c = "charlie",
    d = "delta",
    e = "echo",
    f = "foxtrot",
    g = "golf",
    h = "hotel",
    i = "india",
    j = "juliet",
    k = "kilo",
    l = "lima",
    m = "mike",
    n = "november",
    o = "oscar",
    p = "papa",
    q = "quebec",
    r = "romeo",
    s = "sierra",
    t = "tango",
    u = "uniform",
    v = "victor",
    w = "whiskey",
    x = "x-ray",
    y = "yankee",
    z = "zulu"
}

local phoneticNumbers = {
    ["0"] = "zero",
    ["1"] = "one",
    ["2"] = "two",
    ["3"] = "three",
    ["4"] = "four",
    ["5"] = "five",
    ["6"] = "six",
    ["7"] = "seven",
    ["8"] = "eight",
    ["9"] = "niner",
}

local function debugLog(message)
    if debug then
        message = UTILS.OneLineSerialize(message)
        trigger.action.outText(message, 10)
    end
end


debugLog("JTAC-I loaded.")

local function textToSpeach(message, positionable)
    local speechMessage = ''
    local char, nextChar, matchStart, matchEnd;
    local acronymsToIgnore = { "HE", "30mm", "20mm", "IP", "MQ-9" }
    local skipRange;
    local wordCount = 1

    for i = 1, #message do
        char = message:sub(i, i)
        nextChar = message:sub(i + 1, i + 1)

        if (char == " ") then
            wordCount = wordCount + 1
        end

        for _, word in pairs(acronymsToIgnore) do
            if message:sub(i, i + #word - 1) == word then
                speechMessage = speechMessage .. word
                skipRange = i + #word -1
            end
        end

        if not skipRange or i > skipRange then

            -- CONDITION: character is digit
            if string.match(char, '%d') then
                -- Use phonetic
                speechMessage = speechMessage .. phoneticNumbers[char]
                -- CONDITION: the next character is a alphanumeric
                if string.match(nextChar, '[%d%a]') then
                    speechMessage = speechMessage .. " "
                end
            -- CONDITION: character is uppercase
            elseif string.match(char, '%u')  then
                matchStart, matchEnd = string.find(message:sub(i), '^[%u][%u][%u]+')
                -- CONDITION: Three or more adjacent capital letters
                if matchEnd then
                    skipRange = i + matchEnd    -- Skip; don't do anything
                    speechMessage = speechMessage .. message:sub(i + matchStart - 1, i + matchEnd)
                -- CONDITION: next character is a digit, captial letter, or non-alphabetic letter
                elseif string.match(nextChar, '[%d%u%A]') then
                    speechMessage = speechMessage .. phoneticAlphabet[string.lower(char)] .. " "
                else
                    speechMessage = speechMessage .. char
                end
            -- CONDITION: character is alpha and next character is digit
            elseif string.match(char, '%a') and string.match(nextChar, '%d') then
                speechMessage = speechMessage .. char .. " "
            -- CONDITION: character is hyphen or underscore
            elseif not string.match(char, '[-_]') then
                speechMessage = speechMessage .. char
            end
        end
    end

    debugLog(message)

    if positionable then
        local callsign = positionable:GetCallsign() or positionable:GetName()

        if not unitVoices[callsign] then
            unitVoices[callsign] = microsoftVoices[currentVoiceIndex]
            if currentVoiceIndex == #microsoftVoices then
                currentVoiceIndex = 1
            else
                currentVoiceIndex = currentVoiceIndex + 1
            end
        end

        local voice = unitVoices[callsign]
        STTS.TextToSpeech(speechMessage, JTACI.comms.frequency, JTACI.comms.modulation, "1.0", "SRS", positionable:GetCoalition(), positionable:GetVec3(), 0, voice.gender, "en-US", voice.name)
    else
        STTS.TextToSpeech(speechMessage,JTACI.comms.frequency, JTACI.comms.modulation,"1.0","SRS")
    end
end

local function getEnemyCoalition(friendlyCoalition)
    if friendlyCoalition == 2 or string.lower(friendlyCoalition) == "blue" then
        return "red"
    else
        return "blue"
    end
end

-- Paginates menu items
local function setMultipleMenus(menus, parentMenu)
    local submenus = {}

    for index, menu in pairs(menus) do
        -- Page menus with more than 10 sub-items
        if #menus > 10 and (index % 10 == 10 - (math.floor(index / 10)) or index == 10) then
            parentMenu = missionCommands.addSubMenu('more', parentMenu)
        end
        if menu.func then
            submenus[menu.name] = missionCommands.addCommand(menu.name, parentMenu, menu.func, menu.params)
        else if menu.name then
            submenus[menu.name] = missionCommands.addSubMenu(menu.name, parentMenu)
            end
        end
    end

    return submenus
end

local function angleToCardinalDirection(angle)
    if angle < 0 then
        angle = angle * -1
        if angle < 180 then
            angle = angle + 180
        else
            angle = angle - 180
        end
    end

    if angle >= 0 and angle < 22.5 then
        return 'north'
    elseif angle >= 22.5 and angle < 67.5 then
        return 'northeast'
    elseif angle >= 67.5 and angle < 112.5 then
        return 'east'
    elseif angle >= 112.5 and angle < 157.5 then
        return 'southeast'
    elseif angle >= 157.5 and angle < 202.5 then
        return 'south'
    elseif angle >= 202.5 and angle < 247.5 then
        return 'southwest'
    elseif angle >= 247.5 and angle < 292.5 then
        return 'west'
    elseif angle >= 292.5 and angle < 337.5 then
        return 'northwest'
    else
        return 'northwest'
    end
end -- end angleToCardinalDirection

local function getBackAzimuth(azimuth)
    if azimuth >= 180 then
        return azimuth - 180
    else
        return azimuth + 180
    end
end

-- This is not very accurate, but gives a rough estimate for the observer
local function getTimeOfFlight(weapon)
    local height = weapon:getPoint().y - weapon:getTarget():getPoint().y
    local velocity = weapon:getVelocity()
    velocity = math.sqrt(velocity.x * velocity.x + velocity.y + velocity.y + velocity.z + velocity.z)
    local pitch = math.asin(weapon:getPosition().x.y) * 180/math.pi * -1
    local gravity = 9.8

    local time = (velocity * math.sin(pitch) + math.sqrt(math.pow((velocity * math.sin(pitch)), 2) + 2 * gravity * height)) / gravity

    return time
end

local function getPlaytime(aircraft)
    local timeOnStation = timer.getAbsTime() - aircraft.startTime
    local fuelCurrent = aircraft:GetFuel()
    local fuelLeft = fuelCurrent - fuelEmptyBuffer
    local fuelConsumed = aircraft.startFuel - fuelCurrent
    local fuelConsumptionRate = fuelConsumed / timeOnStation
    return UTILS.Round((fuelLeft / fuelConsumptionRate) / 60)
end

local function refreshAircraftAttackSubmenus()
    for name, aircraft in pairs(aircraftGroups) do

        if not aircraft.Menus then
            aircraft.Menus = {}
        end

        if aircraft.Menus.Attack then
            missionCommands.removeItem(aircraft.Menus.Attack)
        end

        local attackSubmenu = missionCommands.addSubMenu("Attack", aircraft.Menus.Flight)
        aircraft.Menus.Attack = attackSubmenu
        local enemyCoalition = getEnemyCoalition(aircraft:GetCoalition())
        local targetSubmenus = {}
        local targetSubmenusParams = {}

        local weapons = {}

        for _, unit in pairs(aircraft:GetUnits()) do
            for _, weapon in pairs(unit:GetAmmo()) do
                local _, _, weaponType = string.find(weapon.desc.typeName, "%a+.(%a+).%a+")
                local weaponTypeId = 3221225470 -- any weapon

                if weaponType == "shells" then
                    weaponTypeId = 805306368
                elseif weaponType ==  "missiles" then
                    weaponTypeId = 4161536
                elseif weaponType == "bombs" then
                    -- INS
                    if weapon.desc.guidance == 1 then
                        weaponTypeId = 8 -- SNSGB
                    -- Laser
                    else if weapon.desc.guidance == 7 then
                        weaponTypeId = 2  -- LGB
                        else
                            weaponTypeId = 2147485694 -- any bomb
                        end
                    end
                elseif weaponType == "rockets" then
                    weaponTypeId = 30720
                end

                weapons[weapon.desc.displayName] = weaponTypeId
            end
        end

        local headings = {
            ["S -> N"] = 0,
            ["SW -> NE"] = 45,
            ["W -> E"] = 90,
            ["NW -> SE"] = 135,
            ["N -> S"] = 180,
            ["NE -> SW"] = 225,
            ["E -> W"] = 270,
            ["SE -> NW"] = 315,
        }

        -- Loop over groups
        for groupName, group in pairs(_DATABASE.GROUPS) do
            local coalitionName = group:GetCoalitionName()
            if coalitionName and string.lower(group:GetCoalitionName()) == enemyCoalition and group:IsAlive() then
                targetSubmenusParams[groupName] = { name = groupName }
            end
        end

        if next(targetSubmenusParams) == nil then
            return
        end

        -- Loop over types of control
        for toc=1,3 do
            local tocSubmenu = missionCommands.addSubMenu("Type " .. tostring(toc), attackSubmenu)
            targetSubmenus = setMultipleMenus(targetSubmenusParams, tocSubmenu)

            -- Loop over targets
            for targetName, targetSubmenu in pairs(targetSubmenus) do

                -- Loop over weapons
                for weaponName, weaponTypeId in pairs(weapons) do

                    local weaponSubmenu = missionCommands.addSubMenu(weaponName, targetSubmenu)

                    -- Loop over final attack directions
                    for heading, azimuth in pairs(headings) do

                        -- Execute attack
                        missionCommands.addCommand("Final Attack Direction: " .. heading, weaponSubmenu, function ()
                            local groupToAttack = GROUP:FindByName(targetName)
                            local attackQuantity
                            local ipBp

                            if toc == 3 then
                                attackQuantity = nil
                            else
                                attackQuantity = 1
                            end

                            if (toc == 3) then
                                textToSpeach(aircraft:GetCallsign() .. " commencing engagement.", aircraft)
                            else
                                -- For Type 1 and 2 controls, have aircraft give IN calls
                                for _, aircraftUnit in pairs(aircraft:GetUnits()) do
                                    local scheduler, schedulerId

                                    -- Check the aircraft's heading every second until it is in its IN heading
                                    scheduler, schedulerId = SCHEDULER:New(aircraftUnit, function ()
                                        local directionToTarget = aircraftUnit:GetCoordinate():HeadingTo(groupToAttack:GetCoordinate(), aircraftUnit)
                                        local aircraftHeading = aircraftUnit:GetHeading()

                                        -- If the group is in +/- 22 degrees of heading, report IN call and stop this scheduler
                                        if directionToTarget <= azimuth + 15 and directionToTarget >= azimuth - 22
                                        and aircraftHeading <= azimuth + 15 and aircraftHeading >= azimuth - 22 then
                                            textToSpeach(aircraftUnit:GetCallsign() .. " in from the " .. angleToCardinalDirection(getBackAzimuth(azimuth)), aircraftUnit)
                                            scheduler:Stop(schedulerId)
                                        end
                                    end, {}, 1, 1) -- End of scheduler callback
                                end
                            end

                            local task = aircraft:TaskAttackGroup(groupToAttack, weaponTypeId, nil, attackQuantity, getBackAzimuth(azimuth), nil, true)
                            aircraft:PushTask(task)

                            if aircraft:IsHelicopter() then
                                ipBp = "BP"
                            else
                                ipBp = "IP"
                            end

                            textToSpeach(aircraft:GetCallsign() .. " departing " .. ipBp .. ".", aircraft)
                        end, {})
                    end -- End final attack direction loop
                end -- End target loop
            end -- End weapons loop
        end -- End type of control loop
    end -- End aircraft group loop
end

local function getCountryCoalition(country)
    local coalitionId = coalition.getCountryCoalition(country)
    for name, id in pairs(coalition.side) do
        if coalitionId == id then
            return name
        end
    end
    return "NEUTRAL"
end

local function makeObserversImmortal()
    local observers = Group.getByName("observer")
    if observers ~= nil then
        local observerController = observers:getController()
        observerController:setCommand({
            id = 'SetImmortal',
            params = {
              value = true
            }
          })
    end
end

--[[
    aircraftGroup
    point,
    speed,
    altitude,
    wpName
]]
local  function assignAircraftHold(args)
    local aircraftGroup = args.aircraftGroup
    local zone = ZONE:FindByName(args.wpName)
    local task
    local altitudeType
    if not zone then
        zone = ZONE_RADIUS:New(args.wpName, { x = args.point.x, y = args.point.z }, 4000)
    end

    aircraftGroup:SetState(aircraftGroup, "routing", args.wpName)

    if aircraftGroup:IsHelicopter() then
        altitudeType = "RADIO"
    else
        altitudeType = "BARO"
        task = {
            id = 'Orbit',
            params = {
                pattern = AI.Task.OrbitPattern.CIRCLE,
                point = {x = args.point.x, y = args.point.z},
                speed = args.speed,
                altitude = args.altitude
            }
        }
    end

    aircraftGroup:SetTask({
        id = 'Mission',
        params = {
            airborne = true,
            route = {
                points = {
                    [1] = {
                    type = AI.Task.WaypointType.TURNING_POINT,
                    x = args.point.x,
                    y = args.point.z,
                    alt = args.altitude,
                    alt_type = altitudeType,
                    speed = args.speed,
                    name = args.wpName,
                    task = task
                    }
                }
            },
        }
    }, 2)

    -- We only want the aircraft to engage when we tell it to
    aircraftGroup:SetOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.OPEN_FIRE)

    local scheduleId;
    -- Set up a listener to send a message when aircraft arrives at destination
    scheduleId = SCHEDULER:New(aircraftGroup, function ()
        if aircraftGroup:IsCompletelyInZone(zone) and aircraftGroup:GetState(aircraftGroup, "routing") == args.wpName then

            local report
            local feetMsl = UTILS.Round(UTILS.MetersToFeet(args.altitude), -3)

            if string.lower(args.wpName) == 'cp' then

                -- Calcluate distance
                local objZoneVec2 = objectiveZone:GetVec2()
                local objPoint = POINT_VEC2:New(objZoneVec2.x, objZoneVec2.y)
                local zoneVec2 = zone:GetVec2()
                local zonePoint = POINT_VEC2:New(zoneVec2.x, zoneVec2.y)
                local distance = zonePoint:DistanceFromPointVec2(objPoint)

                -- Calculate cardinal direction
                local zoneVec3 = POINT_VEC3:NewFromVec2(zonePoint, 0)
                local objZoneVec3 = POINT_VEC3:NewFromVec2(objPoint, 0)
                local angleRadians = POINT_VEC3:NewFromVec3(objZoneVec3:GetDirectionVec3(zoneVec3))
                local direction = UTILS.Round(angleRadians:GetAngleDegrees(angleRadians), 0)
                report = aircraftGroup:GetCallsign() .. " checking in " .. tostring(UTILS.Round(UTILS.MetersToNM(distance),0)) .. " nautical miles " .. angleToCardinalDirection(direction) ..  " holding block " .. tostring(feetMsl / 1000)
            else
                report = aircraftGroup:GetCallsign() .. " established at " .. args.wpName .. " at block " .. tostring(feetMsl / 1000)
            end

            textToSpeach(report, aircraftGroup)

            aircraftGroup:SetState(aircraftGroup, "routing", "hold")
            SCHEDULER.Stop(scheduleId)
        end

    end, {}, 1, 1)

end -- assignAircraftHold

local function setIpAndAltitudeCommands(aircraftGroup, parentMenu, ip)
    local menus = {}
    local ipSubmenu = missionCommands.addSubMenu(ip.callsignStr, parentMenu)
    local altitutdeType

    if aircraftGroup:IsHelicopter() then
        altitutdeType = "AGL"
    else
        altitutdeType = "MSL"
    end

    for i = 1, 25, 1 do
        local params = { aircraftGroup = aircraftGroup, point = { x = ip.x, z = ip.y }, speed = aircraftGroup:GetUnits()[1]:GetVelocityKNOTS(), altitude = UTILS.FeetToMeters(i * 1000), wpName = "IP " .. ip.callsignStr}
        menus[i] = { name = tostring(i) .. "000 ft " .. altitutdeType, func = assignAircraftHold, params = params }
    end

    setMultipleMenus(menus, ipSubmenu)
end

local function setAircraftSubmenus(aircraftGroup)
    local units = aircraftGroup:GetUnits()
    local flightSubmenu = missionCommands.addSubMenu(units[1]:GetCallsign() .. " (" .. units[1]:GetTypeName() .. ")", aircraftMenu)

    if not aircraftGroup.Menus then
        aircraftGroup.Menus = {}
    end

    aircraftGroup.Menus.Flight = flightSubmenu

    -- Routing commands
    local routeSubmenu = missionCommands.addSubMenu('Route', flightSubmenu)
    local ips = env.mission.coalition[string.lower(aircraftGroup:GetCoalitionName())].nav_points

    -- Add submenu for each IP
    for _, ip in pairs(ips) do
        setIpAndAltitudeCommands(aircraftGroup, routeSubmenu, ip)
    end

    -- Add overhead hold
    local overhead = objectiveZone:GetVec3()
    overhead = {
        x = overhead.x,
        y = overhead.z,
        z = overhead.y,
        callsignStr =  'Overhead'
    }
    setIpAndAltitudeCommands(aircraftGroup, routeSubmenu, overhead)

    -- Aircraft check-in command
    missionCommands.addCommand('Check In', flightSubmenu, function ()
        local callsigns = ""

        -- Aircraft callsigns
        for index, aircraft in pairs(units) do
            callsigns = callsigns .. aircraft:GetCallsign().. ", "
        end

        local aircraft = tostring(#units) .. " " .. units[1]:GetTypeName() .. ", "
        -- Aircraft weapons
        local weapons = ""

        for index, weapon in pairs(units[1]:GetAmmo()) do
            weapons = weapons .. tostring(weapon.count) .. " " .. weapon.desc.displayName .. ", "
        end

        local message = callsigns .. " " .. aircraft .. "playtime " .. tostring(getPlaytime(aircraftGroup)) .. " minutes, laser codes 1688, 1689, negative VDL, litening pod equipped, " .. weapons .. "requesting abort in the clear."

        textToSpeach(message, aircraftGroup)
    end, {})

    -- Attack commands
    refreshAircraftAttackSubmenus()

    -- Abort
    missionCommands.addCommand('Abort', flightSubmenu, function ()
        aircraftGroup:PopCurrentTask()
        debugLog("aborting")
    end, {})

    -- Respawn
    missionCommands.addCommand('Respawn', flightSubmenu, function ()
        aircraftGroup:Respawn(nil, true)
    end, {})
end -- end setAircraftSubmenus

local function initializeAircraft()
    objectiveZone = ZONE:FindByName('objective')
    if not objectiveZone then
        trigger.action.outText("ERROR: No zone by the name of 'objective' detected!")
    end

    local cpZone = ZONE:FindByName('cp')
    local farpZone = ZONE:FindByName('farp')
    local aircraftCount = 0
    local aircraftFound = {}

    -- Locate each aircraft
    for _, group in pairs(_DATABASE.GROUPS) do
        if group:IsAirPlane() or group:IsHelicopter() and not group:IsPlayer() then
            aircraftFound[group.GroupName] = group
        end
    end

    for _, aircraft in pairs(aircraftFound) do
        local delay = aircraftCount * JTACI.aircraftSpawnDelay * 60
        local spawnAircraft = SPAWN:New(aircraft:GetName())
        local unit = aircraft:GetUnits()[1]
        local altitude = unit:GetHeight()
        local speed = unit:GetVelocityKNOTS()
        local respawnZone

        -- If the aircraft is a helicopter, use the FARP zone. Otherwise, use CP
        if aircraft:IsHelicopter() and farpZone then
            respawnZone = farpZone
            if not respawnZone then
                trigger.action.outText("ERROR: no zone by the name of 'farp' detected!", 10)
            end
        else
            respawnZone = cpZone
            if not respawnZone then
                trigger.action.outText("ERROR: no zone by the name of 'cp' detected!", 10)
            end
        end

        spawnAircraft:InitRandomizeZones({respawnZone})
        spawnAircraft:InitDelayOn()
        spawnAircraft:OnSpawnGroup(function (spawnedGroup)
            aircraftGroups[spawnedGroup.GroupName] = spawnedGroup

            spawnedGroup.startTime = timer.getAbsTime()
            spawnedGroup.startFuel = spawnedGroup:GetFuel()

            local taskParams = {
                aircraftGroup = spawnedGroup,
                point = respawnZone:GetCoordinate(),
                speed = speed,
                altitude = altitude,
                wpName = 'CP'
            }

            -- Setup for respawn
            spawnedGroup:InitHeight(altitude)
            spawnedGroup:InitZone(respawnZone)

            assignAircraftHold(taskParams)
            setAircraftSubmenus(spawnedGroup)



            -- Event handling
            for _, aircraftUnit in pairs(spawnedGroup:GetUnits()) do

                aircraftUnit:HandleEvent(EVENTS.Shot)

                -- EVENT: bomb, missile, rocket
                aircraftUnit.OnEventShot = function (self, eventData)
                    if eventData.weapon then
                        local unitName = aircraftUnit:GetName()
                        local weaponCategory = eventData.Weapon:getDesc().category

                        if not unitWeaponsInFlight[unitName] then
                            unitWeaponsInFlight[unitName] = {}
                        end

                        local weaponsInFlight = unitWeaponsInFlight[unitName]
                        weaponsInFlight[#weaponsInFlight+1] = eventData.Weapon

                        -- Bomb
                        if weaponCategory == 3 then

                            -- If this is the first bomb released, check back in one second to see if more were released and report it
                            -- This prevents overwhelming the radio net with release calls when multiple bombs are released
                            if #weaponsInFlight == 1 then
                                local lastCount = 0
                                local function checkForMoreWeaponReleases()
                                    -- We'll assume no more weapons will be released if the count is the same
                                    if #weaponsInFlight == lastCount then
                                        local timeOfFlight = UTILS.Round(getTimeOfFlight(weaponsInFlight[1]), 0)
                                        textToSpeach(tostring(#weaponsInFlight) .. " away. Time of flight " .. tostring(timeOfFlight) .. " seconds.", aircraftUnit)

                                    -- Otherewise, check again later
                                    else
                                        lastCount = lastCount + 1
                                        timer.scheduleFunction(checkForMoreWeaponReleases, {}, timer.getTime() + 1.5)
                                    end
                                end

                                checkForMoreWeaponReleases()
                            end
                        else
                            if #weaponsInFlight == 1 then
                                textToSpeach("Rifle.", aircraftUnit)
                                timer.scheduleFunction(function ()
                                    local timeOfFlight = UTILS.Round(getTimeOfFlight(weaponsInFlight[1]), 0)
                                    textToSpeach("Time of flight " .. tostring(timeOfFlight) .. " secontds.", aircraftUnit)
                                end, {}, timer.getTime() + 1)
                            end
                        end

                        -- Follow weapon until impact, then report
                        local function trackWeaponUntilImpact(weapon)
                            local status, _ =  pcall(function()
                                return weapon:getPoint()
                            end)

                            if not status and #unitWeaponsInFlight[unitName] > 0 then
                                textToSpeach("Splash.", aircraftUnit)

                                -- Stop tracking weapons
                                unitWeaponsInFlight[unitName] = {}
                            else
                                timer.scheduleFunction(trackWeaponUntilImpact, weapon, timer.getTime() + 0.1)
                            end
                        end

                        trackWeaponUntilImpact(eventData.weapon)
                    end
                end -- end OnEventShot handler
                -- EVENT: guns/cannon
                aircraftUnit:HandleEvent(EVENTS.ShootingStart, function (eventData)
                    textToSpeach("Guns", aircraftUnit)
                end)
            end -- end aircraft units loop

            -- Periodically check for low fuel
            local checkFuelScheduler, checkFuleSchedulerId
            checkFuelScheduler, checkFuleSchedulerId = SCHEDULER:New(spawnedGroup, function ()
                if spawnedGroup:GetFuel() < fuelEmptyBuffer then
                    textToSpeach(spawnedGroup:GetCallsign() .. " is bingo fuel and needs to RTB at this time.", spawnedGroup)
                    checkFuelScheduler:Stop(checkFuleSchedulerId)
                end
            end, {}, 0, 10)

            spawnAircraft:SpawnScheduleStop()
        end)

        spawnAircraft:SpawnScheduled(delay, 0.3)

        aircraftCount = aircraftCount + 1
    end

end -- end initializeAircraft

initializeAircraft()

if JTACI and JTACI.isImmortal then
    makeObserversImmortal()
end