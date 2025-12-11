-- UI, missions, raids & CCTV

-- Local mission state (only used in this file)
local ActiveResupplies = {} -- token -> { businessId, missionType, stage, info, van, blip, ... }
local ActiveSales      = {}

local function removeMissionPrompt(mission, fallbackName)
    if not mission then return end

    local function safeRemove(name)
        if not name then return end
        pcall(function()
            exports['lv_proximityprompt']:RemovePrompt(name)
        end)
    end

    -- Object-based prompt (AddNewPrompt returned an object)
    if mission.prompt and mission.prompt.Remove then
        pcall(function()
            mission.prompt:Remove()
        end)
    end

    -- Named prompts (legacy or multi-stage missions)
    if mission.promptName     then safeRemove(mission.promptName)     end
    if mission.promptWarehouse then safeRemove(mission.promptWarehouse) end
    if mission.promptVan      then safeRemove(mission.promptVan)      end
    if mission.promptDropoff  then safeRemove(mission.promptDropoff)  end

    -- Optional fallback
    if fallbackName then
        safeRemove(fallbackName)
    end

    mission.prompt          = nil
    mission.promptName      = nil
    mission.promptWarehouse = nil
    mission.promptVan       = nil
    mission.promptDropoff   = nil
end

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

--------------------------------------------------------
-- STEAL SUPPLIES MISSION (NEW FLOW)
--------------------------------------------------------

local function getHeistConfig()
    local cfg = Config.SupplyHeist or {}
    cfg.WarehouseEnter    = cfg.WarehouseEnter    or vec3(909.24, -2097.41, 30.55)
    cfg.WarehouseInterior = cfg.WarehouseInterior or vec3(1220.133, -2277.844, -50.000)
    cfg.WarehouseExit     = cfg.WarehouseExit     or vec3(1205.89, -2268.45, -47.33)
    cfg.VanSpawn          = cfg.VanSpawn          or vec4(1222.77, -2286.19, -49.00, 359.17)
    cfg.VanModel          = cfg.VanModel          or `gburrito2`
    cfg.DoorHack          = cfg.DoorHack          or { levels = 2, lifes = 3, time = 2 }
    cfg.VanHack           = cfg.VanHack           or { levels = 1, lifes = 3, time = 1 }
    return cfg
end

local function loadModelBlocking(model)
    if type(model) == 'string' then
        model = joaat(model)
    end
    if not IsModelValid(model) then return false end
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(10)
        end
    end
    return true
end

local function cleanupResupplyClient(token)
    local mission = ActiveResupplies[token]
    if not mission then return end

    if mission.blip then
        RemoveBlip(mission.blip)
        mission.blip = nil
    end

    if mission.van and DoesEntityExist(mission.van) then
        DeleteVehicle(mission.van)
        mission.van = nil
    end

    -- Kill every related prompt
    removeMissionPrompt(mission, ('lv_resupply_%s'):format(token))

    -- Just in case a text UI is still up
    pcall(function()
        lib.hideTextUI()
    end)

    ActiveResupplies[token] = nil
end

