-- client/npc.lua

local spawnedPeds = {}

local function loadModel(model)
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

local function spawnBusinessNPC(cfg, index)
    local model = cfg.model
    if not loadModel(model) then
        print('[lv_laitonyritys] Invalid NPC model for BusinessNPC #' .. index)
        return
    end

    local c = cfg.coords

    local ped = CreatePed(
        4,
        model,
        c.x, c.y, c.z - 1.0,
        c.w or 0.0,
        false, true
    )

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, true)

    if cfg.scenario then
        TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
    end

    spawnedPeds[#spawnedPeds+1] = ped

    ------------------------------------------------------------------
    -- Proximity prompt attached directly to the NPC entity
    ------------------------------------------------------------------
    local promptName  = ('lv_laitonyritys_npc_%s'):format(index)
    local objectText  = cfg.promptText or cfg.label or 'Business Broker'

    print(('[lv_laitonyritys] Creating NPC prompt "%s" for ped %s at (%.2f, %.2f, %.2f)')
        :format(promptName, ped, c.x, c.y, c.z)
    )

    local prompt = exports['lv_proximityprompt']:AddNewPrompt({
        name       = promptName,
        job        = nil,                -- everyone
        objecttext = objectText,
        actiontext = 'Talk about businesses',
        holdtime   = 0,                  -- TAP E (no hold)
        key        = 'E',
        -- IMPORTANT: attach to entity instead of static coords
        entity     = ped,
        position   = vector3(c.x, c.y, c.z),
        params     = { npcIndex = index },
        drawdist   = 3.0,
        usagedist  = 2.5,
        usage      = function(data, actions)
            -- If this fires, you WILL see all of these:
            print(('[lv_laitonyritys] NPC prompt used! npcIndex=%s'):format(
                tostring(data and data.npcIndex)
            ))

            -- Debug visual feedback
            if lib and lib.notify then
                lib.notify({
                    title       = 'Businesses',
                    description = 'NPC prompt used – opening business browser...',
                    type        = 'info',
                    duration    = 2000
                })
            end

            TriggerEvent('chat:addMessage', {
                args = { '^2lv_laitonyritys', 'NPC prompt usage fired (Talk about businesses)' }
            })

            -- Finally, open the browser UI
            TriggerEvent('lv_laitonyritys:client:openBusinessBrowser')
        end,
    })

    -- Not strictly required, but keep reference in case you want it later
    cfg._prompt = prompt
end

CreateThread(function()
    Wait(1000)

    if not Config.BusinessNPCs or #Config.BusinessNPCs == 0 then
        print('[lv_laitonyritys] No BusinessNPCs configured.')
        return
    end

    print(('[lv_laitonyritys] Spawning %d BusinessNPCs + prompts.'):format(#Config.BusinessNPCs))

    for i, cfg in ipairs(Config.BusinessNPCs) do
        spawnBusinessNPC(cfg, i)
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    -- If you want to also remove prompts here, you can:
    -- for _, cfg in ipairs(Config.BusinessNPCs or {}) do
    --     if cfg._prompt and cfg._prompt.Remove then
    --         cfg._prompt:Remove()
    --     end
    -- end
end)
