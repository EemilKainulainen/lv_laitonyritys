-- server/core.lua

ESX = exports['es_extended']:getSharedObject()

-- Global state tables so all server scripts see the same data
Businesses           = Businesses           or {}
ResupplyMissions     = ResupplyMissions     or {} -- token -> { src, businessId, missionType }
SellMissions         = SellMissions         or {} -- token -> { src, businessId, missionType }
ActiveSetups         = ActiveSetups         or {} -- [src] = { businessId = ..., truckNetId = ... }

PlayerOriginalBuckets = PlayerOriginalBuckets or {}

BusinessBuckets      = BusinessBuckets      or {} -- [businessId] = routingBucket
PlayersInBusiness    = PlayersInBusiness    or {} -- [src] = businessId
BusinessBucketSeed   = BusinessBucketSeed   or 60000

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

function getIdentifier(src)
    if Config.Framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        return xPlayer.identifier, xPlayer.getName()
    else
        local license
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            if id:sub(1, 8) == 'license:' then
                license = id
                break
            end
        end
        return license or ('unknown:' .. tostring(src)), GetPlayerName(src) or 'Unknown'
    end
end

function toIntBool(v)
    if type(v) == 'boolean' then
        return v and 1 or 0
    end
    return tonumber(v) or 0
end

function getBusinessTypeCfg(businessId)
    local loc = Config.Locations[businessId]
    if not loc then return nil end
    local typeCfg = Config.BusinessTypes[loc.type]
    if not typeCfg then return nil end
    return loc, typeCfg
end

-- Returns the *current* price per product unit for a business,
-- based on its equipment level.
function getEffectiveProductPrice(businessId)
    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return 0 end

    local data = Businesses[businessId]
    local equipLevel = data and data.equipment_level or 0

    local mult = 1.0 + equipLevel * (Config.Production.EquipmentBonusPerLevel or 0.25)
    local basePrice = typeCfg.productSellPrice or 0
    local effective = math.floor(basePrice * mult)

    return effective
end

function ensureBusinessDefaults(businessId)
    local loc = Config.Locations and Config.Locations[businessId]
    if not loc then return end

    local data = Businesses[businessId] or {}

    data.business_id      = businessId
    data.owner_identifier = data.owner_identifier or nil
    data.owner_name       = data.owner_name or nil
    data.supplies         = tonumber(data.supplies) or 0
    data.product          = tonumber(data.product) or 0
    data.equipment_level  = tonumber(data.equipment_level) or 0
    data.employees_level  = tonumber(data.employees_level) or 0
    data.security_level   = tonumber(data.security_level) or 0

    data.is_shut_down     = toIntBool(data.is_shut_down)
    data.has_seen_intro   = toIntBool(data.has_seen_intro)
    data.setup_completed  = toIntBool(data.setup_completed)

    Businesses[businessId] = data
end

function loadBusinesses()
    Businesses = {}

    local rows = MySQL.query.await([[
        SELECT
            business_id,
            owner_identifier,
            owner_name,
            supplies,
            product,
            equipment_level,
            employees_level,
            security_level,
            is_shut_down,
            setup_completed,
            has_seen_intro
        FROM lv_illegal_businesses
    ]])

    for _, row in ipairs(rows) do
        row.supplies        = tonumber(row.supplies) or 0
        row.product         = tonumber(row.product) or 0
        row.equipment_level = tonumber(row.equipment_level) or 0
        row.employees_level = tonumber(row.employees_level) or 0
        row.security_level  = tonumber(row.security_level) or 0

        row.is_shut_down    = toIntBool(row.is_shut_down)
        row.has_seen_intro  = toIntBool(row.has_seen_intro)
        row.setup_completed = toIntBool(row.setup_completed)

        Businesses[row.business_id] = row
    end

    if Config.Locations then
        for id, _ in pairs(Config.Locations) do
            ensureBusinessDefaults(id)
        end
    end
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    loadBusinesses()
end)

function saveBusiness(businessId)
    local data = Businesses[businessId]
    if not data then return end

    if data.owner_identifier then
        MySQL.insert.await([[
            INSERT INTO lv_illegal_businesses
                (business_id, owner_identifier, owner_name,
                 supplies, product,
                 equipment_level, employees_level, security_level,
                 is_shut_down, setup_completed, has_seen_intro)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                owner_identifier = VALUES(owner_identifier),
                owner_name       = VALUES(owner_name),
                supplies         = VALUES(supplies),
                product          = VALUES(product),
                equipment_level  = VALUES(equipment_level),
                employees_level  = VALUES(employees_level),
                security_level   = VALUES(security_level),
                is_shut_down     = VALUES(is_shut_down),
                setup_completed  = VALUES(setup_completed),
                has_seen_intro   = VALUES(has_seen_intro)
        ]], {
            businessId,
            data.owner_identifier,
            data.owner_name or '',
            data.supplies or 0,
            data.product or 0,
            data.equipment_level or 0,
            data.employees_level or 0,
            data.security_level or 0,
            data.is_shut_down or 0,
            data.setup_completed or 0,
            data.has_seen_intro or 0
        })
    else
        MySQL.update.await('DELETE FROM lv_illegal_businesses WHERE business_id = ?', { businessId })
    end
end

function loadAccess(businessId)
    local access = MySQL.query.await([[
        SELECT identifier, name,
               can_stash, can_sell, can_buy, can_steal, can_upgrade
        FROM lv_illegal_business_access
        WHERE business_id = ?
    ]], { businessId })

    local result = {}

    local function flag(v)
        if v == nil then return true end
        return toIntBool(v) == 1
    end

    for _, row in ipairs(access or {}) do
        result[row.identifier] = {
            name        = row.name,
            can_stash   = flag(row.can_stash),
            can_sell    = flag(row.can_sell),
            can_buy     = flag(row.can_buy),
            can_steal   = flag(row.can_steal),
            can_upgrade = flag(row.can_upgrade),
        }
    end
    return result
