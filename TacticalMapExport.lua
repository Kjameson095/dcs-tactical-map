--Moving Map

local socket = require("socket")
local udpSender
local host = "127.0.0.1"
local port = 50000

local Map_AITracker = {} 

-- 1. Chain the Start Function
local Map_PrevLuaExportStart = LuaExportStart
LuaExportStart = function()
    if Map_PrevLuaExportStart then
        Map_PrevLuaExportStart()
    end
    
    udpSender = socket.udp()
    udpSender:setpeername(host, port)
    Map_AITracker = {} 
end

-- 2. Chain the Stop Function
local Map_PrevLuaExportStop = LuaExportStop
LuaExportStop = function()
    if Map_PrevLuaExportStop then
        Map_PrevLuaExportStop()
    end
    
    if udpSender then
        udpSender:close()
    end
end

-- 3. Chain the Loop Function
local Map_PrevLuaExportActivityNextEvent = LuaExportActivityNextEvent
LuaExportActivityNextEvent = function(t)
    local tNext = t + 0.1 
    local jsonParts = {}
    
    local selfData = LoGetSelfData()
    local myName = ""
    
    -- EXTRACT SELF DATA
    if selfData then
        myName = selfData.UnitName or ""
        local myCoalitionID = selfData.CoalitionID or 0
        local myCoalStr = "Neutral"
        
        if myCoalitionID == 1 then myCoalStr = "Red"
        elseif myCoalitionID == 2 then myCoalStr = "Blue" end
        
        if selfData.LatLongAlt then
            local lat = selfData.LatLongAlt.Lat
            local lon = selfData.LatLongAlt.Long
            local alt = selfData.LatLongAlt.Alt
            local speed = LoGetTrueAirSpeed() or 0
            
            local modelName = selfData.Name or "Unknown"
            local callsign = selfData.UnitName or "Player"
            
            local unitJson = string.format(
                '{"id":-1, "lat":%f, "lon":%f, "alt":%f, "speed":%f, "hdg":%f, "name":"%s", "model":"%s", "cat":1, "coalition":"%s", "isSelf":true, "player":"Local Player"}', 
                lat, lon, alt, speed, selfData.Heading, callsign, modelName, myCoalStr
            )
            table.insert(jsonParts, unitJson)
        end
    end

    -- EXTRACT MISSION WAYPOINTS (Aggressive Dragnet)
    local routePoints = {}
    pcall(function()
        local routeData = LoGetRoute()
        if routeData then
            local wpTable = routeData.route or routeData
            local wpDict = {}
            local keys = {}
            for k, wp in pairs(wpTable) do
                if type(wp) == "table" then
                    local idx = wp.this_point_num or k
                    local px, pz, py = nil, nil, 0
                    
                    -- DCS uses several undocumented formats depending on the module/era
                    if wp.world_point and type(wp.world_point.x) == "number" then
                        px, pz, py = wp.world_point.x, wp.world_point.z, wp.world_point.y
                    elseif wp.point and type(wp.point.x) == "number" then
                        px, pz, py = wp.point.x, wp.point.z, wp.point.y
                    elseif type(wp.x) == "number" then
                        px = wp.x
                        pz = wp.y -- DCS 2D map vectors often map East/West to Y
                        py = wp.z or 0
                    end
                    
                    if px and pz and not wpDict[idx] then
                        wpDict[idx] = {x = px, z = pz, y = py}
                        table.insert(keys, idx)
                    end
                end
            end
            table.sort(keys)

            for _, idx in ipairs(keys) do
                local p = wpDict[idx]
                local lat, lon = 0, 0
                local val1, val2 = LoLoCoordinatesToGeoCoordinates(p.x, p.z)
                if type(val1) == "table" then
                    lat = val1.latitude or val1.lat or 0
                    lon = val1.longitude or val1.long or val1.lon or 0
                else
                    lat = val1 or 0
                    lon = val2 or 0
                end
                table.insert(routePoints, string.format('{"wp_num":%d, "lat":%f, "lon":%f, "alt":%f}', idx, lat, lon, p.y or 0))
            end
        end
    end)

    -- FALLBACK: If the full route is hidden, force the active Nav/Steerpoint
    if #routePoints == 0 then
        pcall(function()
            local navPt = LoGetNavigationPosition()
            if type(navPt) == "table" then
                -- Sometimes it returns pure lat/long directly
                if type(navPt.latitude) == "number" and type(navPt.longitude) == "number" then
                    table.insert(routePoints, string.format('{"wp_num":1, "lat":%f, "lon":%f, "alt":%f}', navPt.latitude, navPt.longitude, navPt.altitude or 0))
                
                -- Sometimes it returns the standard DCS grid matrix
                elseif type(navPt.x) == "number" and type(navPt.z) == "number" then
                    local lat, lon = 0, 0
                    local val1, val2 = LoLoCoordinatesToGeoCoordinates(navPt.x, navPt.z)
                    if type(val1) == "table" then
                        lat = val1.latitude or val1.lat or 0
                        lon = val1.longitude or val1.long or val1.lon or 0
                    else
                        lat = val1 or 0
                        lon = val2 or 0
                    end
                    table.insert(routePoints, string.format('{"wp_num":1, "lat":%f, "lon":%f, "alt":%f}', lat, lon, navPt.y or 0))
                end
            end
        end)
    end
    
    local routeJson = string.format('{"id":-2, "cat":100, "points":[%s]}', table.concat(routePoints, ","))
    table.insert(jsonParts, routeJson)
    
    -- EXTRACT WINGMEN, ENEMIES, FARPS & GROUND UNITS
    local objects = LoGetWorldObjects()
    if objects then
        for id, obj in pairs(objects) do
            pcall(function()
                local isMe = (obj.UnitName == myName) or (obj.Name == myName)
                local modelName = obj.Name or "Unknown"
                local upperModel = string.upper(modelName)
                
                local isFARP = false
                if upperModel == "FARP" or upperModel == "INVISIBLE FARP" or string.find(upperModel, "HELIPAD") then
                    isFARP = true
                end
                
                local isLiveAircraft = obj.Type and (obj.Type.level1 == 1) and obj.UnitName
                local isGroundUnit = obj.Type and (obj.Type.level1 == 2 or obj.Type.level1 == 3) and obj.UnitName
                
                if not isMe and (isLiveAircraft or isFARP or isGroundUnit) then
                    
                    local unitCoalStr = "Neutral"
                    if obj.CoalitionID == 1 or obj.Coalition == "Red" or obj.Coalition == "red" then 
                        unitCoalStr = "Red" 
                    elseif obj.CoalitionID == 2 or obj.Coalition == "Blue" or obj.Coalition == "blue" then 
                        unitCoalStr = "Blue" 
                    end
                    
                    local x, y, z = nil, nil, nil
                    
                    if obj.Position then
                        if obj.Position.p and type(obj.Position.p.x) == "number" then
                            x, y, z = obj.Position.p.x, obj.Position.p.y, obj.Position.p.z
                        elseif type(obj.Position.x) == "number" then
                            x, y, z = obj.Position.x, obj.Position.y, obj.Position.z
                        end
                    end
                    
                    if x and z then
                        local lat, lon = 0, 0
                        local val1, val2 = LoLoCoordinatesToGeoCoordinates(x, z)
                        
                        if type(val1) == "table" then
                            lat = val1.latitude or val1.lat or 0
                            lon = val1.longitude or val1.long or val1.lon or 0
                        else
                            lat = val1 or 0
                            lon = val2 or 0
                        end
                        
                        local alt = y or 0
                        local speed = 0
                        
                        if not isFARP then
                            if Map_AITracker[id] then
                                local prev = Map_AITracker[id]
                                local dt = t - prev.t
                                if dt > 0 then
                                    local dx = x - prev.x
                                    local dy = y - prev.y
                                    local dz = z - prev.z
                                    local dist = math.sqrt(dx^2 + dy^2 + dz^2)
                                    speed = dist / dt 
                                end
                            end
                            Map_AITracker[id] = {x = x, y = y, z = z, t = t}
                        end

                        local callsign = obj.UnitName or "Unknown"
                        
                        local cat = 1
                        
                        if isLiveAircraft then
                            if obj.Type.level2 == 2 then cat = 2 else cat = 1 end
                        elseif isFARP then 
                            cat = 3 
                        elseif obj.Type.level1 == 3 then
                            cat = 7 -- Ships
                        elseif obj.Type.level1 == 2 then
                            if obj.Type.level2 == 1 then
                                cat = 5 -- SAM / Air Defense
                            elseif obj.Type.level2 == 4 then
                                cat = 6 -- Truck / Unarmed Transport
                            else
                                cat = 4 -- Armor / Artillery / Default
                            end
                        end
                        
                        local playerName = "AI"
                        if obj.PlayerName then
                            playerName = string.gsub(obj.PlayerName, '"', "'")
                        end

                        if lat ~= 0 and lon ~= 0 then
                            local unitJson = string.format(
                                '{"id":%d, "lat":%f, "lon":%f, "alt":%f, "speed":%f, "hdg":%f, "name":"%s", "model":"%s", "cat":%d, "coalition":"%s", "isSelf":false, "player":"%s"}', 
                                id, lat, lon, alt, speed, obj.Heading or 0, callsign, modelName, cat, unitCoalStr, playerName
                            )
                            table.insert(jsonParts, unitJson)
                        end
                    end
                end
            end)
        end
    end
    
    local dataStr = "[" .. table.concat(jsonParts, ",") .. "]"
    
    if udpSender then
        udpSender:send(dataStr)
    end
    
    if Map_PrevLuaExportActivityNextEvent then
        local prevTNext = Map_PrevLuaExportActivityNextEvent(t)
        if prevTNext and prevTNext < tNext then
            tNext = prevTNext
        end
    end
    
    return tNext
end