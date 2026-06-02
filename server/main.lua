local aliasCache = {}
local identifierToServerId = {}
local serverIdToIdentifier = {}
local maskState = {}

exports.oxmysql:query([[
    CREATE TABLE IF NOT EXISTS `player_aliases` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner_identifier` VARCHAR(255) NOT NULL,
        `target_identifier` VARCHAR(255) NOT NULL,
        `alias` VARCHAR(64) NOT NULL,
        UNIQUE KEY `unique_alias` (`owner_identifier`, `target_identifier`)
    )
]], {})

local function getIdentifier(serverId)
    local player = exports.ox_core:GetPlayer(serverId)
    if player and player.identifier then
        return player.identifier
    end
    for _, id in ipairs(GetPlayerIdentifiers(serverId)) do
        if string.sub(id, 1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

local function buildClientAliasTable(ownerIdentifier)
    local result = {}
    local aliases = aliasCache[ownerIdentifier] or {}
    for targetIdentifier, nickname in pairs(aliases) do
        local targetServerId = identifierToServerId[targetIdentifier]
        if targetServerId then
            result[targetServerId] = nickname
        end
    end
    return result
end

local function pushAliasesToClient(ownerServerId)
    local ownerIdentifier = serverIdToIdentifier[ownerServerId]
    if not ownerIdentifier then return end
    local clientAliases = buildClientAliasTable(ownerIdentifier)
    TriggerClientEvent('rp_alias:client:receiveAliases', ownerServerId, clientAliases)
end

local function loadAliasesForPlayer(serverId)
    local ownerIdentifier = serverIdToIdentifier[serverId]
    if not ownerIdentifier then return end
    exports.oxmysql:query('SELECT target_identifier, alias FROM player_aliases WHERE owner_identifier = @owner', {
        ['@owner'] = ownerIdentifier
    }, function(rows)
        aliasCache[ownerIdentifier] = {}
        for _, row in ipairs(rows) do
            aliasCache[ownerIdentifier][row.target_identifier] = row.alias
        end
        local clientAliases = buildClientAliasTable(ownerIdentifier)
        TriggerClientEvent('rp_alias:client:receiveAliases', serverId, clientAliases)
    end)
end

local function registerPlayer(src)
    local identifier = getIdentifier(src)
    if not identifier then
        print('[rp_alias] Could not get identifier for player ' .. tostring(src))
        return
    end
    print('[rp_alias] Registered: ' .. tostring(src) .. ' = ' .. identifier)
    identifierToServerId[identifier] = src
    serverIdToIdentifier[src] = identifier
    for otherServerId, _ in pairs(serverIdToIdentifier) do
        if otherServerId ~= src then
            pushAliasesToClient(otherServerId)
        end
    end
    loadAliasesForPlayer(src)
end

AddEventHandler('ox:playerLoaded', function(source, player)
    registerPlayer(source)
end)

AddEventHandler('playerSpawned', function()
    local src = source
    SetTimeout(2000, function()
        if not serverIdToIdentifier[src] then
            registerPlayer(src)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = serverIdToIdentifier[src]
    if identifier then
        identifierToServerId[identifier] = nil
    end
    serverIdToIdentifier[src] = nil
    maskState[src] = nil
    TriggerClientEvent('rp_alias:client:removeMaskState', -1, src)
end)

RegisterNetEvent('rp_alias:server:requestMaskState', function()
    local src = source
    TriggerClientEvent('rp_alias:client:receiveMaskState', src, maskState)
end)

RegisterNetEvent('rp_alias:server:setMasked', function(isMasked)
    local src = source
    maskState[src] = isMasked
    TriggerClientEvent('rp_alias:client:playerMaskChanged', -1, src, isMasked)
end)

RegisterCommand('alias', function(source, args)
    local src = source
    if #args < 2 then
        TriggerClientEvent('rp_alias:client:notify', src, "Usage: /alias [player id] [nickname]")
        return
    end
    local targetServerId = tonumber(args[1])
    if not targetServerId then
        TriggerClientEvent('rp_alias:client:notify', src, "Invalid ID — use a number.")
        return
    end
    if not GetPlayerName(targetServerId) then
        TriggerClientEvent('rp_alias:client:notify', src, "That player is not online.")
        return
    end
    if targetServerId == src then
        TriggerClientEvent('rp_alias:client:notify', src, "You cannot alias yourself.")
        return
    end
    if not serverIdToIdentifier[src] then registerPlayer(src) end
    if not serverIdToIdentifier[targetServerId] then registerPlayer(targetServerId) end
    local ownerIdentifier = serverIdToIdentifier[src]
    local targetIdentifier = serverIdToIdentifier[targetServerId]
    if not ownerIdentifier or not targetIdentifier then
        TriggerClientEvent('rp_alias:client:notify', src, "Could not resolve identifiers. Try again in a moment.")
        return
    end
    local nickname = table.concat(args, " ", 2)
    if #nickname > 32 then nickname = string.sub(nickname, 1, 32) end
    if not aliasCache[ownerIdentifier] then aliasCache[ownerIdentifier] = {} end
    aliasCache[ownerIdentifier][targetIdentifier] = nickname
    exports.oxmysql:query([[
        INSERT INTO player_aliases (owner_identifier, target_identifier, alias)
        VALUES (@owner, @target, @alias)
        ON DUPLICATE KEY UPDATE alias = @alias
    ]], {
        ['@owner'] = ownerIdentifier,
        ['@target'] = targetIdentifier,
        ['@alias'] = nickname,
    })
    pushAliasesToClient(src)
    TriggerClientEvent('rp_alias:client:notify', src, ("Alias set: [%d] → %s"):format(targetServerId, nickname))
end, false)

RegisterCommand('clearalias', function(source, args)
    local src = source
    if #args < 1 then
        TriggerClientEvent('rp_alias:client:notify', src, "Usage: /clearalias [player id]")
        return
    end
    local targetServerId = tonumber(args[1])
    if not targetServerId then
        TriggerClientEvent('rp_alias:client:notify', src, "Invalid ID — use a number.")
        return
    end
    if not serverIdToIdentifier[src] then registerPlayer(src) end
    if not serverIdToIdentifier[targetServerId] then registerPlayer(targetServerId) end
    local ownerIdentifier = serverIdToIdentifier[src]
    local targetIdentifier = serverIdToIdentifier[targetServerId]
    if not ownerIdentifier or not targetIdentifier then
        TriggerClientEvent('rp_alias:client:notify', src, "Could not resolve identifiers.")
        return
    end
    if not aliasCache[ownerIdentifier] or not aliasCache[ownerIdentifier][targetIdentifier] then
        TriggerClientEvent('rp_alias:client:notify', src, "You have no alias set for that player.")
        return
    end
    local oldName = aliasCache[ownerIdentifier][targetIdentifier]
    aliasCache[ownerIdentifier][targetIdentifier] = nil
    exports.oxmysql:query('DELETE FROM player_aliases WHERE owner_identifier = @owner AND target_identifier = @target', {
        ['@owner'] = ownerIdentifier,
        ['@target'] = targetIdentifier,
    })
    pushAliasesToClient(src)
    TriggerClientEvent('rp_alias:client:notify', src, ("Alias cleared for [%d] (was: %s)"):format(targetServerId, oldName))
end, false)
