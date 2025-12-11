local SpawnedProductionProps = {} -- [businessId] = { stage = n, objs = {entity, ...} }
Config.EmployeePeds = Config.EmployeePeds or {}

local ProductionProps = {
    meth = {
        stages = {
            -- STAGE 1
            [1] = {
                -- main bag stack
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3197.851, -39.908), rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3198.783, -39.898), rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3199.850, -39.898), rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3200.809, -39.898), rot = vec3(0.0, 0.0, 91.439) },

                -- new table setup
                { model = 'bkr_prop_meth_bigbag_04a', coords = vec3(1014.280, -3194.100, -39.196), rot = vec3(0.0, 0.0, -90.421) },
                { model = 'bkr_prop_meth_tray_02a', coords = vec3(1011.322, -3194.185, -39.196), rot = vec3(0.0, 0.0, 0.0) },
                { model = 'bkr_prop_coke_scale_01', coords = vec3(1013.534, -3194.164, -39.196), rot = vec3(0.0, 0.0, 0.0) },
                { model = 'bkr_prop_meth_openbag_01a', coords = vec3(1013.534, -3194.111, -39.106), rot = vec3(0.0, 0.0, 0.0) },
                { model = 'bkr_prop_meth_smashedtray_01_frag_', coords = vec3(1012.072, -3194.168, -39.196), rot = vec3(0.0, 0.0, 0.891) },
                { model = 'bkr_prop_meth_bigbag_03a', coords = vec3(1012.805, -3194.111, -39.196), rot = vec3(0.0, 0.0, 92.661) },
            },

            -- STAGE 2 (adds on top of Stage 1)
            [2] = {
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3200.852, -39.297),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3197.831, -39.297),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3198.763, -39.297),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3199.943, -39.297),  rot = vec3(0.0, 0.0, 91.439) },
            },

            -- STAGE 3 (adds on top of Stage 1–2)
            [3] = {
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3197.831, -38.697),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3200.831, -38.697),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3198.769, -38.697),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3199.896, -38.697),  rot = vec3(0.0, 0.0, 91.439) },
            },

            -- STAGE 4 (adds on top of Stage 1–3)
            [4] = {
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3200.854, -37.494),  rot = vec3(0.0, 0.0, 91.4)   },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3198.782, -37.494),  rot = vec3(0.0, 0.0, 91.4)   },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3199.927, -37.494),  rot = vec3(0.0, 0.0, 91.4)   },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3197.831, -37.494),  rot = vec3(0.0, 0.0, 91.439) },

                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3197.831, -38.095),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3198.782, -38.095),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3199.927, -38.095),  rot = vec3(0.0, 0.0, 91.439) },
                { model = 'bkr_prop_meth_bigbag_01a', coords = vec3(1017.963, -3200.854, -38.095),  rot = vec3(0.0, 0.0, 91.439) },
            },
        }
    }
}