local function beginResupplyMission(token)
    local mission = ActiveResupplies[token]
    if not mission then
        lib.notify({
            title = 'Resupply',
            description = 'Resupply started, but no local mission data.',
            type = 'error'
        })
        return
    end

    local cfg        = getHeistConfig()
    local whEnter    = cfg.WarehouseEnter      -- vector3
    local whInterior = cfg.WarehouseInterior   -- vector3
    local vanSpawn   = cfg.VanSpawn            -- vector4 (x, y, z, w)

    mission.stage       = 'goToWarehouse'
    mission.hackingDoor = false
    mission.hackingVan  = false
    mission.van         = mission.van or nil
    mission.dropoff     = mission.dropoff or nil

    ----------------------------------------------------------------------
    -- Small helpers for prompts
    ----------------------------------------------------------------------
    local function safeRemovePrompt(name)
        if not name then return end
        pcall(function()
            exports['lv_proximityprompt']:RemovePrompt(name)
        end)
    end

    local function setPromptEnabled(name, enabled)
        if not name then return end
        pcall(function()
            exports['lv_proximityprompt']:SetPromptEnabled(name, enabled and true or false)
        end)
    end

    ----------------------------------------------------------------------
    -- BLIP: Warehouse entrance (first waypoint)
    ----------------------------------------------------------------------
    local blip = AddBlipForCoord(whEnter.x, whEnter.y, whEnter.z)
    SetBlipSprite(blip, 514)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Warehouse Entrance')
    EndTextCommandSetBlipName(blip)

    mission.blip = blip
    SetNewWaypoint(whEnter.x, whEnter.y)

    lib.notify({
        title = 'Resupply',
        description = mission.info and mission.info.description
            or 'Go to the warehouse and hack the security system.',
        type = 'info'
    })

    ----------------------------------------------------------------------
    -- PROMPTS: only for 3D text, we do NOT rely on their `usage`
    ----------------------------------------------------------------------

    -- Entrance prompt
    local whPromptName = ('lv_resupply_wh_%s'):format(token)
    mission.promptWarehouse = whPromptName

    exports['lv_proximityprompt']:AddNewPrompt({
        name       = whPromptName,
        job        = nil,
        objecttext = 'Warehouse Entrance',
        actiontext = 'Start fingerprint hack',
        holdtime   = 0,
        key        = 'E',
        position   = vector3(whEnter.x, whEnter.y, whEnter.z),
        params     = {},
        drawdist   = 10.0,
        usagedist  = 2.0,
        usage      = function()
            -- no-op, logic handled in our loop below
        end,
    })

    -- We'll create van & dropoff prompts later when they become relevant

    ----------------------------------------------------------------------
    -- Helper: start door hack (called when we detect E near entrance)
    ----------------------------------------------------------------------
    local function startDoorHack()
        local m = ActiveResupplies[token]
        if not m or m.stage ~= 'goToWarehouse' or m.hackingDoor then return end

        m.stage       = 'hackingDoor'
        m.hackingDoor = true

        setPromptEnabled(whPromptName, false)

        TriggerServerEvent('lv_laitonyritys:server:alertPoliceSupplyHeist', m.businessId)

        local hackCfg = cfg.DoorHack or {}
        local levels  = hackCfg.levels or 2
        local lifes   = hackCfg.lifes  or 3
        local time    = hackCfg.time   or 2

        TriggerEvent('utk_fingerprint:Start', levels, lifes, time, function(outcome, reason)
            local m2 = ActiveResupplies[token]
            if not m2 then
                safeRemovePrompt(whPromptName)
                return
            end

            m2.hackingDoor = false

            if outcome == true then
                ------------------------------------------------------------------
                -- SUCCESS: Teleport into warehouse and spawn the van
                ------------------------------------------------------------------
                local ped = PlayerPedId()
                DoScreenFadeOut(500)
                while not IsScreenFadedOut() do Wait(0) end

                SetEntityCoords(ped, whInterior.x, whInterior.y, whInterior.z)
                Wait(250)
                DoScreenFadeIn(500)

                if m2.blip then
                    RemoveBlip(m2.blip)
                    m2.blip = nil
                end

                safeRemovePrompt(whPromptName)
                m2.promptWarehouse = nil

                -- Spawn locked van
                if loadModelBlocking(cfg.VanModel) then
                    local modelHash = (type(cfg.VanModel) == 'string') and joaat(cfg.VanModel) or cfg.VanModel
                    local v = CreateVehicle(
                        modelHash,
                        vanSpawn.x, vanSpawn.y, vanSpawn.z,
                        vanSpawn.w or 0.0,
                        true, false
                    )
                    SetVehicleOnGroundProperly(v)
                    SetEntityAsMissionEntity(v, true, true)
                    SetVehicleDoorsLocked(v, 2) -- locked

                    m2.van = v

                    local vblip = AddBlipForEntity(v)
                    SetBlipSprite(vblip, 67)
                    SetBlipScale(vblip, 0.9)
                    SetBlipColour(vblip, 5)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Supply Van')
                    EndTextCommandSetBlipName(vblip)

                    m2.blip = vblip
                end

                m2.stage = 'insideWarehouse'

                lib.notify({
                    title = 'Resupply',
                    description = 'Hack the van doors and steal the supplies.',
                    type = 'info'
                })

                -- Van prompt (visual only)
                if m2.van and DoesEntityExist(m2.van) then
                    local vanPos = GetEntityCoords(m2.van)
                    local vanPromptName = ('lv_resupply_van_%s'):format(token)
                    m2.promptVan = vanPromptName

                    exports['lv_proximityprompt']:AddNewPrompt({
                        name       = vanPromptName,
                        job        = nil,
                        objecttext = 'Supply Van',
                        actiontext = 'Hack van doors',
                        holdtime   = 0,
                        key        = 'E',
                        position   = vector3(vanPos.x, vanPos.y, vanPos.z),
                        params     = {},
                        drawdist   = 20.0,
                        usagedist  = 2.5,
                        usage      = function() end,
                    })
                end
            else
                lib.notify({
                    title = 'Resupply',
                    description = 'You failed the fingerprint hack.',
                    type = 'error'
                })
                safeRemovePrompt(whPromptName)
                mission.promptWarehouse = nil
                cleanupResupplyClient(token)
            end
        end)
    end

    ----------------------------------------------------------------------
    -- Helper: start van hack (called when we detect E near van)
    ----------------------------------------------------------------------
    local function startVanHack()
        local m = ActiveResupplies[token]
        if not m or m.stage ~= 'insideWarehouse' or m.hackingVan then return end
        if not m.van or not DoesEntityExist(m.van) then return end

        m.stage      = 'hackingVan'
        m.hackingVan = true

        local vanPromptName = m.promptVan
        setPromptEnabled(vanPromptName, false)

        local vhCfg  = cfg.VanHack or {}
        local vLvl   = vhCfg.levels or 1
        local vLifes = vhCfg.lifes  or 3
        local vTime  = vhCfg.time   or 1

        TriggerEvent('utk_fingerprint:Start', vLvl, vLifes, vTime, function(ok, reason2)
            local m2 = ActiveResupplies[token]
            if not m2 then
                if vanPromptName then safeRemovePrompt(vanPromptName) end
                return
            end

            m2.hackingVan = false

            if ok == true then
                m2.vanUnlocked = true
                if m2.van and DoesEntityExist(m2.van) then
                    SetVehicleDoorsLocked(m2.van, 1)
                end

                -- Switch blip to facility dropoff
                if m2.blip then
                    RemoveBlip(m2.blip)
                    m2.blip = nil
                end

                local loc = Config.Locations[m2.businessId]
                local drop = loc and (loc.vanCoords or loc.van_coords or loc.setupDelivery or loc.enterCoords)
                if drop then
                    local dropVec = vec3(drop.x, drop.y, drop.z)

                    local dblip = AddBlipForCoord(dropVec.x, dropVec.y, dropVec.z)
                    SetBlipSprite(dblip, 57)
                    SetBlipScale(dblip, 0.9)
                    SetBlipColour(dblip, 3)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Facility Dropoff')
                    EndTextCommandSetBlipName(dblip)

                    m2.blip    = dblip
                    m2.dropoff = dropVec
                    SetNewWaypoint(dropVec.x, dropVec.y)

                    m2.stage = 'driveToDropoff'

                    lib.notify({
                        title = 'Resupply',
                        description = 'Drive the van to your facility loading bay.',
                        type = 'info'
                    })

                    -- Dropoff prompt (visual only)
                    local dropPromptName = ('lv_resupply_drop_%s'):format(token)
                    m2.promptDropoff = dropPromptName

                    exports['lv_proximityprompt']:AddNewPrompt({
                        name       = dropPromptName,
                        job        = nil,
                        objecttext = 'Facility Loading Bay',
                        actiontext = 'Deliver supplies',
                        holdtime   = 0,
                        key        = 'E',
                        position   = vector3(dropVec.x, dropVec.y, dropVec.z),
                        params     = {},
                        drawdist   = 25.0,
                        usagedist  = 5.0,
                        usage      = function() end,
                    })
                else
                    lib.notify({
                        title = 'Resupply',
                        description = 'Dropoff location is not configured for this business.',
                        type = 'error'
                    })
                    if vanPromptName then safeRemovePrompt(vanPromptName) end
                    m2.promptVan = nil
                    cleanupResupplyClient(token)
                end

                if vanPromptName then safeRemovePrompt(vanPromptName) end
                m2.promptVan = nil
            else
                lib.notify({
                    title = 'Resupply',
                    description = 'You failed to hack the van doors.',
                    type = 'error'
                })
                if vanPromptName then safeRemovePrompt(vanPromptName) end
                m2.promptVan = nil
                cleanupResupplyClient(token)
            end
        end)
    end

    ----------------------------------------------------------------------
    -- MAIN LOOP: we handle E presses ourselves
    ----------------------------------------------------------------------
    CreateThread(function()
        local tokenRef   = token
        local textActive = false

        while ActiveResupplies[tokenRef] do
            local m = ActiveResupplies[tokenRef]
            if not m then break end

            local ped   = PlayerPedId()
            local stage = m.stage or 'goToWarehouse'
            local sleep = 500

            -- Fail if van destroyed
            if m.van and not DoesEntityExist(m.van) then
                lib.notify({
                    title = 'Resupply',
                    description = 'The supply van was destroyed. Mission failed.',
                    type = 'error'
                })
                cleanupResupplyClient(tokenRef)
                break
            end

            -- stage-specific logic
            if stage == 'goToWarehouse' then
                local pos  = GetEntityCoords(ped)
                local dist = #(pos - whEnter)

                if dist < 25.0 then
                    sleep = 0
                end

                if dist < 2.0 and not m.hackingDoor then
                    if not textActive then
                        lib.showTextUI('[E] Start fingerprint hack')
                        textActive = true
                    end

                    if IsControlJustPressed(0, 38) then -- E
                        lib.hideTextUI()
                        textActive = false
                        startDoorHack()
                    end
                else
                    if textActive then
                        lib.hideTextUI()
                        textActive = false
                    end
                end

            elseif stage == 'hackingDoor' then
                -- just wait for callback, ensure UI is hidden
                if textActive then
                    lib.hideTextUI()
                    textActive = false
                end
                sleep = 250

            elseif stage == 'insideWarehouse' then
                if textActive then
                    -- ensure we only show relevant hint near van
                    lib.hideTextUI()
                    textActive = false
                end

                local van = m.van
                if van and DoesEntityExist(van) then
                    local pedPos = GetEntityCoords(ped)
                    local vanPos = GetEntityCoords(van)
                    local dist   = #(pedPos - vanPos)

                    if dist < 20.0 then
                        sleep = 0
                    end

                    if dist < 2.5 and not m.vanUnlocked and not m.hackingVan then
                        if not textActive then
                            lib.showTextUI('[E] Hack van doors')
                            textActive = true
                        end

                        if IsControlJustPressed(0, 38) then
                            lib.hideTextUI()
                            textActive = false
                            startVanHack()
                        end
                    else
                        if textActive then
                            lib.hideTextUI()
                            textActive = false
                        end
                    end
                end

            elseif stage == 'hackingVan' then
                if textActive then
                    lib.hideTextUI()
                    textActive = false
                end
                sleep = 250

            elseif stage == 'driveToDropoff' then
                local drop = m.dropoff
                local van  = m.van
                if not drop or not van or not DoesEntityExist(van) then
                    lib.notify({
                        title = 'Resupply',
                        description = 'Dropoff location is not configured or van missing.',
                        type = 'error'
                    })
                    cleanupResupplyClient(tokenRef)
                    break
                end

                local pedVeh = GetVehiclePedIsIn(ped, false)
                local inVan  = (pedVeh == van and GetPedInVehicleSeat(van, -1) == ped)
                local vPos   = GetEntityCoords(van)
                local dist   = #(vPos - drop)

                if dist < 30.0 then
                    sleep = 0
                end

                if inVan and dist < 8.0 then
                    if not textActive then
                        lib.showTextUI('[E] Deliver supplies')
                        textActive = true
                    end

                    if IsControlJustPressed(0, 38) then
                        lib.hideTextUI()
                        textActive = false
                        -- This calls your existing completion event (which does extra optional minigame + server event)
                        TriggerEvent('lv_laitonyritys:client:completeResupply', tokenRef)
                        break
                    end
                else
                    if textActive then
                        lib.hideTextUI()
                        textActive = false
                    end
                end
            end

            Wait(sleep)
        end

        if textActive then
            lib.hideTextUI()
        end
    end)