end

function addAccess(businessId, identifier, name)
    MySQL.insert.await([[
        INSERT INTO lv_illegal_business_access
            (business_id, identifier, name,
             can_stash, can_sell, can_buy, can_steal, can_upgrade)
        VALUES (?, ?, ?, 1, 1, 1, 1, 1)
        ON DUPLICATE KEY UPDATE
            name = VALUES(name)
    ]], { businessId, identifier, name })
end

function removeAccess(businessId, identifier)
    MySQL.update.await('DELETE FROM lv_illegal_business_access WHERE business_id = ? AND identifier = ?', { businessId, identifier })
end

function countPlayerBusinesses(identifier)
    local result = MySQL.scalar.await('SELECT COUNT(*) FROM lv_illegal_businesses WHERE owner_identifier = ?', { identifier })
    return result or 0
end

function canAccessBusiness(src, businessId)
    local identifier = select(1, getIdentifier(src))
    if not identifier then return false end
    local data = Businesses[businessId]
    if not data then return false end
    if data.owner_identifier == identifier then return true end

    local access = loadAccess(businessId)
    return access[identifier] ~= nil
end

function hasPermForAction(identifier, businessId, permKey)
    if not identifier or not businessId then return false end

    local data = Businesses[businessId]
    if not data or not data.owner_identifier then
        return false
    end

    if data.owner_identifier == identifier then
        return true
    end

    local accessList = loadAccess(businessId)
    local entry = accessList[identifier]
    if not entry then return false end

    if permKey == 'stash'   then return entry.can_stash   end
    if permKey == 'sell'    then return entry.can_sell    end
    if permKey == 'buy'     then return entry.can_buy     end
    if permKey == 'steal'   then return entry.can_steal   end
    if permKey == 'upgrade' then return entry.can_upgrade end

    return false
end

---------------------------------------------------------------------
-- Discord / Dispatch
---------------------------------------------------------------------

function discordLog(title, description)
    if not Config.Discord.Enabled or not Config.Discord.Webhook or Config.Discord.Webhook == '' then return end

    local embed = {
        {
            title = title,
            description = description,
            color = 15158332,
            footer = { text = 'lv_laitonyritys' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }
    }

    PerformHttpRequest(Config.Discord.Webhook, function() end, 'POST', json.encode({
        username = Config.Discord.Username,
        avatar_url = Config.Discord.Avatar,
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end

function sendRaidDispatch(businessId)
    if not Config.Dispatch.Enabled or not Config.Dispatch.UseTkDispatch then return end
    local loc = Config.Locations[businessId]
    if not loc then return end

    local coords = loc.enterCoords

    local success, err = pcall(function()
        exports.tk_dispatch:addCall({
            title = Config.Dispatch.Title,
            code = Config.Dispatch.Code,
            priority = Config.Dispatch.Priority,
            message = ('Suspicious activity reported at %s'):format(loc.label),
            coords = coords,
            jobs = Config.Dispatch.Jobs,
            blip = {
                sprite = Config.Dispatch.Blip.sprite,
                scale = Config.Dispatch.Blip.scale,
                color = Config.Dispatch.Blip.color,
                radius = Config.Dispatch.Blip.radius
            },
            playSound = true,
            flash = true
        })
    end)

    if not success then
        print('[lv_laitonyritys] tk-dispatch error: ' .. tostring(err))
    end
end

---------------------------------------------------------------------
-- Business data builder for UI
---------------------------------------------------------------------

function buildBusinessData(src, businessId)
    local identifier, name = getIdentifier(src)
    if not identifier then return nil end

    local loc, typeCfg = getBusinessTypeCfg(businessId)
    if not loc or not typeCfg then return nil end

    local data = Businesses[businessId]
    local accessList = loadAccess(businessId)
    local owned = false
    local canAccess = false

    if data and data.owner_identifier then
        owned = true
        canAccess = (data.owner_identifier == identifier) or accessList[identifier] ~= nil
    end

    local function getNextPrice(kind, level)
        local prices = Config.UpgradePrices[kind]
        if not prices then return 0 end
        return prices[(level or 0) + 1] or 0
    end

    local upgradePrices = {
        equipment = getNextPrice('equipment', data and data.equipment_level),
        employees = getNextPrice('employees', data and data.employees_level),
        security  = getNextPrice('security',  data and data.security_level),
    }

    return {
        businessId       = businessId,
        locationLabel    = loc.label,
        typeLabel        = typeCfg.label,
        type             = loc.type,
        owned            = owned,
        ownerName        = data and data.owner_name or nil,
        isOwner          = (data and data.owner_identifier == identifier) or false,
        canAccess        = canAccess,
        maxSupplies      = typeCfg.maxSupplies,
        maxProduct       = typeCfg.maxProduct,
        supplies         = data and data.supplies or 0,
        product          = data and data.product or 0,
        equipmentLevel   = data and data.equipment_level or 0,
        employeesLevel   = data and data.employees_level or 0,
        securityLevel    = data and data.security_level or 0,
        isShutDown       = data and data.is_shut_down == 1 or false,
        associates       = accessList,
        supplyUnitPrice  = typeCfg.supplyUnitPrice,
        productSellPrice = getEffectiveProductPrice(businessId),

        setup_completed  = data and data.setup_completed or 0,
        has_seen_intro   = data and data.has_seen_intro or 0,

        upgradePrices    = upgradePrices,

        image            = loc.image,
        area             = loc.area,
    }
end
