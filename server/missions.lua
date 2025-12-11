-- server/missions.lua

---------------------------------------------------------------------
-- Resupply missions (Warehouse Heist)
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:startResupply', function(source, businessId, missionType)
    local src = source
    missionType = missionType or 1

    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end

    if not canAccessBusiness(src, businessId) then
        return false
    end

    if not hasPermForAction(identifier, businessId, 'steal') then
        return false
    end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then
        return false
    end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then
        return false
    end

    local token = Utils.RandomToken()
    ResupplyMissions[token] = {
        src         = src,
        businessId  = businessId,
        missionType = missionType,
        startedAt   = os.time()
    }

    local missionInfo = {
        missionType   = missionType,
        businessLabel = loc.label,
        description   = ('Steal supplies for %s.'):format(loc.label or 'your business')
    }

    discordLog(
        'Resupply Started',
        ('Player %s started resupply (warehouse heist) for %s (%s)')
            :format(GetPlayerName(src), businessId, missionType)
    )

    return true, token, missionInfo
end)

RegisterNetEvent('lv_laitonyritys:server:completeResupply', function(token)
    local src = source
    local mission = ResupplyMissions[token]
    if not mission or mission.src ~= src then
        return
    end

    local businessId = mission.businessId
    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then
        ResupplyMissions[token] = nil
        return
    end

    local data = Businesses[businessId]
    if not data then
        ResupplyMissions[token] = nil
        return
    end

    -- Keep the same scaling as before (1/2/3 missionType) unless you change it later
    local addSupplies = 40
    if mission.missionType == 2 then
        addSupplies = 60
    elseif mission.missionType == 3 then
        addSupplies = 80
    end

    local newSupplies = (data.supplies or 0) + addSupplies
    if newSupplies > typeCfg.maxSupplies then
        newSupplies = typeCfg.maxSupplies
    end

    data.supplies = newSupplies
    saveBusiness(businessId)

    discordLog('Resupply Completed', ('Player %s completed resupply for %s, +%d supplies (warehouse heist).')
        :format(GetPlayerName(src), loc.label, addSupplies))

    ResupplyMissions[token] = nil
end)

-- Cops alerted when the FIRST fingerprint hack starts at the warehouse door
RegisterNetEvent('lv_laitonyritys:server:alertPoliceSupplyHeist', function(businessId)
    local src = source
    local cfg = Config.SupplyHeist or {}
    local coords = cfg.WarehouseEnter or vec3(909.24, -2097.41, 30.55)

    if Config.Dispatch and Config.Dispatch.Enabled and Config.Dispatch.UseTkDispatch then
        local success, err = pcall(function()
            exports.tk_dispatch:addCall({
                title = Config.Dispatch.Title or 'Suspicious activity at illegal business',
                code = Config.Dispatch.Code or '10-90',
                priority = Config.Dispatch.Priority or 'high',
                message = 'Possible warehouse hacking in progress.',
                coords = coords,
                jobs = Config.Dispatch.Jobs or { 'police' },
                blip = {
                    sprite = Config.Dispatch.Blip.sprite or 431,
                    scale  = Config.Dispatch.Blip.scale  or 1.0,
                    color  = Config.Dispatch.Blip.color  or 1,
                    radius = Config.Dispatch.Blip.radius or 150.0
                },
                playSound = true,
                flash = true
            })
        end)

        if not success then
            print('[lv_laitonyritys] tk-dispatch error (supply heist): ' .. tostring(err))
        end
    end

    local loc = Config.Locations[businessId]
    discordLog('Supply Theft Started',
        ('Player %s started a warehouse hack for %s (%s)')
        :format(GetPlayerName(src) or ('ID ' .. src), loc and loc.label or 'Unknown', businessId or 'unknown'))
end)

---------------------------------------------------------------------
-- Sell missions (unchanged)
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:startSell', function(source, businessId, missionType)
    local src = source
    missionType = missionType or 1

    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end

    if not canAccessBusiness(src, businessId) then
        return false
    end

    if not hasPermForAction(identifier, businessId, 'sell') then
        return false
    end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then
        return false
    end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then
        return false
    end

    local minProduct = math.floor(typeCfg.maxProduct * 0.25)
    if (data.product or 0) < minProduct then
        return false
    end

    local token = Utils.RandomToken()
    SellMissions[token] = {
        src        = src,
        businessId = businessId,
        missionType = missionType,
        startedAt  = os.time()
    }

    local missionCfg = Config.SellMissions and Config.SellMissions[missionType] or nil

    local missionInfo = {
        missionType = missionType,
        description = missionCfg and missionCfg.description or 'Deliver product to a buyer.'
    }

    if missionCfg and missionCfg.coords then
        missionInfo.label = missionCfg.label or 'Buyer Location'
        missionInfo.target = {
            x = missionCfg.coords.x,
            y = missionCfg.coords.y,
            z = missionCfg.coords.z,
            w = missionCfg.coords.w
        }
    end

    discordLog('Sell Started', ('Player %s started sell for %s (%s)')
        :format(GetPlayerName(src), businessId, missionType))

    return true, token, missionInfo
