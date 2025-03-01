

-- File:    libevents.lua
-- Brief:   DS UEVR event manager system
-- Details: Just a simple event manager system for DS UEVR
-- License: MIT
-- Version: 1.0.0
-- Date:    2025/02/15
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

local events = {}
events.eventTable = {}

-- helper function: get a single event
local function getEvent(name)
    if not events.eventTable[name] then
        events.eventTable[name] = {}
        events.eventTable[name].listeners = {}
    end
    return events.eventTable[name]
end

-- event on/register/subscribe/addListener..
function events:on(name, listener)
    local listeners = getEvent(name).listeners
    table.insert(listeners, listener)
end

-- event off/unregister/unsubscribe/removeListener...
function events:off(name, listener)
    local listeners = getEvent(name).listeners
    for i, l in ipairs(listeners) do
        if l == listener then
            table.remove(listeners, i)
            break
        end
    end
end

-- event emit/trigger/dispatch/fire...
function events:emit(name, ...)
    local listeners = getEvent(name).listeners
    for _, listener in ipairs(listeners) do
        listener(...)
    end
end

return events

-- Usage example:
--[[
local events = require("libevents")

-- Define listener functions
local function doSomeFunc1()
    print("doSomeFunc1 called")
end

local function doSomeFunc2()
    print("doSomeFunc2 called")
end

-- Register the listeners for the 'on_paused_changed' event
events:on('on_paused_changed', doSomeFunc1)
events:on('on_paused_changed', doSomeFunc2)

-- Register an anonymous function for the 'on_paused_changed' event
events:on('on_paused_changed', function(x, y, z)
    print("Anonymous function called with args:", x, y, z)
end)

-- Emit the 'on_paused_changed' event with arguments
events:emit('on_paused_changed', 1, 2, 3)

-- Unregister the 'doSomeFunc1' listener
events:off('on_paused_changed', doSomeFunc1)
]]