end

RegisterNUICallback('startResupply', function(data, cb)
    local missionType = data.missionType or 1

    lib.callback('lv_laitonyritys:startResupply', false, function(success, token, missionInfo)
        if success then
            ActiveResupplies[token] = {
                businessId  = currentBusinessId,
                missionType = missionType,
                info        = missionInfo or {},
                stage       = 'goToWarehouse'
            }

            -- Tell the laptop UI about active mission
            SendNUIMessage({
                action = 'resupplyStarted'
            })

            -- Start the new warehouse heist-style mission
            beginResupplyMission(token)
        end

        cb({ success = success })
    end, currentBusinessId, missionType)
end)

--------------------------------------------------------
-- SELL MISSIONS (3D prompt)
--------------------------------------------------------

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

    local t     = mission.info.target
    local pos   = vec3(t.x, t.y, t.z)
    local label = mission.info.label or 'Buyer Location'

    -- BLIP
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

    -- 3D proximity prompt instead of marker + E loop
    local promptName = ('lv_sell_%s'):format(token)
    mission.promptName = promptName

    mission.prompt = exports['lv_proximityprompt']:AddNewPrompt({
        name       = promptName,
        job        = nil,
        objecttext = label,
        actiontext = 'Complete deal',
        holdtime   = 0,
        key        = 'E',
        position   = vector3(pos.x, pos.y, pos.z),
        params     = { token = token },
        usage      = function(data, actions)
            TriggerEvent('lv_laitonyritys:client:completeSell', data.token)
        end,
        drawdist   = 30.0,
        usagedist  = 2.5,
    })
