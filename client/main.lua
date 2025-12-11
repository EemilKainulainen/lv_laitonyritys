-- client/main.lua

ESX = exports['es_extended']:getSharedObject()

local currentBusinessId = nil
local currentBusinessData = nil

local currentBusinessIdInside = nil
local currentSetup = nil -- { businessId, stage, truck, truckNetId, delivery, blip }

local bikerMethLab = nil
local bikerWeedFarm = nil
local bikerCocaine = nil
local bikerCounterfeit = nil
local bikerDocumentForgery = nil

-- mission tokens & status
local ActiveResupplies = {}
local ActiveSales = {}

local SECURITY_PED_MODEL   = `mp_g_m_pros_01`
local REL_GROUP_SECURITY   = nil
local SecurityPeds         = {}
local ActiveRaidStates     = {}
local RaidEntryUnlocked    = {}
local currentRaidOfficer   = false

local function angleDiff(a, b)
    local d = (a - b) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return math.abs(d)
end

local function resetBusinessUiState()
    currentBusinessId = nil
    currentBusinessData = nil
end

local function closeAllUi()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    resetBusinessUiState()
end

local workerPeds = {}

local function spawnMethWorkers(level)
    local pedModels = {
        `mp_f_meth_01`,
        `mp_f_meth_01`,
        `mp_f_meth_01`
    }

    local pedPositions = {
        vec4(1014.079102, -3194.874756, -40.0, 0.000000),
        vec4(1003.912109, -3200.004395, -40.0, 184.251968),
        vec4(1011.494507, -3200.874756, -40.0, 0.000000),
    }

    -- prevent duplicates
    for _, ped in ipairs(workerPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    workerPeds = {}

    if not level or level <= 0 then return end

    for i = 1, math.min(level, #pedPositions) do
        local model = pedModels[i] or pedModels[1]
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end

        local pos = pedPositions[i]
        local ped = CreatePed(4, model, pos.x, pos.y, pos.z, pos.w, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
        table.insert(workerPeds, ped)
    end
end

local function removeMethWorkers()
    for _, ped in ipairs(workerPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    workerPeds = {}
end

local function clearSecurityForBusiness(businessId)
    local list = SecurityPeds[businessId]
    if not list then return end

    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end

    SecurityPeds[businessId] = nil
end

local function getCameraCoordsForBusiness(businessId)
    local loc = Config.Locations[businessId]
    if not loc then return nil end

    if loc.cameraCoords then
        return loc.cameraCoords
    end

    local ipl = Config.IPLSetup and Config.IPLSetup[loc.type]
    if ipl and ipl.cameraCoords then
        return ipl.cameraCoords
    end

    return nil
end

local function getConfiscateCoordsForBusiness(businessId)
    local loc = Config.Locations[businessId]
    if not loc then return nil end

    local ipl = Config.IPLSetup and Config.IPLSetup[loc.type]
    if ipl and ipl.confiscateCoords then
        return ipl.confiscateCoords
    end

    return nil
end

local function getCurrentUnixTime()
    local cloud = GetCloudTimeAsInt()
    if cloud and cloud > 0 then
        return cloud
    end

    return math.floor(GetGameTimer() / 1000)
end

local function getActiveRaidState(businessId)
    local raid = ActiveRaidStates[businessId]
    if not raid then return nil end

    if raid.expiresAt and raid.expiresAt <= getCurrentUnixTime() then
        ActiveRaidStates[businessId] = nil
        RaidEntryUnlocked[businessId] = nil
        return nil
    end

    return raid
end

local function areSecurityNeutralized(businessId)
    local guards = SecurityPeds[businessId]
    if not guards or #guards == 0 then return true end

    for _, ped in ipairs(guards) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) and not IsPedFatallyInjured(ped) then
            return false
        end
    end

    return true
end

local function spawnSecurityForBusiness(businessId, data)
    clearSecurityForBusiness(businessId)

    if not data then return end

    local secLevel = data.securityLevel or data.security_level or 0
    if secLevel <= 0 then return end

    local loc = Config.Locations[businessId]
    if not loc then return end

    local ipl = Config.IPLSetup and Config.IPLSetup[loc.type]
    if not ipl or not ipl.securityGuards or #ipl.securityGuards == 0 then return end

    local toSpawn = math.min(secLevel, #ipl.securityGuards)
    local spawned = {}

    RequestModel(SECURITY_PED_MODEL)
    while not HasModelLoaded(SECURITY_PED_MODEL) do Wait(0) end

    for i = 1, toSpawn do
        local cfg = ipl.securityGuards[i]
        if cfg and cfg.coords then
            local c = cfg.coords
            local ped = CreatePed(
                4,
                SECURITY_PED_MODEL,
                c.x, c.y, c.z,
                c.w or 0.0,
                false, false
            )

            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)

            if REL_GROUP_SECURITY then
                SetPedRelationshipGroupHash(ped, REL_GROUP_SECURITY)
            end

            -- basic weapon & stats scaled a bit with level
            GiveWeaponToPed(ped, `WEAPON_PISTOL`, 120, false, true)
            SetPedArmour(ped, 25 + (secLevel * 15))
            SetPedAccuracy(ped, 30 + (secLevel * 10))

            if cfg.scenario then
                TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
            else
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
            end

            table.insert(spawned, ped)
        end
    end

    SecurityPeds[businessId] = spawned
end

CreateThread(function()
    -- bob74_ipl is in dependencies, so this is safe
    if GetResourceState('bob74_ipl') == 'started' then
        bikerMethLab         = exports['bob74_ipl']:GetBikerMethLabObject()
        bikerWeedFarm        = exports['bob74_ipl']:GetBikerWeedFarmObject()
        bikerCocaine         = exports['bob74_ipl']:GetBikerCocaineObject()
        bikerCounterfeit     = exports['bob74_ipl']:GetBikerCounterfeitObject()
        bikerDocumentForgery = exports['bob74_ipl']:GetBikerDocumentForgeryObject()

        -- Meth lab base state
        if bikerMethLab and bikerMethLab.Ipl and bikerMethLab.Ipl.Interior then
            bikerMethLab.Ipl.Interior.Load()
            bikerMethLab.Style.Set(bikerMethLab.Style.empty)
            bikerMethLab.Security.Set(bikerMethLab.Security.none)
            bikerMethLab.Details.Enable(bikerMethLab.Details.production, false)
        end

        -- Weed farm base state
        if bikerWeedFarm and bikerWeedFarm.Ipl and bikerWeedFarm.Ipl.Interior then
            bikerWeedFarm.Ipl.Interior.Load()
        end

        -- Cocaine lockup base state
        if bikerCocaine and bikerCocaine.Ipl and bikerCocaine.Ipl.Interior then
            bikerCocaine.Ipl.Interior.Load()
        end

        -- Counterfeit factory base state
        if bikerCounterfeit and bikerCounterfeit.Ipl and bikerCounterfeit.Ipl.Interior then
            bikerCounterfeit.Ipl.Interior.Load()
        end

        -- Document forgery base state
        if bikerDocumentForgery and bikerDocumentForgery.Ipl and bikerDocumentForgery.Ipl.Interior then
            bikerDocumentForgery.Ipl.Interior.Load()
        end
    end
end)

CreateThread(function()
    REL_GROUP_SECURITY = GetHashKey('SECURITY_GUARD')
    AddRelationshipGroup('SECURITY_GUARD')

    -- Security hates cops
    local copGroup = GetHashKey('COP')
    SetRelationshipBetweenGroups(5, REL_GROUP_SECURITY, copGroup)
    SetRelationshipBetweenGroups(5, copGroup, REL_GROUP_SECURITY)
end)


-- Target / interaction, one laptop per location
local function setupTargetForLocation(id, data)
    if not data.laptopCoords then
        -- no laptop defined for this location yet (e.g. coke_1, weed_1 while we're still WIP)
        return
    end
    
    if Config.InteractionType == 'target' and Config.UseOxTarget then
        exports.ox_target:addBoxZone({
            coords = vec3(data.laptopCoords.x, data.laptopCoords.y, data.laptopCoords.z),
            size = vec3(1.0, 1.0, 1.0),
            rotation = data.laptopCoords.w or 0.0,
            debug = false,
            options = {
                {
                    name = 'lv_laitonyritys_' .. id,
                    label = ('Open %s Management'):format(data.label),
                    icon = 'fa-solid fa-laptop',
                    onSelect = function()
                        TriggerEvent('lv_laitonyritys:client:openBusinessMenu', id)
                    end
                }
            }
        })
    else
        -- 3D text/text ui: simple proximity check loop
        CreateThread(function()
            local loc = vec3(data.laptopCoords.x, data.laptopCoords.y, data.laptopCoords.z)
            while true do
                local sleep = 1000
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)
                local dist = #(pos - loc)
                if dist < 1.5 then
                    sleep = 0
                    if Config.InteractionType == 'textui' then
                        lib.showTextUI(('[E] %s'):format(data.label))
                    else
                        SetTextComponentFormat('STRING')
                        AddTextComponentString('~INPUT_CONTEXT~ '..data.label)
                        DisplayHelpTextFromStringLabel(0, false, true, -1)
                    end
                    if IsControlJustReleased(0, 38) then -- E
                        TriggerEvent('lv_laitonyritys:client:openBusinessMenu', id)
                    end
                else
                    if Config.InteractionType == 'textui' then
                        lib.hideTextUI()
                    end
                end

                Wait(sleep)
            end
        end)
    end
end

local function applyIPLDefaults(id, data)
    if not Config.IPLSetup then return data end
    local ipl = Config.IPLSetup[data.type]
    if not ipl then return data end

    -- Only fill if not already set on the location:
    data.interiorCoords = data.interiorCoords or ipl.interiorCoords
    data.exitCoords     = data.exitCoords     or ipl.exitCoords or ipl.interiorCoords
    data.laptopCoords   = data.laptopCoords   or ipl.laptopCoords
    data.laptopModel    = data.laptopModel    or ipl.laptopModel or `prop_laptop_lester2`
    data.cameraCoords   = data.cameraCoords   or ipl.cameraCoords
    data.stashCoords    = data.stashCoords    or ipl.stashCoords
    data.interiorConfig = data.interiorConfig or ipl.interiorConfig
    data.cameraAccessCoords = data.cameraAccessCoords or ipl.cameraAccessCoords

    return data
end

local function showFirstTimeBusinessAlert(businessId)
    lib.callback('lv_laitonyritys:shouldShowIntro', false, function(shouldShow)
        if not shouldShow then return end

        lib.alertDialog({
            header = 'Business',
            content = 'Welcome to your new business, go to the laptop to manage your business.',
            centered = true,
            cancel = false,
            size = 'sm',
            labels = {
                confirm = 'ACKNOWLEDGE'
            }
        })
    end, businessId)
end

local function playDoorTransition(targetCoords, faceHeading)
    local ped = PlayerPedId()
    local dict = 'anim@apt_trans@hinge_l'
    local anim = 'ext_player'

    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end

    -- Face the door / front before anim
    if faceHeading ~= nil then
        SetEntityHeading(ped, faceHeading + 0.0)
    end

    -- Play door animation
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 0, 0.0, false, false, false)

    -- Let most of the anim run
    Wait(1800)

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do
        Wait(10)
    end

    ClearPedTasksImmediately(ped)

    -- Teleport to target (inside/outside)
    SetEntityCoords(ped, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false, true)
    if targetCoords.w then
        SetEntityHeading(ped, targetCoords.w + 0.0)
    end

    Wait(250)
    DoScreenFadeIn(400)
end

local function applyInteriorSetsForBusiness(businessId, data)
    local loc = Config.Locations[businessId]
    if not loc then return end

    ----------------------------------------------------------------
    -- BIKER METH LAB (bob74_ipl)
    ----------------------------------------------------------------
    if businessId == 'meth_1' and bikerMethLab then
        bikerMethLab.Ipl.Interior.Load()

        local eqLevel = data.equipmentLevel or data.equipment_level or 0
        if data.setup_completed == 1 then
            if eqLevel >= 2 then
                bikerMethLab.Style.Set(bikerMethLab.Style.upgrade, false)
            else
                bikerMethLab.Style.Set(bikerMethLab.Style.basic, false)
            end
        else
            bikerMethLab.Style.Set(bikerMethLab.Style.empty, false)
        end

        local secLevel = data.securityLevel or data.security_level or 0
        if data.setup_completed == 1 and secLevel > 0 then
            bikerMethLab.Security.Set(bikerMethLab.Security.upgrade, false)
        else
            bikerMethLab.Security.Set(bikerMethLab.Security.none, false)
        end

        local hasProduct = (data.product or 0) > 0
        bikerMethLab.Details.Enable(bikerMethLab.Details.production, hasProduct, true)

        return
    end

    ----------------------------------------------------------------
    -- BIKER WEED FARM (bob74_ipl)
    ----------------------------------------------------------------
    if loc.type == 'weed' and bikerWeedFarm then
        bikerWeedFarm.Ipl.Interior.Load()

        if bikerWeedFarm.Style and bikerWeedFarm.Style.Clear then
            bikerWeedFarm.Style.Clear(false)
        end
        if bikerWeedFarm.Security and bikerWeedFarm.Security.Clear then
            bikerWeedFarm.Security.Clear(false)
        end

        local plants = {
            bikerWeedFarm.Plant1,
            bikerWeedFarm.Plant2,
            bikerWeedFarm.Plant3,
            bikerWeedFarm.Plant4,
            bikerWeedFarm.Plant5,
            bikerWeedFarm.Plant6,
            bikerWeedFarm.Plant7,
            bikerWeedFarm.Plant8,
            bikerWeedFarm.Plant9
        }

        for _, plant in ipairs(plants) do
            if plant and plant.Clear then
                plant.Clear(false)
            end
        end

        if bikerWeedFarm.Details and bikerWeedFarm.Details.Enable then
            bikerWeedFarm.Details.Enable({
                bikerWeedFarm.Details.production,
                bikerWeedFarm.Details.fans,
                bikerWeedFarm.Details.drying,
                bikerWeedFarm.Details.chairs
            }, false, false)
        end

        if (data.setup_completed or 0) ~= 1 then
            RefreshInterior(bikerWeedFarm.interiorId)
            return
        end

        local eqLevel   = data.equipmentLevel or data.equipment_level or 0
        local secLevel  = data.securityLevel or data.security_level or 0
        local product   = data.product or 0
        local maxProd   = data.maxProduct or 0

        if bikerWeedFarm.Style and bikerWeedFarm.Style.Set then
            local style = (eqLevel >= 2) and bikerWeedFarm.Style.upgrade or bikerWeedFarm.Style.basic
            bikerWeedFarm.Style.Set(style, false)
        end

        if bikerWeedFarm.Security and bikerWeedFarm.Security.Set then
            local secStyle = (secLevel >= 1) and bikerWeedFarm.Security.upgrade or bikerWeedFarm.Security.basic
            bikerWeedFarm.Security.Set(secStyle, false)
        end

        local stageKey = 'small'
        if maxProd > 0 then
            local ratio = product / maxProd
            if     ratio >= 0.66 then stageKey = 'full'
            elseif ratio >= 0.33 then stageKey = 'medium'
            else stageKey = 'small' end
        end

        local useUpgradeLight = (eqLevel >= 2)

        local function setPlant(plant)
            if not plant or not plant.Stage or not plant.Light or not plant.Set then return end
            local stageVal = plant.Stage[stageKey] or plant.Stage.small
            local lightVal = useUpgradeLight and plant.Light.upgrade or plant.Light.basic
            plant.Set(stageVal, lightVal, false)
        end

        for _, plant in ipairs(plants) do
            setPlant(plant)
        end

        if bikerWeedFarm.Details and bikerWeedFarm.Details.Enable then
            bikerWeedFarm.Details.Enable(bikerWeedFarm.Details.fans, true, false)
            bikerWeedFarm.Details.Enable(bikerWeedFarm.Details.chairs, true, false)

            local hasProduct = product > 0
            bikerWeedFarm.Details.Enable(bikerWeedFarm.Details.production, hasProduct, false)
            bikerWeedFarm.Details.Enable(bikerWeedFarm.Details.drying, hasProduct, true)
        end

        RefreshInterior(bikerWeedFarm.interiorId)
        return
    end

    ----------------------------------------------------------------
    -- BIKER COCAINE LOCKUP (bob74_ipl)
    ----------------------------------------------------------------
    if loc.type == 'coke' and bikerCocaine then
        bikerCocaine.Ipl.Interior.Load()

        if bikerCocaine.Style and bikerCocaine.Style.Clear then
            bikerCocaine.Style.Clear(false)
        end
        if bikerCocaine.Security and bikerCocaine.Security.Clear then
            bikerCocaine.Security.Clear(false)
        end

        if bikerCocaine.Details and bikerCocaine.Details.Enable then
            bikerCocaine.Details.Enable({
                bikerCocaine.Details.cokeBasic1,
                bikerCocaine.Details.cokeBasic2,
                bikerCocaine.Details.cokeBasic3,
                bikerCocaine.Details.cokeUpgrade1,
                bikerCocaine.Details.cokeUpgrade2
            }, false, false)
        end

        if (data.setup_completed or 0) ~= 1 then
            RefreshInterior(bikerCocaine.interiorId)
            return
        end

        local eqLevel  = data.equipmentLevel or data.equipment_level or 0
        local secLevel = data.securityLevel or data.security_level or 0
        local product  = data.product or 0

        if bikerCocaine.Style and bikerCocaine.Style.Set then
            local style = (eqLevel >= 2) and bikerCocaine.Style.upgrade or bikerCocaine.Style.basic
            bikerCocaine.Style.Set(style, false)
        end

        if bikerCocaine.Security and bikerCocaine.Security.Set then
            local secStyle
            if secLevel >= 2 then
                secStyle = bikerCocaine.Security.upgrade
            elseif secLevel >= 1 then
                secStyle = bikerCocaine.Security.basic
            else
                secStyle = bikerCocaine.Security.none
            end
            bikerCocaine.Security.Set(secStyle, false)
        end

        local hasProduct = product > 0
        if hasProduct and bikerCocaine.Details and bikerCocaine.Details.Enable then
            if eqLevel >= 2 then
                bikerCocaine.Details.Enable({
                    bikerCocaine.Details.cokeUpgrade1,
                    bikerCocaine.Details.cokeUpgrade2
                }, true, true)
            else
                bikerCocaine.Details.Enable({
                    bikerCocaine.Details.cokeBasic1,
                    bikerCocaine.Details.cokeBasic2,
                    bikerCocaine.Details.cokeBasic3
                }, true, true)
            end
        end

        RefreshInterior(bikerCocaine.interiorId)
        return
    end

    ----------------------------------------------------------------
    -- NEW: BIKER COUNTERFEIT FACTORY (bob74_ipl)
    ----------------------------------------------------------------
    if loc.type == 'counterfeit' and bikerCounterfeit then
        bikerCounterfeit.Ipl.Interior.Load()

        -- Clear printer, security, dryers
        if bikerCounterfeit.Printer and bikerCounterfeit.Printer.Clear then
            bikerCounterfeit.Printer.Clear(false)
        end
        if bikerCounterfeit.Security and bikerCounterfeit.Security.Clear then
            bikerCounterfeit.Security.Clear(false)
        end

        local dryers = {
            bikerCounterfeit.Dryer1,
            bikerCounterfeit.Dryer2,
            bikerCounterfeit.Dryer3,
            bikerCounterfeit.Dryer4
        }
        for _, dryer in ipairs(dryers) do
            if dryer and dryer.Clear then
                dryer.Clear(false)
            end
        end

        -- Clear details (cash piles, chairs, cutter, furnitures)
        if bikerCounterfeit.Details and bikerCounterfeit.Details.Enable then
            bikerCounterfeit.Details.Enable({
                bikerCounterfeit.Details.chairs,
                bikerCounterfeit.Details.cutter,
                bikerCounterfeit.Details.furnitures,
                bikerCounterfeit.Details.Cash10.A,
                bikerCounterfeit.Details.Cash10.B,
                bikerCounterfeit.Details.Cash10.C,
                bikerCounterfeit.Details.Cash10.D,
                bikerCounterfeit.Details.Cash20.A,
                bikerCounterfeit.Details.Cash20.B,
                bikerCounterfeit.Details.Cash20.C,
                bikerCounterfeit.Details.Cash20.D,
                bikerCounterfeit.Details.Cash100.A,
                bikerCounterfeit.Details.Cash100.B,
                bikerCounterfeit.Details.Cash100.C,
                bikerCounterfeit.Details.Cash100.D
            }, false, false)
        end

        -- Not set up yet? keep it pretty empty
        if (data.setup_completed or 0) ~= 1 then
            RefreshInterior(bikerCounterfeit.interiorId)
            return
        end

        local eqLevel  = data.equipmentLevel or data.equipment_level or 0
        local secLevel = data.securityLevel or data.security_level or 0
        local product  = data.product or 0
        local maxProd  = data.maxProduct or 0
        local ratio    = (maxProd > 0) and (product / maxProd) or 0.0

        -- Printer: equipment controls basic/upgrade, product controls prod/no_prod
        if bikerCounterfeit.Printer and bikerCounterfeit.Printer.Set then
            local key
            if eqLevel >= 2 then
                key = (product > 0) and 'upgradeProd' or 'upgrade'
            elseif eqLevel >= 1 then
                key = (product > 0) and 'basicProd' or 'basic'
            else
                -- level 0 → basic machine, only prints when there is product
                key = (product > 0) and 'basicProd' or 'basic'
            end

            local printerIpl = bikerCounterfeit.Printer[key] or bikerCounterfeit.Printer.basic
            bikerCounterfeit.Printer.Set(printerIpl, false)
        end

        -- Security: low / high, or none at level 0
        if bikerCounterfeit.Security and bikerCounterfeit.Security.Set then
            if secLevel >= 2 then
                bikerCounterfeit.Security.Set(bikerCounterfeit.Security.upgrade, false)
            elseif secLevel >= 1 then
                bikerCounterfeit.Security.Set(bikerCounterfeit.Security.basic, false)
            else
                bikerCounterfeit.Security.Clear(false)
            end
        end

        -- Dryers: reflect production intensity
        local function setDryer(dryerObj, stateKey)
            if not dryerObj or not dryerObj.Set then return end
            local ipl = dryerObj[stateKey] or dryerObj.off or dryerObj.none
            dryerObj.Set(ipl, false)
        end

        if product <= 0 then
            -- everything idle
            for _, dryer in ipairs(dryers) do
                setDryer(dryer, 'off')
            end
        elseif ratio < 0.34 then
            -- small run → one dryer working
            setDryer(bikerCounterfeit.Dryer1, 'on')
            setDryer(bikerCounterfeit.Dryer2, 'off')
            setDryer(bikerCounterfeit.Dryer3, 'off')
            setDryer(bikerCounterfeit.Dryer4, 'open')
        elseif ratio < 0.67 then
            -- medium run → 2-3 dryers working
            setDryer(bikerCounterfeit.Dryer1, 'on')
            setDryer(bikerCounterfeit.Dryer2, 'on')
            setDryer(bikerCounterfeit.Dryer3, 'on')
            setDryer(bikerCounterfeit.Dryer4, 'off')
        else
            -- full operation → all blasting
            setDryer(bikerCounterfeit.Dryer1, 'on')
            setDryer(bikerCounterfeit.Dryer2, 'on')
            setDryer(bikerCounterfeit.Dryer3, 'on')
            setDryer(bikerCounterfeit.Dryer4, 'on')
        end

        -- Details: chairs + furnitures always when operational
        if bikerCounterfeit.Details and bikerCounterfeit.Details.Enable then
            bikerCounterfeit.Details.Enable(bikerCounterfeit.Details.chairs, true, false)
            bikerCounterfeit.Details.Enable(bikerCounterfeit.Details.furnitures, true, false)

            -- cutter & cash piles only if there's product
            if product > 0 then
                bikerCounterfeit.Details.Enable(bikerCounterfeit.Details.cutter, true, false)

                local cashGroup
                if ratio < 0.34 then
                    cashGroup = bikerCounterfeit.Details.Cash10
                elseif ratio < 0.67 then
                    cashGroup = bikerCounterfeit.Details.Cash20
                else
                    cashGroup = bikerCounterfeit.Details.Cash100
                end

                if cashGroup then
                    bikerCounterfeit.Details.Enable({
                        cashGroup.A,
                        cashGroup.B,
                        cashGroup.C,
                        cashGroup.D
                    }, true, true)
                end
            end
        end

        RefreshInterior(bikerCounterfeit.interiorId)
        return
    end

    -----------------------------------------------------------------
    -- BIKER DOCUMENT FORGERY (bob74_ipl)
    ----------------------------------------------------------------
    if loc.type == 'forgery' and bikerDocumentForgery then
        bikerDocumentForgery.Ipl.Interior.Load()

        -- Clear style, equipment, security first
        if bikerDocumentForgery.Style and bikerDocumentForgery.Style.Clear then
            bikerDocumentForgery.Style.Clear(false)
        end
        if bikerDocumentForgery.Equipment and bikerDocumentForgery.Equipment.Clear then
            bikerDocumentForgery.Equipment.Clear(false)
        end
        if bikerDocumentForgery.Security and bikerDocumentForgery.Security.Clear then
            bikerDocumentForgery.Security.Clear(false)
        end

        -- Clear all details
        if bikerDocumentForgery.Details and bikerDocumentForgery.Details.Enable then
            local d = bikerDocumentForgery.Details
            bikerDocumentForgery.Details.Enable({
                d.production,
                d.furnitures,
                d.clutter,
                d.Chairs.A,
                d.Chairs.B,
                d.Chairs.C,
                d.Chairs.D,
                d.Chairs.E,
                d.Chairs.F,
                d.Chairs.G
            }, false, false)
        end

        local eqLevel  = data.equipmentLevel or data.equipment_level or 0
        local secLevel = data.securityLevel or data.security_level or 0
        local product  = data.product or 0
        local maxProd  = data.maxProduct or 0
        local ratio    = (maxProd > 0) and (product / maxProd) or 0.0

        -- If not set up yet, keep it very bare
        if (data.setup_completed or 0) ~= 1 then
            -- simple basic shell + chairs so it doesn't look broken
            if bikerDocumentForgery.Style and bikerDocumentForgery.Style.Set then
                bikerDocumentForgery.Style.Set(bikerDocumentForgery.Style.basic, false)
            end

            if bikerDocumentForgery.Details and bikerDocumentForgery.Details.Enable then
                local d = bikerDocumentForgery.Details
                bikerDocumentForgery.Details.Enable({
                    d.Chairs.A,
                    d.Chairs.B,
                    d.Chairs.C,
                    d.Chairs.D,
                    d.Chairs.E,
                    d.Chairs.F,
                    d.Chairs.G
                }, true, true)
            end

            RefreshInterior(bikerDocumentForgery.interiorId)
            return
        end

        -- STYLE: upgrade shell at higher equipment
        if bikerDocumentForgery.Style and bikerDocumentForgery.Style.Set then
            local style = (eqLevel >= 2) and bikerDocumentForgery.Style.upgrade or bikerDocumentForgery.Style.basic
            bikerDocumentForgery.Style.Set(style, false)
        end

        -- EQUIPMENT: none / basic / upgrade
        if bikerDocumentForgery.Equipment and bikerDocumentForgery.Equipment.Set then
            local eqKey
            if eqLevel <= 0 then
                eqKey = 'none'
            elseif eqLevel == 1 then
                eqKey = 'basic'
            else
                eqKey = 'upgrade'
            end

            local eqIpl = bikerDocumentForgery.Equipment[eqKey] or bikerDocumentForgery.Equipment.basic
            bikerDocumentForgery.Equipment.Set(eqIpl, false)
        end

        -- SECURITY: low / high
        if bikerDocumentForgery.Security and bikerDocumentForgery.Security.Set then
            if secLevel >= 2 then
                bikerDocumentForgery.Security.Set(bikerDocumentForgery.Security.upgrade, false)
            elseif secLevel >= 1 then
                bikerDocumentForgery.Security.Set(bikerDocumentForgery.Security.basic, false)
            else
                bikerDocumentForgery.Security.Clear(false)
            end
        end

        -- DETAILS
        if bikerDocumentForgery.Details and bikerDocumentForgery.Details.Enable then
            local d = bikerDocumentForgery.Details

            -- Chairs always when operational
            bikerDocumentForgery.Details.Enable({
                d.Chairs.A,
                d.Chairs.B,
                d.Chairs.C,
                d.Chairs.D,
                d.Chairs.E,
                d.Chairs.F,
                d.Chairs.G
            }, true, false)

            -- Furnitures (printers/shredders) always once setup is complete
            bikerDocumentForgery.Details.Enable(d.furnitures, true, false)

            if product > 0 then
                -- Papers etc. whenever there is product
                bikerDocumentForgery.Details.Enable(d.production, true, false)

                -- Clutter ramps with amount of product
                if ratio >= 0.33 then
                    bikerDocumentForgery.Details.Enable(d.clutter, true, true)
                end
            end
        end

        RefreshInterior(bikerDocumentForgery.interiorId)
        return
    end

    ----------------------------------------------------------------
    -- GENERIC HANDLING FOR OTHER BUSINESSES (entity sets)
    ----------------------------------------------------------------
    if not loc.interiorConfig then return end

    local icfg = loc.interiorConfig
    local coords = icfg.coords
        or (loc.interiorCoords and vec3(loc.interiorCoords.x, loc.interiorCoords.y, loc.interiorCoords.z))

    if not coords then return end

    local interiorId = GetInteriorAtCoords(coords.x, coords.y, coords.z)
    if interiorId == 0 then return end

    local notSetupSets = icfg.notSetupSets or {}
    local setupSets    = icfg.setupSets or {}

    for _, setName in ipairs(notSetupSets) do
        if IsInteriorEntitySetActive(interiorId, setName) then
            DeactivateInteriorEntitySet(interiorId, setName)
        end
    end
    for _, setName in ipairs(setupSets) do
        if IsInteriorEntitySetActive(interiorId, setName) then
            DeactivateInteriorEntitySet(interiorId, setName)
        end
    end

    local activeList = (data.setup_completed == 1) and setupSets or notSetupSets
    for _, setName in ipairs(activeList) do
        ActivateInteriorEntitySet(interiorId, setName)
    end

    RefreshInterior(interiorId)
end

local function refreshFacilityHud(businessId)
    if not businessId then return end

    lib.callback('lv_laitonyritys:getBusinessData', false, function(data)
        if not data then
            SendNUIMessage({ action = 'hideFacilityHud' })
            return
        end

        -- Apply interior sets depending on setup_completed
        applyInteriorSetsForBusiness(businessId, data)
        spawnSecurityForBusiness(businessId, data)

        -- NEW: update production props (meth bags, etc.)
        if UpdateProductionProps then
            UpdateProductionProps(businessId, data)
        end

        SendNUIMessage({
            action = 'showFacilityHud',
            data = data
        })
    end, businessId)
end

local function attemptRaidEntry(businessId)
    local raid = getActiveRaidState(businessId)
    if not raid or not raid.breached then return false end

    local allowed = lib.callback.await('lv_laitonyritys:canEnterRaid', false, businessId)
    if not allowed then
        lib.notify({ title = 'Police Raid', description = 'Raid access unavailable.', type = 'error' })
        return false
    end

    return true
end

local function attemptRaidLockpick(businessId, data)
    local allowed, reason = lib.callback.await('lv_laitonyritys:canPoliceRaid', false, businessId)
    if not allowed then
        lib.notify({
            title = data.label or 'Raid',
            description = reason or 'You cannot raid this lab right now.',
            type = 'error'
        })
        return false
    end

    lib.showTextUI('Lockpicking Door...')

    local ok, success = pcall(function()
        return exports['lockpick']:startLockpick()
    end)

    lib.hideTextUI()

    if not ok or not success then
        lib.notify({
            title = 'Police Raid',
            description = 'Lockpick failed.',
            type = 'error'
        })
        return false
    end

    ActiveRaidStates[businessId] = ActiveRaidStates[businessId] or {}
    ActiveRaidStates[businessId].breached = true
    RaidEntryUnlocked[businessId] = true

    TriggerServerEvent('lv_laitonyritys:server:markRaidBreached', businessId)

    lib.notify({
        title = 'Police Raid',
        description = 'Door unlocked. Enter the lab!',
        type = 'success'
    })

    return true
end

local function applyBusinessUiUpdateFromData(updated)
    if not updated then return end

    currentBusinessData = updated

    -- Update laptop UI
    SendNUIMessage({
        action = 'update',
        data = updated
    })

    -- If player is inside this same facility, update interior + HUD
    if currentBusinessIdInside and currentBusinessIdInside == updated.businessId then
        applyInteriorSetsForBusiness(updated.businessId, updated)

        -- security visuals
        spawnSecurityForBusiness(updated.businessId, updated)

        -- NEW: update production props based on product %
        if UpdateProductionProps then
            UpdateProductionProps(updated.businessId, updated)
        end

        SendNUIMessage({
            action = 'updateFacilityHud',
            data = updated
        })
    end
end

local function setupEntranceForLocation(id, data)
    local entrance = data.enterCoords or data.entranceCoords
    local interior = data.interiorCoords or data.laptopCoords

    if not entrance or not interior then
        return
    end

    local exitCoords = data.exitCoords or interior

    local entranceVec = vec3(entrance.x, entrance.y, entrance.z)
    local exitVec     = vec3(exitCoords.x, exitCoords.y, exitCoords.z)

    CreateThread(function()
        local showing   = false
        local lastLabel = nil

        while true do
            local sleep = 1000
            local ped   = PlayerPedId()
            local pos   = GetEntityCoords(ped)

            local nearEntrance = #(pos - entranceVec) < 1.6
            local nearExit     = #(pos - exitVec) < 1.6

            if nearEntrance then
                sleep = 0
                local raidState = getActiveRaidState(id)
                local label = ('[E] Enter %s'):format(data.label)

                if raidState and not (raidState.breached or RaidEntryUnlocked[id]) then
                    label = '[E] Lockpick Door'
                end

                if not showing or lastLabel ~= label then
                    lib.showTextUI(label)
                    showing   = true
                    lastLabel = label
                end

                if IsControlJustReleased(0, 38) then -- E
                    lib.hideTextUI()
                    showing   = false
                    lastLabel = nil

                    local businessId   = id
                    local businessType = data.type  -- e.g. 'meth'

                    local raid = getActiveRaidState(id)
                    if raid and not (raid.breached or RaidEntryUnlocked[id]) then
                        attemptRaidLockpick(id, data)
                    else
                        -- Check ownership / keys BEFORE entry (unless authorized raid)
                        lib.callback('lv_laitonyritys:getBusinessData', false, function(bizData)
                            if not bizData then
                                lib.notify({
                                    title       = data.label or 'Business',
                                    description = 'Failed to load business data.',
                                    type        = 'error'
                                })
                                return
                            end

                            local enteringRaid = false
                            local refreshedRaid = getActiveRaidState(businessId)

                            if refreshedRaid and (refreshedRaid.breached or RaidEntryUnlocked[businessId]) then
                                enteringRaid = attemptRaidEntry(businessId)
                            end

                            -- must own OR have keys (associate) unless entering via raid
                            if not enteringRaid and (not bizData.owned or not bizData.canAccess) then
                                lib.notify({
                                    title       = bizData.locationLabel or data.label or 'Business',
                                    description = 'You must own this facility or have keys to enter.',
                                    type        = 'error'
                                })
                                return
                            end

                            -- put player into their private business instance
                            TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', businessId, true)

                            -- door transition
                            local faceHeading = entrance.w or GetEntityHeading(PlayerPedId())
                            playDoorTransition(interior, faceHeading)

                            currentBusinessIdInside = businessId
                            currentRaidOfficer = enteringRaid

                            if not enteringRaid then
                                -- spawn employees (only while inside)
                                TriggerEvent('lv_laitonyritys:client:updateEmployeesForBusiness',
                                    businessId,
                                    bizData.type or businessType,      -- 'meth' etc.
                                    bizData.employeesLevel or 0,
                                    true
                                )

                                showFirstTimeBusinessAlert(businessId)
                            end

                            refreshFacilityHud(businessId)
                        end, businessId)
                    end
                end

            elseif nearExit then
                sleep = 0
                local label = '[E] Exit Facility'
                if not showing or lastLabel ~= label then
                    lib.showTextUI(label)
                    showing   = true
                    lastLabel = label
                end

                if IsControlJustReleased(0, 38) then
                    lib.hideTextUI()
                    showing   = false
                    lastLabel = nil

                    local businessId   = id
                    local businessType = data.type

                    -- If we have an active setup mission, we STAY in the same routing bucket
                    -- so the player can still see the truck outside.
                    if not currentSetup then
                        TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', businessId, false)
                    end

                    -- remove employees
                    TriggerEvent('lv_laitonyritys:client:updateEmployeesForBusiness',
                        businessId,
                        businessType,
                        0,
                        false
                    )

                    local faceHeading = exitCoords.w or GetEntityHeading(PlayerPedId())
                    playDoorTransition(entrance, faceHeading)

                    currentBusinessIdInside = nil
                    currentRaidOfficer = false
                    SendNUIMessage({ action = 'hideFacilityHud' })
                    clearSecurityForBusiness(businessId)

                    if ClearProductionProps then
                        ClearProductionProps(businessId)
                    end
                end

            else
                if showing then
                    lib.hideTextUI()
                    showing   = false
                    lastLabel = nil
                end
            end

            Wait(sleep)
        end
    end)
end

local function setupStashForLocation(id, data)
    if not data.stashCoords then return end
    if not Config.UseOxTarget then return end

    local c = data.stashCoords

    exports.ox_target:addBoxZone({
        coords = vec3(c.x, c.y, c.z),
        size = vec3(1.2, 1.2, 1.5),
        rotation = c.w or 0.0,
        debug = false,
        options = {
            {
                name = 'lv_laitonyritys_stash_' .. id,
                label = 'Business Stash',
                icon = 'fa-solid fa-box-archive',
                onSelect = function()
                    TriggerServerEvent('lv_laitonyritys:server:openStash', id)
                end
            }
        }
    })
end

local function setupCameraAccessForLocation(id, data)
    if not data.cameraAccessCoords then return end
    if not Config.UseOxTarget then return end

    local c = data.cameraAccessCoords

    exports.ox_target:addBoxZone({
        coords   = vec3(c.x, c.y, c.z),
        size     = vec3(1.0, 1.0, 1.5),
        rotation = c.w or 0.0,
        debug    = false,
        options  = {
            {
                name  = 'lv_laitonyritys_cctv_' .. id,
                label = 'Access CCTV',
                icon  = 'fa-solid fa-video',
                onSelect = function()
                    TriggerEvent('lv_laitonyritys:client:openCctv', id)
                end
            }
        }
    })
end

CreateThread(function()
    -- wait until Config.Locations exists
    while Config == nil or Config.Locations == nil do
        Wait(100)
    end

    for id, loc in pairs(Config.Locations) do
        -- merge shared IPL data into this location (based on loc.type)
        local data = applyIPLDefaults(id, loc)

        -- store back so other parts (raidCamera, etc.) see the merged values
        Config.Locations[id] = data

        -- door in/out (uses enterCoords + interiorCoords)
        setupEntranceForLocation(id, data)

        -- laptop inside (uses laptopCoords)
        setupTargetForLocation(id, data)

        -- stash inside (uses stashCoords)
        setupStashForLocation(id, data)

        setupCameraAccessForLocation(id, data)
    end
end)

-- NUI callbacks

RegisterNUICallback('close', function(_, cb)
    closeAllUi()
    cb('ok')
end)

RegisterNUICallback('buyBusiness', function(data, cb)
    -- Legacy, not used anymore
    lib.callback('lv_laitonyritys:purchaseBusiness', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)

            lib.notify({
                title = updated.locationLabel or 'Business',
                description = 'Business purchased successfully.',
                type = 'success'
            })
        end

        cb({ success = success })
    end, currentBusinessId)
end)

RegisterNUICallback('buySupplies', function(data, cb)
    local amount = tonumber(data.amount) or 0

    lib.callback('lv_laitonyritys:buySupplies', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)

            lib.notify({
                title = updated.locationLabel or 'Business',
                description = 'Supplies purchased successfully.',
                type = 'success'
            })
        end

        cb({ success = success })
    end, currentBusinessId, amount)
end)

