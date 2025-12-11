-- server/raids.lua

ActiveRaids = ActiveRaids or {} -- [businessId] = { expiresAt, breached, confiscated }

local function isPolice(src)
    if Config.Framework ~= 'esx' or not ESX then return false end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local jobName = xPlayer.job and xPlayer.job.name
    for _, j in ipairs(Config.Raids.PoliceJobs) do
        if jobName == j then
            return true
        end
    end

    return false
end

local function getOnlinePoliceCount()
    local count = 0
    for _, src in ipairs(GetPlayers()) do
        if isPolice(src) then
            count = count + 1
        end
    end
    return count
end

local function getRaidState(businessId)
    local raid = ActiveRaids[businessId]
    if not raid then return nil end

    local now = os.time()
    if raid.expiresAt and raid.expiresAt <= now then
        ActiveRaids[businessId] = nil
        TriggerClientEvent('lv_laitonyritys:client:updateRaidState', -1, businessId, nil)
        return nil
    end

    return raid
end

local function cleanupExpiredRaids()
    for businessId, _ in pairs(ActiveRaids) do
        getRaidState(businessId)
    end
end

local function setRaidState(businessId, state)
    ActiveRaids[businessId] = state
    TriggerClientEvent('lv_laitonyritys:client:updateRaidState', -1, businessId, state)
end

local function startRaidAlert(businessId)
    local duration = (Config.Raids.RaidWindowMinutes or 30) * 60
    local raidState = {
        businessId = businessId,
        breached = false,
        confiscated = false,
        expiresAt = os.time() + duration
    }

    setRaidState(businessId, raidState)
    sendRaidDispatch(businessId)
    TriggerClientEvent('lv_laitonyritys:client:raidCamera', -1, businessId)

    local loc = Config.Locations[businessId]
    discordLog(
        'Police Raid Alert',
        ('A dispatch alert was triggered for %s (%s). Officers can respond for a limited time.')
            :format(loc and loc.label or 'Business', businessId)
    )
end

local function performRaidCheck()
    if not Config.Raids.Enabled then return end

    cleanupExpiredRaids()

    if Config.Raids.RequireOnDutyPolice and getOnlinePoliceCount() < Config.Raids.MinPolice then
        return
    end

    for businessId, data in pairs(Businesses) do
        if data.owner_identifier and (data.is_shut_down or 0) == 0 and not ActiveRaids[businessId] then
            local chance = Config.Raids.BaseRaidChance - (data.security_level or 0) * Config.Raids.SecurityReductionPerLevel
            if chance < 0.0 then chance = 0.0 end
            if math.random() < chance then
                startRaidAlert(businessId)
            end
        end
    end
end

local function notifyRaidVictims(businessId)
    local data = Businesses[businessId]
    if not data then return end

    local owners = {}
    if data.owner_identifier then
        owners[data.owner_identifier] = data.owner_name or 'Owner'
    end

    local access = loadAccess(businessId)
    for identifier, info in pairs(access) do
        owners[identifier] = info.name or identifier
    end

    for _, src in ipairs(GetPlayers()) do
        local identifier = select(1, getIdentifier(src))
        if identifier and owners[identifier] then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Police Raid',
                description = 'Police raid in progress at your lab. Production confiscated!',
                type = 'error',
                duration = 10000,
                sound = 'alert'
            })
        end
    end
end

lib.callback.register('lv_laitonyritys:isRaidActive', function(_, businessId)
    return getRaidState(businessId) ~= nil
end)

lib.callback.register('lv_laitonyritys:canPoliceRaid', function(source, businessId)
    if not getRaidState(businessId) then
        return false, 'No active dispatch alert for this lab.'
    end

    if not isPolice(source) then
        return false, 'Only police can initiate a raid.'
    end

    return true
end)

lib.callback.register('lv_laitonyritys:canEnterRaid', function(source, businessId)
    local raid = getRaidState(businessId)
    if not raid or not raid.breached then return false end
    if not isPolice(source) then return false end
    return true
end)

RegisterNetEvent('lv_laitonyritys:server:markRaidBreached', function(businessId)
    local src = source
    local raid = getRaidState(businessId)
    if not raid or raid.breached or raid.confiscated then return end
    if not isPolice(src) then return end

    raid.breached = true
    raid.expiresAt = os.time() + ((Config.Raids.RaidWindowMinutes or 30) * 60)
    setRaidState(businessId, raid)

    TriggerClientEvent('lv_laitonyritys:client:onRaidStart', -1, businessId)
    discordLog('Police Raid Breach', ('Officers breached %s (%s).'):format(
        (Config.Locations[businessId] and Config.Locations[businessId].label) or 'Business',
        businessId
    ))
end)

RegisterNetEvent('lv_laitonyritys:server:confiscateLab', function(businessId)
    local src = source
    local raid = getRaidState(businessId)
    if not raid or raid.confiscated or not raid.breached then return end
    if not isPolice(src) then return end

    local data = Businesses[businessId]
    if data then
        data.product = 0
        data.supplies = 0
        saveBusiness(businessId)
    end

    raid.confiscated = true
    raid.expiresAt = os.time() + 120 -- give a short clean-up window
    setRaidState(businessId, raid)

    notifyRaidVictims(businessId)
    discordLog('Police Raid Confiscation', ('Officers confiscated production at %s (%s).'):format(
        (Config.Locations[businessId] and Config.Locations[businessId].label) or 'Business',
        businessId
    ))
end)

RegisterCommand('testraid', function(src, args)
    local businessId = args[1]
    if not businessId then
        if src == 0 then
            print('[testraid] Usage: /testraid <businessId>')
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Test Raid',
                description = 'Usage: /testraid <businessId>',
                type = 'error'
            })
        end
        return
    end

    if not Config.Locations[businessId] then
        if src == 0 then
            print(('[testraid] Invalid business id: %s'):format(businessId))
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Test Raid',
                description = 'Invalid business id.',
                type = 'error'
            })
        end
        return
    end

    if src ~= 0 and not isPolice(src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Test Raid',
            description = 'Only police can start a test raid.',
            type = 'error'
        })
        return
    end

    if getRaidState(businessId) then
        if src == 0 then
            print(('[testraid] Raid already active for %s'):format(businessId))
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Test Raid',
                description = 'Raid already active for this lab.',
                type = 'warning'
            })
        end
        return
    end

    startRaidAlert(businessId)

    if src == 0 then
        print(('[testraid] Raid alert started for %s'):format(businessId))
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Test Raid',
            description = ('Raid alert started for %s'):format(Config.Locations[businessId].label or businessId),
            type = 'success'
        })
    end
end, false)

CreateThread(function()
    while true do
        Wait(Config.Raids.CheckIntervalMinutes * 60000)
        performRaidCheck()
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        cleanupExpiredRaids()
    end
end)