end


RegisterNUICallback('startSell', function(data, cb)
    local missionType = data.missionType or 1

    lib.callback('lv_laitonyritys:startSell', false, function(success, token, missionInfo)
        if success then
            ActiveSales[token] = {
                businessId  = currentBusinessId,
                missionType = missionType,
                info        = missionInfo
            }

            -- Tell the laptop UI about active mission
            SendNUIMessage({
                action = 'sellStarted'
            })

            -- Start the client-side mission flow
            beginSellMission(token)
        end

        cb({ success = success })
    end, currentBusinessId, missionType)
end)

--------------------------------------------------------
-- Upgrades / transfer / associates (unchanged)
--------------------------------------------------------

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

-- Open the laptop business menu
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
        currentBusinessId      = businessId
        currentBusinessData    = data

        SetNuiFocus(true, true)
        SendNUIMessage({
            action     = 'openLaptop',
            businessId = businessId,
            data       = data
        })
    end, businessId)
end)

-- Confiscate lab (police)
RegisterNetEvent('lv_laitonyritys:client:confiscateLab', function(businessId)
    if not isPlayerPolice() then
        lib.notify({
            title       = 'Business Raid',
            description = 'Only police can confiscate this lab.',
            type        = 'error'
        })
        return
    end

    if currentBusinessIdInside ~= businessId then
        lib.notify({
            title       = 'Business Raid',
            description = 'You must be inside the facility to confiscate it.',
            type        = 'error'
        })
        return
    end

    local raidState = ActiveRaidBusinesses[businessId]
    if not raidState or not raidState.active then
        lib.notify({
            title       = 'Business Raid',
            description = 'No active raid for this facility.',
            type        = 'error'
        })
        return
    end

    local ok = lib.progressBar({
        duration     = 15000,
        label        = 'Confiscating lab assets...',
        useWhileDead = false,
        canCancel    = true,
        disable      = {
            move   = true,
            car    = true,
            combat = true
        }
    })

    if ok then
        TriggerServerEvent('lv_laitonyritys:server:confiscateBusiness', businessId)
    end
end)