-- simple helper to start client-side resupply mission
local function beginResupplyMission(token)
    local mission = ActiveResupplies[token]
    if not mission or not mission.info or not mission.info.target then
        lib.notify({
            title = 'Resupply',
            description = 'Resupply started, but mission location is not configured.',
            type = 'warning'
        })
        return
    end

    local t = mission.info.target
    local pos = vec3(t.x, t.y, t.z)
    local label = mission.info.label or 'Resupply Site'

    local blip = AddBlipForCoord(t.x, t.y, t.z)
    SetBlipSprite(blip, 514)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)

    SetNewWaypoint(t.x, t.y)

    lib.notify({
        title = 'Resupply',
        description = mission.info.description or 'Go to the marked location and secure supplies.',
        type = 'info'
    })

    mission.blip = blip

    CreateThread(function()
        local textShowing = false
        local tokenRef = token

        while ActiveResupplies[tokenRef] do
            local sleep = 500
            local ped = PlayerPedId()
            local ppos = GetEntityCoords(ped)
            local dist = #(ppos - pos)

            if dist < 30.0 then
                sleep = 0
                DrawMarker(
                    1,
                    t.x, t.y, t.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, t.w or 0.0,
                    2.5, 2.5, 1.5,
                    255, 200, 50, 150,
                    false, true, 2, nil, nil, false
                )

                if dist < 2.5 then
                    if not textShowing then
                        lib.showTextUI('[E] Steal supplies')
                        textShowing = true
                    end

                    if IsControlJustReleased(0, 38) then
                        if textShowing then
                            lib.hideTextUI()
                            textShowing = false
                        end

                        TriggerEvent('lv_laitonyritys:client:completeResupply', tokenRef)
                        break
                    end
                else
                    if textShowing then
                        lib.hideTextUI()
                        textShowing = false
                    end
                end
            end

            Wait(sleep)
        end

        if ActiveResupplies[tokenRef] then
            -- mission ended without completion (server side or other)
            if mission.blip then
                RemoveBlip(mission.blip)
            end
        end

        if textShowing then
            lib.hideTextUI()
        end
    end)
