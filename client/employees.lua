-- client/employees.lua

local EmployeePeds = {}  -- [businessId] = { peds... }

local function loadModel(model)
    if type(model) == 'string' then
        model = joaat(model)
    end

    if not IsModelValid(model) then
        return false
    end

    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(10)
        end
    end

    return true
end

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(10)
    end
    return true
end

local function clearEmployees(businessId)
    local list = EmployeePeds[businessId]
    if not list then return end

    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    EmployeePeds[businessId] = nil
end

local function getMaxEmployeesForLevel(businessType, employeesLevel)
    local cfg = Config.EmployeePeds and Config.EmployeePeds[businessType]
    if not cfg then return 0 end

    local map = cfg.employeesPerLevel or {}
    local max = map[employeesLevel]
    if max ~= nil then
        return math.min(max, #(cfg.slots or {}))
    end

    -- fallback: 1 per level
    return math.min(employeesLevel, #(cfg.slots or {}))
end

local function spawnEmployees(businessId, businessType, employeesLevel)
    clearEmployees(businessId)

    local cfg = Config.EmployeePeds and Config.EmployeePeds[businessType]
    if not cfg or not cfg.slots or #cfg.slots == 0 then
        return
    end

    local count = getMaxEmployeesForLevel(businessType, employeesLevel)
    if count <= 0 then return end

    EmployeePeds[businessId] = {}

    for i = 1, count do
        local slot = cfg.slots[i]
        if slot then
            local coords   = slot.coords
            local model    = slot.model
            local animDict = slot.animDict
            local animName = slot.animName

            if loadModel(model) and loadAnimDict(animDict) then
                local ped = CreatePed(
                    4,
                    joaat(model),
                    coords.x, coords.y, coords.z - 1.0,
                    coords.w or 0.0,
                    false, true
                )

                -- Basic setup
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedCanRagdollFromPlayerImpact(ped, false)
                SetPedCanRagdoll(ped, false)
                FreezeEntityPosition(ped, true)

                -- 🔒 Make them non-interactive + unkillable
                SetEntityInvincible(ped, true)

                -- Full damage proofs: no bullets / melee / explosions / fire etc.
                -- SetEntityProofs(entity, bulletProof, fireProof, explosionProof, collisionProof, meleeProof, p7, drownProof, p9)
                SetEntityProofs(ped, true, true, true, true, true, true, true, true)

                -- Can't be targeted or locked onto
                SetPedCanBeTargetted(ped, false)

                -- Optional: no collision so players can't shove them around
                -- If you want them to still block movement, comment this line out.
                --SetEntityCollision(ped, false, false)

                -- No weapons / disarming safety
                RemoveAllPedWeapons(ped, true)

                TaskPlayAnim(
                    ped,
                    animDict,
                    animName,
                    8.0, -8.0,
                    -1,
                    1,      -- loop
                    0.0,
                    false, false, false
                )

                table.insert(EmployeePeds[businessId], ped)
            end
        end
    end
end

-- Main entry: call this when you enter/leave an interior or when employees_level changes
RegisterNetEvent('lv_laitonyritys:client:updateEmployeesForBusiness', function(businessId, businessType, employeesLevel, inside)
    if not inside then
        clearEmployees(businessId)
        return
    end

    spawnEmployees(businessId, businessType, employeesLevel or 0)
end)
