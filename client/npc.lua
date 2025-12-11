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

    local ped = CreatePed(
        4,
        model,
        cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0,
        cfg.coords.w or 0.0,
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

    -- target: Talk about businesses
    if Config.UseOxTarget then
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'lv_laitonyritys_npc_' .. index,
                icon = 'fa-solid fa-briefcase',
                label = 'Talk about businesses',
                onSelect = function()
                    TriggerEvent('lv_laitonyritys:client:openBusinessBrowser')
                end
            }
        })
    end
end

CreateThread(function()
    Wait(1000)
    if not Config.BusinessNPCs or #Config.BusinessNPCs == 0 then return end

    for i, cfg in ipairs(Config.BusinessNPCs) do
        spawnBusinessNPC(cfg, i)
    end
end)