end

RegisterNUICallback('startResupply', function(data, cb)
    local missionType = data.missionType or 1

    lib.callback('lv_laitonyritys:startResupply', false, function(success, token, missionInfo)
        if success then
            ActiveResupplies[token] = {
                businessId = currentBusinessId,
                missionType = missionType,
                info = missionInfo
            }

            -- Tell the laptop UI about active mission
            SendNUIMessage({
                action = 'resupplyStarted'
            })

            -- Start the actual client-side mission flow (blip, marker, etc.)
            beginResupplyMission(token)
        end

        cb({ success = success })
    end, currentBusinessId, missionType)
end)

-- simple helper to start client-side sell mission
local function beginSellMission(token)
    local mission = ActiveSales[token]
    if not mission or not mission.info or not mission.info.target then
        lib.notify({
            title = 'Sell',
            description = 'Sell mission started, but buyer location is not configured.',
            type = 'warning'
        })
        return
    end

    local t = mission.info.target
    local pos = vec3(t.x, t.y, t.z)
    local label = mission.info.label or 'Buyer Location'

    local blip = AddBlipForCoord(t.x, t.y, t.z)
    SetBlipSprite(blip, 500)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)

    SetNewWaypoint(t.x, t.y)

    lib.notify({
        title = 'Sell',
        description = mission.info.description or 'Deliver the product to the buyer.',
        type = 'info'
    })

    mission.blip = blip

    CreateThread(function()
        local textShowing = false
        local tokenRef = token

        while ActiveSales[tokenRef] do
            local sleep = 500
            local ped = PlayerPedId()
            local ppos = GetEntityCoords(ped)
            local dist = #(ppos - pos)

            if dist < 30.0 then
                sleep = 0
                DrawMarker(
                    1,
                    t.x, t.y, t.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, t.w or 0.0,
                    2.5, 2.5, 1.5,
                    50, 220, 50, 150,
                    false, true, 2, nil, nil, false
                )

                if dist < 2.5 then
                    if not textShowing then
                        lib.showTextUI('[E] Complete deal')
                        textShowing = true
                    end

                    if IsControlJustReleased(0, 38) then
                        if textShowing then
                            lib.hideTextUI()
                            textShowing = false
                        end

                        TriggerEvent('lv_laitonyritys:client:completeSell', tokenRef)
                        break
                    end
                else
                    if textShowing then
                        lib.hideTextUI()
                        textShowing = false
                    end
                end
            end

            Wait(sleep)
        end

        if ActiveSales[tokenRef] then
            if mission.blip then
                RemoveBlip(mission.blip)
            end
        end

        if textShowing then
            lib.hideTextUI()
        end
    end)
