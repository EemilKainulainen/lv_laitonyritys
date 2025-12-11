-- server/ui_callbacks.lua

---------------------------------------------------------------------
-- Basic data for laptop + browser
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:getBusinessData', function(source, businessId)
    return buildBusinessData(source, businessId)
end)

lib.callback.register('lv_laitonyritys:getBusinessBrowserData', function(source)
    local src = source
    local identifier, name = getIdentifier(src)
    if not identifier then return nil end

    local cash, bank = 0, 0

    if Config.Framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            cash = xPlayer.getMoney()
            bank = xPlayer.getAccount('bank').money
        end
    end

    local businesses = {}

    for businessId, loc in pairs(Config.Locations) do
        local data = Businesses[businessId]
        local owned = data and data.owner_identifier ~= nil
        local isOwner = owned and data.owner_identifier == identifier or false
        local typeCfg = Config.BusinessTypes[loc.type]

        local price = loc.price or 500000
        local area  = loc.area or 'Unknown'

        businesses[#businesses+1] = {
            businessId  = businessId,
            label       = loc.label,
            type        = loc.type,
            typeLabel   = typeCfg and typeCfg.label or loc.type,
            owned       = owned,
            isOwner     = isOwner,
            ownerName   = data and data.owner_name or nil,
            price       = price,
            area        = area,
            image       = loc.image,
            description = loc.description,
        }
    end

    return {
        playerName = name or ('ID ' .. src),
        cash       = cash,
        bank       = bank,
        businesses = businesses
    }
end)

---------------------------------------------------------------------
-- Business purchase / intro
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:purchaseBusiness', function(source, businessId)
    local src = source
    local identifier, name = getIdentifier(src)
    if not identifier then return false end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return false end

    local data = Businesses[businessId]
    if data and data.owner_identifier then
        return false
    end

    if countPlayerBusinesses(identifier) >= Config.MaxBusinessesPerPlayer then
        return false
    end

    local xPlayer
    if Config.Framework == 'esx' and ESX then
        xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
    end

    local price = loc.price or 500000

    if xPlayer then
        if xPlayer.getAccount('bank').money < price then
            return false
        end
        xPlayer.removeAccountMoney('bank', price)
    end

    Businesses[businessId] = {
        business_id      = businessId,
        owner_identifier = identifier,
        owner_name       = name,
        supplies         = 0,
        product          = 0,
        equipment_level  = 0,
        employees_level  = 0,
        security_level   = 0,
        is_shut_down     = 0,
        setup_completed  = 0,
        has_seen_intro   = 0
    }
    saveBusiness(businessId)

    discordLog('Business Purchased', ('%s bought %s (%s) for $%s'):format(
        name or ('ID ' .. src), loc.label, businessId, price
    ))

    return true
end)

lib.callback.register('lv_laitonyritys:shouldShowIntro', function(source, businessId)
    local src = source
    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end

    local data = Businesses[businessId]
    if not data then return false end

    if data.owner_identifier ~= identifier then
        return false
    end

    if (data.has_seen_intro or 0) == 1 then
        return false
    end

    data.has_seen_intro = 1

    MySQL.update.await(
        'UPDATE lv_illegal_businesses SET has_seen_intro = 1 WHERE business_id = ?',
        { businessId }
    )

    return true
end)

---------------------------------------------------------------------
-- Supplies / list / owner checks
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:buySupplies', function(source, businessId, amount)
    local src = source
    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return false end

    local data = Businesses[businessId]
    if not data then return false end

    if not hasPermForAction(identifier, businessId, 'buy') then
        return false
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local newSupplies = (data.supplies or 0) + amount
    if newSupplies > typeCfg.maxSupplies then
        amount = typeCfg.maxSupplies - (data.supplies or 0)
        newSupplies = (data.supplies or 0) + amount
    end

    if amount <= 0 then return false end

    local price = amount * typeCfg.supplyUnitPrice

    local xPlayer
    if Config.Framework == 'esx' and ESX then
        xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        if xPlayer.getAccount('bank').money < price then
            return false
        end
        xPlayer.removeAccountMoney('bank', price)
    end

    data.supplies = newSupplies
    saveBusiness(businessId)

    local updated = buildBusinessData(source, businessId)

    discordLog('Supplies Purchased', ('%s bought %d supplies for %s (%s)')
        :format(data.owner_name or 'Unknown', amount, loc.label, businessId))

    return true, updated
end)

lib.callback.register('lv_laitonyritys:getBusinessList', function(source)
    local src = source
    local identifier = select(1, getIdentifier(src))
    if not identifier then return {} end

    local list = {}

    for businessId, loc in pairs(Config.Locations) do
        local data = Businesses[businessId]
        local owned = data and data.owner_identifier ~= nil
        local isOwner = owned and data.owner_identifier == identifier or false
        local ownerName = owned and (data.owner_name or 'Unknown') or nil
        local typeCfg = Config.BusinessTypes[loc.type]

        list[#list+1] = {
            businessId = businessId,
            label      = loc.label,
            type       = loc.type,
            typeLabel  = typeCfg and typeCfg.label or loc.type,
            owned      = owned,
            isOwner    = isOwner,
            ownerName  = ownerName
        }
    end

    return list
end)