Config.EmployeePeds['meth'] = {
    -- How many employees we show per employees_level
    employeesPerLevel = {
        [0] = 0,
        [1] = 1,
        [2] = 3,
        [3] = 5,   -- last upgrade adds +2
    },

    -- Slots are used in order
    slots = {
        {
            -- vec4(1012.09, -3194.86, -38.99, 5.07)
            model = 'MP_F_Meth_01',
            coords = vec4(1012.09, -3194.86, -38.99, 5.07),
            animDict = 'anim@amb@business@meth@meth_smash_weight_check@',
            animName = 'break_weigh_v3_hammer',
        },
        {
            -- vec4(1013.55, -3194.90, -38.99, 1.75)
            model = 'MP_F_Meth_01',
            coords = vec4(1013.55, -3194.90, -38.99, 1.75),
            animDict = 'anim@amb@business@meth@meth_smash_weight_check@',
            animName = 'break_weigh_v1_char01',
        },
        {
            -- vec4(1011.54, -3200.35, -38.99, 2.50)
            model = 'MP_F_Meth_01',
            coords = vec4(1011.54, -3200.35, -38.99, 2.50),
            animDict = 'anim@amb@business@meth@meth_monitoring_cooking@monitoring@',
            animName = 'button_press_monitor',
        },
        {
            -- vec4(1005.72, -3200.27, -38.52, 181.79)
            model = 'MP_F_Meth_01',
            coords = vec4(1005.72, -3200.27, -38.52, 181.79),
            animDict = 'anim@amb@business@meth@meth_monitoring_cooking@cooking@',
            animName = 'chemical_pour_long_cooker',
        },
        {
            -- vec4(1016.69, -3195.95, -38.99, 273.52)
            -- Random clipboard-style idle
            model = 'MP_F_Meth_01',
            coords = vec4(1016.69, -3195.95, -38.99, 273.52),
            animDict = 'missheistdockssetup1clipboard@base',
            animName = 'base',
        },
    },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getStageForProduct(product, maxProduct)
    product    = tonumber(product) or 0
    maxProduct = tonumber(maxProduct) or 0
    if maxProduct <= 0 then return 0 end

    local pct = (product / maxProduct) * 100.0

    -- 0–24%  = stage 0 (no props)
    -- 25–49% = stage 1
    -- 50–74% = stage 2
    -- 75–99% = stage 3
    -- 100%   = stage 4
    if pct >= 100.0 then
        return 4
    elseif pct >= 75.0 then
        return 3
    elseif pct >= 50.0 then
        return 2
    elseif pct >= 25.0 then
        return 1
    end

    return 0
end

local function loadModelBlocking(model)
    if type(model) == 'string' then
        model = joaat(model)
    end
    if not IsModelValid(model) then return false end

    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(0)
        end
    end
    return true
end

local function clearPropsForBusiness(businessId)
    local entry = SpawnedProductionProps[businessId]
    if not entry then return end

    for _, obj in ipairs(entry.objs) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end

    SpawnedProductionProps[businessId] = nil
end

local function spawnPropsForStage(businessId, businessType, stage)
    clearPropsForBusiness(businessId)

    local cfg = ProductionProps[businessType]
    if not cfg or stage <= 0 then
        return
    end

    local spawned = {}

    -- We want cumulative props: stage1 + stage2 + ... currentStage
    for s = 1, stage do
        local stageData = cfg.stages[s]
        if stageData then
            for _, prop in ipairs(stageData) do
                local model = prop.model
                if loadModelBlocking(model) then
                    local mhash = (type(model) == 'string') and joaat(model) or model
                    local c = prop.coords
                    local r = prop.rot or vec3(0.0, 0.0, 0.0)

                    local obj = CreateObject(mhash, c.x, c.y, c.z, false, false, false)
                    if obj ~= 0 then
                        SetEntityRotation(obj, r.x, r.y, r.z, 2, true)
                        FreezeEntityPosition(obj, true)
                        table.insert(spawned, obj)
                    end
                end
            end
        end
    end

    SpawnedProductionProps[businessId] = {
        stage = stage,
        objs  = spawned
    }
end

----------------------------------------------------------------------
-- PUBLIC API (call these from your main client script)
----------------------------------------------------------------------

-- data is the table from buildBusinessData on the server
function UpdateProductionProps(businessId, data)
    if not data or not businessId then
        if businessId then
            clearPropsForBusiness(businessId)
        end
        return
    end

    local businessType = data.type -- 'meth', 'coke', etc (from loc.type)
    if not businessType then return end

    local stage = getStageForProduct(data.product or 0, data.maxProduct or 0)
    local current = SpawnedProductionProps[businessId] and SpawnedProductionProps[businessId].stage or -1

    if stage == current then
        return
    end

    spawnPropsForStage(businessId, businessType, stage)
end

-- Call when leaving the interior
function ClearProductionProps(businessId)
    if businessId then
        clearPropsForBusiness(businessId)
    else
        -- fallback: clear all
        for id, _ in pairs(SpawnedProductionProps) do
            clearPropsForBusiness(id)
        end
    end
end

-- client/production_props.lua

RegisterNetEvent('lv_laitonyritys:client:clearProductionProps', function(businessId)
    ClearProductionProps(businessId)
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearProductionProps(nil)
end)