end

RegisterNUICallback('startSell', function(data, cb)
    local missionType = data.missionType or 1

    lib.callback('lv_laitonyritys:startSell', false, function(success, token, missionInfo)
        if success then
            ActiveSales[token] = {
                businessId = currentBusinessId,
                missionType = missionType,
                info = missionInfo
            }

            -- Tell the laptop UI about active mission
            SendNUIMessage({
                action = 'sellStarted'
            })

            -- Start the client-side mission flow (blip, marker, etc.)
            beginSellMission(token)
        end

        cb({ success = success })
    end, currentBusinessId, missionType)
end)


RegisterNUICallback('upgrade', function(data, cb)
    local upgradeType = data.upgradeType

    lib.callback('lv_laitonyritys:upgrade', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)

            local pretty = 'Upgrade'
            if upgradeType == 'equipment' then
                pretty = 'Equipment upgrade'
            elseif upgradeType == 'employees' then
                pretty = 'Employees upgrade'
            elseif upgradeType == 'security' then
                pretty = 'Security upgrade'
            end

            lib.notify({
                title = updated.locationLabel or 'Business',
                description = pretty .. ' purchased.',
                type = 'success'
            })
        end

        cb({ success = success })
    end, currentBusinessId, upgradeType)
end)


RegisterNUICallback('transfer', function(data, cb)
    local targetId = tonumber(data.targetServerId)

    lib.callback('lv_laitonyritys:transferBusiness', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)

            lib.notify({
                title = updated.locationLabel or 'Business',
                description = 'Business ownership transferred successfully.',
                type = 'success'
            })
        end

        cb({ success = success })
    end, currentBusinessId, targetId)
