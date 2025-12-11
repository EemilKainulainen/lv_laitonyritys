-- shared/utils.lua

Utils = {}

function Utils.Log(msg, ...)
    if Config.Debug then
        print(('[lv_laitonyritys] %s'):format(msg:format(...)))
    end
end

local charset = {}
for i = 48, 57 do table.insert(charset, string.char(i)) end
for i = 65, 90 do table.insert(charset, string.char(i)) end
for i = 97, 122 do table.insert(charset, string.char(i)) end

function Utils.RandomToken(len)
    len = len or Config.MissionTokenLength or 16
    local s = {}
    for i = 1, len do
        s[#s+1] = charset[math.random(1, #charset)]
    end
    return table.concat(s)
end

function Utils.GetBusinessTypeConfig(businessType)
    return Config.BusinessTypes[businessType]
end