-- Sync raid state from server (only meaningful for police)
RegisterNetEvent('lv_laitonyritys:client:setRaidState', function(businessId, info)
    if not isPlayerPolice() then return end

    if info and info.active then
        ActiveRaidBusinesses[businessId] = {
            active       = true,
            doorBreached = info.doorBreached or false
        }

        local loc = Config.Locations[businessId]
        lib.notify({
            title       = 'Business Raid',
            description = ('Suspicious activity reported at %s.'):format(loc and loc.label or 'facility'),
            type        = 'info'
        })
    else
        ActiveRaidBusinesses[businessId] = nil
    end
end)

RegisterNetEvent('lv_laitonyritys:client:raidConfiscated', function(businessId)
    if currentBusinessIdInside == businessId then
        refreshFacilityHud(businessId)
    end
end)

-- Resupply mission completion trigger
RegisterNetEvent('lv_laitonyritys:client:completeResupply', function(token)
    local mission = ActiveResupplies[token]
    if not mission then return end

    if not success then
        lib.notify({ title = 'Resupply', description = 'You failed the hack.', type = 'error' })
        cleanupResupplyClient(token)
        return
    end

    TriggerServerEvent('lv_laitonyritys:server:completeResupply', token)
    cleanupResupplyClient(token)
end)