end)

RegisterNUICallback('addAssociate', function(data, cb)
    local identifier = data.identifier

    lib.callback('lv_laitonyritys:addAssociate', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)
        end
        cb({ success = success })
    end, currentBusinessId, identifier)
end)

RegisterNUICallback('removeAssociate', function(data, cb)
    local identifier = data.identifier

    lib.callback('lv_laitonyritys:removeAssociate', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)
        end
        cb({ success = success })
    end, currentBusinessId, identifier)
end)

-- Purchase button in browser
RegisterNUICallback('purchaseBusiness', function(data, cb)
    local businessId = data and data.businessId
    if not businessId then
        cb({ success = false })
        return
    end

    lib.callback('lv_laitonyritys:purchaseBusiness', false, function(success)
        if success then
            -- refresh browser list after purchase
            lib.callback('lv_laitonyritys:getBusinessBrowserData', false, function(payload)
                if payload then
                    SendNUIMessage({
                        action = 'updateBusinesses',
                        playerName = payload.playerName,
                        cash = payload.cash,
                        bank = payload.bank,
                        businesses = payload.businesses
                    })
                end
            end)
        end

        cb({ success = success })
    end, businessId)
end)

-- Mark on GPS button in browser
RegisterNUICallback('markGps', function(data, cb)
    local businessId = data and data.businessId
    local loc = businessId and Config.Locations[businessId]
    if loc and loc.enterCoords then
        local c = loc.enterCoords
        SetNewWaypoint(c.x, c.y)
        lib.notify({
            title = 'Businesses',
            description = ('GPS set to %s.'):format(loc.label or 'location'),
            type = 'success'
        })
    end
    cb('ok')
end)

