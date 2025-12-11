-- server/raids.lua

local function getOnlinePoliceCount()
    local count = 0
    for _, src in ipairs(GetPlayers()) do
        if Config.Framework == 'esx' and ESX then
            local xPlayer = ESX.GetPlayerFromId(src)
            if xPlayer then
                local jobName = xPlayer.job and xPlayer.job.name
                for _, j in ipairs(Config.Raids.PoliceJobs) do
                    if jobName == j then
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    return count
end

local function performRaidCheck()
    if not Config.Raids.Enabled then return end
    if Config.Raids.RequireOnDutyPolice and getOnlinePoliceCount() < Config.Raids.MinPolice then
        return
    end

    for businessId, data in pairs(Businesses) do
        if data.owner_identifier and data.is_shut_down == 0 then
            local chance = Config.Raids.BaseRaidChance - (data.security_level or 0) * Config.Raids.SecurityReductionPerLevel
            if chance < 0.0 then chance = 0.0 end
            if math.random() < chance then
                data.is_shut_down = 1
                saveBusiness(businessId)

                sendRaidDispatch(businessId)
                discordLog('Business Raided', ('Business %s (%s) owned by %s was raided.')
                    :format(
                        businessId,
                        (Config.Locations[businessId] and Config.Locations[businessId].label) or 'Unknown',
                        data.owner_name or 'Unknown'
                    )
                )

                for _, src in ipairs(GetPlayers()) do
                    local identifier = select(1, getIdentifier(src))
                    if identifier == data.owner_identifier then
                        TriggerClientEvent('chat:addMessage', src, {
                            args = {
                                '^1Business',
                                'Your illegal business has been raided and shut down. Complete the setup mission to reopen it.'
                            }
                        })
                    end
                end

                TriggerClientEvent('lv_laitonyritys:client:raidCamera', -1, businessId)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.Raids.CheckIntervalMinutes * 60000)
        performRaidCheck()
    end
end)