RegisterNetEvent('lv_laitonyritys:client:completeSell', function(token)
    local mission = ActiveSales[token]
    if not mission then return end

    -- Optional: normal lockpick minigame here
    local success = true
    if Config.Minigames and Config.Minigames.Lockpick and Config.Minigames.Lockpick.Type == 'event' then
        -- You can trigger your own lockpick event here if desired
        success = true
    end

    if not success then
        lib.notify({ title = 'Sell', description = 'You failed to secure the deal.', type = 'error' })

        if mission.blip then
            RemoveBlip(mission.blip)
            mission.blip = nil
        end

        removeMissionPrompt(mission, ('lv_sell_%s'):format(token))
        ActiveSales[token] = nil
        return
    end

    if mission.blip then
        RemoveBlip(mission.blip)
        mission.blip = nil
    end

    removeMissionPrompt(mission, ('lv_sell_%s'):format(token))

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
            action     = 'openBusinessBrowser',
            playerName = payload.playerName,
            cash       = payload.cash,
            bank       = payload.bank,
            businesses = payload.businesses
        })
    end)
end)

-- Setup mission (unchanged, still uses marker + E)
RegisterNetEvent('lv_laitonyritys:client:beginSetup', function(businessId, truckCoords, deliveryCoords, label)
    if currentSetup then
        lib.notify({
            title       = label or 'Business',
            description = 'You already have an active setup mission.',
            type        = 'error'
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
        title       = label or 'Business Setup',
        description = 'Setup started. Get the supply truck at the GPS location.',
        type        = 'info'
    })

    currentSetup = {
        businessId  = businessId,
        truck       = veh,
        truckNetId  = netId,
        delivery    = deliveryCoords,
        stage       = 'getTruck',
        blip        = blip,
        textShowing = false
    }

    -- Start monitor thread
    CreateThread(function()
        local deliveryPos   = vec3(deliveryCoords.x, deliveryCoords.y, deliveryCoords.z)
        local targetHeading = deliveryCoords.w or 0.0

        while currentSetup and DoesEntityExist(currentSetup.truck) do
            local sleep = 500

            local ped = PlayerPedId()
            local veh = currentSetup.truck

            -- Truck destroyed? cancel.
            if not DoesEntityExist(veh) or IsEntityDead(veh) then
                lib.notify({
                    title       = label or 'Business Setup',
                    description = 'The supply truck was destroyed. Setup failed.',
                    type        = 'error'
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
                        title       = label or 'Business Setup',
                        description = 'Drive to the setup site and align the truck with the marked bay.',
                        type        = 'info'
                    })

                    currentSetup.stage = 'driveToSite'
                end

            elseif currentSetup.stage == 'driveToSite' or currentSetup.stage == 'align' then
                sleep = 0

                local truckPos = GetEntityCoords(veh)
                local dist     = #(truckPos - deliveryPos)

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
                local hDiff        = angleDiff(truckHeading, targetHeading)

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

-- Raid start (spawn raid guards)
RegisterNetEvent('lv_laitonyritys:client:onRaidStart', function(businessId)
    -- Only do anything if we are inside THIS facility
    if currentBusinessIdInside ~= businessId then
        print('[lv_laitonyritys] raid start ignored, not inside this business')
        return
    end

    -- Leave decorative guards alone, just spawn raid guards in addition
    spawnRaidGuards(businessId)
end)

RegisterNetEvent('lv_laitonyritys:client:setupCompleted', function(businessId)
    lib.notify({
        title       = 'Business Setup',
        description = 'Setup completed. The facility is now operational.',
        type        = 'success'
    })

    -- If you're inside this business when it completes, refresh HUD & interior sets
    if currentBusinessIdInside == businessId then
        refreshFacilityHud(businessId)
    end
end)

-- CCTV logic
local cctvActive = false

local function runCctvCamera(businessId)
    if cctvActive then return end

    local camPos = getCameraCoordsForBusiness(businessId)
    if not camPos then
        lib.notify({
            title       = 'CCTV',
            description = 'Camera not configured for this facility.',
            type        = 'error'
        })
        return
    end

    cctvActive = true

    -- FADE OUT instead of tween
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    local cam     = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
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
                title       = 'CCTV',
                description = 'Security system offline.',
                type        = 'error'
            })
            return
        end

        if not data.owned or not data.canAccess then
            lib.notify({
                title       = data.locationLabel or 'CCTV',
                description = 'You do not have access to this CCTV system.',
                type        = 'error'
            })
            return
        end

        local secLevel = data.securityLevel or data.security_level or 0
        if secLevel <= 0 then
            lib.notify({
                title       = data.locationLabel or 'CCTV',
                description = 'Install security upgrades to unlock CCTV.',
                type        = 'error'
            })
            return
        end

        runCctvCamera(businessId)
    end, businessId)
end)

-- Convenience command to force-close UI
RegisterCommand('closebusinessui', function()
    closeAllUi()
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    for token, mission in pairs(ActiveResupplies) do
        if mission.blip then
            RemoveBlip(mission.blip)
        end
        cleanupResupplyClient(token)
    end

    for token, mission in pairs(ActiveSales) do
        if mission.blip then
            RemoveBlip(mission.blip)
            mission.blip = nil
        end
        removeMissionPrompt(mission, ('lv_sell_%s'):format(token))
    end
end)