RegisterNetEvent('lv_laitonyritys:client:openBusinessMenu', function(businessId)
    lib.callback('lv_laitonyritys:getBusinessData', false, function(data)
        if not data then
            lib.notify({
                title = 'Business',
                description = 'Failed to load business data.',
                type = 'error'
            })
            return
        end

        if not data.owned then
            lib.notify({
                title = data.locationLabel or 'Business',
                description = 'You must own this business to use the laptop.',
                type = 'error'
            })
            return
        end

        if data.setup_completed == 0 then
            -- Setup required
            if not data.isOwner then
                lib.notify({
                    title = data.locationLabel or 'Business',
                    description = 'Only the owner can start the setup mission.',
                    type = 'error'
                })
                return
            end

            lib.callback('lv_laitonyritys:startSetup', false, function(result)
                if not result or not result.ok then
                    local reason = result and result.reason or 'unknown'
                    local msg = 'Setup could not be started.'

                    if reason == 'already_active' then
                        msg = 'You already have an active setup mission.'
                    elseif reason == 'no_truck_config' or reason == 'no_delivery_config' then
                        msg = 'Setup configuration is missing, contact staff.'
                    elseif reason == 'already_setup' then
                        msg = 'This business is already set up.'
                    end

                    lib.notify({
                        title = data.locationLabel or 'Business',
                        description = msg,
                        type = 'error'
                    })
                else
                    lib.notify({
                        title = data.locationLabel or 'Business',
                        description = 'Setup mission started, check your GPS.',
                        type = 'info'
                    })
                end
            end, businessId)

            return
        end

        -- Already set up -> open laptop UI (management)
        currentBusinessId = businessId
        currentBusinessData = data

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openLaptop',
            businessId = businessId,
            data = data
        })
    end, businessId)
