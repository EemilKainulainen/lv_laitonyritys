-- server/routing.lua

RegisterNetEvent('lv_laitonyritys:server:setInsideBusiness', function(businessId, inside)
    local src = source

    if inside then
        if not businessId then return end

        if PlayerOriginalBuckets[src] == nil then
            PlayerOriginalBuckets[src] = GetPlayerRoutingBucket(src) or 0
        end

        local bucket = BusinessBuckets[businessId]
        if not bucket then
            BusinessBucketSeed = BusinessBucketSeed + 1
            bucket = BusinessBucketSeed
            BusinessBuckets[businessId] = bucket
        end

        PlayersInBusiness[src] = businessId
        SetPlayerRoutingBucket(src, bucket)
    else
        local original = PlayerOriginalBuckets[src] or 0
        SetPlayerRoutingBucket(src, original)
        PlayerOriginalBuckets[src] = nil

        local biz = PlayersInBusiness[src]
        PlayersInBusiness[src] = nil

        -- 👉 tell client to clear props for this business
        if biz then
            TriggerClientEvent('lv_laitonyritys:client:clearProductionProps', src, biz)
        end

        -- Optional cleanup of empty buckets:
        -- if biz then
        --     local stillInside = false
        --     for player, bId in pairs(PlayersInBusiness) do
        --         if bId == biz then
        --             stillInside = true
        --             break
        --         end
        --     end
        --     if not stillInside then
        --         BusinessBuckets[biz] = nil
        --     end
        -- end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    ActiveSetups[src]          = nil
    PlayerOriginalBuckets[src] = nil
    PlayersInBusiness[src]     = nil
end)