lib.callback.register('lv_laitonyritys:isBusinessOwner', function(source, businessId)
    local identifier = select(1, getIdentifier(source))
    if not identifier then return false end

    local data = Businesses[businessId]
    if not data then return false end

    return data.owner_identifier == identifier
end)

---------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:upgrade', function(source, businessId, upgradeType)
    local src = source
    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return false end

    local data = Businesses[businessId]
    if not data then return false end

    if not hasPermForAction(identifier, businessId, 'upgrade') then
        return false
    end

    local currentLevel
    local prices = Config.UpgradePrices[upgradeType]
    if not prices then return false end

    if upgradeType == 'equipment' then
        currentLevel = data.equipment_level or 0
    elseif upgradeType == 'employees' then
        currentLevel = data.employees_level or 0
    elseif upgradeType == 'security' then
        currentLevel = data.security_level or 0
    else
        return false
    end

    if currentLevel >= #prices then
        return false
    end

    local nextPrice = prices[currentLevel + 1]

    local xPlayer
    if Config.Framework == 'esx' and ESX then
        xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        if xPlayer.getAccount('bank').money < nextPrice then
            return false
        end
        xPlayer.removeAccountMoney('bank', nextPrice)
    end

    if upgradeType == 'equipment' then
        data.equipment_level = currentLevel + 1
    elseif upgradeType == 'employees' then
        data.employees_level = currentLevel + 1
    elseif upgradeType == 'security' then
        data.security_level = currentLevel + 1
    end

    saveBusiness(businessId)

    local updated = buildBusinessData(source, businessId)

    discordLog('Upgrade Purchased', ('%s upgraded %s (%s) %s to level %d for $%d')
        :format(GetPlayerName(src), loc.label, businessId, upgradeType, currentLevel + 1, nextPrice))

    return true, updated
end)

---------------------------------------------------------------------
-- Ownership transfer & associates / permissions
---------------------------------------------------------------------

lib.callback.register('lv_laitonyritys:transferBusiness', function(source, businessId, targetId)
    local src = source
    local identifier, name = getIdentifier(src)
    if not identifier then return false end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= identifier then return false end

    local target = tonumber(targetId)
    if not target or not GetPlayerName(target) then return false end

    local tIdentifier, tName = getIdentifier(target)
    if not tIdentifier then return false end

    if countPlayerBusinesses(tIdentifier) >= Config.MaxBusinessesPerPlayer then
        return false
    end

    data.owner_identifier = tIdentifier
    data.owner_name = tName
    saveBusiness(businessId)

    local updated = buildBusinessData(source, businessId)

    discordLog('Business Transferred', ('%s transferred %s to %s.')
        :format(name, businessId, tName))

    TriggerClientEvent('chat:addMessage', target, {
        args = { '^2Business', ('You are now the owner of business %s.'):format(businessId) }
    })

    return true, updated
end)

lib.callback.register('lv_laitonyritys:addAssociate', function(source, businessId, input)
    local src = source
    local ownerIdentifier = select(1, getIdentifier(src))
    if not ownerIdentifier then return false end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= ownerIdentifier then
        return false
    end

    if not input or input == '' then
        return false
    end

    local targetIdentifier, targetName
    local maybeId = tonumber(input)

    if maybeId and GetPlayerName(maybeId) then
        targetIdentifier, targetName = getIdentifier(maybeId)
        if not targetIdentifier then
            return false
        end
    else
        targetIdentifier = tostring(input)
        targetName       = tostring(input)
    end

    if targetIdentifier == ownerIdentifier then
        return false
    end

    addAccess(businessId, targetIdentifier, targetName)

    local updated = buildBusinessData(source, businessId)

    return true, updated
end)

lib.callback.register('lv_laitonyritys:setPermissions', function(source, businessId, identifier, perms)
    local src = source
    local ownerIdentifier = select(1, getIdentifier(src))
    if not ownerIdentifier then return false end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= ownerIdentifier then
        return false
    end

    if not identifier or identifier == '' or not perms then
        return false
    end

    MySQL.update.await([[
        UPDATE lv_illegal_business_access
        SET
            can_stash   = ?,
            can_sell    = ?,
            can_buy     = ?,
            can_steal   = ?,
            can_upgrade = ?
        WHERE business_id = ? AND identifier = ?
    ]], {
        perms.can_stash and 1 or 0,
        perms.can_sell and 1 or 0,
        perms.can_buy and 1 or 0,
        perms.can_steal and 1 or 0,
        perms.can_upgrade and 1 or 0,
        businessId,
        identifier
    })

    local updated = buildBusinessData(source, businessId)
    return true, updated
end)

lib.callback.register('lv_laitonyritys:removeAssociate', function(source, businessId, identifier)
    local src = source
    local ownerIdentifier = select(1, getIdentifier(src))
    if not ownerIdentifier then return false end

    local data = Businesses[businessId]
    if not data or data.owner_identifier ~= ownerIdentifier then
        return false
    end

    if not identifier or identifier == '' then
        return false
    end

    removeAccess(businessId, identifier)

    local updated = buildBusinessData(source, businessId)

    return true, updated
end)