end)

-- Resupply mission completion trigger
RegisterNetEvent('lv_laitonyritys:client:completeResupply', function(token)
    local mission = ActiveResupplies[token]
    if not mission then return end

    -- Optional: hacking minigame
    local success = true

    if Config.Minigames.Hacking.Type == 'export' then
        local args = Config.Minigames.Hacking.Args or {}
        local icons = args.icons or 3
        local time = args.time or 5000
        success = exports[Config.Minigames.Hacking.Resource][Config.Minigames.Hacking.Export](icons, time)
    end

    if not success then
        lib.notify({ title = 'Resupply', description = 'You failed the hack.', type = 'error' })
        if mission.blip then
            RemoveBlip(mission.blip)
        end
        ActiveResupplies[token] = nil
        return
    end

    if mission.blip then
        RemoveBlip(mission.blip)
    end

    TriggerServerEvent('lv_laitonyritys:server:completeResupply', token)
    ActiveResupplies[token] = nil
end)

RegisterNetEvent('lv_laitonyritys:client:completeSell', function(token)
    local mission = ActiveSales[token]
    if not mission then return end

    -- Optional: normal lockpick minigame here
    local success = true
    if Config.Minigames.Lockpick.Type == 'event' then
        -- You can trigger your own lockpick event here if desired
        success = true
    end

    if not success then
        lib.notify({ title = 'Sell', description = 'You failed to secure the deal.', type = 'error' })
        if mission.blip then
            RemoveBlip(mission.blip)
        end
        ActiveSales[token] = nil
        return
    end

    if mission.blip then
        RemoveBlip(mission.blip)
    end

    TriggerServerEvent('lv_laitonyritys:server:completeSell', token)
    ActiveSales[token] = nil
end)

-- Raids - camera view (optional)
RegisterNetEvent('lv_laitonyritys:client:raidCamera', function(businessId)
    local data = Config.Locations[businessId]
    if not data or not data.cameraCoords then return end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, data.cameraCoords.x, data.cameraCoords.y, data.cameraCoords.z + 2.0)
    PointCamAtCoord(cam, data.enterCoords.x, data.enterCoords.y, data.enterCoords.z)
    RenderScriptCams(true, true, 500, true, true)
    Wait(7000)
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
end)

RegisterNetEvent('lv_laitonyritys:client:updateRaidState', function(businessId, state)
    if state then
        ActiveRaidStates[businessId] = {
            breached = state.breached or false,
            confiscated = state.confiscated or false,
            expiresAt = state.expiresAt
        }
    else
        ActiveRaidStates[businessId] = nil
        RaidEntryUnlocked[businessId] = nil
    end
end)

RegisterNetEvent('lv_laitonyritys:client:openBusinessBrowser', function()
    lib.callback('lv_laitonyritys:getBusinessBrowserData', false, function(payload)
        if not payload then
            lib.notify({
                title = 'Businesses',
                description = 'Failed to load business list.',
                type = 'error'
            })
            return
        end

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openBusinessBrowser',
            playerName = payload.playerName,
            cash = payload.cash,
            bank = payload.bank,
            businesses = payload.businesses
        })
    end)
end)

RegisterNetEvent('lv_laitonyritys:client:beginSetup', function(businessId, truckCoords, deliveryCoords, label)
    if currentSetup then
        lib.notify({
            title = label or 'Business',
            description = 'You already have an active setup mission.',
            type = 'error'
        })
        return
    end

    local model = `pounder2`
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end

    local veh = CreateVehicle(
        model,
        truckCoords.x, truckCoords.y, truckCoords.z,
        truckCoords.w or 0.0,
        true, false
    )

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDoorsLocked(veh, 1)
    SetModelAsNoLongerNeeded(model)

    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('lv_laitonyritys:server:setupTruckSpawned', netId)

    -- Blip for truck
    local blip = AddBlipForEntity(veh)
    SetBlipSprite(blip, 67)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Setup Truck')
    EndTextCommandSetBlipName(blip)

    SetNewWaypoint(truckCoords.x, truckCoords.y)

    lib.notify({
        title = label or 'Business Setup',
        description = 'Setup started. Get the supply truck at the GPS location.',
        type = 'info'
    })

    currentSetup = {
        businessId = businessId,
        truck = veh,
        truckNetId = netId,
        delivery = deliveryCoords,
        stage = 'getTruck',
        blip = blip,
        textShowing = false
    }

    -- Start monitor thread
    CreateThread(function()
        local deliveryPos = vec3(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z)
        local targetHeading = deliveryCoords.w or 0.0

        while currentSetup and DoesEntityExist(currentSetup.truck) do
            local sleep = 500

            local ped = PlayerPedId()
            local veh = currentSetup.truck

            -- Truck destroyed? cancel.
            if not DoesEntityExist(veh) or IsEntityDead(veh) then
                lib.notify({
                    title = label or 'Business Setup',
                    description = 'The supply truck was destroyed. Setup failed.',
                    type = 'error'
                })

                if currentSetup.blip then
                    RemoveBlip(currentSetup.blip)
                end
                if currentSetup.textShowing then
                    lib.hideTextUI()
                end

                -- restore player back to normal world
                TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', currentSetup.businessId, false)

                currentSetup = nil
                break
            end

            local inTruck = GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped

            if currentSetup.stage == 'getTruck' then
                sleep = 250
                if inTruck then
                    -- Switch GPS to delivery
                    if currentSetup.blip then
                        RemoveBlip(currentSetup.blip)
                    end

                    local blip2 = AddBlipForCoord(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z)
                    SetBlipSprite(blip2, 57)
                    SetBlipScale(blip2, 0.9)
                    SetBlipColour(blip2, 3)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Setup Site')
                    EndTextCommandSetBlipName(blip2)

                    currentSetup.blip = blip2
                    SetNewWaypoint(deliveryCoords.x, deliveryCoords.y)

                    lib.notify({
                        title = label or 'Business Setup',
                        description = 'Drive to the setup site and align the truck with the marked bay.',
                        type = 'info'
                    })

                    currentSetup.stage = 'driveToSite'
                end

            elseif currentSetup.stage == 'driveToSite' or currentSetup.stage == 'align' then
                sleep = 0

                local truckPos = GetEntityCoords(veh)
                local dist = #(truckPos - deliveryPos)

                if dist < 25.0 then
                    currentSetup.stage = 'align'
                end

                -- Draw the alignment cube
                local heading = targetHeading
                local aligned = false

                local boxSizeX = 3.0
                local boxSizeY = 9.0
                local boxSizeZ = 3.0

                local truckHeading = GetEntityHeading(veh)
                local hDiff = angleDiff(truckHeading, targetHeading)

                if dist < 3.5 and hDiff < 12.0 then
                    aligned = true
                end

                local r, g, b = 255, 128, 0
                if aligned then
                    r, g, b = 0, 255, 100
                end

                DrawMarker(
                    1,
                    deliveryCoords.x, deliveryCoords.y, deliveryCoords.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, heading,
                    boxSizeX, boxSizeY, boxSizeZ,
                    r, g, b, 110,
                    false, true, 2, nil, nil, false
                )

                if aligned and inTruck then
                    if not currentSetup.textShowing then
                        lib.showTextUI('[E] Deliver equipment')
                        currentSetup.textShowing = true
                    end

                    if IsControlJustReleased(0, 38) then -- E
                        if currentSetup.textShowing then
                            lib.hideTextUI()
                        end
                        currentSetup.textShowing = false

                        -- Delete truck client-side
                        if currentSetup.blip then
                            RemoveBlip(currentSetup.blip)
                        end

                        SetEntityAsMissionEntity(veh, true, true)
                        DeleteVehicle(veh)

                        -- mark setup complete on server
                        TriggerServerEvent('lv_laitonyritys:server:completeSetup', businessId)

                        -- restore player to normal world
                        TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', businessId, false)

                        currentSetup = nil
                        break
                    end
                else
                    if currentSetup.textShowing then
                        lib.hideTextUI()
                        currentSetup.textShowing = false
                    end
                end
            end

            Wait(sleep)
        end

        -- Safety cleanup
        if currentSetup then
            if currentSetup.blip then
                RemoveBlip(currentSetup.blip)
            end
            if currentSetup.textShowing then
                lib.hideTextUI()
            end

            -- last-resort: put them back in normal world
            TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', currentSetup.businessId, false)

            currentSetup = nil
        end
    end)
end)

