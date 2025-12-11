ESX = exports['es_extended']:getSharedObject()

-- Shared business state (used across multiple client files)
currentBusinessId = nil
currentBusinessData = nil

currentBusinessIdInside = nil
currentSetup = nil -- { businessId, stage, truck, truckNetId, delivery, blip }

-- bob74_ipl references
local bikerMethLab = nil
local bikerWeedFarm = nil
local bikerCocaine = nil
local bikerCounterfeit = nil
local bikerDocumentForgery = nil

-- Security peds
local SECURITY_PED_MODEL   = `mp_g_m_pros_01`
local REL_GROUP_SECURITY   = nil
local SecurityPeds         = {}

-- Raid-only guards (separate from decorative SecurityPeds)
local RaidGuardPeds = {}  -- [businessId] = { ped1, ped2, ... }

-- Active raid state (shared with ui_missions.lua)
ActiveRaidBusinesses = ActiveRaidBusinesses or {} -- [businessId] = { active=true, doorBreached=bool }

local function clearRaidGuards(businessId)
    local list = RaidGuardPeds[businessId]
    if not list then return end

    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    RaidGuardPeds[businessId] = nil
end

-- Global so ui_missions.lua can call it via the raid event
function spawnRaidGuards(businessId)
    clearRaidGuards(businessId)

    local loc = Config.Locations[businessId]
    if not loc then
        print('[lv_laitonyritys] spawnRaidGuards: no location for ' .. tostring(businessId))
        return
    end

    local ipl = Config.IPLSetup and Config.IPLSetup[loc.type]
    if not ipl or not ipl.securityGuards or #ipl.securityGuards == 0 then
        print('[lv_laitonyritys] spawnRaidGuards: no securityGuards config for ' .. tostring(loc.type))
        return
    end

    RequestModel(SECURITY_PED_MODEL)
    while not HasModelLoaded(SECURITY_PED_MODEL) do
        Wait(0)
    end

    local spawned = {}
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())

    -- Make security hate the player group as well
    if REL_GROUP_SECURITY and playerGroup then
        SetRelationshipBetweenGroups(5, REL_GROUP_SECURITY, playerGroup)
        SetRelationshipBetweenGroups(5, playerGroup, REL_GROUP_SECURITY)
    end

    for _, cfg in ipairs(ipl.securityGuards) do
        local c = cfg.coords
        if c then
            local ped = CreatePed(
                4,
                SECURITY_PED_MODEL,
                c.x, c.y, c.z,
                c.w or 0.0,
                false, true
            )

            SetEntityAsMissionEntity(ped, true, true)

            -- Put them in our security group
            if REL_GROUP_SECURITY then
                SetPedRelationshipGroupHash(ped, REL_GROUP_SECURITY)
            end

            -- Make them real combat AI
            SetEntityInvincible(ped, false)
            FreezeEntityPosition(ped, false)
            SetEntityProofs(ped, false, false, false, false, false, false, false, false)

            SetPedCanRagdoll(ped, true)
            SetPedCanRagdollFromPlayerImpact(ped, true)
            SetPedDiesWhenInjured(ped, true)

            SetBlockingOfNonTemporaryEvents(ped, false)

            -- Weapons & stats
            GiveWeaponToPed(ped, `WEAPON_PISTOL`, 120, false, true)
            SetPedArmour(ped, 50)
            SetPedAccuracy(ped, 40)
            SetPedAlertness(ped, 3)
            SetPedCombatMovement(ped, 2) -- offensive
            SetPedCombatAbility(ped, 2)  -- good
            SetPedCombatRange(ped, 2)    -- medium

            SetPedSeeingRange(ped, 100.0)
            SetPedHearingRange(ped, 80.0)

            -- Immediately attack the player
            TaskCombatPed(ped, PlayerPedId(), 0, 16)

            table.insert(spawned, ped)
        end
    end

    RaidGuardPeds[businessId] = spawned

    print(('[lv_laitonyritys] spawnRaidGuards(%s) spawned %d raid guards'):format(
        tostring(businessId), #spawned
    ))
end

-- Global so both main.lua and ui_missions.lua can read/write
ActiveRaidBusinesses = ActiveRaidBusinesses or {} -- [businessId] = { active=true, doorBreached=bool }

-- Global so ui_missions.lua can use it
function isPlayerPolice()
    if Config.Framework ~= 'esx' or not ESX then return false end

    local data = ESX.GetPlayerData and ESX.GetPlayerData() or ESX.PlayerData
    local jobName = data and data.job and data.job.name
    if not jobName then return false end

    local jobs = (Config.Raids and Config.Raids.PoliceJobs) or {}
    for _, j in ipairs(jobs) do
        if j == jobName then
            return true
        end
    end
    return false
end

-- Global so ui_missions.lua (setup mission alignment) can use it
function angleDiff(a, b)
    local d = (a - b) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return math.abs(d)
end

local function resetBusinessUiState()
    currentBusinessId = nil
    currentBusinessData = nil
end

-- Global so ui_missions.lua (close NUI & command) can call it
function closeAllUi()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    resetBusinessUiState()
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

-- Global so CCTV helper in ui_missions.lua can use it
function getCameraCoordsForBusiness(businessId)
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
    -- BIKER COUNTERFEIT FACTORY (bob74_ipl)
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

-- Global so ui_missions.lua can refresh on certain events (raid confiscated/setup completed)
function refreshFacilityHud(businessId)
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

