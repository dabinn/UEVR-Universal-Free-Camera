-- File:    ds-uevr-universal-freecam.lua
-- Brief:   DS UEVR Universal Free Camera plugin
-- Details: This plugin provides a universal free camera functionality for UEVR, 
--          allowing users to freely navigate and explore VR environments. It can 
--          be used as a standalone universal plugin or customized with specific 
--          parameters for other game plugins.
-- License: MIT
-- Version: 1.0.1
-- Date:    2025/02/15
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

-- Initialize the library and global variables
print("---------- ds-uevr-universal-freecam init ----------")
local uId ="DS-Univ-FreeCam" -- Unique ID for this plugin
local lib=require("ds-uevr/libcommon")
local te=TofuExpress

local function uprint(...)
    lib.uprint(uId, ...)
end

-- load  freecam
if not te.freecam then -- Check if freecam lib already loaded by another plugin
    uprint("Universal Free Camera")
else
    uprint("Custom Free Camera already loaded")
    return
end

local freecam = require("ds-uevr/libfreecam")
local cfg=freecam.extCfg

-- Available button codes:
-- A, B, X, Y 
-- LB, RB, L3, R3 (LT, RT are not implemented yet)
-- DPadUp, DPadDown, DPadLeft, DPadRight
-- Back, Start
-- To specify a button combination, use the "+" symbol. For example: "Select+Y"
-- To specify a special event (pressed, held, released, doubleclick), use these words separated by `_` with the button name.
-- For example: `L3_held`, `Select_pressed` 
-- Default event is "released" if not specified.
cfg.buttons = {
    active = "L3_held",
    deactive = "L3",
    resetCam = "R3",
    speedIncrease = "RB",
    speedDecrease = "LB",
}

-- Speed Settings
cfg.spd={}
cfg.spd[1] = {
    speedTotalStep = 10,
    move_speed_max = 50000, -- cm per second
    move_speed_min = 50,
    rotate_speed_max = 180, -- degrees per second
    rotate_speed_min = 90, -- degrees per second
    currMoveStep = 5,
    currRotStep = 5
}

-- Freecam Parameters
cfg.opt={
    enableGuiToggle = false, -- Disable game GUI when free camera is enabled
    freecamFollowPosition = true, -- Follows game camera's position in free camera mode, or the object may run away from the camera.
    freecamFollowRotation = false, -- It feels less `free` when following the rotation of the game camera.
    freecamKeepPosition = false,  -- Don't reset the free camera's position while switching cameras.
    levelFlight = true, -- The vertical orientation of the camera does not affect the flight altitude.
    cam_invert_pitch = false,
    recenterVROnCameraReset = true, -- Reset the camera and recenter VR at the same time
}

freecam.init()
