-- server/raids.lua

ESX = ESX or exports['es_extended']:getSharedObject()

ActiveRaids = ActiveRaids or {} -- [businessId] = { startedAt, endsAt, doorBreached }

local function isPoliceJob(jobName)
    if not jobName then return false end
    local cfg = Config.Raids and Config.Raids.PoliceJobs or {}
    for _, j in ipairs(cfg) do
        if j == jobName then
            return true
        end
    end
    return false
end

local function getPlayersInsideBusiness(businessId)
    local result = {}
    if not businessId or not PlayersInBusiness then return result end

    for src, bId in pairs(PlayersInBusiness) do
        if bId == businessId then
            result[#result+1] = src
        end
    end

    return result
end

local function isPolice(src)
    if Config.Framework ~= 'esx' or not ESX then return false end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.job or not xPlayer.job.name then return false end
    return isPoliceJob(xPlayer.job.name)
end

local function getPolicePlayers()
    local cops = {}

    if Config.Framework ~= 'esx' or not ESX then
        return cops
    end

    if ESX.GetExtendedPlayers then
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            if xPlayer.job and isPoliceJob(xPlayer.job.name) then
                cops[#cops + 1] = xPlayer.source
            end
        end
    elseif ESX.GetPlayers then
        for _, src in ipairs(ESX.GetPlayers()) do
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer and xPlayer.job and isPoliceJob(xPlayer.job.name) then
                cops[#cops + 1] = src
            end
        end
    end

    return cops
end

local function syncRaidStateToCops(businessId)
    local raid = ActiveRaids[businessId]
    local payload

    if raid then
        payload = {
            active       = true,
            doorBreached = raid.doorBreached or false,
            businessId   = businessId,
            endsAt       = raid.endsAt
        }
    else
        payload = nil
    end

    local cops = getPolicePlayers()
    for _, src in ipairs(cops) do
        TriggerClientEvent('lv_laitonyritys:client:setRaidState', src, businessId, payload)
    end
end

local function getOnlineSourcesForIdentifier(identifier)
    local result = {}
    if not identifier or Config.Framework ~= 'esx' or not ESX then return result end

    if ESX.GetExtendedPlayers then
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            if xPlayer.identifier == identifier then
                result[#result+1] = xPlayer.source
            end
        end
    elseif ESX.GetPlayers then
        for _, src in ipairs(ESX.GetPlayers()) do
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer and xPlayer.identifier == identifier then
                result[#result+1] = src
            end
        end
    end

    return result
end

local function notifyOwnerAndKeysRaid(businessId, text)
    local data = Businesses[businessId]
    if not data or not data.owner_identifier then return end

    local loc = Config.Locations[businessId]
    if not loc then return end

    local recipients = {}

    -- owner
    for _, src in ipairs(getOnlineSourcesForIdentifier(data.owner_identifier)) do
        recipients[#recipients+1] = src
    end

    -- associates
    local access = loadAccess(businessId)
    for identifier, _ in pairs(access or {}) do
        for _, src in ipairs(getOnlineSourcesForIdentifier(identifier)) do
            recipients[#recipients+1] = src
        end
    end

    for _, src in ipairs(recipients) do
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Business Raid',
            description = text or ('Police have raided your ' .. (loc.label or 'business') .. '.'),
            type        = 'error',
            duration    = 10000
        })
    end
end

local function startRaidForBusiness(businessId)
    if ActiveRaids[businessId] then return end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then return end
    if (data.setup_completed or 0) ~= 1 then return end
    if (data.is_shut_down or 0) ~= 0 then return end

    -- Optional: only raid if there is actually something to take
    if (data.product or 0) <= 0 and (data.supplies or 0) <= 0 then
        if Config.Debug then
            print(('[lv_laitonyritys] Raid skipped for %s (nothing to confiscate)'):format(businessId))
        end
        return
    end

    local now = os.time()
    local windowMinutes = (Config.Raids and Config.Raids.RaidWindowMinutes) or 30

    ActiveRaids[businessId] = {
        startedAt    = now,
        endsAt       = now + (windowMinutes * 60),
        doorBreached = false
    }

    -- tk-dispatch call + discord log
    sendRaidDispatch(businessId)
    discordLog('Raid Alert', ('Police raid alert started for %s (%s)'):format(loc.label, businessId))

    if Config.Debug then
        print(('[lv_laitonyritys] Raid started for %s'):format(businessId))
    end

    -- Notify cops and give them state
    syncRaidStateToCops(businessId)

    -- For anyone ALREADY inside this business, wake guards right now
    -- For anyone ALREADY inside this business, wake guards right now
    for _, src in ipairs(getPlayersInsideBusiness(businessId)) do
        TriggerClientEvent('lv_laitonyritys:client:onRaidStart', src, businessId)
    end
end

-- Periodic raid chance loop
CreateThread(function()
    if not Config.Raids or not Config.Raids.Enabled then
        return
    end

    local tickMinutes = Config.Raids.CheckIntervalMinutes or 30
    local tickMs = math.floor(tickMinutes * 60000)

    -- seed once
    math.randomseed(os.time() % 2147483647)

    while true do
        Wait(tickMs)

        local cops = getPolicePlayers()
        local numCops = #cops

        if Config.Raids.RequireOnDutyPolice and numCops < (Config.Raids.MinPolice or 0) then
            goto continue
        end

        local candidates = {}

        for businessId, data in pairs(Businesses) do
            if data.owner_identifier and (data.setup_completed or 0) == 1 and (data.is_shut_down or 0) == 0 then
                if not ActiveRaids[businessId] then
                    local loc, typeCfg = getBusinessTypeCfg(businessId)
                    if loc and typeCfg then
                        local baseChance = (Config.Raids.BaseRaidChance or 0.05)
                        local secLevel = data.security_level or 0
                        local reduction = (Config.Raids.SecurityReductionPerLevel or 0.0) * secLevel
                        local chance = math.max(0.0, baseChance - reduction)

                        if chance > 0 and math.random() < chance then
                            candidates[#candidates+1] = businessId
                        end
                    end
                end
            end
        end

        if #candidates > 0 then
            local pick = candidates[math.random(1, #candidates)]
            startRaidForBusiness(pick)
        end

        ::continue::
    end
end)

-- Expiry cleanup loop
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for businessId, raid in pairs(ActiveRaids) do
            if raid.endsAt and now >= raid.endsAt then
                ActiveRaids[businessId] = nil
                syncRaidStateToCops(businessId)
                if Config.Debug then
                    print(('[lv_laitonyritys] Raid window expired for %s'):format(businessId))
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- Callbacks & events for cops
---------------------------------------------------------------------

-- Used by cops when pressing E at the entrance to see if they can raid / lockpick
lib.callback.register('lv_laitonyritys:attemptRaidEntry', function(source, businessId)
    local src = source
    if not isPolice(src) then
        return { ok = false, reason = 'not_police' }
    end

    local raid = ActiveRaids[businessId]
    if not raid then
        return { ok = false, reason = 'no_active_raid' }
    end

    local now = os.time()
    if raid.endsAt and now >= raid.endsAt then
        ActiveRaids[businessId] = nil
        syncRaidStateToCops(businessId)
        return { ok = false, reason = 'raid_expired' }
    end

    return {
        ok           = true,
        doorBreached = raid.doorBreached or false
    }
end)

-- Lockpick success -> mark door as breached, and update cops
RegisterNetEvent('lv_laitonyritys:server:raidDoorBreached', function(businessId)
    local src = source
    if not isPolice(src) then return end

    local raid = ActiveRaids[businessId]
    if not raid then return end

    raid.doorBreached = true
    syncRaidStateToCops(businessId)

    local loc = Config.Locations[businessId]
    if loc then
        discordLog('Raid Breach', ('Police breached the door at %s (%s)'):format(loc.label, businessId))
    end

    if Config.Debug then
        print(('[lv_laitonyritys] Door breached for %s by %s'):format(businessId, GetPlayerName(src) or src))
    end
end)

-- Called by cops after teleporting inside (after door breached)
RegisterNetEvent('lv_laitonyritys:server:enterRaidInterior', function(businessId)
    local src = source
    if not isPolice(src) then return end

    local raid = ActiveRaids[businessId]
    if not raid or not raid.doorBreached then return end

    -- Make guards hostile for players inside
    TriggerClientEvent('lv_laitonyritys:client:onRaidStart', -1, businessId)

    if Config.Debug then
        print(('[lv_laitonyritys] Cop %s entered raid interior %s'):format(GetPlayerName(src) or src, businessId))
    end
end)

-- Confiscation of lab (supplies + product)
RegisterNetEvent('lv_laitonyritys:server:confiscateBusiness', function(businessId)
    local src = source
    if not isPolice(src) then return end

    local raid = ActiveRaids[businessId]
    if not raid then return end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then return end

    -- Wipe production and supplies
    data.supplies = 0
    data.product  = 0
    saveBusiness(businessId)

    -- End raid & sync off
    ActiveRaids[businessId] = nil
    syncRaidStateToCops(businessId)

    discordLog('Raid Confiscation', ('Police confiscated all supplies and product from %s (%s)'):format(loc.label, businessId))

    -- Update visuals inside (interior + props)
    TriggerClientEvent('lv_laitonyritys:client:raidConfiscated', -1, businessId)
    TriggerClientEvent('lv_laitonyritys:client:clearProductionProps', -1, businessId)

    -- Notify owner + key holders
    notifyOwnerAndKeysRaid(businessId, ('Police have confiscated all supplies and product from %s.'):format(loc.label))
end)

---------------------------------------------------------------------
-- Raid state query (for clients entering after raid started)
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:getRaidState', function(source, businessId)
    local raid = ActiveRaids[businessId]
    if not raid then
        return nil
    end

    local now = os.time()
    if raid.endsAt and now >= raid.endsAt then
        -- auto-expire if needed
        ActiveRaids[businessId] = nil
        syncRaidStateToCops(businessId)
        return nil
    end

    return {
        active       = true,
        doorBreached = raid.doorBreached or false,
        endsAt       = raid.endsAt
    }
end)

---------------------------------------------------------------------
-- TEST COMMAND: /testraid [businessId]
---------------------------------------------------------------------

RegisterCommand('testraid', function(src, args)
    -- Console can always use it
    if src ~= 0 then
        local hasAce = IsPlayerAceAllowed(src, 'lv_laitonyritys.raidadmin')
        if not isPolice(src) and not hasAce then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'Test Raid',
                description = 'You are not allowed to use this command.',
                type        = 'error'
            })
            return
        end
    end

    local businessId = args[1]

    if businessId and not Config.Locations[businessId] then
        if src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'Test Raid',
                description = ('Unknown business id: %s'):format(businessId),
                type        = 'error'
            })
        else
            print(('[lv_laitonyritys] Unknown business id: %s'):format(businessId))
        end
        return
    end

    if not businessId then
        -- pick a random valid business (owned + setup completed + not shut down)
        local candidates = {}
        for id, data in pairs(Businesses) do
            if data.owner_identifier and (data.setup_completed or 0) == 1 and (data.is_shut_down or 0) == 0 then
                candidates[#candidates+1] = id
            end
        end

        if #candidates == 0 then
            if src ~= 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title       = 'Test Raid',
                    description = 'No valid businesses to raid (need an owned, set-up, active business).',
                    type        = 'error'
                })
            else
                print('[lv_laitonyritys] No valid businesses to test raid.')
            end
            return
        end

        businessId = candidates[math.random(1, #candidates)]
    end

    startRaidForBusiness(businessId)

    local loc = Config.Locations[businessId]
    local label = loc and loc.label or businessId

    if src ~= 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Test Raid',
            description = ('Started test raid for %s (%s).'):format(label, businessId),
            type        = 'success'
        })
    else
        print(('[lv_laitonyritys] Started test raid for %s (%s).'):format(label, businessId))
    end
end, false)
