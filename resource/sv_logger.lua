-- Prevent running in monitor mode
if not TX_SERVER_MODE then return end


-- =============================================
--  Logger
-- =============================================

-- Micro optimization & variables
local sub = string.sub
local ostime = os.time
local tonumber = tonumber
local luaType = type
local loggerBuffer = {}

-- Limits for data that can come from a game client
local MAX_STRING = 512
local MAX_DEPTH = 3
local MAX_ITEMS = 32
local MAX_BUFFERED = 2000
local WARN_INTERVAL = 30

local lastWarning = {}
local wasChanged = false


--- Makes any value safe to serialize: no NaN/Infinity (invalid JSON, so the whole batch would be lost),
--- no huge strings (they ended up in error messages and crashed old servers), no functions or userdata.
local function sanitizeLogValue(value, depth)
    local valueType = luaType(value)
    if valueType == 'string' then
        if #value > MAX_STRING then
            wasChanged = true
            return sub(value, 1, MAX_STRING)..'...'
        end
        return value
    elseif valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            wasChanged = true
            return 0
        end
        return value
    elseif valueType == 'boolean' or valueType == 'nil' then
        return value
    elseif valueType == 'table' then
        if depth >= MAX_DEPTH then
            wasChanged = true
            return '[table]'
        end
        local out, count = {}, 0
        for k, v in pairs(value) do
            count = count + 1
            if count > MAX_ITEMS then
                wasChanged = true
                break
            end
            local keyType = luaType(k)
            if keyType == 'string' then
                if #k > MAX_STRING then
                    wasChanged = true
                    k = sub(k, 1, 64)..'...'
                end
                out[k] = sanitizeLogValue(v, depth + 1)
            elseif keyType == 'number' and k == k and k ~= math.huge and k ~= -math.huge then
                out[k] = sanitizeLogValue(v, depth + 1)
            else
                wasChanged = true
            end
        end
        return out
    end
    wasChanged = true
    return '['..valueType..']'
end


--- Prints who sent it, so whoever tries this can be found. At most once per player every 30 seconds.
local function warnInvalidEvent(src, type)
    if luaType(src) ~= 'number' or (lastWarning[src] or 0) + WARN_INTERVAL > ostime() then return end
    lastWarning[src] = ostime()
    print(('^1[txAdmin] Player #%d (%s) sent invalid or oversized data in a %s event.^0'):format(
        src,
        sub(GetPlayerName(src) or 'unknown', 1, 75),
        type
    ))
end


--- function logger
--- Sends logs through fd3 to the server & displays the logs on the panel.
---@param src number the source of the player who did the action, or 'tx' if internal
---@param type string the action type
---@param data table|nil the event data
local function logger(src, type, data)
    if src ~= 'tx' then
        if luaType(src) ~= 'number' or src ~= src then return end
        if #loggerBuffer >= MAX_BUFFERED then return end

        wasChanged = false
        data = sanitizeLogValue(data, 0)
        if wasChanged then warnInvalidEvent(src, type) end
    end

    loggerBuffer[#loggerBuffer+1] = {
        src = src,
        type = type,
        data = data or false
    }
end

AddEventHandler('playerDropped', function()
    lastWarning[source] = nil
end)


-- send all of the buffered logs every second
CreateThread(function()
    while true do
        Wait(1000)
        if #loggerBuffer > 0 then
            -- Adding timestamp with fake ms to log entries
            local ts = ostime() * 1000
            for i = 1, #loggerBuffer do
                if i <= 999 then
                    loggerBuffer[i].ts = ts + i-1
                else
                    loggerBuffer[i].ts = ts + 999
                end
            end

            --Sending logs via FD3 and resetting buffer (before encoding, an error must not stop this thread)
            local logs = loggerBuffer
            loggerBuffer = {}
            local success, payload = pcall(json.encode, {
                type = 'txAdminLogData',
                logs = logs
            })
            if success then
                PrintStructuredTrace(payload)
            end
        end
    end
end)