RegisterNUICallback('setPermissions', function(data, cb)
    local identifier = data.identifier
    if not currentBusinessId or not identifier then
        cb({ success = false })
        return
    end

    local perms = {
        can_stash   = data.can_stash   and true or false,
        can_sell    = data.can_sell    and true or false,
        can_buy     = data.can_buy     and true or false,
        can_steal   = data.can_steal   and true or false,
        can_upgrade = data.can_upgrade and true or false,
    }

    lib.callback('lv_laitonyritys:setPermissions', false, function(success, updated)
        if success and updated then
            applyBusinessUiUpdateFromData(updated)
        end
        cb({ success = success })
    end, currentBusinessId, identifier, perms)
end)

RegisterNetEvent('lv_laitonyritys:client:onRaidStart', function(businessId)
    -- Only care if we are inside this facility
    if currentBusinessIdInside ~= businessId then return end

    local guards = SecurityPeds[businessId]
    if not guards then return end

    for _, ped in ipairs(guards) do
        if DoesEntityExist(ped) then
            -- Let them actually be killable in raids
            SetEntityInvincible(ped, false)
            FreezeEntityPosition(ped, false)

            SetPedAlertness(ped, 3)
            SetPedCombatMovement(ped, 2) -- offensive
            SetPedCombatAbility(ped, 2)  -- good fighter
            SetPedCombatRange(ped, 2)    -- medium/long

            SetPedSeeingRange(ped, 100.0)
            SetPedHearingRange(ped, 80.0)

            TaskCombatHatedTargetsAroundPed(ped, 50.0)
        end
    end
end)

CreateThread(function()
    local showing = false

    while true do
        Wait(500)

        local businessId = currentBusinessIdInside
        if not businessId or not currentRaidOfficer then
            if showing then
                lib.hideTextUI()
                showing = false
            end
            goto continue
        end

        local raid = getActiveRaidState(businessId)
        if not raid or not raid.breached or raid.confiscated then
            if showing then
                lib.hideTextUI()
                showing = false
            end
            goto continue
        end

        if not areSecurityNeutralized(businessId) then
            if showing then
                lib.hideTextUI()
                showing = false
            end
            goto continue
        end

        local coords = getConfiscateCoordsForBusiness(businessId)
        if not coords then
            goto continue
        end

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local target = vec3(coords.x, coords.y, coords.z)

        if #(pos - target) < 2.0 then
            if not showing then
                lib.showTextUI('[E] Confiscate Lab Output')
                showing = true
            end

            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                showing = false

                local success = lib.progressCircle({
                    duration = 8000,
                    label = 'Confiscating production...',
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = true,
                    disable = {
                        move = true,
                        car = true,
                        combat = true
                    }
                })

                if success then
                    TriggerServerEvent('lv_laitonyritys:server:confiscateLab', businessId)
                else
                    lib.notify({
                        title = 'Police Raid',
                        description = 'Confiscation cancelled.',
                        type = 'error'
                    })
                end
            end
        elseif showing then
            lib.hideTextUI()
            showing = false
        end

        ::continue::
    end
end)

RegisterNetEvent('lv_laitonyritys:client:setupCompleted', function(businessId)
    lib.notify({
        title = 'Business Setup',
        description = 'Setup completed. The facility is now operational.',
        type = 'success'
    })

    -- If you're inside this business when it completes, refresh HUD & interior sets
    if currentBusinessIdInside == businessId then
        refreshFacilityHud(businessId)
    end
end)

local cctvActive = false

local cctvActive = false

local function runCctvCamera(businessId)
    if cctvActive then return end

    local camPos = getCameraCoordsForBusiness(businessId)
    if not camPos then
        lib.notify({
            title = 'CCTV',
            description = 'Camera not configured for this facility.',
            type = 'error'
        })
        return
    end

    cctvActive = true

    -- FADE OUT instead of tween
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local heading = 0.0
    local pitch   = -15.0
    local fov     = 50.0

    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamRot(cam, pitch, 0.0, heading, 2)
    SetCamFov(cam, fov)

    -- Instant switch, no interpolation
    RenderScriptCams(true, false, 0, true, true)

    -- Force streaming around the camera position (IPL interior)
    SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)

    -- CCTV-style screen effect
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.0)
    StartScreenEffect('CamPushInFranklin', 0, true)

    DoScreenFadeIn(250)

    lib.showTextUI('[←/→][↑/↓] Rotate | Scroll: Zoom | [Backspace] Exit CCTV')

    CreateThread(function()
        while cctvActive do
            Wait(0)

            -- LEFT / RIGHT
            if IsControlPressed(0, 34) then       -- LEFT
                heading = heading + 0.8
            elseif IsControlPressed(0, 35) then   -- RIGHT
                heading = heading - 0.8
            end

            -- UP / DOWN
            if IsControlPressed(0, 32) then       -- UP
                pitch = math.max(-45.0, pitch - 0.5)
            elseif IsControlPressed(0, 33) then   -- DOWN
                pitch = math.min(15.0, pitch + 0.5)
            end

            -- ZOOM (scroll wheel)
            if IsControlPressed(0, 241) then       -- SCROLL UP
                fov = math.max(20.0, fov - 1.0)
            elseif IsControlPressed(0, 242) then   -- SCROLL DOWN
                fov = math.min(60.0, fov + 1.0)
            end

            -- EXIT: backspace / ESC / pause
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) or IsControlJustPressed(0, 200) then
                cctvActive = false
                break
            end

            SetCamRot(cam, pitch, 0.0, heading, 2)
            SetCamFov(cam, fov)
        end

        -- Clean up with fade back
        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do
            Wait(0)
        end

        lib.hideTextUI()
        ClearTimecycleModifier()
        StopScreenEffect('CamPushInFranklin')

        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        ClearFocus()

        DoScreenFadeIn(250)
    end)
end

RegisterNetEvent('lv_laitonyritys:client:openCctv', function(businessId)
    if cctvActive then return end

    lib.callback('lv_laitonyritys:getBusinessData', false, function(data)
        if not data then
            lib.notify({
                title = 'CCTV',
                description = 'Security system offline.',
                type = 'error'
            })
            return
        end

        if not data.owned or not data.canAccess then
            lib.notify({
                title = data.locationLabel or 'CCTV',
                description = 'You do not have access to this CCTV system.',
                type = 'error'
            })
            return
        end

        local secLevel = data.securityLevel or data.security_level or 0
        if secLevel <= 0 then
            lib.notify({
                title = data.locationLabel or 'CCTV',
                description = 'Install security upgrades to unlock CCTV.',
                type = 'error'
            })
            return
        end

        runCctvCamera(businessId)
    end, businessId)
end)

RegisterCommand('closebusinessui', function()
    closeAllUi()
end, false)