-- Global so ui_missions.lua (NUI callbacks) can call this
function applyBusinessUiUpdateFromData(updated)
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

                local raidState   = ActiveRaidBusinesses[id]
                local pol         = isPlayerPolice()
                local raidActive  = pol and raidState ~= nil and raidState.active ~= false
                local label

                if raidActive then
                    if raidState.doorBreached then
                        label = '[E] Enter Facility'
                    else
                        label = '[E] Lockpick Door'
                    end
                else
                    label = ('[E] Enter %s'):format(data.label)
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

                    -- POLICE RAID FLOW
                    if raidActive then
                        -- Check with server if raid is still valid and what the door state is
                        lib.callback('lv_laitonyritys:attemptRaidEntry', false, function(result)
                            if not result or not result.ok then
                                local reason = result and result.reason or 'no_access'
                                local msg = 'You cannot raid this facility right now.'

                                if reason == 'no_active_raid' then
                                    msg = 'No active raid for this facility.'
                                elseif reason == 'not_police' then
                                    msg = 'Only police may breach this door.'
                                elseif reason == 'raid_expired' then
                                    msg = 'The raid window has expired.'
                                end

                                lib.notify({
                                    title       = 'Business Raid',
                                    description = msg,
                                    type        = 'error'
                                })
                                return
                            end

                            -- Update local doorBreached from server result
                            ActiveRaidBusinesses[businessId] = {
                                active       = true,
                                doorBreached = result.doorBreached or false
                            }

                            if result.doorBreached then
                                -- Door already breached -> enter facility as police
                                TriggerServerEvent('lv_laitonyritys:server:setInsideBusiness', businessId, true)

                                local faceHeading = entrance.w or GetEntityHeading(PlayerPedId())
                                playDoorTransition(interior, faceHeading)

                                currentBusinessIdInside = businessId

                                -- Load interior + security for this police client
                                lib.callback('lv_laitonyritys:getBusinessData', false, function(bizData)
                                    if bizData then
                                        TriggerEvent('lv_laitonyritys:client:updateEmployeesForBusiness',
                                            businessId,
                                            bizData.type or businessType,
                                            bizData.employeesLevel or 0,
                                            true
                                        )
                                        refreshFacilityHud(businessId)
                                    end
                                end, businessId)

                                -- Inform server that a cop has entered, so guards go hostile
                                TriggerServerEvent('lv_laitonyritys:server:enterRaidInterior', businessId)
                            else
                                -- Need to lockpick door
                                lib.showTextUI('Lockpicking door...')
                                local success = exports['lockpick']:startLockpick()
                                lib.hideTextUI()

                                if success then
                                    lib.notify({
                                        title       = 'Business Raid',
                                        description = 'Door breached. You can now enter the facility.',
                                        type        = 'success'
                                    })

                                    TriggerServerEvent('lv_laitonyritys:server:raidDoorBreached', businessId)

                                    -- Locally reflect that door is open so label switches to "Enter Facility"
                                    ActiveRaidBusinesses[businessId] = {
                                        active       = true,
                                        doorBreached = true
                                    }
                                else
                                    lib.notify({
                                        title       = 'Business Raid',
                                        description = 'Lockpick failed.',
                                        type        = 'error'
                                    })
                                end
                            end
                        end, businessId)

                    else
                        -- NORMAL OWNER / ASSOCIATE ENTRY FLOW
                        lib.callback('lv_laitonyritys:getBusinessData', false, function(bizData)
                            if not bizData then
                                lib.notify({
                                    title       = data.label or 'Business',
                                    description = 'Failed to load business data.',
                                    type        = 'error'
                                })
                                return
                            end

                            -- must own OR have keys (associate)
                            if not bizData.owned or not bizData.canAccess then
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

                            -- employees
                            TriggerEvent('lv_laitonyritys:client:updateEmployeesForBusiness',
                                businessId,
                                bizData.type or businessType,
                                bizData.employeesLevel or 0,
                                true
                            )

                            showFirstTimeBusinessAlert(businessId)
                            refreshFacilityHud(businessId)

                            -- If there's an active raid, trigger local raid start (for guards etc.)
                            lib.callback('lv_laitonyritys:getRaidState', false, function(state)
                                if state and state.active then
                                    print(('[lv_laitonyritys] active raid detected on entry: %s'):format(businessId))
                                    TriggerEvent('lv_laitonyritys:client:onRaidStart', businessId)
                                end
                            end, businessId)
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

local function setupConfiscateForLocation(id, data)
    if not Config.UseOxTarget then return end

    local loc = Config.Locations[id]
    if not loc then return end

    local ipl = Config.IPLSetup and Config.IPLSetup[loc.type]
    if not ipl or not ipl.confiscateCoords then return end

    local c = ipl.confiscateCoords

    exports.ox_target:addBoxZone({
        coords   = vec3(c.x, c.y, c.z),
        size     = vec3(1.2, 1.2, 1.5),
        rotation = c.w or 0.0,
        debug    = false,
        options  = {
            {
                name  = 'lv_laitonyritys_confiscate_' .. id,
                label = 'Confiscate Lab Assets',
                icon  = 'fa-solid fa-boxes-packing',
                onSelect = function()
                    TriggerEvent('lv_laitonyritys:client:confiscateLab', id)
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
        local data = applyIPLDefaults(id, loc)
        Config.Locations[id] = data

        setupEntranceForLocation(id, data)
        setupTargetForLocation(id, data)
        setupStashForLocation(id, data)
        setupCameraAccessForLocation(id, data)
        setupConfiscateForLocation(id, data)
    end

end)
