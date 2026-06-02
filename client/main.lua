local myAliases = {}
local maskedPlayers = {}
local hiddenPlayers = {}

local colorTags = {
    ['*r*'] = {255, 50,  50,  255},
    ['*g*'] = {50,  255, 50,  255},
    ['*b*'] = {50,  150, 255, 255},
    ['*y*'] = {255, 255, 0,   255},
    ['*o*'] = {255, 165, 0,   255},
    ['*w*'] = {255, 255, 255, 255},
    ['*p*'] = {180, 50,  255, 255},
}

local defaultColor = {255, 255, 255, 230}

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('rp_alias:server:requestMaskState')
end)

RegisterNetEvent('rp_alias:client:receiveMaskState', function(state)
    maskedPlayers = state
end)

RegisterNetEvent('rp_alias:client:playerMaskChanged', function(serverId, isMasked)
    maskedPlayers[serverId] = isMasked
end)

RegisterNetEvent('rp_alias:client:removeMaskState', function(serverId)
    maskedPlayers[serverId] = nil
    hiddenPlayers[serverId] = nil
end)

RegisterNetEvent('rp_alias:client:receiveAliases', function(aliases)
    myAliases = aliases or {}
end)

RegisterNetEvent('rp_alias:client:notify', function(message)
    lib.notify({
        title = 'Alias',
        description = message,
        type = 'inform',
        duration = 4000,
    })
end)

AddEventHandler('rp_alias:client:setHidden', function(serverId, hidden)
    hiddenPlayers[serverId] = hidden
end)

local lastMaskDrawable = -1

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local drawable = GetPedDrawableVariation(ped, Config.MaskComponent)
        if drawable ~= lastMaskDrawable then
            lastMaskDrawable = drawable
            local isMasked = (drawable ~= Config.UnmaskedDrawable)
            TriggerServerEvent('rp_alias:server:setMasked', isMasked)
        end
    end
end)

local function parseColor(alias)
    for tag, color in pairs(colorTags) do
        if string.sub(alias, 1, #tag) == tag then
            local name = string.sub(alias, #tag + 1)
            return color, name
        end
    end
    return defaultColor, alias
end

local function drawLabel(x, y, z, text, color, dist)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    screenY = screenY - 0.03

    -- Compensate for distance so text appears same size at all ranges
    local scale = Config.TextScale * (dist / Config.DrawDistance) * 2.5
    if scale < 0.15 then scale = 0.15 end
    if scale > Config.TextScale then scale = Config.TextScale end

    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

local function buildLabel(serverId)
    if myAliases[serverId] then
        local color, name = parseColor(myAliases[serverId])
        return ("[%d] %s"):format(serverId, name), color
    end
    if maskedPlayers[serverId] then
        return ("[%d] %s"):format(serverId, Config.MaskedPrefix), defaultColor
    end
    return ("[%d] %s"):format(serverId, Config.DefaultLabel), defaultColor
end

local function isNoclipping(ped)
    if not IsEntityVisible(ped) then return true end
    if not DoesEntityHavePhysics(ped) then return true end
    return false
end

CreateThread(function()
    while true do
        Wait(0)
        local myPed = PlayerPedId()
        local myPos = GetEntityCoords(myPed)
        for _, playerHandle in ipairs(GetActivePlayers()) do
            if playerHandle ~= PlayerId() then
                local ped = GetPlayerPed(playerHandle)
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local serverId = GetPlayerServerId(playerHandle)
                    if not hiddenPlayers[serverId] and not isNoclipping(ped) then
                        local pos = GetEntityCoords(ped)
                        local dist = #(myPos - pos)
                        if dist <= Config.DrawDistance then
                            local bx, by, bz = table.unpack(GetPedBoneCoords(ped, 12844, 0.0, 0.0, 0.0))
                            local label, color = buildLabel(serverId)
                            drawLabel(bx, by, bz + 0.45, label, color, dist)
                        end
                    end
                end
            end
        end
    end
end)
