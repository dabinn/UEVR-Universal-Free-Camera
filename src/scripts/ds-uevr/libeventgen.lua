-- File:    libeventgen.lua
-- Brief:   DS UEVR Event Generator Library
-- Details: General event trigger.
-- License: MIT
-- Version: 1.0.0
-- Date:    2025/02/15
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

-- Initialize the library and global variables
print("---------- ds-uver/libeventgen init ----------")
local uId ="DS-EventGen" -- Unique ID for this plugin
local lib=require("ds-uevr/libcommon")
local events = require("ds-uevr/libevents")
local te=TofuExpress

local eventGen={}

local function uprint(...)
    lib.uprint(uId, ...)
end

-- Level detection
local last_world = nil
local last_level = nil
local last_pawn = nil

local function checkLevel()
    
    local game_engine = UEVR_UObjectHook.get_first_object_by_class(lib.game_engine_class)

    local viewport = game_engine.GameViewport
    if viewport == nil then
        uprint("Viewport is nil")
        return
    end
    local world = viewport.World

    if world == nil then
        uprint("World is nil")
        return
    end

    if world ~= last_world then
        last_world = world
    end

    local level = world.PersistentLevel
    if level == nil then
        uprint("Level is nil")
        return
    end

    if level ~= last_level then
        uprint("*** Level changed *** ")
        events:emit("level_changed", level)
        last_level = level
    end


    local pawn = uevr.api:get_local_pawn(0)
    if pawn and pawn ~= last_pawn then
        events:emit("pawn_changed", pawn)
        last_pawn=pawn
    end

end


uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
    if view_index == 1 then
        checkLevel()
    end
end)

return eventGen

