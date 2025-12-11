-- server/production.lua

local function tickProduction()
    for businessId, data in pairs(Businesses) do
        if data.owner_identifier and data.is_shut_down == 0 then
            local loc, typeCfg = getBusinessTypeCfg(businessId)
            if loc and typeCfg then
                local supplies = data.supplies or 0
                local product  = data.product or 0

                if supplies > 0 then
                    local baseConsume = Config.Production.BaseSuppliesPerTick
                    local baseProduct = Config.Production.BaseProductPerTick

                    local employeeMult = 1.0
                        + (data.employees_level or 0) * (Config.Production.EmployeeBonusPerLevel or 0.25)

                    local consume = math.floor(baseConsume * employeeMult)
                    local produce = math.floor(baseProduct * employeeMult)

                    if consume > supplies then
                        consume = supplies
                    end

                    supplies = supplies - consume
                    product  = product + produce

                    if product > typeCfg.maxProduct then
                        product = typeCfg.maxProduct
                    end

                    data.supplies = supplies
                    data.product  = product

                    saveBusiness(businessId)
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.Production.BaseTickMinutes * 60000)
        tickProduction()
    end
end)