end)

RegisterNetEvent('lv_laitonyritys:server:completeSell', function(token)
    local src = source
    local mission = SellMissions[token]
    if not mission or mission.src ~= src then
        return
    end

    local businessId = mission.businessId
    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then
        SellMissions[token] = nil
        return
    end

    local data = Businesses[businessId]
    if not data then
        SellMissions[token] = nil
        return
    end

    local product = data.product or 0
    if product <= 0 then
        SellMissions[token] = nil
        return
    end

    local amountSold = product
    data.product = 0
    saveBusiness(businessId)

    local effectivePrice = getEffectiveProductPrice(businessId)
    local payout = amountSold * effectivePrice

    if Config.Framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            xPlayer.addAccountMoney('black_money', payout)
        end
    end

    discordLog('Sell Completed', ('Player %s sold %d units from %s for $%d.')
        :format(GetPlayerName(src), amountSold, loc.label, payout))

    SellMissions[token] = nil
end)

---------------------------------------------------------------------
-- Setup mission (unchanged)
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:startSetup', function(source, businessId)
    local src = source
    if ActiveSetups[src] then
        return { ok = false, reason = 'already_active' }
    end

    local identifier = select(1, getIdentifier(src))
    if not identifier then
        return { ok = false, reason = 'no_identifier' }
    end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then
        return { ok = false, reason = 'invalid_business' }
    end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= identifier then
        return { ok = false, reason = 'not_owner' }
    end

    if (data.setup_completed or 0) == 1 then
        return { ok = false, reason = 'already_setup' }
    end

    if not Config.SetupTruck then
        return { ok = false, reason = 'no_truck_config' }
    end

    if not loc.setupDelivery then
        return { ok = false, reason = 'no_delivery_config' }
    end

    ActiveSetups[src] = {
        businessId = businessId,
        truckNetId = nil
    }

    TriggerClientEvent('lv_laitonyritys:client:beginSetup', src, businessId, Config.SetupTruck, loc.setupDelivery, loc.label)

    return { ok = true }
end)

RegisterNetEvent('lv_laitonyritys:server:setupTruckSpawned', function(netId)
    local src = source
    local setup = ActiveSetups[src]
    if not setup then return end
    setup.truckNetId = netId
end)

RegisterNetEvent('lv_laitonyritys:server:completeSetup', function(businessId)
    local src = source
    local setup = ActiveSetups[src]
    if not setup or setup.businessId ~= businessId then return end

    local identifier = select(1, getIdentifier(src))
    if not identifier then
        ActiveSetups[src] = nil
        return
    end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= identifier then
        ActiveSetups[src] = nil
        return
    end

    if (data.setup_completed or 0) == 1 then
        ActiveSetups[src] = nil
        return
    end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if typeCfg and typeCfg.maxSupplies then
        data.supplies = typeCfg.maxSupplies
    end

    data.setup_completed = 1
    saveBusiness(businessId)

    if setup.truckNetId then
        local ent = NetworkGetEntityFromNetworkId(setup.truckNetId)
        if ent ~= 0 and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end

    ActiveSetups[src] = nil

    TriggerClientEvent('lv_laitonyritys:client:setupCompleted', src, businessId)
end)

---------------------------------------------------------------------
-- Business stash (unchanged)
---------------------------------------------------------------------

RegisterNetEvent('lv_laitonyritys:server:openStash', function(businessId)
    local src = source
    local identifier = select(1, getIdentifier(src))
    if not identifier then return end

    local loc = Config.Locations[businessId]
    if not loc then return end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then
        return
    end

    if not hasPermForAction(identifier, businessId, 'stash') then
        TriggerClientEvent('ox_lib:notify', src, {
            title = loc.label or 'Business',
            description = 'You do not have access to this stash.',
            type = 'error'
        })
        return
    end

    if (data.setup_completed or 0) ~= 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = loc.label or 'Business',
            description = 'You must complete the business setup before using the stash.',
            type = 'error'
        })
        return
    end

    local stashId = ('lv_business:%s'):format(businessId)
    local label   = ('%s Stash'):format(loc.label or 'Business Stash')

    local maxWeight = 120000
    local slots     = 50

    exports.ox_inventory:RegisterStash(stashId, label, slots, maxWeight, true)
    TriggerClientEvent('ox_inventory:openInventory', src, 'stash', stashId)
end)