--Send initial data
CreateThread(function()
    local resList = {}
    local resCount = GetNumResources() - 1
    for i = 0, resCount do
        local resName = GetResourceByFindIndex(i)
        if GetResourceState(resName) == 'started' then
            local resVersion = GetResourceMetadata(resName, 'version')
            if type(resVersion) == 'string' and #resVersion > 0 then
                resList[#resList+1] = resName..'/'..resVersion
            else
                resList[#resList+1] = resName
            end
        end
    end

    logger('tx', 'LoggerStarted', {
        --txAdmin.metrics.playerDrops data
        gameName = GetConvar('gamename', 'gta5'),
        gameBuild = GetConvar('sv_enforceGameBuild', 'invalid'),
        fxsVersion = GetConvar('version', 'invalid'),
        resources = resList,
    })
end)


-- Explosion handler
local function isInvalid(property, invalidType)
    return (property == nil or property == invalidType)
end

local explosionTypes = {'GRENADE', 'GRENADELAUNCHER', 'STICKYBOMB', 'MOLOTOV', 'ROCKET', 'TANKSHELL', 'HI_OCTANE', 'CAR', 'PLANE', 'PETROL_PUMP', 'BIKE', 'DIR_STEAM', 'DIR_FLAME', 'DIR_WATER_HYDRANT', 'DIR_GAS_CANISTER', 'BOAT', 'SHIP_DESTROY', 'TRUCK', 'BULLET', 'SMOKEGRENADELAUNCHER', 'SMOKEGRENADE', 'BZGAS', 'FLARE', 'GAS_CANISTER', 'EXTINGUISHER', 'PROGRAMMABLEAR', 'TRAIN', 'BARREL', 'PROPANE', 'BLIMP', 'DIR_FLAME_EXPLODE', 'TANKER', 'PLANE_ROCKET', 'VEHICLE_BULLET', 'GAS_TANK', 'BIRD_CRAP', 'RAILGUN', 'BLIMP2', 'FIREWORK', 'SNOWBALL', 'PROXMINE', 'VALKYRIE_CANNON', 'AIR_DEFENCE', 'PIPEBOMB', 'VEHICLEMINE', 'EXPLOSIVEAMMO', 'APCSHELL', 'BOMB_CLUSTER', 'BOMB_GAS', 'BOMB_INCENDIARY', 'BOMB_STANDARD', 'TORPEDO', 'TORPEDO_UNDERWATER', 'BOMBUSHKA_CANNON', 'BOMB_CLUSTER_SECONDARY', 'HUNTER_BARRAGE', 'HUNTER_CANNON', 'ROGUE_CANNON', 'MINE_UNDERWATER', 'ORBITAL_CANNON', 'BOMB_STANDARD_WIDE', 'EXPLOSIVEAMMO_SHOTGUN', 'OPPRESSOR2_CANNON', 'MORTAR_KINETIC', 'VEHICLEMINE_KINETIC', 'VEHICLEMINE_EMP', 'VEHICLEMINE_SPIKE', 'VEHICLEMINE_SLICK', 'VEHICLEMINE_TAR', 'SCRIPT_DRONE', 'RAYGUN', 'BURIEDMINE', 'SCRIPT_MISSIL'}

AddEventHandler('explosionEvent', function(source, ev)
    if (isInvalid(ev.damageScale, 0) or isInvalid(ev.cameraShake, 0) or isInvalid(ev.isInvisible, true) or
        isInvalid(ev.isAudible, false)) then
        return
    end

    if ev.explosionType < -1 or ev.explosionType > 77 then
        ev.explosionType = 'UNKNOWN'
    else
        ev.explosionType = explosionTypes[ev.explosionType + 1]
    end

    logger(tonumber(source), 'explosionEvent', ev)
end)


-- An internal server handler, this is NOT exposed to the client
local function getLogPlayerName(src)
    if type(src) == 'number' then 
        local name = sub(GetPlayerName(src) or "unknown", 1, 75)
        return '[#'..src..'] '..name
    else
        return '[??] '.. (src or "unknown")
    end
end

AddEventHandler('txsv:logger:menuEvent', function(source, action, allowed, data)
    if not allowed then return end
    local message

    --SELF menu options
    if action == 'playerModeChanged' then
        if data == 'godmode' then
            message = "enabled god mode"
        elseif data == 'noclip' then
            message = "enabled noclip"
        elseif data == 'superjump' then
            message = "enabled super jump"
        elseif data == 'none' then
            message = "became mortal (standard mode)"
        else
            message = "changed playermode to unknown"
        end

    elseif action == 'teleportWaypoint' then
        message = "teleported to a waypoint"

    elseif action == 'teleportCoords' then
        if type(data) ~= 'table' then return end
        local x = data.x
        local y = data.y
        local z = data.z
        message = ("teleported to coordinates (x=%.3f, y=%0.3f, z=%0.3f)"):format(x or 0.0, y or 0.0, z or 0.0)

    elseif action == 'spawnVehicle' then
        if type(data) ~= 'string' then return end
        message = "spawned a vehicle (model: " .. data .. ")"

    elseif action == 'deleteVehicle' then
        message = "deleted a vehicle"

    elseif action == 'vehicleRepair' then
        message = "repaired their vehicle"

    elseif action == 'vehicleBoost' then
        message = "boosted their vehicle"

    elseif action == 'healSelf' then
        message = "healed themself"

    elseif action == 'healAll' then
        message = "healed all players!"

    elseif action == 'announcement' then
        if type(data) ~= 'string' then return end
        message = "made a server-wide announcement: " .. data

    elseif action == 'clearArea' then
        if type(data) ~= 'number' then return end
        message = "cleared an area with ".. data .."m radius"

    --INTERACTION modal options
    elseif action == 'spectatePlayer' then
        message = 'started spectating player ' .. getLogPlayerName(data)

    elseif action == 'freezePlayer' then
        message = 'toggled freeze on player ' .. getLogPlayerName(data)

    elseif action == 'teleportPlayer' then
        if type(data) ~= 'table' then return end
        local playerName = getLogPlayerName(data.target)
        local x = data.x or 0.0
        local y = data.y or 0.0
        local z = data.z or 0.0
        message = ("teleported to player %s (x=%.3f, y=%.3f, z=%.3f)"):format(playerName, x, y, z)

    elseif action == 'healPlayer' then
        message = "healed player " .. getLogPlayerName(data)

    elseif action == 'summonPlayer' then
        message = "summoned player " .. getLogPlayerName(data)

    --TROLL modal options
    elseif action == 'drunkEffect' then
        message = "triggered drunk effect on " .. getLogPlayerName(data)

    elseif action == 'setOnFire' then
        message = "set ".. getLogPlayerName(data) .." on fire" 

    elseif action == 'wildAttack' then
        message = "triggered wild attack on " .. getLogPlayerName(data)

    elseif action == 'showPlayerIDs' then
        if type(data) ~= 'boolean' then return end
        if data then
            message = "turned show player IDs on"
        else
            message = "turned show player IDs off"
        end

    --In case of unknown event
    else
        logger(source, 'DebugMessage', "unknown menu event "..action)
        return
    end

    logger(source, 'MenuEvent', {
        action = action,
        message = message
    })
end)

-- Extra handlers
RegisterNetEvent('txsv:logger:deathEvent', function(killer, cause)
    if killer and luaType(killer) ~= 'number' or cause and luaType(cause) ~= 'string' then
        return warnInvalidEvent(source, 'DeathNotice')
    end
    local logData = {
        cause = cause,
        killer = killer
    }
    logger(source, 'DeathNotice', logData)
end)

--FIXME: deprecate or allow server commands
--FIXME: didn't migrate to keep compatibility with external calls
RegisterNetEvent('txaLogger:CommandExecuted', function(data)
    if luaType(data) ~= 'string' then return warnInvalidEvent(source, 'CommandExecuted') end
    logger(source, 'CommandExecuted', data)
end)

--FIXME: didn't migrate to keep compatibility with external calls
RegisterNetEvent('txaLogger:DebugMessage', function(data)
    if luaType(data) ~= 'string' then return warnInvalidEvent(source, 'DebugMessage') end
    logger(source, 'DebugMessage', data)
end)

local function logChatMessage(src, author, text)
    -- when the event comes from a client all three arguments are the client's, even the source
    local fromClient = luaType(source) == 'number'
    if fromClient then src = source end
    if author and luaType(author) ~= 'string' or text and luaType(text) ~= 'string' then
        if fromClient then return warnInvalidEvent(source, 'ChatMessage') end
        author = luaType(author) == 'string' and author or nil
        text = luaType(text) == 'string' and text or nil
    end
    local logData = {
        author = author,
        text = text
    }
    logger(src, 'ChatMessage', logData)
end
RegisterNetEvent('chatMessage', logChatMessage)
AddEventHandler('txsv:logger:addChatMessage', logChatMessage)
